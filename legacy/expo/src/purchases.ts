/**
 * In-app purchase of "NussNuss Plus" (a one-time, non-consumable product) through RevenueCat,
 * which talks to the App Store and Google Play. Apple and Google collect the money and pay it to
 * the bank account the owner adds in App Store Connect and Google Play Console.
 *
 * Setup (owner, once): see replica/deploy.md → "Purchases".
 *  - Product id in both stores: `nussnuss_plus_lifetime`
 *  - RevenueCat entitlement id: `plus`
 *  - Public SDK keys go in app.json → expo.extra.revenuecat.{ios,android}
 */
import { Platform } from 'react-native';
import Constants from 'expo-constants';

export const ENTITLEMENT = 'plus';
export const PRODUCT_ID = 'nussnuss_plus_lifetime';

export type PurchaseState =
  | { status: 'unavailable'; reason: 'web' | 'notConfigured' }
  | { status: 'ready'; price: string | null };

type RC = typeof import('react-native-purchases').default;
let rc: RC | null = null;
let configured = false;

function keys(): { ios?: string; android?: string } {
  const extra = (Constants.expoConfig?.extra ?? {}) as { revenuecat?: { ios?: string; android?: string } };
  return extra.revenuecat ?? {};
}

async function sdk(): Promise<RC | null> {
  if (Platform.OS === 'web') return null;
  const key = Platform.OS === 'ios' ? keys().ios : keys().android;
  if (!key) return null;
  if (!rc) {
    try {
      // Native module: present in store/dev builds, absent in Expo Go.
      rc = require('react-native-purchases').default as RC;
    } catch {
      return null;
    }
  }
  if (!configured) {
    try {
      rc.configure({ apiKey: key });
      configured = true;
    } catch {
      return null;
    }
  }
  return rc;
}

export async function getPurchaseState(): Promise<PurchaseState> {
  if (Platform.OS === 'web') return { status: 'unavailable', reason: 'web' };
  const p = await sdk();
  if (!p) return { status: 'unavailable', reason: 'notConfigured' };
  try {
    const offerings = await p.getOfferings();
    const pkg = offerings.current?.availablePackages.find((x) => x.product.identifier === PRODUCT_ID)
      ?? offerings.current?.availablePackages[0];
    return { status: 'ready', price: pkg?.product.priceString ?? null };
  } catch {
    return { status: 'ready', price: null };
  }
}

/** true if the user owns Plus. Never throws. */
export async function hasPlus(): Promise<boolean> {
  const p = await sdk();
  if (!p) return false;
  try {
    const info = await p.getCustomerInfo();
    return !!info.entitlements.active[ENTITLEMENT];
  } catch {
    return false;
  }
}

export type BuyResult = 'purchased' | 'cancelled' | 'failed' | 'unavailable';

export async function buyPlus(): Promise<BuyResult> {
  const p = await sdk();
  if (!p) return 'unavailable';
  try {
    const offerings = await p.getOfferings();
    const pkg = offerings.current?.availablePackages.find((x) => x.product.identifier === PRODUCT_ID)
      ?? offerings.current?.availablePackages[0];
    if (!pkg) return 'unavailable';
    const { customerInfo } = await p.purchasePackage(pkg);
    return customerInfo.entitlements.active[ENTITLEMENT] ? 'purchased' : 'failed';
  } catch (e: unknown) {
    const err = e as { userCancelled?: boolean };
    return err?.userCancelled ? 'cancelled' : 'failed';
  }
}

export async function restorePlus(): Promise<boolean | null> {
  const p = await sdk();
  if (!p) return null;
  try {
    const info = await p.restorePurchases();
    return !!info.entitlements.active[ENTITLEMENT];
  } catch {
    return false;
  }
}
