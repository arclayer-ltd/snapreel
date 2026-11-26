// Verification of Apple's signed JWS (StoreKit 2 transactions, renewal info and App Store Server Notifications V2).
// No dependencies and no "server-only" import so scripts/jws-selftest.ts can run it with plain Node.
//
// Checks, in order:
//  1. header alg is ES256 and x5c has the leaf, intermediate and root certificates;
//  2. the root in x5c is byte-for-byte Apple Root CA - G3 (pinned below; the .cer is in ./certs);
//  3. the intermediate is issued and signed by that root, the leaf by the intermediate;
//  4. the leaf carries Apple's receipt-signing marker OID 1.2.840.113635.100.6.11.1 and the intermediate
//     1.2.840.113635.100.6.2.1 (Apple's own verifier checks the same two);
//  5. both are within their validity period;
//  6. the JWS signature verifies with the leaf's key.
import crypto, { X509Certificate } from "node:crypto";

// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
// SHA-256 fingerprint 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
export const APPLE_ROOT_CA_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----
`;

export const APPLE_ROOT_CA_G3_SHA256 =
  "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";

// DER encodings of the marker OIDs (tag 06, length 0A, value).
const LEAF_OID = Buffer.from("060a2a864886f76364060b01", "hex"); // 1.2.840.113635.100.6.11.1
const INTERMEDIATE_OID = Buffer.from("060a2a864886f76364060201", "hex"); // 1.2.840.113635.100.6.2.1

export class JwsError extends Error {}

export interface VerifyOptions {
  /** Trusted root; Apple Root CA - G3 unless a test passes its own. */
  rootPem?: string;
  /** Checks the marker OIDs. Tests with their own chain turn this off. */
  requireAppleOids?: boolean;
  now?: Date;
}

export function decodeJwsPayload<T>(jws: string): T {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new JwsError("not a JWS");
  return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as T;
}

export function verifyAppleJws<T>(jws: string, opts: VerifyOptions = {}): T {
  if (typeof jws !== "string" || jws.length > 20_000) throw new JwsError("not a JWS");
  const parts = jws.split(".");
  if (parts.length !== 3) throw new JwsError("not a JWS");
  const [h, p, s] = parts;
  let header: { alg?: string; x5c?: unknown };
  try {
    header = JSON.parse(Buffer.from(h, "base64url").toString("utf8"));
  } catch {
    throw new JwsError("bad header");
  }
  if (header.alg !== "ES256") throw new JwsError("alg must be ES256");
  if (!Array.isArray(header.x5c) || header.x5c.length < 3 || !header.x5c.every((c) => typeof c === "string")) {
    throw new JwsError("x5c must hold three certificates");
  }
  let leaf: X509Certificate, intermediate: X509Certificate, root: X509Certificate;
  try {
    [leaf, intermediate, root] = (header.x5c as string[]).slice(0, 3).map((c) => new X509Certificate(Buffer.from(c, "base64")));
  } catch {
    throw new JwsError("bad certificate in x5c");
  }
  const trusted = new X509Certificate(opts.rootPem ?? APPLE_ROOT_CA_G3_PEM);
  if (!root.raw.equals(trusted.raw)) throw new JwsError("root is not Apple Root CA - G3");
  if (!intermediate.checkIssued(root) || !intermediate.verify(root.publicKey)) throw new JwsError("intermediate not signed by root");
  if (!leaf.checkIssued(intermediate) || !leaf.verify(intermediate.publicKey)) throw new JwsError("leaf not signed by intermediate");
  if (opts.requireAppleOids !== false) {
    if (!leaf.raw.includes(LEAF_OID)) throw new JwsError("leaf is not an App Store signing certificate");
    if (!intermediate.raw.includes(INTERMEDIATE_OID)) throw new JwsError("intermediate is not Apple's WWDR CA");
  }
  const now = (opts.now ?? new Date()).getTime();
  for (const cert of [leaf, intermediate, root]) {
    if (now < Date.parse(cert.validFrom) || now > Date.parse(cert.validTo)) throw new JwsError("certificate outside its validity");
  }
  const ok = crypto.verify(
    "sha256",
    Buffer.from(`${h}.${p}`),
    { key: leaf.publicKey, dsaEncoding: "ieee-p1363" },
    Buffer.from(s, "base64url"),
  );
  if (!ok) throw new JwsError("signature does not verify");
  try {
    return JSON.parse(Buffer.from(p, "base64url").toString("utf8")) as T;
  } catch {
    throw new JwsError("bad payload");
  }
}

// StoreKit 2 shapes (the fields Snapreel reads).
export interface JwsTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  /** True once an upgrade inside the subscription group replaced this transaction. */
  isUpgraded?: boolean;
  transactionReason?: "PURCHASE" | "RENEWAL";
  environment: "Production" | "Sandbox" | "Xcode" | "LocalTesting";
  type?: string;
  signedDate?: number;
}

export interface JwsRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId?: string;
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
  environment?: string;
}

export interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  version?: string;
  signedDate?: number;
  data?: {
    appAppleId?: number;
    bundleId?: string;
    bundleVersion?: string;
    environment?: "Production" | "Sandbox";
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
    status?: number;
  };
  summary?: unknown;
}
