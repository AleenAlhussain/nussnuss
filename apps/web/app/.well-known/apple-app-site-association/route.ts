/**
 * Universal Links: tells iOS that invite links (/join/...) on this site open the NussNuss app when it is
 * installed. APPLE_APP_ID is "<team id>.<bundle id>" from the owner's Apple developer account.
 */
export const dynamic = 'force-dynamic';

export function GET() {
  const ids = (process.env.APPLE_APP_ID ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  const body = {
    applinks: { details: ids.map((appID) => ({ appIDs: [appID], components: [{ '/': '/join/*', comment: 'Invite links' }] })) },
    webcredentials: { apps: ids },
  };
  return Response.json(body, { headers: { 'Cache-Control': 'public, max-age=3600' } });
}
