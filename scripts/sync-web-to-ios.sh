#!/usr/bin/env bash
# Собирает web/ и копирует dist в ios/PrankApp/Resources/Web
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/web"
DEST="$ROOT/ios/PrankApp/Resources/Web"

echo "==> Building web…"
cd "$WEB"
npm install --silent
npm run build

echo "==> Syncing to $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$WEB/dist/." "$DEST/"

# Vite кладёт ассеты рядом; убедимся, что atlas/png на месте
if [[ ! -f "$DEST/atlas.json" && -f "$WEB/assets/atlas.json" ]]; then
  cp -R "$WEB/assets/." "$DEST/"
fi

echo "==> Done. Files:"
find "$DEST" -maxdepth 2 -type f | sort
