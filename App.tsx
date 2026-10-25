import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, BackHandler, I18nManager, Linking, Platform, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { StoreProvider, useStore } from './src/store';
import { ToastProvider, UIProvider, useUI } from './src/ui';
import { NavCtx, Route, Nav } from './src/nav';
import { payloadFromUrl } from './src/share';
import { hasPlus } from './src/purchases';
import Welcome from './src/screens/Welcome';
import Home from './src/screens/Home';
import GroupEdit from './src/screens/GroupEdit';
import Group from './src/screens/Group';
import ExpenseScreen from './src/screens/Expense';
import Settings from './src/screens/Settings';
import Plus from './src/screens/Plus';
import Shared from './src/screens/Shared';

// Layout direction is handled by our own primitives so Arabic/English switch instantly,
// without the restart that native RTL flipping needs.
if (Platform.OS !== 'web') {
  try {
    I18nManager.allowRTL(false);
    I18nManager.forceRTL(false);
  } catch {}
}

function initialWebPayload(): string | null {
  if (Platform.OS !== 'web' || typeof window === 'undefined') return null;
  return payloadFromUrl(window.location.href);
}

function Navigator() {
  const { settings, setSettings } = useStore();
  const { scheme, c } = useUI();
  const [stack, setStack] = useState<Route[]>(() => {
    const base: Route = settings.onboarded ? { name: 'home' } : { name: 'welcome' };
    const p = initialWebPayload();
    return p ? [base, { name: 'shared', payload: p }] : [base];
  });

  const nav = useMemo<Nav>(
    () => ({
      push: (r) => setStack((s) => [...s, r]),
      back: () => setStack((s) => (s.length > 1 ? s.slice(0, -1) : s)),
      replace: (r) => setStack((s) => [...s.slice(0, -1), r]),
      reset: (rs) => setStack(rs),
      canGoBack: stack.length > 1,
    }),
    [stack.length],
  );

  const openUrl = useCallback((url: string | null | undefined) => {
    const p = payloadFromUrl(url);
    if (p) setStack((s) => [...s.filter((r) => r.name !== 'shared'), { name: 'shared', payload: p }]);
  }, []);

  // Deep links on iOS/Android: nussnuss://g?d=… and https://nussnuss.app/#g=…
  useEffect(() => {
    if (Platform.OS === 'web') {
      const onHash = () => openUrl(window.location.href);
      window.addEventListener('hashchange', onHash);
      return () => window.removeEventListener('hashchange', onHash);
    }
    Linking.getInitialURL().then(openUrl).catch(() => {});
    const sub = Linking.addEventListener('url', (e) => openUrl(e.url));
    return () => sub.remove();
  }, [openUrl]);

  // Android hardware back.
  useEffect(() => {
    if (Platform.OS !== 'android') return;
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (stack.length > 1) {
        nav.back();
        return true;
      }
      return false;
    });
    return () => sub.remove();
  }, [stack.length, nav]);

  // Keep Plus in sync with the store receipt (native builds with purchases configured).
  useEffect(() => {
    if (Platform.OS === 'web') return;
    hasPlus().then((owned) => {
      if (owned && !settings.plus) setSettings({ plus: true });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const top = stack[stack.length - 1];
  let screen: React.ReactNode;
  switch (top.name) {
    case 'welcome':
      screen = <Welcome />;
      break;
    case 'home':
      screen = <Home />;
      break;
    case 'groupEdit':
      screen = <GroupEdit key={`ge-${top.id ?? 'new'}`} id={top.id} />;
      break;
    case 'group':
      screen = <Group key={`g-${top.id}`} id={top.id} tab={top.tab} />;
      break;
    case 'expense':
      screen = <ExpenseScreen key={`e-${top.groupId}-${top.id ?? 'new'}`} groupId={top.groupId} id={top.id} />;
      break;
    case 'settings':
      screen = <Settings />;
      break;
    case 'plus':
      screen = <Plus />;
      break;
    case 'shared':
      screen = <Shared key={top.payload.slice(0, 32)} payload={top.payload} />;
      break;
  }

  return (
    <NavCtx.Provider value={nav}>
      <View style={{ flex: 1, backgroundColor: c.bg }}>{screen}</View>
      <StatusBar style={scheme === 'dark' ? 'light' : 'dark'} />
    </NavCtx.Provider>
  );
}

function Root() {
  const { ready, settings } = useStore();
  if (!ready) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#F7F6FB' }}>
        <ActivityIndicator color="#4F3BD6" />
      </View>
    );
  }
  const accent = settings.plus ? settings.accent : 'violet';
  return (
    <UIProvider lang={settings.lang} theme={settings.theme} accent={accent}>
      <ToastProvider>
        <Navigator />
      </ToastProvider>
    </UIProvider>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <StoreProvider>
        <Root />
      </StoreProvider>
    </SafeAreaProvider>
  );
}
