/**
 * Sign in with Apple identity-token check. The Apple user id is only trusted
 * when it comes from the `sub` of a token Apple signed for this app — a bare
 * id in a request body proves nothing (anyone could claim any household).
 */
import { jwksSource, verifySignedToken } from "./jwt.js";

const appleKeys = jwksSource("https://appleid.apple.com/auth/keys");

/** Bundle id(s) Apple puts in `aud`. Comma-separated to allow a Services ID too. */
function audiences() {
  return (process.env.APPLE_BUNDLE_ID || "com.pawsitivesync.app")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

/**
 * @returns {Promise<{ok: true, sub: string} | {ok: false, reason: string}>}
 * `reason` is safe to log; the token itself never is.
 */
export async function verifyAppleIdentityToken(token) {
  const result = await verifySignedToken({
    token,
    keys: appleKeys,
    issuer: "https://appleid.apple.com",
    audiences: audiences(),
  });
  return result.ok ? { ok: true, sub: result.payload.sub } : result;
}
