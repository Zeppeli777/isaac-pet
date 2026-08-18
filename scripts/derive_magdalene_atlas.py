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

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
CELL_WIDTH = 192
CELL_HEIGHT = 208
COLUMNS = 8
ROWS = 11
EXPECTED_SIZE = (CELL_WIDTH * COLUMNS, CELL_HEIGHT * ROWS)
HEAD_COLUMNS = (0, 32, 64, 96, 128, 160)
HAIR_INDEX_FOR_HEAD = {0: 0, 32: 0, 64: 2, 96: 6, 128: 4, 160: 4}


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


def find_head_anchor(target: Image.Image, isaac_source: Image.Image) -> tuple[float, int, int, int, int]:
    """Locate the closest supplied Isaac head in one final atlas cell.

    Standard sprites were historically assembled from both 3× and 4× source pixels.
    The best exact match gives a stable vertical anchor for the source hair layer.
    """
    best = (-1.0, 0, 4, 32, 40)
    for source_x in HEAD_COLUMNS:
        raw = isaac_source.crop((source_x, 0, source_x + 32, 32))
        for scale in (3, 4):
            candidate = raw.resize((32 * scale, 32 * scale), Image.Resampling.NEAREST)
            x = (CELL_WIDTH - candidate.width) // 2
            for y in range(0, 110):
                score = matching_score(target, candidate, x, y)
                if score > best[0]:
                    best = (score, source_x, scale, x, y)
    return best


def is_left_mirrored(row: int, column: int) -> bool:
    # Row 2 is the approved left walk.  Direction slots 9–15 were built by mirroring
    # their canonical right-side source heads; slot 8 remains the non-mirrored down pose.
    return row == 2 or (row == 10 and column >= 1)


def golden_locks_frame(row: int, column: int, source_x: int) -> int:
    """Select the paired source lock frame for the mirrored leftward look family."""
    # The two profile locks are asymmetric because the bow sits on one side.  In the
    # lower direction row, use their paired source art before mirroring so the bow and
    # face opening remain on the visible side instead of becoming a curtain over it.
    if row == 10 and source_x == 64:
        return 6
    if row == 10 and source_x == 96:
        return 2
    return HAIR_INDEX_FOR_HEAD[source_x]


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
    applications: list[dict[str, object]] = []
    low_confidence: list[dict[str, object]] = []
    for row in range(ROWS):
        for column in range(COLUMNS):
            origin = (column * CELL_WIDTH, row * CELL_HEIGHT)
            cell = base.crop((origin[0], origin[1], origin[0] + CELL_WIDTH, origin[1] + CELL_HEIGHT))
            if cell.getbbox() is None:
                continue

            score, source_x, scale, _head_x, head_y = find_head_anchor(cell, isaac_source)
            hair_index = golden_locks_frame(row, column, source_x)
            hair = hair_source.crop((hair_index * 64, 0, (hair_index + 1) * 64, 64))
            mirrored = is_left_mirrored(row, column)
            if mirrored:
                hair = ImageOps.mirror(hair)
            hair = hair.resize((CELL_WIDTH, CELL_WIDTH), Image.Resampling.NEAREST)

            # The 64px Golden Locks frame has its face registration 17px from the top;
            # align it to the matched 32px Isaac head's visible top (2px inset).
            hair_y = head_y + 2 * scale - 17 * 3
            overlay = Image.new("RGBA", (CELL_WIDTH, CELL_HEIGHT), (0, 0, 0, 0))
            overlay.alpha_composite(hair, (0, hair_y))
            derived.alpha_composite(overlay, origin)

            application = {
                "row": row,
                "column": column,
                "head_match_score": round(score, 4),
                "isaac_head_source_x": source_x,
                "source_scale": scale,
                "golden_locks_frame": hair_index,
                "mirrored": mirrored,
                "hair_y": hair_y,
            }
            applications.append(application)
            if score < 0.6:
                low_confidence.append(application)

    if derived.size != EXPECTED_SIZE:
        raise SystemExit("derived atlas dimensions changed unexpectedly")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    derived.save(args.output, lossless=True, quality=100)
    reloaded = Image.open(args.output).convert("RGBA")
    if reloaded.size != EXPECTED_SIZE:
        raise SystemExit("encoded WebP dimensions are invalid")

    make_contact_sheet(reloaded, args.contact_sheet)
    manifest = {
        "ok": True,
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
        "applications": applications,
        "contact_sheet": str(args.contact_sheet.relative_to(ROOT)),
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Derived: {args.output}")
    print(f"Contact sheet: {args.contact_sheet}")
    print(f"Occupied cells: {len(applications)}; low-confidence anchors: {len(low_confidence)}")


if __name__ == "__main__":
    main()
