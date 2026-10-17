/**
 * Firebase Auth ID-token check (Apple, Google or email sign-in on the phone).
 * Verified against Google's published keys, so the server needs no
 * firebase-admin dependency or service-account secret.
 * https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library
 */
import { jwksSource, verifySignedToken } from "./jwt.js";

const firebaseKeys = jwksSource(
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
);

function projectId() {
  return (process.env.FIREBASE_PROJECT_ID || "gave-it-app").trim();
}

const providers = new Set(["apple.com", "google.com", "password"]);

/**
 * @returns {Promise<{ok: true, uid: string, provider: string, email: string | null}
 *   | {ok: false, reason: string}>} `reason` is safe to log.
 */
export async function verifyFirebaseIdToken(token) {
  const project = projectId();
  const result = await verifySignedToken({
    token,
    keys: firebaseKeys,
    issuer: `https://securetoken.google.com/${project}`,
    audiences: [project],
  });
  if (!result.ok) return result;
  const { payload } = result;
  const now = Math.floor(Date.now() / 1000);
  // Firebase also requires a past sign-in time.
  if (!Number.isFinite(payload.auth_time) || payload.auth_time - 60 > now) {
    return { ok: false, reason: "bad_auth_time" };
  }
  const provider = payload.firebase?.sign_in_provider;
  // Anonymous or custom tokens don't prove a real person; only these do.
  if (!providers.has(provider)) return { ok: false, reason: "unsupported_provider" };
  const email = typeof payload.email === "string" && payload.email_verified === true ? payload.email : null;
  return { ok: true, uid: payload.sub, provider, email };
}
