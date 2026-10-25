'use client';

import { AppleLogo, Copy, DeviceMobile, Fingerprint, Key, ShieldCheck, ShieldWarning, Trash } from '@phosphor-icons/react';
import { browserSupportsWebAuthn, startAuthentication, startRegistration } from '@simplewebauthn/browser';
import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError, type Security, type Session } from '@/lib/api';
import { haptic } from '@/lib/feel';
import { useSession } from '@/lib/session';
import { Sheet } from './glass';
import { shortDate } from './paywall';
import { useToast } from './toast';
import { Button, Field, Section } from './ui';

/**
 * Sign in with Apple or Google on the web. Both stay hidden until the owner sets the client ids
 * (NEXT_PUBLIC_APPLE_CLIENT_ID, NEXT_PUBLIC_GOOGLE_CLIENT_ID) and the API has them too.
 */
const APPLE_ID = process.env.NEXT_PUBLIC_APPLE_CLIENT_ID ?? '';
const GOOGLE_ID = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID ?? '';

type GoogleId = { accounts: { id: { initialize: (o: object) => void; renderButton: (el: HTMLElement, o: object) => void } } };
type AppleId = { auth: { init: (o: object) => void; signIn: () => Promise<{ authorization: { id_token: string }; user?: { name?: { firstName?: string } } }> } };

function script(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) return resolve();
    const s = Object.assign(document.createElement('script'), { src, async: true });
    s.onload = () => resolve();
    s.onerror = () => reject(new Error('script'));
    document.head.appendChild(s);
  });
}

export function useProviders(providers?: Security['providers']) {
  return { apple: !!APPLE_ID && providers?.apple !== false, google: !!GOOGLE_ID && providers?.google !== false };
}

function GoogleButton({ onToken }: { onToken: (token: string) => void }) {
  const el = useRef<HTMLDivElement>(null);
  const { prefs } = useSession();
  const cb = useRef(onToken);
  cb.current = onToken;
  useEffect(() => {
    script('https://accounts.google.com/gsi/client')
      .then(() => {
        const g = (window as unknown as { google?: GoogleId }).google;
        if (!g || !el.current) return;
        g.accounts.id.initialize({ client_id: GOOGLE_ID, callback: (r: { credential: string }) => cb.current(r.credential) });
        g.accounts.id.renderButton(el.current, { theme: 'outline', size: 'large', shape: 'pill', width: 320, locale: prefs.lang, text: 'continue_with' });
      })
      .catch(() => {});
  }, [prefs.lang]);
  return <div ref={el} className="flex min-h-11 justify-center" data-testid="google-button" />;
}

async function appleToken(): Promise<{ token: string; name?: string } | null> {
  await script('https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js');
  const a = (window as unknown as { AppleID?: AppleId }).AppleID;
  if (!a) return null;
  a.auth.init({ clientId: APPLE_ID, scope: 'name', redirectURI: window.location.origin, usePopup: true });
  const r = await a.auth.signIn();
  return { token: r.authorization.id_token, name: r.user?.name?.firstName };
}

/** The ways back into an account on this device: a code, a passkey, Apple, Google. */
export function SignInSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t, adopt } = useSession();
  const toast = useToast();
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [webauthn, setWebauthn] = useState(false);
  const prov = useProviders();
  useEffect(() => {
    if (!open) return;
    setCode('');
    setError(null);
    setWebauthn(browserSupportsWebAuthn());
  }, [open]);

  const done = (s: Session) => {
    haptic('success');
    adopt(s);
    toast(t('welcomeBack'));
    onClose();
  };
  const withCode = async () => {
    if (code.replace(/[\s-]/g, '').length < 6) return setError(t('codeBad'));
    setBusy(true);
    try {
      done(await api.signInWithCode(code));
    } catch (e) {
      setError(e instanceof ApiError && e.status === 401 ? t('codeBad') : e instanceof ApiError && e.status === 0 ? t('offline') : t('error'));
    } finally {
      setBusy(false);
    }
  };
  const withPasskey = async () => {
    setBusy(true);
    try {
      const o = await api.passkeyLoginOptions();
      const response = await startAuthentication({ optionsJSON: o.options as unknown as Parameters<typeof startAuthentication>[0]['optionsJSON'] });
      done(await api.passkeyLogin(o.challengeId, response));
    } catch (e) {
      if ((e as Error).name !== 'NotAllowedError') setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const withIdentity = async (provider: 'apple' | 'google', token: string, name?: string) => {
    try {
      const r = await api.identity(provider, token, name);
      if ('token' in r) done(r);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  return (
    <Sheet open={open} onClose={onClose} title={t('haveAccount')} testId="sign-in-sheet">
      <form
        className="flex flex-col gap-4 pb-2"
        onSubmit={(e) => {
          e.preventDefault();
          withCode();
        }}
      >
        <Field
          label={t('codeLabel')}
          hint={t('codeHint')}
          error={error}
          value={code}
          autoComplete="one-time-code"
          autoCapitalize="characters"
          spellCheck={false}
          maxLength={40}
          onChange={(e) => {
            setCode(e.target.value.toUpperCase());
            setError(null);
          }}
          data-testid="code"
          data-autofocus
          dir="ltr"
        />
        <Button type="submit" block disabled={busy} data-testid="code-continue">
          {t('buy')}
        </Button>
        {webauthn ? (
          <Button variant="secondary" block icon={<Fingerprint size={22} />} disabled={busy} onClick={withPasskey} data-testid="passkey-sign-in">
            {t('passkeySignIn')}
          </Button>
        ) : null}
        {prov.apple ? (
          <Button
            block
            className="bg-black text-white dark:bg-white dark:text-black"
            icon={<AppleLogo size={22} weight="fill" />}
            onClick={async () => {
              const r = await appleToken().catch(() => null);
              if (r) withIdentity('apple', r.token, r.name);
            }}
          >
            {t('continueApple')}
          </Button>
        ) : null}
        {prov.google ? <GoogleButton onToken={(tok) => withIdentity('google', tok)} /> : null}
      </form>
    </Sheet>
  );
}

function CodeSheet({ code, onClose, title, body, expiresAt }: { code: string | null; onClose: () => void; title: string; body: string; expiresAt?: string }) {
  const { t, prefs } = useSession();
  const toast = useToast();
  return (
    <Sheet open={!!code} onClose={onClose} title={title} testId="code-sheet">
      <div className="flex flex-col gap-4 pb-2">
        <p className="t-subhead text-text-2">{body}</p>
        <output className="whitespace-nowrap rounded-card bg-surface px-3 py-5 text-center font-mono font-semibold tracking-wider text-text select-all" style={{ fontSize: 'clamp(1rem, 4.6vw, 1.6rem)' }} dir="ltr" data-testid="shown-code">
          {code}
        </output>
        {expiresAt ? <p className="text-center t-footnote text-text-2">{new Date(expiresAt).toLocaleTimeString(prefs.lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB', { hour: '2-digit', minute: '2-digit' })}</p> : null}
        <Button
          block
          variant="secondary"
          icon={<Copy size={20} />}
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(code ?? '');
              toast(t('codeCopied'));
            } catch {}
          }}
        >
          {t('copy')}
        </Button>
        <Button block onClick={onClose}>
          {t('done')}
        </Button>
      </div>
    </Sheet>
  );
}

function Row({ icon, title, sub, onClick, trailing, testId, danger }: { icon: React.ReactNode; title: string; sub?: string; onClick?: () => void; trailing?: React.ReactNode; testId?: string; danger?: boolean }) {
  const cls = `focus-ring flex min-h-14 w-full items-center gap-3 border-b border-separator/60 px-4 py-2 text-start last:border-0 ${danger ? 'text-danger' : 'text-text'}`;
  const inner = (
    <>
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-row bg-accent-soft text-on-accent-soft" aria-hidden>
        {icon}
      </span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="t-body">{title}</span>
        {sub ? <span className="t-footnote text-text-2">{sub}</span> : null}
      </span>
      {trailing}
    </>
  );
  return onClick ? (
    <button type="button" className={cls} onClick={onClick} data-testid={testId}>
      {inner}
    </button>
  ) : (
    <div className={cls} data-testid={testId}>
      {inner}
    </div>
  );
}

/** Settings › Account: what protects the account, and the ways to add protection. */
export function AccountSection() {
  const { t, prefs } = useSession();
  const toast = useToast();
  const [sec, setSec] = useState<Security | null>(null);
  const [shown, setShown] = useState<{ code: string; kind: 'recovery' | 'link'; expiresAt?: string } | null>(null);
  const [webauthn, setWebauthn] = useState(false);
  const prov = useProviders(sec?.providers);
  const load = useCallback(() => api.security().then(setSec).catch(() => {}), []);
  useEffect(() => {
    load();
    setWebauthn(browserSupportsWebAuthn());
  }, [load]);

  const safe = !!sec && (sec.recoveryCode || sec.passkeys.length > 0 || sec.identities.length > 0);
  const date = (iso: string) => shortDate(iso, prefs.lang);

  const addPasskey = async () => {
    try {
      const o = await api.passkeyRegisterOptions();
      const response = await startRegistration({ optionsJSON: o.options as unknown as Parameters<typeof startRegistration>[0]['optionsJSON'] });
      await api.passkeyRegister(o.challengeId, response);
      haptic('success');
      toast(t('passkeyAdded'));
      load();
    } catch (e) {
      if ((e as Error).name !== 'NotAllowedError') toast((e as Error).message);
    }
  };
  const link = async (provider: 'apple' | 'google', token: string) => {
    try {
      await api.identity(provider, token);
      load();
    } catch (e) {
      toast((e as Error).message);
    }
  };

  return (
    <>
      <Section title={t('account')} footer={sec && !safe ? t('accountUnsafeBody') : undefined}>
        <Row
          icon={safe ? <ShieldCheck size={20} weight="fill" /> : <ShieldWarning size={20} weight="fill" />}
          title={safe ? t('accountSafe') : t('accountUnsafe')}
          testId="account-status"
        />
        <Row
          icon={<Key size={20} />}
          title={sec?.recoveryCode ? t('recoveryRemake') : t('recoveryMake')}
          sub={sec?.recoveryCreatedAt ? t('recoveryMadeOn', { date: date(sec.recoveryCreatedAt) }) : undefined}
          testId="make-recovery"
          onClick={() =>
            api
              .makeRecovery()
              .then((r) => {
                setShown({ code: r.code, kind: 'recovery' });
                load();
              })
              .catch(() => toast(t('error')))
          }
        />
        <Row
          icon={<DeviceMobile size={20} />}
          title={t('linkDevice')}
          testId="link-device"
          onClick={() =>
            api
              .makeLink()
              .then((r) => setShown({ code: r.code, kind: 'link', expiresAt: r.expiresAt }))
              .catch(() => toast(t('error')))
          }
        />
        {webauthn ? <Row icon={<Fingerprint size={20} />} title={t('passkeyAdd')} sub={t('passkeyHint')} onClick={addPasskey} testId="add-passkey" /> : null}
        {sec?.passkeys.map((k) => (
          <Row
            key={k.id}
            icon={<Fingerprint size={20} weight="fill" />}
            title={t('passkeys')}
            sub={t('passkeyOn', { date: date(k.createdAt) })}
            trailing={
              <button type="button" aria-label={t('remove')} className="tap focus-ring grid place-items-center rounded-full text-danger" onClick={() => api.passkeyRemove(k.id).then(load).catch(() => toast(t('error')))}>
                <Trash size={18} />
              </button>
            }
          />
        ))}
        {sec?.identities.map((i) => (
          <Row key={i.provider} icon={<ShieldCheck size={20} />} title={t('linkedWith', { provider: i.provider === 'apple' ? 'Apple' : 'Google' })} sub={i.email ?? undefined} />
        ))}
        {prov.apple && !sec?.identities.some((i) => i.provider === 'apple') ? (
          <Row
            icon={<AppleLogo size={20} weight="fill" />}
            title={t('continueApple')}
            onClick={async () => {
              const r = await appleToken().catch(() => null);
              if (r) link('apple', r.token);
            }}
          />
        ) : null}
        {prov.google && !sec?.identities.some((i) => i.provider === 'google') ? (
          <div className="border-b border-separator/60 px-4 py-3 last:border-0">
            <GoogleButton onToken={(tok) => link('google', tok)} />
          </div>
        ) : null}
      </Section>

      {sec && sec.sessions.length > 1 ? (
        <Section title={t('devices')}>
          {sec.sessions.map((s) => (
            <Row
              key={s.id}
              icon={<DeviceMobile size={20} />}
              title={s.current ? t('thisDevice') : (s.device ?? t('otherDevice'))}
              sub={t('lastSeen', { date: date(s.lastSeenAt) })}
              trailing={
                s.current ? null : (
                  <button type="button" className="tap focus-ring shrink-0 rounded-full px-3 t-footnote font-semibold text-danger" onClick={() => api.endSession(s.id).then(load).catch(() => toast(t('error')))}>
                    {t('signOut')}
                  </button>
                )
              }
            />
          ))}
        </Section>
      ) : null}

      <CodeSheet
        code={shown?.code ?? null}
        onClose={() => setShown(null)}
        title={shown?.kind === 'link' ? t('linkDevice') : t('recoveryCode')}
        body={shown?.kind === 'link' ? t('linkShow') : t('recoveryShow')}
        expiresAt={shown?.expiresAt}
      />
    </>
  );
}
