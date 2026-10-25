import React from 'react';
import { View } from 'react-native';
import { useStore } from '../store';
import { useNav } from '../nav';
import { Button, Card, Empty, IconButton, Row, Screen, T, useUI } from '../ui';
import { computeBalances, groupTotal } from '../split';
import { formatMoney } from '../money';
import { space } from '../theme';

export default function Home() {
  const { groups, settings, createDemo } = useStore();
  const nav = useNav();
  const { t, c, lang } = useUI();
  const me = settings.name.trim().toLowerCase();

  return (
    <Screen
      testID="screen-home"
      title={t('groups')}
      right={<IconButton name="settings" label={t('settings')} onPress={() => nav.push({ name: 'settings' })} testID="open-settings" />}
      footer={groups.length ? <Button label={t('newGroup')} icon="plus" onPress={() => nav.push({ name: 'groupEdit' })} testID="new-group" /> : undefined}
    >
      {groups.length === 0 ? (
        <Empty icon="users" title={t('noGroupsTitle')} body={t('noGroupsBody')}>
          <Button label={t('newGroup')} icon="plus" onPress={() => nav.push({ name: 'groupEdit' })} testID="new-group" />
          <Button label={t('tryDemo')} variant="secondary" icon="play" onPress={() => nav.push({ name: 'group', id: createDemo(lang, settings.name) })} testID="try-demo" />
        </Empty>
      ) : (
        groups.map((g) => {
          const mine = g.members.find((m) => m.name.trim().toLowerCase() === me);
          const bal = mine ? computeBalances(g)[mine.id] ?? 0 : null;
          return (
            <Card key={g.id} onPress={() => nav.push({ name: 'group', id: g.id })} testID="group-card">
              <Row gap={space[3]}>
                <View style={{ width: 48, height: 48, borderRadius: 14, backgroundColor: c.surface2, alignItems: 'center', justifyContent: 'center' }}>
                  <T v="title">{g.emoji}</T>
                </View>
                <View style={{ flex: 1, gap: 2 }}>
                  <T v="h2" lines={1}>
                    {g.name}
                  </T>
                  <T v="muted" lines={1}>
                    {g.members.map((m) => m.name).join(lang === 'ar' ? '، ' : ', ')}
                  </T>
                </View>
                <View style={{ alignItems: lang === 'ar' ? 'flex-start' : 'flex-end', gap: 2 }}>
                  {bal === null ? (
                    <T v="label">{formatMoney(groupTotal(g), g.currency, lang)}</T>
                  ) : bal === 0 ? (
                    <T v="label" color={c.textMuted}>
                      {t('settled')}
                    </T>
                  ) : (
                    <T v="label" color={bal > 0 ? c.success : c.danger}>
                      {bal > 0 ? t('youAreOwed', { amount: formatMoney(bal, g.currency, lang) }) : t('youOwe', { amount: formatMoney(-bal, g.currency, lang) })}
                    </T>
                  )}
                </View>
              </Row>
            </Card>
          );
        })
      )}
    </Screen>
  );
}
