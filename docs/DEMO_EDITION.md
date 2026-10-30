# 体験版（Demo）の構成と配信の手順

2026-10-28 実装。プロジェクトは1つのまま、書き出しのプリセットで製品版と体験版を分ける。

## 切り替えの仕組み

- 判定は `src/bossmaker/rbm_edition.gd`（`RBMEdition.is_demo()`）の1か所だけ。
  - 書き出しプリセット「Windows Desktop Demo」の Custom Features に `demo` が入っている時だけ体験版になる。
  - エディターでの実行と、製品版のプリセット「Windows Desktop」は製品版（既定）のまま。
  - 開発中に体験版を試す時は、起動の引数に `--mc-demo` を付ける（例: `Godot --path . -- --mc-demo`）。
- 体験版の制限
  - ボスは竜・スライム・幽霊・朽ちた機械武者の4体。
  - 作成は SIMPLE だけ（HARDCORE は「製品版限定」で押せない）。
  - 手元の保存は5体まで。
  - オンライン公開は1人2体まで（公開中のボスを非公開にすると入れ替えられる）。
  - オンラインの一覧・検索・ランダム・ランキングは、体験版の4体で作られた SIMPLE のボスだけを出す。
  - プレイ時間の制限は無い。
- 体験版だけの表示: ホーム左上の「ガイド」と、初めて起動した時のガイド（`rbm_demo_guide.gd`）。

## 保存先

| 版 | 置き場 |
|---|---|
| 製品版 | `user://bossmaker/`（変えていない） |
| 体験版 | `user://bossmaker_demo/` |

- 保存したボス戦・討伐記録・挑戦の記録・送信待ち・設定は、すべてこの下に入る。
- 書き出した版はどちらも同じ保存フォルダ（`MakersAndChallengers`）を使うので、製品版は体験版の置き場を読める。

## 製品版への引き継ぎ（`rbm_demo_carry_over.gd`）

- 確認の出し方
  - 製品版を起動してホームに来た時、体験版のデータがあれば、最初の1回だけ「引き継ぐ／あとで」と尋ねる。
  - 「あとで」を選ぶと、次からは自動では尋ねない。
  - ホーム左上の「体験版から引き継ぐ」から、いつでも手動で引き継げる。このボタンは、引き継げる物がある時だけ出る。
- 保存したボス戦
  - 製品版に同じ stage_id が無いものだけを写す。製品版のファイルは上書き・削除しない。
  - 引き継いだ stage_id は製品版の置き場の `demo_carry_over.json` に覚える。製品版で消しても、もう一度は写さない（重複・復活しない）。
- 討伐記録: 製品版の記録とまとめる（同じボスは1件、早い方のクリアが残る）。
- 体験版の側のファイルは消さない。
- オンラインに公開したボス
  - 公開の id ごと写る。
  - 公開の持ち主は Steam のアカウントなので、製品版から非公開・更新できる。
- 同じPCでの確認（2026-10-28、本物の保存先の決め方で4回起動）
  1. 製品版で1体を保存する。
  2. 体験版で6体を保存しようとすると、5体だけ保存できる。製品版のファイルは変わらない。
  3. 製品版で引き継ぐと、5体と討伐記録が増える。製品版の元のデータと体験版の側は変わらない。
  4. 1体を消してからもう一度引き継いでも、何も増えない。
  - 確認の道具: `prototypes/demo_2026-10-28/tools/e2e_carry_over.gd`
- 書き出した版は、どちらもコミット済みの `custom_user_dir_name.template="MakersAndChallengers"` で同じ保存フォルダを使う。

## Steam Cloud の制約

- Steam Cloud はアプリ（AppID）ごとに分かれている。体験版の Steam Cloud の中身は、製品版からは読めない。
- 引き継げるのは、同じPCの手元の保存（`user://bossmaker_demo`）だけ。
- 別のPCで体験版を遊んだ分は、製品版に引き継げない。
  - Steam Cloud に入れているのは討伐記録だけで、ボス戦の保存は元々 Steam Cloud に入れていない。
  - 別のPCでも引き継げるようにするには、サーバー側の保存などの別の仕組みが要る（未実装）。
- 体験版の Steam Cloud を使う場合は、Steamworks で体験版のアプリの Steam Cloud の容量・ファイル数を設定する。使わなければ、体験版の討伐記録は手元だけに残る。

## 制限を外せないかの確認（2026-10-28）

- 起動の引数
  - `--mc-demo` は書き出していない版（エディターの実行）だけで見る。書き出した版では見ないので、引数で体験版と製品版を切り替えられない（`OS.has_feature("template")`）。
  - 書き出した体験版は機能タグ `demo` で決まるので、引数では外せない。
- 環境変数・手元のファイル
  - 書き出した体験版は、`STEAM_APP_ID` の環境変数と `steam_dev_appid.local.txt` で AppID を差し替えない。製品版の AppID で起動して、制限を外すことを防ぐ。
- サーバーで守っている部分（クライアントを改変しても回避できない）
  - 本人の版は Steam のチケットのアプリで決まる。製品版のチケットは製品版を持っている人しか出せない。
  - 体験版のチケットで、次のことはできない。
    - HARDCORE のボスと4体以外のボスの公開。
    - 3体目の公開。
    - 範囲外のボスの挑戦の記録・戦闘チケット・続けて挑戦のチケット。範囲外のボスは、ランキング・クリア率・討伐の数にも入らない。
- 改変されたクライアントでは回避できる部分（手元だけの制限。オンラインの記録・公開には影響しない）
  - 手元の保存の5体。
  - HARDCORE のボタン。
  - 選べるボスの4体。
  - 公開ボスの一覧で、範囲外のボスを見ること。公開データは誰でも読めるので、見ることや手元で遊ぶことは止められない。記録には残らない。

## Steam

### AppID

- 製品版は 5482410（変えていない）、体験版は 5521380（2026-10-28 取得）。
- 体験版の値は `src/bossmaker/online/rbm_steam_config.gd` の `DEMO_APP_ID` に書く。
- 書き出した体験版は、環境変数や手元のファイルで AppID を差し替えない。

### 書き出し（Windows）

- 書き出しのプリセット「Windows Desktop Demo」を使う。Custom Features は `demo`、書き出し先は `../../steam用のゲームフォルダ_体験版/MakersAndChallengers.exe`。
- スクリプトで書き出す時（製品版と同じ手順。種類に `demo` を指定する）:
  `bash tools/build_release_windows.sh <書き出し先> demo`
  - 書き出した物は `MakersAndChallengers.exe`・`.pck`・GodotSteam と Steam API の DLL・`pack_check.json`。
  - pck の中には機能タグ `demo` が入る（project.binary の `_custom_features`）。

### SteamCMD のアップロード設定（`tools/prepare_steam_demo_upload.ps1`）

- 設定ファイルを作るだけで、SteamCMD は実行しない。製品版のスクリプトと設定には触れない。
- 準備: `powershell -NoProfile -File tools/prepare_steam_demo_upload.ps1 -SourceDirectory <書き出し先> -OutputDirectory <新しいフォルダ>`
  - 次の3つを確かめる。
    - pck の確認（pack_check.json）が通っている。
    - pck に `demo` の機能タグがある（製品版の pck は体験版として上げられない）。
    - 上げるのは実行に要る4つのファイルだけ。
  - 作る物: `content/`・`app_build_5521380.vdf`・`depot_build_5521381.vdf`・`demo_upload_manifest.json`。
- アップロードの直前の確認: `-OutputDirectory <そのフォルダ> -VerifyOnly`
  - 中身・設定が準備の後に変わっていないかを確かめる。
- アップロードは人が行う: `steamcmd +login <アカウント> +run_app_build "<フォルダ>/app_build_5521380.vdf" +quit`
  - `setlive` は空にしてある。上げた後に Steamworks でビルドを default に出す。
- デポは 5521381（体験版の AppID + 1、Steamworks の既定）にしてある。違う番号なら `-DepotId` で指定する。

## サーバー（Supabase。2026-10-30 本番に反映済み）

- 本人の版は「Steam のチケットがどちらのアプリのものか」で決める（`steam-auth/steam_ticket_verifier.ts`）。
  - 製品版の AppID で確かめて失敗した時だけ、環境変数 `STEAM_DEMO_APP_ID` の AppID でも確かめる。
  - 製品版のチケットの扱いは今までどおり。
- 体験版のチケットで公開すると、`publish-boss` が SIMPLE・4体だけ、公開中は2体まで、に制限する（`_shared/edition.ts`）。
- 一覧（list-bosses・search-bosses・random-boss・list-popular-bosses・list-hard-bosses・list-unchallenged-bosses）と get-boss は、`edition=demo` の時に体験版の範囲だけを返す。
- 体験版のチケットでは、範囲外のボスの挑戦の記録（record-challenge-attempt・record-challenge-clear）・戦闘チケット（issue-battle-ticket・submit-battle-result の続けて挑戦）を断る（`demoBossRejection`）。
  - これは表示の範囲を決めるだけで、権限には使わない。
- 反映の手順
  1. Supabase の関数の秘密の値に `STEAM_DEMO_APP_ID=5521380` を設定する。
  2. 上の関数（steam-auth を使うすべての関数を含む）をデプロイする。
  3. 設定するまでは、体験版のチケットは受け付けない（今までどおり）。
- 確かめ方: `deno test supabase/functions`

### オンライン挑戦は異なるボス累計15体まで（2026-10-29 実装、2026-10-30 本番に反映）

- 本番の反映（2026-10-30、ユーザーの許可）: migration `20261029000000` を適用 → `STEAM_DEMO_APP_ID=5521380` を設定 →
  15関数をデプロイ（commit `8deaea0`）。製品版から見た応答は反映前と同じ（読み取りの確認30項目のうち、変わったのは新しい関数・表の4項目だけ）。
  体験版のチケットでの実際の挑戦（枠を使う確認）は、まだしていない。記録は `supabase/plans/demo_challenge_limit_release.md` の 5。

- 決まり: Steam アカウントごとに、初めて戦闘を始めたボス（boss_id）を1体と数える。同じボスへの再挑戦・勝ち負けは数えない。
  15体に達したら新しいボスには挑戦できない（挑戦済みの15体には何度でも）。ボスが削除・非公開になっても枠は戻らない。
  製品版のチケットには制限が無い（体験版で15体に達した人も、製品版では自由に挑戦できる）。
- DB: migration `20261029000000_demo_challenge_slots.sql`
  - 表 `demo_challenge_slots`（steam_id・boss_id の主キー、ボスへの外部キーなし）。
  - 関数 `claim_demo_challenge_slot()`（同じ人の同時の要求は advisory lock で順番に処理）・`demo_challenge_status()`。
  - どれも service_role だけ。取り消しは `supabase/rollback/20261029000000_drop_demo_challenge_slots.sql`。
- 関数
  - `record-challenge-attempt`・`issue-battle-ticket`: 体験版のチケットの時だけ枠を確かめる。15体で新しいボスなら 403 `demo_challenge_limit`（記録もチケットも出さない）。
  - 新しい `demo-challenge-status`: 使用状況（used・limit・challenged_boss_ids）。読むだけ。
  - `record-challenge-clear`（古いゲームのクリアの記録）・`submit-battle-result` の次の戦闘のチケット（2026-10-30 追加）: 体験版の
    チケットの時は同じように枠を確かめる。挑戦の記録を飛ばしてクリアや次のチケットだけを送っても、16体目は開かない。
    通常のゲームは挑戦の記録で枠を使った後なので「挑戦済み」になり、枠は増えない。
- ゲーム: 体験版で新しいボスに挑む時だけ、挑戦の記録を先に送り、受け付けられてから戦闘を始める（`rbm_challenge_entry.gd`）。
  - 通信できなければ始めない。
  - オンライン一覧の上に「オンライン挑戦 ○ / 15体」を出す。
- 反映の順: migration を当てる → `STEAM_DEMO_APP_ID` を設定 → 関数をデプロイ → ゲームを更新。
  - `STEAM_DEMO_APP_ID` は 2026-10-30 に本番の関数の秘密の値へ設定した（それまでは体験版のチケットを受け付けなかった）。
  - デプロイする関数: steam-auth を使う全ての関数（体験版の判定）と、新しい demo-challenge-status。
  - 逆の順にすると、関数が無い関数（DB）を呼んで体験版の挑戦が 502 になる。
  - 空実行: 2026-10-30 に本番 DB で begin … rollback の中で migration と取り消しの SQL を当てて確かめた（行は作らない）。
    前後で表・列・関数・権限の指紋と全ての表の行数が同じ。手順は `supabase/tools/dry_run_migration.sh` と同じ形。
    下の分離レベルの安全対策を入れた後の SQL でも、もう一度同じ確かめをして合格（2026-10-30）。
  - 分離レベルの安全対策（2026-10-30）: `claim_demo_challenge_slot()` は read committed（既定）以外では枠を増やさずエラーで止まる。
    Edge Function は 502 の db_error として扱い、15体の上限（`demo_challenge_limit`）とは区別する。
  - 実際の PostgreSQL（17.6、本番と同じ版、手元だけ）での同時の要求の確かめ（2026-10-30）: 14体から別の2体を同時に50回・13体から
    3/5/10体を同時に各10回・0体から40体を同時に・15体の後・同じボスへ20本同時・8人が同時に各20体を、すべて15体を超えずに合格。
    ロックを外した写しでは同じ手順で20回中20回15体を超えた（手順が本当に同時の要求を起こしていることの確かめ）。
    手順と結果は `supabase/plans/demo_challenge_limit_release.md`。
- 戻し方: ゲームと関数を前の版に戻す → `supabase/rollback/20261029000000_drop_demo_challenge_slots.sql`。
  関数だけを15体の制限の前の版（2026-10-28 の体験版の対応）に戻すと、体験版は制限なしの挑戦に戻る（表は残るので、
  もう一度デプロイすれば累計も戻る）。今の本番の関数（2026-10-22 の版、1565a01）まで戻すと、体験版のオンラインは使えなくなる。
  - 関数を当てる前のゲームは、今までどおり制限なしで遊べる（新しいゲームは使用状況が「分からない」と出し、挑戦の確認は今の記録の関数で通る）。
- 既存の記録からの初期化: しない。今の挑戦の記録（boss_challenge_records）は製品版・体験版を区別していないため、体験版で
  挑戦したボスを正しく判定できない（2026-10-29 時点で本番のボス・記録は0件）。

## 未決定（ユーザーの判断が要る）

- Steam のストア・デポ・Steam Cloud の設定（Steamworks の手作業）。
- SIMPLE で作ったボスを HARDCORE へ変える機能は追加しない（モード固定のまま。2026-10-28 ユーザーの決定）。
