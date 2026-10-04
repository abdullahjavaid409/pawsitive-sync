/**
 * RevenueCat REST lookups. Pro only ever comes from RevenueCat: this file asks
 * it directly; the webhook handler in db.js hears about changes.
 */
/** Tests point this at a local fake; production always uses RevenueCat. */
const api = `${process.env.REVENUECAT_API_BASE || "https://api.revenuecat.com"}/v2/projects/`;
export const proEntitlement = "pro";

/** RevenueCat ids (not secrets). Override per environment if the project changes. */
const projectId = process.env.REVENUECAT_PROJECT_ID || "projd3c76f4a";
const proEntitlementId = process.env.REVENUECAT_PRO_ENTITLEMENT_ID || "entld3f5604b68";

const inactive = { ok: true, active: false, expiresAt: null, productId: null };

/**
 * The `pro` entitlement for one RevenueCat customer, or why it couldn't be read.
 * Needs REVENUECAT_SECRET_KEY: a v2 secret key with read access to customer
 * information. Never ship it in the app.
 * @returns {Promise<{ok: true, active: boolean, expiresAt: Date|null, productId: null}
 *   | {ok: false, reason: string}>}
 */
export async function fetchProEntitlement(appUserId, { secret = process.env.REVENUECAT_SECRET_KEY } = {}) {
  if (!secret) return { ok: false, reason: "no_secret_key" };
  const url = `${api}${projectId}/customers/${encodeURIComponent(appUserId)}/active_entitlements`;
  try {
    const response = await fetch(url, {
      headers: { authorization: `Bearer ${secret}`, accept: "application/json" },
      signal: AbortSignal.timeout(8000),
    });
    // Unknown customer: this store account never opened the app or bought.
    if (response.status === 404) return inactive;
    if (!response.ok) return { ok: false, reason: `status_${response.status}` };
    const items = (await response.json())?.items ?? [];
    const pro = items.find((item) => item?.entitlement_id === proEntitlementId);
    if (!pro) return inactive;
    const expiresAt = Number.isFinite(pro.expires_at) ? new Date(pro.expires_at) : null;
    return {
      ok: true,
      active: expiresAt == null || expiresAt.getTime() > Date.now(),
      expiresAt,
      productId: null,
    };
  } catch (error) {
    return { ok: false, reason: String(error?.name ?? error) };
  }
}
