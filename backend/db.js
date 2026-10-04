import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import pg from "pg";
import { fetchProEntitlement, proEntitlement } from "./revenuecat.js";
import { checkPhotoSize, deletePhoto, keyBelongsTo, newPhotoKey, photoExists, photosConfigured, presignUpload, presignView } from "./photos.js";
import { batchActions, requireRole, roles } from "./roles.js";
import { pushSender } from "./push.js";

const { Pool } = pg;

const schemaVersion = "8";

/**
 * RevenueCat REST lag after a fresh purchase: a lookup that says "inactive"
 * only revokes state older than this (a just-delivered webhook wins).
 */
const lookupRevokeAfterMs = 10 * 60 * 1000;

/** Invite codes stop working this long after they were made (or rotated). */
export const inviteTtlMs = 7 * 24 * 60 * 60 * 1000;

/**
 * One member's RevenueCat `pro` entitlement (members.rc_*). Pro only ever
 * comes from RevenueCat (webhook or a server-side subscriber lookup); free
 * trials are App Store intro offers, so they arrive as an active entitlement.
 */
function memberHasPro(row) {
  if (!row?.rc_is_pro) return false;
  // Ends exactly at the stored expiry, even if EXPIRATION never arrives. A
  // renewal moves the expiry first (RENEWAL webhook, retried by RevenueCat;
  // the payer's app also re-checks RevenueCat on sync), so no slack is
  // needed — and none means nobody keeps Pro after it ends.
  const expires = row.rc_expires_at;
  return expires == null || new Date(expires).getTime() > Date.now();
}

/**
 * When household Pro ends: the latest expiry among current payers, null
 * for a lifetime purchase, undefined when not Pro. Sent to apps so a phone
 * that is offline drops Pro on time without asking the server.
 */
function proUntil(memberRows) {
  const payers = (memberRows ?? []).filter(memberHasPro);
  if (payers.length === 0) return undefined;
  if (payers.some((row) => row.rc_expires_at == null)) return null;
  return new Date(Math.max(...payers.map((row) => new Date(row.rc_expires_at).getTime()))).toISOString();
}

/** Household Pro = any member currently entitled. One payer expiring never cancels another. */
function hasPro(memberRows) {
  return (memberRows ?? []).some(memberHasPro);
}

/** Household Pro straight from the members table (one indexed query). */
export async function householdHasPro(pool, householdId) {
  const result = await pool.query(
    "SELECT rc_is_pro, rc_expires_at FROM members WHERE household_id = $1 AND rc_is_pro",
    [householdId],
  );
  return hasPro(result.rows);
}
const parts = ["morning", "afternoon", "evening"];
const species = ["cat", "dog", "rabbit", "other"];
const outcomes = ["given", "skipped", "uncertain"];
const codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
/** Signed-in app members per household (sitter links don't count). */
const maxMembers = 30;

function envInt(name, fallback, min, max) {
  const value = Number.parseInt(process.env[name] ?? "", 10);
  return Number.isFinite(value) ? Math.min(Math.max(value, min), max) : fallback;
}

export function createPool(connectionString) {
  return new Pool({
    connectionString,
    // One request uses one connection (household reads are a single query), so
    // 10 per instance serves thousands of households and leaves room under
    // Postgres' max_connections for a second replica and psql.
    max: envInt("PG_POOL_MAX", 10, 1, 50),
    idleTimeoutMillis: 30_000,
    // Fail fast with a 500 instead of queueing forever when the pool is drained.
    connectionTimeoutMillis: 5_000,
    // A runaway query or a stuck transaction can't hold a connection hostage.
    statement_timeout: envInt("PG_STATEMENT_TIMEOUT_MS", 15_000, 1_000, 120_000),
    idle_in_transaction_session_timeout: 30_000,
    application_name: "pawsitive-api",
  });
}

const migrationLockKey = 72_041_101; // any constant; serialises boots of several replicas

export async function migrate(pool, log) {
  const started = Date.now();
  const client = await pool.connect();
  try {
    // Two replicas booting together must not run DDL at the same time.
    await client.query("SELECT pg_advisory_lock($1)", [migrationLockKey]);
    await migrateLocked(client);
  } finally {
    await client.query("SELECT pg_advisory_unlock($1)", [migrationLockKey]).catch(() => {});
    client.release();
  }
  log("db.migrated", { version: schemaVersion, durationMs: Date.now() - started });
}

/** CREATE INDEX CONCURRENTLY so a big table keeps taking writes while it builds. */
async function ensureIndexConcurrently(client, name, definition) {
  // A failed concurrent build leaves an INVALID index that IF NOT EXISTS would skip.
  const invalid = await client.query(
    `SELECT 1 FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
     WHERE c.relname = $1 AND NOT i.indisvalid`,
    [name],
  );
  if (invalid.rowCount > 0) await client.query(`DROP INDEX CONCURRENTLY IF EXISTS ${name}`);
  await client.query(`CREATE INDEX CONCURRENTLY IF NOT EXISTS ${name} ON ${definition}`);
}

/** `pool` here is the one locked client: every statement runs on it. */
async function migrateLocked(pool) {
  await pool.query("CREATE TABLE IF NOT EXISTS meta (key text PRIMARY KEY, value text NOT NULL)");
  const current = await pool.query("SELECT value FROM meta WHERE key = 'schema_version'");
  const fromVersion = current.rows[0]?.value ?? null;
  // Version 1 held one shared demo household with no owners; nothing in it is user data.
  // A missing version row alone is NOT proof of v1 (a partial restore could lose `meta`):
  // only drop when the v2+ `households` table doesn't exist either.
  const households = await pool.query("SELECT to_regclass('public.households') IS NOT NULL AS present");
  if (fromVersion === "1" || (fromVersion === null && !households.rows[0].present)) {
    await pool.query("DROP TABLE IF EXISTS activity, doses, medications, pets, members, settings CASCADE");
  }
  await pool.query(`
    CREATE TABLE IF NOT EXISTS households (
      id text PRIMARY KEY,
      invite_code text NOT NULL UNIQUE,
      is_pro boolean NOT NULL DEFAULT false,
      plan text NOT NULL DEFAULT 'yearly',
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS members (
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      id text NOT NULL,
      name text NOT NULL,
      role text NOT NULL,
      token_hash text UNIQUE,
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (household_id, id)
    );
    CREATE TABLE IF NOT EXISTS pets (
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      id text NOT NULL,
      name text NOT NULL,
      species text NOT NULL,
      age_years integer NOT NULL DEFAULT 0,
      weight_kg double precision NOT NULL DEFAULT 0,
      breed text NOT NULL DEFAULT '',
      sex text NOT NULL DEFAULT '',
      conditions jsonb NOT NULL DEFAULT '[]',
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (household_id, id)
    );
    CREATE TABLE IF NOT EXISTS medications (
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      id text NOT NULL,
      pet_id text NOT NULL,
      name text NOT NULL,
      amount text NOT NULL DEFAULT '',
      parts jsonb NOT NULL,
      supply_total integer NOT NULL DEFAULT 0,
      doses_left integer NOT NULL DEFAULT 0,
      start_day text NOT NULL,
      end_day text NOT NULL DEFAULT '',
      archived boolean NOT NULL DEFAULT false,
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (household_id, id)
    );
    CREATE TABLE IF NOT EXISTS dose_logs (
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      id text NOT NULL,
      medication_id text NOT NULL,
      part text NOT NULL,
      day text NOT NULL,
      member_id text NOT NULL,
      outcome text NOT NULL,
      amount text NOT NULL DEFAULT '',
      note text,
      time_label text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (household_id, id),
      UNIQUE (household_id, medication_id, part, day)
    );
    CREATE INDEX IF NOT EXISTS dose_logs_day_idx ON dose_logs (household_id, day);
    CREATE TABLE IF NOT EXISTS apple_links (
      apple_user_id text PRIMARY KEY,
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      member_id text NOT NULL,
      linked_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS care_events (
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      id text NOT NULL,
      pet_id text NOT NULL,
      title text NOT NULL,
      kind text NOT NULL,
      due_day text NOT NULL,
      note text NOT NULL DEFAULT '',
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (household_id, id)
    );
    CREATE INDEX IF NOT EXISTS care_events_due_idx ON care_events (household_id, due_day);
    CREATE TABLE IF NOT EXISTS device_tokens (
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      member_id text NOT NULL,
      platform text NOT NULL,
      token text NOT NULL,
      push_enabled boolean NOT NULL DEFAULT true,
      updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (household_id, member_id, token)
    );
    CREATE TABLE IF NOT EXISTS analytics_daily (
      day date NOT NULL,
      event text NOT NULL,
      count integer NOT NULL DEFAULT 0,
      PRIMARY KEY (day, event)
    );
    CREATE TABLE IF NOT EXISTS sitter_links (
      household_id text NOT NULL REFERENCES households (id) ON DELETE CASCADE,
      id text NOT NULL,
      member_id text NOT NULL,
      token_hash text NOT NULL UNIQUE,
      label text NOT NULL DEFAULT 'Sitter',
      expires_at timestamptz NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (household_id, id)
    );
    CREATE INDEX IF NOT EXISTS sitter_links_token_idx ON sitter_links (token_hash);
  `);
  await pool.query(`
    ALTER TABLE medications ADD COLUMN IF NOT EXISTS end_day text NOT NULL DEFAULT '';
  `);
  await pool.query(`
    ALTER TABLE households ADD COLUMN IF NOT EXISTS rc_expires_at timestamptz;
    ALTER TABLE households ADD COLUMN IF NOT EXISTS rc_product_id text;
  `);
  await pool.query(`
    ALTER TABLE households ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz;
  `);
  await pool.query(`
    ALTER TABLE households ADD COLUMN IF NOT EXISTS rc_event_at timestamptz;
  `);
  await pool.query(`
    ALTER TABLE pets ADD COLUMN IF NOT EXISTS photo_key text;
  `);
  await pool.query(`
    ALTER TABLE medications ADD COLUMN IF NOT EXISTS archived_at timestamptz;
  `);
  // v7 — all additive, so a v6 server (rollback) keeps working on this schema.
  // Invite expiry: existing codes count as made now, so nobody is locked out.
  // A constant default (now() is evaluated once) adds the column without a rewrite.
  await pool.query(`
    ALTER TABLE households ADD COLUMN IF NOT EXISTS invite_created_at timestamptz NOT NULL DEFAULT now();
    ALTER TABLE members ADD COLUMN IF NOT EXISTS rc_is_pro boolean NOT NULL DEFAULT false;
    ALTER TABLE members ADD COLUMN IF NOT EXISTS rc_expires_at timestamptz;
    ALTER TABLE members ADD COLUMN IF NOT EXISTS rc_event_at timestamptz;
    ALTER TABLE members ADD COLUMN IF NOT EXISTS rc_product_id text;
    ALTER TABLE sitter_links ADD COLUMN IF NOT EXISTS last_used_at timestamptz;
    ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production';
    CREATE TABLE IF NOT EXISTS member_removals (
      token_hash text PRIMARY KEY,
      household_id text NOT NULL,
      removed_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  // v8 — custom reminder time per dose ({"morning":"07:00"}); NULL = the
  // part defaults. Nullable with no default: instant, and a v7 server
  // (rollback) simply never reads it.
  await pool.query(`
    ALTER TABLE medications ADD COLUMN IF NOT EXISTS times jsonb;
    -- Saved while Free but over Free's limits (an old or modified app, or Pro
    -- that ended before an offline add synced). Never rejected: the medicine
    -- and its doses stay, apps pause its reminders until Pro.
    ALTER TABLE medications ADD COLUMN IF NOT EXISTS needs_pro boolean NOT NULL DEFAULT false;
  `);
  // One-time: the old household-wide Pro flag moves onto the owner's row so
  // nobody loses Pro. Guarded by a meta key so it never re-runs (a later
  // EXPIRATION must not be undone by a reboot).
  const proMoved = await pool.query("SELECT 1 FROM meta WHERE key = 'pro_per_member'");
  if (proMoved.rowCount === 0) {
    await moveHouseholdProToOwners(pool);
    await pool.query("INSERT INTO meta (key, value) VALUES ('pro_per_member', '1') ON CONFLICT DO NOTHING");
  }
  // Old builds registered a made-up "local:<time>" id that can never receive a push.
  await pool.query("DELETE FROM device_tokens WHERE token LIKE 'local:%'");
  // Registering a token removes it from any other household/member (phone reused).
  await ensureIndexConcurrently(pool, "device_tokens_token_idx", "device_tokens (token)");
  // Household snapshot reads the newest 100 days of logs; without this it
  // sorts every log the household ever wrote.
  await ensureIndexConcurrently(pool, "dose_logs_created_idx", "dose_logs (household_id, created_at DESC)");
  // Duplicate of the UNIQUE constraint's own index: double write cost, no reads.
  await pool.query("DROP INDEX IF EXISTS sitter_links_token_idx");
  await pool.query(
    `INSERT INTO meta (key, value) VALUES ('schema_version', $1)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [schemaVersion],
  );
}

/**
 * v7 migration step: copies the household-wide Pro flag (and its expiry and
 * event clock) onto the owner's member row. Skips owners that already have
 * their own RevenueCat state. `householdId` limits it to one household (tests).
 */
export async function moveHouseholdProToOwners(client, householdId = null) {
  await client.query(
    `UPDATE members m
     SET rc_is_pro = h.is_pro, rc_expires_at = h.rc_expires_at,
         rc_event_at = h.rc_event_at, rc_product_id = h.rc_product_id
     FROM households h
     WHERE m.household_id = h.id AND m.role = 'owner' AND h.is_pro AND m.rc_event_at IS NULL
       AND ($1::text IS NULL OR h.id = $1)`,
    [householdId],
  );
}

/**
 * A 400 the app shows as-is, so `message` is plain words for a pet owner.
 * `detail` is the developer reason (field, rule) and only goes to the logs.
 */
export class InputError extends Error {
  constructor(message, detail = message) {
    super(message);
    this.status = 400;
    this.detail = detail;
  }
}

/** 403: this needs a Pro household. `message` is shown to the person as-is. */
export class ProRequiredError extends InputError {
  constructor(message, detail = message) {
    super(message, detail);
    this.status = 403;
    this.publicCode = "pro_required";
  }
}

/**
 * A 404 with a machine-readable `publicCode` (e.g. `invite_expired`) so newer
 * apps can react; older apps just show `message`.
 */
export class NotFoundError extends InputError {
  constructor(message, publicCode, detail = message) {
    super(message, detail);
    this.status = 404;
    this.publicCode = publicCode;
  }
}

/** A malformed request is the app's bug, not the user's — say so kindly. */
const appProblem = "Something went wrong saving that. Update the app or try again.";

const requiredWords = {
  name: "Please enter a name.",
  title: "Please enter a title.",
  amount: "Please enter an amount.",
  label: "Please enter a label.",
};

function text(value, field, { max = 80, required = true } = {}) {
  const result = typeof value === "string" ? value.trim().slice(0, max) : "";
  if (required && !result) {
    const words = requiredWords[field.split(".").pop()] ?? appProblem;
    throw new InputError(words, `${field} is required`);
  }
  return result;
}

function id(value, field) {
  if (typeof value !== "string" || !/^[a-z0-9-]{1,40}$/.test(value)) {
    throw new InputError(appProblem, `${field} is not valid`);
  }
  return value;
}

function oneOf(value, allowed, field, fallback) {
  if (allowed.includes(value)) return value;
  if (fallback !== undefined) return fallback;
  throw new InputError(appProblem, `${field} is not valid`);
}

function day(value, field) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new InputError("That date doesn't look right. Pick it again.", `${field} must be YYYY-MM-DD`);
  }
  return value;
}

function count(value, max) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) return 0;
  return Math.min(Math.round(number), max);
}

function weight(value) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > 200) return 0;
  return Math.round(number * 10) / 10;
}

function list(value, max) {
  return Array.isArray(value) ? value.slice(0, max) : [];
}

function newToken() {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token) {
  return createHash("sha256").update(token).digest("hex");
}

function newId(prefix) {
  return `${prefix}-${randomBytes(6).toString("hex")}`;
}

function newCode() {
  const bytes = randomBytes(6);
  let code = "";
  for (const byte of bytes) code += codeAlphabet[byte % codeAlphabet.length];
  return code;
}

function readPet(input) {
  return {
    id: id(input?.id, "pet.id"),
    name: text(input?.name, "pet.name", { max: 40 }),
    species: oneOf(input?.species, species, "pet.species", "other"),
    ageYears: count(input?.ageYears, 40),
    weightKg: weight(input?.weightKg),
    breed: text(input?.breed, "pet.breed", { max: 60, required: false }),
    sex: text(input?.sex, "pet.sex", { max: 20, required: false }),
    conditions: list(input?.conditions, 12)
      .map((item) => text(item, "condition", { max: 40, required: false }))
      .filter(Boolean),
  };
}

const clockPattern = /^([01]\d|2[0-3]):([0-5]\d)$/;

/**
 * Custom reminder times: `undefined` when the field is absent (old apps —
 * the caller must keep what's stored), `null` to clear, else an object of
 * part → "HH:mm" (24h, local wall clock) limited to `chosenParts`.
 * Any valid time is allowed for any part; a bad one is rejected, never
 * silently dropped, so the person isn't reminded at a time they didn't pick.
 */
function readTimes(value, chosenParts) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new InputError(badTimeMessage, "medication.times must be an object");
  }
  const result = {};
  for (const [part, time] of Object.entries(value)) {
    if (!parts.includes(part)) continue;
    if (typeof time !== "string" || !clockPattern.test(time)) {
      throw new InputError(badTimeMessage, `medication.times.${part} must be HH:mm`);
    }
    if (chosenParts.includes(part)) result[part] = time;
  }
  return Object.keys(result).length === 0 ? null : result;
}

const badTimeMessage = "That reminder time doesn't look right. Pick it again.";

function readMedication(input) {
  const chosen = [...new Set(list(input?.parts, 3))].filter((part) => parts.includes(part));
  if (chosen.length === 0) throw new InputError("Pick at least one time of day.");
  const supplyTotal = count(input?.supplyTotal, 1000);
  return {
    id: id(input?.id, "medication.id"),
    petId: id(input?.petId, "medication.petId"),
    name: text(input?.name, "medication.name", { max: 60 }),
    amount: text(input?.amount, "medication.amount", { max: 40, required: false }),
    parts: parts.filter((part) => chosen.includes(part)),
    supplyTotal,
    dosesLeft: input?.dosesLeft === undefined ? supplyTotal : count(input.dosesLeft, supplyTotal),
    startDay: day(input?.startDay, "medication.startDay"),
    // Compared as a string against YYYY-MM-DD days, so anything else means "no end".
    endDay: /^\d{4}-\d{2}-\d{2}$/.test(input?.endDay ?? "") ? input.endDay : "",
    times: readTimes(input?.times, chosen),
  };
}

function readLog(input) {
  return {
    id: id(input?.id, "log.id"),
    medicationId: id(input?.medicationId, "log.medicationId"),
    part: oneOf(input?.part, parts, "log.part"),
    day: day(input?.day, "log.day"),
    memberId: input?.memberId === undefined ? undefined : id(input.memberId, "log.memberId"),
    outcome: oneOf(input?.outcome, outcomes, "log.outcome"),
    amount: text(input?.amount, "log.amount", { max: 40, required: false }),
    note: text(input?.note, "log.note", { max: 200, required: false }) || null,
    timeLabel: text(input?.timeLabel, "log.timeLabel", { max: 20 }),
  };
}

async function insertPet(client, householdId, pet) {
  const result = await client.query(
    `INSERT INTO pets (household_id, id, name, species, age_years, weight_kg, breed, sex, conditions)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)
     ON CONFLICT (household_id, id) DO UPDATE SET
       name = EXCLUDED.name, species = EXCLUDED.species, age_years = EXCLUDED.age_years,
       weight_kg = EXCLUDED.weight_kg, breed = EXCLUDED.breed, sex = EXCLUDED.sex,
       conditions = EXCLUDED.conditions
     RETURNING *`,
    [
      householdId,
      pet.id,
      pet.name,
      pet.species,
      pet.ageYears,
      pet.weightKg,
      pet.breed,
      pet.sex,
      JSON.stringify(pet.conditions),
    ],
  );
  return mapPet(result.rows[0]);
}

async function insertMedication(client, householdId, medication) {
  const pet = await client.query("SELECT 1 FROM pets WHERE household_id = $1 AND id = $2", [
    householdId,
    medication.petId,
  ]);
  if (pet.rowCount === 0) throw new InputError("That pet was removed from the household. Pull down to refresh.");
  const result = await client.query(
    `INSERT INTO medications (household_id, id, pet_id, name, amount, parts, supply_total, doses_left, start_day, end_day, times)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11::jsonb)
     ON CONFLICT (household_id, id) DO UPDATE SET
       name = EXCLUDED.name, amount = EXCLUDED.amount, parts = EXCLUDED.parts,
       supply_total = EXCLUDED.supply_total, doses_left = EXCLUDED.doses_left,
       end_day = EXCLUDED.end_day, archived = false,
       -- Old apps never send times: an upsert without them keeps the stored ones.
       times = CASE WHEN $12 THEN EXCLUDED.times ELSE medications.times END
     RETURNING *`,
    [
      householdId,
      medication.id,
      medication.petId,
      medication.name,
      medication.amount,
      JSON.stringify(medication.parts),
      medication.supplyTotal,
      medication.dosesLeft,
      medication.startDay,
      medication.endDay || "",
      medication.times == null ? null : JSON.stringify(medication.times),
      medication.times !== undefined,
    ],
  );
  return mapMedication(result.rows[0]);
}

async function transaction(pool, work) {
  const client = await pool.connect();
  let broken;
  try {
    await client.query("BEGIN");
    const result = await work(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    // A failed ROLLBACK (dead connection) must not hide the real error, and
    // that connection must not go back into the pool.
    await client.query("ROLLBACK").catch((rollbackError) => {
      broken = rollbackError;
    });
    throw error;
  } finally {
    client.release(broken);
  }
}

/// Creates a household from a device's setup, including anything it saved offline.
export async function createHousehold(pool, body) {
  const ownerName = text(body?.owner?.name, "owner.name", { max: 40, required: false }) || "You";
  const ownerId = body?.owner?.id === undefined ? "you" : id(body.owner.id, "owner.id");
  const pets = list(body?.pets, 10).map(readPet);
  const caregivers = list(body?.caregivers, 10).map((item) => ({
    id: id(item?.id, "caregiver.id"),
    name: text(item?.name, "caregiver.name", { max: 40 }),
    role: oneOf(item?.role, roles, "caregiver.role", "caregiver"),
  }));
  const medications = list(body?.medications, 50).map(readMedication);
  const logs = list(body?.logs, 2000).map(readLog);
  const token = newToken();

  return transaction(pool, async (client) => {
    const householdId = newId("house");
    let inviteCode = "";
    for (let attempt = 0; attempt < 5 && !inviteCode; attempt += 1) {
      const candidate = newCode();
      const inserted = await client.query(
        `INSERT INTO households (id, invite_code) VALUES ($1, $2)
         ON CONFLICT (invite_code) DO NOTHING RETURNING id`,
        [householdId, candidate],
      );
      if (inserted.rowCount > 0) inviteCode = candidate;
    }
    if (!inviteCode) throw new Error("Could not make an invite code");

    await client.query(
      `INSERT INTO members (household_id, id, name, role, token_hash) VALUES ($1,$2,$3,'owner',$4)`,
      [householdId, ownerId, ownerName, hashToken(token)],
    );
    for (const caregiver of caregivers) {
      if (caregiver.id === ownerId) continue;
      await client.query(
        `INSERT INTO members (household_id, id, name, role) VALUES ($1,$2,$3,$4)
         ON CONFLICT DO NOTHING`,
        [householdId, caregiver.id, caregiver.name, caregiver.role === "owner" ? "caregiver" : caregiver.role],
      );
    }
    for (const pet of pets) await insertPet(client, householdId, pet);
    for (const medication of medications) await insertMedication(client, householdId, medication);
    if (logs.length > 0) {
      // Up to 2000 offline logs: one statement, not 2000 round trips.
      await client.query(
        `INSERT INTO dose_logs (household_id, id, medication_id, part, day, member_id, outcome, amount, note, time_label)
         SELECT $1, * FROM unnest($2::text[], $3::text[], $4::text[], $5::text[], $6::text[],
                                  $7::text[], $8::text[], $9::text[], $10::text[])
         ON CONFLICT DO NOTHING`,
        [
          householdId,
          logs.map((entry) => entry.id),
          logs.map((entry) => entry.medicationId),
          logs.map((entry) => entry.part),
          logs.map((entry) => entry.day),
          logs.map((entry) => entry.memberId ?? ownerId),
          logs.map((entry) => entry.outcome),
          logs.map((entry) => entry.amount),
          logs.map((entry) => entry.note),
          logs.map((entry) => entry.timeLabel),
        ],
      );
    }
    return { token, householdId, memberId: ownerId };
  });
}

export async function joinHousehold(pool, body) {
  const code = text(body?.code, "code", { max: 12 }).toUpperCase().replace(/[^A-Z0-9]/g, "");
  const name = text(body?.name, "name", { max: 40 });
  const household = await pool.query(
    `SELECT id, invite_created_at > now() - ($2::bigint * interval '1 millisecond') AS fresh
     FROM households WHERE invite_code = $1`,
    [code, inviteTtlMs],
  );
  if (household.rowCount === 0) return null;
  if (!household.rows[0].fresh) {
    throw new NotFoundError("That invite code expired. Ask for a new one.", "invite_expired", "invite code expired");
  }
  const householdId = household.rows[0].id;
  const memberId = newId("member");
  const token = newToken();
  // A leaked invite code must not let anyone add members without bound.
  const inserted = await pool.query(
    `INSERT INTO members (household_id, id, name, role, token_hash)
     SELECT $1,$2,$3,$4,$5
     WHERE (SELECT count(*) FROM members WHERE household_id = $1 AND token_hash IS NOT NULL) < $6`,
    [
      householdId,
      memberId,
      name,
      oneOf(body?.role, ["caregiver", "sitter"], "role", "caregiver"),
      hashToken(token),
      maxMembers,
    ],
  );
  if (inserted.rowCount === 0) {
    throw new InputError("This household is full. Ask the owner to remove someone first.", "member cap reached");
  }
  return { token, householdId, memberId };
}

/**
 * Owner: a new invite code that works for [inviteTtlMs]; the old one stops
 * working at once. Two quick rotations simply leave the second code.
 */
export async function rotateInviteCode(pool, { householdId }) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const candidate = newCode();
    try {
      const result = await pool.query(
        `UPDATE households SET invite_code = $2, invite_created_at = now() WHERE id = $1
         RETURNING invite_code, invite_created_at`,
        [householdId, candidate],
      );
      const row = result.rows[0];
      if (!row) return null;
      return {
        inviteCode: row.invite_code,
        inviteExpiresAt: new Date(new Date(row.invite_created_at).getTime() + inviteTtlMs).toISOString(),
      };
    } catch (error) {
      if (error?.code !== "23505") throw error; // unique clash: try another code
    }
  }
  throw new Error("Could not make an invite code");
}

const assignableRoles = ["caregiver", "sitter"];

/**
 * Owner: changes another member's role to caregiver or sitter. The owner
 * can't change their own role, so there is always exactly one owner.
 * Browser sitter-link members have no app, so their role is fixed.
 */
export async function setMemberRole(pool, { householdId, memberId }, targetId, body) {
  const target = id(targetId, "member.id");
  const role = oneOf(body?.role, assignableRoles, "role");
  if (target === memberId) throw new InputError("You're the owner. Your role can't change.", "owner self-demotion");
  const current = await pool.query(
    `SELECT m.role, EXISTS (SELECT 1 FROM sitter_links s WHERE s.household_id = m.household_id AND s.member_id = m.id) AS link
     FROM members m WHERE m.household_id = $1 AND m.id = $2`,
    [householdId, target],
  );
  const row = current.rows[0];
  if (!row) return null;
  if (row.role === "owner") throw new InputError("The owner's role can't change.", "target is owner");
  if (row.link) throw new InputError("Browser sitter links can't change role. Revoke the link instead.", "sitter link member");
  const updated = await pool.query(
    "UPDATE members SET role = $3 WHERE household_id = $1 AND id = $2 AND role <> 'owner' RETURNING *",
    [householdId, target, role],
  );
  return updated.rows[0] ? mapMember(updated.rows[0], memberId) : null;
}

/**
 * Owner: removes a member. Their app token stops working at once (a
 * tombstone lets their phone say why), their push tokens and any sitter
 * link go, and their past logs stay (shown as "Former member"). Null when
 * they were already gone.
 */
export async function removeMember(pool, { householdId, memberId }, targetId) {
  const target = id(targetId, "member.id");
  if (target === memberId) {
    throw new InputError("To leave, delete your account in Settings instead.", "owner removing self");
  }
  const result = await transaction(pool, async (client) => {
    const row = (
      await client.query("SELECT role, token_hash FROM members WHERE household_id = $1 AND id = $2 FOR UPDATE", [
        householdId,
        target,
      ])
    ).rows[0];
    if (!row) return null;
    if (row.role === "owner") throw new InputError("The owner can't be removed.", "target is owner");
    if (row.token_hash) {
      await client.query(
        `INSERT INTO member_removals (token_hash, household_id) VALUES ($1, $2)
         ON CONFLICT (token_hash) DO UPDATE SET removed_at = now()`,
        [row.token_hash, householdId],
      );
    }
    await client.query("DELETE FROM device_tokens WHERE household_id = $1 AND member_id = $2", [householdId, target]);
    await client.query("DELETE FROM sitter_links WHERE household_id = $1 AND member_id = $2", [householdId, target]);
    await client.query("DELETE FROM members WHERE household_id = $1 AND id = $2", [householdId, target]);
    return { removed: true, role: row.role };
  });
  // A removed payer no longer counts toward household Pro.
  if (result) await refreshLegacyPro(pool, householdId);
  return result;
}

/** The member a bearer token belongs to, with their current role (read fresh every request). */
export async function memberForToken(pool, token) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const result = await pool.query("SELECT household_id, id, role FROM members WHERE token_hash = $1", [hashToken(token)]);
  const row = result.rows[0];
  return row ? { householdId: row.household_id, memberId: row.id, role: row.role } : null;
}

/**
 * Only asked after a token failed: was it removed by the owner? Lets the app
 * say "The owner removed you" instead of a generic sign-in error.
 */
export async function wasRemoved(pool, token) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return false;
  const result = await pool.query("SELECT 1 FROM member_removals WHERE token_hash = $1", [hashToken(token)]);
  return result.rowCount > 0;
}

function mapMember(row, memberId) {
  // Apps create the household with the owner named "You"; to everyone else
  // that would read as themselves ("You gave Miso"), so call them Owner.
  const placeholder = row.role === "owner" && row.id !== memberId && /^you$/i.test(row.name);
  return {
    id: row.id,
    name: placeholder ? "Owner" : row.name,
    role: row.role,
    joined: row.joined ?? row.token_hash != null,
    ...(row.id === memberId ? { isYou: true } : {}),
    // Additive (v7): lets the owner see that removing this person ends Pro.
    ...(memberHasPro(row) ? { paysForPro: true } : {}),
  };
}

function mapPet(row) {
  return {
    id: row.id,
    // Short-lived bucket URL (a day); the app caches by photoKey.
    photoKey: row.photo_key ?? null,
    photoUrl: presignView(row.photo_key),
    name: row.name,
    species: row.species,
    ageYears: row.age_years,
    weightKg: row.weight_kg,
    breed: row.breed,
    sex: row.sex,
    conditions: row.conditions,
  };
}

function mapMedication(row) {
  return {
    id: row.id,
    petId: row.pet_id,
    name: row.name,
    amount: row.amount,
    parts: row.parts,
    supplyTotal: row.supply_total,
    dosesLeft: row.doses_left,
    startDay: row.start_day,
    endDay: row.end_day || "",
    // Additive: old apps ignore it. Omitted (not null) when unset.
    ...(row.times ? { times: row.times } : {}),
    // Additive: only sent when set; old apps ignore it.
    ...(row.needs_pro ? { needsPro: true } : {}),
  };
}

function mapLog(row) {
  return {
    id: row.id,
    medicationId: row.medication_id,
    part: row.part,
    day: row.day,
    memberId: row.member_id,
    outcome: row.outcome,
    amount: row.amount,
    ...(row.note ? { note: row.note } : {}),
    timeLabel: row.time_label,
  };
}

const careKinds = ["vaccine", "vetVisit", "refill", "other"];

function readCareEvent(input) {
  return {
    id: id(input?.id, "event.id"),
    petId: id(input?.petId, "event.petId"),
    title: text(input?.title, "event.title", { max: 80 }),
    kind: oneOf(input?.kind, careKinds, "event.kind", "other"),
    dueDay: day(input?.dueDay, "event.dueDay"),
    note: text(input?.note, "event.note", { max: 200, required: false }) || "",
  };
}

function mapCareEvent(row) {
  return {
    id: row.id,
    petId: row.pet_id,
    title: row.title,
    kind: row.kind,
    dueDay: row.due_day,
    note: row.note || "",
  };
}

/**
 * The whole household in ONE round trip on ONE pooled connection (it used to
 * fan out six parallel queries, so a single request could drain the pool).
 * Token hashes never leave the database. `logDay` narrows logs to one day
 * (sitter view) instead of the 100-day window.
 */
export async function loadHousehold(pool, { householdId, memberId }, { logDay } = {}) {
  const logFilter = logDay
    ? "household_id = $1 AND day = $2"
    : "household_id = $1 AND created_at > now() - interval '100 days'";
  const archivedLogFilter = logDay ? "l.day = $2" : "l.created_at > now() - interval '100 days'";
  const result = await pool.query(
    `SELECT
       (SELECT row_to_json(h) FROM (
          SELECT id, invite_code, invite_created_at, plan FROM households WHERE id = $1
        ) h) AS household,
       (SELECT coalesce(json_agg(m ORDER BY m.created_at), '[]'::json) FROM (
          SELECT id, name, role, token_hash IS NOT NULL AS joined, created_at, rc_is_pro, rc_expires_at
          FROM members WHERE household_id = $1
        ) m) AS members,
       (SELECT coalesce(json_agg(p ORDER BY p.created_at), '[]'::json) FROM (
          SELECT * FROM pets WHERE household_id = $1
        ) p) AS pets,
       (SELECT coalesce(json_agg(d ORDER BY d.created_at), '[]'::json) FROM (
          SELECT * FROM medications WHERE household_id = $1 AND archived = false
        ) d) AS medications,
       -- Stopped medicines that still have logs in the returned window, so a
       -- phone that joins later can label that history (vet report).
       (SELECT coalesce(json_agg(a ORDER BY a.created_at), '[]'::json) FROM (
          SELECT m.* FROM medications m
          WHERE m.household_id = $1 AND m.archived = true
            AND EXISTS (SELECT 1 FROM dose_logs l WHERE l.household_id = $1 AND l.medication_id = m.id AND ${archivedLogFilter})
          LIMIT 200
        ) a) AS archived_medications,
       (SELECT coalesce(json_agg(l ORDER BY l.created_at DESC), '[]'::json) FROM (
          SELECT * FROM dose_logs WHERE ${logFilter} ORDER BY created_at DESC LIMIT 3000
        ) l) AS logs,
       (SELECT coalesce(json_agg(c ORDER BY c.due_day), '[]'::json) FROM (
          SELECT * FROM care_events WHERE household_id = $1 ORDER BY due_day ASC LIMIT 200
        ) c) AS care_events`,
    logDay ? [householdId, logDay] : [householdId],
  );
  const row = result.rows[0];
  const household = row?.household;
  if (!household) return null;
  // Pro (even a purchase the server heard of late) unlocks marked medicines
  // for good: they count as Pro-era schedules from now on. Only runs when
  // something is marked, so a normal snapshot costs no extra query.
  if (hasPro(row.members) && row.medications.some((m) => m.needs_pro)) {
    await pool.query("UPDATE medications SET needs_pro = false WHERE household_id = $1 AND needs_pro", [householdId]);
    for (const medication of row.medications) medication.needs_pro = false;
  }
  const role = row.members.find((member) => member.id === memberId)?.role ?? "sitter";
  const isOwner = role === "owner";
  return {
    household: {
      id: household.id,
      // Only the owner can invite, so only the owner sees the code (older
      // caregiver apps then show no code instead of one they can't manage).
      inviteCode: isOwner ? household.invite_code : "",
      ...(isOwner
        ? { inviteExpiresAt: new Date(new Date(household.invite_created_at).getTime() + inviteTtlMs).toISOString() }
        : {}),
      isPro: hasPro(row.members),
      // Additive: exact end of Pro (null = lifetime). Omitted when Free.
      ...(proUntil(row.members) === undefined ? {} : { proUntil: proUntil(row.members) }),
      plan: household.plan,
    },
    memberId,
    // Additive (v7): the caller's own role, read fresh on every snapshot.
    role,
    members: row.members.map((member) => mapMember(member, memberId)),
    pets: row.pets.map(mapPet),
    medications: row.medications.map(mapMedication),
    // Separate list so older apps never show a stopped medicine as active.
    archivedMedications: row.archived_medications.map((m) => ({ ...mapMedication(m), archivedAt: m.archived_at })),
    logs: row.logs.map(mapLog),
    careEvents: row.care_events.map(mapCareEvent),
  };
}

export async function addPet(pool, { householdId }, body) {
  const pet = readPet(body);
  // Not counting this pet itself: a replayed outbox addPet is an upsert, not an 11th pet.
  const existing = await pool.query(
    "SELECT count(*)::int AS n FROM pets WHERE household_id = $1 AND id <> $2",
    [householdId, pet.id],
  );
  if (existing.rows[0].n >= 10) throw new InputError("A household can have up to 10 pets.");
  return insertPet(pool, householdId, pet);
}

export async function updatePet(pool, { householdId }, petId, body) {
  const exists = await pool.query("SELECT 1 FROM pets WHERE household_id = $1 AND id = $2", [
    householdId,
    id(petId, "pet.id"),
  ]);
  if (exists.rowCount === 0) return null;
  return insertPet(pool, householdId, readPet({ ...body, id: petId }));
}

/** Free tier, mirrored from the app (PetLimits): one medicine per pet, morning only, 4:00–11:59. */
const freeMedsPerPet = 1;
const freeMorningFirst = "04:00";
const freeMorningLast = "11:59";

function morningInFreeWindow(time) {
  // "HH:mm" compares correctly as text; no custom time means 08:00.
  return time == null || (time >= freeMorningFirst && time <= freeMorningLast);
}

/** Why a new medicine is over Free's limits, or null when it fits. */
async function freeLimitBreach(pool, householdId, medication) {
  if (medication.parts.length !== 1 || medication.parts[0] !== "morning") return "times";
  if (!morningInFreeWindow(medication.times?.morning)) return "time_window";
  const others = await pool.query(
    `SELECT count(*)::int AS n FROM medications
     WHERE household_id = $1 AND pet_id = $2 AND id <> $3 AND archived = false
       AND (end_day = '' OR end_day >= $4)`,
    [householdId, medication.petId, medication.id, medication.startDay],
  );
  return others.rows[0].n >= freeMedsPerPet ? "meds" : null;
}

/**
 * Adds (or re-sends) a medicine. Over Free's limits without Pro it is still
 * saved — rejecting would make the app drop it, and a pet's medicine must
 * never vanish — but marked `needs_pro`, cleared once the household has Pro.
 * Household creation (the app's first upload) never marks: that data was
 * made on the phone under its own rules, including Pro-era schedules.
 */
export async function addMedication(pool, { householdId }, body) {
  const input = readMedication(body);
  const medication = await insertMedication(pool, householdId, input);
  if (await householdHasPro(pool, householdId)) return medication;
  const breach = await freeLimitBreach(pool, householdId, input);
  if (!breach) return medication;
  await pool.query("UPDATE medications SET needs_pro = true WHERE household_id = $1 AND id = $2", [
    householdId,
    input.id,
  ]);
  return { ...medication, needsPro: true };
}

/**
 * Partial update of a medicine. Only fields present in `body` change
 * (today: `times`), so an edit from one phone never resets what another
 * phone changed. Returns null when the medicine is gone or stopped.
 */
export async function updateMedication(pool, { householdId }, medicationId, body) {
  const medId = id(medicationId, "medication.id");
  const current = await pool.query(
    "SELECT * FROM medications WHERE household_id = $1 AND id = $2 AND archived = false",
    [householdId, medId],
  );
  if (current.rowCount === 0) return null;
  const times = readTimes(body?.times, current.rows[0].parts);
  if (times === undefined) return mapMedication(current.rows[0]);
  // Free keeps the morning reminder in the morning. Only a changed morning
  // time counts, so one saved on Pro is kept; over the limit it is saved
  // and marked, never refused (see addMedication).
  const before = current.rows[0].times?.morning ?? null;
  const after = times?.morning ?? null;
  const breach =
    current.rows[0].parts.includes("morning") &&
    after !== before &&
    !morningInFreeWindow(after) &&
    !(await householdHasPro(pool, householdId));
  const result = await pool.query(
    `UPDATE medications SET times = $3::jsonb, needs_pro = needs_pro OR $4
     WHERE household_id = $1 AND id = $2 AND archived = false RETURNING *`,
    [householdId, medId, times == null ? null : JSON.stringify(times), breach],
  );
  return result.rows[0] ? mapMedication(result.rows[0]) : null;
}

export async function archiveMedication(pool, { householdId }, medicationId) {
  const result = await pool.query(
    "UPDATE medications SET archived = true, archived_at = now() WHERE household_id = $1 AND id = $2",
    [householdId, id(medicationId, "medication.id")],
  );
  return result.rowCount > 0;
}

export async function refillMedication(pool, { householdId }, medicationId) {
  const result = await pool.query(
    `UPDATE medications SET doses_left = supply_total
     WHERE household_id = $1 AND id = $2 AND archived = false RETURNING *`,
    [householdId, id(medicationId, "medication.id")],
  );
  return result.rows[0] ? mapMedication(result.rows[0]) : null;
}

/// Saves one dose. A second log for the same medicine, time of day, and date is refused.
export async function logDose(pool, { householdId, memberId }, body) {
  const entry = readLog(body);
  return transaction(pool, async (client) => {
    const medication = await client.query(
      "SELECT * FROM medications WHERE household_id = $1 AND id = $2 AND archived = false FOR UPDATE",
      [householdId, entry.medicationId],
    );
    if (medication.rowCount === 0) return { missing: true };
    let giver = memberId;
    if (entry.memberId && entry.memberId !== memberId) {
      const member = await client.query("SELECT 1 FROM members WHERE household_id = $1 AND id = $2", [
        householdId,
        entry.memberId,
      ]);
      if (member.rowCount > 0) giver = entry.memberId;
    }
    const insert = () =>
      client.query(
        `INSERT INTO dose_logs (household_id, id, medication_id, part, day, member_id, outcome, amount, note, time_label)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT DO NOTHING RETURNING *`,
        [
          householdId,
          entry.id,
          entry.medicationId,
          entry.part,
          entry.day,
          giver,
          entry.outcome,
          entry.amount,
          entry.note,
          entry.timeLabel,
        ],
      );
    let inserted = await insert();
    if (inserted.rowCount === 0) {
      const existing = await client.query(
        `SELECT * FROM dose_logs WHERE household_id = $1
         AND ((medication_id = $2 AND part = $3 AND day = $4) OR id = $5)`,
        [householdId, entry.medicationId, entry.part, entry.day, entry.id],
      );
      const prior = existing.rows[0];
      // "Not sure if given" stays open until someone confirms it was given or skipped.
      const resolvesUncertain =
        prior?.outcome === "uncertain" && entry.outcome !== "uncertain" && prior.id !== entry.id;
      if (!resolvesUncertain) {
        return { conflict: prior ? mapLog(prior) : null };
      }
      await client.query("DELETE FROM dose_logs WHERE household_id = $1 AND id = $2", [
        householdId,
        prior.id,
      ]);
      inserted = await insert();
    }
    let updated = mapMedication(medication.rows[0]);
    if (entry.outcome === "given" && updated.supplyTotal > 0) {
      const result = await client.query(
        `UPDATE medications SET doses_left = GREATEST(doses_left - 1, 0)
         WHERE household_id = $1 AND id = $2 RETURNING *`,
        [householdId, entry.medicationId],
      );
      updated = mapMedication(result.rows[0]);
    }
    return { log: mapLog(inserted.rows[0]), medication: updated };
  });
}

export async function setPlan(pool, { householdId }, plan) {
  if (plan !== "yearly" && plan !== "monthly") return null;
  await pool.query("UPDATE households SET plan = $1 WHERE id = $2", [plan, householdId]);
  return plan;
}

/**
 * POST /v1/billing/trial (path kept for shipped apps): the caller says it just
 * bought or restored. Ask RevenueCat — never the client — whether this
 * member's store account has `pro`, and store it on this member's row; the
 * household is Pro while any member is. Covers purchases made before
 * sharing, which no webhook ties to the household.
 */
export async function refreshProFromRevenueCat(pool, { householdId, memberId }, logFn = () => {}) {
  const pro = await fetchProEntitlement(`${householdId}:${memberId}`);
  if (!pro.ok) {
    logFn("billing.rc_refresh_failed", { householdId, reason: pro.reason });
  } else {
    if (pro.active) {
      await applyProState(pool, householdId, memberId, {
        isPro: true,
        expiresAt: pro.expiresAt,
        productId: pro.productId,
        eventAt: new Date(),
      });
    } else {
      // RevenueCat is the truth: an ended subscription is revoked here too
      // (not only by EXPIRATION). State written in the last few minutes is
      // kept — REST can lag a webhook that just reported a purchase.
      const now = new Date();
      const revoked = await pool.query(
        `UPDATE members SET rc_is_pro = false, rc_expires_at = $3, rc_event_at = $3
         WHERE household_id = $1 AND id = $2 AND rc_is_pro
           AND (rc_event_at IS NULL OR rc_event_at < $4)
         RETURNING id`,
        [householdId, memberId, now, new Date(now.getTime() - lookupRevokeAfterMs)],
      );
      if (revoked.rowCount > 0) {
        await refreshLegacyPro(pool, householdId);
        logFn("billing.rc_refresh_revoked", { householdId });
      }
    }
    logFn("billing.rc_refresh", { householdId, active: pro.active });
  }
  const members = (
    await pool.query("SELECT rc_is_pro, rc_expires_at FROM members WHERE household_id = $1 AND rc_is_pro", [householdId])
  ).rows;
  const plan = (await pool.query("SELECT plan FROM households WHERE id = $1", [householdId])).rows[0]?.plan;
  const until = proUntil(members);
  return {
    isPro: hasPro(members),
    ...(until === undefined ? {} : { proUntil: until }),
    plan: plan ?? "yearly",
  };
}

export async function addCareEvent(pool, { householdId }, body) {
  const event = readCareEvent(body);
  const pet = await pool.query("SELECT 1 FROM pets WHERE household_id = $1 AND id = $2", [
    householdId,
    event.petId,
  ]);
  if (pet.rowCount === 0) throw new InputError("That pet was removed from the household. Pull down to refresh.");
  const result = await pool.query(
    `INSERT INTO care_events (household_id, id, pet_id, title, kind, due_day, note)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     ON CONFLICT (household_id, id) DO UPDATE SET
       title = EXCLUDED.title, kind = EXCLUDED.kind, due_day = EXCLUDED.due_day, note = EXCLUDED.note
     RETURNING *`,
    [householdId, event.id, event.petId, event.title, event.kind, event.dueDay, event.note],
  );
  return mapCareEvent(result.rows[0]);
}

export async function removeCareEvent(pool, { householdId }, eventId) {
  const result = await pool.query(
    "DELETE FROM care_events WHERE household_id = $1 AND id = $2",
    [householdId, id(eventId, "event.id")],
  );
  return result.rowCount > 0;
}

export async function linkAppleAccount(pool, { householdId, memberId }, appleUserId) {
  const appleId = text(appleUserId, "appleUserId", { max: 128 });
  const owner = await pool.query(
    "SELECT 1 FROM members WHERE household_id = $1 AND id = $2 AND role = 'owner'",
    [householdId, memberId],
  );
  if (owner.rowCount === 0) throw new InputError("Only the household owner can link Apple Sign-In.");
  await pool.query(
    `INSERT INTO apple_links (apple_user_id, household_id, member_id)
     VALUES ($1,$2,$3)
     ON CONFLICT (apple_user_id) DO UPDATE SET household_id = EXCLUDED.household_id, member_id = EXCLUDED.member_id, linked_at = now()`,
    [appleId, householdId, memberId],
  );
  return { linked: true };
}

export async function recoverFromApple(pool, appleUserId) {
  const appleId = text(appleUserId, "appleUserId", { max: 128 });
  const link = await pool.query("SELECT household_id, member_id FROM apple_links WHERE apple_user_id = $1", [
    appleId,
  ]);
  const row = link.rows[0];
  if (!row) return null;
  const token = newToken();
  await pool.query(
    "UPDATE members SET token_hash = $1 WHERE household_id = $2 AND id = $3",
    [hashToken(token), row.household_id, row.member_id],
  );
  return { token, householdId: row.household_id, memberId: row.member_id };
}

/**
 * Saves this phone's push token. Only real tokens are stored: `apns:<hex>`
 * (iOS) or `fcm:<id>` (Android). Older apps send a made-up `local:<time>`
 * id — accepted (200) so they keep working, but never stored. A token moves
 * with the phone: any row for it under another member/household is removed.
 * `delivery` tells the app whether the server can actually push.
 */
export async function registerDevice(pool, auth, body, sender = pushSender()) {
  const platform = oneOf(body?.platform, ["ios", "android", "other"], "platform", "other");
  const token = text(body?.token, "token", { max: 512 });
  const pushEnabled = body?.pushEnabled !== false;
  const environment = body?.environment === "sandbox" ? "sandbox" : "production";
  const real =
    (platform === "ios" && /^apns:[0-9a-f]{64,200}$/i.test(token)) ||
    (platform === "android" && /^fcm:[\w:.-]{20,500}$/.test(token));
  if (!real) return { ok: true, stored: false, delivery: false };
  const normalized = platform === "ios" ? token.toLowerCase() : token;
  await transaction(pool, async (client) => {
    await client.query(
      "DELETE FROM device_tokens WHERE token = $1 AND NOT (household_id = $2 AND member_id = $3)",
      [normalized, auth.householdId, auth.memberId],
    );
    await client.query(
      `INSERT INTO device_tokens (household_id, member_id, platform, token, push_enabled, environment, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,now())
       ON CONFLICT (household_id, member_id, token) DO UPDATE SET
         push_enabled = EXCLUDED.push_enabled, environment = EXCLUDED.environment, updated_at = now()`,
      [auth.householdId, auth.memberId, platform, normalized, pushEnabled, environment],
    );
  });
  return { ok: true, stored: true, delivery: sender.canSend({ platform, token: normalized }) };
}

export async function leaveHousehold(pool, { householdId, memberId }) {
  return transaction(pool, async (client) => {
    await client.query("DELETE FROM device_tokens WHERE household_id = $1 AND member_id = $2", [
      householdId,
      memberId,
    ]);
    const result = await client.query(
      "DELETE FROM members WHERE household_id = $1 AND id = $2 AND role <> 'owner'",
      [householdId, memberId],
    );
    if (result.rowCount > 0) return { left: true };
    const owner = await client.query(
      "UPDATE members SET token_hash = NULL WHERE household_id = $1 AND id = $2 AND role = 'owner'",
      [householdId, memberId],
    );
    return owner.rowCount > 0 ? { left: true, ownerSignedOut: true } : { left: false };
  });
}

export async function exportHouseholdData(pool, { householdId, memberId }) {
  const snapshot = await loadHousehold(pool, { householdId, memberId });
  if (!snapshot) return null;
  return {
    exportedAt: new Date().toISOString(),
    ...snapshot,
  };
}

/**
 * The funnel events the app sends (AnalyticsService._funnelEvents). This route
 * is unauthenticated, so free-form names would let anyone grow the table
 * without bound; add new names here when the app adds them.
 */
const analyticsEvents = new Set([
  "onboarding.finished",
  "dose.log.completed",
  "household.connected",
  "household.joined",
  "billing.purchase.completed",
  "billing.pro.unlocked",
  "care_event.added",
  ...(process.env.ANALYTICS_EXTRA_EVENTS ?? "").split(",").map((name) => name.trim()).filter(Boolean),
]);

export async function trackAnalytics(pool, events) {
  const list = Array.isArray(events) ? events.slice(0, 50) : [];
  const counts = new Map();
  for (const item of list) {
    const name = typeof item?.name === "string" ? item.name : "";
    if (analyticsEvents.has(name)) counts.set(name, (counts.get(name) ?? 0) + 1);
  }
  if (counts.size > 0) {
    // One statement per batch instead of one per event.
    await pool.query(
      `INSERT INTO analytics_daily (day, event, count)
       SELECT CURRENT_DATE, e.name, e.n FROM unnest($1::text[], $2::int[]) AS e(name, n)
       ON CONFLICT (day, event) DO UPDATE SET count = analytics_daily.count + EXCLUDED.count`,
      [[...counts.keys()], [...counts.values()]],
    );
  }
  return { recorded: list.length };
}

export async function applyBatchOperation(pool, auth, operation) {
  const type = text(operation?.type, "operation.type", { max: 32 });
  const payload = operation?.payload ?? {};
  // Same rules as the single-call routes; a forbidden op fails alone.
  if (batchActions[type]) requireRole(auth, batchActions[type]);
  switch (type) {
    case "logDose": {
      const result = await logDose(pool, auth, payload);
      if (result.missing) return { status: "missing" };
      if (result.conflict !== undefined) return { status: "conflict", log: result.conflict };
      return { status: "ok", log: result.log, medication: result.medication };
    }
    case "addPet":
      return { status: "ok", pet: await addPet(pool, auth, payload) };
    case "updatePet":
      return {
        status: "ok",
        pet: await updatePet(pool, auth, id(payload?.id, "pet.id"), payload),
      };
    case "addMedication":
      return { status: "ok", medication: await addMedication(pool, auth, payload) };
    case "updateMedication": {
      const medication = await updateMedication(pool, auth, id(payload?.id, "medication.id"), payload);
      return medication ? { status: "ok", medication } : { status: "missing" };
    }
    case "removeMedication":
      await archiveMedication(pool, auth, id(payload?.id, "medication.id"));
      return { status: "ok" };
    case "refill": {
      const medication = await refillMedication(pool, auth, id(payload?.id, "medication.id"));
      return medication ? { status: "ok", medication } : { status: "missing" };
    }
    case "addCareEvent":
      return { status: "ok", careEvent: await addCareEvent(pool, auth, payload) };
    case "removeCareEvent":
      await removeCareEvent(pool, auth, id(payload?.id, "event.id"));
      return { status: "ok" };
    default:
      throw new InputError("Update the app to sync this change.", `Unknown operation type: ${type}`);
  }
}

/**
 * Applies outbox operations one by one (each is its own transaction, and each
 * is idempotent on replay: upserts, conflict-guarded dose logs). Returns the
 * fresh household plus `logged` — new dose logs for the caller to notify on
 * once, instead of a push per replayed dose.
 */
export async function applyBatch(pool, auth, body) {
  const operations = list(body?.operations, 100);
  const results = [];
  const logged = [];
  for (const operation of operations) {
    const opId = text(operation?.id, "operation.id", { max: 48, required: false }) || newId("op");
    try {
      const result = await applyBatchOperation(pool, auth, operation);
      if (result.status === "ok" && result.log && operation?.type === "logDose") {
        logged.push(result.log);
      }
      results.push({ id: opId, ...result });
    } catch (error) {
      const exposed = error instanceof InputError || error?.expose === true;
      results.push({
        id: opId,
        status: "error",
        message: exposed ? error.message : "Operation failed",
        // Additive: newer apps tell a role change apart from a bad request.
        ...(exposed && error.publicCode ? { code: error.publicCode } : {}),
      });
    }
  }
  return { results, household: await loadHousehold(pool, auth), logged };
}

const partOpensAt = { morning: 0, afternoon: 12, evening: 17 };
const partTimeLabel = {
  morning: "8:00 AM",
  afternoon: "1:00 PM",
  evening: "8:00 PM",
};

function medicationActiveOn(medication, day) {
  return (
    medication.startDay <= day &&
    (medication.endDay === "" || medication.endDay >= day)
  );
}

/** "7:00 AM" for a minute of day (same wording as the app's default labels). */
function formatMinute(minute) {
  const hour = Math.floor(minute / 60);
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${h12}:${String(minute % 60).padStart(2, "0")} ${hour < 12 ? "AM" : "PM"}`;
}

function formatTimeLabel(date = new Date()) {
  let hour = date.getHours();
  const minute = date.getMinutes();
  const pm = hour >= 12;
  if (hour > 12) hour -= 12;
  if (hour === 0) hour = 12;
  return `${hour}:${String(minute).padStart(2, "0")} ${pm ? "PM" : "AM"}`;
}

export async function createSitterLink(pool, auth, body) {
  if (!(await householdHasPro(pool, auth.householdId))) {
    throw new ProRequiredError("Browser sitter links need Pawsitive Pro.");
  }
  await removeExpiredSitterLinks(pool, auth.householdId);
  const label = text(body?.label, "label", { max: 40, required: false }) || "Sitter";
  const linkId = newId("slink");
  const memberId = newId("sitter");
  const token = newToken();
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  // Member + link together or not at all (no orphan sitter members).
  await transaction(pool, async (client) => {
    await client.query(
      `INSERT INTO members (household_id, id, name, role) VALUES ($1,$2,$3,'sitter')`,
      [auth.householdId, memberId, label],
    );
    await client.query(
      `INSERT INTO sitter_links (household_id, id, member_id, token_hash, label, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [auth.householdId, linkId, memberId, hashToken(token), label, expiresAt],
    );
  });
  return { token, expiresAt: expiresAt.toISOString(), memberId, linkId };
}

/** Last-used stamps are written at most this often per link (a write per page load would be waste). */
const sitterTouchMs = 60 * 60 * 1000;

export async function sitterForToken(pool, token) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const result = await pool.query(
    `SELECT household_id, id, member_id, label, last_used_at FROM sitter_links
     WHERE token_hash = $1 AND expires_at > now()`,
    [hashToken(token)],
  );
  const row = result.rows[0];
  if (!row) return null;
  if (!row.last_used_at || Date.now() - new Date(row.last_used_at).getTime() > sitterTouchMs) {
    // Best effort and off the request's critical path: a failure only means
    // "last used" is a little stale.
    pool
      .query("UPDATE sitter_links SET last_used_at = now() WHERE household_id = $1 AND id = $2", [row.household_id, row.id])
      .catch(() => {});
  }
  return {
    householdId: row.household_id,
    memberId: row.member_id,
    linkId: row.id,
    label: row.label,
    role: "sitter",
  };
}

/**
 * Deletes a household's expired sitter links and their browser-only sitter
 * members (never an app member: those have a token). Logs stay and read as
 * "Former member". Runs on sitter-link reads/creates — no cron needed.
 */
export async function removeExpiredSitterLinks(pool, householdId) {
  await pool.query(
    `WITH gone AS (
       DELETE FROM sitter_links WHERE household_id = $1 AND expires_at <= now() RETURNING member_id
     )
     DELETE FROM members m USING gone
     WHERE m.household_id = $1 AND m.id = gone.member_id AND m.role = 'sitter' AND m.token_hash IS NULL`,
    [householdId],
  );
}

/**
 * The same cleanup across every household, a bounded batch at a time. The
 * server calls it at most once an hour in the background of a request.
 */
export async function sweepExpiredSitterLinks(pool, { limit = 500 } = {}) {
  const result = await pool.query(
    `WITH gone AS (
       DELETE FROM sitter_links WHERE (household_id, id) IN (
         SELECT household_id, id FROM sitter_links WHERE expires_at <= now() LIMIT $1
       ) RETURNING household_id, member_id
     ), members_gone AS (
       DELETE FROM members m USING gone
       WHERE m.household_id = gone.household_id AND m.id = gone.member_id
         AND m.role = 'sitter' AND m.token_hash IS NULL
       RETURNING 1
     )
     SELECT (SELECT count(*) FROM gone)::int AS links, (SELECT count(*) FROM members_gone)::int AS members`,
    [limit],
  );
  // Removal tombstones only need to outlive a phone's next sync or two.
  await pool.query("DELETE FROM member_removals WHERE removed_at < now() - interval '90 days'");
  return result.rows[0];
}

/** Owner: the household's working sitter links, newest first. */
export async function listSitterLinks(pool, { householdId }) {
  await removeExpiredSitterLinks(pool, householdId);
  const result = await pool.query(
    `SELECT id, label, expires_at, created_at, last_used_at FROM sitter_links
     WHERE household_id = $1 AND expires_at > now() ORDER BY created_at DESC LIMIT 100`,
    [householdId],
  );
  return result.rows.map((row) => ({
    id: row.id,
    label: row.label,
    expiresAt: new Date(row.expires_at).toISOString(),
    createdAt: new Date(row.created_at).toISOString(),
    lastUsedAt: row.last_used_at ? new Date(row.last_used_at).toISOString() : null,
  }));
}

/**
 * Owner: revokes a sitter link. Its token stops working on the next request
 * (sitterForToken reads the row), and its browser sitter member goes too.
 * False when it was already gone (double tap, another phone) — callers
 * treat that as done.
 */
export async function revokeSitterLink(pool, { householdId }, linkId) {
  return transaction(pool, async (client) => {
    const link = await client.query(
      "DELETE FROM sitter_links WHERE household_id = $1 AND id = $2 RETURNING member_id",
      [householdId, id(linkId, "link.id")],
    );
    if (link.rowCount === 0) return false;
    const memberId = link.rows[0].member_id;
    await client.query("DELETE FROM device_tokens WHERE household_id = $1 AND member_id = $2", [householdId, memberId]);
    await client.query(
      "DELETE FROM members WHERE household_id = $1 AND id = $2 AND role = 'sitter' AND token_hash IS NULL",
      [householdId, memberId],
    );
    return true;
  });
}

/** Minute of day for "HH:mm", or null. */
function clockMinute(value) {
  const match = typeof value === "string" ? clockPattern.exec(value) : null;
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
}

export async function getSitterView(pool, sitterAuth, query) {
  const viewDay = day(query?.day, "day");
  const hour = Math.min(Math.max(Number(query?.hour) || 0, 0), 23);
  // Optional (newer pages send it): makes a 7:30 custom time due at 7:30.
  const nowMinute = hour * 60 + Math.min(Math.max(Number(query?.minute) || 0, 0), 59);
  // Only this day's logs: the sitter never needs the 100-day history.
  const snapshot = await loadHousehold(pool, sitterAuth, { logDay: viewDay });
  if (!snapshot) return null;
  const petsById = Object.fromEntries(snapshot.pets.map((pet) => [pet.id, pet]));
  const logsByKey = {};
  for (const entry of snapshot.logs) {
    if (entry.day === viewDay) logsByKey[`${entry.medicationId}:${entry.part}`] = entry;
  }
  const membersById = Object.fromEntries(snapshot.members.map((member) => [member.id, member.name]));
  const doses = [];
  for (const medication of snapshot.medications) {
    if (!medicationActiveOn(medication, viewDay)) continue;
    for (const part of medication.parts) {
      const log = logsByKey[`${medication.id}:${part}`];
      if (log?.outcome === "skipped") continue;
      const scheduled = clockMinute(medication.times?.[part]);
      let status = "upcoming";
      if (log?.outcome === "given") status = "given";
      else if (nowMinute >= Math.min(partOpensAt[part] * 60, scheduled ?? Infinity)) status = "due";
      const pet = petsById[medication.petId];
      doses.push({
        id: `${medication.id}-${part}`,
        medicationId: medication.id,
        part,
        petName: pet?.name ?? "Pet",
        name: medication.name,
        amount: log?.amount || medication.amount,
        status,
        uncertain: log?.outcome === "uncertain",
        loggedBy: log ? membersById[log.memberId] ?? "Someone" : null,
        timeLabel: log?.timeLabel ?? (scheduled == null ? partTimeLabel[part] : formatMinute(scheduled)),
      });
    }
  }
  doses.sort((a, b) => parts.indexOf(a.part) - parts.indexOf(b.part));
  return {
    day: viewDay,
    label: sitterAuth.label,
    pets: snapshot.pets.map((pet) => ({ id: pet.id, name: pet.name, species: pet.species, photoUrl: pet.photoUrl })),
    doses,
  };
}

export async function sitterLogDose(pool, sitterAuth, body) {
  const entry = readLog({
    ...body,
    memberId: sitterAuth.memberId,
    timeLabel: body?.timeLabel ?? formatTimeLabel(),
  });
  const result = await logDose(pool, sitterAuth, entry);
  return result;
}

/** Most doses carried in one push's data (APNs payloads max out at 4 KB). */
const pushDoseCap = 20;

/** "Sam gave Miso's Insulin · 8:02 AM" — the visible line for one dose. */
export function doseNotificationText({ who, petName, medName, outcome, timeLabel }) {
  const what = petName ? `${petName}'s ${medName}` : medName;
  const verb =
    outcome === "given" ? `${who} gave ${what}` : outcome === "skipped" ? `${who} skipped ${what}` : `${who} isn't sure ${what} was given`;
  return timeLabel ? `${verb} · ${timeLabel}` : verb;
}

/**
 * Tells the rest of the household about new dose logs. Accepts one log or a
 * batch (outbox replay): the device-token lookup runs first and alone, so the
 * common no-partner case costs one indexed query; a batch sends one summary
 * instead of a push per dose.
 *
 * iOS devices get two pushes: the visible alert, and a silent background
 * push carrying the doses so the phone can cancel its own reminder for them
 * (Apple only wakes an app for `content-available` pushes). Android gets one
 * message with both. Never the member who logged; browser sitters have no
 * device tokens. Tokens APNs/FCM call invalid are deleted. Best-effort:
 * callers run it after the response (runInBackground).
 */
export async function notifyHouseholdOnDose(pool, auth, logEntries, logFn, sender = pushSender()) {
  const entries = (Array.isArray(logEntries) ? logEntries : [logEntries]).filter(Boolean);
  if (entries.length === 0) return;
  const tokens = await pool.query(
    `SELECT member_id, token, platform, environment FROM device_tokens
     WHERE household_id = $1 AND member_id <> $2 AND push_enabled = true`,
    [auth.householdId, auth.memberId],
  );
  if (tokens.rowCount === 0) return;
  const devices = [];
  for (const row of tokens.rows) {
    if (sender.canSend(row)) devices.push(row);
    else if (row.platform === "ios" || row.platform === "android") sender.noteNotConfigured(row.platform, logFn);
  }
  if (devices.length === 0) return;

  const first = entries[0];
  const [medication, member] = await Promise.all([
    pool.query(
      `SELECT m.name, p.name AS pet_name FROM medications m
       LEFT JOIN pets p ON p.household_id = m.household_id AND p.id = m.pet_id
       WHERE m.household_id = $1 AND m.id = $2`,
      [auth.householdId, first.medicationId],
    ),
    pool.query("SELECT name, role FROM members WHERE household_id = $1 AND id = $2", [auth.householdId, auth.memberId]),
  ]);
  const rawName = member.rows[0]?.name ?? "Someone";
  // Owners are stored as "You" by the app; to anyone else that's "Owner".
  const who = member.rows[0]?.role === "owner" && /^you$/i.test(rawName) ? "Owner" : rawName;
  const single = entries.length === 1;
  const alert = {
    title: single && first.outcome !== "given" ? "Dose update" : "Dose logged",
    body: single
      ? doseNotificationText({
          who,
          petName: medication.rows[0]?.pet_name ?? "",
          medName: medication.rows[0]?.name ?? "a dose",
          outcome: first.outcome,
          timeLabel: first.timeLabel,
        })
      : `${who} logged ${entries.length} doses`,
  };
  const data = {
    type: "dose_logged",
    householdId: auth.householdId,
    doses: entries.slice(0, pushDoseCap).map((entry) => ({
      logId: entry.id,
      medicationId: entry.medicationId,
      part: entry.part,
      day: entry.day,
      outcome: entry.outcome,
    })),
  };
  const collapseId = single ? first.id : undefined;

  const invalid = new Set();
  let sent = 0;
  let failed = 0;
  await Promise.all(
    devices.map(async (device) => {
      const messages =
        device.platform === "ios"
          ? [
              { alert, data, collapseId, threadId: auth.householdId },
              { background: true, data },
            ]
          : [{ alert, data, collapseId }];
      for (const message of messages) {
        const result = await sender.send(device, message);
        if (result.ok) {
          sent += 1;
          continue;
        }
        failed += 1;
        if (result.invalid) {
          invalid.add(device.token);
          break; // no point sending the second push to a dead token
        }
        logFn("push.failed", { householdId: auth.householdId, platform: device.platform, reason: result.reason });
      }
    }),
  );
  if (invalid.size > 0) {
    await pool.query("DELETE FROM device_tokens WHERE household_id = $1 AND token = ANY($2::text[])", [
      auth.householdId,
      [...invalid],
    ]);
  }
  logFn("push.sent", {
    householdId: auth.householdId,
    devices: devices.length,
    sent,
    failed,
    removed: invalid.size,
    doses: entries.length,
  });
}

/** Events that carry the subscription's current expiry; Pro = not yet expired. */
const stateEvents = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  // Auto-renew off or billing retry: the user keeps Pro until expiry/grace end.
  "CANCELLATION",
  "BILLING_ISSUE",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "NON_RENEWING_PURCHASE",
  "REFUND_REVERSED",
]);

function secretMatches(given, secret) {
  if (typeof given !== "string" || !given || !secret) return false;
  // Equal-length digests: constant time and doesn't leak the secret's length.
  const a = createHash("sha256").update(given).digest();
  const b = createHash("sha256").update(secret).digest();
  return timingSafeEqual(a, b);
}

/**
 * RevenueCat sends the configured Authorization header value verbatim; it is
 * checked before the body is even read. Fails closed when no secret is set.
 */
export function revenueCatWebhookAuthorized(headerValue) {
  const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
  if (!secret) return { ok: false, reason: "secret_not_configured" };
  if (typeof headerValue !== "string" || !headerValue) return { ok: false, reason: "missing_header" };
  const given = headerValue.replace(/^Bearer\s+/i, "").trim();
  // Accept the secret configured with or without a "Bearer " prefix in RevenueCat.
  const expected = secret.replace(/^Bearer\s+/i, "").trim();
  return secretMatches(given, expected) ? { ok: true } : { ok: false, reason: "bad_secret" };
}

/** Household member for a RevenueCat customer. Apps log in as "<householdId>:<memberId>";
 * purchases made before joining arrive with that id in `aliases`. A bare member
 * id is only trusted when unique — every owner used to be "you". */
async function householdForCustomer(pool, ids) {
  for (const id of ids) {
    const split = id.indexOf(":");
    if (split <= 0) continue;
    const row = await pool.query(
      "SELECT household_id, id FROM members WHERE household_id = $1 AND id = $2",
      [id.slice(0, split), id.slice(split + 1)],
    );
    if (row.rows[0]) return { householdId: row.rows[0].household_id, memberId: row.rows[0].id };
  }
  for (const id of ids) {
    if (id.includes(":") || id.startsWith("$RCAnonymousID")) continue;
    const row = await pool.query("SELECT household_id, id FROM members WHERE id = $1 LIMIT 2", [id]);
    if (row.rowCount > 1) return { reason: "ambiguous_member" };
    if (row.rows[0]) return { householdId: row.rows[0].household_id, memberId: row.rows[0].id };
  }
  return { reason: "member_not_found" };
}

function customerIds(event, ...keys) {
  const ids = [];
  for (const key of keys) {
    const value = event?.[key];
    for (const id of Array.isArray(value) ? value : [value]) {
      if (typeof id === "string" && id && !ids.includes(id)) ids.push(id);
    }
  }
  return ids.slice(0, 20);
}

/**
 * Stores one member's entitlement. Retries and out-of-order deliveries: an
 * older event never overwrites a newer one *for that member* (each payer
 * has their own clock). Also refreshes the legacy households.is_pro copy so
 * a rollback to a v6 server still sees the right answer.
 */
async function applyProState(pool, householdId, memberId, { isPro, expiresAt, productId, eventAt }) {
  const result = await pool.query(
    `UPDATE members
     SET rc_is_pro = $3, rc_expires_at = $4, rc_product_id = COALESCE($5, rc_product_id), rc_event_at = $6
     WHERE household_id = $1 AND id = $2 AND (rc_event_at IS NULL OR rc_event_at <= $6)
     RETURNING id`,
    [householdId, memberId, isPro, expiresAt, productId, eventAt],
  );
  if (result.rowCount > 0) await refreshLegacyPro(pool, householdId);
  return result.rowCount > 0;
}

/** households.is_pro / rc_expires_at as an aggregate of the members (rollback safety only). */
async function refreshLegacyPro(pool, householdId) {
  const rows = (
    await pool.query("SELECT rc_is_pro, rc_expires_at FROM members WHERE household_id = $1 AND rc_is_pro", [householdId])
  ).rows.filter(memberHasPro);
  const lifetime = rows.some((row) => row.rc_expires_at == null);
  const latest = rows.reduce((max, row) => (row.rc_expires_at && (!max || row.rc_expires_at > max) ? row.rc_expires_at : max), null);
  await pool.query("UPDATE households SET is_pro = $2, rc_expires_at = $3 WHERE id = $1", [
    householdId,
    rows.length > 0,
    rows.length > 0 && !lifetime ? latest : rows.length > 0 ? null : new Date(),
  ]);
}

/**
 * A webhook without the shared secret is only a hint that something changed:
 * nothing in its body is trusted. For each household customer it names, ask
 * RevenueCat's API (REVENUECAT_SECRET_KEY) for the real `pro` state and store
 * that. A forged call can only make us re-read the truth. Returns `retry`
 * when RevenueCat can't be reached, so the webhook is delivered again.
 */
export async function verifyRevenueCatWebhookByLookup(pool, body, logFn) {
  const event = body?.event;
  const type = typeof event?.type === "string" ? event.type.slice(0, 40) : "";
  if (type === "TEST") {
    logFn("billing.webhook_test", { environment: event?.environment ?? "", verified: "lookup" });
    return { status: "ok", test: true };
  }
  const ids = customerIds(event, "app_user_id", "original_app_user_id", "aliases", "transferred_from", "transferred_to");
  // customer id → member. Each named member gets their own lookup.
  const targets = new Map();
  for (const id of ids) {
    const split = id.indexOf(":");
    if (split <= 0 || targets.size >= 5 || targets.has(id)) continue;
    const row = await pool.query("SELECT household_id, id FROM members WHERE household_id = $1 AND id = $2", [
      id.slice(0, split),
      id.slice(split + 1),
    ]);
    if (row.rows[0]) targets.set(id, { householdId: row.rows[0].household_id, memberId: row.rows[0].id });
  }
  if (targets.size === 0) return ignored(logFn, "member_not_found", type);

  for (const [customerId, { householdId, memberId }] of targets) {
    const pro = await fetchProEntitlement(customerId);
    if (!pro.ok) {
      logFn("billing.webhook_lookup_failed", { householdId, type, reason: pro.reason });
      return { status: "retry" };
    }
    await applyProState(pool, householdId, memberId, {
      isPro: pro.active,
      expiresAt: pro.expiresAt ?? (pro.active ? null : new Date()),
      productId: pro.productId,
      eventAt: new Date(),
    });
    logFn("billing.webhook", { householdId, type, isPro: pro.active, verified: "lookup" });
  }
  return { status: "ok" };
}

/** Ignored webhooks still answer 200 (RevenueCat would retry otherwise) but are logged. */
function ignored(logFn, reason, type) {
  logFn("billing.webhook_ignored", { reason, type: type || null });
  return { status: "ignored", reason };
}

export async function handleRevenueCatWebhook(pool, body, logFn) {
  const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
  if (!secret) {
    // Fail closed: without a secret anyone could grant themselves Pro.
    logFn("billing.webhook_secret_missing", {});
    return { status: "unauthorized" };
  }
  if (!secretMatches(body?.authorization, secret.replace(/^Bearer\s+/i, "").trim())) {
    return { status: "unauthorized" };
  }

  const event = body?.event;
  const type = typeof event?.type === "string" ? event.type : "";
  if (type === "TEST") {
    logFn("billing.webhook_test", { environment: event?.environment ?? "" });
    return { status: "ok", test: true };
  }
  if (!type) return ignored(logFn, "no_event", type);

  const entitlements = event.entitlement_ids;
  if (Array.isArray(entitlements) && entitlements.length > 0 && !entitlements.includes(proEntitlement)) {
    return ignored(logFn, "other_entitlement", type);
  }

  const eventAt = new Date(
    Number.isFinite(event.event_timestamp_ms) ? event.event_timestamp_ms : Date.now(),
  );
  const productId = typeof event.product_id === "string" ? event.product_id.slice(0, 200) : null;

  if (type === "TRANSFER") {
    // The subscription moved to another store account; the old owner loses it.
    // The new owner's app re-syncs Pro and the next renewal confirms it.
    const from = await householdForCustomer(pool, customerIds(event, "transferred_from"));
    if (!from.householdId) return ignored(logFn, from.reason, type);
    await applyProState(pool, from.householdId, from.memberId, { isPro: false, expiresAt: eventAt, productId: null, eventAt });
    logFn("billing.webhook", { householdId: from.householdId, type, isPro: false });
    return { status: "ok", isPro: false };
  }

  let isPro;
  let expiresAt = null;
  const refund = type === "CANCELLATION" && event.cancel_reason === "CUSTOMER_SUPPORT";
  if (type === "EXPIRATION" || refund) {
    // A refund (CANCELLATION + CUSTOMER_SUPPORT) ends Pro at once, even for
    // a lifetime purchase, whatever expiry the event carries.
    isPro = false;
    expiresAt = eventAt;
  } else if (stateEvents.has(type)) {
    const expiresMs = Number.isFinite(event.grace_period_expiration_at_ms)
      ? event.grace_period_expiration_at_ms
      : event.expiration_at_ms;
    if (Number.isFinite(expiresMs)) {
      expiresAt = new Date(expiresMs);
      isPro = expiresMs > Date.now();
    } else if (type === "CANCELLATION" || type === "BILLING_ISSUE") {
      // These never mean "lifetime": with no expiry to honour, end it now.
      isPro = false;
      expiresAt = eventAt;
    } else {
      isPro = true; // lifetime / non-expiring purchase
    }
  } else {
    return ignored(logFn, "event_type", type);
  }

  const found = await householdForCustomer(
    pool,
    customerIds(event, "app_user_id", "original_app_user_id", "aliases"),
  );
  if (!found.householdId) return ignored(logFn, found.reason, type);

  const applied = await applyProState(pool, found.householdId, found.memberId, { isPro, expiresAt, productId, eventAt });
  if (!applied) {
    logFn("billing.webhook_stale", { householdId: found.householdId, type });
    return { status: "ignored", reason: "stale_event" };
  }
  logFn("billing.webhook", {
    householdId: found.householdId,
    type,
    isPro,
    environment: event.environment ?? "",
  });
  return { status: "ok", isPro };
}

/** Photos are optional infrastructure: without the bucket the app keeps photos on the phone. */
function requirePhotos() {
  if (!photosConfigured()) throw new InputError("Photo sharing isn't available right now.", "photos bucket not configured");
}

async function petExists(pool, householdId, petId) {
  const row = await pool.query("SELECT photo_key FROM pets WHERE household_id = $1 AND id = $2", [householdId, petId]);
  return row.rows[0] ?? null;
}

/** Step 1: a 5-minute URL the phone PUTs the JPEG to directly. */
export async function startPetPhotoUpload(pool, { householdId }, petId, body) {
  requirePhotos();
  const pet = await petExists(pool, householdId, id(petId, "petId"));
  if (!pet) return null;
  const bytes = Number(body?.bytes);
  if (!checkPhotoSize(bytes)) {
    throw new InputError("That photo is too large. Try another one.", `photo bytes ${body?.bytes}`);
  }
  const photoKey = newPhotoKey(householdId, petId);
  return { photoKey, upload: presignUpload(photoKey, bytes) };
}

/** Step 2: attach the uploaded object to the pet and delete the old one. */
export async function attachPetPhoto(pool, { householdId }, petId, body, logFn = () => {}) {
  requirePhotos();
  const pet = await petExists(pool, householdId, id(petId, "petId"));
  if (!pet) return null;
  const photoKey = body?.photoKey;
  if (!keyBelongsTo(photoKey, householdId, petId)) throw new InputError(appProblem, "photoKey not for this pet");
  if (!(await photoExists(photoKey))) {
    throw new InputError("The photo didn't finish uploading. Try again.", "photo object missing");
  }
  await pool.query("UPDATE pets SET photo_key = $3 WHERE household_id = $1 AND id = $2", [householdId, petId, photoKey]);
  if (pet.photo_key && pet.photo_key !== photoKey) await deletePhoto(pet.photo_key, logFn);
  return { photoKey, photoUrl: presignView(photoKey) };
}

export async function removePetPhoto(pool, { householdId }, petId, logFn = () => {}) {
  const pet = await petExists(pool, householdId, id(petId, "petId"));
  if (!pet) return null;
  await pool.query("UPDATE pets SET photo_key = NULL WHERE household_id = $1 AND id = $2", [householdId, petId]);
  await deletePhoto(pet.photo_key, logFn);
  return { removed: Boolean(pet.photo_key) };
}

/**
 * DELETE /v1/account — App Store 5.1.1(v) account deletion.
 * Owner: the whole household goes (every table cascades from households), then
 * its pet photos are removed from the bucket. Other members' phones get 401
 * "This household no longer exists." on their next sync and keep their copy.
 * Caregiver / sitter: only their member record, push tokens and sitter access
 * go; past dose logs stay so the household's history remains accurate (they
 * show as a former member).
 */
export async function deleteAccount(pool, { householdId, memberId }, logFn = () => {}) {
  const member = await pool.query("SELECT role FROM members WHERE household_id = $1 AND id = $2", [householdId, memberId]);
  const role = member.rows[0]?.role;
  if (!role) return { deleted: false };

  if (role === "owner") {
    const photos = await pool.query("SELECT photo_key FROM pets WHERE household_id = $1 AND photo_key IS NOT NULL", [
      householdId,
    ]);
    await pool.query("DELETE FROM households WHERE id = $1", [householdId]);
    for (const row of photos.rows) await deletePhoto(row.photo_key, logFn);
    logFn("account.deleted", { householdId, role, scope: "household", photos: photos.rowCount });
    return { deleted: true, scope: "household" };
  }

  await transaction(pool, async (client) => {
    await client.query("DELETE FROM device_tokens WHERE household_id = $1 AND member_id = $2", [householdId, memberId]);
    await client.query("DELETE FROM sitter_links WHERE household_id = $1 AND member_id = $2", [householdId, memberId]);
    await client.query("DELETE FROM members WHERE household_id = $1 AND id = $2", [householdId, memberId]);
  });
  logFn("account.deleted", { householdId, role, scope: "member" });
  return { deleted: true, scope: "member" };
}
