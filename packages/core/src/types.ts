export type Lang = 'en' | 'ar';
export type SplitMode = 'equal' | 'exact' | 'percent' | 'shares';
export type CategoryId = 'food' | 'groceries' | 'transport' | 'stay' | 'fun' | 'bills' | 'shopping' | 'other';

export const SPLIT_MODES: readonly SplitMode[] = ['equal', 'exact', 'percent', 'shares'] as const;
export const CATEGORIES: readonly CategoryId[] = ['food', 'groceries', 'transport', 'stay', 'fun', 'bills', 'shopping', 'other'] as const;

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

/** The parts of an expense the money rules need. */
export interface ExpenseLike {
  /** minor units in `currency` */
  amount: number;
  currency: string;
  /** group-currency major units per one expense-currency major unit */
  rate: number;
  paidBy: string;
  mode: SplitMode;
  items: SplitItem[];
}

export interface PaymentLike {
  from: string;
  to: string;
  /** minor units in the group currency */
  amount: number;
}

export interface GroupLike {
  currency: string;
  members: { id: string }[];
  expenses: ExpenseLike[];
  payments: PaymentLike[];
}

export interface Transfer {
  from: string;
  to: string;
  amount: number;
}
