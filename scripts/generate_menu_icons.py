#!/usr/bin/env python3
"""Hand-drawn pixel icons for the menu group roots.

A native menu item can only carry a small bitmap next to its attributed title
(no SVG, no recolourable artwork), so the four group roots — 动作 / 对话 / 任务 /
设置 — get 16x16 icons drawn on the same palette PixelStyle uses for the app's
pixel UI. The @2x sheets are nearest-neighbour upscales of the very same pixel
maps, so the icons stay crisp on Retina screens; PetController loads both
representations into one NSImage sized 16x16 points.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "Resources/MenuIcons"
QA = ROOT / "qa"
WIDTH, HEIGHT = 16, 16
RETINA_SCALE = 2
# PixelStyle palette (calibrated RGB, Sources/IsaacPetApp/PixelStyle.swift).
INK = (61, 59, 56, 255)
OUTLINE = (87, 79, 74, 255)
FACE = (222, 217, 212, 255)
PAPER = (237, 232, 230, 255)
ACCENT = (194, 66, 51, 255)

PALETTE = {
    ".": (0, 0, 0, 0),
    "#": INK,
    "o": OUTLINE,
    "f": FACE,
    "p": PAPER,
    "r": ACCENT,
}

# Each icon is a 16-row pixel map, every row exactly 16 characters wide.
ICONS: dict[str, list[str]] = {
    # 动作: raised fist with a brick-red wristband, top corners stepped round.
    "Action": [
        "....########....",
        "..############..",
        "..#f##f##f##f#..",
        "..#ffffffffff#..",
        ".##ffffffffff##.",
        ".#ffffffffffff#.",
        ".#ffffffffffff#.",
        ".#ffffffffffff#.",
        ".#ffffffffffff#.",
        ".#ffffffffffff#.",
        ".#ffffffffffff#.",
        ".#rrrrrrrrrrrr#.",
        ".#ffffffffffff#.",
        ".#ffffffffffff#.",
        "..############..",
        "................",
    ],
    # 对话: speech bubble with a three-dot ellipsis and a bottom-left tail.
    "Chat": [
        "................",
        ".##############.",
        ".#pppppppppppp#.",
        ".#pppppppppppp#.",
        ".#pprrpprrpprr#.",
        ".#pprrpprrpprr#.",
        ".#pppppppppppp#.",
        ".#pppppppppppp#.",
        ".##############.",
        ".##.............",
        "...#............",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    # 任务: sheet of paper with a red check and two gray task lines.
    "Tasks": [
        "....###.........",
        "....###.........",
        "...###########..",
        "...#ppppppppp#..",
        "...#rppppoooo#..",
        "...#prpppoooo#..",
        "...#pprprpppp#..",
        "...#ppprppppp#..",
        "...#pppppoooo#..",
        "...#pppppoooo#..",
        "...#ppppppppp#..",
        "...#ppppppppp#..",
        "...#ppppppppp#..",
        "...#ppppppppp#..",
        "...###########..",
        "................",
    ],
    # 设置: gear with four teeth and an accent hub.
    "Settings": [
        "......####......",
        "......####......",
        "..############..",
        "..############..",
        "..##ffffffff##..",
        "..##ffffffff##..",
        "####ffrrrrff####",
        "####ffrrrrff####",
        "####ffrrrrff####",
        "####ffrrrrff####",
        "..##ffffffff##..",
        "..##ffffffff##..",
        "..############..",
        "..############..",
        "......####......",
        "......####......",
    ],
}


def draw_icon(rows: list[str]) -> Image.Image:
    if len(rows) != HEIGHT or any(len(row) != WIDTH for row in rows):
        raise ValueError(f"icon must be {WIDTH}x{HEIGHT}, got {len(rows)} rows")
    icon = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    pixels = icon.load()
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char not in PALETTE:
                raise ValueError(f"unknown palette char {char!r} in row {y}")
            pixels[x, y] = PALETTE[char]
    return icon


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    icons: dict[str, Image.Image] = {}
    used = set()
    for name, rows in ICONS.items():
        icon = draw_icon(rows)
        icons[name] = icon
        icon.save(OUTPUT_DIR / f"{name}.png")
        retina = icon.resize(
            (WIDTH * RETINA_SCALE, HEIGHT * RETINA_SCALE), Image.Resampling.NEAREST
        )
        retina.save(OUTPUT_DIR / f"{name}@2x.png")
        used |= {color for color in icon.getdata() if color[3]}
        print(f"menu icon written: {OUTPUT_DIR / f'{name}.png'}")

    magnification = 8
    tile = 16 * magnification + 24
    sheet = Image.new(
        "RGBA",
        (tile * len(icons) + 20, tile + 20),
        (35, 35, 42, 255),
    )
    for index, (name, icon) in enumerate(icons.items()):
        big = icon.resize(
            (WIDTH * magnification, HEIGHT * magnification), Image.Resampling.NEAREST
        )
        sheet.alpha_composite(big, (10 + index * tile, 10))
    sheet.convert("RGB").save(QA / "menu-icons-contact-sheet.png")

    report = {
        "output": str(OUTPUT_DIR.relative_to(ROOT)),
        "size": [WIDTH, HEIGHT],
        "icons": sorted(ICONS),
        "palette": sorted(color[:3] for color in used),
        "allowed": sorted(color[:3] for color in PALETTE.values() if color[3]),
        "ok": used <= {color for color in PALETTE.values()},
    }
    (QA / "menu-icons-validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["ok"]:
        raise SystemExit("menu icon validation failed")
    print(f"contact sheet: {QA / 'menu-icons-contact-sheet.png'}")


if __name__ == "__main__":
    main()
