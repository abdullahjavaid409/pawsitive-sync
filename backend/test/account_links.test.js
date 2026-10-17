/**
 * Sign-in recovery: token checks (no network, a local RSA key) and the
 * link / recover / clean-up rules against a real local Postgres.
 *
 *   TEST_DATABASE_URL=postgres://localhost/pawsitive_qa node --test backend/test/account_links.test.js
 */
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import pg from "pg";
import { verifySignedToken } from "../jwt.js";
import {
  createHousehold,
  deleteAccount,
  joinHousehold,
  leaveHousehold,
  linkAccount,
  memberForToken,
  migrate,
  recoverAccount,
  removeMember,
  rotateInviteCode,
  unlinkAccount,
} from "../db.js";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: "jwk" }), kid: "test-kid", alg: "RS256" };
const keys = async () => [jwk];
const issuer = "https://securetoken.google.com/gave-it-app";

function token(payload, { kid = "test-kid", alg = "RS256", key = privateKey } = {}) {
  const head = Buffer.from(JSON.stringify({ alg, kid })).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = sign("RSA-SHA256", Buffer.from(`${head}.${body}`), key).toString("base64url");
  return `${head}.${body}.${signature}`;
}

const now = () => Math.floor(Date.now() / 1000);
const good = () => ({ iss: issuer, aud: "gave-it-app", sub: "uid-1", iat: now() - 10, exp: now() + 3600 });
const check = (value) => verifySignedToken({ token: value, keys, issuer, audiences: ["gave-it-app"] });

describe("verifySignedToken", () => {
  test("accepts a token signed for this project", async () => {
    const result = await check(token(good()));
    assert.equal(result.ok, true);
    assert.equal(result.payload.sub, "uid-1");
  });

  test("rejects every forged or stale shape with a loggable reason", async () => {
    const other = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
    const cases = [
      [undefined, "missing_token"],
      ["", "missing_token"],
      ["a.b", "malformed_token"],
      ["!!.!!.!!", "malformed_token"],
      [token(good(), { alg: "HS256" }), "bad_alg"],
      [token(good(), { kid: "unknown" }), "unknown_kid"],
      [token(good(), { key: other }), "bad_signature"],
      [token({ ...good(), iss: "https://evil.example" }), "bad_issuer"],
      [token({ ...good(), aud: "someone-else" }), "bad_audience"],
      [token({ ...good(), exp: now() - 3600 }), "expired"],
      [token({ ...good(), iat: now() + 3600 }), "issued_in_future"],
      [token({ ...good(), sub: "" }), "no_subject"],
      ["x".repeat(5000), "missing_token"],
    ];
    for (const [value, reason] of cases) {
      const result = await check(value);
      assert.equal(result.ok, false, reason);
      assert.equal(result.reason, reason);
    }
  });

  test("a key fetch failure is a reason, never a throw", async () => {
    const result = await verifySignedToken({
      token: token(good()),
      keys: async () => {
        throw new Error("network down");
      },
      issuer,
      audiences: ["gave-it-app"],
    });
    assert.equal(result.ok, false);
    assert.match(result.reason, /^keys_unavailable/);
  });
});

const databaseUrl = process.env.TEST_DATABASE_URL || "postgres://localhost/pawsitive_qa";
let pool;

describe("account links", () => {
  before(async () => {
    pool = new pg.Pool({ connectionString: databaseUrl, max: 2 });
    await migrate(pool, () => {});
  });
  after(async () => pool?.end());

  async function household() {
    const owner = await createHousehold(pool, { owner: { name: "Sam" } });
    const { inviteCode: code } = await rotateInviteCode(pool, owner);
    const helper = await joinHousehold(pool, { code, name: "Alex" });
    return { owner, helper };
  }

  const uid = () => `uid-${Math.random().toString(36).slice(2)}`;

  test("a linked sign-in recovers on a new phone and locks the old one out", async () => {
    const { owner } = await household();
    const subject = uid();
    await linkAccount(pool, owner, "firebase", subject);
    const recovered = await recoverAccount(pool, "firebase", subject);
    assert.equal(recovered.householdId, owner.householdId);
    assert.equal(recovered.memberId, owner.memberId);
    assert.ok(await memberForToken(pool, recovered.token));
    assert.equal(await memberForToken(pool, owner.token), null, "old phone token stops working");
  });

  test("any member can link, and an unknown sign-in recovers nothing", async () => {
    const { helper } = await household();
    const subject = uid();
    await linkAccount(pool, helper, "firebase", subject);
    assert.equal((await recoverAccount(pool, "firebase", subject)).memberId, helper.memberId);
    assert.equal(await recoverAccount(pool, "firebase", uid()), null);
  });

  test("linking the same sign-in again moves it to the newest membership", async () => {
    const first = await household();
    const second = await household();
    const subject = uid();
    await linkAccount(pool, first.owner, "firebase", subject);
    await linkAccount(pool, second.owner, "firebase", subject);
    assert.equal((await recoverAccount(pool, "firebase", subject)).householdId, second.owner.householdId);
  });

  test("a removed member can't sign back in", async () => {
    const { owner, helper } = await household();
    const subject = uid();
    await linkAccount(pool, helper, "firebase", subject);
    await removeMember(pool, owner, helper.memberId);
    assert.equal(await recoverAccount(pool, "firebase", subject), null);
  });

  test("a member who leaves can't sign back in; an owner signing out still can", async () => {
    const { owner, helper } = await household();
    const helperSubject = uid();
    const ownerSubject = uid();
    await linkAccount(pool, helper, "firebase", helperSubject);
    await linkAccount(pool, owner, "firebase", ownerSubject);
    await leaveHousehold(pool, helper);
    await leaveHousehold(pool, owner);
    assert.equal(await recoverAccount(pool, "firebase", helperSubject), null);
    assert.equal((await recoverAccount(pool, "firebase", ownerSubject)).memberId, owner.memberId);
  });

  test("deleting an account (member or whole household) ends recovery", async () => {
    const { owner, helper } = await household();
    const helperSubject = uid();
    const ownerSubject = uid();
    await linkAccount(pool, helper, "firebase", helperSubject);
    await linkAccount(pool, owner, "firebase", ownerSubject);
    await deleteAccount(pool, helper);
    assert.equal(await recoverAccount(pool, "firebase", helperSubject), null);
    await deleteAccount(pool, owner);
    assert.equal(await recoverAccount(pool, "firebase", ownerSubject), null);
  });

  test("unlink removes recovery for that member only", async () => {
    const { owner, helper } = await household();
    const ownerSubject = uid();
    const helperSubject = uid();
    await linkAccount(pool, owner, "firebase", ownerSubject);
    await linkAccount(pool, helper, "firebase", helperSubject);
    assert.deepEqual(await unlinkAccount(pool, owner), { unlinked: true });
    assert.equal(await recoverAccount(pool, "firebase", ownerSubject), null);
    assert.ok(await recoverAccount(pool, "firebase", helperSubject));
  });
});
