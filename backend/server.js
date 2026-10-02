import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import {
  createPool,
  loadHousehold,
  logDose,
  migrate,
  refillMedication,
  seedIfEmpty,
  setPlan,
  skipDose,
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

const maxBodyBytes = 4096;
const rateWindowMs = 60_000;
const rateLimit = 30;
const hits = new Map();

function safeId(value) {
  return /^[a-z0-9-]{1,40}$/.test(value);
}

function clientKey(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim().slice(0, 64);
  }
  return req.socket.remoteAddress ?? "unknown";
}

function limited(req) {
  const now = Date.now();
  const key = clientKey(req);
  const current = hits.get(key);
  if (!current || current.resetAt <= now) {
    if (hits.size > 500) hits.clear();
    hits.set(key, { count: 1, resetAt: now + rateWindowMs });
    return false;
  }
  current.count += 1;
  return current.count > rateLimit;
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBodyBytes) {
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

const server = createServer(async (req, res) => {
  const started = Date.now();
  const requestId = req.headers["x-request-id"]?.toString() || randomUUID();
  const url = new URL(req.url ?? "/", "http://localhost");
  res.setHeader("x-request-id", requestId);
  log("request.received", { requestId, method: req.method, path: url.pathname });

  if (url.pathname !== "/health" && limited(req)) {
    send(res, 429, { error: "Too many requests" });
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
      status === 400 ? "Invalid JSON" : status === 413 ? "Body too large" : "Internal error";
    send(res, status, { error: message });
    log("request.failed", {
      requestId,
      method: req.method,
      path: url.pathname,
      status,
      durationMs: Date.now() - started,
    });
  }
});

async function route(req, url, requestId) {
  if (req.method === "GET" && url.pathname === "/health") {
    await pool.query("SELECT 1");
    return { status: 200, body: { ok: true, service: "pawsitive-api", database: "postgres" } };
  }
  if (req.method === "GET" && url.pathname === "/v1/household") {
    return { status: 200, body: await loadHousehold(pool) };
  }

  const doseLog = url.pathname.match(/^\/v1\/doses\/([^/]+)\/log$/);
  if (req.method === "POST" && doseLog) {
    const body = await readJson(req);
    const doseId = decodeURIComponent(doseLog[1]);
    if (!safeId(doseId)) {
      return { status: 400, body: { error: "Unknown dose" } };
    }
    const saved = await logDose(pool, doseId, body);
    if (!saved) {
      log("dose.log_rejected", { requestId, doseId, memberId: body.memberId ?? null });
      return { status: 400, body: { error: "Dose, member, amount, and time are required" } };
    }
    log("dose.logged", { requestId, doseId, memberId: body.memberId, outcome: body.outcome ?? "smooth" });
    return { status: 200, body: saved };
  }

  const doseSkip = url.pathname.match(/^\/v1\/doses\/([^/]+)\/skip$/);
  if (req.method === "POST" && doseSkip) {
    const doseId = decodeURIComponent(doseSkip[1]);
    if (!safeId(doseId)) {
      return { status: 400, body: { error: "Unknown dose" } };
    }
    const removed = await skipDose(pool, doseId);
    if (!removed) {
      log("dose.skip_rejected", { requestId, doseId });
      return { status: 404, body: { error: "Dose not found" } };
    }
    log("dose.skipped", { requestId, doseId });
    return { status: 200, body: { doseId } };
  }

  const refill = url.pathname.match(/^\/v1\/medications\/([^/]+)\/refill$/);
  if (req.method === "POST" && refill) {
    const medicationId = decodeURIComponent(refill[1]);
    if (!safeId(medicationId)) {
      return { status: 400, body: { error: "Unknown medication" } };
    }
    const medication = await refillMedication(pool, medicationId);
    if (!medication) {
      log("medication.refill_rejected", { requestId, medicationId });
      return { status: 404, body: { error: "Medication not found" } };
    }
    log("medication.refilled", { requestId, medicationId, dosesLeft: medication.dosesLeft });
    return { status: 200, body: { medication } };
  }

  if (req.method === "POST" && url.pathname === "/v1/billing/plan") {
    const body = await readJson(req);
    const plan = await setPlan(pool, body.plan);
    if (!plan) {
      log("billing.plan_rejected", { requestId, plan: body.plan ?? null });
      return { status: 400, body: { error: "Plan must be yearly or monthly" } };
    }
    log("billing.plan_set", { requestId, plan });
    return { status: 200, body: { plan } };
  }

  if (req.method === "POST" && url.pathname === "/v1/billing/trial") {
    const billing = await startTrial(pool);
    log("billing.trial_started", { requestId });
    return { status: 200, body: billing };
  }

  return { status: 404, body: { error: "Not found" } };
}

await connectWithRetry();
await migrate(pool, log);
await seedIfEmpty(pool, log);

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
