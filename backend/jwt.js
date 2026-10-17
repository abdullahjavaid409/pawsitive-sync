/**
 * RS256 identity-token check shared by Sign in with Apple and Firebase Auth.
 * A subject is only trusted when it comes from a token the issuer signed for
 * this app; the token itself is never logged, only a short `reason`.
 */
import { createPublicKey, verify } from "node:crypto";

const keysTtlMs = 6 * 60 * 60 * 1000;
const refetchFloorMs = 60 * 1000;
const clockSkewS = 60;

/**
 * A JWKS cache for one key URL: refreshed every 6 hours, or early when a
 * token names a key we don't have (rotation), but at most once a minute.
 */
export function jwksSource(url) {
  let cache = { keys: [], fetchedAt: 0 };
  return async function keys({ force = false } = {}) {
    const age = Date.now() - cache.fetchedAt;
    if (cache.keys.length > 0 && age < keysTtlMs && !(force && age > refetchFloorMs)) {
      return cache.keys;
    }
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`keys_status_${response.status}`);
    const list = (await response.json())?.keys;
    cache = { keys: Array.isArray(list) ? list : [], fetchedAt: Date.now() };
    return cache.keys;
  };
}

function decodePart(part) {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

/**
 * @param {{token: unknown, keys: Function, issuer: string, audiences: string[]}} options
 * @returns {Promise<{ok: true, payload: object} | {ok: false, reason: string}>}
 */
export async function verifySignedToken({ token, keys, issuer, audiences }) {
  if (typeof token !== "string" || token.length === 0 || token.length > 4096) {
    return { ok: false, reason: "missing_token" };
  }
  const pieces = token.split(".");
  if (pieces.length !== 3) return { ok: false, reason: "malformed_token" };
  let header;
  let payload;
  try {
    header = decodePart(pieces[0]);
    payload = decodePart(pieces[1]);
  } catch {
    return { ok: false, reason: "malformed_token" };
  }
  if (header?.alg !== "RS256" || typeof header.kid !== "string") return { ok: false, reason: "bad_alg" };

  let jwk;
  try {
    jwk = (await keys()).find((key) => key?.kid === header.kid);
    if (!jwk) jwk = (await keys({ force: true })).find((key) => key?.kid === header.kid);
  } catch (error) {
    return { ok: false, reason: `keys_unavailable:${String(error?.message ?? error).slice(0, 60)}` };
  }
  if (!jwk) return { ok: false, reason: "unknown_kid" };

  let valid = false;
  try {
    valid = verify(
      "RSA-SHA256",
      Buffer.from(`${pieces[0]}.${pieces[1]}`),
      createPublicKey({ key: jwk, format: "jwk" }),
      Buffer.from(pieces[2], "base64url"),
    );
  } catch {
    valid = false;
  }
  if (!valid) return { ok: false, reason: "bad_signature" };

  const now = Math.floor(Date.now() / 1000);
  if (payload?.iss !== issuer) return { ok: false, reason: "bad_issuer" };
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.some((value) => audiences.includes(value))) return { ok: false, reason: "bad_audience" };
  if (!Number.isFinite(payload.exp) || payload.exp + clockSkewS < now) return { ok: false, reason: "expired" };
  if (Number.isFinite(payload.iat) && payload.iat - clockSkewS > now) return { ok: false, reason: "issued_in_future" };
  if (typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 128) {
    return { ok: false, reason: "no_subject" };
  }
  return { ok: true, payload };
}
