#!/usr/bin/env python3
"""Convert the platform-shared Isaac atlases (WebP) into PNG assets for the
Windows (WPF) build, which decodes PNG natively without extra codecs.

Usage:
    python Windows/scripts/convert_assets.py

Reads from the repository root:
    Resources/spritesheet.webp
    Resources/shooting-atlas.webp
    Resources/walking-vertical-atlas.webp
    Resources/IsaacTear.png
    Resources/IsaacPet.png
    Resources/StatusIsaac.png
    Resources/Agents/magdalene-spritesheet.webp
    Resources/Agents/judas-spritesheet.webp

Writes into Windows/IsaacPet.Windows/Assets/.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Resources"
OUT = ROOT / "Windows" / "IsaacPet.Windows" / "Assets"

CELL_W = 192
CELL_H = 208

WEBP_ATLASES = {
    "spritesheet.webp": (CELL_W * 8, CELL_H * 11),
    "shooting-atlas.webp": (CELL_W * 4, CELL_H),
    "walking-vertical-atlas.webp": (CELL_W * 4, CELL_H * 2),
}

OPTIONAL_ATLASES = {
    # 多角色图集：存在才转换，缺失时 Windows 端与 macOS 端一样回退为 Isaac。
    "Agents/magdalene-spritesheet.webp": (CELL_W * 8, CELL_H * 11),
    "Agents/judas-spritesheet.webp": (CELL_W * 8, CELL_H * 11),
}

PLAIN_COPIES = ["IsaacTear.png", "IsaacPet.png", "StatusIsaac.png"]


def convert_webp(source: Path, dest: Path, expected: tuple[int, int]) -> None:
    image = Image.open(source).convert("RGBA")
    if image.size != expected:
        raise SystemExit(
            f"{source.name}: 尺寸错误 {image.size[0]}x{image.size[1]}，"
            f"期望 {expected[0]}x{expected[1]}"
        )
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, optimize=True)
    print(f"ok  {source.relative_to(ROOT)} -> {dest.relative_to(ROOT)} ({image.size[0]}x{image.size[1]})")


def build_icon(source: Path, dest: Path) -> None:
    image = Image.open(source).convert("RGBA")
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (256, 256)])
    print(f"ok  {source.relative_to(ROOT)} -> {dest.relative_to(ROOT)} (multi-size ico)")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    for name, expected in WEBP_ATLASES.items():
        convert_webp(RESOURCES / name, OUT / (Path(name).stem + ".png"), expected)

    for name, expected in OPTIONAL_ATLASES.items():
        source = RESOURCES / name
        if not source.exists():
            print(f"skip  {name}（未安装，菜单项将保持禁用）")
            continue
        dest = OUT / source.parent.name / (source.stem + ".png")
        convert_webp(source, dest, expected)

    for name in PLAIN_COPIES:
        source = RESOURCES / name
        shutil.copyfile(source, OUT / name)
        print(f"ok  {name}（直接复制）")

    build_icon(RESOURCES / "IsaacPet.png", OUT / "IsaacPet.ico")
    return 0


if __name__ == "__main__":
    sys.exit(main())
