import React, { useState } from 'react';
import { View } from 'react-native';
import { useStore } from '../store';
import { useNav } from '../nav';
import { Button, Field, Icon, Row, Screen, Segmented, T, useUI } from '../ui';
import { Logo } from '../components';
import { space } from '../theme';
import type { Lang } from '../types';

export default function Welcome() {
  const { settings, setSettings } = useStore();
  const nav = useNav();
  const { t, c } = useUI();
  const [name, setName] = useState(settings.name);
  const [err, setErr] = useState<string | null>(null);

  const start = () => {
    const n = name.trim();
    if (!n) {
      setErr(t('yourNameHint'));
      return;
    }
    setSettings({ name: n.slice(0, 40), onboarded: true });
    nav.reset([{ name: 'home' }]);
  };

  const points: [React.ComponentProps<typeof Icon>['name'], string, string][] =
    settings.lang === 'ar'
      ? [
          ['zap', 'بلا حدود', 'أضف مصاريف قد ما تبي، بدون انتظار ولا إعلانات'],
          ['user-x', 'بلا تسجيل', 'لا أنت ولا أصحابك تحتاجون حساب'],
          ['wifi-off', 'بدون إنترنت', 'يشتغل في البر والطيارة'],
        ]
      : [
          ['zap', 'No limits', 'Add as many expenses as you like. No waits, no ads.'],
          ['user-x', 'No sign-up', 'Not for you, not for your friends.'],
          ['wifi-off', 'Works offline', 'In the desert, on a plane, anywhere.'],
        ];

  return (
    <Screen
      testID="screen-welcome"
      footer={<Button label={t('start')} onPress={start} testID="start" icon="arrow-right" />}
    >
      <Row justify="flex-end">
        <View style={{ width: 220 }}>
          <Segmented<Lang>
            testID="lang"
            value={settings.lang}
            onChange={(l) => setSettings({ lang: l })}
            options={[
              { key: 'en', label: 'English' },
              { key: 'ar', label: 'العربية' },
            ]}
          />
        </View>
      </Row>
      <View style={{ alignItems: 'center', gap: space[4], paddingTop: space[5] }}>
        <Logo size={84} />
        <T v="display" center role="header">
          {t('welcomeTitle')}
        </T>
        <T v="muted" center style={{ maxWidth: 380 }}>
          {t('welcomeBody')}
        </T>
      </View>
      <View style={{ gap: space[3], paddingVertical: space[2] }}>
        {points.map(([icon, title, body]) => (
          <Row key={title} gap={space[3]} align="flex-start">
            <View style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: c.accentSoft, alignItems: 'center', justifyContent: 'center' }}>
              <Icon name={icon} size={18} color={c.onAccentSoft} />
            </View>
            <View style={{ flex: 1 }}>
              <T v="h2">{title}</T>
              <T v="muted">{body}</T>
            </View>
          </Row>
        ))}
      </View>
      <Field
        label={t('yourName')}
        hint={t('yourNameHint')}
        value={name}
        onChangeText={(v) => {
          setName(v);
          setErr(null);
        }}
        error={err}
        maxLength={40}
        autoComplete="given-name"
        returnKeyType="go"
        onSubmitEditing={start}
        testID="name"
      />
    </Screen>
  );
}
