#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

PKG="com.example.prank"
APK="android/app/build/outputs/apk/debug/app-debug.apk"
DST="android/app/src/main/assets/prank_engine"

fail() { echo; echo "❌ $*"; exit 1; }
ok()   { echo "✅ $*"; }
step() { echo; echo "─── $*"; }

# ── sanity ──
command -v npm  >/dev/null || fail "npm не найден"
[ -f web/package.json ]              || fail "Нет web/package.json — запусти из корня проекта"
[ -d android/app/src/main ]          || fail "Нет android/app/src/main"
[ -f web/src/index.html ]            || fail "Нет web/src/index.html"
[ -f web/src/prank.js ]              || fail "Нет web/src/prank.js"

# ── 1. источник ──
step "[1/6] Санити-проверка исходников"
if grep -qE "Экран SberKids|background:\s*#f2f4f8" web/src/index.html; then
  fail "web/src/index.html всё ещё содержит старый фейковый экран"
fi
if ! grep -q 'id="cat-animation-overlay"' web/src/index.html; then
  fail "В web/src/index.html нет <canvas id=\"cat-animation-overlay\">"
fi
if ! grep -q "switchMode" web/src/prank.js; then
  fail "В web/src/prank.js нет switchMode — бандл не готов к DemoActivity"
fi
ok "Исходники в порядке"

# ── 2. сборка web ──
step "[2/6] Сборка web (без кэша Vite)"
( cd web && rm -rf dist node_modules/.vite && npm run build )
[ -f web/dist/index.html ] || fail "web/dist/index.html не создан"
grep -qE "Экран SberKids" web/dist/index.html && fail "dist содержит старый экран"
ok "web/dist собран"

# ── 3. синк в android ──
step "[3/6] Синк в android/app/src/main/assets/prank_engine"
rm -rf "$DST"
mkdir -p "$DST"
cp -r web/dist/. "$DST"/

# статика → assets/
mkdir -p "$DST/assets"
shopt -s nullglob
for f in "$DST"/atlas.json "$DST"/atlas_winter.json "$DST"/*.png; do
  [ -f "$f" ] && mv "$f" "$DST/assets/"
done
shopt -u nullglob

# ── 4. проверка структуры ──
step "[4/6] Проверка структуры assets"
echo "Содержимое $DST:"
find "$DST" -type f | sort

[ -f "$DST/index.html" ]                 || fail "Нет index.html"
[ -f "$DST/assets/atlas.json" ]          || fail "Нет assets/atlas.json"
[ -f "$DST/assets/cat-states.png" ]      || fail "Нет assets/cat-states.png"
[ -f "$DST/assets/yarn-variants.png" ]   || fail "Нет assets/yarn-variants.png"
[ -f "$DST/assets/cat-dance-simple.png" ]|| fail "Нет assets/cat-dance-simple.png"

BUNDLE=$(ls "$DST"/assets/index-*.js 2>/dev/null | head -1 || true)
[ -n "$BUNDLE" ] || fail "Нет assets/index-*.js (сборка Vite не дала bundle)"
ok "Структура правильная: index.html + assets/{bundle, atlas.json, *.png}"

# ── 5. сборка APK ──
step "[5/6] Сборка APK (clean + rerun-tasks)"
( cd android && ./gradlew :app:clean :app:assembleDebug --rerun-tasks )

[ -f "$APK" ] || fail "APK не собран: $APK"

echo
echo "Файлы prank_engine в APK:"
unzip -l "$APK" | grep prank_engine || fail "prank_engine не попал в APK"

# жёсткая проверка, что atlas/png именно в assets/
if ! unzip -l "$APK" | grep -q "prank_engine/assets/atlas.json"; then
  fail "В APK atlas.json не в assets/ — Gradle взял старые ассеты"
fi
ok "APK собран, ассеты на месте"

# ── 6. установка ──
step "[6/6] Установка на устройство"
if command -v adb >/dev/null && adb get-state 2>/dev/null | grep -q device; then
  adb install -r "$APK"
  ok "Установлено"
else
  echo "⚠️  Устройство не подключено (adb devices). APK лежит здесь:"
  echo "   $APK"
fi

echo
echo "🎉 Готово."
echo "   Тряхни телефон → должен появиться оверлей с игрой"
echo "   Если что-то не так: adb logcat -s PrankTriggerService PrankEngine chromium"
