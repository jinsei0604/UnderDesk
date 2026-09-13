# Makers & Challengers

Godot 4.7製のボス作成・挑戦ゲーム。現在のプロジェクトはこのゲーム専用です。

## 起動・検証

正式パス：`C:\src\makers-and-challengers`

```powershell
& 'C:\src\tools\godot\Godot_v4.7-stable_win64.exe' --path 'C:\src\makers-and-challengers'
# 初回・素材追加後のインポート
& 'C:\src\tools\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --editor --import --quit
# リポジトリのルートで全テスト
& 'C:\src\tools\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

メインシーン：`res://src/bossmaker/rbm_game_root.tscn`。ゲーム名、Godotバージョン、画面設定は変更していません。

### GPU/Visual検証（正式runner、2026-09-13〜）

`RBMGameRoot`を利用するGPU検証・UIキャプチャ系ツール（`tools/verify_world_ui_install_gpu.gd`、`tools/_ui_pass_shots/capture_*.gd`）は、`tools/gpu_runner.tscn`経由で実行する。

```powershell
& 'C:\src\tools\godot\Godot_v4.7-stable_win64.exe' --path 'C:\src\makers-and-challengers' res://tools/gpu_runner.tscn -- `
  --tool=res://tools/verify_world_ui_install_gpu.gd `
  --output=<出力先ディレクトリ> `
  [--record-all]
```

旧来の`godot --path . -s res://tools/xxx.gd`直接起動は、これらの`RBMGameRoot`利用ツールでは**非推奨・非対応**（autoload登録前にスクリプトがコンパイルされ、Compile Errorになる）。対象スクリプトは`func run_gpu_verification(tree: SceneTree, ...) -> ...`という明示的entry pointを公開すること。

`RBMGameRoot`を経由しないVFX単体検証ツール（`tools/verify_healer_lightning_gpu.gd`等、`tools/verify_battle_visuals_gpu.gd`直系）はこの制約を受けないため、従来通り`-s`直接起動のままで良い。

## 構成

- `src/bossmaker/`：戦闘、Creator、Clear Check、Challenge、表示、SE。
- `assets_bossmaker/`：本番画像・モーション素材・採用SE。
- `data_bossmaker/`：味方・ボス・戦闘定義。
- `tests/bossmaker/`：GUT回帰テスト。`addons/gut/`は共有テスト基盤。
- `tools/verify_*`：GPU・実スキル・特殊技・UI・音声検証。
- `tools/_ui_pass_shots/`：現行ゲームの制作・確認ツール。過去の生成物整理は今回繰り返していません。
- `src/bossmaker/online/`、`supabase/`、`tools/supabase_poc/`：既存オンライン接続。ローカル環境設定はコミット禁止。

`bossmaker` / `RBM` は内部識別子として維持しています。既存のデータ形式・セーブ先・Gitリモートも維持しています。詳細と過去の設計記録は [src/bossmaker/README.md](src/bossmaker/README.md)。
