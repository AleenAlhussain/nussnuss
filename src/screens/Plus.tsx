import React, { useEffect, useState } from 'react';
import { View } from 'react-native';
import { useStore } from '../store';
import { useNav } from '../nav';
import { Button, Card, Icon, PlusBadge, Row, Screen, T, useToast, useUI } from '../ui';
import { Logo } from '../components';
import { buyPlus, getPurchaseState, PurchaseState, restorePlus } from '../purchases';
import { space } from '../theme';

export default function Plus() {
  const { settings, setSettings } = useStore();
  const nav = useNav();
  const toast = useToast();
  const { t, c } = useUI();
  const [state, setState] = useState<PurchaseState | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    getPurchaseState().then(setState);
  }, []);

  const features = [t('plusF1'), t('plusF2'), t('plusF3'), t('plusF4')];

  const buy = async () => {
    setBusy(true);
    const r = await buyPlus();
    setBusy(false);
    if (r === 'purchased') {
      setSettings({ plus: true });
      toast(t('plusActive'));
    } else if (r === 'failed') toast(t('purchaseFailed'));
    else if (r === 'unavailable') toast(t('plusNotReady'));
  };

  const restore = async () => {
    setBusy(true);
    const r = await restorePlus();
    setBusy(false);
    if (r) {
      setSettings({ plus: true });
      toast(t('plusActive'));
    } else toast(r === null ? t('plusNotReady') : t('nothingToRestore'));
  };

  const unavailable = state?.status === 'unavailable';

  return (
    <Screen
      testID="screen-plus"
      title={t('plus')}
      onBack={nav.back}
      footer={
        settings.plus ? undefined : (
          <>
            {unavailable ? (
              <T v="small" center testID="plus-unavailable">
                {state.reason === 'web' ? t('plusWebOnly') : t('plusNotReady')}
              </T>
            ) : null}
            <Button
              label={state?.status === 'ready' && state.price ? t('buyFor', { price: state.price }) : t('buyOnce')}
              onPress={buy}
              loading={busy || !state}
              disabled={unavailable}
              testID="buy-plus"
            />
            <Button label={t('restore')} variant="ghost" onPress={restore} disabled={unavailable || busy} testID="restore-plus" />
            {__DEV__ && unavailable ? (
              <Button label="Simulate purchase (development build only)" variant="ghost" onPress={() => setSettings({ plus: true })} testID="dev-unlock" />
            ) : null}
          </>
        )
      }
    >
      <View style={{ alignItems: 'center', gap: space[3], paddingTop: space[3] }}>
        <Logo size={64} />
        <PlusBadge />
        <T v="display" center role="header">
          {t('plusTitle')}
        </T>
        <T v="muted" center style={{ maxWidth: 380 }}>
          {t('plusBody')}
        </T>
      </View>
      <Card>
        {features.map((f) => (
          <Row key={f} gap={space[3]} style={{ paddingVertical: space[1] }}>
            <Icon name="check-circle" color={c.success} />
            <T v="body" style={{ flex: 1 }}>
              {f}
            </T>
          </Row>
        ))}
      </Card>
      {settings.plus ? (
        <View style={{ backgroundColor: c.successSoft, padding: space[4], borderRadius: 18 }} testID="plus-active">
          <T v="h2" color={c.success} center>
            {t('plusActive')}
          </T>
        </View>
      ) : null}
    </Screen>
  );
}
