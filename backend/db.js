import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import pg from "pg";
import { fetchProEntitlement, proEntitlement } from "./revenuecat.js";
import { checkPhotoSize, deletePhoto, keyBelongsTo, newPhotoKey, photoExists, photosConfigured, presignUpload, presignView } from "./photos.js";

const { Pool } = pg;

const schemaVersion = "6";

/** A missed RENEWAL webhook must not cut off a paying household right away. */
const storeExpirySlackMs = 24 * 60 * 60 * 1000;

/**
 * Pro only ever comes from RevenueCat (webhook or a server-side subscriber
 * lookup). Free trials are App Store intro offers, so RevenueCat reports
 * them as an active `pro` entitlement — the server never grants its own.
 */
function hasPro(household) {
  if (!household?.is_pro) return false;
  // Expiry from the last RevenueCat update also ends Pro if EXPIRATION never arrives.
  const expires = household.rc_expires_at;
  return expires == null || new Date(expires).getTime() + storeExpirySlackMs > Date.now();
}
const parts = ["morning", "afternoon", "evening"];
const species = ["cat", "dog", "rabbit", "other"];
const roles = ["owner", "caregiver", "sitter"];
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
    `INSERT INTO medications (household_id, id, pet_id, name, amount, parts, supply_total, doses_left, start_day, end_day)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10)
     ON CONFLICT (household_id, id) DO UPDATE SET
       name = EXCLUDED.name, amount = EXCLUDED.amount, parts = EXCLUDED.parts,
       supply_total = EXCLUDED.supply_total, doses_left = EXCLUDED.doses_left,
       end_day = EXCLUDED.end_day, archived = false
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
  const household = await pool.query("SELECT id FROM households WHERE invite_code = $1", [code]);
  if (household.rowCount === 0) return null;
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

export async function memberForToken(pool, token) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const result = await pool.query("SELECT household_id, id FROM members WHERE token_hash = $1", [hashToken(token)]);
  const row = result.rows[0];
  return row ? { householdId: row.household_id, memberId: row.id } : null;
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
          SELECT id, invite_code, is_pro, plan, rc_expires_at FROM households WHERE id = $1
        ) h) AS household,
       (SELECT coalesce(json_agg(m ORDER BY m.created_at), '[]'::json) FROM (
          SELECT id, name, role, token_hash IS NOT NULL AS joined, created_at
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
  return {
    household: {
      id: household.id,
      inviteCode: household.invite_code,
      isPro: hasPro(household),
      plan: household.plan,
    },
    memberId,
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

export async function addMedication(pool, { householdId }, body) {
  return insertMedication(pool, householdId, readMedication(body));
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
 * member's store account has `pro`, and share it with the household. Covers
 * purchases made before sharing, which no webhook ties to the household.
 */
export async function refreshProFromRevenueCat(pool, { householdId, memberId }, logFn = () => {}) {
  const pro = await fetchProEntitlement(`${householdId}:${memberId}`);
  if (!pro.ok) {
    logFn("billing.rc_refresh_failed", { householdId, reason: pro.reason });
  } else {
    if (pro.active) {
      await applyProState(pool, householdId, {
        isPro: true,
        expiresAt: pro.expiresAt,
        productId: pro.productId,
        eventAt: new Date(),
      });
    }
    // Not active: leave it. A partner may pay; EXPIRATION webhooks revoke.
    logFn("billing.rc_refresh", { householdId, active: pro.active });
  }
  const row = (
    await pool.query("SELECT plan, is_pro, rc_expires_at FROM households WHERE id = $1", [householdId])
  ).rows[0];
  return { isPro: hasPro(row), plan: row?.plan ?? "yearly" };
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

export async function registerDevice(pool, auth, body) {
  const platform = oneOf(body?.platform, ["ios", "android", "other"], "platform", "other");
  const token = text(body?.token, "token", { max: 512 });
  const pushEnabled = body?.pushEnabled !== false;
  await pool.query(
    `INSERT INTO device_tokens (household_id, member_id, platform, token, push_enabled, updated_at)
     VALUES ($1,$2,$3,$4,$5,now())
     ON CONFLICT (household_id, member_id, token) DO UPDATE SET
       push_enabled = EXCLUDED.push_enabled, updated_at = now()`,
    [auth.householdId, auth.memberId, platform, token, pushEnabled],
  );
  return { ok: true };
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
      results.push({
        id: opId,
        status: "error",
        message: error instanceof InputError ? error.message : "Operation failed",
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

function formatTimeLabel(date = new Date()) {
  let hour = date.getHours();
  const minute = date.getMinutes();
  const pm = hour >= 12;
  if (hour > 12) hour -= 12;
  if (hour === 0) hour = 12;
  return `${hour}:${String(minute).padStart(2, "0")} ${pm ? "PM" : "AM"}`;
}

export async function createSitterLink(pool, auth, body) {
  const pro = await pool.query("SELECT is_pro, rc_expires_at FROM households WHERE id = $1", [
    auth.householdId,
  ]);
  if (!hasPro(pro.rows[0])) {
    throw new ProRequiredError("Browser sitter links need Pawsitive Pro.");
  }
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

export async function sitterForToken(pool, token) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const result = await pool.query(
    `SELECT household_id, id, member_id, label FROM sitter_links
     WHERE token_hash = $1 AND expires_at > now()`,
    [hashToken(token)],
  );
  const row = result.rows[0];
  return row
    ? {
        householdId: row.household_id,
        memberId: row.member_id,
        linkId: row.id,
        label: row.label,
      }
    : null;
}

export async function getSitterView(pool, sitterAuth, query) {
  const viewDay = day(query?.day, "day");
  const hour = Math.min(Math.max(Number(query?.hour) || 0, 0), 23);
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
      let status = "upcoming";
      if (log?.outcome === "given") status = "given";
      else if (hour >= partOpensAt[part]) status = "due";
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
        timeLabel: log?.timeLabel ?? partTimeLabel[part],
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

/**
 * Tells the rest of the household about new dose logs. Accepts one log or a
 * batch (outbox replay): the device-token lookup runs first and alone, so the
 * common no-partner case costs one indexed query; a batch sends one summary
 * instead of a push per dose. Best-effort: callers don't await it on the
 * request path.
 */
export async function notifyHouseholdOnDose(pool, auth, logEntries, logFn) {
  const entries = (Array.isArray(logEntries) ? logEntries : [logEntries]).filter(Boolean);
  if (entries.length === 0) return;
  const tokens = await pool.query(
    `SELECT token, platform FROM device_tokens
     WHERE household_id = $1 AND member_id <> $2 AND push_enabled = true`,
    [auth.householdId, auth.memberId],
  );
  if (tokens.rowCount === 0) return;
  const first = entries[0];
  const [medication, member] = await Promise.all([
    pool.query("SELECT name FROM medications WHERE household_id = $1 AND id = $2", [
      auth.householdId,
      first.medicationId,
    ]),
    pool.query("SELECT name FROM members WHERE household_id = $1 AND id = $2", [
      auth.householdId,
      auth.memberId,
    ]),
  ]);
  const medName = medication.rows[0]?.name ?? "a dose";
  const who = member.rows[0]?.name ?? "Someone";
  const outcomeLabel =
    first.outcome === "given" ? "gave" : first.outcome === "skipped" ? "skipped" : "marked uncertain for";
  const single = entries.length === 1;
  const title = single && first.outcome !== "given" ? "Dose update" : "Dose logged";
  const body = single ? `${who} ${outcomeLabel} ${medName}` : `${who} logged ${entries.length} doses`;
  const fcmKey = process.env.FCM_SERVER_KEY;
  for (const row of tokens.rows) {
    logFn("push.queued", {
      householdId: auth.householdId,
      platform: row.platform,
      doses: entries.length,
      hasFcm: Boolean(fcmKey),
    });
    if (!fcmKey || row.platform === "ios" || !row.token.startsWith("fcm:")) continue;
    try {
      const response = await fetch("https://fcm.googleapis.com/fcm/send", {
        method: "POST",
        headers: {
          authorization: `key=${fcmKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          to: row.token.slice(4),
          notification: { title, body },
          data: { type: "dose_logged", logId: first.id },
        }),
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) logFn("push.failed", { householdId: auth.householdId, status: response.status });
    } catch (error) {
      logFn("push.failed", { householdId: auth.householdId, reason: String(error?.name ?? error).slice(0, 60) });
    }
  }
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

/** Household for a RevenueCat customer. Apps log in as "<householdId>:<memberId>";
 * purchases made before joining arrive with that id in `aliases`. A bare member
 * id is only trusted when unique — every owner used to be "you". */
async function householdForCustomer(pool, ids) {
  for (const id of ids) {
    const split = id.indexOf(":");
    if (split <= 0) continue;
    const row = await pool.query(
      "SELECT household_id FROM members WHERE household_id = $1 AND id = $2",
      [id.slice(0, split), id.slice(split + 1)],
    );
    if (row.rows[0]) return { householdId: row.rows[0].household_id };
  }
  for (const id of ids) {
    if (id.includes(":") || id.startsWith("$RCAnonymousID")) continue;
    const row = await pool.query("SELECT household_id FROM members WHERE id = $1 LIMIT 2", [id]);
    if (row.rowCount > 1) return { reason: "ambiguous_member" };
    if (row.rows[0]) return { householdId: row.rows[0].household_id };
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

async function applyProState(pool, householdId, { isPro, expiresAt, productId, eventAt }) {
  // Retries and out-of-order deliveries: never let an older event win.
  const result = await pool.query(
    `UPDATE households
     SET is_pro = $2, rc_expires_at = $3, rc_product_id = COALESCE($4, rc_product_id), rc_event_at = $5
     WHERE id = $1 AND (rc_event_at IS NULL OR rc_event_at <= $5)
     RETURNING id`,
    [householdId, isPro, expiresAt, productId, eventAt],
  );
  return result.rowCount > 0;
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
  const targets = new Map();
  for (const id of ids) {
    const split = id.indexOf(":");
    if (split <= 0 || targets.size >= 5) continue;
    const row = await pool.query("SELECT household_id FROM members WHERE household_id = $1 AND id = $2", [
      id.slice(0, split),
      id.slice(split + 1),
    ]);
    if (row.rows[0] && !targets.has(row.rows[0].household_id)) targets.set(row.rows[0].household_id, id);
  }
  if (targets.size === 0) return ignored(logFn, "member_not_found", type);

  for (const [householdId, customerId] of targets) {
    const pro = await fetchProEntitlement(customerId);
    if (!pro.ok) {
      logFn("billing.webhook_lookup_failed", { householdId, type, reason: pro.reason });
      return { status: "retry" };
    }
    await applyProState(pool, householdId, {
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
    await applyProState(pool, from.householdId, { isPro: false, expiresAt: eventAt, productId: null, eventAt });
    logFn("billing.webhook", { householdId: from.householdId, type, isPro: false });
    return { status: "ok", isPro: false };
  }

  let isPro;
  let expiresAt = null;
  if (type === "EXPIRATION") {
    isPro = false;
    expiresAt = eventAt;
  } else if (stateEvents.has(type)) {
    const expiresMs = Number.isFinite(event.grace_period_expiration_at_ms)
      ? event.grace_period_expiration_at_ms
      : event.expiration_at_ms;
    if (Number.isFinite(expiresMs)) {
      expiresAt = new Date(expiresMs);
      isPro = expiresMs > Date.now();
    } else {
      isPro = true; // lifetime / non-expiring
    }
  } else {
    return ignored(logFn, "event_type", type);
  }

  const found = await householdForCustomer(
    pool,
    customerIds(event, "app_user_id", "original_app_user_id", "aliases"),
  );
  if (!found.householdId) return ignored(logFn, found.reason, type);

  const applied = await applyProState(pool, found.householdId, { isPro, expiresAt, productId, eventAt });
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
