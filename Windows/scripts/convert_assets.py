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
    Resources/Agents/<role>-spritesheet.webp（自动发现，如 magdalene / cain / judas…）
    Resources/Agents/<role>-shooting-atlas.webp
    Resources/Agents/<role>-walking-vertical-atlas.webp
    Resources/Agents/<role>-raising-atlas.webp

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
    # 竖向行走循环重建后为 8 列（原 4 列）。
    "walking-vertical-atlas.webp": (CELL_W * 8, CELL_H * 2),
    # 举卡抽牌姿势辅助图集。
    "raising-atlas.webp": (CELL_W * 8, CELL_H),
}

# 角色专属图集按文件名后缀确定期望尺寸；存在才转换，缺失时两端一样回退为 Isaac。
AGENT_SUFFIX_SIZES = {
    "-spritesheet.webp": (CELL_W * 8, CELL_H * 11),
    "-shooting-atlas.webp": (CELL_W * 4, CELL_H),
    "-walking-vertical-atlas.webp": (CELL_W * 8, CELL_H * 2),
    "-raising-atlas.webp": (CELL_W * 8, CELL_H),
}

# 塔罗卡面 HUD 图标（含卡背），直接复制进 Assets/Cards。
CARD_ICONS = "Cards"
CARD_PLAIN_COPIES = ["Cards/CardBack.png"] + [
    f"Cards/Tarot{index:02d}.png" for index in range(22)
] + [f"Cards/TarotReversed{index:02d}.png" for index in range(22)]

# 菜单分组根项的像素图标（动作/对话/任务/设置）。
MENU_ICON_COPIES = [f"MenuIcons/{name}.png" for name in ("Action", "Chat", "Tasks", "Settings")]

PLAIN_COPIES = ["IsaacTear.png", "IsaacTearDrop.png", "EmoteHappy.png", "EmoteSad.png", "EmoteShocked.png", "IsaacPet.png", "StatusIsaac.png"]


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

    agents = RESOURCES / "Agents"
    if agents.is_dir():
        for source in sorted(agents.glob("*.webp")):
            # Match on the suffix after the role id, e.g. "cain-shooting-atlas.webp".
            suffix = "-" + source.stem.split("-", 1)[1] + source.suffix if "-" in source.stem else ""
            expected = AGENT_SUFFIX_SIZES.get(suffix)
            if expected is None:
                print(f"skip  Agents/{source.name}（未知后缀）")
                continue
            dest = OUT / agents.name / (source.stem + ".png")
            convert_webp(source, dest, expected)

    for name in PLAIN_COPIES:
        source = RESOURCES / name
        shutil.copyfile(source, OUT / name)
        print(f"ok  {name}（直接复制）")

    for name in CARD_PLAIN_COPIES:
        source = RESOURCES / name
        if not source.exists():
            print(f"skip  {name}（未安装）")
            continue
        dest = OUT / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        print(f"ok  {name}（直接复制）")

    for name in MENU_ICON_COPIES:
        source = RESOURCES / name
        if not source.exists():
            print(f"skip  {name}（未安装）")
            continue
        dest = OUT / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        print(f"ok  {name}（直接复制）")

    build_icon(RESOURCES / "IsaacPet.png", OUT / "IsaacPet.ico")
    return 0


if __name__ == "__main__":
    sys.exit(main())
