import { createServer } from "node:http";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  InputError,
  addCareEvent,
  addMedication,
  addPet,
  updatePet,
  applyBatch,
  archiveMedication,
  createHousehold,
  createPool,
  createSitterLink,
  exportHouseholdData,
  getSitterView,
  handleRevenueCatWebhook,
  deleteAccount,
  startPetPhotoUpload,
  attachPetPhoto,
  removePetPhoto,
  verifyRevenueCatWebhookByLookup,
  joinHousehold,
  leaveHousehold,
  linkAppleAccount,
  loadHousehold,
  logDose,
  memberForToken,
  migrate,
  notifyHouseholdOnDose,
  recoverFromApple,
  refillMedication,
  updateMedication,
  registerDevice,
  removeCareEvent,
  setPlan,
  sitterForToken,
  sitterLogDose,
  refreshProFromRevenueCat,
  revenueCatWebhookAuthorized,
  trackAnalytics,
  rotateInviteCode,
  setMemberRole,
  removeMember,
  listSitterLinks,
  revokeSitterLink,
  sweepExpiredSitterLinks,
  wasRemoved,
} from "./db.js";
import { verifyAppleIdentityToken } from "./apple.js";
import { requireRole } from "./roles.js";

const webDir = join(dirname(fileURLToPath(import.meta.url)), "web");
/** Absolute origin for link-preview images (crawlers need full URLs). */
const publicBase = (process.env.PUBLIC_BASE_URL || "https://pawsitive-api-production.up.railway.app").replace(/\/+$/, "");
const sitterPage = readFileSync(join(webDir, "sitter.html"), "utf8").replaceAll("__PUBLIC_BASE__", publicBase);
const sitterPreviewImage = readFileSync(join(webDir, "og-sitter.png"));

/**
 * The sitter page holds a bearer token, so it gets a strict CSP: only its own
 * inline script/style (pinned by hash, computed here so edits can't drift),
 * fetches only to this origin, never framed.
 */
function inlineHashes(html, tag) {
  const pattern = new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, "g");
  return [...html.matchAll(pattern)].map(
    (match) => `'sha256-${createHash("sha256").update(match[1]).digest("base64")}'`,
  );
}
const sitterCsp = [
  "default-src 'none'",
  `script-src ${inlineHashes(sitterPage, "script").join(" ")}`,
  `style-src ${inlineHashes(sitterPage, "style").join(" ")}`,
  "connect-src 'self'",
  "img-src 'self' data:",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

const slowMs = Number(process.env.SLOW_REQUEST_MS) || 500;

function log(event, fields) {
  process.stdout.write(
    `${JSON.stringify({
      time: new Date().toISOString(),
      service: "pawsitive-api",
      event,
      ...fields,
    })}\n`,
  );
}

/** A logger that stamps every line with the request it belongs to. */
const scopedLog = (requestId) => (event, fields) => log(event, { requestId, ...fields });

const baseHeaders = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "x-frame-options": "DENY",
  "cache-control": "no-store",
  "strict-transport-security": "max-age=31536000",
  "cross-origin-resource-policy": "same-origin",
};

let shuttingDown = false;

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    ...baseHeaders,
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    // An oversized body was left unread: drop the connection after replying.
    ...(status === 413 || shuttingDown ? { connection: "close" } : {}),
  });
  res.end(payload);
}

function sendHtml(res, status, html) {
  res.writeHead(status, {
    ...baseHeaders,
    "content-type": "text/html; charset=utf-8",
    "content-length": Buffer.byteLength(html),
    "content-security-policy": sitterCsp,
    ...(shuttingDown ? { connection: "close" } : {}),
  });
  res.end(html);
}

const smallBody = 8 * 1024;
const importBody = 512 * 1024;
const webhookBody = 64 * 1024;
const rateWindowMs = 60_000;
const limits = { default: 120, join: 10, create: 10, recover: 5, billing: 10, webhook: 600 };
const hits = new Map();
const maxTrackedClients = 20_000;

/**
 * Client IP for rate limiting. Railway's edge appends the address it saw to
 * X-Forwarded-For, so the RIGHTMOST entry is the one a client can't forge
 * (the leftmost is whatever the client sent). TRUSTED_PROXY_HOPS covers extra
 * proxies in front (e.g. a CDN).
 */
const trustedHops = Math.max(Number(process.env.TRUSTED_PROXY_HOPS) || 1, 1);
function clientKey(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    const chain = forwarded.split(",").map((part) => part.trim()).filter(Boolean);
    const ip = chain[Math.max(chain.length - trustedHops, 0)];
    if (ip) return ip.slice(0, 64);
  }
  return req.socket.remoteAddress ?? "unknown";
}

function limited(req, bucket) {
  const now = Date.now();
  const key = `${bucket}:${clientKey(req)}`;
  const current = hits.get(key);
  if (!current || current.resetAt <= now) {
    if (hits.size >= maxTrackedClients) {
      // Drop expired windows first; only wipe live ones if still over the cap.
      for (const [entryKey, entry] of hits) if (entry.resetAt <= now) hits.delete(entryKey);
      if (hits.size >= maxTrackedClients) hits.clear();
    }
    hits.set(key, { count: 1, resetAt: now + rateWindowMs });
    return false;
  }
  current.count += 1;
  return current.count > limits[bucket];
}

function readJson(req, maxBytes = smallBody) {
  return new Promise((resolve, reject) => {
    const tooLarge = () => Object.assign(new Error("Body too large"), { status: 413 });
    const declared = Number(req.headers["content-length"]);
    if (Number.isFinite(declared) && declared > maxBytes) {
      reject(tooLarge());
      return;
    }
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        // Stop buffering; the 413 is sent with Connection: close.
        req.removeAllListeners("data");
        req.pause();
        reject(tooLarge());
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

/** Push and other best-effort work runs after the response; shutdown waits for it. */
const background = new Set();
function runInBackground(work, requestId) {
  const task = Promise.resolve()
    .then(work)
    .catch((error) => {
      log("background.failed", { requestId, reason: String(error?.message ?? error).slice(0, 200) });
    })
    .finally(() => background.delete(task));
  background.add(task);
}

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  log("db.missing_url", {});
  process.exit(1);
}

const pool = createPool(connectionString);
// An idle client dying (DB restart, network blip) emits 'error' on the pool;
// unhandled, that would crash the process.
pool.on("error", (error) => {
  log("db.pool_error", { code: error?.code ?? "unknown", reason: String(error?.message ?? error).slice(0, 200) });
});

async function connectWithRetry() {
  for (let attempt = 1; attempt <= 10; attempt += 1) {
    try {
      await pool.query("SELECT 1");
      log("db.connected", { attempt });
      return;
    } catch (error) {
      log("db.connect_failed", {
        attempt,
        code: error instanceof Error && "code" in error ? error.code : "unknown",
      });
      if (attempt === 10) throw error;
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }
}

function bucketFor(req, path) {
  if (req.method !== "POST") return "default";
  if (path === "/v1/join") return "join";
  if (path === "/v1/households") return "create";
  if (path === "/v1/auth/apple/recover") return "recover";
  // Each call is a RevenueCat API request; keep a loop from burning the quota.
  if (path === "/v1/billing/trial") return "billing";
  if (path === "/v1/webhooks/revenuecat") return "webhook";
  return "default";
}

/** Plain words for the person; the developer reason goes to the logs only. */
function failure(error) {
  const status =
    error instanceof SyntaxError || error instanceof URIError || error?.code === "ERR_INVALID_URL"
      ? 400
      : Number.isInteger(error?.status) && error.status >= 400 && error.status < 600
        ? error.status
        : 500;
  const message =
    error instanceof InputError || error?.expose === true
      ? error.message
      : status === 400
        ? "Something went wrong sending that. Try again."
        : status === 413
          ? "That's too much to send at once. Try again with less."
          : "Something went wrong on our side. Try again in a moment.";
  // 5xx: the error message (never the stack, never query parameters) plus the
  // Postgres SQLSTATE when there is one. 4xx: the InputError detail.
  const reason =
    status >= 500
      ? String(error?.message ?? error).slice(0, 200)
      : String(error?.detail ?? error?.message ?? message).slice(0, 200);
  return {
    status,
    message,
    reason,
    code: typeof error?.code === "string" ? error.code : undefined,
    // Machine-readable reason the app may act on (role_forbidden, pro_required, invite_expired).
    publicCode: typeof error?.publicCode === "string" ? error.publicCode : undefined,
  };
}

const server = createServer(async (req, res) => {
  const started = Date.now();
  // Echoed in a response header and logs: keep it to safe characters.
  const requestId =
    req.headers["x-request-id"]?.toString().replace(/[^A-Za-z0-9._:-]/g, "").slice(0, 64) || randomUUID();
  res.setHeader("x-request-id", requestId);
  let path = "/";
  const timing = () => {
    const durationMs = Date.now() - started;
    return { durationMs, ...(durationMs >= slowMs ? { slow: true } : {}) };
  };

  try {
    // Inside the try: a malformed request target used to throw here, outside
    // any handler, and crash the whole process.
    const url = new URL(req.url ?? "/", "http://localhost");
    path = url.pathname.slice(0, 200);

    if (path !== "/health" && limited(req, bucketFor(req, url.pathname))) {
      send(res, 429, { error: "Too many tries. Wait a minute and try again." });
      log("request.limited", { requestId, method: req.method, path, status: 429, bucket: bucketFor(req, url.pathname) });
      return;
    }

    const result = await route(req, url, requestId);
    if (result.png) {
      res.writeHead(result.status, {
        ...baseHeaders,
        "content-type": "image/png",
        "content-length": result.png.length,
        "cache-control": "public, max-age=86400",
        // Preview images are meant to be shown by other apps and sites.
        "cross-origin-resource-policy": "cross-origin",
      });
      res.end(result.png);
    } else if (result.html) {
      sendHtml(res, result.status, result.html);
    } else {
      send(res, result.status, result.body);
    }
    log("request.completed", { requestId, method: req.method, path, status: result.status, ...timing() });
  } catch (error) {
    const { status, message, reason, code, publicCode } = failure(error);
    if (!res.headersSent) send(res, status, { error: message, ...(publicCode ? { code: publicCode } : {}) });
    else res.destroy();
    log("request.failed", { requestId, method: req.method, path, status, reason, code, publicCode, ...timing() });
  }
});

// Slow-client protection (Node's defaults allow a 5-minute request).
server.headersTimeout = 15_000;
server.requestTimeout = 30_000;
// Longer than Railway's proxy idle timeout so the proxy closes first.
server.keepAliveTimeout = 65_000;

function bearer(req) {
  const header = req.headers.authorization;
  if (typeof header !== "string" || !header.startsWith("Bearer ")) return null;
  return header.slice(7).trim();
}

async function authorize(req) {
  const token = bearer(req);
  return token ? memberForToken(pool, token) : null;
}

/**
 * Expired sitter links are swept at most once an hour, in the background of
 * whatever request comes along — no cron, no extra service.
 */
const sweepEveryMs = 60 * 60 * 1000;
let lastSweepAt = 0;
function maybeSweep(requestId) {
  const at = Date.now();
  if (at - lastSweepAt < sweepEveryMs) return;
  lastSweepAt = at;
  runInBackground(async () => {
    const swept = await sweepExpiredSitterLinks(pool);
    if (swept.links > 0) log("sitter.links_swept", { requestId, ...swept });
  }, requestId);
}

async function authorizeSitter(req) {
  const header = req.headers.authorization;
  if (typeof header !== "string" || !header.startsWith("Bearer ")) return null;
  return sitterForToken(pool, header.slice(7).trim());
}

async function snapshot(auth) {
  return loadHousehold(pool, auth);
}

async function route(req, url, requestId) {
  const path = url.pathname;
  if (req.method === "GET" && path === "/health") {
    await pool.query("SELECT 1");
    return { status: 200, body: { ok: true, service: "pawsitive-api", version: 5 } };
  }

  if (req.method === "GET" && (path === "/sitter" || path === "/join")) {
    return { status: 200, html: sitterPage };
  }

  if (req.method === "GET" && path === "/og-sitter.png") {
    return { status: 200, png: sitterPreviewImage };
  }

  if (req.method === "GET" && path === "/v1/sitter/view") {
    const sitter = await authorizeSitter(req);
    if (!sitter) return { status: 401, body: { error: "This sitter link expired or is invalid." } };
    const view = await getSitterView(pool, sitter, {
      day: url.searchParams.get("day"),
      hour: url.searchParams.get("hour"),
      minute: url.searchParams.get("minute"),
    });
    if (!view) return { status: 404, body: { error: "This household no longer exists." } };
    return { status: 200, body: view };
  }

  if (req.method === "POST" && path === "/v1/sitter/logs") {
    const sitter = await authorizeSitter(req);
    if (!sitter) return { status: 401, body: { error: "This sitter link expired or is invalid." } };
    const result = await sitterLogDose(pool, sitter, await readJson(req));
    if (result.missing) return { status: 404, body: { error: "That medicine was removed. Pull down to refresh." } };
    if (result.conflict !== undefined) {
      log("dose.already_logged", { requestId, householdId: sitter.householdId, source: "sitter" });
      return { status: 409, body: { error: "Someone already logged this dose.", log: result.conflict } };
    }
    log("dose.logged", {
      requestId,
      householdId: sitter.householdId,
      outcome: result.log.outcome,
      source: "sitter",
    });
    runInBackground(() => notifyHouseholdOnDose(pool, sitter, result.log, scopedLog(requestId)), requestId);
    return { status: 201, body: result };
  }

  if (req.method === "POST" && path === "/v1/households") {
    const body = await readJson(req, importBody);
    const created = await createHousehold(pool, body);
    log("household.created", { requestId, householdId: created.householdId });
    return { status: 201, body: { token: created.token, ...(await snapshot(created)) } };
  }

  if (req.method === "POST" && path === "/v1/join") {
    const body = await readJson(req);
    const joined = await joinHousehold(pool, body);
    if (!joined) {
      log("household.join_rejected", { requestId });
      return { status: 404, body: { error: "That invite code was not found. Check it and try again." } };
    }
    log("household.joined", { requestId, householdId: joined.householdId, memberId: joined.memberId });
    return { status: 201, body: { token: joined.token, ...(await snapshot(joined)) } };
  }

  if (req.method === "POST" && path === "/v1/auth/apple/recover") {
    const body = await readJson(req);
    // Only an Apple-signed identity token proves who this is. A bare
    // appleUserId (old contract) would let anyone take over a household.
    const apple = await verifyAppleIdentityToken(body.identityToken);
    if (!apple.ok) {
      log("auth.apple_rejected", { requestId, reason: apple.reason, route: "recover" });
      return { status: 401, body: { error: "Apple Sign-In couldn't be confirmed. Try signing in again." } };
    }
    const recovered = await recoverFromApple(pool, apple.sub);
    if (!recovered) {
      return { status: 404, body: { error: "No household is linked to this Apple ID yet." } };
    }
    log("auth.apple_recovered", { requestId, householdId: recovered.householdId });
    return { status: 200, body: { token: recovered.token, ...(await snapshot(recovered)) } };
  }

  if (req.method === "POST" && path === "/v1/webhooks/revenuecat") {
    // Header only — a secret inside the JSON body is never accepted — and
    // checked before reading the body, so strangers can't make us parse 64 KB.
    const headerValue = req.headers.authorization;
    const check = revenueCatWebhookAuthorized(headerValue);
    // No header at all: still useful as a "something changed" ping, but only
    // through a RevenueCat API lookup — the body is never trusted. A wrong
    // header is always rejected.
    if (!check.ok && check.reason !== "bad_secret" && process.env.REVENUECAT_SECRET_KEY) {
      const body = await readJson(req, webhookBody);
      const result = await verifyRevenueCatWebhookByLookup(pool, body, scopedLog(requestId));
      if (result.status === "retry") return { status: 503, body: { error: "Try again shortly." } };
      return { status: 200, body: result };
    }
    if (!check.ok) {
      log(check.reason === "secret_not_configured" ? "billing.webhook_secret_missing" : "billing.webhook_unauthorized", {
        requestId,
        reason: check.reason,
      });
      return { status: 401, body: { error: "Invalid webhook secret" } };
    }
    const body = await readJson(req, webhookBody);
    const result = await handleRevenueCatWebhook(
      pool,
      { ...body, authorization: headerValue.replace(/^Bearer\s+/i, "").trim() },
      scopedLog(requestId),
    );
    if (result.status === "unauthorized") return { status: 401, body: { error: "Invalid webhook secret" } };
    return { status: 200, body: result };
  }

  if (req.method === "POST" && path === "/v1/analytics/batch") {
    const body = await readJson(req);
    return { status: 202, body: await trackAnalytics(pool, body.events) };
  }

  if (!path.startsWith("/v1/")) return { status: 404, body: { error: "That page doesn't exist." } };

  const auth = await authorize(req);
  if (!auth) {
    // Only on failure: tell a removed member why (their phone keeps its data).
    if (await wasRemoved(pool, bearer(req))) {
      return {
        status: 401,
        body: { error: "The household owner removed you from this household.", code: "member_removed" },
      };
    }
    return { status: 401, body: { error: "Sign in again to reach this household." } };
  }
  maybeSweep(requestId);
  // Every /v1 route below names the action it needs (roles.js).
  const allow = (action) => requireRole(auth, action);

  if (req.method === "GET" && path === "/v1/household") {
    allow("household.read");
    const house = await snapshot(auth);
    if (!house) return { status: 401, body: { error: "This household no longer exists." } };
    return { status: 200, body: house };
  }

  if (req.method === "POST" && path === "/v1/pets") {
    allow("pet.add");
    const pet = await addPet(pool, auth, await readJson(req));
    log("pet.added", { requestId, householdId: auth.householdId, petId: pet.id });
    return { status: 201, body: { pet } };
  }

  const petPhotoPath = path.match(/^\/v1\/pets\/([^/]+)\/photo(\/upload)?$/);
  if (petPhotoPath) {
    const petId = decodeURIComponent(petPhotoPath[1]);
    const missing = { status: 404, body: { error: "That pet was removed. Pull down to refresh." } };
    allow("pet.photo");
    if (req.method === "POST" && petPhotoPath[2]) {
      const started = await startPetPhotoUpload(pool, auth, petId, await readJson(req));
      if (!started) return missing;
      log("pet.photo_upload_started", { requestId, householdId: auth.householdId, petId });
      return { status: 200, body: started };
    }
    if (req.method === "PUT" && !petPhotoPath[2]) {
      const attached = await attachPetPhoto(pool, auth, petId, await readJson(req), scopedLog(requestId));
      if (!attached) return missing;
      log("pet.photo_set", { requestId, householdId: auth.householdId, petId });
      return { status: 200, body: attached };
    }
    if (req.method === "DELETE" && !petPhotoPath[2]) {
      const removed = await removePetPhoto(pool, auth, petId, scopedLog(requestId));
      if (!removed) return missing;
      log("pet.photo_removed", { requestId, householdId: auth.householdId, petId });
      return { status: 200, body: removed };
    }
  }

  const petPath = path.match(/^\/v1\/pets\/([^/]+)$/);
  if (req.method === "PATCH" && petPath) {
    allow("pet.update");
    const pet = await updatePet(pool, auth, decodeURIComponent(petPath[1]), await readJson(req));
    if (!pet) return { status: 404, body: { error: "That pet was removed. Pull down to refresh." } };
    log("pet.updated", { requestId, householdId: auth.householdId, petId: pet.id });
    return { status: 200, body: { pet } };
  }

  if (req.method === "POST" && path === "/v1/medications") {
    allow("medication.add");
    const medication = await addMedication(pool, auth, await readJson(req));
    log("medication.added", { requestId, householdId: auth.householdId, medicationId: medication.id });
    return { status: 201, body: { medication } };
  }

  const medicationPath = path.match(/^\/v1\/medications\/([^/]+)$/);
  if (req.method === "PATCH" && medicationPath) {
    allow("medication.update");
    const medication = await updateMedication(pool, auth, decodeURIComponent(medicationPath[1]), await readJson(req));
    if (!medication) return { status: 404, body: { error: "That medicine was removed. Pull down to refresh." } };
    log("medication.updated", { requestId, householdId: auth.householdId, medicationId: medication.id });
    return { status: 200, body: { medication } };
  }
  if (req.method === "DELETE" && medicationPath) {
    allow("medication.archive");
    const removed = await archiveMedication(pool, auth, decodeURIComponent(medicationPath[1]));
    if (!removed) return { status: 404, body: { error: "That medicine was removed. Pull down to refresh." } };
    log("medication.archived", { requestId, householdId: auth.householdId });
    return { status: 200, body: { ok: true } };
  }

  const refill = path.match(/^\/v1\/medications\/([^/]+)\/refill$/);
  if (req.method === "POST" && refill) {
    allow("medication.refill");
    const medication = await refillMedication(pool, auth, decodeURIComponent(refill[1]));
    if (!medication) return { status: 404, body: { error: "That medicine was removed. Pull down to refresh." } };
    log("medication.refilled", { requestId, householdId: auth.householdId, medicationId: medication.id });
    return { status: 200, body: { medication } };
  }

  if (req.method === "POST" && path === "/v1/logs") {
    allow("dose.log");
    const result = await logDose(pool, auth, await readJson(req));
    if (result.missing) return { status: 404, body: { error: "That medicine was removed. Pull down to refresh." } };
    if (result.conflict !== undefined) {
      log("dose.already_logged", { requestId, householdId: auth.householdId });
      return { status: 409, body: { error: "Someone already logged this dose.", log: result.conflict } };
    }
    log("dose.logged", { requestId, householdId: auth.householdId, outcome: result.log.outcome });
    runInBackground(() => notifyHouseholdOnDose(pool, auth, result.log, scopedLog(requestId)), requestId);
    return { status: 201, body: result };
  }

  if (req.method === "POST" && path === "/v1/sync/batch") {
    // Per-op roles are checked inside applyBatch; a forbidden op fails alone.
    const body = await readJson(req, importBody);
    const { logged, ...batch } = await applyBatch(pool, auth, body);
    const failed = batch.results.filter((item) => item.status === "error").length;
    log("sync.batch", {
      requestId,
      householdId: auth.householdId,
      count: batch.results.length,
      failed,
      dosesLogged: logged.length,
    });
    if (logged.length > 0) {
      runInBackground(() => notifyHouseholdOnDose(pool, auth, logged, scopedLog(requestId)), requestId);
    }
    return { status: 200, body: batch };
  }

  if (req.method === "POST" && path === "/v1/sitter-links") {
    allow("sitterLinks.manage");
    const created = await createSitterLink(pool, auth, await readJson(req));
    log("sitter.link_created", {
      requestId,
      householdId: auth.householdId,
      linkId: created.linkId,
    });
    return {
      status: 201,
      body: {
        token: created.token,
        expiresAt: created.expiresAt,
        // Additive (v5): lets the owner's phone match its cached link to the list.
        id: created.linkId,
        // Fragment, not query: never sent to the server or proxy logs on open.
        url: `/sitter#t=${encodeURIComponent(created.token)}`,
      },
    };
  }

  if (req.method === "POST" && path === "/v1/care-events") {
    allow("careEvent.add");
    const event = await addCareEvent(pool, auth, await readJson(req));
    log("care_event.added", { requestId, householdId: auth.householdId, eventId: event.id });
    return { status: 201, body: { careEvent: event } };
  }

  const careEventPath = path.match(/^\/v1\/care-events\/([^/]+)$/);
  if (req.method === "DELETE" && careEventPath) {
    allow("careEvent.remove");
    const removed = await removeCareEvent(pool, auth, decodeURIComponent(careEventPath[1]));
    if (!removed) return { status: 404, body: { error: "That reminder was already removed." } };
    log("care_event.removed", { requestId, householdId: auth.householdId });
    return { status: 200, body: { ok: true } };
  }

  if (req.method === "POST" && path === "/v1/auth/apple/link") {
    allow("apple.link");
    const body = await readJson(req);
    const apple = await verifyAppleIdentityToken(body.identityToken);
    if (!apple.ok) {
      log("auth.apple_rejected", { requestId, reason: apple.reason, route: "link" });
      return { status: 401, body: { error: "Apple Sign-In couldn't be confirmed. Try signing in again." } };
    }
    const linked = await linkAppleAccount(pool, auth, apple.sub);
    log("auth.apple_linked", { requestId, householdId: auth.householdId });
    return { status: 200, body: linked };
  }

  if (req.method === "POST" && path === "/v1/devices/register") {
    allow("device.register");
    const registered = await registerDevice(pool, auth, await readJson(req));
    log("device.registered", {
      requestId,
      householdId: auth.householdId,
      stored: registered.stored,
      delivery: registered.delivery,
    });
    return { status: 200, body: registered };
  }

  if (req.method === "DELETE" && path === "/v1/account") {
    allow("account.delete");
    const result = await deleteAccount(pool, auth, scopedLog(requestId));
    if (!result.deleted) return { status: 401, body: { error: "This phone is no longer in the household." } };
    return { status: 200, body: result };
  }

  if (req.method === "POST" && path === "/v1/members/leave") {
    allow("member.leave");
    const left = await leaveHousehold(pool, auth);
    log("member.left", { requestId, householdId: auth.householdId, memberId: auth.memberId });
    return { status: 200, body: left };
  }

  if (req.method === "GET" && path === "/v1/export") {
    allow("export");
    const data = await exportHouseholdData(pool, auth);
    if (!data) return { status: 404, body: { error: "This household no longer exists." } };
    log("export.completed", { requestId, householdId: auth.householdId });
    return { status: 200, body: data };
  }

  if (req.method === "POST" && path === "/v1/billing/plan") {
    allow("billing.plan");
    const body = await readJson(req);
    const plan = await setPlan(pool, auth, body.plan);
    if (!plan) return { status: 400, body: { error: "Pick yearly or monthly." } };
    log("billing.plan_set", { requestId, householdId: auth.householdId, plan });
    return { status: 200, body: { plan } };
  }

  if (req.method === "POST" && path === "/v1/billing/trial") {
    allow("billing.refresh");
    const refreshed = await refreshProFromRevenueCat(pool, auth, scopedLog(requestId));
    return { status: 200, body: refreshed };
  }

  if (req.method === "POST" && path === "/v1/invite/rotate") {
    allow("invite.rotate");
    const rotated = await rotateInviteCode(pool, auth);
    if (!rotated) return { status: 401, body: { error: "This household no longer exists." } };
    log("invite.rotated", { requestId, householdId: auth.householdId });
    return { status: 200, body: rotated };
  }

  if (req.method === "GET" && path === "/v1/sitter-links") {
    allow("sitterLinks.manage");
    return { status: 200, body: { links: await listSitterLinks(pool, auth) } };
  }

  const sitterLinkPath = path.match(/^\/v1\/sitter-links\/([^/]+)$/);
  if (req.method === "DELETE" && sitterLinkPath) {
    allow("sitterLinks.manage");
    const revoked = await revokeSitterLink(pool, auth, decodeURIComponent(sitterLinkPath[1]));
    log("sitter.link_revoked", { requestId, householdId: auth.householdId, existed: revoked });
    // Already gone (double tap, another phone) is still "revoked".
    return { status: 200, body: { ok: true, revoked } };
  }

  const memberPath = path.match(/^\/v1\/members\/([^/]+)$/);
  if (memberPath && (req.method === "PATCH" || req.method === "DELETE")) {
    allow("members.manage");
    const targetId = decodeURIComponent(memberPath[1]);
    const gone = { status: 404, body: { error: "That person already left the household.", code: "member_gone" } };
    if (req.method === "PATCH") {
      const member = await setMemberRole(pool, auth, targetId, await readJson(req));
      if (!member) return gone;
      log("member.role_changed", { requestId, householdId: auth.householdId, memberId: targetId, role: member.role });
      return { status: 200, body: { member } };
    }
    const removed = await removeMember(pool, auth, targetId);
    if (!removed) return gone;
    log("member.removed", { requestId, householdId: auth.householdId, memberId: targetId, role: removed.role });
    return { status: 200, body: { ok: true } };
  }

  return { status: 404, body: { error: "That page doesn't exist." } };
}

await connectWithRetry();
await migrate(pool, log);

const port = Number(process.env.PORT) || 3000;
server.listen(port, "0.0.0.0", () => {
  log("server.started", { port });
});

/**
 * SIGTERM (Railway redeploy): stop accepting, let in-flight requests and
 * background pushes finish, close the pool, exit. Hard stop after 10 s.
 */
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log("server.stopping", { signal, inFlightBackground: background.size });
  const force = setTimeout(() => {
    log("server.stop_forced", { signal });
    process.exit(1);
  }, Number(process.env.SHUTDOWN_GRACE_MS) || 10_000);
  force.unref();
  const closed = new Promise((resolve) => server.close(resolve));
  server.closeIdleConnections();
  await closed;
  await Promise.allSettled([...background]);
  await pool.end().catch((error) => log("db.pool_end_failed", { reason: String(error?.message ?? error) }));
  log("server.stopped", { signal });
  process.exit(0);
}

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    shutdown(signal);
  });
}

process.on("unhandledRejection", (error) => {
  log("process.unhandled_rejection", { reason: String(error?.message ?? error).slice(0, 200) });
});
process.on("uncaughtException", (error) => {
  log("process.uncaught_exception", { reason: String(error?.message ?? error).slice(0, 200) });
  process.exit(1);
});
