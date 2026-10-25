export type Lang = 'en' | 'ar';
export type SplitMode = 'equal' | 'exact' | 'percent' | 'shares';
export type CategoryId =
  | 'food'
  | 'groceries'
  | 'transport'
  | 'stay'
  | 'fun'
  | 'bills'
  | 'shopping'
  | 'other';

export interface Member {
  id: string;
  name: string;
}

/**
 * value meaning by mode:
 *  equal   – 1 = included, 0 = left out
 *  exact   – amount in minor units of the expense currency
 *  percent – basis points (25% = 2500); all items sum to 10000
 *  shares  – a whole-number weight (2 = twice as much as 1)
 */
export interface SplitItem {
  memberId: string;
  value: number;
}

export interface Expense {
  id: string;
  title: string;
  /** minor units in `currency` */
  amount: number;
  currency: string;
  /** how many group-currency major units one expense-currency major unit is worth */
  rate: number;
  paidBy: string;
  mode: SplitMode;
  items: SplitItem[];
  category: CategoryId;
  /** ISO date-time, UTC */
  date: string;
  createdAt: string;
}

export interface Payment {
  id: string;
  from: string;
  to: string;
  /** minor units in the group currency */
  amount: number;
  date: string;
}

export interface Group {
  id: string;
  name: string;
  emoji: string;
  currency: string;
  members: Member[];
  expenses: Expense[];
  payments: Payment[];
  createdAt: string;
  updatedAt: string;
}

export interface Transfer {
  from: string;
  to: string;
  amount: number;
}

export type ThemePref = 'system' | 'light' | 'dark';

export interface Settings {
  lang: Lang;
  name: string;
  theme: ThemePref;
  accent: string;
  plus: boolean;
  onboarded: boolean;
}

export interface ExpenseDraft {
  groupId: string;
  title: string;
  amountText: string;
  currency: string;
  rateText: string;
  paidBy: string;
  mode: SplitMode;
  values: Record<string, string>;
  included: Record<string, boolean>;
  category: CategoryId;
}
