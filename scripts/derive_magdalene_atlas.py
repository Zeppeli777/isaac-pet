#!/usr/bin/env python3
"""Derive a Magdalene desktop-pet atlas from approved Isaac motion and hair art.

The base animation timing, bodies and direction registration remain the approved Isaac atlas.
Only the user-provided Golden Locks pixels are composited onto each occupied cell.  This
is intentionally a deterministic source-art derivation: it does not generate, redraw,
or interpolate any new pixels.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageOps


ROOT = Path(__file__).resolve().parents[1]
CELL_WIDTH = 192
CELL_HEIGHT = 208
COLUMNS = 8
ROWS = 11
EXPECTED_SIZE = (CELL_WIDTH * COLUMNS, CELL_HEIGHT * ROWS)
HAIR_FRAME = 64
HEAD_COLUMNS = (0, 32, 64, 96, 128, 160)
HEAD_SCALES = (3, 3.5, 4)
HAIR_INDEX_FOR_HEAD = {0: 0, 32: 0, 64: 2, 96: 6, 128: 4, 160: 4}
# An Isaac head tile is 32px with its visible art starting a few rows down; the Golden
# Locks frame carries its face opening 17px from the top.  The hair must be scaled with
# the head it lands on, otherwise the head grows past the hair and the two no longer match.
HEAD_TILE = 32
HAIR_REGISTRATION = 17
HEAD_VISIBLE_WIDTH = 28
# A cell whose head cannot be identified this confidently borrows the dominant head of
# its own animation row, so one pose never changes locks mid-animation.
CONFIDENT_MATCH = 0.9
SHEET_BACKGROUND = (38, 38, 45, 255)


def rgba_bytes(image: Image.Image) -> bytes:
    return image.convert("RGBA").tobytes()


def matching_score(target: Image.Image, candidate: Image.Image, x: int, y: int) -> float:
    """Return an exact-pixel score over opaque candidate pixels."""
    if x < 0 or y < 0 or x + candidate.width > target.width or y + candidate.height > target.height:
        return -1.0
    region = target.crop((x, y, x + candidate.width, y + candidate.height))
    candidate_pixels = candidate.load()
    region_pixels = region.load()
    matches = 0
    total = 0
    for py in range(candidate.height):
        for px in range(candidate.width):
            pixel = candidate_pixels[px, py]
            if pixel[3] == 0:
                continue
            total += 1
            if region_pixels[px, py] == pixel:
                matches += 1
    return matches / total if total else -1.0


def blurred_score(target: Image.Image, candidate: Image.Image, x: int, y: int) -> float:
    """Score a placement on area-averaged downscales.

    The approved walking rows were rebuilt by resampling, so their head pixels no longer
    line up exactly with any source tile.  Comparing 4×-averaged blocks keeps the head
    identifiable where exact pixels would fail.
    """
    if x < 0 or y < 0 or x + candidate.width > target.width or y + candidate.height > target.height:
        return -1.0
    region = target.crop((x, y, x + candidate.width, y + candidate.height))
    left = Image.new("RGBA", region.size, SHEET_BACKGROUND)
    left.alpha_composite(region)
    right = Image.new("RGBA", candidate.size, SHEET_BACKGROUND)
    right.alpha_composite(candidate)
    size = (max(1, candidate.width // 4), max(1, candidate.height // 4))
    left = left.resize(size, Image.Resampling.BOX).convert("RGB")
    right = right.resize(size, Image.Resampling.BOX).convert("RGB")
    histogram = ImageChops.difference(left, right).convert("L").histogram()
    mean = sum(value * count for value, count in enumerate(histogram)) / sum(histogram)
    return 1.0 - mean / 255.0


def find_head_anchor(
    target: Image.Image,
    isaac_source: Image.Image,
    sources: tuple[int, ...] = HEAD_COLUMNS,
    scales: tuple[float, ...] = HEAD_SCALES,
) -> dict[str, object]:
    """Locate the closest supplied Isaac head in one final atlas cell.

    Sprites were historically assembled from 3×, 3.5× and 4× source pixels, and the
    leftward poses mirror their head.  Every combination is scored on blurred blocks to
    survive resampled art, and the visible head top is read from the cell's own
    silhouette, so only a small vertical window around it has to be searched.  Restricting
    `sources`/`scales` re-anchors one already chosen head, which is what a snapped cell
    needs so its hair registration follows the head it ends up wearing.
    """
    sprite = target.getbbox()
    sprite_top = sprite[1] if sprite else 0
    best: dict[str, object] = {
        "blurred": -1.0,
        "source_x": sources[0],
        "scale": scales[0],
        "x": 0,
        "y": 0,
        "mirrored": False,
    }
    for source_x in sources:
        raw = isaac_source.crop((source_x, 0, source_x + HEAD_TILE, HEAD_TILE))
        inset = (raw.getbbox() or (0, 0, HEAD_TILE, HEAD_TILE))[1]
        for scale in scales:
            size = int(round(HEAD_TILE * scale))
            candidate = raw.resize((size, size), Image.Resampling.NEAREST)
            for mirrored in (False, True):
                option = ImageOps.mirror(candidate) if mirrored else candidate
                x = (CELL_WIDTH - option.width) // 2
                base_y = sprite_top - int(round(inset * scale))
                for y in range(base_y - 4, base_y + 5):
                    score = blurred_score(target, option, x, y)
                    if score > best["blurred"]:
                        best = {
                            "blurred": score,
                            "source_x": source_x,
                            "scale": scale,
                            "x": x,
                            "y": y,
                            "mirrored": mirrored,
                        }
    best["exact"] = matching_score(
        target,
        head_candidate(isaac_source, best["source_x"], best["scale"], best["mirrored"]),
        best["x"],
        best["y"],
    )
    return best


def head_candidate(
    isaac_source: Image.Image,
    source_x: int,
    scale: float,
    mirrored: bool = False,
) -> Image.Image:
    size = int(round(HEAD_TILE * scale))
    tile = isaac_source.crop((source_x, 0, source_x + HEAD_TILE, HEAD_TILE))
    candidate = tile.resize((size, size), Image.Resampling.NEAREST)
    return ImageOps.mirror(candidate) if mirrored else candidate


def lock_layout(row: int, column: int, source_x: int) -> tuple[int, bool]:
    """Return the Golden Locks frame for one head and whether to mirror it.

    Frames 2 and 6 are the profile locks: frame 2 hangs its lock to the left, behind a
    right-facing head, and frame 6 hangs it to the right, behind a left-facing head.
    Both are taken exactly as authored — mirroring a frame drapes its lock and bow over
    the face instead of leaving them at the back of the head.
    """
    left_facing = row == 2 or (row == 10 and column >= 1)
    if source_x in (64, 96):
        return (6, False) if left_facing else (2, False)
    return HAIR_INDEX_FOR_HEAD[source_x], left_facing


def make_contact_sheet(atlas: Image.Image, output: Path) -> None:
    background = Image.new("RGBA", atlas.size, (38, 38, 45, 255))
    background.alpha_composite(atlas)
    preview = background.resize((atlas.width // 2, atlas.height // 2), Image.Resampling.NEAREST)
    output.parent.mkdir(parents=True, exist_ok=True)
    preview.save(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-atlas", type=Path, default=ROOT / "Resources/spritesheet.webp")
    parser.add_argument("--isaac-source", type=Path, default=ROOT / "Assets/Source/isaac-character-sheet.png")
    parser.add_argument("--hair-source", type=Path, default=ROOT / "Assets/Source/agents/magdalene-golden-locks.png")
    parser.add_argument("--output", type=Path, default=ROOT / "Resources/Agents/magdalene-spritesheet.webp")
    parser.add_argument("--contact-sheet", type=Path, default=ROOT / "qa/magdalene-derived-contact-sheet.png")
    parser.add_argument("--manifest", type=Path, default=ROOT / "qa/magdalene-derived-atlas.json")
    args = parser.parse_args()

    base = Image.open(args.base_atlas).convert("RGBA")
    isaac_source = Image.open(args.isaac_source).convert("RGBA")
    hair_source = Image.open(args.hair_source).convert("RGBA")
    if base.size != EXPECTED_SIZE:
        raise SystemExit(f"base atlas must be {EXPECTED_SIZE[0]}x{EXPECTED_SIZE[1]}, got {base.size}")
    if isaac_source.size != (512, 512):
        raise SystemExit(f"Isaac source must be 512x512, got {isaac_source.size}")
    if hair_source.size != (512, 64):
        raise SystemExit(f"Golden Locks source must be 512x64, got {hair_source.size}")

    derived = base.copy()
    cells: list[tuple[int, int, tuple[int, int], Image.Image, dict[str, object]]] = []
    for row in range(ROWS):
        for column in range(COLUMNS):
            origin = (column * CELL_WIDTH, row * CELL_HEIGHT)
            cell = base.crop((origin[0], origin[1], origin[0] + CELL_WIDTH, origin[1] + CELL_HEIGHT))
            if cell.getbbox() is None:
                continue
            cells.append((row, column, origin, cell, find_head_anchor(cell, isaac_source)))

    # One animation row shows one character, so a pose whose head cannot be identified
    # confidently borrows the row's dominant head instead of inventing its own locks.
    dominant: dict[int, tuple[int, float]] = {}
    for row in range(ROWS):
        totals: dict[tuple[int, float], float] = {}
        for cell_row, _column, _origin, _cell, anchor in cells:
            if cell_row != row:
                continue
            key = (anchor["source_x"], anchor["scale"])
            totals[key] = totals.get(key, 0.0) + anchor["blurred"]
        if totals:
            dominant[row] = max(totals, key=lambda key: totals[key])

    applications: list[dict[str, object]] = []
    low_confidence: list[dict[str, object]] = []
    for row, column, origin, cell, anchor in cells:
        snapped = anchor["blurred"] < CONFIDENT_MATCH
        source_x, scale = dominant[row] if snapped else (anchor["source_x"], anchor["scale"])
        if snapped:
            # The row's head replaces this cell's own match, so its vertical anchor has
            # to be found again: the previous y belonged to another tile's inset/scale.
            anchor = find_head_anchor(cell, isaac_source, sources=(source_x,), scales=(scale,))
        head_y = anchor["y"]
        hair_index, mirrored = lock_layout(row, column, source_x)
        hair = hair_source.crop((hair_index * HAIR_FRAME, 0, (hair_index + 1) * HAIR_FRAME, HAIR_FRAME))
        if mirrored:
            hair = ImageOps.mirror(hair)
        # Scale the locks with the head they land on: a 3× lock frame on a 4× head
        # leaves the head wider than the hair, which reads as a bare Isaac head.
        hair_size = int(round(HAIR_FRAME * scale))
        hair = hair.resize((hair_size, hair_size), Image.Resampling.NEAREST)
        hair_x = (CELL_WIDTH - hair_size) // 2
        # Align the frame's face registration to the matched head's visible top.
        head_tile = isaac_source.crop((source_x, 0, source_x + HEAD_TILE, HEAD_TILE))
        inset = (head_tile.getbbox() or (0, 0, HEAD_TILE, HEAD_TILE))[1]
        visible_top = head_y + inset * scale
        hair_y = int(round(visible_top - HAIR_REGISTRATION * scale))

        # The scaled frame is wider than a cell, so stage it on a padded canvas and
        # crop back to the cell: the locks stay centred and nothing bleeds sideways.
        pad = CELL_WIDTH
        stage = Image.new(
            "RGBA",
            (CELL_WIDTH + 2 * pad, CELL_HEIGHT + 2 * pad),
            (0, 0, 0, 0),
        )
        stage.alpha_composite(hair, (pad + hair_x, pad + hair_y))
        overlay = stage.crop((pad, pad, pad + CELL_WIDTH, pad + CELL_HEIGHT))
        derived.alpha_composite(overlay, origin)

        # The locks have to be wider than the head they sit on and stay inside the
        # cell, otherwise the composite reads as a bare head with a hair patch.
        frame_box = hair.getbbox() or (0, 0, hair_size, hair_size)
        hair_left = hair_x + frame_box[0]
        hair_right = hair_x + frame_box[2]
        hair_top = hair_y + frame_box[1]
        hair_bottom = hair_y + frame_box[3]
        inside_cell = (
            0 <= hair_left and hair_right <= CELL_WIDTH
            and 0 <= hair_top and hair_bottom <= CELL_HEIGHT
        )
        application = {
            "row": row,
            "column": column,
            "head_match_score": round(anchor["blurred"], 4),
            "head_pixel_score": round(anchor["exact"], 4),
            "head_snapped_to_row": snapped,
            "isaac_head_source_x": source_x,
            "source_scale": scale,
            "golden_locks_frame": hair_index,
            "mirrored": mirrored,
            "hair_size": [hair_size, hair_size],
            "hair_offset": [hair_x, hair_y],
            "hair_bbox": [hair_left, hair_top, hair_right, hair_bottom],
            "hair_covers_head": (
                inside_cell
                and (hair_right - hair_left) >= HEAD_VISIBLE_WIDTH * scale
                and hair_top <= head_y + HEAD_TILE * scale
                and hair_bottom >= head_y
            ),
        }
        applications.append(application)
        if snapped:
            low_confidence.append(application)

    if derived.size != EXPECTED_SIZE:
        raise SystemExit("derived atlas dimensions changed unexpectedly")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    derived.save(args.output, lossless=True, quality=100)
    reloaded = Image.open(args.output).convert("RGBA")
    if reloaded.size != EXPECTED_SIZE:
        raise SystemExit("encoded WebP dimensions are invalid")

    make_contact_sheet(reloaded, args.contact_sheet)
    # Every lock overlay has to beat its head match, sit inside the cell and be wider
    # than the head it covers; a bare head with a hair patch fails the build.
    coverage_failures = [item for item in applications if not item["hair_covers_head"]]
    manifest = {
        "ok": not coverage_failures,
        "algorithm": "approved Isaac atlas plus exact user-provided Golden Locks overlay",
        "output": str(args.output.relative_to(ROOT)),
        "size": list(reloaded.size),
        "sources": [
            str(args.base_atlas.relative_to(ROOT)),
            str(args.isaac_source.relative_to(ROOT)),
            str(args.hair_source.relative_to(ROOT)),
        ],
        "occupied_cells": len(applications),
        "low_confidence_head_matches": low_confidence,
        "hair_coverage_failures": coverage_failures,
        "applications": applications,
        "contact_sheet": str(args.contact_sheet.relative_to(ROOT)),
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Derived: {args.output}")
    print(f"Contact sheet: {args.contact_sheet}")
    print(f"Occupied cells: {len(applications)}; low-confidence anchors: {len(low_confidence)}")
    if coverage_failures:
        raise SystemExit(
            f"{len(coverage_failures)} cells have hair that does not cover its head"
        )


if __name__ == "__main__":
    main()
