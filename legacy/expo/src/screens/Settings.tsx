import React from 'react';
import { Platform, Pressable, Share, View } from 'react-native';
import Constants from 'expo-constants';
import { useStore } from '../store';
import { useNav } from '../nav';
import { Button, Card, Divider, Field, Icon, PlusBadge, Row, Screen, Segmented, T, useToast, useUI } from '../ui';
import { ACCENT_NAMES, accentSwatch, AccentName, space } from '../theme';
import { toCSV } from '../share';
import type { Lang, ThemePref } from '../types';

function downloadWeb(filename: string, text: string) {
  const blob = new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export default function Settings() {
  const { settings, setSettings, groups } = useStore();
  const nav = useNav();
  const toast = useToast();
  const { t, c, scheme } = useUI();

  const exportGroup = async (gid: string) => {
    if (!settings.plus) return nav.push({ name: 'plus' });
    const g = groups.find((x) => x.id === gid);
    if (!g) return;
    const csv = toCSV(g, settings.lang);
    const file = `${g.name.replace(/[^\p{L}\p{N}]+/gu, '-')}.csv`;
    if (Platform.OS === 'web') downloadWeb(file, csv);
    else {
      try {
        await Share.share({ message: csv, title: file });
      } catch {
        toast(t('purchaseFailed'));
      }
    }
  };

  return (
    <Screen testID="screen-settings" title={t('settings')} onBack={nav.back}>
      <Card>
        <T v="label">{t('language')}</T>
        <Segmented<Lang>
          testID="settings-lang"
          value={settings.lang}
          onChange={(l) => setSettings({ lang: l })}
          options={[
            { key: 'en', label: 'English' },
            { key: 'ar', label: 'العربية' },
          ]}
        />
        <Divider />
        <Field label={t('yourName')} value={settings.name} onChangeText={(v) => setSettings({ name: v.slice(0, 40) })} testID="settings-name" />
        <Divider />
        <T v="label">{t('theme')}</T>
        <Segmented<ThemePref>
          value={settings.theme}
          onChange={(v) => setSettings({ theme: v })}
          options={(['system', 'light', 'dark'] as ThemePref[]).map((k) => ({ key: k, label: t(`theme_${k}`) }))}
        />
      </Card>

      <Card onPress={() => nav.push({ name: 'plus' })} testID="open-plus">
        <Row justify="space-between">
          <Row gap={space[2]} style={{ flex: 1 }}>
            <PlusBadge />
            <T v="h2">{t('plus')}</T>
          </Row>
          <Row gap={space[1]}>
            {settings.plus ? <T v="small" color={c.success}>✓</T> : null}
            <Icon name="chevron-right" color={c.textMuted} />
          </Row>
        </Row>
        <Row gap={space[1]} align="center">
          <T v="label">{t('accent')}</T>
          {!settings.plus ? <Icon name="lock" size={14} color={c.textMuted} /> : null}
        </Row>
        <Row gap={space[3]}>
          {ACCENT_NAMES.map((a: AccentName) => {
            const on = settings.accent === a;
            return (
              <Pressable
                key={a}
                onPress={() => (settings.plus || a === 'violet' ? setSettings({ accent: a }) : nav.push({ name: 'plus' }))}
                accessibilityRole="radio"
                accessibilityState={{ checked: on }}
                accessibilityLabel={a}
                testID={`accent-${a}`}
                style={{ width: 40, height: 40, borderRadius: 20, backgroundColor: accentSwatch(a, scheme), borderWidth: on ? 3 : 0, borderColor: c.text }}
              />
            );
          })}
        </Row>
      </Card>

      {groups.length ? (
        <Card>
          <Row gap={space[1]}>
            <T v="label">{t('exportCsv')}</T>
            {!settings.plus ? <Icon name="lock" size={14} color={c.textMuted} /> : null}
          </Row>
          {groups.map((g) => (
            <Row key={g.id} justify="space-between">
              <T v="body" lines={1} style={{ flex: 1 }}>
                {g.emoji} {g.name}
              </T>
              <Button small full={false} variant="secondary" icon="download" label="CSV" onPress={() => exportGroup(g.id)} testID="export-csv" />
            </Row>
          ))}
        </Card>
      ) : null}

      <Card>
        <Row gap={space[2]}>
          <Icon name="shield" color={c.success} />
          <T v="h2">{t('privacy')}</T>
        </Row>
        <T v="muted">{t('privacyBody')}</T>
      </Card>

      <View style={{ alignItems: 'center', gap: space[1], paddingVertical: space[3] }}>
        <T v="label">{t('appName')}</T>
        <T v="small">{t('version', { v: Constants.expoConfig?.version ?? '1.0.0' })}</T>
        <T v="small">{t('tagline')}</T>
      </View>
    </Screen>
  );
}

