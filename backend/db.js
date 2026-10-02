import { createHash, randomBytes } from "node:crypto";
import pg from "pg";

const { Pool } = pg;

const schemaVersion = "2";
const parts = ["morning", "afternoon", "evening"];
const species = ["cat", "dog", "rabbit", "other"];
const roles = ["owner", "caregiver", "sitter"];
const outcomes = ["given", "skipped"];
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
  if (current.rows[0]?.value !== schemaVersion) {
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
    `INSERT INTO medications (household_id, id, pet_id, name, amount, parts, supply_total, doses_left, start_day)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9)
     ON CONFLICT (household_id, id) DO UPDATE SET
       name = EXCLUDED.name, amount = EXCLUDED.amount, parts = EXCLUDED.parts,
       supply_total = EXCLUDED.supply_total, doses_left = EXCLUDED.doses_left, archived = false
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

export async function loadHousehold(pool, { householdId, memberId }) {
  const [house, members, pets, medications, logs] = await Promise.all([
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
  ]);
  const household = house.rows[0];
  if (!household) return null;
  return {
    household: {
      id: household.id,
      inviteCode: household.invite_code,
      isPro: household.is_pro,
      plan: household.plan,
    },
    memberId,
    members: members.rows.map((row) => mapMember(row, memberId)),
    pets: pets.rows.map(mapPet),
    medications: medications.rows.map(mapMedication),
    logs: logs.rows.map(mapLog),
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
    const inserted = await client.query(
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
    if (inserted.rowCount === 0) {
      const existing = await client.query(
        `SELECT * FROM dose_logs WHERE household_id = $1
         AND ((medication_id = $2 AND part = $3 AND day = $4) OR id = $5)`,
        [householdId, entry.medicationId, entry.part, entry.day, entry.id],
      );
      return { conflict: existing.rows[0] ? mapLog(existing.rows[0]) : null };
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

export async function startTrial(pool, { householdId }) {
  const result = await pool.query(
    "UPDATE households SET is_pro = true WHERE id = $1 RETURNING plan",
    [householdId],
  );
  return { isPro: true, plan: result.rows[0]?.plan ?? "yearly" };
}
