#!/usr/bin/env python3
"""Rank review themes from replica/reviews.csv (stand-in for replica-entrepreneur's reviews.py).

Usage: python3 reviews.py replica/reviews.csv --out replica/feedback.md
Rows without a URL are dropped. Low ratings and recent reviews weigh more.
Themes with < 3 reviews or a single source are marked THIN.
"""
import csv, sys, argparse, datetime, re

THEMES = {
    "daily limit / cooldown": r"limit|capped|per day|a day|wait|delay|cooldown|wait screens",
    "ads and upsell pressure": r"\bad\b|ads|bombard|upsell|premium|paywall|freemium",
    "price / subscription": r"price|priced|fee|subscription|ripoff|greed|expensive|one-time|\$",
    "everyone must sign up": r"sign ?up|joining|phone number",
    "settling up is weak / disputes": r"settl|paying each other|amounts owed|disputes|different amounts",
    "split options": r"custom %|50/50|split",
    "no drafts / data loss": r"draft|progress",
    "app ruined (general)": r"ruin|useless|unusable|unfit|horrible|tripe|sink",
}

def weight(row):
    w = 1.0
    try:
        r = int(row["rating"]) if row["rating"] else 2
    except ValueError:
        r = 2
    w *= {1: 3, 2: 2.5, 3: 1.5, 4: 1, 5: 0.5}.get(r, 2)
    if row["date"]:
        try:
            age = (datetime.date.today() - datetime.date.fromisoformat(row["date"])).days
            w *= 1.5 if age < 365 else (1.2 if age < 3 * 365 else 1.0)
        except ValueError:
            pass
    return w

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = [r for r in csv.DictReader(open(a.csv, encoding="utf-8")) if r.get("url")]
    out = [f"# Feedback ranking\n\nSample: {len(rows)} rows with links, "
           f"{len({r['source'] for r in rows})} sources. Generated {datetime.date.today()}.\n"]
    unmatched = []
    scored = []
    for name, pat in THEMES.items():
        hits = [r for r in rows if re.search(pat, r["text"], re.I)]
        if not hits:
            continue
        srcs = {r["source"] for r in hits}
        score = sum(weight(r) for r in hits)
        thin = len(hits) < 3 or len(srcs) < 2
        scored.append((score, name, hits, srcs, thin))
    for r in rows:
        if not any(re.search(p, r["text"], re.I) for p in THEMES.values()):
            unmatched.append(r)
    scored.sort(reverse=True)
    out.append("| rank | theme | score | reviews | sources | note |\n|---|---|---|---|---|---|")
    for i, (s, n, h, src, thin) in enumerate(scored, 1):
        out.append(f"| {i} | {n} | {s:.1f} | {len(h)} | {', '.join(sorted(src))} | {'THIN' if thin else ''} |")
    for s, n, h, src, thin in scored:
        out.append(f"\n## {n}\n")
        for r in h[:6]:
            tag = "" if r["kind"] != "paraphrase" else " _(paraphrase, not a quote)_"
            out.append(f"- {r['rating'] or '?'}★ {r['date'] or 'n.d.'}: \"{r['text']}\"{tag} ([link]({r['url']}))")
    out.append("\n## Unmatched low ratings (read by hand)\n")
    for r in unmatched:
        out.append(f"- {r['rating'] or '?'}★ {r['source']}: \"{r['text']}\" ([link]({r['url']}))")
    open(a.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"{len(rows)} rows, {len(scored)} themes -> {a.out}")

if __name__ == "__main__":
    main()
