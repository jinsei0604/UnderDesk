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

# Repair an already distributed build without incorporating unfinished worktree assets.
# bash tools/build_release_windows.sh <new-output> repair <existing-build> <new-work-dir>
# This prepares files/VDFs only; it never runs SteamCMD.
if [ "$KIND" = repair ]; then
  BASE=${3:?"修復元の配布済みフォルダを指定してください"}
  WORK=${4:?"新しい作業用フォルダを指定してください"}
  CONFIG_ARGS=()
  [ ! -f "$REPO/supabase_poc.local.env" ] || CONFIG_ARGS=(-ConfigFile "$(cygpath -am "$REPO/supabase_poc.local.env")")
  exec pwsh.exe -NoProfile -File "$(cygpath -am "$REPO/tools/prepare_steam_release.ps1")" \
    -SourceDirectory "$(cygpath -am "$BASE")" -OutputDirectory "$(cygpath -am "$OUT")" \
    -WorkDirectory "$(cygpath -am "$WORK")" -Godot "$(cygpath -am "$GODOT")" \
    -RepairMissingPublicConfig "${CONFIG_ARGS[@]}"
fi

case "$KIND" in
  release) PRESET="Windows Desktop"; MODE="--export-release" ;;
  verify)  PRESET="Windows Desktop Verify"; MODE="--export-debug" ;;
  demo)    PRESET="Windows Desktop Demo"; MODE="--export-release" ;;  # 体験版（AppID 5521380。docs/DEMO_EDITION.md）
  *) echo "種類は release / verify / demo / repair"; exit 2 ;;
esac

# A dirty source tree must be an explicit build choice, never an accidental release.
if [ -e "$REPO/.git" ]; then
  STATUS=$(git -C "$REPO" status --porcelain) || { echo "Git 状態を確認できません。書き出しを停止します。"; exit 1; }
  if [ -n "$STATUS" ] && [ "${MC_ALLOW_WORKTREE_BUILD:-0}" != 1 ]; then
    echo "未コミット変更があります。配布済み版の repair、または確認済みのクリーンなコピーを使ってください。"
    echo "制作中の変更を意図して含める場合だけ MC_ALLOW_WORKTREE_BUILD=1 を指定してください。"
    exit 1
  fi
fi

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
# ally_awakening（味方の覚醒の素材・処理、2026-10-24〜）も src から読むので写す（2026-10-30 まで漏れていて、書き出した版で覚醒の演出が読めなかった）
for d in src addons assets_bossmaker data_bossmaker localization ally_awakening; do
  cp -r "$REPO/$d" "$STAGE/$d"
done
rm -rf "$STAGE/addons/gut"
# 配布物に入れない試作（どこからも使われていない画面の試作。元のファイルは作業ツリーに残す。2026-10-30）
rm -rf "$STAGE/src/bossmaker/creator_preview"
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
"$GODOT" --headless --path "$STAGE" --import > "$OUT/import.log" 2>&1
SUPABASE_URL="$PUB_URL" SUPABASE_PUBLISHABLE_KEY="$PUB_KEY" "$GODOT" --headless --path "$STAGE" -s res://tools/make_supabase_public_config.gd 2>&1 | grep -E "PUBLIC_CONFIG"
unset PUB_URL PUB_KEY
"$GODOT" --headless --path "$STAGE" -s res://tools/make_supabase_public_config.gd -- --check
"$GODOT" --headless --path "$STAGE" "$MODE" "$PRESET" "$OUT/MakersAndChallengers.exe" > "$OUT/export.log" 2>&1
grep -q "savepack" "$OUT/export.log" || { echo "書き出しに失敗（$OUT/export.log）"; exit 1; }
# スクリプトの読み込みに失敗した物があれば止める（2026-10-30、写していないフォルダを参照して覚醒の演出が読めなかった件）
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT/export.log" | head -5; then
  echo "書き出しの時にスクリプトのエラー（$OUT/export.log）"; exit 1
fi

# 5. pck の中身の確認（同じ版のエディターで pck を読む）
rm -f "$OUT/pack_check.json"
"$GODOT" --headless --main-pack "$OUT/MakersAndChallengers.pck" -s "$REPO/tools/check_release_pack.gd" -- --report="$(cygpath -m "$OUT/pack_check.json")" 2>&1 | grep -E "PACK_CHECK|PACK_PROBLEM"
grep -q '"problems": \[\]' "$OUT/pack_check.json" || { echo "pck の中身に問題（$OUT/pack_check.json）"; exit 1; }

rm -rf "$STAGE"
echo "BUILD_DONE kind=$KIND preset=\"$PRESET\" godot=$VERSION out=$OUT"
ls -la "$OUT"
