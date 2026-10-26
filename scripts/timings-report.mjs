// Reads the API log (TIMINGS=log) on stdin and prints how long the five main jobs take.
//   node scripts/timings-report.mjs < api.log
// Each timing line holds {"app","version","job","ms","ok"} and nothing about the person.
import { createInterface } from 'node:readline';

const jobs = new Map();
const lines = createInterface({ input: process.stdin });
for await (const line of lines) {
  const at = line.indexOf('{"app"');
  if (at < 0) continue;
  try {
    const t = JSON.parse(line.slice(at));
    if (typeof t.job !== 'string' || typeof t.ms !== 'number') continue;
    const j = jobs.get(t.job) ?? { ok: [], failed: 0, apps: new Set() };
    if (t.ok) j.ok.push(t.ms);
    else j.failed++;
    j.apps.add(t.app);
    jobs.set(t.job, j);
  } catch {
    /* not a timing line */
  }
}

/** The p-th percentile, interpolated (the median of 6.4 s and 9.1 s is 7.75 s). */
const pct = (xs, p) => {
  if (!xs.length) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  const i = (p / 100) * (s.length - 1);
  const lo = Math.floor(i);
  return s[lo] + (s[Math.min(lo + 1, s.length - 1)] - s[lo]) * (i - lo);
};
const sec = (ms) => (Number.isNaN(ms) ? '–' : `${(ms / 1000).toFixed(1)} s`);
const TARGETS = { add_expense: 8000, find_balance: 5000 };

console.log('job            done  failed  median   p90     target');
for (const job of ['add_expense', 'uneven_split', 'settle', 'invite', 'find_balance']) {
  const j = jobs.get(job) ?? { ok: [], failed: 0, apps: new Set() };
  const median = pct(j.ok, 50);
  const target = TARGETS[job];
  const mark = target ? (median <= target ? ' ok' : ' over') : '';
  console.log(`${job.padEnd(14)} ${String(j.ok.length).padStart(4)}  ${String(j.failed).padStart(6)}  ${sec(median).padStart(6)}  ${sec(pct(j.ok, 90)).padStart(6)}  ${target ? sec(target) + mark : ''}`);
}
