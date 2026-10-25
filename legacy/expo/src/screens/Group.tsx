import React, { useState } from 'react';
import { Linking, Platform, Share, View } from 'react-native';
import * as Clipboard from 'expo-clipboard';
import Constants from 'expo-constants';
import { useStore } from '../store';
import { useNav } from '../nav';
import { Button, Card, Empty, IconButton, Row, Screen, Segmented, Sheet, T, useToast, useUI } from '../ui';
import { CategoryIcon, SettlePlan } from '../components';
import { computeBalances, expenseInGroupCurrency, groupTotal } from '../split';
import { formatMoney } from '../money';
import { MAX_LINK_LENGTH, SHARE_BASE_URL, shareLink, summaryText } from '../share';
import { space } from '../theme';
import type { Group as G } from '../types';

export function webBase(): string {
  if (Platform.OS === 'web' && typeof window !== 'undefined' && !/^(localhost|127\.)/.test(window.location.hostname)) {
    return window.location.origin + window.location.pathname;
  }
  const configured = (Constants.expoConfig?.extra as { shareBaseUrl?: string } | undefined)?.shareBaseUrl;
  return configured || SHARE_BASE_URL;
}

export function ShareSheet({ group, visible, onClose }: { group: G; visible: boolean; onClose: () => void }) {
  const { t, lang } = useUI();
  const toast = useToast();
  const link = shareLink(group, webBase());
  const tooLong = link.length > MAX_LINK_LENGTH;
  const text = summaryText(group, lang, tooLong ? undefined : link);

  const copy = async (s: string) => {
    try {
      await Clipboard.setStringAsync(s);
      toast(t('copied'));
    } catch {
      toast(s.slice(0, 60));
    }
  };

  return (
    <Sheet visible={visible} onClose={onClose} title={t('shareTitle')} testID="share-sheet">
      <View style={{ gap: space[3] }}>
        <T v="muted">{t('shareBody')}</T>
        {tooLong ? <T v="small">{t('linkTooLong')}</T> : null}
        <Button
          label={t('whatsapp')}
          icon="message-circle"
          testID="share-whatsapp"
          onPress={() => {
            Linking.openURL(`https://wa.me/?text=${encodeURIComponent(text)}`).catch(() => copy(text));
            onClose();
          }}
        />
        {!tooLong ? <Button label={t('copyLink')} icon="link" variant="secondary" onPress={() => copy(link)} testID="copy-link" /> : null}
        <Button label={t('copySummary')} icon="copy" variant="secondary" onPress={() => copy(text)} testID="copy-summary" />
        <Button
          label={t('moreOptions')}
          icon="share-2"
          variant="ghost"
          onPress={async () => {
            try {
              await Share.share({ message: text });
            } catch {
              copy(text);
            }
          }}
        />
      </View>
    </Sheet>
  );
}

export default function Group({ id, tab: initialTab }: { id: string; tab?: 'expenses' | 'balances' }) {
  const store = useStore();
  const nav = useNav();
  const toast = useToast();
  const { t, c, lang } = useUI();
  const [tab, setTab] = useState<'expenses' | 'balances'>(initialTab ?? 'expenses');
  const [sharing, setSharing] = useState(false);
  const g = store.groups.find((x) => x.id === id);

  if (!g) {
    return (
      <Screen onBack={nav.back} title="">
        <Empty icon="alert-circle" title={t('badLink')} body="" />
      </Screen>
    );
  }

  const me = g.members.find((m) => m.name.trim().toLowerCase() === store.settings.name.trim().toLowerCase());
  const myBal = me ? computeBalances(g)[me.id] ?? 0 : null;
  const nameOf = (mid: string) => g.members.find((m) => m.id === mid)?.name ?? '?';
  const fmtDate = (iso: string) => {
    try {
      return new Date(iso).toLocaleDateString(lang === 'ar' ? 'ar-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'short' });
    } catch {
      return iso.slice(0, 10);
    }
  };

  return (
    <Screen
      testID="screen-group"
      title={`${g.emoji} ${g.name}`}
      onBack={nav.back}
      right={
        <Row gap={0}>
          <IconButton name="share-2" label={t('share')} onPress={() => setSharing(true)} testID="share" />
          <IconButton name="edit-2" label={t('editGroup')} onPress={() => nav.push({ name: 'groupEdit', id: g.id })} testID="edit-group" />
        </Row>
      }
      footer={<Button label={t('addExpense')} icon="plus" onPress={() => nav.push({ name: 'expense', groupId: g.id })} testID="add-expense" />}
    >
      <Card>
        <T v="muted">{t('total')}</T>
        <T v="display" testID="group-total">
          {formatMoney(groupTotal(g), g.currency, lang)}
        </T>
        {myBal !== null ? (
          <Row>
            <View style={{ backgroundColor: myBal > 0 ? c.successSoft : myBal < 0 ? c.dangerSoft : c.surface2, borderRadius: 12, paddingHorizontal: space[3], paddingVertical: space[2] }}>
              <T v="label" color={myBal > 0 ? c.success : myBal < 0 ? c.danger : c.textMuted} testID="my-balance">
                {myBal > 0 ? t('youAreOwed', { amount: formatMoney(myBal, g.currency, lang) }) : myBal < 0 ? t('youOwe', { amount: formatMoney(-myBal, g.currency, lang) }) : t('settled')}
              </T>
            </View>
          </Row>
        ) : null}
      </Card>

      <Segmented
        testID="tab"
        value={tab}
        onChange={setTab}
        options={[
          { key: 'expenses', label: `${t('expenses')} (${g.expenses.length})` },
          { key: 'balances', label: t('balances') },
        ]}
      />

      {tab === 'expenses' ? (
        g.expenses.length === 0 ? (
          <Empty icon="file-plus" title={t('noExpensesTitle')} body={t('noExpensesBody')} />
        ) : (
          <View style={{ gap: space[2] }}>
            {[...g.expenses]
              .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt))
              .map((e) => (
                <Card key={e.id} onPress={() => nav.push({ name: 'expense', groupId: g.id, id: e.id })} testID="expense-row" style={{ padding: space[3] }}>
                  <Row gap={space[3]}>
                    <CategoryIcon cat={e.category} />
                    <View style={{ flex: 1, gap: 2 }}>
                      <T v="h2" lines={1}>
                        {e.title}
                      </T>
                      <T v="small" lines={1}>
                        {e.currency === g.currency ? t('paidBy1', { name: nameOf(e.paidBy) }) : t('paidByX', { name: nameOf(e.paidBy), amount: formatMoney(e.amount, e.currency, lang) })} · {fmtDate(e.date)}
                      </T>
                    </View>
                    <T v="amount">{formatMoney(expenseInGroupCurrency(e, g.currency), g.currency, lang)}</T>
                  </Row>
                </Card>
              ))}
          </View>
        )
      ) : (
        <SettlePlan
          group={g}
          highlightName={store.settings.name}
          onMarkPaid={(from, to, amount) => {
            const pid = store.addPayment(g.id, { from, to, amount });
            toast(t('paidRecorded'), { label: t('undo'), onPress: () => store.deletePayment(g.id, pid) });
          }}
        />
      )}
      <ShareSheet group={g} visible={sharing} onClose={() => setSharing(false)} />
    </Screen>
  );
}
