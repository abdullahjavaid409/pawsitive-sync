import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanResults, normalizeQuery, searchMedicines } from "../medicine_search.js";

/** Just enough of pg's Pool for the cache table. */
function fakePool() {
  const rows = new Map();
  return {
    rows,
    async query(sql, params) {
      if (sql.startsWith("SELECT")) {
        return rows.has(params[0])
          ? { rowCount: 1, rows: [{ results: rows.get(params[0]) }] }
          : { rowCount: 0, rows: [] };
      }
      if (!rows.has(params[0])) rows.set(params[0], JSON.parse(params[1]));
      return { rowCount: 1, rows: [] };
    },
  };
}

function groq(medicines, { ok = true, status = 200 } = {}) {
  let calls = 0;
  const impl = async () => {
    calls += 1;
    return {
      ok,
      status,
      json: async () => ({ choices: [{ message: { content: JSON.stringify({ medicines }) } }] }),
    };
  };
  return { impl, calls: () => calls };
}

function withKey(t) {
  process.env.GROQ_API_KEY = "test-key";
  t.after(() => delete process.env.GROQ_API_KEY);
}

test("normalizeQuery trims, lowercases and rejects junk", () => {
  assert.equal(normalizeQuery("  Carpro  "), "carpro");
  assert.equal(normalizeQuery("ab"), null);
  assert.equal(normalizeQuery("x".repeat(41)), null);
  assert.equal(normalizeQuery("<script>"), null);
  assert.equal(normalizeQuery(42), null);
});

test("cleanResults keeps valid rows, tidies names and species", () => {
  const out = cleanResults({
    medicines: [
      { name: "carprofen", form: "tablet", use: "pain relief", species: ["dog", "horse"] },
      { name: "Carprofen", form: "tablet", use: "dup" },
      { name: "", form: "tablet" },
      { name: "<b>x</b>", form: "tablet" },
      { name: "Rimadyl", form: "spray", use: "Pain" },
      { name: "Apoquel (oclacitinib)", form: "tablet", species: "dog" },
    ],
  });
  assert.deepEqual(out, [
    { name: "Carprofen", form: "tablet", use: "Pain relief", species: ["dog"] },
    { name: "Rimadyl", form: "other", use: "Pain", species: [] },
    { name: "Apoquel", form: "tablet", use: "", species: [] },
  ]);
  assert.deepEqual(cleanResults(null), []);
});

test("one Groq call per query, whatever pet is searching", async (t) => {
  withKey(t);
  const pool = fakePool();
  const reply = groq([{ name: "Carprofen", form: "tablet", use: "Pain", species: ["dog"] }]);
  const first = await searchMedicines(pool, { query: "Carp" }, reply.impl);
  assert.equal(first.source, "groq");
  const again = await searchMedicines(pool, { query: " carp " }, reply.impl);
  assert.equal(again.source, "cache");
  assert.equal(again.results[0].name, "Carprofen");
  assert.equal(reply.calls(), 1);
});

test("an empty answer is stored too, so it isn't asked again", async (t) => {
  withKey(t);
  const pool = fakePool();
  const reply = groq([]);
  await searchMedicines(pool, { query: "zzzq" }, reply.impl);
  const again = await searchMedicines(pool, { query: "zzzq" }, reply.impl);
  assert.equal(again.source, "cache");
  assert.equal(reply.calls(), 1);
});

test("Groq failures return nothing and are not stored", async (t) => {
  withKey(t);
  const pool = fakePool();
  const found = await searchMedicines(pool, { query: "apoq" }, groq([], { ok: false, status: 500 }).impl);
  assert.equal(found.source, "error");
  assert.deepEqual(found.results, []);
  assert.equal(pool.rows.size, 0);
});

test("no key: no call, empty results", async () => {
  delete process.env.GROQ_API_KEY;
  const reply = groq([{ name: "X", form: "tablet" }]);
  const found = await searchMedicines(fakePool(), { query: "apoq" }, reply.impl);
  assert.equal(found.source, "unconfigured");
  assert.equal(reply.calls(), 0);
});

test("an invalid query never reaches the cache or Groq", async () => {
  const reply = groq([]);
  const found = await searchMedicines(fakePool(), { query: "a" }, reply.impl);
  assert.equal(found.source, "invalid");
  assert.equal(reply.calls(), 0);
});

test("a spent daily budget stops paid calls but not cached answers", async (t) => {
  withKey(t);
  const pool = fakePool();
  const reply = groq([{ name: "Carprofen", form: "tablet", species: ["dog"] }]);
  await searchMedicines(pool, { query: "carp" }, reply.impl);
  const limited = await searchMedicines(pool, { query: "newq" }, reply.impl, () => false);
  assert.equal(limited.source, "limited");
  assert.equal(pool.rows.has("newq"), false);
  const cached = await searchMedicines(pool, { query: "carp" }, reply.impl, () => false);
  assert.equal(cached.source, "cache");
  assert.equal(reply.calls(), 1);
});
