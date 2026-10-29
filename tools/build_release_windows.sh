#!/bin/bash
# Windows 向けの書き出し（2026-10-18）。Godot 本体と書き出しテンプレートは同じ 4.7.2.stable を使う。
# 作業ツリーは変えない: 必要なものだけを写したフォルダ（_stage）の中で、取り込み・確認・書き出しをする。
#
# 使い方（リポジトリの直下で、Git Bash）:
#   bash tools/build_release_windows.sh <出力フォルダ> [配布版=release | 検証版=verify]
# 例:
#   bash tools/build_release_windows.sh ../mc_build/release release
#   bash tools/build_release_windows.sh ../mc_build/verify verify
# 前提:
#   - C:/src/tools/godot/Godot_v4.7.2-stable_win64_console.exe（GODOT で上書きできる）
#   - %APPDATA%/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe など
#   - 接続先（Project URL・Publishable key）: 環境変数 SUPABASE_URL・SUPABASE_PUBLISHABLE_KEY、
#     無ければ開発用のローカル設定 supabase_poc.local.env。ここから、配布用の公開設定 supabase_public.env を
#     写しの中で作る（tools/make_supabase_public_config.gd が検査して書く。リポジトリには置かない・Git でも管理しない）。
#     秘密の鍵（Secret key・service_role）は作る道具が拒否する。値は画面にもログにも出さない。
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?"出力フォルダを指定してください"}
KIND=${2:-release}
GODOT=${GODOT:-/c/src/tools/godot/Godot_v4.7.2-stable_win64_console.exe}
EXPECTED_VERSION="4.7.2.stable"

case "$KIND" in
  release) PRESET="Windows Desktop"; MODE="--export-release" ;;
  verify)  PRESET="Windows Desktop Verify"; MODE="--export-debug" ;;
  demo)    PRESET="Windows Desktop Demo"; MODE="--export-release" ;;  # 体験版（AppID 5521380。docs/DEMO_EDITION.md）
  *) echo "種類は release / verify / demo"; exit 2 ;;
esac

# 1. 版をそろえる（本体とテンプレート）
VERSION=$("$GODOT" --version | tr -d '\r')
case "$VERSION" in
  "$EXPECTED_VERSION"*) ;;
  *) echo "Godot の版が違う: $VERSION（$EXPECTED_VERSION が要る）"; exit 1 ;;
esac
TEMPLATES="$(cygpath -u "$APPDATA")/Godot/export_templates/$EXPECTED_VERSION"
for t in windows_release_x86_64.exe windows_debug_x86_64.exe windows_debug_x86_64_console.exe; do
  [ -f "$TEMPLATES/$t" ] || { echo "書き出しテンプレートが無い: $TEMPLATES/$t"; exit 1; }
done
grep -q "^${EXPECTED_VERSION}" "$TEMPLATES/version.txt" 2>/dev/null || [ ! -f "$TEMPLATES/version.txt" ] || { echo "テンプレートの版が違う"; exit 1; }

# 2. 接続先の値（表示しない）。環境変数が無ければ、開発用のローカル設定から読む
PUB_URL="${SUPABASE_URL:-}"
PUB_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"
if [ -z "$PUB_URL" ] || [ -z "$PUB_KEY" ]; then
  [ -f "$REPO/supabase_poc.local.env" ] || { echo "接続先が無い（環境変数 SUPABASE_URL・SUPABASE_PUBLISHABLE_KEY か supabase_poc.local.env）"; exit 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r')
    case "$line" in
      SUPABASE_URL=*) PUB_URL="${line#SUPABASE_URL=}" ;;
      SUPABASE_PUBLISHABLE_KEY=*) PUB_KEY="${line#SUPABASE_PUBLISHABLE_KEY=}" ;;
    esac
  done < "$REPO/supabase_poc.local.env"
fi
[ -n "$PUB_URL" ] && [ -n "$PUB_KEY" ] || { echo "接続先の値が空"; exit 1; }

# 3. 写したフォルダ（.git・prototypes・tests・docs・supabase・ローカルの設定は写さない）
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
STAGE="$OUT/_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/tools"
for d in src addons assets_bossmaker data_bossmaker localization; do
  cp -r "$REPO/$d" "$STAGE/$d"
done
rm -rf "$STAGE/addons/gut"
cp "$REPO/project.godot" "$REPO/default_bus_layout.tres" "$REPO/export_presets.cfg" "$STAGE/"
cp "$REPO/tools/make_supabase_public_config.gd" "$REPO/tools/verify_export_online.gd" "$REPO/tools/verify_export_online.tscn" "$STAGE/tools/"
# GUT はエディターのプラグインとして登録されているだけ（ゲームでは使わない）。写しでは登録を外す
sed -i 's#enabled=PackedStringArray("res://addons/gut/plugin.cfg")#enabled=PackedStringArray()#' "$STAGE/project.godot"
# 検証版だけ: 書き出した版はコマンドラインで場面を差し替えられないので、検証版の印（mc_export_verify）が
# ある時の起動画面を検証の道具にする（写しの project.godot だけ。配布版・作業ツリーは変えない）
if [ "$KIND" = "verify" ]; then
  sed -i 's#^run/main_scene="res://src/bossmaker/rbm_game_root.tscn"#&\nrun/main_scene.mc_export_verify="res://tools/verify_export_online.tscn"#' "$STAGE/project.godot"
  grep -q 'main_scene.mc_export_verify' "$STAGE/project.godot" || { echo "検証版の起動画面を設定できなかった"; exit 1; }
fi
[ -d "$REPO/.godot/imported" ] && { mkdir -p "$STAGE/.godot"; cp -r "$REPO/.godot/imported" "$STAGE/.godot/imported"; }

# 4. 取り込み・配布用の公開設定を作る（検査して書く。秘密の鍵なら止まる）・確かめる・書き出し
"$GODOT" --headless --path "$STAGE" --import > "$OUT/import.log" 2>&1 || true
SUPABASE_URL="$PUB_URL" SUPABASE_PUBLISHABLE_KEY="$PUB_KEY" "$GODOT" --headless --path "$STAGE" -s res://tools/make_supabase_public_config.gd 2>&1 | grep -E "PUBLIC_CONFIG" || true
unset PUB_URL PUB_KEY
"$GODOT" --headless --path "$STAGE" -s res://tools/make_supabase_public_config.gd -- --check
"$GODOT" --headless --path "$STAGE" "$MODE" "$PRESET" "$OUT/MakersAndChallengers.exe" > "$OUT/export.log" 2>&1
grep -q "savepack" "$OUT/export.log" || { echo "書き出しに失敗（$OUT/export.log）"; exit 1; }

# 5. pck の中身の確認（同じ版のエディターで pck を読む）
"$GODOT" --headless --main-pack "$OUT/MakersAndChallengers.pck" -s "$REPO/tools/check_release_pack.gd" -- --report="$(cygpath -m "$OUT/pack_check.json")" 2>&1 | grep -E "PACK_CHECK|PACK_PROBLEM" || true
grep -q '"problems": \[\]' "$OUT/pack_check.json" || { echo "pck の中身に問題（$OUT/pack_check.json）"; exit 1; }

rm -rf "$STAGE"
echo "BUILD_DONE kind=$KIND preset=\"$PRESET\" godot=$VERSION out=$OUT"
ls -la "$OUT"
