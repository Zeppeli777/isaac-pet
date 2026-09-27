#!/usr/bin/env python3
"""Derive the card-drawing "raise" helper atlases from the approved thumbsUp row.

抽卡动作 = 手臂上举展示卡牌。It reuses the approved thumbsUp motion (the only
upward arm raise in the source atlas) as its pixels and only re-times it: the
raised frames repeat so Isaac holds the card up before lowering the arm. Like
the shooting and vertical-walking helpers this is a deterministic derivation of
existing source art per role, not new art.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "qa"
CELL_WIDTH = 192
CELL_HEIGHT = 208
SOURCE_ROW = 7  # thumbsUp
SOURCE_FRAMES = 6
# down, rising, raised, hold x3, raised variant, lowering
RAISE_SEQUENCE = (0, 1, 2, 3, 3, 3, 4, 5)
ROLES = {
    "Resources/spritesheet.webp": "Resources/raising-atlas.webp",
    "Resources/Agents/magdalene-spritesheet.webp": "Resources/Agents/magdalene-raising-atlas.webp",
}


def frame(atlas: Image.Image, column: int) -> Image.Image:
    left = column * CELL_WIDTH
    top = SOURCE_ROW * CELL_HEIGHT
    return atlas.crop((left, top, left + CELL_WIDTH, top + CELL_HEIGHT))


def derive(source_path: Path, output_path: Path) -> list[Image.Image]:
    atlas = Image.open(source_path).convert("RGBA")
    sources = [frame(atlas, column) for column in range(SOURCE_FRAMES)]
    for column, cell in enumerate(sources):
        if not cell.getbbox():
            raise SystemExit(f"{source_path}: thumbsUp frame {column} is empty")

    raising = Image.new("RGBA", (CELL_WIDTH * len(RAISE_SEQUENCE), CELL_HEIGHT), (0, 0, 0, 0))
    cells = []
    for column, source_column in enumerate(RAISE_SEQUENCE):
        cell = sources[source_column]
        cells.append(cell)
        raising.alpha_composite(cell, (column * CELL_WIDTH, 0))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    raising.save(output_path, lossless=True, quality=100, exact=True)
    return cells


def contact_sheet(assets: dict[str, list[Image.Image]]) -> None:
    QA.mkdir(parents=True, exist_ok=True)
    roles = list(assets)
    sheet = Image.new(
        "RGBA",
        (CELL_WIDTH * len(RAISE_SEQUENCE), CELL_HEIGHT * len(roles)),
        (35, 35, 42, 255),
    )
    from PIL import ImageDraw

    draw = ImageDraw.Draw(sheet)
    for row_index, (name, cells) in enumerate(assets.items()):
        y = row_index * CELL_HEIGHT
        for column, cell in enumerate(cells):
            sheet.alpha_composite(cell, (column * CELL_WIDTH, y))
        draw.text((6, y + 6), f"{name} row {SOURCE_ROW} -> raise {RAISE_SEQUENCE}", fill=(255, 255, 255, 255))
    sheet.save(QA / "raising-atlas-contact-sheet.png")


def main() -> None:
    assets: dict[str, list[Image.Image]] = {}
    report = {
        "sourceRow": SOURCE_ROW,
        "sequence": list(RAISE_SEQUENCE),
        "cell": [CELL_WIDTH, CELL_HEIGHT],
        "roles": [],
    }
    for source_name, output_name in ROLES.items():
        source_path = ROOT / source_name
        output_path = ROOT / output_name
        cells = derive(source_path, output_path)
        assets[source_path.name] = cells
        saved = Image.open(output_path).convert("RGBA")
        role_report = {
            "source": source_name,
            "output": output_name,
            "size": list(saved.size),
            "cells": [
                {
                    "index": index,
                    "sourceColumn": RAISE_SEQUENCE[index],
                    "bbox": list(cell.getbbox() or (0, 0, 0, 0)),
                    "matches_source_frame": cell.tobytes() == frame(
                        Image.open(source_path).convert("RGBA"), RAISE_SEQUENCE[index]
                    ).tobytes(),
                }
                for index, cell in enumerate(cells)
            ],
        }
        role_report["ok"] = (
            saved.size == (CELL_WIDTH * len(RAISE_SEQUENCE), CELL_HEIGHT)
            and all(item["matches_source_frame"] and item["bbox"] != [0, 0, 0, 0] for item in role_report["cells"])
        )
        report["roles"].append(role_report)

    report["ok"] = all(role["ok"] for role in report["roles"])
    contact_sheet(assets)
    (QA / "raising-atlas-validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["ok"]:
        raise SystemExit("raising atlas validation failed")
    print(f"raising atlases derived: {list(ROLES.values())}")


if __name__ == "__main__":
    main()
