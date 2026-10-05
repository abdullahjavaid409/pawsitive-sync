/**
 * Header-less RevenueCat webhooks are answered by a REST lookup. A lookup that
 * lags a fresh purchase (or a forged ping) must never block the real signed
 * webhook, and must not revoke Pro that was set in the last 10 minutes.
 *
 *   TEST_DATABASE_URL=postgres://localhost/pawsitive_qa node --test backend/test/*.test.js
 */
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import pg from "pg";

const databaseUrl = process.env.TEST_DATABASE_URL || "postgres://localhost/pawsitive_qa";
const backendDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const port = 3900 + Math.floor(Math.random() * 500);
const base = `http://127.0.0.1:${port}`;
const secret = "lookup-test-secret";

/** customer id → active entitlement expiry (ms), or absent = no Pro (404). */
const rcActive = new Map();
let fake;
let fakePort;
let server;
let pool;

before(async () => {
  fake = createServer((req, res) => {
    const match = req.url.match(/\/customers\/([^/]+)\/active_entitlements/);
    const id = match ? decodeURIComponent(match[1]) : "";
    if (!rcActive.has(id)) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ items: [{ entitlement_id: "entld3f5604b68", expires_at: rcActive.get(id) }] }));
  });
  await new Promise((resolve) => fake.listen(0, "127.0.0.1", resolve));
  fakePort = fake.address().port;
  pool = new pg.Pool({ connectionString: databaseUrl, max: 2 });
  server = spawn(process.execPath, ["server.js"], {
    cwd: backendDir,
    env: {
      ...process.env,
      DATABASE_URL: databaseUrl,
      PORT: String(port),
      REVENUECAT_WEBHOOK_SECRET: secret,
      REVENUECAT_SECRET_KEY: "sk_test_fake",
      REVENUECAT_API_BASE: `http://127.0.0.1:${fakePort}`,
      APNS_KEY_P8: "",
      FCM_SERVICE_ACCOUNT_JSON: "",
    },
    stdio: ["ignore", "pipe", "inherit"],
  });
  server.stdout.resume();
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      if ((await fetch(`${base}/health`)).ok) return;
    } catch {
      // not up yet
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error("server did not start");
});

after(async () => {
  server?.kill("SIGTERM");
  fake?.close();
  await pool?.end();
});

const ip = () => `10.${[1, 2, 3].map(() => randomBytes(1)[0]).join(".")}`;

async function household() {
  const created = await fetch(`${base}/v1/households`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": ip() },
    body: JSON.stringify({ owner: { id: "you", name: "Sam" }, pets: [], medications: [], logs: [] }),
  }).then((r) => r.json());
  return { id: created.household.id, token: created.token };
}

async function isPro(house) {
  const body = await fetch(`${base}/v1/household`, {
    headers: { authorization: `Bearer ${house.token}`, "x-forwarded-for": ip() },
  }).then((r) => r.json());
  return body.household.isPro;
}

/** A webhook for the owner; `signed` adds the Authorization header. */
async function webhook(house, type, { signed, at }) {
  const headers = { "content-type": "application/json", "x-forwarded-for": "10.9.9.9" };
  if (signed) headers.authorization = `Bearer ${secret}`;
  return fetch(`${base}/v1/webhooks/revenuecat`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      event: {
        type,
        app_user_id: `${house.id}:you`,
        entitlement_ids: ["pro"],
        event_timestamp_ms: at,
        expiration_at_ms: Date.now() + 30 * 86_400_000,
        product_id: "pawsitive_yearly",
      },
    }),
  }).then((r) => r.json());
}

test("a lagging (or forged) lookup never blocks the real purchase webhook", async () => {
  const house = await household();
  const boughtAt = Date.now() - 5000;
  // REST hasn't caught up: the header-less ping sees no Pro.
  const ping = await webhook(house, "INITIAL_PURCHASE", { signed: false, at: Date.now() });
  assert.equal(ping.status, "ok");
  assert.equal(await isPro(house), false);
  // The real signed webhook, timestamped at purchase (before the ping).
  const real = await webhook(house, "INITIAL_PURCHASE", { signed: true, at: boughtAt });
  assert.notEqual(real.reason, "stale_event");
  assert.equal(await isPro(house), true);
});

test("a lookup can’t revoke Pro set in the last 10 minutes; an older one it can", async () => {
  const house = await household();
  await webhook(house, "INITIAL_PURCHASE", { signed: true, at: Date.now() });
  assert.equal(await isPro(house), true);
  // RevenueCat REST says "no Pro" right away (lag, or a forged ping).
  await webhook(house, "EXPIRATION", { signed: false, at: Date.now() });
  assert.equal(await isPro(house), true, "fresh purchase kept");
  // The same answer about Pro from 11 minutes ago is trusted.
  await pool.query("UPDATE members SET rc_event_at = now() - interval '11 minutes' WHERE household_id = $1", [house.id]);
  await webhook(house, "EXPIRATION", { signed: false, at: Date.now() });
  assert.equal(await isPro(house), false);
});

test("a lookup that finds Pro grants it", async () => {
  const house = await household();
  rcActive.set(`${house.id}:you`, Date.now() + 86_400_000);
  await webhook(house, "RENEWAL", { signed: false, at: Date.now() });
  assert.equal(await isPro(house), true);
});
