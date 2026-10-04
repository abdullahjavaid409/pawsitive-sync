/**
 * Sign in with Apple identity-token check. The Apple user id is only trusted
 * when it comes from the `sub` of a token Apple signed for this app — a bare
 * id in a request body proves nothing (anyone could claim any household).
 */
import { createPublicKey, verify } from "node:crypto";

const issuer = "https://appleid.apple.com";
const keysUrl = "https://appleid.apple.com/auth/keys";
const keysTtlMs = 6 * 60 * 60 * 1000;
const refetchFloorMs = 60 * 1000;
const clockSkewS = 60;

/** Bundle id(s) Apple puts in `aud`. Comma-separated to allow a Services ID too. */
function audiences() {
  return (process.env.APPLE_BUNDLE_ID || "com.abdulmanan.pawsitivesync")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

let cache = { keys: [], fetchedAt: 0 };

async function appleKeys({ force = false } = {}) {
  const age = Date.now() - cache.fetchedAt;
  if (cache.keys.length > 0 && age < keysTtlMs && !(force && age > refetchFloorMs)) {
    return cache.keys;
  }
  const response = await fetch(keysUrl, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error(`apple_keys_status_${response.status}`);
  const keys = (await response.json())?.keys;
  cache = { keys: Array.isArray(keys) ? keys : [], fetchedAt: Date.now() };
  return cache.keys;
}

function decodePart(part) {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

/**
 * @returns {Promise<{ok: true, sub: string} | {ok: false, reason: string}>}
 * `reason` is safe to log; the token itself never is.
 */
export async function verifyAppleIdentityToken(token) {
  if (typeof token !== "string" || token.length > 4096) return { ok: false, reason: "missing_token" };
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
    jwk = (await appleKeys()).find((key) => key?.kid === header.kid);
    if (!jwk) jwk = (await appleKeys({ force: true })).find((key) => key?.kid === header.kid);
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
  if (!aud.some((value) => audiences().includes(value))) return { ok: false, reason: "bad_audience" };
  if (!Number.isFinite(payload.exp) || payload.exp + clockSkewS < now) return { ok: false, reason: "expired" };
  if (Number.isFinite(payload.iat) && payload.iat - clockSkewS > now) return { ok: false, reason: "issued_in_future" };
  if (typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 128) {
    return { ok: false, reason: "no_subject" };
  }
  return { ok: true, sub: payload.sub };
}
