import { readFileSync } from 'node:fs';
import { importPKCS8, SignJWT } from 'jose';

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
  token_uri?: string;
}

/** A Google service account from an env var holding the JSON key itself or a path to it. */
export function readServiceAccount(envValue: string | undefined): ServiceAccount | null {
  if (!envValue) return null;
  try {
    return JSON.parse(envValue.trim().startsWith('{') ? envValue : readFileSync(envValue, 'utf8')) as ServiceAccount;
  } catch {
    return null;
  }
}

const tokens = new Map<string, { token: string; until: number }>();

/** OAuth access token for a service account and scope (JWT bearer grant), cached until a minute before expiry. */
export async function googleAccessToken(sa: ServiceAccount, scope: string): Promise<string> {
  const key = `${sa.client_email}|${scope}`;
  const hit = tokens.get(key);
  if (hit && hit.until > Date.now() + 60_000) return hit.token;
  const tokenUri = sa.token_uri ?? 'https://oauth2.googleapis.com/token';
  const assertion = await new SignJWT({ scope })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setAudience(tokenUri)
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(await importPKCS8(sa.private_key, 'RS256'));
  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!res.ok) throw new Error(`Google token ${res.status}`);
  const body = (await res.json()) as { access_token: string; expires_in?: number };
  tokens.set(key, { token: body.access_token, until: Date.now() + (body.expires_in ?? 3600) * 1000 });
  return body.access_token;
}

export function clearGoogleTokens() {
  tokens.clear();
}
