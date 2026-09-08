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

## 構成

- `src/bossmaker/`：戦闘、Creator、Clear Check、Challenge、表示、SE。
- `assets_bossmaker/`：本番画像・モーション素材・採用SE。
- `data_bossmaker/`：味方・ボス・戦闘定義。
- `tests/bossmaker/`：GUT回帰テスト。`addons/gut/`は共有テスト基盤。
- `tools/verify_*`：GPU・実スキル・特殊技・UI・音声検証。
- `tools/_ui_pass_shots/`：現行ゲームの制作・確認ツール。過去の生成物整理は今回繰り返していません。
- `src/bossmaker/online/`、`supabase/`、`tools/supabase_poc/`：既存オンライン接続。ローカル環境設定はコミット禁止。

`bossmaker` / `RBM` は内部識別子として維持しています。既存のデータ形式・セーブ先・Gitリモートも維持しています。詳細と過去の設計記録は [src/bossmaker/README.md](src/bossmaker/README.md)。
