#!/usr/bin/env python3
"""Derive desktop-pet atlases for the remaining regular characters.

Every approved Isaac pose is kept: the script locates the Isaac head inside each
occupied atlas cell (the same anchor search the Magdalene derivation uses), replaces
it with the matching head tile from the character's own player sheet and re-applies
that character's default costume pieces (eyepatch, fez, hair, horns) exactly where the
game's anm2 files put them.  Cells whose palette differs from Isaac's (Blue Baby, The
Lost, Keeper, Azazel, Lilith, The Forgotten) additionally get a deterministic body
recolor built by scanning the two player sheets pixel for pixel.  The custom crying
pose is pet-only art with no game counterpart, so that row is recolored instead of
re-headed.

This stays a source-art derivation: no pixels are invented, every sprite comes from
the character's own sheet in Assets/Source/game-sheets/.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageChops, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SHEETS = ROOT / "Assets" / "Source" / "game-sheets"
AGENTS = ROOT / "Resources" / "Agents"
QA = ROOT / "qa"

CELL_WIDTH = 192
CELL_HEIGHT = 208
COLUMNS = 8
ROWS = 11
EXPECTED_SIZE = (CELL_WIDTH * COLUMNS, CELL_HEIGHT * ROWS)
VERTICAL_WALK_COLUMNS = 8
VERTICAL_WALK_ROWS = 2
SHOOTING_COLUMNS = 4
RAISING_COLUMNS = 8
HEAD_TILE = 32
HEAD_SCALES = (3, 3.5, 4)
CONFIDENT_MATCH = 0.9
MIN_SNAPPED_SCORE = 0.55
SHEET_BACKGROUND = (38, 38, 45, 255)
# The pet's custom crying pose (main sheet row 5) has no game-sheet counterpart.
CRY_ROW = 5


@dataclass
class Costume:
    """One costume overlay aligned to the player-sheet head grid.

    `frames` maps an Isaac head tile x to the (xcrop, ycrop) of the costume frame the
    game's anm2 draws over that head; `mirrored_frames` names dedicated left-facing
    frames (used as authored, never re-mirrored).  `offset` places the frame relative
    to the head tile's top-left corner, derived from the anm2 pivots.
    """

    png: str
    size: tuple[int, int]
    offset: tuple[int, int]
    frames: dict[int, tuple[int, int]]
    mirrored_frames: dict[int, tuple[int, int]] = field(default_factory=dict)


@dataclass
class Role:
    id: str
    sheet: str
    # Roles whose head art lives in a costume animation instead of the sheet's top row.
    head_frames: dict[int, tuple[int, int]] | None = None
    head_size: tuple[int, int] = (HEAD_TILE, HEAD_TILE)
    head_offset: tuple[int, int] = (0, 0)
    # The player sheet the body recolor scans; defaults to `sheet`, which roles whose
    # head source is a costume animation (Azazel) point back at their base sheet.
    palette_sheet: str | None = None
    costumes: list[Costume] = field(default_factory=list)
    # An optional second figure (Esau) derived from the same cell and drawn behind.
    twin: "Role | None" = None
    twin_offset: tuple[int, int] = (0, 0)

    def sheet_image(self) -> Image.Image:
        return Image.open(SHEETS / self.sheet).convert("RGBA")

    def palette_image(self) -> Image.Image:
        return Image.open(SHEETS / (self.palette_sheet or self.sheet)).convert("RGBA")


EYEPATCH = Costume(
    png="character_003_cainseyepatch.png",
    size=(32, 32),
    offset=(0, 0),
    frames={0: (0, 0), 32: (32, 0), 64: (64, 0), 96: (96, 0), 128: (128, 0), 160: (160, 0)},
    mirrored_frames={64: (192, 0), 96: (224, 0)},
)
FEZ = Costume(
    png="character_004_judasfez.png",
    size=(32, 64),
    offset=(0, -16),
    frames={0: (0, 0), 32: (32, 0), 64: (192, 0), 96: (224, 0), 128: (128, 0), 160: (160, 0)},
    mirrored_frames={64: (64, 0), 96: (96, 0)},
)
EVE_HAIR = Costume(
    png="character_005_evehead.png",
    size=(64, 64),
    offset=(-16, -16),
    frames={0: (0, 0), 32: (64, 0), 64: (128, 0), 96: (192, 0), 128: (256, 0), 160: (320, 0)},
    mirrored_frames={64: (384, 0), 96: (448, 0)},
)
EDEN_HAIR = Costume(
    png="character_009_edenhair1.png",
    size=(64, 48),
    offset=(-16, -16),
    frames={0: (0, 0), 32: (64, 0), 64: (128, 0), 96: (192, 0), 128: (256, 0), 160: (320, 0)},
    mirrored_frames={64: (384, 0), 96: (448, 0)},
)
# The Repentance hair costumes share the Eve head's frame geometry (64x64 frames,
# pivot 32/44, YPosition -5).
BETH_HAIR = Costume(
    png="character_001x_bethshair.png",
    size=(64, 64),
    offset=(-16, -16),
    frames={0: (0, 0), 32: (64, 0), 64: (128, 0), 96: (192, 0), 128: (256, 0), 160: (320, 0)},
    mirrored_frames={64: (384, 0), 96: (448, 0)},
)
JACOB_HAIR = Costume(
    png="character_002x_jacobhair.png",
    size=(64, 64),
    offset=(-16, -16),
    frames={0: (0, 0), 32: (64, 0), 64: (128, 0), 96: (192, 0), 128: (256, 0), 160: (320, 0)},
    mirrored_frames={64: (384, 0), 96: (448, 0)},
)
ESAU_HAIR = Costume(
    png="character_003x_esauhair.png",
    size=(64, 64),
    offset=(-16, -16),
    frames={0: (0, 0), 32: (64, 0), 64: (128, 0), 96: (192, 0), 128: (256, 0), 160: (320, 0)},
    mirrored_frames={64: (384, 0), 96: (448, 0)},
)

# Jacob & Esau share every cell: Esau runs the same derivation on his own sheet and is
# composited behind Jacob at this offset, so the twins move in lockstep like in game.
TWIN_OFFSET = (-46, -4)

ROLES: list[Role] = [
    Role(id="cain", sheet="character_003_cain.png", costumes=[EYEPATCH]),
    Role(id="bluebaby", sheet="character_006_bluebaby.png"),
    Role(id="eve", sheet="character_005_eve.png", costumes=[EVE_HAIR]),
    Role(id="samson", sheet="character_007_samson.png"),
    Role(id="azazel",
         sheet="character_008_azazelhead.png",
         palette_sheet="character_008_azazel.png",
         head_frames={0: (0, 0), 32: (0, 0), 64: (0, 64), 96: (0, 64), 128: (0, 128), 160: (0, 128)},
         head_size=(64, 48),
         head_offset=(-16, -19)),
    Role(id="eden", sheet="character_009_eden.png", costumes=[EDEN_HAIR]),
    Role(id="lazarus", sheet="character_009_lazarus.png"),
    Role(id="thelost", sheet="character_012_thelost.png"),
    Role(id="lilith", sheet="character_014_lilith.png"),
    Role(id="keeper", sheet="character_015_keeper.png"),
    Role(id="apollyon", sheet="character_016_apollyon.png"),
    Role(id="theforgotten", sheet="character_017_theforgotten.png"),
    Role(id="bethany", sheet="character_001x_bethany.png", costumes=[BETH_HAIR]),
    Role(id="jacobesau",
         sheet="character_002x_jacob.png",
         costumes=[JACOB_HAIR],
         twin=Role(id="esau-twin", sheet="character_003x_esau.png", costumes=[ESAU_HAIR]),
         twin_offset=TWIN_OFFSET),
    Role(id="judas", sheet="character_004_judas.png", costumes=[FEZ]),
]


def rgba_bytes(image: Image.Image) -> bytes:
    return image.convert("RGBA").tobytes()


def blurred_score(target: Image.Image, candidate: Image.Image, x: int, y: int) -> float:
    """Score a placement on area-averaged downscales (see the Magdalene derivation)."""
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


def find_head_anchor(
    target: Image.Image,
    isaac_source: Image.Image,
    sources: tuple[int, ...] = (0, 32, 64, 96, 128, 160),
    scales: tuple[float, ...] = HEAD_SCALES,
) -> dict[str, object]:
    """Locate the closest supplied Isaac head in one atlas cell."""
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
        target, head_candidate(isaac_source, best["source_x"], best["scale"], best["mirrored"]),
        best["x"], best["y"],
    )
    return best


def head_candidate(
    isaac_source: Image.Image, source_x: int, scale: float, mirrored: bool = False
) -> Image.Image:
    size = int(round(HEAD_TILE * scale))
    tile = isaac_source.crop((source_x, 0, source_x + HEAD_TILE, HEAD_TILE))
    candidate = tile.resize((size, size), Image.Resampling.NEAREST)
    return ImageOps.mirror(candidate) if mirrored else candidate


def scaled(image: Image.Image, scale: float, mirrored: bool = False) -> Image.Image:
    size = (int(round(image.width * scale)), int(round(image.height * scale)))
    resized = image.resize(size, Image.Resampling.NEAREST)
    return ImageOps.mirror(resized) if mirrored else resized


def paste_staged(canvas: Image.Image, sprite: Image.Image, x: int, y: int, mask: Image.Image | None = None) -> None:
    """Composite through a padded stage so oversized sprites crop instead of shifting.

    When a mask canvas is given, the sprite's opaque footprint is stamped into it so the
    recolor step knows which pixels belong to the freshly pasted art.
    """
    pad = CELL_WIDTH
    stage = Image.new("RGBA", (canvas.width + 2 * pad, canvas.height + 2 * pad), (0, 0, 0, 0))
    stage.alpha_composite(sprite, (pad + x, pad + y))
    overlay = stage.crop((pad, pad, pad + canvas.width, pad + canvas.height))
    canvas.alpha_composite(overlay)
    if mask is not None:
        opaque = overlay.getchannel("A").point(lambda a: 255 if a else 0)
        mask.paste(255, (0, 0), opaque)


def build_palette_map(role: Role, isaac_source: Image.Image) -> dict[tuple[int, int, int], tuple[int, int, int]]:
    """Map Isaac's colors onto the role's by scanning both sheets below the head row.

    The player sheets share one layout, so the pixel at (x, y) on both sheets depicts
    the same body spot; their colors correspond one to one.  The head row is excluded:
    heads are replaced wholesale, and excluding it keeps Isaac's eye white and tear
    teals (which the body never uses) unmapped so they survive the recolor.
    """
    isaac = isaac_source
    other = role.palette_image()
    votes: dict[tuple[int, int, int], dict[tuple[int, int, int], int]] = {}
    isaac_pixels = isaac.load()
    other_pixels = other.load()
    for y in range(HEAD_TILE, isaac.height):
        for x in range(isaac.width):
            source = isaac_pixels[x, y]
            if source[3] == 0:
                continue
            target = other_pixels[x, y]
            key = source[:3]
            value = target[:3]
            bucket = votes.setdefault(key, {})
            bucket[value] = bucket.get(value, 0) + 1
    mapping = {key: max(bucket.items(), key=lambda item: item[1])[0] for key, bucket in votes.items()}
    # The pet art draws its outline with two near-black inks; the game sheets only
    # ship one, so the second follows the first.
    if (8, 0, 0) in mapping:
        mapping.setdefault((9, 0, 0), mapping[(8, 0, 0)])
    return mapping


def remap_cell(
    cell: Image.Image,
    mapping: dict[tuple[int, int, int], tuple[int, int, int]],
    mask: Image.Image | None = None,
) -> Image.Image:
    """Recolor the cell's Isaac-palette pixels through the role's palette map.

    Pixels covered by a pasted head or costume are their own source art and never
    touched.  Everything else goes through the map; colors a few units off the sheet
    palette (the vertical walk cycle was rebuilt by resampling) follow their closest
    mapped key so recolored bodies do not keep pink freckles.  The 55-unit tolerance
    only reaches resample noise of the shared body ramp — deliberately distinct colors
    (hair, bandana, demon red) sit far beyond it and pass through untouched.
    """
    keys = list(mapping)
    tolerance = 55.0
    pixels = cell.load()
    mask_pixels = mask.load() if mask is not None else None
    for y in range(cell.height):
        for x in range(cell.width):
            pixel = pixels[x, y]
            if pixel[3] == 0:
                continue
            if mask_pixels is not None and mask_pixels[x, y]:
                continue
            mapped = mapping.get(pixel[:3])
            if mapped is None:
                best_distance = tolerance * tolerance
                for key in keys:
                    distance = sum((pixel[index] - key[index]) ** 2 for index in range(3))
                    if distance <= best_distance:
                        best_distance = distance
                        mapped = mapping[key]
            if mapped is not None:
                pixels[x, y] = (mapped[0], mapped[1], mapped[2], pixel[3])
    return cell


def role_head(
    role: Role, sheet: Image.Image, source_x: int, scale: float, mirrored: bool
) -> tuple[Image.Image, tuple[int, int]]:
    """Return the role's head sprite for one Isaac head tile plus its paste offset."""
    if role.head_frames is not None:
        xcrop, ycrop = role.head_frames[source_x]
        tile = sheet.crop((xcrop, ycrop, xcrop + role.head_size[0], ycrop + role.head_size[1]))
        return scaled(tile, scale, mirrored), (
            int(round(role.head_offset[0] * scale)),
            int(round(role.head_offset[1] * scale)),
        )
    tile = sheet.crop((source_x, 0, source_x + HEAD_TILE, HEAD_TILE))
    return scaled(tile, scale, mirrored), (0, 0)


def costume_frame(
    costume: Costume, source_x: int, mirrored: bool
) -> tuple[Image.Image, tuple[int, int], bool] | None:
    """Return the costume tile for one head tile plus its offset and mirroring flag.

    Profile tiles (64/96) have dedicated pre-mirrored left-facing frames, so a
    left-facing profile uses them as authored; every other mirrored tile just mirrors
    the normal frame, which is what the game does outside the profile animations.
    """
    if mirrored and source_x in costume.mirrored_frames:
        xcrop, ycrop = costume.mirrored_frames[source_x]
        should_mirror = False
    else:
        if source_x not in costume.frames:
            return None
        xcrop, ycrop = costume.frames[source_x]
        should_mirror = mirrored
    source = Image.open(SHEETS / costume.png).convert("RGBA")
    tile = source.crop((xcrop, ycrop, xcrop + costume.size[0], ycrop + costume.size[1]))
    return tile, costume.offset, should_mirror


def render_cell(
    cell: Image.Image,
    role: Role,
    anchor: dict[str, object],
    source_x: int,
    scale: float,
    mapping: dict[tuple[int, int, int], tuple[int, int, int]],
) -> tuple[Image.Image, list[str], float]:
    """Re-head one cell for one role; returns the cell, costume names and match score."""
    sheet = role.sheet_image()
    mirrored = bool(anchor["mirrored"])
    mask = Image.new("L", (cell.width, cell.height), 0)
    head, head_offset = role_head(role, sheet, source_x, scale, mirrored)
    paste_staged(cell, head, anchor["x"] + head_offset[0], anchor["y"] + head_offset[1], mask)
    costume_applications = []
    score = float(anchor["blurred"])
    for costume in role.costumes:
        entry = costume_frame(costume, source_x, mirrored)
        if entry is None:
            continue
        tile, offset, should_mirror = entry
        sprite = scaled(tile, scale, should_mirror)
        paste_staged(
            cell,
            sprite,
            anchor["x"] + int(round(offset[0] * scale)),
            anchor["y"] + int(round(offset[1] * scale)),
            mask,
        )
        costume_applications.append(costume.png)
    remap_cell(cell, mapping, mask)
    return cell, costume_applications, score


def derive_atlas(
    base: Image.Image,
    role: Role,
    isaac_source: Image.Image,
    rows: int,
    columns: int,
    skip_head_rows: set[int],
) -> tuple[Image.Image, list[dict[str, object]], list[dict[str, object]]]:
    """Re-head every occupied cell of one Isaac atlas for one role."""
    derived = base.copy()
    mapping = build_palette_map(role, isaac_source)
    twin_mapping = build_palette_map(role.twin, isaac_source) if role.twin else None
    cells: list[tuple[int, int, Image.Image, dict[str, object]]] = []
    for row in range(rows):
        for column in range(columns):
            origin = (column * CELL_WIDTH, row * CELL_HEIGHT)
            cell = base.crop((origin[0], origin[1], origin[0] + CELL_WIDTH, origin[1] + CELL_HEIGHT))
            if cell.getbbox() is None:
                continue
            anchor = None if row in skip_head_rows else find_head_anchor(cell, isaac_source)
            cells.append((row, column, cell, anchor))

    dominant: dict[int, tuple[int, float]] = {}
    for row in range(rows):
        totals: dict[tuple[int, float], float] = {}
        for cell_row, _column, _cell, anchor in cells:
            if cell_row != row or anchor is None:
                continue
            key = (anchor["source_x"], anchor["scale"])
            totals[key] = totals.get(key, 0.0) + anchor["blurred"]
        if totals:
            dominant[row] = max(totals, key=lambda key: totals[key])

    applications: list[dict[str, object]] = []
    failures: list[dict[str, object]] = []
    for row, column, cell, anchor in cells:
        origin = (column * CELL_WIDTH, row * CELL_HEIGHT)
        if anchor is None:
            remap_cell(cell, mapping)
            if twin_mapping is not None:
                remap_cell(cell, twin_mapping)
            derived.alpha_composite(cell, origin)
            applications.append({
                "row": row,
                "column": column,
                "mode": "recolored",
            })
            continue
        snapped = anchor["blurred"] < CONFIDENT_MATCH
        source_x, scale = dominant[row] if snapped else (anchor["source_x"], anchor["scale"])
        if snapped:
            anchor = find_head_anchor(cell, isaac_source, sources=(source_x,), scales=(scale,))
        main, costumes, score = render_cell(cell.copy(), role, anchor, source_x, scale, mapping)
        if role.twin is not None and twin_mapping is not None:
            twin, _twin_costumes, _twin_score = render_cell(
                cell.copy(), role.twin, anchor, source_x, scale, twin_mapping
            )
            staged = Image.new("RGBA", (CELL_WIDTH, CELL_HEIGHT), (0, 0, 0, 0))
            staged.alpha_composite(twin, role.twin_offset)
            staged.alpha_composite(main, (0, 0))
            main = staged
        derived.alpha_composite(main, origin)
        application = {
            "row": row,
            "column": column,
            "mode": "reheaded",
            "isaac_head_source_x": source_x,
            "scale": scale,
            "mirrored": bool(anchor["mirrored"]),
            "head_match_score": round(score, 4),
            "head_snapped_to_row": snapped,
            "costumes": costumes,
        }
        applications.append(application)
        if snapped and score < MIN_SNAPPED_SCORE:
            failures.append(application)
    return derived, applications, failures


def make_contact_sheet(atlas: Image.Image, output: Path) -> None:
    background = Image.new("RGBA", atlas.size, SHEET_BACKGROUND)
    background.alpha_composite(atlas)
    preview = background.resize((atlas.width // 2, atlas.height // 2), Image.Resampling.NEAREST)
    output.parent.mkdir(parents=True, exist_ok=True)
    preview.save(output)


def derive_role(role: Role, isaac_source: Image.Image) -> dict[str, object]:
    atlas_jobs = {
        "spritesheet": (ROOT / "Resources/spritesheet.webp", ROWS, COLUMNS, {CRY_ROW}),
        "shooting_atlas": (ROOT / "Resources/shooting-atlas.webp", 1, SHOOTING_COLUMNS, set()),
        "walking_vertical_atlas": (
            ROOT / "Resources/walking-vertical-atlas.webp", VERTICAL_WALK_ROWS, VERTICAL_WALK_COLUMNS, set()
        ),
        "raising_atlas": (ROOT / "Resources/raising-atlas.webp", 1, RAISING_COLUMNS, set()),
    }
    result: dict[str, object] = {"role": role.id, "sheet": role.sheet, "atlases": {}}
    for name, (source_path, rows, columns, skip_rows) in atlas_jobs.items():
        base = Image.open(source_path).convert("RGBA")
        expected = (CELL_WIDTH * columns, CELL_HEIGHT * rows)
        if base.size != expected:
            raise SystemExit(f"{name} must be {expected[0]}x{expected[1]}, got {base.size}")
        derived, applications, failures = derive_atlas(base, role, isaac_source, rows, columns, skip_rows)
        output = AGENTS / f"{role.id}-{name.replace('_', '-')}.webp"
        AGENTS.mkdir(parents=True, exist_ok=True)
        derived.save(output, lossless=True, quality=100, exact=True)
        reloaded = Image.open(output).convert("RGBA")
        if rgba_bytes(reloaded) != rgba_bytes(derived):
            raise SystemExit(f"{output.name} did not round-trip losslessly")
        contact = QA / f"{role.id}-{name.replace('_', '-')}-contact.png"
        make_contact_sheet(reloaded, contact)
        result["atlases"][name] = {
            "path": str(output.relative_to(ROOT)),
            "size": list(reloaded.size),
            "occupied_cells": len(applications),
            "recolored_only_cells": sum(1 for a in applications if a["mode"] == "recolored"),
            "failures": failures,
            "contact_sheet": str(contact.relative_to(ROOT)),
        }
        result.setdefault("failures", []).extend(
            {**failure, "atlas": name} for failure in failures
        )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--isaac-source", type=Path, default=ROOT / "Assets/Source/isaac-character-sheet.png")
    parser.add_argument("--roles", nargs="*", default=None, help="subset of role ids to derive")
    parser.add_argument("--manifest", type=Path, default=QA / "role-atlases-manifest.json")
    args = parser.parse_args()

    isaac_source = Image.open(args.isaac_source).convert("RGBA")
    if isaac_source.size != (512, 512):
        raise SystemExit(f"Isaac source must be 512x512, got {isaac_source.size}")

    roles = ROLES if not args.roles else [r for r in ROLES if r.id in args.roles]
    unknown = set(args.roles or []) - {r.id for r in ROLES}
    if unknown:
        raise SystemExit(f"unknown roles: {sorted(unknown)}")

    results = []
    for role in roles:
        result = derive_role(role, isaac_source)
        results.append(result)
        failures = result["failures"]
        print(
            f"{role.id}: {sum(a['occupied_cells'] for a in result['atlases'].values())} cells "
            f"({sum(a['recolored_only_cells'] for a in result['atlases'].values())} recolor-only), "
            f"{len(failures)} failures"
        )
        if failures:
            for failure in failures:
                print(f"  FAIL {failure['atlas']} row {failure['row']} col {failure['column']} "
                      f"score {failure['head_match_score']}")

    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    ok = not any(result["failures"] for result in results)
    args.manifest.write_text(
        json.dumps({"ok": ok, "roles": results}, ensure_ascii=False, indent=2) + "\n"
    )
    if not ok:
        raise SystemExit("some cells could not be re-headed confidently; see the manifest")
    print(f"Manifest: {args.manifest}")


if __name__ == "__main__":
    main()
