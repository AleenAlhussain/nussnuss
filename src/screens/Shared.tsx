import React, { useMemo } from 'react';
import { Linking, Platform, View } from 'react-native';
import { useStore } from '../store';
import { STORE_LINKS, useNav } from '../nav';
import { Button, Card, Empty, Row, Screen, T, useToast, useUI } from '../ui';
import { CategoryIcon, Logo, SettlePlan } from '../components';
import { decodeGroup } from '../share';
import { expenseInGroupCurrency, groupTotal } from '../split';
import { formatMoney } from '../money';
import { space } from '../theme';

function clearHash() {
  if (Platform.OS === 'web' && typeof window !== 'undefined' && window.location.hash) {
    window.history.replaceState(null, '', window.location.pathname + window.location.search);
  }
}

export default function Shared({ payload }: { payload: string }) {
  const store = useStore();
  const nav = useNav();
  const toast = useToast();
  const { t, c, lang } = useUI();
  const g = useMemo(() => decodeGroup(payload), [payload]);

  const leave = () => {
    clearHash();
    if (nav.canGoBack) nav.back();
    else nav.reset([{ name: store.settings.onboarded ? 'home' : 'welcome' }]);
  };

  if (!g) {
    return (
      <Screen testID="screen-shared" title={t('sharedGroup')} onBack={leave}>
        <Empty icon="link-2" title={t('badLink')} body="" />
      </Screen>
    );
  }

  const nameOf = (id: string) => g.members.find((m) => m.id === id)?.name ?? '?';
  const storeLink = Platform.OS === 'web' ? (/(iPhone|iPad)/.test(navigator.userAgent) ? STORE_LINKS.ios : STORE_LINKS.android) : '';

  return (
    <Screen
      testID="screen-shared"
      title={`${g.emoji} ${g.name}`}
      onBack={leave}
      footer={
        <>
          <Button
            label={t('importGroup')}
            icon="download"
            testID="import-group"
            onPress={() => {
              const r = store.importGroup(g);
              toast(r === 'new' ? t('imported') : t('alreadyImported'));
              clearHash();
              nav.reset([{ name: 'home' }, { name: 'group', id: g.id, tab: 'balances' }]);
            }}
          />
          {storeLink ? <Button label={t('getApp')} variant="ghost" onPress={() => Linking.openURL(storeLink)} /> : null}
        </>
      }
    >
      <Row gap={space[3]} style={{ backgroundColor: c.accentSoft, padding: space[3], borderRadius: 14 }}>
        <Logo size={28} />
        <T v="small" color={c.onAccentSoft} style={{ flex: 1 }}>
          {t('sharedNote')}
        </T>
      </Row>
      <Card>
        <T v="muted">{t('total')}</T>
        <T v="display" testID="shared-total">
          {formatMoney(groupTotal(g), g.currency, lang)}
        </T>
      </Card>
      <SettlePlan group={g} />
      <View style={{ gap: space[2] }}>
        <T v="h2" role="header">
          {t('expenses')} ({g.expenses.length})
        </T>
        {g.expenses.map((e) => (
          <Card key={e.id} style={{ padding: space[3] }}>
            <Row gap={space[3]}>
              <CategoryIcon cat={e.category} />
              <View style={{ flex: 1 }}>
                <T v="h2" lines={1}>
                  {e.title}
                </T>
                <T v="small">{e.currency === g.currency ? t('paidBy1', { name: nameOf(e.paidBy) }) : t('paidByX', { name: nameOf(e.paidBy), amount: formatMoney(e.amount, e.currency, lang) })}</T>
              </View>
              <T v="amount">{formatMoney(expenseInGroupCurrency(e, g.currency), g.currency, lang)}</T>
            </Row>
          </Card>
        ))}
      </View>
    </Screen>
  );
}
