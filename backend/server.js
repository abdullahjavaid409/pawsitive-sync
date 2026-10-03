import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
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
  registerDevice,
  removeCareEvent,
  setPlan,
  sitterForToken,
  sitterLogDose,
  startTrial,
  trackAnalytics,
} from "./db.js";

const sitterPage = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "web", "sitter.html"),
  "utf8",
);

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

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "x-frame-options": "DENY",
    "cache-control": "no-store",
  });
  res.end(payload);
}

function sendHtml(res, status, html) {
  res.writeHead(status, {
    "content-type": "text/html; charset=utf-8",
    "content-length": Buffer.byteLength(html),
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "cache-control": "no-store",
  });
  res.end(html);
}

const smallBody = 8 * 1024;
const importBody = 512 * 1024;
const rateWindowMs = 60_000;
const limits = { default: 120, join: 10, create: 10 };
const hits = new Map();

function clientKey(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim().slice(0, 64);
  }
  return req.socket.remoteAddress ?? "unknown";
}

function limited(req, bucket) {
  const now = Date.now();
  const key = `${bucket}:${clientKey(req)}`;
  const current = hits.get(key);
  if (!current || current.resetAt <= now) {
    if (hits.size > 5000) hits.clear();
    hits.set(key, { count: 1, resetAt: now + rateWindowMs });
    return false;
  }
  current.count += 1;
  return current.count > limits[bucket];
}

function readJson(req, maxBytes = smallBody) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(Object.assign(new Error("Body too large"), { status: 413 }));
        req.destroy();
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

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  log("db.missing_url", {});
  process.exit(1);
}

const pool = createPool(connectionString);

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
  if (req.method === "POST" && path === "/v1/join") return "join";
  if (req.method === "POST" && path === "/v1/households") return "create";
  return "default";
}

const server = createServer(async (req, res) => {
  const started = Date.now();
  const requestId = req.headers["x-request-id"]?.toString().slice(0, 64) || randomUUID();
  const url = new URL(req.url ?? "/", "http://localhost");
  res.setHeader("x-request-id", requestId);

  if (url.pathname !== "/health" && limited(req, bucketFor(req, url.pathname))) {
    send(res, 429, { error: "Too many tries. Wait a minute and try again." });
    log("request.limited", { requestId, method: req.method, path: url.pathname });
    return;
  }

  try {
    const result = await route(req, url, requestId);
    if (result.html) {
      sendHtml(res, result.status, result.html);
    } else {
      send(res, result.status, result.body);
    }
    log("request.completed", {
      requestId,
      method: req.method,
      path: url.pathname,
      status: result.status,
      durationMs: Date.now() - started,
    });
  } catch (error) {
    const status = error instanceof SyntaxError ? 400 : error.status ?? 500;
    const message =
      error instanceof InputError
        ? error.message
        : status === 400
          ? "Invalid JSON"
          : status === 413
            ? "Body too large"
            : "Internal error";
    send(res, status, { error: message });
    log("request.failed", {
      requestId,
      method: req.method,
      path: url.pathname,
      status,
      reason: status === 500 ? String(error?.message ?? error).slice(0, 200) : message,
      durationMs: Date.now() - started,
    });
  }
});

async function authorize(req) {
  const header = req.headers.authorization;
  if (typeof header !== "string" || !header.startsWith("Bearer ")) return null;
  return memberForToken(pool, header.slice(7).trim());
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
    return { status: 200, body: { ok: true, service: "pawsitive-api", version: 4 } };
  }

  if (req.method === "GET" && (path === "/sitter" || path === "/join")) {
    return { status: 200, html: sitterPage };
  }

  if (req.method === "GET" && path === "/v1/sitter/view") {
    const sitter = await authorizeSitter(req);
    if (!sitter) return { status: 401, body: { error: "This sitter link expired or is invalid." } };
    const view = await getSitterView(pool, sitter, {
      day: url.searchParams.get("day"),
      hour: url.searchParams.get("hour"),
    });
    if (!view) return { status: 404, body: { error: "Household not found." } };
    return { status: 200, body: view };
  }

  if (req.method === "POST" && path === "/v1/sitter/logs") {
    const sitter = await authorizeSitter(req);
    if (!sitter) return { status: 401, body: { error: "This sitter link expired or is invalid." } };
    const result = await sitterLogDose(pool, sitter, await readJson(req));
    if (result.missing) return { status: 404, body: { error: "Medication not found" } };
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
    await notifyHouseholdOnDose(pool, sitter, result.log, log);
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
    const recovered = await recoverFromApple(pool, body.appleUserId);
    if (!recovered) {
      return { status: 404, body: { error: "No household is linked to this Apple ID yet." } };
    }
    log("auth.apple_recovered", { requestId, householdId: recovered.householdId });
    return { status: 200, body: { token: recovered.token, ...(await snapshot(recovered)) } };
  }

  if (req.method === "POST" && path === "/v1/webhooks/revenuecat") {
    const body = await readJson(req, importBody);
    // Header only — a secret inside the JSON body is never accepted.
    const headerSecret = req.headers.authorization?.replace(/^Bearer\s+/i, "").trim();
    const result = await handleRevenueCatWebhook(
      pool,
      { ...body, authorization: headerSecret },
      log,
    );
    if (result.status === "unauthorized") return { status: 401, body: { error: "Invalid webhook secret" } };
    return { status: 200, body: result };
  }

  if (req.method === "POST" && path === "/v1/analytics/batch") {
    const body = await readJson(req);
    return { status: 202, body: await trackAnalytics(pool, body.events) };
  }

  if (!path.startsWith("/v1/")) return { status: 404, body: { error: "Not found" } };

  const auth = await authorize(req);
  if (!auth) return { status: 401, body: { error: "Sign in again to reach this household." } };

  if (req.method === "GET" && path === "/v1/household") {
    const house = await snapshot(auth);
    if (!house) return { status: 401, body: { error: "This household no longer exists." } };
    return { status: 200, body: house };
  }

  if (req.method === "POST" && path === "/v1/pets") {
    const pet = await addPet(pool, auth, await readJson(req));
    log("pet.added", { requestId, householdId: auth.householdId, petId: pet.id });
    return { status: 201, body: { pet } };
  }

  const petPath = path.match(/^\/v1\/pets\/([^/]+)$/);
  if (req.method === "PATCH" && petPath) {
    const pet = await updatePet(pool, auth, decodeURIComponent(petPath[1]), await readJson(req));
    if (!pet) return { status: 404, body: { error: "Pet not found" } };
    log("pet.updated", { requestId, householdId: auth.householdId, petId: pet.id });
    return { status: 200, body: { pet } };
  }

  if (req.method === "POST" && path === "/v1/medications") {
    const medication = await addMedication(pool, auth, await readJson(req));
    log("medication.added", { requestId, householdId: auth.householdId, medicationId: medication.id });
    return { status: 201, body: { medication } };
  }

  const medicationPath = path.match(/^\/v1\/medications\/([^/]+)$/);
  if (req.method === "DELETE" && medicationPath) {
    const removed = await archiveMedication(pool, auth, decodeURIComponent(medicationPath[1]));
    if (!removed) return { status: 404, body: { error: "Medication not found" } };
    log("medication.archived", { requestId, householdId: auth.householdId });
    return { status: 200, body: { ok: true } };
  }

  const refill = path.match(/^\/v1\/medications\/([^/]+)\/refill$/);
  if (req.method === "POST" && refill) {
    const medication = await refillMedication(pool, auth, decodeURIComponent(refill[1]));
    if (!medication) return { status: 404, body: { error: "Medication not found" } };
    log("medication.refilled", { requestId, householdId: auth.householdId, medicationId: medication.id });
    return { status: 200, body: { medication } };
  }

  if (req.method === "POST" && path === "/v1/logs") {
    const result = await logDose(pool, auth, await readJson(req));
    if (result.missing) return { status: 404, body: { error: "Medication not found" } };
    if (result.conflict !== undefined) {
      log("dose.already_logged", { requestId, householdId: auth.householdId });
      return { status: 409, body: { error: "Someone already logged this dose.", log: result.conflict } };
    }
    log("dose.logged", { requestId, householdId: auth.householdId, outcome: result.log.outcome });
    await notifyHouseholdOnDose(pool, auth, result.log, log);
    return { status: 201, body: result };
  }

  if (req.method === "POST" && path === "/v1/sync/batch") {
    const body = await readJson(req, importBody);
    const batch = await applyBatch(pool, auth, body, log);
    log("sync.batch", { requestId, householdId: auth.householdId, count: body.operations?.length ?? 0 });
    return { status: 200, body: batch };
  }

  if (req.method === "POST" && path === "/v1/sitter-links") {
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
        url: `/sitter?t=${encodeURIComponent(created.token)}`,
      },
    };
  }

  if (req.method === "POST" && path === "/v1/care-events") {
    const event = await addCareEvent(pool, auth, await readJson(req));
    log("care_event.added", { requestId, householdId: auth.householdId, eventId: event.id });
    return { status: 201, body: { careEvent: event } };
  }

  const careEventPath = path.match(/^\/v1\/care-events\/([^/]+)$/);
  if (req.method === "DELETE" && careEventPath) {
    const removed = await removeCareEvent(pool, auth, decodeURIComponent(careEventPath[1]));
    if (!removed) return { status: 404, body: { error: "Care event not found" } };
    log("care_event.removed", { requestId, householdId: auth.householdId });
    return { status: 200, body: { ok: true } };
  }

  if (req.method === "POST" && path === "/v1/auth/apple/link") {
    const body = await readJson(req);
    const linked = await linkAppleAccount(pool, auth, body.appleUserId);
    log("auth.apple_linked", { requestId, householdId: auth.householdId });
    return { status: 200, body: linked };
  }

  if (req.method === "POST" && path === "/v1/devices/register") {
    const registered = await registerDevice(pool, auth, await readJson(req));
    log("device.registered", { requestId, householdId: auth.householdId });
    return { status: 200, body: registered };
  }

  if (req.method === "POST" && path === "/v1/members/leave") {
    const left = await leaveHousehold(pool, auth);
    log("member.left", { requestId, householdId: auth.householdId, memberId: auth.memberId });
    return { status: 200, body: left };
  }

  if (req.method === "GET" && path === "/v1/export") {
    const data = await exportHouseholdData(pool, auth);
    if (!data) return { status: 404, body: { error: "Household not found" } };
    log("export.completed", { requestId, householdId: auth.householdId });
    return { status: 200, body: data };
  }

  if (req.method === "POST" && path === "/v1/billing/plan") {
    const body = await readJson(req);
    const plan = await setPlan(pool, auth, body.plan);
    if (!plan) return { status: 400, body: { error: "Plan must be yearly or monthly" } };
    return { status: 200, body: { plan } };
  }

  if (req.method === "POST" && path === "/v1/billing/trial") {
    return { status: 200, body: await startTrial(pool, auth) };
  }

  return { status: 404, body: { error: "Not found" } };
}

await connectWithRetry();
await migrate(pool, log);

const port = Number(process.env.PORT) || 3000;
server.listen(port, "0.0.0.0", () => {
  log("server.started", { port });
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    log("server.stopping", { signal });
    server.close(() => {
      pool.end().then(() => process.exit(0));
    });
  });
}
