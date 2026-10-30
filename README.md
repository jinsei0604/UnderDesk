# Makers & Challengers

Godot 4.7.2製のボス作成・挑戦ゲーム。現在のプロジェクトはこのゲーム専用です。

## 起動・検証

正式パス：`C:\src\makers-and-challengers`

```powershell
& 'C:\src\tools\godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\src\makers-and-challengers'
# 初回・素材追加後のインポート
& 'C:\src\tools\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import --quit
# リポジトリのルートで全テスト
& 'C:\src\tools\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

メインシーン：`res://src/bossmaker/rbm_game_root.tscn`。

Godot は本体・書き出しテンプレートとも **4.7.2.stable**（2026-10-20 に 4.7 から統一）。本体は `C:\src\tools\godot\` に置き、テンプレートは `%APPDATA%\Godot\export_templates\4.7.2.stable\`。

### 配布版（Windows）の書き出し

```bash
# Git Bash、リポジトリのルートで。作業ツリーは変えず、写しの中で取り込み・書き出し・pck の点検までする
bash tools/build_release_windows.sh <出力フォルダ> release   # 配布版
bash tools/build_release_windows.sh <出力フォルダ> verify    # 検証版（本物の通信と画面を確かめる道具入り）
```

- オンラインの接続先（Project URL と公開用の鍵）は、書き出しのたびに写しの中で `supabase_public.env` に書く（`tools/make_supabase_public_config.gd`）。値は環境変数 `SUPABASE_URL`・`SUPABASE_PUBLISHABLE_KEY`、無ければ開発用の `supabase_poc.local.env` から。どちらのファイルも Git では管理しない。秘密の鍵（Secret key・service_role）は道具が拒否する。

#### Steam アップロード準備（必須）

手動エクスポートの出力を SteamPipe の content に直接コピーしない。`include_filter` は存在しない公開設定ファイルを生成しないため、手動エクスポートが成功してもオンライン接続できない場合がある。

通常は上の `build_release_windows.sh` で書き出す。未コミット変更がある時は既定で停止する（制作中の変更を意図して含める場合だけ `MC_ALLOW_WORKTREE_BUILD=1`）。続いて、検証済みの専用フォルダとファイル指定の VDF を作る:

```powershell
pwsh -File tools/prepare_steam_release.ps1 -SourceDirectory <書き出し済みフォルダ> -OutputDirectory <新しい配布準備フォルダ> -WorkDirectory <新しい作業用フォルダ>
pwsh -File tools/verify_steam_upload.ps1 -PreparedDirectory <配布準備フォルダ>
```

設定が欠落・不正、開発用設定が混入、PCK 検査が不合格の場合は準備を失敗扱いにする。検査後に PCK・DLL・実行ファイル・VDF が変わった場合も直前の確認が失敗する。SteamCMD にはこの準備フォルダの `app_5482410.vdf` を指定する（以前の SDK の content 全体を送る VDF は使わない）。これらのスクリプトはアップロードしない。

配布済み版の公開設定だけを補う場合は、制作中のソースを再エクスポートせず、既存スクリプトの修復用経路を使える（Godot 4.7.2 / PCK v4 / Windows x64 専用）:

```bash
bash tools/build_release_windows.sh <新しい配布準備フォルダ> repair <配布済みフォルダ> <新しい作業用フォルダ>
```

元の全リソースの内容と実行ファイル・Steam DLL を照合し、`supabase_public.env` だけを追加する。既存の配布物・作業ツリーは変更しない。公開設定は従来の生成ツールで検査して作る。作業用フォルダにはローカル設定のコピーが残るため、配布・共有・コミットしない。アップロード対象は生成した `content/` 内の4ファイルだけ。
- 配布版の保存先は `%APPDATA%\MakersAndChallengers`（`project.godot` の `config/custom_user_dir_name.template`）。エディター・テストは今までどおり `%APPDATA%\Godot\app_userdata\Makers & Challengers`。
- 書き出した版はコマンドラインで場面を差し替えられない。検証版は `MakersAndChallengers.console.exe -- --report=<出力> [--ui=1] [--steam=1]` で `tools/verify_export_online.gd` が動く。開発機で動かす時は `APPDATA` を別のフォルダに向けると、保存・ログが分かれる。

### GPU/Visual検証（正式runner、2026-09-13〜）

`RBMGameRoot`を利用するGPU検証・UIキャプチャ系ツール（`tools/verify_world_ui_install_gpu.gd`、`tools/_ui_pass_shots/capture_*.gd`）は、`tools/gpu_runner.tscn`経由で実行する。

```powershell
& 'C:\src\tools\godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\src\makers-and-challengers' res://tools/gpu_runner.tscn -- `
  --tool=res://tools/verify_world_ui_install_gpu.gd `
  --output=<出力先ディレクトリ> `
  [--record-all]
```

旧来の`godot --path . -s res://tools/xxx.gd`直接起動は、これらの`RBMGameRoot`利用ツールでは**非推奨・非対応**（autoload登録前にスクリプトがコンパイルされ、Compile Errorになる）。対象スクリプトは`func run_gpu_verification(tree: SceneTree, ...) -> int`という明示的entry pointを公開すること。

**成功判定契約（2026-09-13制定）**: 正式runner対応toolは、戻り値`int`に加えて`var _gpu_verification_completed := false`を公開し、処理を最後まで完走した場合にのみこれを`true`にしてから`return`する。runnerはこのフラグと戻り値の両方を確認し、`exit code 0`＝検証が最後まで正常完了したことを保証する。フラグ未対応のtool・フラグが`true`にならなかった場合・戻り値が`int`でない場合は、いずれも`exit code 0`を返さない（安全側）。**runnerの`exit code 0`は検証正常完了、非0は途中失敗または検証失敗を意味する**——`exit code`だけを見て成否を判断してよい。

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
