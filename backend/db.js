import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import pg from "pg";

const { Pool } = pg;

const schemaVersion = "6";
const trialDays = 7;

/** A missed RENEWAL webhook must not cut off a paying household right away. */
const storeExpirySlackMs = 24 * 60 * 60 * 1000;

/** Paid (store webhook) or inside the one free trial. */
function hasPro(household) {
  if (!household) return false;
  if (household.is_pro) {
    // Expiry from the last webhook also ends Pro if EXPIRATION never arrives.
    const expires = household.rc_expires_at;
    if (expires == null || new Date(expires).getTime() + storeExpirySlackMs > Date.now()) {
      return true;
    }
  }
  return household.trial_ends_at != null && new Date(household.trial_ends_at) > new Date();
}
const parts = ["morning", "afternoon", "evening"];
const species = ["cat", "dog", "rabbit", "other"];
const roles = ["owner", "caregiver", "sitter"];
const outcomes = ["given", "skipped", "uncertain"];
const codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function createPool(connectionString) {
  return new Pool({
    connectionString,
    max: 5,
    idleTimeoutMillis: 10_000,
  });
}

export async function migrate(pool, log) {
  const started = Date.now();
  await pool.query("CREATE TABLE IF NOT EXISTS meta (key text PRIMARY KEY, value text NOT NULL)");
  const current = await pool.query("SELECT value FROM meta WHERE key = 'schema_version'");
  const fromVersion = current.rows[0]?.value ?? null;
  if (fromVersion === "1" || fromVersion === null) {
    // Version 1 held one shared demo household with no owners; nothing in it is user data.
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
  await pool.query(
    `INSERT INTO meta (key, value) VALUES ('schema_version', $1)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [schemaVersion],
  );
  log("db.migrated", { version: schemaVersion, durationMs: Date.now() - started });
}

export class InputError extends Error {
  constructor(message) {
    super(message);
    this.status = 400;
  }
}

function text(value, field, { max = 80, required = true } = {}) {
  const result = typeof value === "string" ? value.trim().slice(0, max) : "";
  if (required && !result) throw new InputError(`${field} is required`);
  return result;
}

function id(value, field) {
  if (typeof value !== "string" || !/^[a-z0-9-]{1,40}$/.test(value)) {
    throw new InputError(`${field} is not valid`);
  }
  return value;
}

function oneOf(value, allowed, field, fallback) {
  if (allowed.includes(value)) return value;
  if (fallback !== undefined) return fallback;
  throw new InputError(`${field} is not valid`);
}

function day(value, field) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new InputError(`${field} must be YYYY-MM-DD`);
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
    conditions: list(input?.conditions, 12)
      .map((item) => text(item, "condition", { max: 40, required: false }))
      .filter(Boolean),
  };
}

function readMedication(input) {
  const chosen = [...new Set(list(input?.parts, 3))].filter((part) => parts.includes(part));
  if (chosen.length === 0) throw new InputError("Pick at least one time of day");
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
    endDay: text(input?.endDay, "medication.endDay", { max: 10, required: false }) || "",
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
    `INSERT INTO pets (household_id, id, name, species, age_years, weight_kg, conditions)
     VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)
     ON CONFLICT (household_id, id) DO UPDATE SET
       name = EXCLUDED.name, species = EXCLUDED.species, age_years = EXCLUDED.age_years,
       weight_kg = EXCLUDED.weight_kg, conditions = EXCLUDED.conditions
     RETURNING *`,
    [householdId, pet.id, pet.name, pet.species, pet.ageYears, pet.weightKg, JSON.stringify(pet.conditions)],
  );
  return mapPet(result.rows[0]);
}

async function insertMedication(client, householdId, medication) {
  const pet = await client.query("SELECT 1 FROM pets WHERE household_id = $1 AND id = $2", [
    householdId,
    medication.petId,
  ]);
  if (pet.rowCount === 0) throw new InputError("That pet is not in this household");
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
  try {
    await client.query("BEGIN");
    const result = await work(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
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
    for (const entry of logs) {
      await client.query(
        `INSERT INTO dose_logs (household_id, id, medication_id, part, day, member_id, outcome, amount, note, time_label)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT DO NOTHING`,
        [
          householdId,
          entry.id,
          entry.medicationId,
          entry.part,
          entry.day,
          entry.memberId ?? ownerId,
          entry.outcome,
          entry.amount,
          entry.note,
          entry.timeLabel,
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
  await pool.query(
    `INSERT INTO members (household_id, id, name, role, token_hash) VALUES ($1,$2,$3,$4,$5)`,
    [householdId, memberId, name, oneOf(body?.role, ["caregiver", "sitter"], "role", "caregiver"), hashToken(token)],
  );
  return { token, householdId, memberId };
}

export async function memberForToken(pool, token) {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const result = await pool.query("SELECT household_id, id FROM members WHERE token_hash = $1", [hashToken(token)]);
  const row = result.rows[0];
  return row ? { householdId: row.household_id, memberId: row.id } : null;
}

function mapMember(row, memberId) {
  return {
    id: row.id,
    name: row.name,
    role: row.role,
    joined: row.token_hash !== null,
    ...(row.id === memberId ? { isYou: true } : {}),
  };
}

function mapPet(row) {
  return {
    id: row.id,
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

export async function loadHousehold(pool, { householdId, memberId }) {
  const [house, members, pets, medications, logs, careEvents] = await Promise.all([
    pool.query("SELECT * FROM households WHERE id = $1", [householdId]),
    pool.query("SELECT * FROM members WHERE household_id = $1 ORDER BY created_at", [householdId]),
    pool.query("SELECT * FROM pets WHERE household_id = $1 ORDER BY created_at", [householdId]),
    pool.query(
      "SELECT * FROM medications WHERE household_id = $1 AND archived = false ORDER BY created_at",
      [householdId],
    ),
    pool.query(
      `SELECT * FROM dose_logs WHERE household_id = $1
       AND created_at > now() - interval '100 days' ORDER BY created_at DESC LIMIT 3000`,
      [householdId],
    ),
    pool.query(
      "SELECT * FROM care_events WHERE household_id = $1 ORDER BY due_day ASC LIMIT 200",
      [householdId],
    ),
  ]);
  const household = house.rows[0];
  if (!household) return null;
  return {
    household: {
      id: household.id,
      inviteCode: household.invite_code,
      isPro: hasPro(household),
      plan: household.plan,
    },
    memberId,
    members: members.rows.map((row) => mapMember(row, memberId)),
    pets: pets.rows.map(mapPet),
    medications: medications.rows.map(mapMedication),
    logs: logs.rows.map(mapLog),
    careEvents: careEvents.rows.map(mapCareEvent),
  };
}

export async function addPet(pool, { householdId }, body) {
  const existing = await pool.query("SELECT count(*)::int AS n FROM pets WHERE household_id = $1", [householdId]);
  if (existing.rows[0].n >= 10) throw new InputError("A household can have up to 10 pets");
  return insertPet(pool, householdId, readPet(body));
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
    "UPDATE medications SET archived = true WHERE household_id = $1 AND id = $2",
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

/** One free trial per household; asking again never extends it. */
export async function startTrial(pool, { householdId }) {
  const result = await pool.query(
    `UPDATE households
     SET trial_ends_at = COALESCE(trial_ends_at, now() + make_interval(days => $2))
     WHERE id = $1 RETURNING plan, is_pro, trial_ends_at, rc_expires_at`,
    [householdId, trialDays],
  );
  const row = result.rows[0];
  return { isPro: hasPro(row), plan: row?.plan ?? "yearly" };
}

export async function addCareEvent(pool, { householdId }, body) {
  const event = readCareEvent(body);
  const pet = await pool.query("SELECT 1 FROM pets WHERE household_id = $1 AND id = $2", [
    householdId,
    event.petId,
  ]);
  if (pet.rowCount === 0) throw new InputError("That pet is not in this household");
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
  if (owner.rowCount === 0) throw new InputError("Only the household owner can link Apple Sign-In");
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
  await pool.query("DELETE FROM device_tokens WHERE household_id = $1 AND member_id = $2", [
    householdId,
    memberId,
  ]);
  const result = await pool.query(
    "DELETE FROM members WHERE household_id = $1 AND id = $2 AND role <> 'owner'",
    [householdId, memberId],
  );
  if (result.rowCount > 0) return { left: true };
  const owner = await pool.query(
    "SELECT 1 FROM members WHERE household_id = $1 AND id = $2 AND role = 'owner'",
    [householdId, memberId],
  );
  if (owner.rowCount === 0) return { left: false };
  await pool.query("UPDATE members SET token_hash = NULL WHERE household_id = $1 AND id = $2", [
    householdId,
    memberId,
  ]);
  return { left: true, ownerSignedOut: true };
}

export async function exportHouseholdData(pool, { householdId, memberId }) {
  const snapshot = await loadHousehold(pool, { householdId, memberId });
  if (!snapshot) return null;
  return {
    exportedAt: new Date().toISOString(),
    ...snapshot,
  };
}

export async function trackAnalytics(pool, events) {
  const list = Array.isArray(events) ? events.slice(0, 50) : [];
  for (const item of list) {
    const name = text(item?.name, "event.name", { max: 64, required: false });
    if (!name) continue;
    const safe = name.replace(/[^a-z0-9_.]/gi, "").slice(0, 48);
    if (!safe) continue;
    await pool.query(
      `INSERT INTO analytics_daily (day, event, count) VALUES (CURRENT_DATE, $1, 1)
       ON CONFLICT (day, event) DO UPDATE SET count = analytics_daily.count + 1`,
      [safe],
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
      throw new InputError(`Unknown operation type: ${type}`);
  }
}

export async function applyBatch(pool, auth, body, logFn) {
  const operations = list(body?.operations, 100);
  const results = [];
  for (const operation of operations) {
    const opId = text(operation?.id, "operation.id", { max: 48, required: false }) || newId("op");
    try {
      const result = await applyBatchOperation(pool, auth, operation);
      if (result.status === "ok" && result.log && operation?.type === "logDose") {
        await notifyHouseholdOnDose(pool, auth, result.log, logFn);
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
  return { results, household: await loadHousehold(pool, auth) };
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
  const pro = await pool.query("SELECT is_pro, trial_ends_at, rc_expires_at FROM households WHERE id = $1", [
    auth.householdId,
  ]);
  if (!hasPro(pro.rows[0])) {
    throw new InputError("Browser sitter links need PawsitiveSync Pro.");
  }
  const label = text(body?.label, "label", { max: 40, required: false }) || "Sitter";
  const linkId = newId("slink");
  const memberId = newId("sitter");
  const token = newToken();
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await pool.query(
    `INSERT INTO members (household_id, id, name, role) VALUES ($1,$2,$3,'sitter')`,
    [auth.householdId, memberId, label],
  );
  await pool.query(
    `INSERT INTO sitter_links (household_id, id, member_id, token_hash, label, expires_at)
     VALUES ($1,$2,$3,$4,$5,$6)`,
    [auth.householdId, linkId, memberId, hashToken(token), label, expiresAt],
  );
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
  const snapshot = await loadHousehold(pool, sitterAuth);
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
    pets: snapshot.pets.map((pet) => ({ id: pet.id, name: pet.name, species: pet.species })),
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

export async function notifyHouseholdOnDose(pool, auth, logEntry, logFn) {
  const [tokens, medication, member] = await Promise.all([
    pool.query(
      `SELECT token, platform FROM device_tokens
       WHERE household_id = $1 AND member_id <> $2 AND push_enabled = true`,
      [auth.householdId, auth.memberId],
    ),
    pool.query("SELECT name FROM medications WHERE household_id = $1 AND id = $2", [
      auth.householdId,
      logEntry.medicationId,
    ]),
    pool.query("SELECT name FROM members WHERE household_id = $1 AND id = $2", [
      auth.householdId,
      auth.memberId,
    ]),
  ]);
  if (tokens.rowCount === 0) return;
  const medName = medication.rows[0]?.name ?? "a dose";
  const who = member.rows[0]?.name ?? "Someone";
  const outcomeLabel =
    logEntry.outcome === "given"
      ? "gave"
      : logEntry.outcome === "skipped"
        ? "skipped"
        : "marked uncertain for";
  const title = logEntry.outcome === "given" ? "Dose logged" : "Dose update";
  const body = `${who} ${outcomeLabel} ${medName}`;
  const fcmKey = process.env.FCM_SERVER_KEY;
  for (const row of tokens.rows) {
    logFn("push.queued", {
      householdId: auth.householdId,
      platform: row.platform,
      hasFcm: Boolean(fcmKey),
    });
    if (!fcmKey || row.platform === "ios" || !row.token.startsWith("fcm:")) continue;
    try {
      await fetch("https://fcm.googleapis.com/fcm/send", {
        method: "POST",
        headers: {
          authorization: `key=${fcmKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          to: row.token.slice(4),
          notification: { title, body },
          data: { type: "dose_logged", logId: logEntry.id },
        }),
      });
    } catch (error) {
      logFn("push.failed", { reason: String(error?.message ?? error).slice(0, 120) });
    }
  }
}

const proEntitlement = "pro";

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
  if (typeof given !== "string") return false;
  const a = Buffer.from(given);
  const b = Buffer.from(secret);
  return a.length === b.length && timingSafeEqual(a, b);
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

export async function handleRevenueCatWebhook(pool, body, logFn) {
  const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
  if (!secret) {
    // Fail closed: without a secret anyone could grant themselves Pro.
    logFn("billing.webhook_secret_missing", {});
    return { status: "unauthorized" };
  }
  if (!secretMatches(body?.authorization, secret)) return { status: "unauthorized" };

  const event = body?.event;
  const type = typeof event?.type === "string" ? event.type : "";
  if (type === "TEST") {
    logFn("billing.webhook_test", { environment: event?.environment ?? "" });
    return { status: "ok", test: true };
  }
  if (!type) return { status: "ignored", reason: "no_event" };

  const entitlements = event.entitlement_ids;
  if (Array.isArray(entitlements) && entitlements.length > 0 && !entitlements.includes(proEntitlement)) {
    return { status: "ignored", reason: "other_entitlement" };
  }

  const eventAt = new Date(
    Number.isFinite(event.event_timestamp_ms) ? event.event_timestamp_ms : Date.now(),
  );
  const productId = typeof event.product_id === "string" ? event.product_id.slice(0, 200) : null;

  if (type === "TRANSFER") {
    // The subscription moved to another store account; the old owner loses it.
    // The new owner's app re-syncs Pro and the next renewal confirms it.
    const from = await householdForCustomer(pool, customerIds(event, "transferred_from"));
    if (!from.householdId) return { status: "ignored", reason: from.reason };
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
    return { status: "ignored", reason: "event_type" };
  }

  const found = await householdForCustomer(
    pool,
    customerIds(event, "app_user_id", "original_app_user_id", "aliases"),
  );
  if (!found.householdId) return { status: "ignored", reason: found.reason };

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
