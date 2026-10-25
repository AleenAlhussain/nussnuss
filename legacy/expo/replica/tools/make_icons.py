#!/usr/bin/env python3
"""Draw the NussNuss mark (a coin in two fair halves) into every icon the stores and Expo need.
Usage: python3 replica/tools/make_icons.py   (run from the project root)"""
from PIL import Image, ImageDraw

VIOLET = (79, 59, 214, 255)
SAFFRON = (244, 180, 0, 255)
WHITE = (255, 255, 255, 255)
LIGHT_BG = (247, 246, 251, 255)
SS = 4  # supersampling for smooth edges


def mark(draw, cx, cy, d, left, right, gap_ratio=0.07, drop_ratio=0.08):
    """Two half discs of diameter d centred at (cx, cy); the right half drops a little."""
    r = d / 2
    gap = d * gap_ratio
    drop = d * drop_ratio
    lx = cx - gap / 2
    draw.pieslice([lx - r, cy - r - drop / 2, lx + r, cy + r - drop / 2], 90, 270, fill=left)
    rx = cx + gap / 2
    draw.pieslice([rx - r, cy - r + drop / 2, rx + r, cy + r + drop / 2], 270, 90, fill=right)


def render(size, bg, d_ratio, left, right, rounded=False):
    S = size * SS
    img = Image.new('RGBA', (S, S), bg)
    dr = ImageDraw.Draw(img)
    mark(dr, S / 2, S / 2, S * d_ratio, left, right)
    img = img.resize((size, size), Image.LANCZOS)
    return img


def main():
    out = 'assets/'
    # iOS + generic icon: full-bleed, no transparency (Apple requirement).
    render(1024, VIOLET, 0.58, WHITE, SAFFRON).convert('RGB').save(out + 'icon.png')
    # Android adaptive icon: foreground inside the 66% safe zone, transparent.
    render(1024, (0, 0, 0, 0), 0.40, WHITE, SAFFRON).save(out + 'android-icon-foreground.png')
    Image.new('RGBA', (1024, 1024), VIOLET).save(out + 'android-icon-background.png')
    render(1024, (0, 0, 0, 0), 0.40, WHITE, WHITE).save(out + 'android-icon-monochrome.png')
    # Splash mark on transparent (splash background colour is set in app.json).
    render(1024, (0, 0, 0, 0), 0.62, VIOLET, SAFFRON).save(out + 'splash-icon.png')
    # Web favicon.
    render(196, VIOLET, 0.62, WHITE, SAFFRON).resize((48, 48), Image.LANCZOS).save(out + 'favicon.png')
    # Brand mark for docs / landing page.
    render(512, (0, 0, 0, 0), 0.9, VIOLET, SAFFRON).save(out + 'brand/mark.png')
    render(512, (0, 0, 0, 0), 0.9, WHITE, SAFFRON).save(out + 'brand/mark-on-dark.png')
    print('icons written to assets/')


if __name__ == '__main__':
    main()
