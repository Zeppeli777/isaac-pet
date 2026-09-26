#!/usr/bin/env python3
"""Build the standalone Isaac atlas and icon assets from the supplied pixel art."""

from __future__ import annotations

import json
import subprocess
from math import hypot, sqrt
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "Assets" / "Source"
RESOURCES = ROOT / "Resources"
QA = ROOT / "qa"
CELL_W, CELL_H = 192, 208
ATLAS_SIZE = (CELL_W * 8, CELL_H * 11)
VERTICAL_WALK_COLUMNS = 8
VERTICAL_WALK_ROWS = 2
WALK_TARGET_WIDTH = 112
WALK_HEAD_TOP = 46
WALK_BODY_MARGIN = 28
TEAR_SIZE = 19
# Sampled from the Isaac tear reference: black rim, then three steps of lit blue.
TEAR_OUTLINE = (7, 0, 0, 255)
TEAR_SHADE = (120, 162, 248, 255)
TEAR_BODY = (169, 197, 252, 255)
TEAR_HIGHLIGHT = (231, 242, 254, 255)
# Sampled from the in-game emote bubble references (Assets/Source/Emotes): tan paper,
# its light/shadow variants, the dark outline and the white of the eyes.
EMOTE_TAN = (193, 173, 150, 255)
EMOTE_TAN_LIGHT = (198, 179, 156, 255)
EMOTE_TAN_SHADOW = (151, 133, 119, 255)
EMOTE_OUTLINE = (52, 47, 44, 255)
EMOTE_WHITE = (255, 255, 255, 255)
EMOTE_PALETTE = (EMOTE_TAN, EMOTE_TAN_LIGHT, EMOTE_TAN_SHADOW, EMOTE_OUTLINE, EMOTE_WHITE)
# The paper texture flickers between the tan variants, so they must dominate a cell
# decisively before they are allowed to speckle the flat body.
EMOTE_SOFT_COLORS = {EMOTE_TAN_LIGHT, EMOTE_TAN_SHADOW}
EMOTE_SOFT_SHARE = 0.55
EMOTE_GRID_WIDTH = 48
EMOTE_MAGNIFICATION = 10
# The supplied vertical walk cycle is a contact sheet of 16 slices laid out as 8 columns
# by 2 rows; its columns are not uniform and its rows differ in height, so each slice is
# addressed by the content band the gaps leave behind.
WALK_CYCLE_SHEET = "isaac-vertical-walk-cycle"
WALK_CYCLE_COLUMNS = 8
WALK_CYCLE_ROWS = 2
# Body order of each direction's walk cycle, addressed as (row, column) on that sheet.
WALK_DOWN_BODIES = ((1, 0), (1, 1), (1, 2), (1, 1), (1, 0), (1, 6), (1, 7), (1, 6))
WALK_UP_BODIES = ((1, 0), (0, 7), (0, 6), (0, 7), (1, 0), (1, 4), (1, 3), (1, 4))


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


def make_tear_sprite() -> None:
    # Isaac's tears are round orbs: a dark rim around a blue ball with a bright highlight,
    # so the projectile is shaded here instead of cropping the detached crying-face blob.
    canvas = Image.new("RGBA", (TEAR_SIZE, TEAR_SIZE), (0, 0, 0, 0))
    pixels = canvas.load()
    center = (TEAR_SIZE - 1) / 2
    radius = TEAR_SIZE / 2
    rim = 0.24
    highlight_center = (center - 1.8, center - 1.6)
    highlight_radius = 2.4
    light = (-0.30, 0.42, 0.86)  # the light source sits above and to the left of the tear
    for y in range(TEAR_SIZE):
        for x in range(TEAR_SIZE):
            nx = (x - center) / (radius - 0.15)
            ny = (y - center) / (radius - 0.15)
            distance = hypot(nx, ny)
            if distance > 1:
                continue
            if distance > 1 - rim:
                pixels[x, y] = TEAR_OUTLINE
                continue
            diffuse = max(0.0, nx * light[0] - ny * light[1] + sqrt(1 - distance * distance) * light[2])
            if hypot(x - highlight_center[0], y - highlight_center[1]) <= highlight_radius:
                pixels[x, y] = TEAR_HIGHLIGHT
            elif diffuse > 0.95:
                pixels[x, y] = TEAR_HIGHLIGHT
            elif diffuse > 0.62:
                pixels[x, y] = TEAR_BODY
            else:
                pixels[x, y] = TEAR_SHADE
    canvas.save(RESOURCES / "IsaacTear.png")

    # Keep the round shape reviewable next to the other atlases.
    magnified = nearest(canvas, 8)
    contact = Image.new(
        "RGBA",
        (magnified.width + 60, magnified.height + 28),
        (35, 35, 42, 255),
    )
    contact.alpha_composite(canvas, (20, 28))
    contact.alpha_composite(magnified, (39, 0))
    draw = ImageDraw.Draw(contact)
    draw.text((20, 6), "1x", fill=(255, 255, 255, 255))
    draw.text((39, 6), "8x", fill=(255, 255, 255, 255))
    contact.save(QA / "tear-contact-sheet.png")


def tear_validation(tear: Image.Image) -> dict[str, object]:
    palette = {TEAR_OUTLINE, TEAR_SHADE, TEAR_BODY, TEAR_HIGHLIGHT}
    alpha = tear.getchannel("A")
    pixels = alpha.load()
    center = (TEAR_SIZE - 1) / 2
    radius = TEAR_SIZE / 2
    inside_circle = all(
        hypot(x - center, y - center) <= radius
        for y in range(TEAR_SIZE)
        for x in range(TEAR_SIZE)
        if pixels[x, y]
    )
    colors = {color for color in tear.getdata() if color[3]}
    return {
        "path": "Resources/IsaacTear.png",
        "size": [TEAR_SIZE, TEAR_SIZE],
        "components": connected_components(tear),
        "round": inside_circle,
        "palette": sorted(color[:3] for color in colors) == sorted(color[:3] for color in palette),
        "contact_sheet": "qa/tear-contact-sheet.png",
    }


def is_emote_backdrop(pixel: tuple[int, ...]) -> bool:
    red, green, blue = pixel[:3]
    return red > 242 and green > 242 and blue > 242


def drop_emote_backdrop(image: Image.Image) -> Image.Image:
    """Flood the white page colour away from the borders so interior whites survive."""
    image = image.convert("RGBA")
    pixels = image.load()
    seen = [[False] * image.width for _ in range(image.height)]
    stack: list[tuple[int, int]] = []
    for x in range(image.width):
        for y in (0, image.height - 1):
            if is_emote_backdrop(pixels[x, y]) and not seen[y][x]:
                seen[y][x] = True
                stack.append((x, y))
    for y in range(image.height):
        for x in (0, image.width - 1):
            if is_emote_backdrop(pixels[x, y]) and not seen[y][x]:
                seen[y][x] = True
                stack.append((x, y))
    while stack:
        x, y = stack.pop()
        pixels[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < image.width and 0 <= ny < image.height \
                    and not seen[ny][nx] and is_emote_backdrop(pixels[nx, ny]):
                seen[ny][nx] = True
                stack.append((nx, ny))
    return image


def nearest_emote_color(pixel: tuple[int, ...]) -> tuple[int, int, int, int]:
    best, best_distance = EMOTE_TAN, 1 << 30
    for color in EMOTE_PALETTE:
        distance = sum((pixel[index] - color[index]) ** 2 for index in range(3))
        if distance < best_distance:
            best_distance, best = distance, color
    return best


def make_emote_bubble(source: Image.Image) -> Image.Image:
    """Grid-snap one reference emote bubble onto the shared pixel grid."""
    image = drop_emote_backdrop(source)
    image = image.crop(image.getbbox())
    width = EMOTE_GRID_WIDTH
    height = round(image.height / image.width * width)
    pixels = image.load()
    output = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    out = output.load()
    for cell_y in range(height):
        y0, y1 = image.height * cell_y // height, image.height * (cell_y + 1) // height
        for cell_x in range(width):
            x0, x1 = image.width * cell_x // width, image.width * (cell_x + 1) // width
            votes: dict[tuple[int, int, int, int], int] = {}
            total = 0
            for y in range(y0, y1):
                for x in range(x0, x1):
                    if pixels[x, y][3]:
                        color = nearest_emote_color(pixels[x, y])
                        votes[color] = votes.get(color, 0) + 1
                        total += 1
            if not votes:
                continue
            ranked = sorted(votes.items(), key=lambda item: -item[1])
            color = ranked[0][0]
            # Texture speckle guard: a soft colour only survives with a decisive majority.
            if color in EMOTE_SOFT_COLORS and ranked[0][1] < total * EMOTE_SOFT_SHARE and len(ranked) > 1:
                color = ranked[1][0]
            out[cell_x, cell_y] = color
    return output


def make_emote_bubbles() -> dict[str, Image.Image]:
    sources = {
        "sad": "reference-emote-sad.png",
        "shocked": "reference-emote-shocked.png",
        "happy": "reference-emote-happy.png",
    }
    bubbles = {}
    for kind, filename in sources.items():
        bubble = make_emote_bubble(Image.open(SOURCE_DIR / "Emotes" / filename))
        bubbles[kind] = bubble
        bubble.save(RESOURCES / f"Emote{kind.capitalize()}.png")

    cell = max(bubble.height for bubble in bubbles.values()) * EMOTE_MAGNIFICATION
    reference_height = 240
    sheet = Image.new("RGBA", (900 + cell + 30, cell + 30), (35, 35, 42, 255))
    draw = ImageDraw.Draw(sheet)
    x = 10
    for kind in ("sad", "shocked", "happy"):
        reference = Image.open(SOURCE_DIR / "Emotes" / sources[kind]).convert("RGBA")
        reference = reference.crop(reference.getbbox())
        scaled = reference.resize(
            (round(reference.width * reference_height / reference.height), reference_height),
            Image.Resampling.NEAREST,
        )
        sheet.alpha_composite(scaled, (x, 15))
        draw.text((x, 2), f"{kind} ref", fill=(255, 255, 255, 255))
        x += scaled.width + 12
    for kind in ("sad", "shocked", "happy"):
        magnified = nearest(bubbles[kind], EMOTE_MAGNIFICATION)
        sheet.alpha_composite(magnified, (x, 15))
        draw.text((x, 2), f"{kind} {bubbles[kind].width}x{bubbles[kind].height}", fill=(255, 255, 255, 255))
        x += magnified.width + 10
    sheet.save(QA / "emotes-contact-sheet.png")
    return bubbles


def emote_validation(bubbles: dict[str, Image.Image]) -> dict[str, object]:
    cells = {}
    for kind, bubble in bubbles.items():
        colors = {color for color in bubble.getdata() if color[3]}
        cells[kind] = {
            "path": f"Resources/Emote{kind.capitalize()}.png",
            "size": [bubble.width, bubble.height],
            "components": connected_components(bubble),
            "palette": colors <= set(EMOTE_PALETTE),
        }
    return cells


def make_shooting_atlas(source_sheet: Image.Image, body: Image.Image) -> list[Image.Image]:
    # Exact closed-eye/cardinal frames from the supplied Isaac sheet:
    # up = flattened back, right = closed side, down = closed front, left = mirrored side.
    sources = [(160, False), (96, False), (32, False), (96, True)]
    cells = [make_direction_cell(source_head(source_sheet, x, flip), body) for x, flip in sources]
    shooting_atlas = Image.new("RGBA", (CELL_W * 4, CELL_H), (0, 0, 0, 0))
    for column, cell in enumerate(cells):
        shooting_atlas.alpha_composite(cell, (column * CELL_W, 0))
    shooting_atlas.save(RESOURCES / "shooting-atlas.webp", lossless=True, quality=100, exact=True)

    contact = Image.new("RGBA", shooting_atlas.size, (35, 35, 42, 255))
    draw = ImageDraw.Draw(contact)
    for column, (label, cell) in enumerate(zip(("up", "right", "down", "left"), cells)):
        contact.alpha_composite(cell, (column * CELL_W, 0))
        draw.text((column * CELL_W + 6, 6), f"shoot {label}", fill=(255, 255, 255, 255))
    contact.save(QA / "shooting-contact-sheet.png")
    return cells


def cycle_bands(lines: list[bool], count: int) -> list[tuple[int, int]]:
    """Group a per-line ink profile into `count` content bands split by empty gaps."""
    bands: list[tuple[int, int]] = []
    start = None
    for index, inked in enumerate(lines):
        if inked and start is None:
            start = index
        elif not inked and start is not None:
            bands.append((start, index - 1))
            start = None
    if start is not None:
        bands.append((start, len(lines) - 1))
    if len(bands) != count:
        raise SystemExit(f"expected {count} walk-cycle slice bands, found {len(bands)}")
    return bands


def is_cycle_backdrop(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue = pixel[:3]
    return red > 200 and green > 200 and blue > 200 and max(red, green, blue) - min(red, green, blue) <= 12


def cycle_slice_bands(sheet: Image.Image) -> dict[str, list[tuple[int, int]]]:
    """Locate every slice of the walk-cycle contact sheet from its empty gutters."""
    pixels = sheet.load()
    columns = [
        any(not is_cycle_backdrop(pixels[x, y]) for y in range(sheet.height))
        for x in range(sheet.width)
    ]
    rows = [
        any(not is_cycle_backdrop(pixels[x, y]) for x in range(sheet.width))
        for y in range(sheet.height)
    ]
    return {
        "columns": cycle_bands(columns, WALK_CYCLE_COLUMNS),
        "rows": cycle_bands(rows, WALK_CYCLE_ROWS),
    }


def cycle_slice(
    sheet: Image.Image,
    bands: dict[str, list[tuple[int, int]]],
    row: int,
    column: int,
) -> Image.Image:
    """Cut one slice out of the walk-cycle contact sheet and drop its light backdrop."""
    x0, x1 = bands["columns"][column]
    y0, y1 = bands["rows"][row]
    block = sheet.crop((x0, y0, x1 + 1, y1 + 1)).convert("RGBA")
    block_pixels = block.load()
    for y in range(block.height):
        for x in range(block.width):
            if is_cycle_backdrop(block_pixels[x, y]):
                block_pixels[x, y] = (0, 0, 0, 0)
    return trimmed(block)


def make_vertical_walking_cell(head: Image.Image, body: Image.Image) -> Image.Image:
    """Register one already-sized body slice under the 4× head."""
    canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    scaled_head = nearest(head, 4)
    canvas.alpha_composite(
        body, ((CELL_W - body.width) // 2, CELL_H - body.height - WALK_BODY_MARGIN)
    )
    canvas.alpha_composite(scaled_head, ((CELL_W - scaled_head.width) // 2, WALK_HEAD_TOP))
    return canvas


def make_vertical_walking_atlas(
    source_sheet: Image.Image, cycle_sheet: Image.Image
) -> dict[str, list[Image.Image]]:
    """Compose the supplied eight-frame front/back walk cycles with their matching heads."""
    heads = {
        "down": source_head(source_sheet, 0),       # normal front-facing Isaac
        "up": source_head(source_sheet, 128),        # normal back of head
    }
    bodies = {"down": WALK_DOWN_BODIES, "up": WALK_UP_BODIES}
    bands = cycle_slice_bands(cycle_sheet)
    rows = {
        direction: [
            make_vertical_walking_cell(
                heads[direction],
                cycle_slice(cycle_sheet, bands, slice_row, slice_column),
            )
            for slice_row, slice_column in cells
        ]
        for direction, cells in bodies.items()
    }

    atlas = Image.new(
        "RGBA",
        (CELL_W * VERTICAL_WALK_COLUMNS, CELL_H * VERTICAL_WALK_ROWS),
        (0, 0, 0, 0),
    )
    for row, direction in enumerate(("down", "up")):
        for column, cell in enumerate(rows[direction]):
            atlas.alpha_composite(cell, (column * CELL_W, row * CELL_H))
    atlas.save(RESOURCES / "walking-vertical-atlas.webp", lossless=True, quality=100, exact=True)

    contact = Image.new("RGBA", atlas.size, (35, 35, 42, 255))
    draw = ImageDraw.Draw(contact)
    for row, direction in enumerate(("down", "up")):
        for column, cell in enumerate(rows[direction]):
            contact.alpha_composite(cell, (column * CELL_W, row * CELL_H))
            draw.text(
                (column * CELL_W + 6, row * CELL_H + 6),
                f"walk {direction} {column + 1}: slice {bodies[direction][column]}",
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
    cycle_sheet = Image.open(SOURCE_DIR / f"{WALK_CYCLE_SHEET}.png").convert("RGBA")
    if cycle_sheet.size != (996, 264):
        raise SystemExit(f"unexpected walk-cycle sheet dimensions: {cycle_sheet.size}")
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

    atlas.save(RESOURCES / "spritesheet.webp", lossless=True, quality=100, exact=True)
    make_icons(base)
    make_tear_sprite()
    emote_bubbles = make_emote_bubbles()
    shooting_cells = make_shooting_atlas(source_sheet, body)
    vertical_walking_cells = make_vertical_walking_atlas(source_sheet, cycle_sheet)

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
    final_tear = Image.open(RESOURCES / "IsaacTear.png").convert("RGBA")
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
        "tear": tear_validation(final_tear),
        "emotes": emote_validation(emote_bubbles),
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
    tear = validation["tear"]
    validation["ok"] = (
        validation["ok"]
        and tear["size"] == [TEAR_SIZE, TEAR_SIZE]
        and tear["components"] == 1
        and tear["round"]
        and tear["palette"]
    )
    for emote in validation["emotes"].values():
        validation["ok"] = validation["ok"] and emote["components"] == 1 and emote["palette"]
    (QA / "assets-validation.json").write_text(json.dumps(validation, indent=2) + "\n")
    if not validation["ok"]:
        raise SystemExit("asset validation failed")


if __name__ == "__main__":
    main()
