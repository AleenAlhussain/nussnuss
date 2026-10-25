import { createContext, useContext } from 'react';

export type Route =
  | { name: 'welcome' }
  | { name: 'home' }
  | { name: 'groupEdit'; id?: string }
  | { name: 'group'; id: string; tab?: 'expenses' | 'balances' }
  | { name: 'expense'; groupId: string; id?: string }
  | { name: 'settings' }
  | { name: 'plus' }
  | { name: 'shared'; payload: string };

export interface Nav {
  push: (r: Route) => void;
  back: () => void;
  replace: (r: Route) => void;
  reset: (rs: Route[]) => void;
  canGoBack: boolean;
}

export const NavCtx = createContext<Nav | null>(null);

export function useNav(): Nav {
  const n = useContext(NavCtx);
  if (!n) throw new Error('Nav missing');
  return n;
}

/** Store links, filled in after the app is live (replica/deploy.md). Empty = hidden. */
export const STORE_LINKS = {
  ios: '',
  android: '',
};
