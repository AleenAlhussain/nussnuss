import { X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { compactVerify, decodeProtectedHeader, importX509 } from 'jose';
import { clearGoogleTokens, googleAccessToken, readServiceAccount, type ServiceAccount } from '../common/google.js';

/**
 * Store receipt checks. Both fail closed: without the owner's store credentials nothing is granted.
 *
 * Apple: StoreKit 2 sends a signed transaction (JWS). Its x5c chain must end at Apple's root
 * certificate, which you download from apple.com/certificateauthority and pass as APPLE_ROOT_CA
 * (a PEM, or a path to one). APPLE_BUNDLE_ID must match the app.
 *
 * Google: the Play Developer API answers for a purchase token. It needs a service account with
 * access to the app in Play Console (GOOGLE_PLAY_SERVICE_ACCOUNT, the JSON key) and ANDROID_PACKAGE_NAME.
 */

export class StoreError extends Error {
  constructor(
    message: string,
    readonly status = 400,
  ) {
    super(message);
  }
}

const pemOf = (v: string) => (v.includes('BEGIN CERTIFICATE') ? v : readFileSync(v, 'utf8'));

export interface AppleTransaction {
  bundleId: string;
  productId: string;
  transactionId: string;
  originalTransactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment?: string;
}

export async function verifyAppleTransaction(jws: string): Promise<AppleTransaction> {
  const rootSetting = process.env.APPLE_ROOT_CA;
  const bundleId = process.env.APPLE_BUNDLE_ID;
  if (!rootSetting || !bundleId) throw new StoreError('App Store purchases are not set up on this server yet.', 503);
  let header: ReturnType<typeof decodeProtectedHeader>;
  try {
    header = decodeProtectedHeader(jws);
  } catch {
    throw new StoreError('That purchase could not be read.');
  }
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) throw new StoreError('That purchase is not signed by the App Store.');
  const chain = x5c.map((b64) => new X509Certificate(Buffer.from(b64, 'base64')));
  const root = new X509Certificate(pemOf(rootSetting));
  const now = Date.now();
  for (let i = 0; i < chain.length; i++) {
    const c = chain[i];
    if (Date.parse(c.validFrom) > now || Date.parse(c.validTo) < now) throw new StoreError('That purchase certificate has expired.');
    const issuer = i + 1 < chain.length ? chain[i + 1] : root;
    if (c.fingerprint256 === root.fingerprint256) continue;
    if (!c.verify(issuer.publicKey)) throw new StoreError('That purchase is not signed by the App Store.');
  }
  const last = chain[chain.length - 1];
  if (last.fingerprint256 !== root.fingerprint256 && !last.verify(root.publicKey)) throw new StoreError('That purchase is not signed by the App Store.');
  const key = await importX509(chain[0].toString(), 'ES256');
  let payload: AppleTransaction;
  try {
    payload = JSON.parse(new TextDecoder().decode((await compactVerify(jws, key)).payload)) as AppleTransaction;
  } catch {
    throw new StoreError('That purchase is not signed by the App Store.');
  }
  if (payload.bundleId !== bundleId) throw new StoreError('That purchase is for a different app.');
  if (payload.revocationDate) throw new StoreError('That purchase was refunded.');
  return payload;
}

function serviceAccount(): ServiceAccount {
  if (!process.env.ANDROID_PACKAGE_NAME) throw new StoreError('Google Play purchases are not set up on this server yet.', 503);
  const sa = readServiceAccount(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT);
  if (!sa) throw new StoreError('Google Play purchases are not set up on this server yet.', 503);
  return sa;
}

export interface GooglePurchase {
  productId: string;
  orderId: string;
  expiresAt: Date | null;
}

/** Checks a Play purchase and acknowledges it (Play refunds purchases that are never acknowledged). */
export async function verifyGooglePurchase(productId: string, purchaseToken: string, subscription: boolean): Promise<GooglePurchase> {
  const sa = serviceAccount();
  const pkg = process.env.ANDROID_PACKAGE_NAME!;
  const base = (process.env.GOOGLE_PLAY_API_URL ?? 'https://androidpublisher.googleapis.com').replace(/\/$/, '');
  const token = await googleAccessToken(sa, 'https://www.googleapis.com/auth/androidpublisher').catch(() => {
    throw new StoreError('Google Play did not accept the server key.', 502);
  });
  const auth = { Authorization: `Bearer ${token}` };
  const root = `${base}/androidpublisher/v3/applications/${encodeURIComponent(pkg)}/purchases`;
  if (subscription) {
    const res = await fetch(`${root}/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`, { headers: auth });
    if (!res.ok) throw new StoreError('Google Play does not know that purchase.');
    const s = (await res.json()) as {
      subscriptionState?: string;
      latestOrderId?: string;
      acknowledgementState?: string;
      lineItems?: { productId: string; expiryTime?: string }[];
    };
    const item = s.lineItems?.find((l) => l.productId === productId);
    if (!item || !['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'].includes(s.subscriptionState ?? '')) {
      throw new StoreError('That subscription is not active.');
    }
    if (s.acknowledgementState !== 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED') {
      await fetch(`${root}/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`, {
        method: 'POST',
        headers: { ...auth, 'Content-Type': 'application/json' },
        body: '{}',
      });
    }
    return { productId, orderId: s.latestOrderId ?? purchaseToken, expiresAt: item.expiryTime ? new Date(item.expiryTime) : null };
  }
  const res = await fetch(`${root}/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`, { headers: auth });
  if (!res.ok) throw new StoreError('Google Play does not know that purchase.');
  const p = (await res.json()) as { purchaseState?: number; orderId?: string; acknowledgementState?: number };
  if (p.purchaseState !== 0) throw new StoreError('That purchase is not complete.');
  if (p.acknowledgementState !== 1) {
    await fetch(`${root}/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`, {
      method: 'POST',
      headers: { ...auth, 'Content-Type': 'application/json' },
      body: '{}',
    });
  }
  return { productId, orderId: p.orderId ?? purchaseToken, expiresAt: null };
}

/** For tests only. */
export function resetStoreCaches() {
  clearGoogleTokens();
}
