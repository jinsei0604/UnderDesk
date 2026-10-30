# 体験版の本番反映の手順（オンライン挑戦は異なるボス累計15体まで）

2026-10-30 作成。**2026-10-30 にこの手順で本番に反映した**（結果は末尾の 5）。手順はリポジトリの直下で、`supabase` は `C:\src\tools\supabase\supabase.exe`。

## 0. 反映するもの

| 種類 | 中身 |
|---|---|
| DB | migration `20261029000000_demo_challenge_slots.sql`（新しい表1つ・関数2つ。今ある表・関数には触れない）。本番で未適用はこの1つだけ（2026-10-30 `migration list` で確認） |
| 関数の秘密の値 | `STEAM_DEMO_APP_ID=5521380`（体験版の AppID。公開の番号で、鍵ではない）。2026-10-30 時点で未設定 |
| Edge Functions | 今ある14個の再デプロイと、新しい `demo-challenge-status`（計15個） |
| ゲーム | 体験版の書き出し（Steam へのアップロードは別の判断） |

本番の関数は 2026-10-22 の版（commit `1565a01`。本番から取り出した21ファイルが、この commit と一致することを 2026-10-30 に確認）。
その後のサーバーの変更は、`52b6de0`（体験版の対応、2026-10-28）と、未 commit の15体の制限だけ。

## 0.5 済んでいる確かめ（2026-10-30）

| 確かめ | 結果 |
|---|---|
| 手元の PostgreSQL 17.6（本番と同じ版・本番とは切り離し）で同時の要求 | 120回すべて15体を超えない（`supabase/tools/local_pg/run_concurrency.sh`）。2回流して同じ |
| 対照: ロックを外した写しで同じ手順 | 20回中20回15体を超えた（最大23体）＝手順が本当に同時の要求を起こしている |
| 異常系・分離レベル・権限 | 34項目合格（`run_errors_isolation_privileges.sh`） |
| 取り消しの SQL | 手元で当てて表・関数が消え、今ある表の形・行数は同じ。migration は2回当てても失敗しない |
| 製品版のチケットでの応答（本番の版と手元の版） | 75項目で同じ |
| 本番 DB での空実行（begin … rollback） | 安全対策の前・後の SQL とも `ALL_CHECKS_OK`。前後で指紋・全表の行数が同じ |
| deno test | 231件合格 |

分離レベルの安全対策: `claim_demo_challenge_slot()` は read committed 以外（repeatable read・serializable 等）では、何も書かずに
エラーで止まる。Edge Function は 502 の db_error（15体の上限の `demo_challenge_limit` とは別）、ゲームは「通信できなかった」と出して
戦闘を始めない。本番の既定は read committed で、ロールごとの上書きも無い（2026-10-30 読み取りで確認）。

## 1. 前の準備（読み取りだけ）

1. `git status` で、反映する物が commit されていることを確かめる（関数は作業ツリーからデプロイされるので、commit の後の内容でデプロイする）。
2. `deno test supabase/functions` が全部合格。
3. 今の状態を控える:
   - `supabase migration list --linked`（未適用が `20261029000000` だけ）
   - `supabase functions list`（14個の版の番号）
   - `node supabase/tools/check_deployed_functions.mjs <前.json>`（読み取りだけの30項目。2026-10-30 の結果は `C:\src\tools\claude-mc\logs\demo_slots_dryrun\before_deploy_check.json`）
   - 表の行数と、DB の形の指紋（`C:\src\tools\claude-mc\logs\demo_slots_dryrun\fingerprint.sql`・`rowcounts.sql`）
4. 本番のデータの控え（2026-10-30 時点でボス0件・挑戦の記録0件・チケット0件）。データがあれば、表ごとに JSON で書き出しておく
   （2026-10-29 の削除の時と同じ方法: `C:\src\tools\claude-mc\backups\prod_bosses_2026-10-29\`）。

## 2. 順番

### ① migration
```
supabase db push --linked --dry-run   # 当てる物が 20261029000000 だけか確かめる
supabase db push --linked
```
- 確かめ: `supabase/tools/verify_demo_challenge_slots_checks.sql` を `begin;` と `rollback;` で挟んで流す（行は作らない）→ `DEMO_SLOTS_CHECKS_OK`。
- 今の関数（10-22 の版）はこの表・関数を使わないので、製品版にも今のゲームにも影響しない。
- 新しい表へのロックだけで、今ある表はロックしない（空実行は約5秒、2026-10-30）。

### ② 秘密の値
```
supabase secrets set STEAM_DEMO_APP_ID=5521380
supabase secrets list   # 名前に STEAM_DEMO_APP_ID があることだけ見る（値は出さない）
```
- 今の関数（10-22 の版）は、この値を読まない。設定しても何も変わらない。

### ③ 関数（1つずつ名前を指定。`--prune` は使わない）
各グループの後に `check_deployed_functions.mjs` を流し、前の結果と比べる。

| 順 | 関数 | 製品版から見た変化 |
|---|---|---|
| A | demo-challenge-status（新） | 無い（新しい関数） |
| B | get-boss・list-bosses・search-bosses・random-boss・list-popular-bosses・list-hard-bosses | `?edition=demo` の時だけ体験版の範囲に絞る。付けない要求は同じ |
| C | list-unchallenged-bosses・list-my-hard-awards・unpublish-boss | 体験版のチケットも本人として受け付ける。製品版のチケットは同じ |
| D | publish-boss | 体験版のチケットの公開だけ制限（SIMPLE・4体・2体まで）。製品版は同じ |
| E | issue-battle-ticket・record-challenge-attempt・submit-battle-result・record-challenge-clear | 体験版のチケットの時だけ、範囲と15体の枠を確かめる。製品版は同じ |

```
supabase functions deploy demo-challenge-status --use-api
supabase functions deploy get-boss --use-api
...（上の表の順）
```
- この PC には Docker が無いので `--use-api`（サーバー側で組み立てる）を付ける。新しい関数も今までと同じく `verify_jwt: true`（既定）でデプロイする。
- E は「枠を確かめる関数（DB）」を呼ぶので、必ず ① の後。① より前にデプロイすると、体験版の挑戦が 502 になる（製品版は呼ばないので影響しない）。

### ④ ゲーム
体験版のゲームは、①〜③ が終わってから配る。製品版のゲームは変えなくてよい。

## 3. 反映の後の確かめ

1. `supabase functions list`: 15個が ACTIVE、`demo-challenge-status` が加わっている。
2. `node supabase/tools/check_deployed_functions.mjs <後.json>` と前の結果を比べる。変わってよいのは次だけ:
   - `demo-challenge-status no ticket` 404 → 400、`fake ticket` 404 → 401
   - `REST demo_challenge_slots (direct)`・`RPC claim_demo_challenge_slot (direct)` 404 → 401（公開用の鍵では読めない・呼べない）
3. DB の形の指紋: 増えたのが新しい表1つ・関数2つだけ。今ある表の行数は同じ。
4. 体験版のチケットでの実際の確認（Steam の体験版のアプリで起動したゲームが要る）は、本番に利用者自身の挑戦の枠の行ができる。行うかはユーザーが決める。

## 4. 異常の時の戻し方

| 症状 | 戻し方 | データ |
|---|---|---|
| 体験版だけおかしい | `supabase secrets unset STEAM_DEMO_APP_ID`（体験版のチケットを受け付けなくなる。製品版はそのまま） | 消えない |
| 製品版がおかしい（関数） | 今の版（`1565a01`）の関数をデプロイし直す（下）。`demo-challenge-status` は `supabase functions delete demo-challenge-status` で消すか、残す（呼ばれなければ何もしない） | 消えない |
| DB の migration を取り消す | 関数を先に戻してから `supabase/rollback/20261029000000_drop_demo_challenge_slots.sql` | 体験版の挑戦の累計（`demo_challenge_slots`）だけ消える（全員0体に戻る） |

`1565a01` の関数を戻す時（作業ツリーには触れない）:
```
git archive 1565a01 supabase/functions | tar -x -C <空の一時フォルダ>
supabase functions deploy <関数名> --use-api --workdir <一時フォルダ> --project-ref <プロジェクトの ref>
```
（2026-10-30、本番から取り出した21ファイルと `git archive 1565a01` の中身が同じことを確認した）

### データを消さずに戻せる範囲
- ボス・挑戦の記録・戦闘チケット・戦闘結果・難関の認定: 今回の反映では、表の形も今ある行も変えない。関数・秘密の値を戻しても消えない。
- 体験版の利用者が反映の後に作った記録（公開したボス・挑戦の記録・結果）は、戻した後も残る（製品版と同じ表に入るので、体験版の分だけを見分けて消すことはできない）。
- 挑戦の枠（`demo_challenge_slots`）: 関数だけ戻せば残る。取り消しの SQL を当てた時だけ消える。

## 5. 反映の記録（2026-10-30、ユーザーの許可）

| 段階 | 結果 |
|---|---|
| commit・push | `8deaea0`（サーバー関連の21ファイルだけ。HEAD＋この21ファイルだけの tree で deno test 231件合格＝未 commit の物に頼らない） |
| 接続先 | アカウントのプロジェクトは1つ（MakersAndChallengers）。CLI の接続先とゲームの本番の接続先が一致 |
| 前の控え | 4つの表を JSON で控えた（`C:\src\tools\claude-mc\backups\prod_before_demo_slots_2026-10-30\`、ボス0・記録0・チケット0・接続テスト1） |
| migration | `db push --dry-run` で `20261029000000` だけ（seed・role なし）→ `db push` で適用（約5秒）。未適用0件 |
| 適用後の確かめ | `verify_demo_challenge_slots_checks.sql` → `DEMO_SLOTS_CHECKS_OK`。新しい物を除いた表・列・関数・権限・ポリシー・トリガーは前と同じ。全表の行数も同じ（新しい表は0行） |
| 秘密の値 | `STEAM_DEMO_APP_ID` を登録。ほかの値は変わらない（名前と指紋だけで確認） |
| 関数 | A→B→C→D→E の順に15個をデプロイ。全部 ACTIVE・`verify_jwt: true`。各グループの後の30項目の比較で想定外の差0 |
| 中身の照合 | 本番から取り出した15関数の24ファイルが commit `8deaea0` と同じ |
| 30項目の比較 | 変わらない26・想定どおりに変わった4（demo-challenge-status 404→400／404→401、表・関数の直接の呼び出し 404→401）・想定外0 |
| 起動の確認 | publish-boss・unpublish-boss も ticket 無しで 400（書き込む前に断る） |

まだしていないこと: 体験版のチケットでの実際の挑戦（本番に枠の行ができる）、関数のエラーのログの確認（CLI に無いので Supabase のダッシュボードで見る）。
秘密の値を設定した時、14関数の版の番号が1つずつ上がった（更新の時刻と中身は変わらず。Supabase 側の番号の付け直し）。
