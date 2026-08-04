#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="${1:-$ROOT/dist/Isaac Pet.app}"
TARGET="$HOME/Applications/Isaac Pet.app"

if [ ! -d "$SOURCE" ]; then
  echo "App not found: $SOURCE" >&2
  echo "Run scripts/build_app.sh first." >&2
  exit 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$TARGET"
/usr/bin/ditto --rsrc "$SOURCE" "$TARGET"
/usr/bin/open "$TARGET"
echo "Installed and opened: $TARGET"
