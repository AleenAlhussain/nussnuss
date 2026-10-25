import { connect } from 'node:http2';
import { readFileSync } from 'node:fs';
import { Inject, Injectable, Logger } from '@nestjs/common';
import { eq } from 'drizzle-orm';
import { importPKCS8, SignJWT } from 'jose';
import { googleAccessToken, readServiceAccount } from '../common/google.js';
import { DB, type Db } from '../db/db.module.js';
import { devices } from '../db/schema.js';

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Push to phones. Android goes through Firebase Cloud Messaging (FCM_SERVICE_ACCOUNT), iPhone through
 * APNs with a token key (APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC). Either can be missing: the
 * notice still waits in the app's inbox.
 */
@Injectable()
export class PushService {
  private readonly log = new Logger('Push');
  private apnsJwt?: { token: string; at: number };

  constructor(@Inject(DB) private readonly db: Db) {}

  get configured() {
    return { android: !!process.env.FCM_SERVICE_ACCOUNT, ios: !!(process.env.APNS_KEY && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_TOPIC) };
  }

  /** Sends to every device the person has; returns how many accepted it. Dead tokens are removed. */
  async toUser(userId: string, msg: PushMessage): Promise<number> {
    const list = await this.db.select().from(devices).where(eq(devices.userId, userId));
    let ok = 0;
    for (const d of list) {
      try {
        const r = d.platform === 'android' ? await this.fcm(d.token, msg) : d.platform === 'ios' ? await this.apns(d.token, msg) : 'skip';
        if (r === 'ok') ok++;
        if (r === 'gone') await this.db.delete(devices).where(eq(devices.id, d.id));
      } catch (e) {
        this.log.warn(`push to ${d.platform} failed: ${(e as Error).message}`);
      }
    }
    return ok;
  }

  private async fcm(token: string, msg: PushMessage): Promise<'ok' | 'gone' | 'skip'> {
    const sa = readServiceAccount(process.env.FCM_SERVICE_ACCOUNT);
    if (!sa?.project_id) return 'skip';
    const access = await googleAccessToken(sa, 'https://www.googleapis.com/auth/firebase.messaging');
    const base = (process.env.FCM_URL ?? 'https://fcm.googleapis.com').replace(/\/$/, '');
    const res = await fetch(`${base}/v1/projects/${sa.project_id}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: { token, notification: { title: msg.title, body: msg.body }, data: msg.data ?? {} } }),
    });
    if (res.status === 404) return 'gone';
    return res.ok ? 'ok' : 'skip';
  }

  private async apnsToken(): Promise<string> {
    if (this.apnsJwt && Date.now() - this.apnsJwt.at < 40 * 60_000) return this.apnsJwt.token;
    const raw = process.env.APNS_KEY!;
    const pem = raw.includes('BEGIN PRIVATE KEY') ? raw : readFileSync(raw, 'utf8');
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: process.env.APNS_KEY_ID! })
      .setIssuer(process.env.APNS_TEAM_ID!)
      .setIssuedAt()
      .sign(await importPKCS8(pem, 'ES256'));
    this.apnsJwt = { token, at: Date.now() };
    return token;
  }

  private async apns(deviceToken: string, msg: PushMessage): Promise<'ok' | 'gone' | 'skip'> {
    if (!this.configured.ios) return 'skip';
    const host = process.env.APNS_HOST ?? (process.env.APNS_SANDBOX === 'true' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com');
    const jwt = await this.apnsToken();
    return new Promise((resolve, reject) => {
      const session = connect(host);
      session.on('error', reject);
      const req = session.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${jwt}`,
        'apns-topic': process.env.APNS_TOPIC!,
        'apns-push-type': 'alert',
        'content-type': 'application/json',
      });
      req.on('response', (h) => {
        const status = Number(h[':status']);
        req.on('end', () => session.close());
        req.resume();
        resolve(status === 200 ? 'ok' : status === 410 ? 'gone' : 'skip');
      });
      req.on('error', reject);
      req.end(JSON.stringify({ aps: { alert: { title: msg.title, body: msg.body }, sound: 'default' }, ...(msg.data ?? {}) }));
    });
  }
}
