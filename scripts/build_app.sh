#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

if [ "${ISAAC_REGENERATE_ASSETS:-0}" = "1" ] || [ ! -f Resources/spritesheet.webp ] || [ ! -f Resources/shooting-atlas.webp ] || [ ! -f Resources/walking-vertical-atlas.webp ] || [ ! -f Resources/IsaacPet.icns ] || [ ! -f Resources/IsaacTear.png ]; then
  PYTHON=${ISAAC_PYTHON:-python3}
  if ! "$PYTHON" -c 'import PIL' 2>/dev/null; then
    echo "Asset regeneration requires Pillow. Set ISAAC_PYTHON and PYTHONPATH if it is installed in a custom environment." >&2
    exit 1
  fi
  "$PYTHON" scripts/generate_assets.py
fi
swift build -c release --product IsaacPet

BIN=$(swift build -c release --show-bin-path)/IsaacPet
APP="$ROOT/dist/Isaac Pet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/IsaacPet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/spritesheet.webp Resources/shooting-atlas.webp Resources/walking-vertical-atlas.webp Resources/StatusIsaac.png Resources/IsaacPet.icns Resources/IsaacTear.png NOTICE.md "$APP/Contents/Resources/"

/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP"
echo "Built: $APP"
