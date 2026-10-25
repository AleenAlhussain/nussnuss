import type { Lang } from './types.js';

export interface CurrencyInfo {
  code: string;
  decimals: number;
  en: string;
  ar: string;
  /** symbol shown in Arabic UI; English UI shows the ISO code */
  arSymbol?: string;
}

// Decimals follow ISO 4217, except IQD/LBP/SYP/IDR where nobody uses the minor unit.
export const CURRENCIES: CurrencyInfo[] = [
  { code: 'AED', decimals: 2, en: 'UAE dirham', ar: 'درهم إماراتي', arSymbol: 'د.إ' },
  { code: 'SAR', decimals: 2, en: 'Saudi riyal', ar: 'ريال سعودي', arSymbol: 'ر.س' },
  { code: 'KWD', decimals: 3, en: 'Kuwaiti dinar', ar: 'دينار كويتي', arSymbol: 'د.ك' },
  { code: 'QAR', decimals: 2, en: 'Qatari riyal', ar: 'ريال قطري', arSymbol: 'ر.ق' },
  { code: 'BHD', decimals: 3, en: 'Bahraini dinar', ar: 'دينار بحريني', arSymbol: 'د.ب' },
  { code: 'OMR', decimals: 3, en: 'Omani rial', ar: 'ريال عماني', arSymbol: 'ر.ع' },
  { code: 'EGP', decimals: 2, en: 'Egyptian pound', ar: 'جنيه مصري', arSymbol: 'ج.م' },
  { code: 'JOD', decimals: 3, en: 'Jordanian dinar', ar: 'دينار أردني', arSymbol: 'د.أ' },
  { code: 'LBP', decimals: 0, en: 'Lebanese pound', ar: 'ليرة لبنانية', arSymbol: 'ل.ل' },
  { code: 'IQD', decimals: 0, en: 'Iraqi dinar', ar: 'دينار عراقي', arSymbol: 'د.ع' },
  { code: 'SYP', decimals: 0, en: 'Syrian pound', ar: 'ليرة سورية', arSymbol: 'ل.س' },
  { code: 'MAD', decimals: 2, en: 'Moroccan dirham', ar: 'درهم مغربي', arSymbol: 'د.م' },
  { code: 'TND', decimals: 3, en: 'Tunisian dinar', ar: 'دينار تونسي', arSymbol: 'د.ت' },
  { code: 'DZD', decimals: 2, en: 'Algerian dinar', ar: 'دينار جزائري', arSymbol: 'د.ج' },
  { code: 'LYD', decimals: 3, en: 'Libyan dinar', ar: 'دينار ليبي', arSymbol: 'د.ل' },
  { code: 'SDG', decimals: 2, en: 'Sudanese pound', ar: 'جنيه سوداني', arSymbol: 'ج.س' },
  { code: 'YER', decimals: 2, en: 'Yemeni rial', ar: 'ريال يمني', arSymbol: 'ر.ي' },
  { code: 'USD', decimals: 2, en: 'US dollar', ar: 'دولار أمريكي', arSymbol: '$' },
  { code: 'EUR', decimals: 2, en: 'Euro', ar: 'يورو', arSymbol: '€' },
  { code: 'GBP', decimals: 2, en: 'British pound', ar: 'جنيه إسترليني', arSymbol: '£' },
  { code: 'TRY', decimals: 2, en: 'Turkish lira', ar: 'ليرة تركية' },
  { code: 'INR', decimals: 2, en: 'Indian rupee', ar: 'روبية هندية' },
  { code: 'PKR', decimals: 2, en: 'Pakistani rupee', ar: 'روبية باكستانية' },
  { code: 'IDR', decimals: 0, en: 'Indonesian rupiah', ar: 'روبية إندونيسية' },
  { code: 'MYR', decimals: 2, en: 'Malaysian ringgit', ar: 'رينغيت ماليزي' },
  { code: 'SGD', decimals: 2, en: 'Singapore dollar', ar: 'دولار سنغافوري' },
  { code: 'THB', decimals: 2, en: 'Thai baht', ar: 'بات تايلندي' },
  { code: 'PHP', decimals: 2, en: 'Philippine peso', ar: 'بيزو فلبيني' },
  { code: 'JPY', decimals: 0, en: 'Japanese yen', ar: 'ين ياباني' },
  { code: 'KRW', decimals: 0, en: 'South Korean won', ar: 'وون كوري' },
  { code: 'CNY', decimals: 2, en: 'Chinese yuan', ar: 'يوان صيني' },
  { code: 'CAD', decimals: 2, en: 'Canadian dollar', ar: 'دولار كندي' },
  { code: 'AUD', decimals: 2, en: 'Australian dollar', ar: 'دولار أسترالي' },
  { code: 'CHF', decimals: 2, en: 'Swiss franc', ar: 'فرنك سويسري' },
  { code: 'SEK', decimals: 2, en: 'Swedish krona', ar: 'كرونة سويدية' },
  { code: 'NOK', decimals: 2, en: 'Norwegian krone', ar: 'كرونة نرويجية' },
  { code: 'DKK', decimals: 2, en: 'Danish krone', ar: 'كرونة دنماركية' },
  { code: 'BRL', decimals: 2, en: 'Brazilian real', ar: 'ريال برازيلي' },
  { code: 'MXN', decimals: 2, en: 'Mexican peso', ar: 'بيزو مكسيكي' },
  { code: 'ZAR', decimals: 2, en: 'South African rand', ar: 'راند جنوب أفريقي' },
  { code: 'NGN', decimals: 2, en: 'Nigerian naira', ar: 'نايرا نيجيرية' },
];

const BY_CODE: Record<string, CurrencyInfo> = Object.fromEntries(CURRENCIES.map((c) => [c.code, c]));

export function currency(code: string): CurrencyInfo {
  return BY_CODE[code] ?? { code, decimals: 2, en: code, ar: code };
}

export function decimalsOf(code: string): number {
  return currency(code).decimals;
}

function groupThousands(intPart: string): string {
  return intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** 4550 AED -> "45.50"; never uses floating point for the digits. */
export function formatNumber(minor: number, code: string): string {
  const d = decimalsOf(code);
  const neg = minor < 0;
  const abs = Math.abs(Math.round(minor));
  const s = String(abs).padStart(d + 1, '0');
  const intPart = d ? s.slice(0, -d) : s;
  const frac = d ? s.slice(-d) : '';
  return (neg ? '-' : '') + groupThousands(intPart) + (d ? '.' + frac : '');
}

/** "AED 45.50" in English, "45.50 د.إ" in Arabic. */
export function formatMoney(minor: number, code: string, lang: Lang): string {
  const n = formatNumber(minor, code);
  if (lang === 'ar') {
    const sym = currency(code).arSymbol ?? code;
    return `${n} ${sym}`;
  }
  return `${code} ${n}`;
}

const ARABIC_INDIC = '٠١٢٣٤٥٦٧٨٩';
const PERSIAN = '۰۱۲۳۴۵۶۷۸۹';

/** Turn Arabic-Indic / Persian digits and separators into plain ASCII. */
export function normalizeDigits(input: string): string {
  let out = '';
  for (const ch of input) {
    const a = ARABIC_INDIC.indexOf(ch);
    const p = PERSIAN.indexOf(ch);
    if (a >= 0) out += String(a);
    else if (p >= 0) out += String(p);
    else if (ch === '٫') out += '.';
    else if (ch === '٬') out += ',';
    else out += ch;
  }
  return out;
}

/**
 * Parse what a person typed into minor units. Accepts "45", "45.5", "45,50", "1,250.75",
 * "٤٥٫٥". Returns null if it is not a positive amount with at most `decimals` places.
 */
export function parseAmount(input: string, code: string): number | null {
  const d = decimalsOf(code);
  let s = normalizeDigits(input).trim().replace(/\s/g, '');
  if (!s) return null;
  // A single comma followed by 1..3 digits at the end, with no dot, is a decimal comma.
  if (!s.includes('.') && /^\d+,\d{1,3}$/.test(s) && !/^\d{1,3},\d{3}$/.test(s)) {
    s = s.replace(',', '.');
  }
  s = s.replace(/,/g, '');
  if (!/^\d+(\.\d*)?$/.test(s) && !/^\.\d+$/.test(s)) return null;
  const [i, f = ''] = s.split('.');
  if (f.length > d) return null;
  const minor = Number(i || '0') * 10 ** d + Number((f + '0'.repeat(d)).slice(0, d) || '0');
  if (!Number.isFinite(minor) || minor <= 0 || minor > 9e14) return null;
  return minor;
}

/** minor units -> plain editable string, e.g. 4550 AED -> "45.50" */
export function minorToInput(minor: number, code: string): string {
  return formatNumber(minor, code).replace(/,/g, '');
}

/** Convert minor units between currencies using a major-unit rate. */
export function convertMinor(minor: number, fromCode: string, toCode: string, rate: number): number {
  if (fromCode === toCode) return minor;
  const shift = decimalsOf(toCode) - decimalsOf(fromCode);
  return Math.round(minor * rate * 10 ** shift);
}

/**
 * Amount keypad input with simple sums: "12 + 8.5", "100 - 15", "٤٥ + ٥".
 * Returns minor units, or null when any term is invalid or the total is not positive.
 * No eval: terms are parsed one by one with parseAmount's rules.
 */
export function parseAmountExpression(input: string, code: string): number | null {
  const s = normalizeDigits(input).replace(/[−–]/g, '-').replace(/\s+/g, '');
  if (!s) return null;
  if (!/^[0-9.,]+([+-][0-9.,]+)*$/.test(s)) return null;
  const terms = s.match(/[+-]?[0-9.,]+/g) ?? [];
  let total = 0;
  for (const t of terms) {
    const sign = t.startsWith('-') ? -1 : 1;
    const v = parseAmount(t.replace(/^[+-]/, ''), code);
    if (v === null) return null;
    total += sign * v;
  }
  return total > 0 ? total : null;
}
