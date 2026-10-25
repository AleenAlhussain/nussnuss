import React, { useMemo, useState } from 'react';
import { Pressable, View, Text } from 'react-native';
import { CURRENCIES, currency, formatMoney } from './money';
import { Avatar, Field, Icon, Row, Sheet, T, useUI } from './ui';
import { space, radius } from './theme';
import { catKey } from './i18n';
import type { CategoryId, Group } from './types';
import { computeBalances, simplifyDebts } from './split';

/** The mark: one coin, two fair halves. Drawn with views so it needs no image or SVG library. */
export function Logo({ size = 72 }: { size?: number }) {
  const { c } = useUI();
  const half = size / 2;
  const gap = Math.max(2, size * 0.06);
  return (
    <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={{ width: size + gap, height: size, flexDirection: 'row', gap }}>
      <View style={{ width: half, height: size, backgroundColor: c.accent, borderTopLeftRadius: half, borderBottomLeftRadius: half }} />
      <View style={{ width: half, height: size, backgroundColor: c.highlight, borderTopRightRadius: half, borderBottomRightRadius: half, marginTop: size * 0.08 }} />
    </View>
  );
}

export const CAT_ICON: Record<CategoryId, React.ComponentProps<typeof Icon>['name']> = {
  food: 'coffee',
  groceries: 'shopping-cart',
  transport: 'navigation',
  stay: 'home',
  fun: 'star',
  bills: 'file-text',
  shopping: 'shopping-bag',
  other: 'tag',
};

export const CATEGORIES: CategoryId[] = ['food', 'groceries', 'transport', 'stay', 'fun', 'bills', 'shopping', 'other'];

export function CategoryIcon({ cat }: { cat: CategoryId }) {
  const { c } = useUI();
  return (
    <View style={{ width: 40, height: 40, borderRadius: radius.md, backgroundColor: c.accentSoft, alignItems: 'center', justifyContent: 'center' }}>
      <Icon name={CAT_ICON[cat]} size={18} color={c.onAccentSoft} />
    </View>
  );
}

export function CurrencyPicker({ visible, onClose, onPick, selected }: { visible: boolean; onClose: () => void; onPick: (code: string) => void; selected: string }) {
  const { c, lang, t } = useUI();
  const [q, setQ] = useState('');
  const list = useMemo(() => {
    const s = q.trim().toLowerCase();
    return CURRENCIES.filter((x) => !s || x.code.toLowerCase().includes(s) || x.en.toLowerCase().includes(s) || x.ar.includes(s));
  }, [q]);
  return (
    <Sheet visible={visible} onClose={onClose} title={t('currency')} testID="currency-sheet">
      <Field placeholder="AED, SAR, USD…" value={q} onChangeText={setQ} autoCapitalize="characters" testID="currency-search" />
      <View style={{ marginTop: space[2] }}>
        {list.map((x) => {
          const on = x.code === selected;
          return (
            <Pressable
              key={x.code}
              onPress={() => {
                onPick(x.code);
                onClose();
                setQ('');
              }}
              testID={`currency-${x.code}`}
              accessibilityRole="button"
              accessibilityState={{ selected: on }}
              style={({ pressed }) => [{ paddingVertical: space[3], paddingHorizontal: space[2], borderRadius: radius.sm }, (pressed || on) && { backgroundColor: c.surface2 }]}
            >
              <Row justify="space-between">
                <T v="body" style={{ flex: 1 }}>
                  {lang === 'ar' ? x.ar : x.en}
                </T>
                <T v="label" color={c.textMuted}>
                  {x.code}
                </T>
              </Row>
            </Pressable>
          );
        })}
      </View>
    </Sheet>
  );
}

export function CurrencyButton({ code, onPress, testID, locked, compact }: { code: string; onPress: () => void; testID?: string; locked?: boolean; compact?: boolean }) {
  const { c, lang } = useUI();
  const info = currency(code);
  return (
    <Pressable
      onPress={onPress}
      testID={testID}
      accessibilityRole="button"
      accessibilityLabel={compact ? `${code}, ${lang === 'ar' ? info.ar : info.en}` : lang === 'ar' ? `${info.ar} (${code})` : `${code} · ${info.en}`}
      style={({ pressed }) => [{ borderWidth: 1, borderColor: c.borderInput, borderRadius: radius.md, minHeight: compact ? 64 : 48, paddingHorizontal: space[3], justifyContent: 'center', backgroundColor: c.surface }, pressed && { backgroundColor: c.surface2 }]}
    >
      <Row justify="space-between">
        <T v={compact ? 'h2' : 'body'} lines={1} style={{ flexShrink: 1 }}>
          {compact ? code : lang === 'ar' ? `${info.ar} (${code})` : `${code} · ${info.en}`}
        </T>
        <Icon name={locked ? 'lock' : 'chevron-down'} size={18} color={c.textMuted} />
      </Row>
    </Pressable>
  );
}

/** Balances list + who-pays-whom, shared by the group screen and the shared view. */
export function SettlePlan({ group, onMarkPaid, highlightName }: { group: Group; onMarkPaid?: (from: string, to: string, amount: number) => void; highlightName?: string }) {
  const { c, t, lang } = useUI();
  const balances = computeBalances(group);
  const order = group.members.map((m) => m.id);
  const transfers = simplifyDebts(balances, order);
  const nameOf = (id: string) => group.members.find((m) => m.id === id)?.name ?? '?';
  const idx = (id: string) => order.indexOf(id);
  const isMe = (id: string) => !!highlightName && nameOf(id).trim().toLowerCase() === highlightName.trim().toLowerCase();
  return (
    <View style={{ gap: space[4] }}>
      <View style={{ gap: space[2] }}>
        <T v="h2" role="header">
          {t('whoOwes')}
        </T>
        {transfers.length === 0 ? (
          <View style={{ backgroundColor: c.successSoft, borderRadius: radius.lg, padding: space[4] }} testID="all-settled">
            <Row gap={space[2]}>
              <Icon name="check-circle" color={c.success} />
              <T v="h2" color={c.success}>
                {t('settledNice')}
              </T>
            </Row>
          </View>
        ) : (
          transfers.map((tr, i) => (
            <View key={`${tr.from}-${tr.to}-${i}`} style={{ backgroundColor: c.surface, borderColor: c.border, borderWidth: 1, borderRadius: radius.lg, padding: space[3], gap: space[3] }} testID="transfer">
              <Row justify="space-between" gap={space[3]}>
                <Row gap={space[2]} style={{ flex: 1 }}>
                  <Avatar name={nameOf(tr.from)} index={idx(tr.from)} size={32} />
                  <Icon name="arrow-right" size={16} color={c.textMuted} />
                  <Avatar name={nameOf(tr.to)} index={idx(tr.to)} size={32} />
                  <T v="body" style={{ flex: 1 }} lines={2}>
                    <Text style={{ fontWeight: isMe(tr.from) ? '800' : '600' }}>{nameOf(tr.from)}</Text>
                    {` ${t('pays')} `}
                    <Text style={{ fontWeight: isMe(tr.to) ? '800' : '600' }}>{nameOf(tr.to)}</Text>
                  </T>
                </Row>
                <T v="amount">{formatMoney(tr.amount, group.currency, lang)}</T>
              </Row>
              {onMarkPaid ? (
                <Pressable
                  onPress={() => onMarkPaid(tr.from, tr.to, tr.amount)}
                  accessibilityRole="button"
                  testID="mark-paid"
                  style={({ pressed }) => [{ backgroundColor: c.accentSoft, borderRadius: radius.md, minHeight: 40, alignItems: 'center', justifyContent: 'center' }, pressed && { opacity: 0.8 }]}
                >
                  <Row gap={space[2]}>
                    <Icon name="check" size={16} color={c.onAccentSoft} />
                    <Text style={{ color: c.onAccentSoft, fontWeight: '700' }}>{t('markPaid')}</Text>
                  </Row>
                </Pressable>
              ) : null}
            </View>
          ))
        )}
      </View>
      <View style={{ gap: space[2] }}>
        <T v="h2" role="header">
          {t('balances')}
        </T>
        {group.members.map((m, i) => {
          const b = balances[m.id] ?? 0;
          const color = b > 0 ? c.success : b < 0 ? c.danger : c.textMuted;
          const label = b > 0 ? t('isOwed', { amount: formatMoney(b, group.currency, lang) }) : b < 0 ? t('owes', { amount: formatMoney(-b, group.currency, lang) }) : t('even');
          return (
            <Row key={m.id} justify="space-between" style={{ paddingVertical: space[1] }}>
              <Row gap={space[3]} style={{ flex: 1 }}>
                <Avatar name={m.name} index={i} />
                <T v="body" lines={1} style={{ flex: 1, fontWeight: isMe(m.id) ? '700' : '400' }}>
                  {m.name}
                  {isMe(m.id) ? ` (${t('you')})` : ''}
                </T>
              </Row>
              <T v="label" color={color} testID={`balance-${m.name}`}>
                {label}
              </T>
            </Row>
          );
        })}
      </View>
    </View>
  );
}
