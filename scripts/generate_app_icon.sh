#!/bin/zsh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG_PATH="$REPO_ROOT/assets/AppIcon.svg"
TMP_DIR="$REPO_ROOT/.tmp-icon"
PNG_PATH="$TMP_DIR/AppIcon.svg.png"
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
ICNS_PATH="$REPO_ROOT/assets/AppIcon.icns"

if [[ ! -f "$SVG_PATH" ]]; then
  echo "Missing icon source: $SVG_PATH" >&2
  exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

qlmanage -t -s 1024 -o "$TMP_DIR" "$SVG_PATH" >/dev/null

if [[ ! -f "$PNG_PATH" ]]; then
  echo "Failed to render PNG from SVG" >&2
  exit 1
fi

mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PNG_PATH" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$PNG_PATH" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Generated icon: $ICNS_PATH"
