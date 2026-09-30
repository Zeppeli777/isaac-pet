#!/usr/bin/env python3
"""Derive the card-drawing "raise" helper atlases from the approved thumbsUp row.

抽卡动作 = 双手向上举起卡牌。The pixels come from the approved thumbsUp motion
(the only upward arm raise in the source atlas) and are only re-timed and
mirrored: the raised arm from the fully-lifted frame is mirrored about the
character's symmetry axis and tucked behind the body, giving a both-arms-up
pose without inventing new pixels. Like the shooting and vertical-walking
helpers this is a deterministic derivation of existing source art per role.
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
# idle, arm rising, one arm up — then the mirrored both-arms pose (held during
# the spin) is appended as the fourth column.
RAISE_SEQUENCE = (0, 1, 2)
ROLES = {
    "Resources/spritesheet.webp": "Resources/raising-atlas.webp",
    "Resources/Agents/magdalene-spritesheet.webp": "Resources/Agents/magdalene-raising-atlas.webp",
}
# The raised arm lives in this strip of the fully-lifted frame (frame 3);
# everything left of it is face/body and must not leak into the mirror.
ARM_STRIP = (112, 166, 46, 146)  # (x0, x1, y0, y1)
# Mirror axis of the shared face art, located by scanning the Isaac head band
# (score 0.986) and verified on the QA contact sheet. Both roles reuse the same
# face registration, so one axis serves both; automatic detection is unreliable
# under Magdalene's asymmetric hair.
SYMMETRY_AXES = {
    "Resources/spritesheet.webp": 83.5,
    "Resources/Agents/magdalene-spritesheet.webp": 83.5,
}


def strip_box() -> tuple[int, int, int, int]:
    return (ARM_STRIP[0], ARM_STRIP[2], ARM_STRIP[1], ARM_STRIP[3])


def frame(atlas: Image.Image, column: int) -> Image.Image:
    left = column * CELL_WIDTH
    top = SOURCE_ROW * CELL_HEIGHT
    return atlas.crop((left, top, left + CELL_WIDTH, top + CELL_HEIGHT))


def both_arms_frame(
    lifted: Image.Image, base_lifted: Image.Image, axis: float
) -> Image.Image:
    """Add a mirrored copy of the raised arm on the other side of the head.

    The arm pixels always come from the base (Isaac) sheet: role hair overlays
    reach into the arm strip and must not be duplicated onto the other side.
    The role's own frame composites on top, so the mirrored arm only shows
    where the body is transparent — the arm reads as tucked behind the head.
    """
    strip = base_lifted.crop(strip_box())
    strip_pixels = strip.load()
    composite = lifted.copy()
    for y in range(strip.height):
        for x in range(strip.width):
            pixel = strip_pixels[x, y]
            if pixel[3] == 0:
                continue
            source_x = ARM_STRIP[0] + x
            target_x = int(round(2 * axis - source_x))
            if 0 <= target_x < CELL_WIDTH:
                composite.putpixel((target_x, ARM_STRIP[2] + y), pixel)
    composite.alpha_composite(lifted)
    return composite


def connected_components(image: Image.Image) -> int:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    seen: set[tuple[int, int]] = set()
    components = 0
    for y in range(image.height):
        for x in range(image.width):
            if pixels[x, y] == 0 or (x, y) in seen:
                continue
            components += 1
            stack = [(x, y)]
            seen.add((x, y))
            while stack:
                px, py = stack.pop()
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < image.width and 0 <= ny < image.height:
                        if pixels[nx, ny] and (nx, ny) not in seen:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
    return components


def derive(source_path: Path, output_path: Path) -> list[Image.Image]:
    atlas = Image.open(source_path).convert("RGBA")
    sources = [frame(atlas, column) for column in range(SOURCE_FRAMES)]
    base_atlas = Image.open(ROOT / "Resources/spritesheet.webp").convert("RGBA")
    base_sources = [frame(base_atlas, column) for column in range(SOURCE_FRAMES)]
    for column, cell in enumerate(sources):
        if not cell.getbbox():
            raise SystemExit(f"{source_path}: thumbsUp frame {column} is empty")

    both_arms = both_arms_frame(sources[3], base_sources[3], SYMMETRY_AXES[str(source_path.relative_to(ROOT))])
    if connected_components(both_arms) != connected_components(sources[3]):
        raise SystemExit(f"{source_path}: mirrored arm introduced stray pixels")

    derived: list[Image.Image | None] = [
        sources[column] for column in RAISE_SEQUENCE
    ] + [None] * (8 - len(RAISE_SEQUENCE))
    derived[3] = both_arms

    raising = Image.new("RGBA", (CELL_WIDTH * 8, CELL_HEIGHT), (0, 0, 0, 0))
    cells: list[Image.Image] = []
    for column in range(8):
        cell = derived[column]
        if cell is None:
            continue
        raising.alpha_composite(cell, (column * CELL_WIDTH, 0))
        cells.append(cell)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    raising.save(output_path, lossless=True, quality=100, exact=True)
    return cells


def contact_sheet(assets: dict[str, list[Image.Image]]) -> None:
    from PIL import ImageDraw

    QA.mkdir(parents=True, exist_ok=True)
    roles = list(assets)
    sheet = Image.new(
        "RGBA",
        (CELL_WIDTH * 8, CELL_HEIGHT * len(roles)),
        (35, 35, 42, 255),
    )
    draw = ImageDraw.Draw(sheet)
    for row_index, (name, cells) in enumerate(assets.items()):
        y = row_index * CELL_HEIGHT
        for column, cell in enumerate(cells):
            sheet.alpha_composite(cell, (column * CELL_WIDTH, y))
        draw.text((6, y + 6), f"{name} raise {RAISE_SEQUENCE} + mirrored arms", fill=(255, 255, 255, 255))
    sheet.save(QA / "raising-atlas-contact-sheet.png")


def main() -> None:
    assets: dict[str, list[Image.Image]] = {}
    report = {
        "sourceRow": SOURCE_ROW,
        "sequence": list(RAISE_SEQUENCE),
        "armStrip": list(ARM_STRIP),
        "cell": [CELL_WIDTH, CELL_HEIGHT],
        "roles": [],
    }
    for source_name, output_name in ROLES.items():
        source_path = ROOT / source_name
        output_path = ROOT / output_name
        cells = derive(source_path, output_path)
        assets[source_path.name] = cells
        saved = Image.open(output_path).convert("RGBA")
        atlas = Image.open(source_path).convert("RGBA")
        role_report = {
            "source": source_name,
            "output": output_name,
            "size": list(saved.size),
            "symmetryAxis": SYMMETRY_AXES[source_name],
            "cells": [
                {
                    "index": index,
                    "sourceColumn": RAISE_SEQUENCE[index] if index < len(RAISE_SEQUENCE) else 3,
                    "bbox": list(cell.getbbox() or (0, 0, 0, 0)),
                    "matches_source_frame": (
                        cell.tobytes() == frame(atlas, RAISE_SEQUENCE[index]).tobytes()
                        if index < len(RAISE_SEQUENCE)
                        else False
                    ),
                }
                for index, cell in enumerate(cells)
            ],
        }
        role_report["ok"] = (
            saved.size == (CELL_WIDTH * 8, CELL_HEIGHT)
            and all(item["bbox"] != [0, 0, 0, 0] for item in role_report["cells"])
            and all(
                item["matches_source_frame"]
                for item in role_report["cells"][: len(RAISE_SEQUENCE)]
            )
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
