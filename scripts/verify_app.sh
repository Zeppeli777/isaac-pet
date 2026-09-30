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
/usr/bin/plutil -extract NSRemindersFullAccessUsageDescription raw -o - "$APP/Contents/Info.plist" | grep -F '不会修改或删除系统提醒事项'
/usr/bin/plutil -extract NSRemindersUsageDescription raw -o - "$APP/Contents/Info.plist" | grep -F '不会修改或删除系统提醒事项'
/usr/bin/codesign --verify --deep --strict "$APP"
WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/spritesheet.webp" | awk '/pixelWidth/ {print $2}')
HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/spritesheet.webp" | awk '/pixelHeight/ {print $2}')
[ "$WIDTH" = "1536" ] && [ "$HEIGHT" = "2288" ] || { echo "Unexpected atlas size: ${WIDTH}x${HEIGHT}" >&2; exit 1; }
SHOOT_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/shooting-atlas.webp" | awk '/pixelWidth/ {print $2}')
SHOOT_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/shooting-atlas.webp" | awk '/pixelHeight/ {print $2}')
[ "$SHOOT_WIDTH" = "768" ] && [ "$SHOOT_HEIGHT" = "208" ] || { echo "Unexpected shooting atlas size: ${SHOOT_WIDTH}x${SHOOT_HEIGHT}" >&2; exit 1; }
VERTICAL_WALK_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/walking-vertical-atlas.webp" | awk '/pixelWidth/ {print $2}')
VERTICAL_WALK_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/walking-vertical-atlas.webp" | awk '/pixelHeight/ {print $2}')
[ "$VERTICAL_WALK_WIDTH" = "1536" ] && [ "$VERTICAL_WALK_HEIGHT" = "416" ] || { echo "Unexpected vertical walking atlas size: ${VERTICAL_WALK_WIDTH}x${VERTICAL_WALK_HEIGHT}" >&2; exit 1; }
RAISING_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/raising-atlas.webp" | awk '/pixelWidth/ {print $2}')
RAISING_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/raising-atlas.webp" | awk '/pixelHeight/ {print $2}')
[ "$RAISING_WIDTH" = "1536" ] && [ "$RAISING_HEIGHT" = "208" ] || { echo "Unexpected raising atlas size: ${RAISING_WIDTH}x${RAISING_HEIGHT}" >&2; exit 1; }
TEAR_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/IsaacTear.png" | awk '/pixelWidth/ {print $2}')
TEAR_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/IsaacTear.png" | awk '/pixelHeight/ {print $2}')
[ "$TEAR_WIDTH" = "28" ] && [ "$TEAR_HEIGHT" = "28" ] || { echo "Unexpected tear size: ${TEAR_WIDTH}x${TEAR_HEIGHT}" >&2; exit 1; }
DROP="$APP/Contents/Resources/IsaacTearDrop.png"
[ -f "$DROP" ] || { echo "Missing Isaac tear drop" >&2; exit 1; }
DROP_WIDTH=$(/usr/bin/sips -g pixelWidth "$DROP" | awk '/pixelWidth/ {print $2}')
DROP_HEIGHT=$(/usr/bin/sips -g pixelHeight "$DROP" | awk '/pixelHeight/ {print $2}')
[ "$DROP_WIDTH" = "10" ] && [ "$DROP_HEIGHT" = "10" ] || { echo "Unexpected tear drop size: ${DROP_WIDTH}x${DROP_HEIGHT}" >&2; exit 1; }
if [ -d "$APP/Contents/Resources/Agents" ]; then
  while IFS= read -r role_atlas; do
    ROLE_WIDTH=$(/usr/bin/sips -g pixelWidth "$role_atlas" | awk '/pixelWidth/ {print $2}')
    ROLE_HEIGHT=$(/usr/bin/sips -g pixelHeight "$role_atlas" | awk '/pixelHeight/ {print $2}')
    [ "$ROLE_WIDTH" = "1536" ] && [ "$ROLE_HEIGHT" = "2288" ] || {
      echo "Unexpected role atlas size for $role_atlas: ${ROLE_WIDTH}x${ROLE_HEIGHT}" >&2
      exit 1
    }
  done < <(find "$APP/Contents/Resources/Agents" -type f -name '*-spritesheet.webp' -print)
fi
if [ -f "$APP/Contents/Resources/Agents/magdalene-portrait.png" ]; then
  PORTRAIT_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/Agents/magdalene-portrait.png" | awk '/pixelWidth/ {print $2}')
  PORTRAIT_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/Agents/magdalene-portrait.png" | awk '/pixelHeight/ {print $2}')
  [ "$PORTRAIT_WIDTH" = "192" ] && [ "$PORTRAIT_HEIGHT" = "192" ] || {
    echo "Unexpected Magdalene portrait size: ${PORTRAIT_WIDTH}x${PORTRAIT_HEIGHT}" >&2
    exit 1
  }
fi
for helper in "magdalene-shooting-atlas 768 208" "magdalene-walking-vertical-atlas 1536 416" "magdalene-raising-atlas 1536 208"; do
  set -- $helper
  HELPER="$APP/Contents/Resources/Agents/$1.webp"
  [ -f "$HELPER" ] || continue
  HELPER_WIDTH=$(/usr/bin/sips -g pixelWidth "$HELPER" | awk '/pixelWidth/ {print $2}')
  HELPER_HEIGHT=$(/usr/bin/sips -g pixelHeight "$HELPER" | awk '/pixelHeight/ {print $2}')
  [ "$HELPER_WIDTH" = "$2" ] && [ "$HELPER_HEIGHT" = "$3" ] || {
    echo "Unexpected $1 size: ${HELPER_WIDTH}x${HELPER_HEIGHT}" >&2
    exit 1
  }
done
CARD_COUNT=$(find "$APP/Contents/Resources/Cards" -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
[ "$CARD_COUNT" = "45" ] || { echo "Unexpected card icon count: ${CARD_COUNT} (expected 45 = 44 faces + back)" >&2; exit 1; }
CARD_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/Cards/Tarot00.png" | awk '/pixelWidth/ {print $2}')
CARD_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/Cards/Tarot00.png" | awk '/pixelHeight/ {print $2}')
[ "$CARD_WIDTH" = "14" ] && [ "$CARD_HEIGHT" = "18" ] || { echo "Unexpected card icon size: ${CARD_WIDTH}x${CARD_HEIGHT}" >&2; exit 1; }
BACK_WIDTH=$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/Cards/CardBack.png" | awk '/pixelWidth/ {print $2}')
BACK_HEIGHT=$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/Cards/CardBack.png" | awk '/pixelHeight/ {print $2}')
[ "$BACK_WIDTH" = "14" ] && [ "$BACK_HEIGHT" = "18" ] || { echo "Unexpected card back size: ${BACK_WIDTH}x${BACK_HEIGHT}" >&2; exit 1; }
echo "atlas: ${WIDTH}x${HEIGHT} RGBA"
echo "shooting atlas: ${SHOOT_WIDTH}x${SHOOT_HEIGHT} Isaac source frames"
echo "vertical walking atlas: ${VERTICAL_WALK_WIDTH}x${VERTICAL_WALK_HEIGHT} Isaac source frames"
echo "tear: ${TEAR_WIDTH}x${TEAR_HEIGHT} Isaac palette; drop: ${DROP_WIDTH}x${DROP_HEIGHT}"
swift run IsaacPetCoreChecks
echo "Verified: $APP"
