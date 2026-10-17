// Medicine name search for names the app doesn't ship with. Each query is
// answered by Groq once and stored for everyone; results carry the species
// they're used in, so one call serves cats, dogs and rabbits alike.
// Suggestions only: never doses.

const speciesNames = ["cat", "dog", "rabbit"];
const forms = new Set(["tablet", "capsule", "liquid", "injection", "drops", "topical", "chew", "other"]);
const maxResults = 8;
const timeoutMs = 6000;
// 120b, not 20b: the smaller model misses common drugs and invents names.
const model = process.env.GROQ_MODEL || "openai/gpt-oss-120b";

/** "  Carpro " → "carpro"; null when it isn't a searchable name. */
export function normalizeQuery(raw) {
  if (typeof raw !== "string") return null;
  const q = raw.trim().toLowerCase().replace(/\s+/g, " ");
  if (q.length < 3 || q.length > 40) return null;
  if (!/^[\p{L}\p{N} '.+-]+$/u.test(q)) return null;
  return q;
}

/** Well-formed rows only; the model's reply is never trusted as is. */
export function cleanResults(value) {
  const list = Array.isArray(value?.medicines) ? value.medicines : [];
  const seen = new Set();
  const out = [];
  for (const item of list) {
    // One plain name per row: brackets tend to hold a second product's name.
    const name = typeof item?.name === "string" ? item.name.replace(/\s*[([].*$/, "").trim() : "";
    if (!name || name.length > 60 || /[<>{}]/.test(name)) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    const species = Array.isArray(item?.species) ? speciesNames.filter((s) => item.species.includes(s)) : [];
    out.push({
      name: capitalize(name),
      form: forms.has(item?.form) ? item.form : "other",
      use: capitalize(typeof item?.use === "string" ? item.use.trim().slice(0, 40) : ""),
      species,
    });
    if (out.length >= maxResults) break;
  }
  return out;
}

function capitalize(text) {
  return text ? text[0].toUpperCase() + text.slice(1) : text;
}

const instructions =
  "You list real veterinary medicines for a pet medicine logging app. " +
  'Reply only JSON: {"medicines":[{"name":string,' +
  '"form":"tablet"|"capsule"|"liquid"|"injection"|"drops"|"topical"|"chew"|"other",' +
  '"use":string,"species":["cat"|"dog"|"rabbit"]}]}. ' +
  `Up to ${maxResults} items, most commonly prescribed first. Each item is ONE name exactly as printed on its label: ` +
  "a generic name or a single brand name, never both, never with brackets, never another product's name. " +
  "Brand and generic of the same drug are separate items. Only names that start with or closely match the search " +
  "(allow small typos). Only medicines vets use in cats, dogs or rabbits; no human-only brands. " +
  '"species" lists which of those it is used in. "use" is a plain-English purpose under 30 characters. ' +
  "If nothing matches, return an empty list. Never give doses or advice.";

async function askGroq(q, fetchImpl) {
  const key = process.env.GROQ_API_KEY;
  if (!key) return { results: [], source: "unconfigured" };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        temperature: 0,
        max_completion_tokens: 900,
        reasoning_effort: "low",
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: instructions },
          { role: "user", content: `search: ${q}` },
        ],
      }),
    });
    if (!response.ok) return { results: [], source: "error", status: response.status };
    const data = await response.json();
    const text = data?.choices?.[0]?.message?.content ?? "";
    return { results: cleanResults(JSON.parse(text)), source: "groq" };
  } catch (error) {
    return { results: [], source: error?.name === "AbortError" ? "timeout" : "error" };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * `{ results, source }`, source being cache | groq | limited | unconfigured |
 * error | timeout | invalid. Answers (empty ones too) are stored for good:
 * drug names don't change, so a query costs one model call, ever. Failures
 * aren't stored, so the next search retries. `canAsk()` is checked only
 * before a paid call; false means the caller's daily budget is spent.
 */
export async function searchMedicines(pool, { query }, fetchImpl = fetch, canAsk = () => true) {
  const q = normalizeQuery(query);
  if (!q) return { results: [], source: "invalid" };
  const cached = await pool.query("SELECT results FROM medicine_search_cache WHERE query = $1", [q]);
  if (cached.rowCount > 0) return { results: cached.rows[0].results, source: "cache" };
  if (!canAsk()) return { results: [], source: "limited" };
  const answer = await askGroq(q, fetchImpl);
  if (answer.source === "groq") {
    await pool.query(
      `INSERT INTO medicine_search_cache (query, results) VALUES ($1, $2)
       ON CONFLICT (query) DO NOTHING`,
      [q, JSON.stringify(answer.results)],
    );
  }
  return answer;
}
