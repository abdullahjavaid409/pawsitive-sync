import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import {
  InputError,
  addMedication,
  addPet,
  updatePet,
  archiveMedication,
  createHousehold,
  createPool,
  joinHousehold,
  loadHousehold,
  logDose,
  memberForToken,
  migrate,
  refillMedication,
  setPlan,
  startTrial,
} from "./db.js";

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
    send(res, result.status, result.body);
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

async function snapshot(auth) {
  return loadHousehold(pool, auth);
}

async function route(req, url, requestId) {
  const path = url.pathname;
  if (req.method === "GET" && path === "/health") {
    await pool.query("SELECT 1");
    return { status: 200, body: { ok: true, service: "pawsitive-api", version: 2 } };
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
    return { status: 201, body: result };
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
