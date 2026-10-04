/**
 * Push delivery without SDKs: APNs over HTTP/2 with token (ES256 JWT) auth,
 * and FCM HTTP v1 with a service-account OAuth token. Both are optional —
 * missing env vars mean that platform is skipped (logged once per process).
 *
 * Env:
 *   APNS_KEY_P8   contents of the AuthKey_XXXX.p8 file (PEM; "\n" escapes ok)
 *   APNS_KEY_ID   the key's 10-character id
 *   APNS_TEAM_ID  Apple team id (default 48AMK8N4G5)
 *   APNS_TOPIC    the app's bundle id (default com.pawsitivesync.app)
 *   FCM_SERVICE_ACCOUNT_JSON  the Firebase service-account JSON (raw or base64)
 */
import http2 from "node:http2";
import { createPrivateKey, sign as cryptoSign } from "node:crypto";

const apnsHosts = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};
/** Apple rejects tokens older than an hour and throttles refreshes under 20 min. */
const apnsJwtTtlMs = 50 * 60 * 1000;
const sendTimeoutMs = 5000;
const fcmScope = "https://www.googleapis.com/auth/firebase.messaging";

/** APNs answers that mean "this device token will never work again". */
const apnsInvalidReasons = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);
const apnsAuthReasons = new Set(["ExpiredProviderToken", "InvalidProviderToken"]);

const b64url = (value) => Buffer.from(typeof value === "string" ? value : JSON.stringify(value)).toString("base64url");

/** PEM from an env var: tolerates literal "\n" escapes (common in dashboards). */
function pem(value) {
  return typeof value === "string" ? value.replace(/\\n/g, "\n").trim() : "";
}

/**
 * The APNs provider token: ES256 over `header.claims`, signature in the raw
 * r||s (IEEE P1363) form JWTs use, not DER.
 */
export function signApnsJwt({ key, keyId, teamId, nowMs = Date.now() }) {
  const header = { alg: "ES256", kid: keyId };
  const claims = { iss: teamId, iat: Math.floor(nowMs / 1000) };
  const input = `${b64url(header)}.${b64url(claims)}`;
  const signature = cryptoSign("sha256", Buffer.from(input), { key, dsaEncoding: "ieee-p1363" });
  return `${input}.${signature.toString("base64url")}`;
}

/** The OAuth assertion Google exchanges for an FCM access token (RS256). */
export function signGoogleAssertion({ clientEmail, privateKey, tokenUri, nowMs = Date.now() }) {
  const iat = Math.floor(nowMs / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = { iss: clientEmail, scope: fcmScope, aud: tokenUri, iat, exp: iat + 3600 };
  const input = `${b64url(header)}.${b64url(claims)}`;
  const signature = cryptoSign("sha256", Buffer.from(input), privateKey);
  return `${input}.${signature.toString("base64url")}`;
}

function readServiceAccount(raw) {
  if (!raw) return null;
  try {
    const text = raw.trim().startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8");
    const json = JSON.parse(text);
    if (!json.project_id || !json.client_email || !json.private_key) return null;
    return {
      projectId: json.project_id,
      clientEmail: json.client_email,
      privateKey: createPrivateKey(pem(json.private_key)),
      tokenUri: json.token_uri || "https://oauth2.googleapis.com/token",
    };
  } catch {
    return null;
  }
}

/** FCM data values must all be strings. */
function stringData(data) {
  const out = {};
  for (const [key, value] of Object.entries(data ?? {})) {
    out[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return out;
}

/**
 * Creates a sender. Everything external is injectable so tests never touch
 * the network: `connect` (http2.connect), `fetchImpl`, `now`.
 *
 * `send(device, message)` never throws; it resolves to
 * `{ ok, invalid?, reason? }` where `invalid` means "delete this token".
 *  - device:  { platform: "ios"|"android", token: "apns:<hex>"|"fcm:<id>", environment }
 *  - message: { alert?: {title, body}, data?: object, background?: boolean, collapseId? }
 */
export function createPushSender({
  env = process.env,
  connect = http2.connect,
  fetchImpl = (...args) => fetch(...args),
  now = () => Date.now(),
} = {}) {
  let apnsKey = null;
  let apnsKeyError = false;
  const keyId = env.APNS_KEY_ID?.trim() || "";
  const teamId = env.APNS_TEAM_ID?.trim() || "48AMK8N4G5";
  const topic = env.APNS_TOPIC?.trim() || "com.pawsitivesync.app";
  try {
    if (env.APNS_KEY_P8 && keyId) apnsKey = createPrivateKey(pem(env.APNS_KEY_P8));
  } catch {
    apnsKeyError = true;
  }
  const account = readServiceAccount(env.FCM_SERVICE_ACCOUNT_JSON);

  let jwtCache = null; // { token, at }
  let fcmCache = null; // { token, expiresAt }
  let fcmPending = null;
  const sessions = new Map();
  const notConfiguredLogged = new Set();

  function apnsJwt() {
    const at = now();
    if (jwtCache && at - jwtCache.at < apnsJwtTtlMs) return jwtCache.token;
    jwtCache = { token: signApnsJwt({ key: apnsKey, keyId, teamId, nowMs: at }), at };
    return jwtCache.token;
  }

  /** One multiplexed HTTP/2 connection per APNs host, reopened when it dies. */
  function session(environment) {
    const host = apnsHosts[environment] ?? apnsHosts.production;
    const existing = sessions.get(host);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const created = connect(host);
    const forget = () => {
      if (sessions.get(host) === created) sessions.delete(host);
    };
    created.on("error", forget);
    created.on("close", forget);
    created.on("goaway", forget);
    // Idle connections must not keep the process alive at shutdown.
    created.unref?.();
    sessions.set(host, created);
    return created;
  }

  function sendApns(device, message) {
    const hex = device.token.slice("apns:".length);
    const background = message.background === true;
    const payload = background
      ? { aps: { "content-available": 1 }, ...(message.data ?? {}) }
      : {
          aps: {
            alert: message.alert,
            sound: "default",
            ...(message.threadId ? { "thread-id": message.threadId } : {}),
          },
          ...(message.data ?? {}),
        };
    const headers = {
      ":method": "POST",
      ":path": `/3/device/${hex}`,
      authorization: `bearer ${apnsJwt()}`,
      "apns-topic": topic,
      "apns-push-type": background ? "background" : "alert",
      // Background pushes must be priority 5 or Apple drops them.
      "apns-priority": background ? "5" : "10",
      ...(message.collapseId ? { "apns-collapse-id": String(message.collapseId).slice(0, 64) } : {}),
    };
    return new Promise((resolve) => {
      let settled = false;
      const done = (result) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(result);
      };
      let request;
      const timer = setTimeout(() => {
        request?.close?.(http2.constants.NGHTTP2_CANCEL);
        done({ ok: false, reason: "timeout" });
      }, sendTimeoutMs);
      try {
        request = session(device.environment).request(headers);
      } catch (error) {
        done({ ok: false, reason: String(error?.code ?? error?.message ?? error).slice(0, 60) });
        return;
      }
      let status = 0;
      const chunks = [];
      request.on("response", (responseHeaders) => {
        status = Number(responseHeaders[":status"]) || 0;
      });
      request.on("data", (chunk) => chunks.push(chunk));
      request.on("end", () => {
        if (status === 200) return done({ ok: true });
        let reason = `status_${status}`;
        try {
          reason = JSON.parse(Buffer.concat(chunks).toString("utf8"))?.reason || reason;
        } catch {
          // Body isn't JSON: keep the status.
        }
        if (apnsAuthReasons.has(reason)) jwtCache = null;
        done({ ok: false, reason, invalid: status === 410 || apnsInvalidReasons.has(reason) });
      });
      request.on("error", (error) => done({ ok: false, reason: String(error?.code ?? error?.message).slice(0, 60) }));
      request.end(JSON.stringify(payload));
    });
  }

  async function fcmToken() {
    if (fcmCache && fcmCache.expiresAt > now()) return fcmCache.token;
    // Concurrent sends share one token request.
    fcmPending ??= (async () => {
      try {
        const assertion = signGoogleAssertion({ ...account, nowMs: now() });
        const response = await fetchImpl(account.tokenUri, {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
            assertion,
          }).toString(),
          signal: AbortSignal.timeout(sendTimeoutMs),
        });
        if (!response.ok) throw new Error(`fcm_oauth_status_${response.status}`);
        const json = await response.json();
        const lifetimeS = Number(json.expires_in) || 3600;
        // Refresh a minute early so a send never carries an expiring token.
        fcmCache = { token: json.access_token, expiresAt: now() + (lifetimeS - 60) * 1000 };
        return fcmCache.token;
      } finally {
        fcmPending = null;
      }
    })();
    return fcmPending;
  }

  async function sendFcm(device, message) {
    try {
      const accessToken = await fcmToken();
      const body = {
        message: {
          token: device.token.slice("fcm:".length),
          ...(message.alert && !message.background ? { notification: message.alert } : {}),
          data: stringData(message.data),
          android: {
            priority: "high",
            ...(message.collapseId ? { collapse_key: String(message.collapseId).slice(0, 64) } : {}),
          },
        },
      };
      const response = await fetchImpl(`https://fcm.googleapis.com/v1/projects/${account.projectId}/messages:send`, {
        method: "POST",
        headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(sendTimeoutMs),
      });
      if (response.ok) return { ok: true };
      let detail = {};
      try {
        detail = (await response.json())?.error ?? {};
      } catch {
        // Not JSON.
      }
      const codes = (detail.details ?? []).map((item) => item?.errorCode).filter(Boolean);
      if (response.status === 401) fcmCache = null;
      const invalid =
        response.status === 404 ||
        codes.includes("UNREGISTERED") ||
        (response.status === 400 && /registration token/i.test(String(detail.message ?? "")));
      return { ok: false, invalid, reason: codes[0] ?? detail.status ?? `status_${response.status}` };
    } catch (error) {
      return { ok: false, reason: String(error?.name === "TimeoutError" ? "timeout" : error?.message ?? error).slice(0, 60) };
    }
  }

  return {
    /** Which platforms can send. `apnsKeyError`: the key env var is set but unreadable. */
    configured() {
      return { apns: apnsKey != null, fcm: account != null, apnsKeyError };
    },

    /** Logs `push.not_configured` once per process per platform. */
    noteNotConfigured(platform, logFn) {
      if (notConfiguredLogged.has(platform)) return;
      notConfiguredLogged.add(platform);
      logFn("push.not_configured", { platform, ...(platform === "ios" && apnsKeyError ? { reason: "bad_key" } : {}) });
    },

    canSend(device) {
      if (device.platform === "ios") return apnsKey != null && device.token.startsWith("apns:");
      if (device.platform === "android") return account != null && device.token.startsWith("fcm:");
      return false;
    },

    async send(device, message) {
      if (device.token.startsWith("apns:")) {
        if (!apnsKey) return { ok: false, reason: "not_configured" };
        return sendApns(device, message);
      }
      if (device.token.startsWith("fcm:")) {
        if (!account) return { ok: false, reason: "not_configured" };
        return sendFcm(device, message);
      }
      return { ok: false, reason: "unsupported_token" };
    },

    /** Closes open APNs connections (tests, shutdown). */
    close() {
      for (const open of sessions.values()) open.close();
      sessions.clear();
    },
  };
}

let shared = null;
/** The process-wide sender, created on first use from `process.env`. */
export function pushSender() {
  shared ??= createPushSender();
  return shared;
}
