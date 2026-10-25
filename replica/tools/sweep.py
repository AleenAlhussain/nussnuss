#!/usr/bin/env python3
"""Find leftovers of other brands in the codebase (stand-in for replica-brand's sweep.py).
Usage: python3 sweep.py . --config replica/brand.json   -> exit 1 if anything is found."""
import json, os, re, sys, argparse

SKIP = {"node_modules", ".git", "dist", "build", ".expo", "replica", "web-build", "test-results",
        "playwright-report", "ios", "android"}
EXT = {".ts", ".tsx", ".js", ".jsx", ".json", ".html", ".css", ".md", ".svg", ".txt", ".yml", ".yaml"}

ap = argparse.ArgumentParser()
ap.add_argument("root")
ap.add_argument("--config")
a = ap.parse_args()
cfg = json.load(open(a.config)) if a.config else {}
terms = cfg.get("avoid", []) + cfg.get("domains", []) + cfg.get("colors", [])
pat = re.compile("|".join(re.escape(t.replace(" ", "")) + "|" + re.escape(t) for t in terms), re.I)
hits = 0
for d, dirs, files in os.walk(a.root):
    dirs[:] = [x for x in dirs if x not in SKIP]
    for f in files:
        p = os.path.join(d, f)
        if pat.search(f):
            print(f"name: {p}"); hits += 1
        if os.path.splitext(f)[1].lower() not in EXT:
            continue
        try:
            for i, line in enumerate(open(p, encoding="utf-8", errors="ignore"), 1):
                m = pat.search(line)
                if m:
                    print(f"{p}:{i}: {m.group(0)}"); hits += 1
        except OSError:
            pass
print("clean" if not hits else f"{hits} leftover(s)")
sys.exit(1 if hits else 0)
