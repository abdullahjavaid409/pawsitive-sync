/**
 * Funnel counts: phones send { name, count } once a day; only known names
 * (or a placement/step slug on the two split events) are stored.
 */
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { trackAnalytics } from "../db.js";

function fakePool() {
  const calls = [];
  return { calls, query: async (sql, params) => calls.push({ sql, params }) };
}

describe("trackAnalytics", () => {
  test("sums counts per known name in one statement", async () => {
    const pool = fakePool();
    const result = await trackAnalytics(pool, [
      { name: "dose.log.completed", count: 3 },
      { name: "dose.log.completed" },
      { name: "billing.paywall.opened.invite", count: 2 },
      { name: "onboarding.step.pet_basics", count: 1 },
    ]);
    assert.equal(result.recorded, 3);
    assert.equal(pool.calls.length, 1);
    const [names, counts] = pool.calls[0].params;
    const byName = Object.fromEntries(names.map((name, i) => [name, counts[i]]));
    assert.deepEqual(byName, {
      "dose.log.completed": 4,
      "billing.paywall.opened.invite": 2,
      "onboarding.step.pet_basics": 1,
    });
  });

  test("drops unknown names, bad slugs and absurd counts", async () => {
    const pool = fakePool();
    await trackAnalytics(pool, [
      { name: "user.email", count: 1 },
      { name: "billing.paywall.opened.Has Spaces", count: 1 },
      { name: "billing.paywall.opened." + "x".repeat(40), count: 1 },
      { name: "billing.trial.tap", count: 1e9 },
      { name: "billing.trial.tap", count: -5 },
    ]);
    const [names, counts] = pool.calls[0].params;
    assert.deepEqual(names, ["billing.trial.tap"]);
    assert.deepEqual(counts, [1001]);
  });

  test("an empty or invalid body writes nothing", async () => {
    const pool = fakePool();
    assert.deepEqual(await trackAnalytics(pool, undefined), { recorded: 0 });
    assert.deepEqual(await trackAnalytics(pool, [{ name: 42 }]), { recorded: 0 });
    assert.equal(pool.calls.length, 0);
  });
});
