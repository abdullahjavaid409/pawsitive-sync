/**
 * Pet photos in the Railway S3-compatible bucket. The server never handles the
 * image bytes: phones upload and download straight to/from the bucket with
 * short-lived presigned URLs (AWS SigV4, query-string auth), so photos cost no
 * server bandwidth. Plain node:crypto — no SDK dependency.
 */
import { createHash, createHmac, randomBytes } from "node:crypto";

const env = (name) => process.env[name] ?? "";
const maxPhotoBytes = 400 * 1024; // the app sends ~60 KB JPEGs; anything bigger is refused
const uploadTtlSeconds = 5 * 60;
const viewTtlSeconds = 24 * 60 * 60;

export function photosConfigured() {
  return Boolean(env("PHOTOS_S3_ENDPOINT") && env("PHOTOS_S3_BUCKET") && env("PHOTOS_S3_ACCESS_KEY_ID") && env("PHOTOS_S3_SECRET_ACCESS_KEY"));
}

/** Object keys are scoped to the household and pet so a key can't be reused elsewhere. */
export function newPhotoKey(householdId, petId) {
  return `households/${householdId}/pets/${petId}/${randomBytes(8).toString("hex")}.jpg`;
}

export function keyBelongsTo(key, householdId, petId) {
  return (
    typeof key === "string" &&
    key.startsWith(`households/${householdId}/pets/${petId}/`) &&
    /^[a-z0-9/_-]+\.jpg$/i.test(key) &&
    !key.includes("..")
  );
}

export function checkPhotoSize(bytes) {
  return Number.isInteger(bytes) && bytes > 0 && bytes <= maxPhotoBytes;
}

const hex = (data) => createHash("sha256").update(data).digest("hex");
const hmac = (key, data) => createHmac("sha256", key).update(data).digest();
const encode = (value) =>
  encodeURIComponent(value).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

function objectUrl(key) {
  const endpoint = new URL(env("PHOTOS_S3_ENDPOINT"));
  // Railway buckets use virtual-host style: https://<bucket>.<endpoint host>/<key>
  const host = `${env("PHOTOS_S3_BUCKET")}.${endpoint.host}`;
  const path = "/" + key.split("/").map(encode).join("/");
  return { host, path, origin: `${endpoint.protocol}//${host}` };
}

/**
 * A presigned URL for one S3 call. `signedHeaders` (lower-case name → value)
 * must be sent by the client exactly; `host` is always signed.
 */
function presign(method, key, ttlSeconds, signedHeaders = {}) {
  const { host, path, origin } = objectUrl(key);
  const region = env("PHOTOS_S3_REGION") || "auto";
  const now = new Date();
  const amzDate = now.toISOString().replace(/[-:]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const scope = `${dateStamp}/${region}/s3/aws4_request`;
  const headers = { host, ...signedHeaders };
  const headerNames = Object.keys(headers).map((name) => name.toLowerCase()).sort();
  const query = {
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${env("PHOTOS_S3_ACCESS_KEY_ID")}/${scope}`,
    "X-Amz-Date": amzDate,
    "X-Amz-Expires": String(ttlSeconds),
    "X-Amz-SignedHeaders": headerNames.join(";"),
  };
  const canonicalQuery = Object.keys(query)
    .sort()
    .map((name) => `${encode(name)}=${encode(query[name])}`)
    .join("&");
  const canonicalHeaders = headerNames.map((name) => `${name}:${String(headers[name]).trim()}\n`).join("");
  const canonicalRequest = [method, path, canonicalQuery, canonicalHeaders, headerNames.join(";"), "UNSIGNED-PAYLOAD"].join("\n");
  const stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, hex(canonicalRequest)].join("\n");
  let signingKey = hmac(`AWS4${env("PHOTOS_S3_SECRET_ACCESS_KEY")}`, dateStamp);
  for (const part of [region, "s3", "aws4_request"]) signingKey = hmac(signingKey, part);
  const signature = createHmac("sha256", signingKey).update(stringToSign).digest("hex");
  return `${origin}${path}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

/** Upload URL: the phone must PUT exactly `bytes` of image/jpeg within 5 minutes. */
export function presignUpload(key, bytes) {
  return {
    url: presign("PUT", key, uploadTtlSeconds, { "content-type": "image/jpeg", "content-length": String(bytes) }),
    headers: { "content-type": "image/jpeg", "content-length": String(bytes) },
    expiresInSeconds: uploadTtlSeconds,
  };
}

/** View URL, valid a day; phones cache the image by key so it isn't refetched. */
export function presignView(key) {
  return key && photosConfigured() ? presign("GET", key, viewTtlSeconds) : null;
}

/** Best effort: a leftover object only costs a few KB, so failures are logged, not thrown. */
export async function deletePhoto(key, logFn = () => {}) {
  if (!key || !photosConfigured()) return;
  try {
    const response = await fetch(presign("DELETE", key, 60), { method: "DELETE", signal: AbortSignal.timeout(5000) });
    if (!response.ok && response.status !== 404) logFn("photo.delete_failed", { status: response.status });
  } catch (error) {
    logFn("photo.delete_failed", { reason: String(error?.name ?? error) });
  }
}

/** HEAD the uploaded object so a pet never points at a photo that isn't there. */
export async function photoExists(key) {
  try {
    const response = await fetch(presign("HEAD", key, 60), { method: "HEAD", signal: AbortSignal.timeout(5000) });
    return response.ok;
  } catch {
    return false;
  }
}
