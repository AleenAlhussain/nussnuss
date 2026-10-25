// Random groups run through the TypeScript rules. test/parity_test.dart replays them through the Dart port
// and expects identical balances, transfers, totals, formatting and parsing.
//   npm run build:packages && node apps/mobile/tool/parity.mjs > apps/mobile/test/parity.json
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '../../..');
const c = await import(pathToFileURL(join(root, 'packages/core/dist/index.js')).href);
let seed = 42; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const curs = ['AED','KWD','JPY','USD','OMR','IQD'];
const modes = ['equal','exact','percent','shares'];
const cases = [];
const N = Number(process.argv[2] ?? 300);
for (let n = 0; n < N; n++) {
  const ids = Array.from({length: 2 + Math.floor(rnd()*6)}, (_, i) => 'm' + i);
  const gc = curs[Math.floor(rnd()*curs.length)];
  const expenses = Array.from({length: 1 + Math.floor(rnd()*8)}, () => {
    const mode = modes[Math.floor(rnd()*4)];
    const cur = rnd() < 0.3 ? curs[Math.floor(rnd()*curs.length)] : gc;
    const amount = 1 + Math.floor(rnd()*200000);
    const rate = cur === gc ? 1 : Math.round(rnd()*50000)/1000 + 0.001;
    const who = ids.filter(() => rnd() > 0.3); if (!who.length) who.push(ids[0]);
    let items;
    if (mode === 'equal') items = who.map((m) => ({memberId: m, value: 1}));
    else if (mode === 'shares') items = who.map((m) => ({memberId: m, value: 1 + Math.floor(rnd()*4)}));
    else if (mode === 'exact') { const p = c.allocate(amount, who.map(() => 1 + Math.floor(rnd()*9))); items = who.map((m, i) => ({memberId: m, value: p[i]})); }
    else { const p = c.allocate(10000, who.map(() => 1 + Math.floor(rnd()*9))); items = who.map((m, i) => ({memberId: m, value: p[i]})); }
    return {amount, currency: cur, rate, paidBy: ids[Math.floor(rnd()*ids.length)], mode, items};
  });
  const payments = rnd() < 0.5 ? [{from: ids[1], to: ids[0], amount: Math.floor(rnd()*5000)}] : [];
  const g = {currency: gc, members: ids.map((id) => ({id})), expenses, payments};
  const bal = c.computeBalances(g);
  const typed = (s) => [s, c.parseAmountExpression(s, gc), c.parseAmount(s, gc)];
  const inputs = [String(Math.floor(rnd()*1e6)/100), (rnd()*999).toFixed(3) + '+' + (rnd()*99).toFixed(1), '1,' + String(Math.floor(rnd()*999)).padStart(3,'0')];
  cases.push({g, ids, bal, transfers: c.simplifyDebts(bal, ids), total: c.groupTotal(g), fmt: c.formatMoney(bal[ids[0]], gc, 'ar'), parsed: inputs.map(typed)});
}
console.log(JSON.stringify(cases));
