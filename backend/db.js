import pg from "pg";

const { Pool } = pg;

export function createPool(connectionString) {
  return new Pool({
    connectionString,
    max: 3,
    idleTimeoutMillis: 10_000,
  });
}

export async function migrate(pool, log) {
  const started = Date.now();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS settings (
      id integer PRIMARY KEY CHECK (id = 1),
      is_pro boolean NOT NULL,
      plan text NOT NULL
    );
    CREATE TABLE IF NOT EXISTS members (
      id text PRIMARY KEY,
      name text NOT NULL,
      initials text NOT NULL,
      role text NOT NULL,
      avatar_tone text NOT NULL,
      status text,
      active boolean NOT NULL DEFAULT false,
      is_you boolean NOT NULL DEFAULT false
    );
    CREATE TABLE IF NOT EXISTS pets (
      id text PRIMARY KEY,
      name text NOT NULL,
      species text NOT NULL,
      age_years integer NOT NULL,
      breed text NOT NULL,
      sex text NOT NULL,
      conditions jsonb NOT NULL,
      weight_kg double precision NOT NULL,
      on_time_percent integer NOT NULL,
      daily_meds integer NOT NULL
    );
    CREATE TABLE IF NOT EXISTS doses (
      id text PRIMARY KEY,
      pet_id text NOT NULL,
      medication_id text NOT NULL,
      name text NOT NULL,
      amount text NOT NULL,
      part text NOT NULL,
      status text NOT NULL,
      subtitle text NOT NULL,
      given_by_id text
    );
    CREATE TABLE IF NOT EXISTS medications (
      id text PRIMARY KEY,
      pet_id text NOT NULL,
      name text NOT NULL,
      detail text NOT NULL,
      dose_label text NOT NULL,
      when_label text NOT NULL,
      fallback_label text NOT NULL,
      doses_left integer NOT NULL,
      supply_total integer NOT NULL,
      lasts_until text NOT NULL,
      on_time_label text NOT NULL,
      history jsonb NOT NULL
    );
    CREATE TABLE IF NOT EXISTS activity (
      id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      member_id text NOT NULL,
      actor text NOT NULL,
      action text NOT NULL,
      emphasis text NOT NULL,
      time_label text NOT NULL,
      note text
    );
    CREATE INDEX IF NOT EXISTS doses_pet_id_idx ON doses (pet_id);
    CREATE INDEX IF NOT EXISTS doses_status_idx ON doses (status);
    CREATE INDEX IF NOT EXISTS activity_member_id_idx ON activity (member_id);
    CREATE INDEX IF NOT EXISTS medications_pet_id_idx ON medications (pet_id);
  `);
  log("db.migrated", { durationMs: Date.now() - started });
}

const seedMembers = [
  ["you", "You", "You", "owner", "brand", null, false, true],
  ["sara", "Sara", "S", "caregiver", "soft", "Active now", true, false],
  ["dan", "Dan", "D", "caregiver", "neutral", "On duty tonight", false, false],
  ["priya", "Priya", "P", "sitter", "neutral", "Oct 5 – Oct 12", false, false],
];

const seedPets = [
  ["miso", "Miso", "cat", 12, "Domestic shorthair", "female", ["Diabetes", "Kidney disease"], 4.6, 97, 3],
  ["juniper", "Juniper", "dog", 8, "Mixed breed", "female", ["Arthritis"], 18.2, 100, 1],
];

const seedDoses = [
  ["insulin-am", "miso", "insulin", "Insulin", "2 units", "morning", "given", "Miso · Sara, 8:02 AM", "sara"],
  ["benazepril-am", "miso", "benazepril", "Benazepril", "2.5 mg", "morning", "given", "Miso · Sara, 8:04 AM", "sara"],
  ["joint-am", "juniper", "joint", "Joint supplement", "", "morning", "given", "Juniper · Dan, 8:30 AM", "dan"],
  ["fluids-pm", "miso", "fluids", "Fluids", "100 ml", "afternoon", "due", "Miso · due 1:00 PM", null],
  ["insulin-pm", "miso", "insulin", "Insulin", "2 units", "evening", "upcoming", "Miso · 8:00 PM with food · Dan", null],
];

export async function seedIfEmpty(pool, log) {
  const existing = await pool.query("SELECT 1 FROM settings WHERE id = 1");
  if (existing.rowCount > 0) {
    log("db.seed_skipped", { reason: "already_seeded" });
    return;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("INSERT INTO settings (id, is_pro, plan) VALUES (1, false, 'yearly')");
    for (const row of seedMembers) {
      await client.query(
        `INSERT INTO members (id, name, initials, role, avatar_tone, status, active, is_you)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        row,
      );
    }
    for (const row of seedPets) {
      await client.query(
        `INSERT INTO pets (id, name, species, age_years, breed, sex, conditions, weight_kg, on_time_percent, daily_meds)
         VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$10)`,
        [row[0], row[1], row[2], row[3], row[4], row[5], JSON.stringify(row[6]), row[7], row[8], row[9]],
      );
    }
    for (const row of seedDoses) {
      await client.query(
        `INSERT INTO doses (id, pet_id, medication_id, name, amount, part, status, subtitle, given_by_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        row,
      );
    }
    await client.query(
      `INSERT INTO medications (
         id, pet_id, name, detail, dose_label, when_label, fallback_label,
         doses_left, supply_total, lasts_until, on_time_label, history
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb)`,
      [
        "benazepril",
        "miso",
        "Benazepril",
        "2.5 mg tablet · Miso · kidney support",
        "1 tablet",
        "Daily, 8:00 AM",
        "Ping Sara after 30 min",
        4,
        30,
        "Tue, Oct 6",
        "29 of 30 on time this month",
        JSON.stringify([
          { when: "Today · 8:04 AM", who: "Sara" },
          { when: "Thu · 8:11 AM", who: "Dan" },
          { when: "Wed · 9:40 AM", who: "You", lateNote: "1h 40m late" },
        ]),
      ],
    );
    const activity = [
      ["sara", "Sara", "gave Miso", "Insulin · 2 units", "8:02 AM", null],
      ["sara", "Sara", "gave Miso", "Benazepril", "8:04 AM", null],
      ["dan", "Dan", "noted for Miso", "", "8:20 AM", "Vomited a little after breakfast"],
    ];
    for (const row of activity) {
      await client.query(
        `INSERT INTO activity (member_id, actor, action, emphasis, time_label, note)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        row,
      );
    }
    await client.query("COMMIT");
    log("db.seeded", { members: seedMembers.length, pets: seedPets.length, doses: seedDoses.length });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function mapMember(row) {
  return {
    id: row.id,
    name: row.name,
    initials: row.initials,
    role: row.role,
    avatarTone: row.avatar_tone,
    ...(row.status ? { status: row.status } : {}),
    ...(row.active ? { active: true } : {}),
    ...(row.is_you ? { isYou: true } : {}),
  };
}

function mapPet(row) {
  return {
    id: row.id,
    name: row.name,
    species: row.species,
    ageYears: row.age_years,
    breed: row.breed,
    sex: row.sex,
    conditions: row.conditions,
    weightKg: row.weight_kg,
    onTimePercent: row.on_time_percent,
    dailyMeds: row.daily_meds,
  };
}

function mapDose(row) {
  return {
    id: row.id,
    petId: row.pet_id,
    medicationId: row.medication_id,
    name: row.name,
    amount: row.amount,
    part: row.part,
    status: row.status,
    subtitle: row.subtitle,
    ...(row.given_by_id ? { givenById: row.given_by_id } : {}),
  };
}

function mapMedication(row) {
  return {
    id: row.id,
    petId: row.pet_id,
    name: row.name,
    detail: row.detail,
    doseLabel: row.dose_label,
    whenLabel: row.when_label,
    fallbackLabel: row.fallback_label,
    dosesLeft: row.doses_left,
    supplyTotal: row.supply_total,
    lastsUntil: row.lasts_until,
    onTimeLabel: row.on_time_label,
    history: row.history,
  };
}

function mapActivity(row) {
  return {
    memberId: row.member_id,
    actor: row.actor,
    action: row.action,
    emphasis: row.emphasis,
    timeLabel: row.time_label,
    ...(row.note ? { note: row.note } : {}),
  };
}

export async function loadHousehold(pool) {
  const [settings, members, pets, doses, medications, activity] = await Promise.all([
    pool.query("SELECT is_pro, plan FROM settings WHERE id = 1"),
    pool.query("SELECT * FROM members ORDER BY is_you DESC, name"),
    pool.query("SELECT * FROM pets ORDER BY name"),
    pool.query("SELECT * FROM doses"),
    pool.query("SELECT * FROM medications"),
    pool.query("SELECT * FROM activity ORDER BY id DESC"),
  ]);
  const setting = settings.rows[0];
  return {
    isPro: setting?.is_pro ?? false,
    plan: setting?.plan ?? "yearly",
    members: members.rows.map(mapMember),
    pets: pets.rows.map(mapPet),
    doses: doses.rows.map(mapDose),
    medications: medications.rows.map(mapMedication),
    activity: activity.rows.map(mapActivity),
  };
}

export async function logDose(pool, doseId, body) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const doseResult = await client.query("SELECT * FROM doses WHERE id = $1 FOR UPDATE", [doseId]);
    const memberResult = await client.query("SELECT * FROM members WHERE id = $1", [body.memberId]);
    const dose = doseResult.rows[0];
    const member = memberResult.rows[0];
    if (!dose || !member || typeof body.amount !== "string" || typeof body.timeLabel !== "string") {
      await client.query("ROLLBACK");
      return null;
    }
    const petResult = await client.query("SELECT name FROM pets WHERE id = $1", [dose.pet_id]);
    const petName = petResult.rows[0]?.name ?? "Pet";
    const who = member.is_you ? "You" : member.name;
    const subtitle = `${petName} · ${who}, ${body.timeLabel}`;
    const updated = await client.query(
      `UPDATE doses SET status = 'given', amount = $2, given_by_id = $3, subtitle = $4 WHERE id = $1 RETURNING *`,
      [doseId, body.amount, member.id, subtitle],
    );
    const note = { vomited: "Vomited a little after the dose", partial: "Partial dose", lowAppetite: "Low appetite" }[body.outcome] ?? null;
    const emphasis = body.amount ? `${dose.name} · ${body.amount}` : dose.name;
    const activity = await client.query(
      `INSERT INTO activity (member_id, actor, action, emphasis, time_label, note)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [member.id, who, `gave ${petName}`, emphasis, body.timeLabel, note],
    );
    await client.query("COMMIT");
    return { dose: mapDose(updated.rows[0]), activity: mapActivity(activity.rows[0]) };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function skipDose(pool, doseId) {
  const result = await pool.query("DELETE FROM doses WHERE id = $1", [doseId]);
  return result.rowCount > 0;
}

export async function refillMedication(pool, medicationId) {
  const result = await pool.query(
    "UPDATE medications SET doses_left = supply_total WHERE id = $1 RETURNING *",
    [medicationId],
  );
  return result.rows[0] ? mapMedication(result.rows[0]) : null;
}

export async function setPlan(pool, plan) {
  if (plan !== "yearly" && plan !== "monthly") return null;
  await pool.query("UPDATE settings SET plan = $1 WHERE id = 1", [plan]);
  return plan;
}

export async function startTrial(pool) {
  await pool.query("UPDATE settings SET is_pro = true WHERE id = 1");
  const result = await pool.query("SELECT plan FROM settings WHERE id = 1");
  return { isPro: true, plan: result.rows[0]?.plan ?? "yearly" };
}
