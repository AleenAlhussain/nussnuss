import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, View } from 'react-native';
import { useStore } from '../store';
import { useNav } from '../nav';
import { Avatar, Button, Chip, Confirm, Field, Icon, IconButton, PlusBadge, Row, Screen, Segmented, T, useUI, useToast } from '../ui';
import { CATEGORIES, CurrencyButton, CurrencyPicker } from '../components';
import { catKey, modeKey } from '../i18n';
import { formatMoney, minorToInput, normalizeDigits, parseAmount, decimalsOf } from '../money';
import { owedInExpenseCurrency, validateSplit } from '../split';
import { radius, space } from '../theme';
import type { CategoryId, ExpenseDraft, SplitItem, SplitMode } from '../types';

const MODES: SplitMode[] = ['equal', 'exact', 'percent', 'shares'];

function parsePercent(s: string): number {
  const n = Number(normalizeDigits(s).replace(',', '.').replace('%', '').trim());
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0;
}
function parseShares(s: string): number {
  const n = Number(normalizeDigits(s).trim());
  return Number.isInteger(n) && n > 0 && n <= 1000 ? n : 0;
}

export default function ExpenseScreen({ groupId, id }: { groupId: string; id?: string }) {
  const store = useStore();
  const nav = useNav();
  const toast = useToast();
  const { t, c, lang } = useUI();
  const g = store.groups.find((x) => x.id === groupId);
  const existing = g?.expenses.find((e) => e.id === id);
  const members = g?.members ?? [];
  const me = members.find((m) => m.name.trim().toLowerCase() === store.settings.name.trim().toLowerCase());

  const initValues = (mode: SplitMode): Record<string, string> => {
    if (!existing || existing.mode !== mode) {
      return Object.fromEntries(members.map((m) => [m.id, mode === 'shares' ? '1' : '']));
    }
    return Object.fromEntries(
      members.map((m) => {
        const v = existing.items.find((i) => i.memberId === m.id)?.value ?? 0;
        if (mode === 'exact') return [m.id, v ? minorToInput(v, existing.currency) : ''];
        if (mode === 'percent') return [m.id, v ? String(v / 100) : ''];
        return [m.id, String(v)];
      }),
    );
  };

  const [amountText, setAmountText] = useState(existing ? minorToInput(existing.amount, existing.currency) : '');
  const [title, setTitle] = useState(existing?.title ?? '');
  const [category, setCategory] = useState<CategoryId>(existing?.category ?? 'other');
  const [paidBy, setPaidBy] = useState(existing?.paidBy ?? me?.id ?? members[0]?.id ?? '');
  const [mode, setMode] = useState<SplitMode>(existing?.mode ?? 'equal');
  const [values, setValues] = useState<Record<string, string>>(() => initValues(existing?.mode ?? 'equal'));
  const [included, setIncluded] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(members.map((m) => [m.id, existing && existing.mode === 'equal' ? existing.items.some((i) => i.memberId === m.id && i.value > 0) : true])),
  );
  const [cur, setCur] = useState(existing?.currency ?? g?.currency ?? 'USD');
  const [rateText, setRateText] = useState(existing && existing.currency !== g?.currency ? String(existing.rate) : '');
  const [pick, setPick] = useState(false);
  const [tried, setTried] = useState(false);
  const [confirmDel, setConfirmDel] = useState(false);
  const [draftNote, setDraftNote] = useState(false);
  const draftLoaded = useRef(!!existing);

  // Restore a draft for new expenses (fix F8).
  useEffect(() => {
    if (existing || !g) return;
    store.loadDraft(g.id).then((d) => {
      if (d && (d.amountText || d.title)) {
        setAmountText(d.amountText);
        setTitle(d.title);
        setCategory(d.category);
        if (members.some((m) => m.id === d.paidBy)) setPaidBy(d.paidBy);
        setMode(d.mode);
        setValues((v) => ({ ...v, ...d.values }));
        setIncluded((v) => ({ ...v, ...d.included }));
        setCur(d.currency);
        setRateText(d.rateText);
        setDraftNote(true);
      }
      draftLoaded.current = true;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (existing || !g || !draftLoaded.current) return;
    const d: ExpenseDraft = { groupId: g.id, title, amountText, currency: cur, rateText, paidBy, mode, values, included, category };
    const h = setTimeout(() => store.saveDraft(d), 300);
    return () => clearTimeout(h);
  }, [existing, g, title, amountText, cur, rateText, paidBy, mode, values, included, category, store]);

  const amount = parseAmount(amountText, cur) ?? 0;
  const foreign = !!g && cur !== g.currency;
  const rate = foreign ? Number(normalizeDigits(rateText).replace(',', '.')) : 1;

  const items: SplitItem[] = useMemo(
    () =>
      members.map((m) => {
        if (mode === 'equal') return { memberId: m.id, value: included[m.id] ? 1 : 0 };
        if (mode === 'exact') return { memberId: m.id, value: parseAmount(values[m.id] ?? '', cur) ?? 0 };
        if (mode === 'percent') return { memberId: m.id, value: parsePercent(values[m.id] ?? '') };
        return { memberId: m.id, value: parseShares(values[m.id] ?? '') };
      }),
    [members, mode, included, values, cur],
  );

  const splitErr = validateSplit(amount, mode, items, paidBy, members.map((m) => m.id));
  const preview = !splitErr ? owedInExpenseCurrency({ amount, mode, items }) : null;
  const sumExact = items.reduce((a, b) => a + (mode === 'exact' ? b.value : 0), 0);
  const sumPct = items.reduce((a, b) => a + (mode === 'percent' ? b.value : 0), 0);

  if (!g) return null;

  const errText = (() => {
    if (!tried) return null;
    if (!amount) return t('err_noAmount');
    if (foreign && !(rate > 0)) return t('err_rate');
    if (!title.trim()) return t('err_title');
    if (!splitErr) return null;
    if (splitErr === 'exactMismatch') return t('err_exactMismatch', { got: formatMoney(sumExact, cur, lang), need: formatMoney(amount, cur, lang) });
    if (splitErr === 'percentMismatch') return t('err_percentMismatch', { got: (sumPct / 100).toString() });
    return t(`err_${splitErr}` as Parameters<typeof t>[0]);
  })();

  const save = () => {
    setTried(true);
    if (!amount || !title.trim() || splitErr || (foreign && !(rate > 0))) return;
    const data = {
      title: title.trim().slice(0, 80),
      amount,
      currency: cur,
      rate: foreign ? rate : 1,
      paidBy,
      mode,
      items: items.filter((i) => i.value > 0),
      category,
      date: existing?.date ?? new Date().toISOString(),
    };
    if (existing) store.updateExpense(g.id, { ...existing, ...data });
    else {
      store.addExpense(g.id, data);
      store.clearDraft(g.id);
    }
    nav.back();
  };

  const remaining =
    mode === 'exact' && amount
      ? t('remaining', { amount: formatMoney(amount - sumExact, cur, lang) })
      : mode === 'percent'
        ? t('percentLeft', { n: ((10000 - sumPct) / 100).toString() })
        : null;

  return (
    <Screen
      testID="screen-expense"
      title={existing ? existing.title : t('addExpense')}
      onBack={nav.back}
      right={existing ? <IconButton name="trash-2" label={t('delete')} onPress={() => setConfirmDel(true)} testID="delete-expense" color={c.danger} /> : undefined}
      footer={
        <>
          {errText ? (
            <T v="small" color={c.danger} testID="expense-error">
              {errText}
            </T>
          ) : null}
          <Button label={t('save')} icon="check" onPress={save} testID="save-expense" />
        </>
      }
    >
      {draftNote ? (
        <Row gap={space[2]} style={{ backgroundColor: c.accentSoft, padding: space[3], borderRadius: radius.md }}>
          <Icon name="rotate-ccw" size={16} color={c.onAccentSoft} />
          <T v="small" color={c.onAccentSoft} style={{ flex: 1 }}>
            {t('draftRestored')}
          </T>
        </Row>
      ) : null}

      <Row gap={space[2]} align="flex-end">
        <Field
          style={{ flex: 1 }}
          label={t('amount')}
          big
          value={amountText}
          onChangeText={setAmountText}
          keyboardType="decimal-pad"
          inputMode="decimal"
          placeholder={decimalsOf(cur) === 3 ? '0.000' : decimalsOf(cur) === 0 ? '0' : '0.00'}
          testID="amount"
          autoFocus={!existing}
        />
        <View style={{ width: 112 }}>
          <CurrencyButton
            compact
            code={cur}
            locked={!store.settings.plus}
            testID="expense-currency"
            onPress={() => (store.settings.plus ? setPick(true) : nav.push({ name: 'plus' }))}
          />
        </View>
      </Row>
      {foreign ? (
        <Field label={t('rate', { from: cur, to: g.currency })} value={rateText} onChangeText={setRateText} keyboardType="decimal-pad" inputMode="decimal" placeholder="3.6725" testID="rate" />
      ) : null}

      <Field label={t('whatFor')} placeholder={t('whatForPh')} value={title} onChangeText={setTitle} maxLength={80} testID="title" />

      <View style={{ gap: space[2] }}>
        <T v="label">{t('category')}</T>
        <Row wrap gap={space[2]}>
          {CATEGORIES.map((k) => (
            <Chip key={k} label={t(catKey(k))} selected={k === category} onPress={() => setCategory(k)} testID={`cat-${k}`} />
          ))}
        </Row>
      </View>

      <View style={{ gap: space[2] }}>
        <T v="label">{t('paidBy')}</T>
        <Row wrap gap={space[2]}>
          {members.map((m) => (
            <Chip key={m.id} label={m.name} selected={m.id === paidBy} onPress={() => setPaidBy(m.id)} testID="payer" />
          ))}
        </Row>
      </View>

      <View style={{ gap: space[2] }}>
        <Row justify="space-between">
          <T v="label">{t('splitHow')}</T>
          {remaining ? (
            <T v="small" color={(mode === 'exact' ? amount - sumExact : 10000 - sumPct) === 0 ? c.success : c.textMuted} testID="remaining">
              {remaining}
            </T>
          ) : null}
        </Row>
        <Segmented<SplitMode>
          testID="mode"
          value={mode}
          onChange={(m) => {
            setMode(m);
            setValues(initValues(m));
          }}
          options={MODES.map((m) => ({ key: m, label: t(modeKey(m)) }))}
        />
        <View style={{ gap: space[1], marginTop: space[1] }}>
          {members.map((m, i) => {
            const share = preview?.[m.id];
            return (
              <Row key={m.id} gap={space[3]} style={{ minHeight: 52 }}>
                <Avatar name={m.name} index={i} size={32} />
                <T v="body" lines={1} style={{ flex: 1 }}>
                  {m.name}
                </T>
                {mode === 'equal' ? (
                  <Pressable
                    onPress={() => setIncluded((s) => ({ ...s, [m.id]: !s[m.id] }))}
                    accessibilityRole="checkbox"
                    accessibilityState={{ checked: !!included[m.id] }}
                    accessibilityLabel={m.name}
                    testID="include"
                    hitSlop={8}
                  >
                    <Row gap={space[2]}>
                      <T v="label" color={c.textMuted}>
                        {included[m.id] && share !== undefined ? formatMoney(share, cur, lang) : ''}
                      </T>
                      <View style={{ width: 26, height: 26, borderRadius: 8, borderWidth: 2, borderColor: included[m.id] ? c.accent : c.borderInput, backgroundColor: included[m.id] ? c.accent : 'transparent', alignItems: 'center', justifyContent: 'center' }}>
                        {included[m.id] ? <Icon name="check" size={16} color={c.onAccent} /> : null}
                      </View>
                    </Row>
                  </Pressable>
                ) : (
                  <Row gap={space[2]}>
                    {mode !== 'exact' && share !== undefined ? (
                      <T v="small" color={c.textMuted}>
                        {formatMoney(share, cur, lang)}
                      </T>
                    ) : null}
                    <Field
                      value={values[m.id] ?? ''}
                      onChangeText={(v) => setValues((s) => ({ ...s, [m.id]: v }))}
                      keyboardType={mode === 'shares' ? 'number-pad' : 'decimal-pad'}
                      inputMode={mode === 'shares' ? 'numeric' : 'decimal'}
                      placeholder={mode === 'percent' ? '%' : mode === 'shares' ? '1' : '0'}
                      accessibilityLabel={`${m.name} ${t(modeKey(mode))}`}
                      testID="split-value"
                      style={{ width: 96 }}
                      inputStyle={{ minHeight: 40, textAlign: 'center' }}
                    />
                  </Row>
                )}
              </Row>
            );
          })}
        </View>
      </View>

      {!store.settings.plus ? (
        <Pressable onPress={() => nav.push({ name: 'plus' })} accessibilityRole="button" style={{ alignSelf: 'center' }}>
          <Row gap={space[2]}>
            <PlusBadge />
            <T v="small">{t('plusF1')}</T>
          </Row>
        </Pressable>
      ) : null}

      <CurrencyPicker visible={pick} onClose={() => setPick(false)} onPick={setCur} selected={cur} />
      <Confirm
        visible={confirmDel}
        message={t('deleteExpenseQ')}
        confirmLabel={t('delete')}
        onCancel={() => setConfirmDel(false)}
        onConfirm={() => {
          setConfirmDel(false);
          if (existing) {
            store.deleteExpense(g.id, existing.id);
            toast(t('delete') + ' ✓', { label: t('undo'), onPress: () => store.addExpense(g.id, existing) });
          }
          nav.back();
        }}
      />
    </Screen>
  );
}
