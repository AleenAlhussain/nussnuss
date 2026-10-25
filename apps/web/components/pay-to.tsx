'use client';

import { Bank, Link as LinkIcon, Plus, Trash, Wallet } from '@phosphor-icons/react';
import { PAY_TO_KINDS, type PayTo, type PayToKind } from '@nussnuss/core';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import type { TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { Sheet } from './glass';
import { methodName } from './settle';
import { useToast } from './toast';
import { Button, Field, Section } from './ui';

const ICON: Record<PayToKind, typeof Bank> = { iban: Bank, instapay: Wallet, stcpay: Wallet, phone: Wallet, paypal: LinkIcon, wise: LinkIcon, link: LinkIcon };
const PLACEHOLDER: Record<PayToKind, string> = {
  iban: 'AE07 0331 2345 6789 0123 456',
  instapay: 'name@instapay',
  stcpay: '+966 5x xxx xxxx',
  phone: '+20 1x xxxx xxxx',
  paypal: 'paypal.me/name',
  wise: 'wise.com/pay/me/name',
  link: 'https://',
};

/** Settings › How friends pay you: shown to people in my groups when they settle up with me. */
export function PayToSection() {
  const { t, me, setMe } = useSession();
  const toast = useToast();
  const [adding, setAdding] = useState(false);
  const [kind, setKind] = useState<PayToKind>('iban');
  const [value, setValue] = useState('');
  const [label, setLabel] = useState('');
  const [error, setError] = useState<string | null>(null);
  const list = me?.payTo ?? [];
  useEffect(() => {
    if (!adding) return;
    setKind('iban');
    setValue('');
    setLabel('');
    setError(null);
  }, [adding]);

  const saveList = async (next: PayTo[]) => {
    const m = await api.patchMe({ payTo: next });
    setMe(m);
  };
  const add = async () => {
    try {
      await saveList([...list, { kind, value: value.trim(), ...(label.trim() ? { label: label.trim() } : {}) }]);
      setAdding(false);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  return (
    <>
      <Section title={t('payTo')} footer={t('payToHint')}>
        {list.map((p, i) => {
          const Icon = ICON[p.kind];
          return (
            <div key={`${p.kind}-${i}`} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0" data-testid="pay-to-row">
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-row bg-accent-soft text-on-accent-soft" aria-hidden>
                <Icon size={20} />
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="t-body text-text">{methodName(p, t)}</span>
                <span className="truncate t-footnote text-text-2" dir="ltr">
                  {p.value}
                </span>
              </span>
              <button
                type="button"
                aria-label={`${t('remove')} ${methodName(p, t)}`}
                className="tap focus-ring grid place-items-center rounded-full text-danger"
                onClick={() => saveList(list.filter((_, j) => j !== i)).catch((e) => toast((e as Error).message))}
              >
                <Trash size={18} />
              </button>
            </div>
          );
        })}
        {list.length < 5 ? (
          <button type="button" onClick={() => setAdding(true)} className="focus-ring flex min-h-12 w-full items-center gap-3 px-4 t-body text-accent" data-testid="add-pay-to">
            <Plus size={20} />
            {t('payAdd')}
          </button>
        ) : null}
      </Section>

      <Sheet
        open={adding}
        onClose={() => setAdding(false)}
        title={t('payAdd')}
        testId="pay-to-sheet"
        footer={
          <div className="flex flex-col gap-2">
            {error ? (
              <p className="text-center t-footnote text-danger" role="alert">
                {error}
              </p>
            ) : null}
            <Button block onClick={add} disabled={value.trim().length < 3} data-testid="save-pay-to">
              {t('save')}
            </Button>
          </div>
        }
      >
        <div className="flex flex-col gap-5">
          <div className="flex flex-wrap gap-2" role="radiogroup" aria-label={t('payTo')}>
            {PAY_TO_KINDS.map((k) => (
              <button
                key={k}
                type="button"
                role="radio"
                aria-checked={kind === k}
                onClick={() => setKind(k)}
                data-testid={`pay-kind-${k}`}
                className={`focus-ring inline-flex h-11 items-center rounded-full px-4 t-subhead font-medium ${kind === k ? 'bg-accent text-on-accent' : 'bg-surface text-text ring-1 ring-separator'}`}
              >
                {t(`pay_${k}` as TKey)}
              </button>
            ))}
          </div>
          <Field
            label={t('payValue')}
            value={value}
            placeholder={PLACEHOLDER[kind]}
            maxLength={120}
            inputMode={kind === 'phone' || kind === 'stcpay' ? 'tel' : kind === 'iban' || kind === 'instapay' ? 'text' : 'url'}
            autoCapitalize={kind === 'iban' ? 'characters' : 'none'}
            spellCheck={false}
            dir="ltr"
            onChange={(e) => {
              setValue(e.target.value);
              setError(null);
            }}
            data-testid="pay-value"
            data-autofocus
          />
          <Field label={t('payLabel')} value={label} maxLength={40} onChange={(e) => setLabel(e.target.value)} />
        </div>
      </Sheet>
    </>
  );
}
