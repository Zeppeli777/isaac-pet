#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="${1:-$ROOT/dist/Isaac Pet.app}"

[ -d "$APP" ] || { echo "Missing app: $APP" >&2; exit 1; }
[ -x "$APP/Contents/MacOS/IsaacPet" ] || { echo "Missing executable" >&2; exit 1; }
[ -f "$APP/Contents/Resources/spritesheet.webp" ] || { echo "Missing atlas" >&2; exit 1; }
[ -f "$APP/Contents/Resources/shooting-atlas.webp" ] || { echo "Missing shooting atlas" >&2; exit 1; }
[ -f "$APP/Contents/Resources/walking-vertical-atlas.webp" ] || { echo "Missing vertical walking atlas" >&2; exit 1; }
[ -f "$APP/Contents/Resources/IsaacTear.png" ] || { echo "Missing Isaac tear projectile" >&2; exit 1; }
/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist" | grep -Fx 'com.fanmade.isaacpet'
/usr/bin/plutil -extract LSUIElement raw -o - "$APP/Contents/Info.plist" | grep -Fx 'true'
/usr/bin/codesign --verify --deep --strict "$APP"
WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/spritesheet.webp" | awk '/pixelWidth/ {print $2}')
HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/spritesheet.webp" | awk '/pixelHeight/ {print $2}')
[ "$WIDTH" = "1536" ] && [ "$HEIGHT" = "2288" ] || { echo "Unexpected atlas size: ${WIDTH}x${HEIGHT}" >&2; exit 1; }
SHOOT_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/shooting-atlas.webp" | awk '/pixelWidth/ {print $2}')
SHOOT_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/shooting-atlas.webp" | awk '/pixelHeight/ {print $2}')
[ "$SHOOT_WIDTH" = "768" ] && [ "$SHOOT_HEIGHT" = "208" ] || { echo "Unexpected shooting atlas size: ${SHOOT_WIDTH}x${SHOOT_HEIGHT}" >&2; exit 1; }
VERTICAL_WALK_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/walking-vertical-atlas.webp" | awk '/pixelWidth/ {print $2}')
VERTICAL_WALK_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/walking-vertical-atlas.webp" | awk '/pixelHeight/ {print $2}')
[ "$VERTICAL_WALK_WIDTH" = "768" ] && [ "$VERTICAL_WALK_HEIGHT" = "416" ] || { echo "Unexpected vertical walking atlas size: ${VERTICAL_WALK_WIDTH}x${VERTICAL_WALK_HEIGHT}" >&2; exit 1; }
TEAR_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/IsaacTear.png" | awk '/pixelWidth/ {print $2}')
TEAR_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/IsaacTear.png" | awk '/pixelHeight/ {print $2}')
[ "$TEAR_WIDTH" = "19" ] && [ "$TEAR_HEIGHT" = "19" ] || { echo "Unexpected tear size: ${TEAR_WIDTH}x${TEAR_HEIGHT}" >&2; exit 1; }
echo "atlas: ${WIDTH}x${HEIGHT} RGBA"
echo "shooting atlas: ${SHOOT_WIDTH}x${SHOOT_HEIGHT} Isaac source frames"
echo "vertical walking atlas: ${VERTICAL_WALK_WIDTH}x${VERTICAL_WALK_HEIGHT} Isaac source frames"
echo "tear: ${TEAR_WIDTH}x${TEAR_HEIGHT} Isaac palette"
swift run IsaacPetCoreChecks
echo "Verified: $APP"
