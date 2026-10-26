// One glossary for every screen: the same words on the web, iPhone and Android, in English and Arabic.
// Checks apps/web/lib/i18n.ts (the one source both apps use) against the glossary below, and scans the
// web and Flutter code for words typed in by hand instead of taken from the strings. Exit 1 on a breach.
//   node scripts/glossary.mjs
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import ts from 'typescript';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const src = readFileSync(join(root, 'apps/web/lib/i18n.ts'), 'utf8').replace(/^const (en|ar)\b/gm, 'export const $1');
const js = ts.transpileModule(src, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const tmp = mkdtempSync(join(tmpdir(), 'nn-glossary-'));
writeFileSync(join(tmp, 'i18n.mjs'), js);
const { en, ar } = await import(pathToFileURL(join(tmp, 'i18n.mjs')).href);
rmSync(tmp, { recursive: true, force: true });

/** The words of the product. Each has one form in each language. */
const TERMS = {
  tabHome: ['Home', 'الرئيسية'],
  tabActivity: ['Activity', 'النشاط'],
  tabYou: ['You', 'أنت'],
  settleUp: ['Settle up', 'التسوية'],
  markPaid: ['Mark as paid', 'تم الدفع'],
  youAreOwed: ['You get back', 'لك'],
  youOwe: ['You owe', 'عليك'],
  look_default: ['Default', 'الافتراضي'],
  glass_tinted: ['Tinted', 'ملوّن'],
  glass_solid: ['Solid', 'صلب'],
  plus: ['NussNuss Plus', null],
};

/** Variants that drift in over time, and the glossary word to use instead. */
const BANNED = [
  [/\bSettle Up\b/, 'Settle up'],
  [/\bMark paid\b/i, 'Mark as paid'],
  [/\bpay ?back\b/i, 'get back'],
  [/\bdebts?\b/i, 'owes / you owe'],
  [/\bIOU\b/, 'owes'],
  [/\bViolet look\b/i, 'Default look'],
  [/\b(Groups|Settings) tab\b/, 'Home / You tab'],
];

let errors = 0;
const fail = (msg) => {
  errors++;
  console.log(`  FAIL ${msg}`);
};

console.log('Glossary terms');
for (const [key, [e, a]] of Object.entries(TERMS)) {
  if (en[key] !== e) fail(`${key}: English is "${en[key]}", the glossary says "${e}"`);
  if (a && ar[key] !== a) fail(`${key}: Arabic is "${ar[key]}", the glossary says "${a}"`);
}

console.log('Words to avoid in the strings');
for (const [key, value] of Object.entries(en)) {
  for (const [re, use] of BANNED) if (re.test(value)) fail(`${key}: "${value}" — use "${use}"`);
}

console.log('Words typed in by hand in the code');
const walk = (dir, ext, out = []) => {
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, ext, out);
    else if (ext.some((x) => name.endsWith(x)) && !name.endsWith('.g.dart')) out.push(p);
  }
  return out;
};
const code = [...walk(join(root, 'apps/web/app'), ['.tsx']), ...walk(join(root, 'apps/web/components'), ['.tsx']), ...walk(join(root, 'apps/mobile/lib'), ['.dart'])];
/** What people can read: string literals and JSX text, not comments or names in the code. */
const shown = (text) => [
  ...[...text.matchAll(/'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"/g)].map((m) => m[0]),
  ...[...text.matchAll(/>([^<>{}\n]*[A-Za-z][^<>{}\n]*)</g)].map((m) => m[1]),
];
for (const file of code) {
  const text = readFileSync(file, 'utf8').replace(/^\s*(\/\/|\*|\/\*).*$/gm, '');
  for (const lit of shown(text)) {
    for (const [re, use] of BANNED) {
      const m = lit.match(re);
      if (m) fail(`${relative(root, file)}: "${m[0]}" — use "${use}"`);
    }
  }
  // Flutter: Text('Settings') and the like should come from the strings.
  for (const m of text.matchAll(/\bText\(\s*'([A-Z][a-z]+(?: [a-z]+){0,4})'/g)) {
    if (!['NussNuss'].includes(m[1])) fail(`${relative(root, file)}: Text('${m[1]}') — take it from the strings (S.of(context))`);
  }
}

console.log(errors ? `\n${errors} glossary problem(s)` : '\nGlossary OK');
process.exit(errors ? 1 : 0);
