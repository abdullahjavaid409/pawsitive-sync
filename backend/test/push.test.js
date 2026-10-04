/**
 * Push sender unit tests: no network. The HTTP/2 client and fetch are fakes.
 * Run: node --test backend/test/*.test.js
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { createPublicKey, generateKeyPairSync, verify } from "node:crypto";
import { createPushSender, signApnsJwt, signGoogleAssertion } from "../push.js";

const ec = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const p8 = ec.privateKey.export({ type: "pkcs8", format: "pem" });
const rsa = generateKeyPairSync("rsa", { modulusLength: 2048 });
const serviceAccount = JSON.stringify({
  project_id: "pawsitive-test",
  client_email: "push@pawsitive-test.iam.gserviceaccount.com",
  private_key: rsa.privateKey.export({ type: "pkcs8", format: "pem" }),
  token_uri: "https://oauth2.example.test/token",
});
const apnsEnv = { APNS_KEY_P8: p8, APNS_KEY_ID: "ABC123DEFG", APNS_TEAM_ID: "48AMK8N4G5", APNS_TOPIC: "com.pawsitivesync.app" };
const iosDevice = { platform: "ios", token: `apns:${"ab".repeat(32)}`, environment: "sandbox" };
const androidDevice = { platform: "android", token: "fcm:device-registration-token-123456", environment: "production" };

function decode(part) {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

/** A fake http2.connect: records each request and answers with `replies` in order. */
function fakeHttp2(replies) {
  const calls = [];
  const connect = (host) => {
    const session = new EventEmitter();
    session.closed = false;
    session.destroyed = false;
    session.unref = () => {};
    session.close = () => {
      session.closed = true;
    };
    session.request = (headers) => {
      const request = new EventEmitter();
      const call = { host, headers, body: "" };
      calls.push(call);
      request.close = () => {};
      request.end = (body) => {
        call.body = body;
        const reply = replies.shift() ?? { status: 200 };
        if (reply.hang) return; // never answers: exercises the 5 s timeout
        setImmediate(() => {
          request.emit("response", { ":status": reply.status });
          if (reply.body) request.emit("data", Buffer.from(JSON.stringify(reply.body)));
          request.emit("end");
        });
      };
      return request;
    };
    return session;
  };
  return { connect, calls };
}

test("APNs JWT is ES256 with kid/iss/iat and verifies with the public key", () => {
  const token = signApnsJwt({ key: ec.privateKey, keyId: "ABC123DEFG", teamId: "48AMK8N4G5", nowMs: 1_700_000_000_000 });
  const [header, claims, signature] = token.split(".");
  assert.deepEqual(decode(header), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(decode(claims), { iss: "48AMK8N4G5", iat: 1_700_000_000 });
  // JWT ES256 signatures are raw r||s: exactly 64 bytes.
  assert.equal(Buffer.from(signature, "base64url").length, 64);
  const ok = verify(
    "sha256",
    Buffer.from(`${header}.${claims}`),
    { key: createPublicKey(ec.privateKey), dsaEncoding: "ieee-p1363" },
    Buffer.from(signature, "base64url"),
  );
  assert.equal(ok, true);
});

test("Google assertion is RS256 with the FCM scope and a one-hour lifetime", () => {
  const token = signGoogleAssertion({
    clientEmail: "push@x.iam.gserviceaccount.com",
    privateKey: rsa.privateKey,
    tokenUri: "https://oauth2.googleapis.com/token",
    nowMs: 1_700_000_000_000,
  });
  const [header, claims, signature] = token.split(".");
  assert.deepEqual(decode(header), { alg: "RS256", typ: "JWT" });
  const body = decode(claims);
  assert.equal(body.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assert.equal(body.exp - body.iat, 3600);
  assert.equal(
    verify("sha256", Buffer.from(`${header}.${claims}`), rsa.publicKey, Buffer.from(signature, "base64url")),
    true,
  );
});

test("not configured: nothing is sent and push.not_configured logs once per platform", async () => {
  const sender = createPushSender({ env: {}, connect: () => assert.fail("must not connect") });
  assert.deepEqual(sender.configured(), { apns: false, fcm: false, apnsKeyError: false });
  assert.equal(sender.canSend(iosDevice), false);
  assert.deepEqual(await sender.send(iosDevice, { alert: { title: "t", body: "b" } }), { ok: false, reason: "not_configured" });
  const logs = [];
  const logFn = (event, fields) => logs.push({ event, fields });
  sender.noteNotConfigured("ios", logFn);
  sender.noteNotConfigured("ios", logFn);
  sender.noteNotConfigured("android", logFn);
  assert.deepEqual(logs.map((entry) => [entry.event, entry.fields.platform]), [
    ["push.not_configured", "ios"],
    ["push.not_configured", "android"],
  ]);
});

test("an unreadable APNs key counts as not configured (never throws at boot)", () => {
  const sender = createPushSender({ env: { APNS_KEY_P8: "not a key", APNS_KEY_ID: "X" } });
  assert.equal(sender.configured().apns, false);
  assert.equal(sender.configured().apnsKeyError, true);
});

test("APNs alert + background requests carry the right host, headers and payload; JWT is cached", async () => {
  const http = fakeHttp2([{ status: 200 }, { status: 200 }]);
  const sender = createPushSender({ env: apnsEnv, connect: http.connect });
  const data = { type: "dose_logged", doses: [{ medicationId: "med-1", part: "morning", day: "2026-10-04" }] };
  assert.deepEqual(await sender.send(iosDevice, { alert: { title: "Dose logged", body: "Sam gave Miso's Insulin · 8:02 AM" }, data, collapseId: "log-1" }), { ok: true });
  assert.deepEqual(await sender.send(iosDevice, { background: true, data }), { ok: true });
  const [alert, silent] = http.calls;
  assert.equal(alert.host, "https://api.sandbox.push.apple.com");
  assert.equal(alert.headers[":path"], `/3/device/${"ab".repeat(32)}`);
  assert.equal(alert.headers["apns-topic"], "com.pawsitivesync.app");
  assert.equal(alert.headers["apns-push-type"], "alert");
  assert.equal(alert.headers["apns-priority"], "10");
  assert.equal(alert.headers["apns-collapse-id"], "log-1");
  assert.match(alert.headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.equal(JSON.parse(alert.body).aps.alert.body, "Sam gave Miso's Insulin · 8:02 AM");
  assert.equal(silent.headers["apns-push-type"], "background");
  assert.equal(silent.headers["apns-priority"], "5");
  const silentBody = JSON.parse(silent.body);
  assert.deepEqual(silentBody.aps, { "content-available": 1 });
  assert.equal(silentBody.doses[0].medicationId, "med-1");
  // Same JWT reused within its 50-minute life.
  assert.equal(alert.headers.authorization, silent.headers.authorization);
});

test("APNs JWT refreshes after 50 minutes and after ExpiredProviderToken", async () => {
  let clock = 1_700_000_000_000;
  const http = fakeHttp2([{ status: 200 }, { status: 403, body: { reason: "ExpiredProviderToken" } }, { status: 200 }, { status: 200 }]);
  const sender = createPushSender({ env: apnsEnv, connect: http.connect, now: () => clock });
  await sender.send(iosDevice, { alert: { title: "a", body: "b" } });
  clock += 1000;
  const expired = await sender.send(iosDevice, { alert: { title: "a", body: "b" } });
  assert.equal(expired.ok, false);
  assert.equal(expired.invalid, false);
  clock += 1000;
  await sender.send(iosDevice, { alert: { title: "a", body: "b" } });
  clock += 51 * 60 * 1000;
  await sender.send(iosDevice, { alert: { title: "a", body: "b" } });
  const auths = http.calls.map((call) => call.headers.authorization);
  assert.equal(auths[0], auths[1]);
  assert.notEqual(auths[1], auths[2], "provider-token error forces a new JWT");
  assert.notEqual(auths[2], auths[3], "older than 50 minutes forces a new JWT");
});

test("APNs 410 and BadDeviceToken mark the token invalid; a 500 does not", async () => {
  const http = fakeHttp2([
    { status: 410, body: { reason: "Unregistered" } },
    { status: 400, body: { reason: "BadDeviceToken" } },
    { status: 500, body: { reason: "InternalServerError" } },
  ]);
  const sender = createPushSender({ env: apnsEnv, connect: http.connect });
  assert.deepEqual(await sender.send(iosDevice, { alert: { title: "a", body: "b" } }), { ok: false, reason: "Unregistered", invalid: true });
  assert.deepEqual(await sender.send(iosDevice, { alert: { title: "a", body: "b" } }), { ok: false, reason: "BadDeviceToken", invalid: true });
  assert.deepEqual(await sender.send(iosDevice, { alert: { title: "a", body: "b" } }), { ok: false, reason: "InternalServerError", invalid: false });
});

test("APNs production devices use the production host", async () => {
  const http = fakeHttp2([{ status: 200 }]);
  const sender = createPushSender({ env: apnsEnv, connect: http.connect });
  await sender.send({ ...iosDevice, environment: "production" }, { alert: { title: "a", body: "b" } });
  assert.equal(http.calls[0].host, "https://api.push.apple.com");
});

test("APNs send gives up after 5 s and reports a timeout", { timeout: 10_000 }, async () => {
  const http = fakeHttp2([{ hang: true }]);
  const sender = createPushSender({ env: apnsEnv, connect: http.connect });
  const started = Date.now();
  const result = await sender.send(iosDevice, { alert: { title: "a", body: "b" } });
  assert.deepEqual(result, { ok: false, reason: "timeout" });
  assert.ok(Date.now() - started >= 4900);
});

function fakeFetch(handlers) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    const handler = handlers.shift();
    const { status, body } = handler(url, init);
    return { ok: status >= 200 && status < 300, status, json: async () => body };
  };
  return { fetchImpl, calls };
}

test("FCM: one OAuth exchange is cached across sends; data values are strings", async () => {
  const http = fakeFetch([
    () => ({ status: 200, body: { access_token: "ya29.token", expires_in: 3600 } }),
    () => ({ status: 200, body: { name: "projects/x/messages/1" } }),
    () => ({ status: 200, body: { name: "projects/x/messages/2" } }),
  ]);
  const sender = createPushSender({ env: { FCM_SERVICE_ACCOUNT_JSON: serviceAccount }, fetchImpl: http.fetchImpl });
  assert.equal(sender.configured().fcm, true);
  const message = { alert: { title: "Dose logged", body: "Sam gave Miso's Insulin" }, data: { type: "dose_logged", doses: [{ day: "2026-10-04" }] } };
  assert.deepEqual(await sender.send(androidDevice, message), { ok: true });
  assert.deepEqual(await sender.send(androidDevice, message), { ok: true });
  assert.equal(http.calls.length, 3, "token exchange once, then two sends");
  assert.equal(http.calls[0].url, "https://oauth2.example.test/token");
  assert.match(http.calls[0].init.body, /grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer/);
  assert.equal(http.calls[1].url, "https://fcm.googleapis.com/v1/projects/pawsitive-test/messages:send");
  assert.equal(http.calls[1].init.headers.authorization, "Bearer ya29.token");
  const sent = JSON.parse(http.calls[1].init.body).message;
  assert.equal(sent.token, "device-registration-token-123456");
  assert.equal(sent.notification.title, "Dose logged");
  assert.equal(typeof sent.data.doses, "string");
});

test("FCM UNREGISTERED marks the token invalid", async () => {
  const http = fakeFetch([
    () => ({ status: 200, body: { access_token: "t", expires_in: 3600 } }),
    () => ({ status: 404, body: { error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } } }),
  ]);
  const sender = createPushSender({ env: { FCM_SERVICE_ACCOUNT_JSON: serviceAccount }, fetchImpl: http.fetchImpl });
  const result = await sender.send(androidDevice, { alert: { title: "a", body: "b" } });
  assert.equal(result.ok, false);
  assert.equal(result.invalid, true);
  assert.equal(result.reason, "UNREGISTERED");
});

test("FCM access token is fetched again once it expires", async () => {
  let clock = 1_700_000_000_000;
  const http = fakeFetch([
    () => ({ status: 200, body: { access_token: "first", expires_in: 120 } }),
    () => ({ status: 200, body: {} }),
    () => ({ status: 200, body: { access_token: "second", expires_in: 3600 } }),
    () => ({ status: 200, body: {} }),
  ]);
  const sender = createPushSender({ env: { FCM_SERVICE_ACCOUNT_JSON: serviceAccount }, fetchImpl: http.fetchImpl, now: () => clock });
  await sender.send(androidDevice, { alert: { title: "a", body: "b" } });
  clock += 61 * 1000; // past (120 s - 60 s early refresh)
  await sender.send(androidDevice, { alert: { title: "a", body: "b" } });
  assert.equal(http.calls[3].init.headers.authorization, "Bearer second");
});

test("unsupported tokens (old local:<time> ids) are never sent", async () => {
  const sender = createPushSender({ env: apnsEnv, connect: () => assert.fail("must not connect") });
  const device = { platform: "ios", token: "local:12345" };
  assert.equal(sender.canSend(device), false);
  assert.deepEqual(await sender.send(device, { alert: { title: "a", body: "b" } }), { ok: false, reason: "unsupported_token" });
});
