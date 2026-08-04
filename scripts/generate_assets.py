#!/usr/bin/env python3
"""Build the standalone Isaac atlas and icon assets from the supplied pixel art."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "Assets" / "Source"
RESOURCES = ROOT / "Resources"
QA = ROOT / "qa"
CELL_W, CELL_H = 192, 208
ATLAS_SIZE = (CELL_W * 8, CELL_H * 11)
VERTICAL_WALK_COLUMNS = 4
VERTICAL_WALK_ROWS = 2
WALK_TARGET_WIDTH = 112
WALK_HEAD_TOP = 46


def nearest(image: Image.Image, scale: int) -> Image.Image:
    return image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)


def trimmed(image: Image.Image) -> Image.Image:
    box = image.getbbox()
    return image.crop(box) if box else image.copy()


def source_head(sheet: Image.Image, x: int, mirrored: bool = False) -> Image.Image:
    head = trimmed(sheet.crop((x, 0, x + 32, 32)))
    return ImageOps.mirror(head) if mirrored else head


def source_body(sheet: Image.Image, x: int, y: int) -> Image.Image:
    return trimmed(sheet.crop((x, y, x + 32, y + 32)))


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


def make_direction_cell(
    head: Image.Image,
    body: Image.Image,
    fixed_head_top: int | None = None,
) -> Image.Image:
    canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    scaled_body = nearest(body, 4)
    scaled_head = nearest(head, 4)
    body_x = (CELL_W - scaled_body.width) // 2
    body_y = CELL_H - scaled_body.height - 28
    head_x = (CELL_W - scaled_head.width) // 2
    # Normal direction poses use a small overlap. Vertical walking bodies include more torso,
    # so their head is registered to the shared top edge and the torso sits behind it.
    head_y = fixed_head_top if fixed_head_top is not None else body_y - scaled_head.height + 10
    canvas.alpha_composite(scaled_body, (body_x, body_y))
    canvas.alpha_composite(scaled_head, (head_x, head_y))
    return canvas


def normalize_walking_row(atlas: Image.Image, row: int, frame_count: int) -> list[Image.Image]:
    """Bring legacy three-pixel walking art up to the four-pixel idle/look scale."""
    normalized: list[Image.Image] = []
    for column in range(frame_count):
        left = column * CELL_W
        top = row * CELL_H
        cell = atlas.crop((left, top, left + CELL_W, top + CELL_H))
        box = cell.getbbox()
        if not box:
            raise SystemExit(f"walking row {row} frame {column} is empty")
        sprite = cell.crop(box)
        target_height = round(sprite.height * WALK_TARGET_WIDTH / sprite.width)
        resized = sprite.resize((WALK_TARGET_WIDTH, target_height), Image.Resampling.NEAREST)
        source_center_x = (box[0] + box[2]) / 2
        target_x = round(source_center_x - WALK_TARGET_WIDTH / 2)
        target_y = box[3] - target_height
        output = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        output.alpha_composite(resized, (target_x, target_y))
        atlas.paste(output, (left, top))
        normalized.append(output)
    return normalized


def make_icons(base: Image.Image) -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    head = trimmed(base.crop((0, 0, base.width, 24)))
    status = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    small = nearest(head, 1)
    status.alpha_composite(small, ((36 - small.width) // 2, (36 - small.height) // 2))
    status.resize((18, 18), Image.Resampling.NEAREST).save(RESOURCES / "StatusIsaac.png")

    icon = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    icon_sprite = nearest(trimmed(base), 24)
    icon.alpha_composite(icon_sprite, ((1024 - icon_sprite.width) // 2, (1024 - icon_sprite.height) // 2))
    icon.save(RESOURCES / "IsaacPet.png")

    iconset = ROOT / ".build" / "IsaacPet.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.Resampling.NEAREST).save(iconset / f"icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.Resampling.NEAREST).save(iconset / f"icon_{size}x{size}@2x.png")
    icns = RESOURCES / "IsaacPet.icns"
    subprocess.run(["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)


def make_tear_sprite(atlas: Image.Image) -> None:
    # Crop the detached tear from the supplied crying animation itself. This keeps the
    # projectile pixel-for-pixel Isaac artwork rather than inventing a new shape or palette.
    cell = atlas.crop((0, 5 * CELL_H, CELL_W, 6 * CELL_H))
    pixel = cell.load()
    cyan = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    cyan_pixels = cyan.load()
    for y in range(cell.height):
        for x in range(cell.width):
            r, g, b, a = pixel[x, y]
            if a and b > g * 0.92 and g > r * 1.15 and g > 110:
                cyan_pixels[x, y] = (r, g, b, a)
    box = cyan.getbbox()
    if not box:
        raise SystemExit("Isaac crying animation has no tear pixels")
    # The lower cyan component is the detached tear; crop it with its exact source pixels.
    tear = cyan.crop((box[0], 158, box[2], 177))
    tear.save(RESOURCES / "IsaacTear.png")


def make_shooting_atlas(source_sheet: Image.Image, body: Image.Image) -> list[Image.Image]:
    # Exact closed-eye/cardinal frames from the supplied Isaac sheet:
    # up = flattened back, right = closed side, down = closed front, left = mirrored side.
    sources = [(160, False), (96, False), (32, False), (96, True)]
    cells = [make_direction_cell(source_head(source_sheet, x, flip), body) for x, flip in sources]
    shooting_atlas = Image.new("RGBA", (CELL_W * 4, CELL_H), (0, 0, 0, 0))
    for column, cell in enumerate(cells):
        shooting_atlas.alpha_composite(cell, (column * CELL_W, 0))
    shooting_atlas.save(RESOURCES / "shooting-atlas.webp", lossless=True, quality=100)

    contact = Image.new("RGBA", shooting_atlas.size, (35, 35, 42, 255))
    draw = ImageDraw.Draw(contact)
    for column, (label, cell) in enumerate(zip(("up", "right", "down", "left"), cells)):
        contact.alpha_composite(cell, (column * CELL_W, 0))
        draw.text((column * CELL_W + 6, 6), f"shoot {label}", fill=(255, 255, 255, 255))
    contact.save(QA / "shooting-contact-sheet.png")
    return cells


def make_vertical_walking_atlas(source_sheet: Image.Image) -> dict[str, list[Image.Image]]:
    """Compose the supplied two-frame front/back body cycles with their matching heads."""
    # These are the original Isaac body cells used in the supplied reference images.
    # Alternating A/B twice gives a four-frame loop at the same cadence as side walking.
    source_cells = {
        "down": [(448, 0), (480, 0), (448, 0), (480, 0)],
        "up": [(256, 96), (288, 96), (256, 96), (288, 96)],
    }
    heads = {
        "down": source_head(source_sheet, 0),       # normal front-facing Isaac
        "up": source_head(source_sheet, 128),        # normal back of head
    }
    rows = {
        direction: [
            make_direction_cell(
                heads[direction],
                source_body(source_sheet, x, y),
                fixed_head_top=WALK_HEAD_TOP,
            )
            for x, y in cells
        ]
        for direction, cells in source_cells.items()
    }

    atlas = Image.new(
        "RGBA",
        (CELL_W * VERTICAL_WALK_COLUMNS, CELL_H * VERTICAL_WALK_ROWS),
        (0, 0, 0, 0),
    )
    for row, direction in enumerate(("down", "up")):
        for column, cell in enumerate(rows[direction]):
            atlas.alpha_composite(cell, (column * CELL_W, row * CELL_H))
    atlas.save(RESOURCES / "walking-vertical-atlas.webp", lossless=True, quality=100)

    contact = Image.new("RGBA", atlas.size, (35, 35, 42, 255))
    draw = ImageDraw.Draw(contact)
    for row, direction in enumerate(("down", "up")):
        for column, ((x, y), cell) in enumerate(zip(source_cells[direction], rows[direction])):
            contact.alpha_composite(cell, (column * CELL_W, row * CELL_H))
            draw.text(
                (column * CELL_W + 6, row * CELL_H + 6),
                f"walk {direction} {column + 1}: {x},{y}",
                fill=(255, 255, 255, 255),
            )
    contact.save(QA / "vertical-walking-contact-sheet.png")
    return rows


def make_scale_contact_sheet(atlas: Image.Image, vertical_atlas: Image.Image) -> None:
    frames = [
        ("idle", atlas.crop((0, 0, CELL_W, CELL_H))),
        ("static right", atlas.crop((4 * CELL_W, 9 * CELL_H, 5 * CELL_W, 10 * CELL_H))),
        ("static down", atlas.crop((0, 10 * CELL_H, CELL_W, 11 * CELL_H))),
        ("static up", atlas.crop((0, 9 * CELL_H, CELL_W, 10 * CELL_H))),
        ("walk right", atlas.crop((0, CELL_H, CELL_W, 2 * CELL_H))),
        ("walk left", atlas.crop((0, 2 * CELL_H, CELL_W, 3 * CELL_H))),
        ("walk down", vertical_atlas.crop((0, 0, CELL_W, CELL_H))),
        ("walk up", vertical_atlas.crop((0, CELL_H, CELL_W, 2 * CELL_H))),
    ]
    sheet = Image.new("RGBA", (CELL_W * 4, CELL_H * 2), (35, 35, 42, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (label, cell) in enumerate(frames):
        row, column = divmod(index, 4)
        x = column * CELL_W
        y = row * CELL_H
        sheet.alpha_composite(cell, (x, y))
        box = cell.getbbox()
        if box:
            width = box[2] - box[0]
            height = box[3] - box[1]
            draw.rectangle(
                (x + box[0], y + box[1], x + box[2] - 1, y + box[3] - 1),
                outline=(92, 220, 126, 255),
            )
            draw.text((x + 6, y + 6), f"{label} {width}x{height}", fill=(255, 255, 255, 255))
    sheet.save(QA / "scale-contact-sheet.png")


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    base = Image.open(SOURCE_DIR / "isaac-appearance.png").convert("RGBA")
    source_sheet = Image.open(SOURCE_DIR / "isaac-character-sheet.png").convert("RGBA")
    atlas = Image.open(RESOURCES / "spritesheet-source.webp").convert("RGBA")
    if atlas.size != ATLAS_SIZE:
        raise SystemExit(f"unexpected atlas dimensions: {atlas.size}")

    horizontal_walking_cells = {
        "right": normalize_walking_row(atlas, 1, 8),
        "left": normalize_walking_row(atlas, 2, 8),
    }

    # Eight stable Isaac look poses, duplicated into the 16 directional slots.
    # The source atlas contains the previous approximate look rows. Clear them completely before
    # compositing transparent replacements, otherwise detached pixels survive outside the new pose.
    atlas.paste((0, 0, 0, 0), (0, 9 * CELL_H, atlas.width, 11 * CELL_H))
    head_x = [128, 96, 96, 64, 64, 64, 64, 0, 0, 64, 64, 64, 64, 96, 96, 128]
    mirrored = [False] * 9 + [True] * 7
    body = trimmed(base.crop((0, 22, base.width, base.height)))
    directions = []
    for index, (x, flip) in enumerate(zip(head_x, mirrored)):
        cell = make_direction_cell(source_head(source_sheet, x, flip), body)
        row, col = divmod(index, 8)
        atlas.alpha_composite(cell, (col * CELL_W, (9 + row) * CELL_H))
        directions.append(cell)

    atlas.save(RESOURCES / "spritesheet.webp", lossless=True, quality=100)
    make_icons(base)
    make_tear_sprite(atlas)
    shooting_cells = make_shooting_atlas(source_sheet, body)
    vertical_walking_cells = make_vertical_walking_atlas(source_sheet)

    sheet = Image.new("RGBA", (CELL_W * 8, CELL_H * 2), (35, 35, 42, 255))
    draw = ImageDraw.Draw(sheet)
    labels = ["up", "up-right", "up-right", "right", "right", "down-right", "down-right", "down",
              "down", "down-left", "down-left", "left", "left", "up-left", "up-left", "up"]
    for index, cell in enumerate(directions):
        row, col = divmod(index, 8)
        sheet.alpha_composite(cell, (col * CELL_W, row * CELL_H))
        draw.text((col * CELL_W + 6, row * CELL_H + 6), labels[index], fill=(255, 255, 255, 255))
    sheet.save(QA / "direction-contact-sheet.png")

    final_direction_cells = [
        atlas.crop(((index % 8) * CELL_W, (9 + index // 8) * CELL_H,
                    (index % 8 + 1) * CELL_W, (10 + index // 8) * CELL_H))
        for index in range(16)
    ]
    final_shooting_atlas = Image.open(RESOURCES / "shooting-atlas.webp").convert("RGBA")
    final_shooting_cells = [
        final_shooting_atlas.crop((column * CELL_W, 0, (column + 1) * CELL_W, CELL_H))
        for column in range(4)
    ]
    final_vertical_walking_atlas = Image.open(RESOURCES / "walking-vertical-atlas.webp").convert("RGBA")
    final_vertical_walking_cells = {
        direction: [
            final_vertical_walking_atlas.crop(
                (column * CELL_W, row * CELL_H, (column + 1) * CELL_W, (row + 1) * CELL_H)
            )
            for column in range(VERTICAL_WALK_COLUMNS)
        ]
        for row, direction in enumerate(("down", "up"))
    }
    final_horizontal_walking_cells = {
        direction: [
            atlas.crop(
                (column * CELL_W, row * CELL_H, (column + 1) * CELL_W, (row + 1) * CELL_H)
            )
            for column in range(8)
        ]
        for row, direction in ((1, "right"), (2, "left"))
    }
    make_scale_contact_sheet(atlas, final_vertical_walking_atlas)
    idle_bbox = atlas.crop((0, 0, CELL_W, CELL_H)).getbbox()
    validation = {
        "ok": True,
        "atlas": "Resources/spritesheet.webp",
        "size": list(atlas.size),
        "source": ["Assets/Source/isaac-character-sheet.png", "Assets/Source/isaac-appearance.png"],
        "scale_consistency": {
            "target_visible_width": WALK_TARGET_WIDTH,
            "idle_bbox": list(idle_bbox or (0, 0, 0, 0)),
            "contact_sheet": "qa/scale-contact-sheet.png",
        },
        "direction_cells": [
            {
                "index": i,
                "components": connected_components(cell),
                "bbox": list(cell.getbbox() or (0, 0, 0, 0)),
                "matches_composed_cell": cell.tobytes() == directions[i].tobytes(),
            }
            for i, cell in enumerate(final_direction_cells)
        ],
        "shooting_atlas": {
            "path": "Resources/shooting-atlas.webp",
            "size": [CELL_W * 4, CELL_H],
            "order": ["up-flat-back", "right-closed", "down-closed", "left-closed"],
            "source_head_x": [160, 96, 32, 96],
            "cells": [
                {
                    "index": index,
                    "components": connected_components(cell),
                    "bbox": list(cell.getbbox() or (0, 0, 0, 0)),
                    "matches_composed_cell": cell.tobytes() == shooting_cells[index].tobytes(),
                }
                for index, cell in enumerate(final_shooting_cells)
            ],
        },
        "horizontal_walking": {
            "target_visible_width": WALK_TARGET_WIDTH,
            "cells": {
                direction: [
                    {
                        "index": index,
                        "components": connected_components(cell),
                        "bbox": list(cell.getbbox() or (0, 0, 0, 0)),
                        "matches_normalized_cell": (
                            cell.tobytes() == horizontal_walking_cells[direction][index].tobytes()
                        ),
                    }
                    for index, cell in enumerate(final_horizontal_walking_cells[direction])
                ]
                for direction in ("right", "left")
            },
        },
        "vertical_walking_atlas": {
            "path": "Resources/walking-vertical-atlas.webp",
            "size": [CELL_W * VERTICAL_WALK_COLUMNS, CELL_H * VERTICAL_WALK_ROWS],
            "order": ["down-front-head", "up-back-head"],
            "source_body_cells": {
                "down": [[448, 0], [480, 0], [448, 0], [480, 0]],
                "up": [[256, 96], [288, 96], [256, 96], [288, 96]],
            },
            "cells": {
                direction: [
                    {
                        "index": index,
                        "components": connected_components(cell),
                        "bbox": list(cell.getbbox() or (0, 0, 0, 0)),
                        "matches_composed_cell": cell.tobytes() == vertical_walking_cells[direction][index].tobytes(),
                    }
                    for index, cell in enumerate(final_vertical_walking_cells[direction])
                ]
                for direction in ("down", "up")
            },
        },
    }
    validation["ok"] = atlas.size == ATLAS_SIZE and all(
        item["components"] == 1 and item["matches_composed_cell"]
        for item in validation["direction_cells"]
    ) and all(
        item["bbox"][2] - item["bbox"][0] == WALK_TARGET_WIDTH
        and item["bbox"][3] == 180
        for item in validation["direction_cells"]
    ) and all(
        item["components"] == 1 and item["matches_composed_cell"]
        for item in validation["shooting_atlas"]["cells"]
    ) and all(
        item["components"] == 1
        and item["matches_normalized_cell"]
        and item["bbox"][2] - item["bbox"][0] == WALK_TARGET_WIDTH
        and item["bbox"][3] - item["bbox"][1] == 132
        and 180 <= item["bbox"][3] <= 182
        for direction in ("right", "left")
        for item in validation["horizontal_walking"]["cells"][direction]
    ) and all(
        item["components"] == 1 and item["matches_composed_cell"]
        for direction in ("down", "up")
        for item in validation["vertical_walking_atlas"]["cells"][direction]
    ) and all(
        item["bbox"][0] == 40
        and item["bbox"][1] == WALK_HEAD_TOP
        and item["bbox"][2] == 152
        and item["bbox"][3] == 180
        for direction in ("down", "up")
        for item in validation["vertical_walking_atlas"]["cells"][direction]
    ) and idle_bbox is not None and idle_bbox[2] - idle_bbox[0] == WALK_TARGET_WIDTH
    (QA / "assets-validation.json").write_text(json.dumps(validation, indent=2) + "\n")
    if not validation["ok"]:
        raise SystemExit("asset validation failed")


if __name__ == "__main__":
    main()
