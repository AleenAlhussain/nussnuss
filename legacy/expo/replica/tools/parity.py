#!/usr/bin/env python3
"""Feature parity score (stand-in for replica-diff's parity.py).
Weights: must 3, should 2, could 1; partial = half; skip rows and our own additions are left out
of the parity score and reported separately. Usage: python3 parity.py replica/features.csv [--markdown]"""
import csv, sys
from collections import defaultdict

W = {"must": 3, "should": 2, "could": 1}
V = {"yes": 1.0, "partial": 0.5, "no": 0.0}
rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
md = "--markdown" in sys.argv
par = [r for r in rows if r["original"] == "yes" and r["clone"] != "skip"]
ours = [r for r in rows if r["original"] == "no"]
skip = [r for r in rows if r["clone"] == "skip"]
tot = sum(W[r["priority"]] for r in par)
got = sum(W[r["priority"]] * V[r["clone"]] for r in par)
must = [r for r in par if r["priority"] == "must"]
must_done = sum(1 for r in must if r["clone"] == "yes")
area = defaultdict(lambda: [0, 0])
for r in par:
    area[r["area"]][0] += W[r["priority"]] * V[r["clone"]]
    area[r["area"]][1] += W[r["priority"]]
missing = [r for r in par if r["clone"] != "yes"]
missing.sort(key=lambda r: -W[r["priority"]])
fix_done = sum(1 for r in ours if r["clone"] == "yes")
out = []
out.append(f"Feature parity: {100*got/tot:.0f}% ({got:g}/{tot} weighted)")
out.append(f"Must-haves: {must_done}/{len(must)} done")
out.append(f"Our fixes and additions: {fix_done}/{len(ours)} done")
out.append(f"Skipped on purpose: {len(skip)} ({', '.join(r['feature'] for r in skip)})")
out.append("By area (weakest first): " + ", ".join(f"{a} {100*v/t:.0f}%" for a, (v, t) in sorted(area.items(), key=lambda x: x[1][0]/x[1][1])))
out.append("Missing / partial: " + ("; ".join(f"{r['feature']} ({r['clone']})" for r in missing) or "none"))
verdict = "not shippable" if must_done < len(must) else ("better than the original" if fix_done == len(ours) and 100*got/tot >= 80 else "shippable")
out.append(f"Verdict: {verdict}")
print("\n".join(("- " + l if md else l) for l in out))
sys.exit(0 if must_done == len(must) else 1)
