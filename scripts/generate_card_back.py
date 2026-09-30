#!/usr/bin/env python3
"""Derive the upright tarot card back from the wiki's diagonal back sprite.

The game draws card backs tilted 45 degrees inside a 32x32 canvas; the pet's
card panels show cards upright (14x18, matching the front faces cropped from
Cards_sprite.png). This script re-lays the diagonal back upright using its own
sampled palette and motifs: dark outline, gold rim, deep red field, two center
diamonds and corner dots — no new colours are invented.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Assets/Source/tarot/card-back-diagonal.png"
OUTPUT = ROOT / "Resources/Cards/CardBack.png"
QA = ROOT / "qa"
WIDTH, HEIGHT = 14, 18
# Sampled from Assets/Source/tarot/card-back-diagonal.png (opaque pixels).
OUTLINE = (8, 0, 0, 255)
GOLD = (123, 93, 47, 255)
BRONZE = (118, 75, 51, 255)
RED = (115, 60, 55, 255)


def draw_back() -> Image.Image:
    back = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    pixels = back.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            edge = x in (0, WIDTH - 1) or y in (0, HEIGHT - 1)
            rim = x in (1, WIDTH - 2) or y in (1, HEIGHT - 2)
            if edge:
                pixels[x, y] = OUTLINE
            elif rim:
                pixels[x, y] = GOLD
            elif y == HEIGHT - 3:
                pixels[x, y] = BRONZE
            else:
                pixels[x, y] = RED

    draw = ImageDraw.Draw(back)
    # Two diamonds stacked along the card's long axis, echoing the source's
    # paired ornaments, plus a gold dot in each inner corner.
    for center_y in (6, 12):
        draw.point((6, center_y - 1) + (7, center_y - 1), fill=GOLD)
        draw.point(((5, center_y), (6, center_y), (7, center_y), (8, center_y)), fill=GOLD)
        draw.point((6, center_y + 1) + (7, center_y + 1), fill=GOLD)
    for x, y in ((3, 3), (10, 3), (3, 14), (10, 14)):
        draw.point((x, y), fill=GOLD)
    return back


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    back = draw_back()
    back.save(OUTPUT)

    QA.mkdir(parents=True, exist_ok=True)
    magnification = 8
    source_big = source.resize((source.width * 4, source.height * 4), Image.Resampling.NEAREST)
    big = back.resize((WIDTH * magnification, HEIGHT * magnification), Image.Resampling.NEAREST)
    sheet = Image.new(
        "RGBA",
        (source_big.width + big.width + 210, big.height + 30),
        (35, 35, 42, 255),
    )
    sheet.alpha_composite(source_big, (20, 15))
    sheet.alpha_composite(big, (source_big.width + 80, 15))
    sheet.convert("RGB").save(QA / "card-back-contact-sheet.png")

    opaque = {color for color in back.getdata() if color[3]}
    report = {
        "source": str(SOURCE.relative_to(ROOT)),
        "output": str(OUTPUT.relative_to(ROOT)),
        "size": [WIDTH, HEIGHT],
        "palette": sorted(color[:3] for color in opaque),
        "allowed": sorted(color[:3] for color in (OUTLINE, GOLD, BRONZE, RED)),
        "ok": opaque <= {OUTLINE, GOLD, BRONZE, RED},
    }
    (QA / "card-back-validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["ok"]:
        raise SystemExit("card back validation failed")
    print(f"card back written: {OUTPUT}")


if __name__ == "__main__":
    main()
