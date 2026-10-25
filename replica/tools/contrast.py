#!/usr/bin/env python3
"""WCAG contrast check for tokens.json (stand-in for replica-design's contrast.py).
body pairs need 4.5:1, ui pairs (borders, focus rings, large text) need 3:1. Exit 1 on failure."""
import json, sys

def lum(hexc):
    h = hexc.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

t = json.load(open(sys.argv[1]))
fails = 0
sets = [(m, c) for m, c in t["color"].items()]
for name, over in t.get("accents", {}).items():
    for m in over:
        sets.append((f"{m}+{name}", {**t["color"][m], **over[m]}))
for mode, colors in sets:
    print(f"\n[{mode}]")
    for fg, bg, kind in t["pairs"]:
        r = ratio(colors[fg], colors[bg])
        need = 4.5 if kind == "body" else 3.0
        ok = r >= need
        fails += not ok
        print(f"  {'OK  ' if ok else 'FAIL'} {fg:>13} on {bg:<12} {r:5.2f}:1 (need {need})")
print(f"\n{fails} failure(s)")
sys.exit(1 if fails else 0)
