#!/usr/bin/env python3
"""Derive the card-drawing "raise" helper atlases from approved source art.

抽卡动作 = 双手向上举起卡牌。Frames 0-2 reuse the approved thumbsUp row (arm
down, rising, one arm up). The final both-arms-up frame is composed from the
character sheet's own "\\o/" figure (crying, both arms raised — the pose the
game itself uses), scaled to the approved sprite band and registered on the
shared feet/head anchors, so no mirrored or invented pixels are involved.

Magdalene keeps her Golden Locks: the composed figure's head is replaced by her
own thumbsUp head+hair (the region above where the arms live in both roles),
plus the hair strands that hang below that line (extracted as the per-pixel
difference from the base Isaac frame, which excludes arms because both roles'
arm pixels are identical there).
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
RAISE_SEQUENCE = (0, 1, 2)  # followed by the composed both-arms frame
# The character sheet's complete both-arms-up figure (crying, "\\o/").
FIGURE_BOX = (82, 218, 110, 249)
# Anchor band the approved thumbsUp sprites occupy inside a cell: head top and
# feet bottom, with the shared face axis as the horizontal center.
HEAD_TOP = 46
FEET_BOTTOM = 178
FACE_AXIS = 83.5
# Head+hair live above this line in both roles' frame 0; arms start below it.
HEAD_BOTTOM = 137
ROLES = {
    "Resources/spritesheet.webp": "Resources/raising-atlas.webp",
    "Resources/Agents/magdalene-spritesheet.webp": "Resources/Agents/magdalene-raising-atlas.webp",
}


def frame(atlas: Image.Image, column: int) -> Image.Image:
    left = column * CELL_WIDTH
    top = SOURCE_ROW * CELL_HEIGHT
    return atlas.crop((left, top, left + CELL_WIDTH, top + CELL_HEIGHT))


def composed_figure_frame() -> Image.Image:
    """Scale the sheet's \\o/ figure onto the approved sprite band anchors."""
    sheet = Image.open(ROOT / "Assets/Source/isaac-character-sheet.png").convert("RGBA")
    figure = sheet.crop(FIGURE_BOX)
    band_height = FEET_BOTTOM - HEAD_TOP
    scale = band_height / figure.height
    scaled = figure.resize(
        (round(figure.width * scale), band_height), Image.Resampling.NEAREST
    )
    canvas = Image.new("RGBA", (CELL_WIDTH, CELL_HEIGHT), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, (round(FACE_AXIS - scaled.width / 2), HEAD_TOP))
    return canvas


def role_head_layer(role_frame0: Image.Image, base_frame0: Image.Image) -> Image.Image | None:
    """Head+hair layer from the role's own frame 0, or None for the base role."""
    if role_frame0.tobytes() == base_frame0.tobytes():
        return None
    role_px = role_frame0.load()
    base_px = base_frame0.load()
    layer = Image.new("RGBA", (CELL_WIDTH, CELL_HEIGHT), (0, 0, 0, 0))
    layer_px = layer.load()
    for y in range(CELL_HEIGHT):
        for x in range(CELL_WIDTH):
            pixel = role_px[x, y]
            if pixel[3] == 0:
                continue
            # Above the arm line the whole head+hair transfers; below it only
            # the hanging hair strands, which the base role lacks right there
            # (both roles' arm pixels are identical, so they diff away).
            if y <= HEAD_BOTTOM or base_px[x, y] != pixel:
                layer_px[x, y] = pixel
    return layer


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


def derive(source_path: Path, output_path: Path, base_atlas: Image.Image) -> list[Image.Image]:
    atlas = Image.open(source_path).convert("RGBA")
    sources = [frame(atlas, column) for column in range(SOURCE_FRAMES)]
    for column, cell in enumerate(sources):
        if not cell.getbbox():
            raise SystemExit(f"{source_path}: thumbsUp frame {column} is empty")

    figure_frame = composed_figure_frame()
    head_layer = role_head_layer(sources[0], frame(base_atlas, 0))
    if head_layer is not None:
        figure_frame.alpha_composite(head_layer)
    if connected_components(figure_frame) != 1:
        raise SystemExit(f"{source_path}: composed both-arms frame is not one connected sprite")

    derived: list[Image.Image] = [sources[column] for column in RAISE_SEQUENCE]
    derived.append(figure_frame)
    derived += [None] * (8 - len(derived))

    raising = Image.new("RGBA", (CELL_WIDTH * 8, CELL_HEIGHT), (0, 0, 0, 0))
    cells: list[Image.Image] = []
    for column, cell in enumerate(derived):
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
        draw.text(
            (6, y + 6),
            f"{name} raise {RAISE_SEQUENCE} + composed both-arms figure",
            fill=(255, 255, 255, 255),
        )
    sheet.save(QA / "raising-atlas-contact-sheet.png")


def main() -> None:
    base_atlas = Image.open(ROOT / "Resources/spritesheet.webp").convert("RGBA")
    assets: dict[str, list[Image.Image]] = {}
    report = {
        "sourceRow": SOURCE_ROW,
        "sequence": list(RAISE_SEQUENCE) + ["composed-o-pose"],
        "figureBox": list(FIGURE_BOX),
        "anchors": {"headTop": HEAD_TOP, "feetBottom": FEET_BOTTOM, "faceAxis": FACE_AXIS},
        "cell": [CELL_WIDTH, CELL_HEIGHT],
        "roles": [],
    }
    for source_name, output_name in ROLES.items():
        source_path = ROOT / source_name
        output_path = ROOT / output_name
        role_atlas = Image.open(source_path).convert("RGBA")
        cells = derive(source_path, output_path, base_atlas)
        assets[source_path.name] = cells
        saved = Image.open(output_path).convert("RGBA")
        role_report = {
            "source": source_name,
            "output": output_name,
            "size": list(saved.size),
            "cells": [
                {
                    "index": index,
                    "bbox": list(cell.getbbox() or (0, 0, 0, 0)),
                    "matches_source_frame": (
                        cell.tobytes() == frame(role_atlas, RAISE_SEQUENCE[index]).tobytes()
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
