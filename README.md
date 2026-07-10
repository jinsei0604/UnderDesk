# UNDERDESK（仮題: タスクバーの底のダンジョン）

デスクトップ常駐型 放置ダンジョン経営 × 発掘ナラティブ。
画面下端の横長ウィンドウの中で、手下たちがダンジョンを掘り続ける。

企画書は `docs/design.md` を正とする（§12 のコーディング規約に従うこと）。

## 開発環境

- Godot 4.7（`C:\src\tools\godot\Godot_v4.7-stable_win64.exe`）
- テスト: GUT 9.6.1（`addons/gut`）

## コマンド

```powershell
# 実行（常駐ウィンドウ）
& C:\src\tools\godot\Godot_v4.7-stable_win64.exe --path C:\src\underdesk

# テスト
& C:\src\tools\godot\Godot_v4.7-stable_win64_console.exe --headless --path C:\src\underdesk `
  -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# ファイル追加/クラス追加後の再インポート
& C:\src\tools\godot\Godot_v4.7-stable_win64_console.exe --headless --path C:\src\underdesk --import
```

## 構成

- `src/core/` — エンジン非依存の純ロジック（tick制シム、グリッド、ジョブ、経路）
- `src/window/` — OS依存の常駐ウィンドウ処理（隔離）
- `src/meta/` — セーブ（世代バックアップ）、オフライン進行
- `src/narrative/` — 文書DB、ローカライズ
- `data/` — 地層・部屋・文書などの外部データ（JSON）
- `locale/` — ja.csv / en.csv（文書本文含む）
- `tests/` — GUT。オフライン等価性とセーブ往復が最重要
