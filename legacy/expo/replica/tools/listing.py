#!/usr/bin/env python3
"""Lint replica/launch/listing.json against store limits (stand-in for replica-launch's listing.py).
App Store: name 30, subtitle 30, promotional 170, keywords 100 (bytes, comma-separated, no spaces
needed), description 4000. Google Play: title 30, short 80, full 4000.
Flags emoji and ranking/price claims in short fields, repeated keywords, words in keywords that are
already in the name, and any `avoid` name anywhere. Exit 1 on an error."""
import json, re, sys, unicodedata

d = json.load(open(sys.argv[1], encoding="utf-8"))
avoid = [a.lower() for a in d.get("avoid", [])]
errors, warns = [], []

def resolve(v):
    if isinstance(v, str) and v.startswith("@"):
        cur = d
        for k in v[1:].split("."):
            cur = cur[k]
        return cur
    return v

def count(s):
    return len(unicodedata.normalize("NFC", s))

EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿]")
CLAIMS = re.compile(r"\b(#1|best|top|number one|free!|cheapest|\d+% off)\b", re.I)

def check(store, loc, field, value, limit, short=False):
    value = resolve(value)
    n = count(value)
    tag = f"{store}/{loc}/{field}"
    if n > limit:
        errors.append(f"{tag}: {n} > {limit} chars")
    if short and EMOJI.search(value):
        errors.append(f"{tag}: emoji in a short field")
    if short and CLAIMS.search(value):
        warns.append(f"{tag}: ranking/price claim '{CLAIMS.search(value).group(0)}'")
    for a in avoid:
        if a in value.lower():
            errors.append(f"{tag}: mentions '{a}'")
    print(f"  {'OK ' if n <= limit else 'ERR'} {tag:<40} {n:>4}/{limit}")

for loc, v in d["appstore"].items():
    check("appstore", loc, "name", v["name"], 30, True)
    check("appstore", loc, "subtitle", v["subtitle"], 30, True)
    check("appstore", loc, "promotional_text", v["promotional_text"], 170)
    check("appstore", loc, "description", v["description"], 4000)
    kw = v["keywords"]
    nb = len(kw.encode("utf-8"))
    print(f"  {'OK ' if nb <= 100 else 'ERR'} appstore/{loc}/keywords (bytes)            {nb:>4}/100")
    if nb > 100:
        errors.append(f"appstore/{loc}/keywords: {nb} bytes > 100")
    words = [w.strip().lower() for w in kw.split(",")]
    if len(set(words)) != len(words):
        warns.append(f"appstore/{loc}/keywords: repeated words")
    if ", " in kw:
        warns.append(f"appstore/{loc}/keywords: spaces after commas waste characters")
    in_name = [w for w in words if w in (v["name"] + " " + v["subtitle"]).lower()]
    if in_name:
        warns.append(f"appstore/{loc}/keywords: already in name/subtitle: {', '.join(in_name)}")
    for a in avoid:
        if a in kw.lower():
            errors.append(f"appstore/{loc}/keywords: mentions '{a}'")
for loc, v in d["googleplay"].items():
    check("googleplay", loc, "title", v["title"], 30, True)
    check("googleplay", loc, "short_description", v["short_description"], 80, True)
    check("googleplay", loc, "full_description", v["full_description"], 4000)
for w in warns:
    print("WARN", w)
for e in errors:
    print("ERROR", e)
print("listing OK" if not errors else f"{len(errors)} error(s)")
sys.exit(1 if errors else 0)
