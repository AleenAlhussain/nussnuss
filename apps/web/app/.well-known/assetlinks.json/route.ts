/**
 * Android App Links: lets Android open invite links straight in the app. ANDROID_CERT_SHA256 is the
 * SHA-256 fingerprint of the signing certificate (Play Console › App integrity), comma-separated if several.
 */
export const dynamic = 'force-dynamic';

export function GET() {
  const pkg = process.env.ANDROID_PACKAGE_NAME || 'app.nussnuss.nussnuss';
  const prints = (process.env.ANDROID_CERT_SHA256 ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  const body = prints.length
    ? [{ relation: ['delegate_permission/common.handle_all_urls', 'delegate_permission/common.get_login_creds'], target: { namespace: 'android_app', package_name: pkg, sha256_cert_fingerprints: prints } }]
    : [];
  return Response.json(body, { headers: { 'Cache-Control': 'public, max-age=3600' } });
}
