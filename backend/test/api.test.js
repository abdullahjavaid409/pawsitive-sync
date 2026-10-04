/**
 * API integration tests against a real local Postgres. Starts its own server
 * on a random port (never 3100, never production).
 *
 *   TEST_DATABASE_URL=postgres://localhost/pawsitive_qa node --test backend/test/
 *
 * Every request carries its own X-Forwarded-For so the per-IP rate limits
 * (10 creates/joins a minute) never trip during the matrix.
 */
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import pg from "pg";
import { createPushSender } from "../push.js";
import { moveHouseholdProToOwners, notifyHouseholdOnDose } from "../db.js";

const databaseUrl = process.env.TEST_DATABASE_URL || "postgres://localhost/pawsitive_qa";
const backendDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const port = 3300 + Math.floor(Math.random() * 600);
const base = `http://127.0.0.1:${port}`;
const webhookSecret = "test-webhook-secret";
let server;
let pool;

before(async () => {
  pool = new pg.Pool({ connectionString: databaseUrl, max: 3 });
  server = spawn(process.execPath, ["server.js"], {
    cwd: backendDir,
    env: {
      ...process.env,
      DATABASE_URL: databaseUrl,
      PORT: String(port),
      REVENUECAT_WEBHOOK_SECRET: webhookSecret,
      REVENUECAT_SECRET_KEY: "",
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
  await pool?.end();
});

async function call(method, path, { token, body } = {}) {
  const headers = {
    "content-type": "application/json",
    "x-forwarded-for": `10.${[1, 2, 3].map(() => randomBytes(1)[0]).join(".")}`,
  };
  if (token) headers.authorization = `Bearer ${token}`;
  const response = await fetch(`${base}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : {} };
}

const today = "2026-10-04";

/** Owner "Sam" + caregiver "Dan" + app sitter "Sara", one pet, one medicine. */
async function household() {
  const created = await call("POST", "/v1/households", {
    body: {
      owner: { id: "you", name: "Sam" },
      pets: [{ id: "pet-1", name: "Miso", species: "cat" }],
      medications: [
        { id: "med-1", petId: "pet-1", name: "Insulin", amount: "2 u", parts: ["morning", "evening"], supplyTotal: 30, startDay: "2026-01-01" },
      ],
      logs: [],
    },
  });
  assert.equal(created.status, 201);
  const code = created.body.household.inviteCode;
  const caregiver = await call("POST", "/v1/join", { body: { code, name: "Dan" } });
  const sitter = await call("POST", "/v1/join", { body: { code, name: "Sara", role: "sitter" } });
  const extra = await call("POST", "/v1/join", { body: { code, name: "Extra" } });
  assert.equal(caregiver.status, 201);
  assert.equal(sitter.status, 201);
  return {
    id: created.body.household.id,
    code,
    owner: { token: created.body.token, id: "you" },
    caregiver: { token: caregiver.body.token, id: caregiver.body.memberId },
    sitter: { token: sitter.body.token, id: sitter.body.memberId },
    extra: { token: extra.body.token, id: extra.body.memberId },
  };
}

let webhookClock = Date.now();
/** A header-verified RevenueCat webhook for one member. */
async function webhook(house, memberId, type, { expiresInMs = 30 * 86_400_000, at } = {}) {
  webhookClock += 1000;
  const response = await fetch(`${base}/v1/webhooks/revenuecat`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${webhookSecret}`, "x-forwarded-for": "10.9.9.9" },
    body: JSON.stringify({
      event: {
        type,
        app_user_id: `${house.id}:${memberId}`,
        entitlement_ids: ["pro"],
        event_timestamp_ms: at ?? webhookClock,
        expiration_at_ms: Date.now() + expiresInMs,
        product_id: "pawsitive_yearly",
      },
    }),
  });
  return response.json();
}

async function isPro(token) {
  return (await call("GET", "/v1/household", { token })).body.household.isPro;
}

describe("role matrix (role × route)", () => {
  /** Each route: who may call it, and the request. Roles run sitter → caregiver → owner. */
  const routes = [
    { name: "GET /v1/household", allowed: ["owner", "caregiver", "sitter"], req: () => ["GET", "/v1/household"] },
    { name: "POST /v1/logs", allowed: ["owner", "caregiver", "sitter"], req: (h, role) => ["POST", "/v1/logs", { id: `log-${role}`, medicationId: "med-1", part: "morning", day: today, outcome: "given", timeLabel: "8:02 AM" }] },
    { name: "POST /v1/pets", allowed: ["owner", "caregiver"], req: () => ["POST", "/v1/pets", { id: "pet-2", name: "Pip", species: "dog" }] },
    { name: "PATCH /v1/pets/:id", allowed: ["owner", "caregiver"], req: () => ["PATCH", "/v1/pets/pet-1", { name: "Miso", species: "cat" }] },
    { name: "POST /v1/pets/:id/photo/upload", allowed: ["owner", "caregiver"], req: () => ["POST", "/v1/pets/pet-1/photo/upload", { bytes: 1000 }] },
    { name: "DELETE /v1/pets/:id/photo", allowed: ["owner", "caregiver"], req: () => ["DELETE", "/v1/pets/pet-1/photo"] },
    { name: "POST /v1/medications", allowed: ["owner", "caregiver"], req: () => ["POST", "/v1/medications", { id: "med-2", petId: "pet-1", name: "Gaba", parts: ["evening"], startDay: today }] },
    { name: "POST /v1/medications/:id/refill", allowed: ["owner", "caregiver"], req: () => ["POST", "/v1/medications/med-1/refill"] },
    { name: "DELETE /v1/medications/:id", allowed: ["owner"], req: () => ["DELETE", "/v1/medications/med-1"] },
    { name: "POST /v1/care-events", allowed: ["owner", "caregiver"], req: () => ["POST", "/v1/care-events", { id: "evt-1", petId: "pet-1", title: "Vet", kind: "vetVisit", dueDay: today }] },
    { name: "DELETE /v1/care-events/:id", allowed: ["owner", "caregiver"], req: () => ["DELETE", "/v1/care-events/evt-1"] },
    { name: "POST /v1/invite/rotate", allowed: ["owner"], req: () => ["POST", "/v1/invite/rotate"] },
    { name: "POST /v1/sitter-links", allowed: ["owner"], req: () => ["POST", "/v1/sitter-links", { label: "Weekend" }] },
    { name: "GET /v1/sitter-links", allowed: ["owner"], req: () => ["GET", "/v1/sitter-links"] },
    { name: "DELETE /v1/sitter-links/:id", allowed: ["owner"], req: () => ["DELETE", "/v1/sitter-links/slink-none"] },
    { name: "PATCH /v1/members/:id", allowed: ["owner"], req: (h) => ["PATCH", `/v1/members/${h.extra.id}`, { role: "sitter" }] },
    { name: "DELETE /v1/members/:id", allowed: ["owner"], req: (h) => ["DELETE", `/v1/members/${h.extra.id}`] },
    { name: "POST /v1/billing/plan", allowed: ["owner"], req: () => ["POST", "/v1/billing/plan", { plan: "monthly" }] },
    { name: "POST /v1/billing/trial", allowed: ["owner", "caregiver", "sitter"], req: () => ["POST", "/v1/billing/trial"] },
    { name: "POST /v1/devices/register", allowed: ["owner", "caregiver", "sitter"], req: () => ["POST", "/v1/devices/register", { platform: "ios", token: "local:1" }] },
    { name: "GET /v1/export", allowed: ["owner", "caregiver"], req: () => ["GET", "/v1/export"] },
    { name: "POST /v1/auth/apple/link", allowed: ["owner"], req: () => ["POST", "/v1/auth/apple/link", { identityToken: "x" }] },
  ];

  for (const route of routes) {
    test(route.name, async () => {
      const house = await household();
      for (const role of ["sitter", "caregiver", "owner"]) {
        const [method, path, body] = route.req(house, role);
        const response = await call(method, path, { token: house[role].token, body });
        const forbidden = response.status === 403 && response.body.code === "role_forbidden";
        if (route.allowed.includes(role)) {
          assert.equal(forbidden, false, `${role} should be allowed: ${response.status} ${JSON.stringify(response.body)}`);
        } else {
          assert.equal(forbidden, true, `${role} should be forbidden: ${response.status} ${JSON.stringify(response.body)}`);
          // Plain words, and still an `error` string for apps already in the field.
          assert.match(response.body.error, /owner|Sitters can view and log doses only/);
        }
      }
    });
  }

  test("owner-only routes say so in plain words", async () => {
    const house = await household();
    const response = await call("POST", "/v1/invite/rotate", { token: house.caregiver.token });
    assert.deepEqual(response.body, { error: "Only the household owner can do that.", code: "role_forbidden" });
  });

  test("sync/batch rejects only the forbidden op and keeps the rest", async () => {
    const house = await household();
    const batch = await call("POST", "/v1/sync/batch", {
      token: house.caregiver.token,
      body: {
        operations: [
          { id: "op-1", type: "logDose", payload: { id: "log-b1", medicationId: "med-1", part: "morning", day: today, outcome: "given", timeLabel: "8:00 AM" } },
          { id: "op-2", type: "removeMedication", payload: { id: "med-1" } },
          { id: "op-3", type: "refill", payload: { id: "med-1" } },
        ],
      },
    });
    assert.equal(batch.status, 200);
    assert.deepEqual(batch.body.results.map((result) => result.status), ["ok", "error", "ok"]);
    assert.equal(batch.body.results[1].code, "role_forbidden");
    assert.equal(batch.body.results[1].message, "Only the household owner can do that.");
    // The medicine is still active for everyone.
    assert.ok(batch.body.household.medications.some((m) => m.id === "med-1"));

    const sitterBatch = await call("POST", "/v1/sync/batch", {
      token: house.sitter.token,
      body: { operations: [{ id: "op-4", type: "addPet", payload: { id: "pet-9", name: "No", species: "dog" } }] },
    });
    assert.equal(sitterBatch.body.results[0].status, "error");
    assert.equal(sitterBatch.body.results[0].code, "role_forbidden");
  });

  test("a role changed on another phone applies on the very next request", async () => {
    const house = await household();
    assert.equal((await call("GET", "/v1/household", { token: house.caregiver.token })).body.role, "caregiver");
    const changed = await call("PATCH", `/v1/members/${house.caregiver.id}`, { token: house.owner.token, body: { role: "sitter" } });
    assert.equal(changed.status, 200);
    assert.equal(changed.body.member.role, "sitter");
    const denied = await call("POST", "/v1/medications/med-1/refill", { token: house.caregiver.token });
    assert.equal(denied.status, 403);
    assert.equal(denied.body.code, "role_forbidden");
    const snapshot = await call("GET", "/v1/household", { token: house.caregiver.token });
    assert.equal(snapshot.body.role, "sitter");
    assert.equal(snapshot.body.members.find((m) => m.isYou).role, "sitter");
  });
});

describe("member management", () => {
  test("owner can't demote themselves, can't promote anyone to owner; unknown member is 404", async () => {
    const house = await household();
    const self = await call("PATCH", "/v1/members/you", { token: house.owner.token, body: { role: "caregiver" } });
    assert.equal(self.status, 400);
    const promote = await call("PATCH", `/v1/members/${house.caregiver.id}`, { token: house.owner.token, body: { role: "owner" } });
    assert.equal(promote.status, 400);
    const missing = await call("PATCH", "/v1/members/member-nobody", { token: house.owner.token, body: { role: "sitter" } });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, "member_gone");
    const owners = (await call("GET", "/v1/household", { token: house.owner.token })).body.members.filter((m) => m.role === "owner");
    assert.equal(owners.length, 1);
  });

  test("removing a member: token dies with a reason, push tokens go, logs stay; repeat is 404", async () => {
    const house = await household();
    await call("POST", "/v1/logs", {
      token: house.caregiver.token,
      body: { id: "log-dan", medicationId: "med-1", part: "morning", day: today, outcome: "given", timeLabel: "8:02 AM" },
    });
    await call("POST", "/v1/devices/register", {
      token: house.caregiver.token,
      body: { platform: "ios", token: `apns:${"cd".repeat(32)}`, environment: "sandbox" },
    });
    const removed = await call("DELETE", `/v1/members/${house.caregiver.id}`, { token: house.owner.token });
    assert.equal(removed.status, 200);

    const after = await call("GET", "/v1/household", { token: house.caregiver.token });
    assert.equal(after.status, 401);
    assert.equal(after.body.code, "member_removed");

    const tokens = await pool.query("SELECT 1 FROM device_tokens WHERE household_id = $1 AND member_id = $2", [house.id, house.caregiver.id]);
    assert.equal(tokens.rowCount, 0);
    const snapshot = (await call("GET", "/v1/household", { token: house.owner.token })).body;
    assert.ok(!snapshot.members.some((m) => m.id === house.caregiver.id));
    assert.ok(snapshot.logs.some((log) => log.id === "log-dan" && log.memberId === house.caregiver.id));

    const again = await call("DELETE", `/v1/members/${house.caregiver.id}`, { token: house.owner.token });
    assert.equal(again.status, 404);
    const self = await call("DELETE", "/v1/members/you", { token: house.owner.token });
    assert.equal(self.status, 400);
  });
});

describe("invite codes", () => {
  test("only the owner sees the code, with an expiry 7 days out", async () => {
    const house = await household();
    const owner = (await call("GET", "/v1/household", { token: house.owner.token })).body.household;
    assert.equal(owner.inviteCode, house.code);
    const days = (new Date(owner.inviteExpiresAt).getTime() - Date.now()) / 86_400_000;
    assert.ok(days > 6.9 && days <= 7, `expires in ${days} days`);
    const caregiver = (await call("GET", "/v1/household", { token: house.caregiver.token })).body.household;
    assert.equal(caregiver.inviteCode, "");
    assert.equal(caregiver.inviteExpiresAt, undefined);
  });

  test("an expired code is refused with a friendly 404", async () => {
    const house = await household();
    await pool.query("UPDATE households SET invite_created_at = now() - interval '8 days' WHERE id = $1", [house.id]);
    const joined = await call("POST", "/v1/join", { body: { code: house.code, name: "Late" } });
    assert.equal(joined.status, 404);
    assert.deepEqual(joined.body, { error: "That invite code expired. Ask for a new one.", code: "invite_expired" });
  });

  test("rotate: new code works, old one stops at once; double rotate leaves the last", async () => {
    const house = await household();
    const first = await call("POST", "/v1/invite/rotate", { token: house.owner.token });
    const second = await call("POST", "/v1/invite/rotate", { token: house.owner.token });
    assert.equal(first.status, 200);
    assert.notEqual(first.body.inviteCode, house.code);
    assert.ok(first.body.inviteExpiresAt);
    assert.equal((await call("POST", "/v1/join", { body: { code: house.code, name: "Old" } })).status, 404);
    assert.equal((await call("POST", "/v1/join", { body: { code: first.body.inviteCode, name: "Mid" } })).status, 404);
    assert.equal((await call("POST", "/v1/join", { body: { code: second.body.inviteCode, name: "New" } })).status, 201);
  });
});

describe("sitter links", () => {
  test("list, last used, revoke at once, expired cleanup", async () => {
    const house = await household();
    await webhook(house, "you", "INITIAL_PURCHASE");
    const a = await call("POST", "/v1/sitter-links", { token: house.owner.token, body: { label: "Weekend" } });
    const b = await call("POST", "/v1/sitter-links", { token: house.owner.token, body: { label: "Neighbour" } });
    assert.equal(a.status, 201);
    let list = (await call("GET", "/v1/sitter-links", { token: house.owner.token })).body.links;
    assert.deepEqual(list.map((link) => link.label).sort(), ["Neighbour", "Weekend"]);
    assert.ok(list.every((link) => link.expiresAt && link.createdAt && link.lastUsedAt === null));

    assert.equal((await call("GET", `/v1/sitter/view?day=${today}&hour=9`, { token: a.body.token })).status, 200);
    for (let i = 0; i < 20; i += 1) {
      list = (await call("GET", "/v1/sitter-links", { token: house.owner.token })).body.links;
      if (list.find((link) => link.label === "Weekend").lastUsedAt) break;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    const weekend = list.find((link) => link.label === "Weekend");
    assert.ok(weekend.lastUsedAt, "last used is stamped");

    const revoked = await call("DELETE", `/v1/sitter-links/${weekend.id}`, { token: house.owner.token });
    assert.deepEqual(revoked.body, { ok: true, revoked: true });
    assert.equal((await call("GET", `/v1/sitter/view?day=${today}&hour=9`, { token: a.body.token })).status, 401);
    const again = await call("DELETE", `/v1/sitter-links/${weekend.id}`, { token: house.owner.token });
    assert.deepEqual(again.body, { ok: true, revoked: false });
    let members = (await call("GET", "/v1/household", { token: house.owner.token })).body.members;
    assert.ok(!members.some((m) => m.name === "Weekend"), "revoked link's sitter member is gone");

    // Expire the other link: it disappears from the list and its member is cleaned up.
    await pool.query("UPDATE sitter_links SET expires_at = now() - interval '1 minute' WHERE household_id = $1", [house.id]);
    list = (await call("GET", "/v1/sitter-links", { token: house.owner.token })).body.links;
    assert.equal(list.length, 0);
    members = (await call("GET", "/v1/household", { token: house.owner.token })).body.members;
    assert.ok(!members.some((m) => m.name === "Neighbour"));
    assert.equal((await call("GET", `/v1/sitter/view?day=${today}&hour=9`, { token: b.body.token })).status, 401);
  });

  test("a browser sitter member's role can't be changed", async () => {
    const house = await household();
    await webhook(house, "you", "INITIAL_PURCHASE");
    await call("POST", "/v1/sitter-links", { token: house.owner.token, body: { label: "Browser" } });
    const sitterMember = (await call("GET", "/v1/household", { token: house.owner.token })).body.members.find((m) => m.name === "Browser");
    const changed = await call("PATCH", `/v1/members/${sitterMember.id}`, { token: house.owner.token, body: { role: "caregiver" } });
    assert.equal(changed.status, 400);
  });
});

describe("Pro per member", () => {
  test("two payers: one expires → still Pro; last one expires → Free", async () => {
    const house = await household();
    assert.equal(await isPro(house.owner.token), false);
    await webhook(house, "you", "INITIAL_PURCHASE");
    await webhook(house, house.caregiver.id, "INITIAL_PURCHASE");
    assert.equal(await isPro(house.sitter.token), true);
    await webhook(house, "you", "EXPIRATION");
    assert.equal(await isPro(house.owner.token), true, "caregiver still pays");
    const members = (await call("GET", "/v1/household", { token: house.owner.token })).body.members;
    assert.equal(members.find((m) => m.id === house.caregiver.id).paysForPro, true);
    assert.equal(members.find((m) => m.id === "you").paysForPro, undefined);
    await webhook(house, house.caregiver.id, "EXPIRATION");
    assert.equal(await isPro(house.owner.token), false);
  });

  test("out-of-order events are judged per member", async () => {
    const house = await household();
    const t = Date.now();
    // Caregiver: EXPIRATION (newer) arrives before a delayed RENEWAL (older) → stays expired.
    await webhook(house, house.caregiver.id, "INITIAL_PURCHASE", { at: t - 10_000 });
    await webhook(house, house.caregiver.id, "EXPIRATION", { at: t });
    const stale = await webhook(house, house.caregiver.id, "RENEWAL", { at: t - 5000 });
    assert.equal(stale.reason, "stale_event");
    assert.equal(await isPro(house.owner.token), false);
    // Owner's older event isn't "stale" just because the caregiver had a newer one.
    const ownerEvent = await webhook(house, "you", "INITIAL_PURCHASE", { at: t - 20_000 });
    assert.equal(ownerEvent.status, "ok");
    assert.equal(await isPro(house.owner.token), true);
  });

  test("a removed payer no longer counts", async () => {
    const house = await household();
    await webhook(house, house.extra.id, "INITIAL_PURCHASE");
    assert.equal(await isPro(house.owner.token), true);
    await call("DELETE", `/v1/members/${house.extra.id}`, { token: house.owner.token });
    assert.equal(await isPro(house.owner.token), false);
  });

  test("migration moves the old household flag onto the owner", async () => {
    const house = await household();
    await pool.query(
      "UPDATE households SET is_pro = true, rc_expires_at = now() + interval '20 days', rc_event_at = now() WHERE id = $1",
      [house.id],
    );
    assert.equal(await isPro(house.owner.token), false, "the household flag alone no longer counts");
    await moveHouseholdProToOwners(pool, house.id);
    assert.equal(await isPro(house.caregiver.token), true);
    const owner = await pool.query("SELECT rc_is_pro FROM members WHERE household_id = $1 AND id = 'you'", [house.id]);
    assert.equal(owner.rows[0].rc_is_pro, true);
  });
});

describe("push fan-out", () => {
  const apnsA = `apns:${"aa".repeat(32)}`;
  const fcmB = "fcm:android-registration-token-b-123456";
  const apnsOwner = `apns:${"ee".repeat(32)}`;

  function fakeSender(invalidTokens = new Set()) {
    const sent = [];
    return {
      sent,
      canSend: (device) => device.token.startsWith("apns:") || device.token.startsWith("fcm:"),
      noteNotConfigured: () => {},
      send: async (device, message) => {
        sent.push({ token: device.token, message });
        return invalidTokens.has(device.token) ? { ok: false, invalid: true, reason: "Unregistered" } : { ok: true };
      },
    };
  }

  test("registration stores only real tokens and moves a token between members", async () => {
    const house = await household();
    const fake = await call("POST", "/v1/devices/register", { token: house.caregiver.token, body: { platform: "ios", token: "local:123" } });
    assert.equal(fake.status, 200);
    assert.equal(fake.body.stored, false);
    const real = await call("POST", "/v1/devices/register", {
      token: house.caregiver.token,
      body: { platform: "ios", token: apnsA.toUpperCase().replace("APNS:", "apns:"), environment: "sandbox" },
    });
    assert.equal(real.body.stored, true);
    assert.equal(real.body.delivery, false, "test server has no APNs key");
    const row = await pool.query("SELECT environment, token FROM device_tokens WHERE household_id = $1 AND member_id = $2", [house.id, house.caregiver.id]);
    assert.deepEqual(row.rows, [{ environment: "sandbox", token: apnsA }]);
    // Same phone, now signed in as the sitter: the caregiver row goes.
    await call("POST", "/v1/devices/register", { token: house.sitter.token, body: { platform: "ios", token: apnsA } });
    const owners = await pool.query("SELECT member_id FROM device_tokens WHERE token = $1", [apnsA]);
    assert.deepEqual(owners.rows.map((r) => r.member_id), [house.sitter.id]);
  });

  test("a dose notifies everyone else (iOS: alert + silent), never the logger; invalid tokens are deleted", async () => {
    const house = await household();
    await call("POST", "/v1/devices/register", { token: house.caregiver.token, body: { platform: "ios", token: apnsA } });
    await call("POST", "/v1/devices/register", { token: house.sitter.token, body: { platform: "android", token: fcmB } });
    await call("POST", "/v1/devices/register", { token: house.owner.token, body: { platform: "ios", token: apnsOwner } });
    const sender = fakeSender(new Set([fcmB]));
    const logs = [];
    await notifyHouseholdOnDose(
      pool,
      { householdId: house.id, memberId: "you" },
      { id: "log-p1", medicationId: "med-1", part: "morning", day: today, outcome: "given", timeLabel: "8:02 AM" },
      (event, fields) => logs.push({ event, fields }),
      sender,
    );
    assert.ok(!sender.sent.some((s) => s.token === apnsOwner), "never the member who logged");
    const toCaregiver = sender.sent.filter((s) => s.token === apnsA);
    assert.equal(toCaregiver.length, 2);
    assert.deepEqual(toCaregiver[0].message.alert, { title: "Dose logged", body: "Sam gave Miso's Insulin · 8:02 AM" });
    assert.equal(toCaregiver[1].message.background, true);
    assert.deepEqual(toCaregiver[1].message.data.doses, [
      { logId: "log-p1", medicationId: "med-1", part: "morning", day: today, outcome: "given" },
    ]);
    assert.equal(sender.sent.filter((s) => s.token === fcmB).length, 1);
    const left = await pool.query("SELECT token FROM device_tokens WHERE household_id = $1 ORDER BY token", [house.id]);
    assert.deepEqual(left.rows.map((r) => r.token), [apnsA, apnsOwner].sort());
    assert.ok(logs.some((entry) => entry.event === "push.sent" && entry.fields.removed === 1));
  });

  test("a batch sends one summary", async () => {
    const house = await household();
    await call("POST", "/v1/devices/register", { token: house.caregiver.token, body: { platform: "ios", token: apnsA } });
    const sender = fakeSender();
    await notifyHouseholdOnDose(
      pool,
      { householdId: house.id, memberId: "you" },
      [
        { id: "l1", medicationId: "med-1", part: "morning", day: today, outcome: "given", timeLabel: "8:00 AM" },
        { id: "l2", medicationId: "med-1", part: "evening", day: today, outcome: "skipped", timeLabel: "8:00 PM" },
      ],
      () => {},
      sender,
    );
    assert.equal(sender.sent.length, 2); // one alert + one silent to the single device
    assert.equal(sender.sent[0].message.alert.body, "Sam logged 2 doses");
    assert.equal(sender.sent[1].message.data.doses.length, 2);
  });

  test("not configured: skips sending and logs push.not_configured once", async () => {
    const house = await household();
    await call("POST", "/v1/devices/register", { token: house.caregiver.token, body: { platform: "ios", token: apnsA } });
    const sender = createPushSender({ env: {}, connect: () => assert.fail("must not connect") });
    const logs = [];
    const logFn = (event, fields) => logs.push({ event, fields });
    const entry = { id: "l9", medicationId: "med-1", part: "morning", day: today, outcome: "given", timeLabel: "8:00 AM" };
    await notifyHouseholdOnDose(pool, { householdId: house.id, memberId: "you" }, entry, logFn, sender);
    await notifyHouseholdOnDose(pool, { householdId: house.id, memberId: "you" }, entry, logFn, sender);
    assert.deepEqual(logs.map((l) => l.event), ["push.not_configured"]);
  });
});

describe("older apps keep working", () => {
  test("join without a role, snapshots without new fields, 403 still has an error string", async () => {
    const house = await household();
    const snapshot = (await call("GET", "/v1/household", { token: house.caregiver.token })).body;
    for (const key of ["household", "memberId", "members", "pets", "medications", "logs", "careEvents"]) {
      assert.ok(key in snapshot, key);
    }
    assert.equal(typeof snapshot.household.isPro, "boolean");
    const denied = await call("DELETE", "/v1/medications/med-1", { token: house.caregiver.token });
    assert.equal(typeof denied.body.error, "string");
    const freePro = await call("POST", "/v1/sitter-links", { token: house.owner.token, body: {} });
    assert.equal(freePro.status, 403);
    assert.equal(freePro.body.error, "Browser sitter links need Pawsitive Pro.");
    assert.equal(freePro.body.code, "pro_required");
  });
});
