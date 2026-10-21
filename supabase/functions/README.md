# Edge Functions（Supabase）

オンライン機能のサーバー側。各関数は `<関数名>/index.ts`、テストは同じフォルダの `index.test.ts`（実際のSupabaseへは出ない偽のDBを使う）。

## テスト・デプロイ

- テスト: このフォルダで `deno test`（全関数）。`_shared` を変えたら全関数を流す。
- デプロイ: リポジトリの直下で `supabase functions deploy <関数名>`（1つずつ名前を指定する。`--prune` は使わない＝ほかの関数を消すため）。
- デプロイの前後の確認（読み取りだけ）: リポジトリの直下で `node supabase/tools/check_deployed_functions.mjs <出力.json>`。状態コード・項目の名前・件数・SteamID が出ていないかだけを出す（接続先・鍵の値は出さない）。前後の JSON を比べる。2026-10-20 のデプロイでは15項目すべて前後で同じ。
- 関数の変更の前後の応答の比較（偽の DB）: `deno run --allow-read supabase/tools/compare_function_responses.ts <変更前の functions> <変更後の functions>`（変更前は `git archive HEAD supabase/functions` などで取り出す）。
- JWT の確認: 2026-10-17 時点で、デプロイ済みの関数はすべて `verify_jwt: true`（`supabase functions list` で確認）。新しい関数も同じ設定（既定）でデプロイする。
- 無料枠のプロジェクトは、しばらく使われないと一時停止される（2026-10-17 に停止中を確認）。停止中はすべてのオンライン機能が通信の失敗になる。再開はダッシュボードから。

## Steam の本人確認（公開・挑戦の記録・未挑戦）

- ゲームは GetAuthTicketForWebApi（identity `makers-and-challengers-backend`、`RBMSteamAuth.WEB_API_IDENTITY` と `steam-auth/index.ts` の `WEB_API_IDENTITY` を必ず同じにする）で ticket を取り、hex で送る。関数は Valve の AuthenticateUserTicket（`https://partner.steam-api.com/ISteamUserAuth/AuthenticateUserTicket/v1/`。Publisher Web API Key の問い合わせは partner 用の宛先、という Valve の説明に従う）で確かめた SteamID だけを使う。リクエストに入っている SteamID は使わない。
- 要る Secrets（Supabase の Edge Functions → Secrets）: `STEAM_APP_ID`（正式 AppID 5482410）と `STEAM_PUBLISHER_WEB_API_KEY`（Steamworks の Users & Permissions → Manage Groups → アプリのグループ → Create WebAPI Key。管理者だけが作れる）。どちらかが無い間、`publish-boss`・`unpublish-boss`・`record-challenge-attempt`・`record-challenge-clear`・`issue-battle-ticket`・`submit-battle-result`・`list-my-hard-awards`・`list-unchallenged-bosses` は 503 `not_configured` を返す。
- 鍵はゲーム・Git・ログ・チャットに入れない。入れ方: ダッシュボードで入力するか、リポジトリの外に置いた一時ファイルで `supabase secrets set --env-file <ファイル>`（流した後にファイルを消す）。Edge Functions の出口の IP は決まっていないので、鍵の IP の制限は付けない。
- 確かめ（読み取りだけ）: 書き出した検証版で `MakersAndChallengers.console.exe -- --report=<出力> --steam=1`（本物の ticket で `list-unchallenged-bosses` を呼ぶ。鍵が入っていれば 200）。

## 挑戦者数・クリア率と、戦闘チケット（2026-10-23）

- **数え方（一覧・検索・ランダム・未挑戦・人気・高難度・難関ボス討伐の認定で共通）**: 挑戦者 = 作者本人を除き、決着した戦闘（勝ち・負け）の結果が1回以上ある人（`boss_challenge_records.result_count > 0`）。クリアした人 = そのうち勝ちの結果がある人（`result_clear_count > 0`）。通常クリア率 = クリアした人 ÷ 挑戦者。挑戦者0人は未集計（ゲームの画面は「—」。0% と出さない）。挑戦を始めただけ（`challenge_count`）・旧版のゲームのクリアの記録（`record-challenge-clear` の `clear_count`）・この仕組みより前の記録は数えない。人気の順位の決まり（挑戦者数 → 総挑戦回数 → 公開日時）と、高難度の決まり（挑戦者5人以上・補正クリア率 (クリアした人+1)/(挑戦者+2) の低い順）は変えていない（数える人だけが変わった）。共通の集計は `_shared/boss_card_fields.ts`。
- **戦闘チケット**（表 `boss_battle_tickets`、DB の `issue_boss_battle_ticket`・`submit_boss_battle_result`。`_shared/battle_tickets.ts`）: 戦闘の開始ごとにサーバーが出す1回限りの札。Steam で確かめた本人・ボス・そのボスのモードと版（DB の値）に結びつく。結果（勝ち・負け）はチケットでだけ受け付け、1枚で1回だけ数える。同じ結果（同じチケット・同じ結果の id・同じ勝敗）の送り直しは数えずに今の状態を返す（`duplicate`）。別の結果での使い回しは `used`、知らない・本人やボスが違うチケットは `invalid`、期限（30日）を過ぎたものは `expired`。ボスが後で非公開になっても、公開中に出したチケットの結果は受け付ける。
  - 発行の上限: 1人×1ボスで1時間に60枚・1人で24時間に600枚（結果1回に1枚なので、結果を送れる回数の上限にもなる）。超えても戦闘は止めない（その戦闘の結果が数えられないだけ）。最短の戦闘時間は拒む条件にしない。
  - 表を大きくしない: 期限から1日過ぎたチケットは、発行の時に消す（本人の分すべてと、ほかの人の分を1回100枚まで）。
  - 関数: `record-challenge-attempt`（`want_battle_ticket: true` の時、最初の戦闘のチケットも返す。旧版のゲームは送らないのでチケットは出ない）、`issue-battle-ticket`（次の戦闘のチケット。200・404 非公開・429 上限）、`submit-battle-result`（結果を最大20件まとめて受け付ける。1件ごとに `counted`・`duplicate`・`invalid`・`used`・`expired`・`error`（DB に届かなかった。ゲームは後で送り直す）。`next_ticket_boss_id` で次の戦闘のチケットも同じ応答で返す）、`list-my-hard-awards`（本人の認定済みのボスの id だけ）。どれも SteamID を返さない。`record-challenge-clear` は旧版のゲームとの互換のために残す（`clear_count` を足して `by_owner` を返すだけ。数え方には入らない）。
  - チケットの限界（今後の改善）: チケットは「サーバーが戦闘の開始を知っている」「1つの結果を1回だけ数える」「回数の上限」を保証するが、勝ったこと自体は確かめない（戦闘はゲームの中で決まる。ゲームを持つアカウントなら、関数を直接呼んで、チケットを取ってすぐ勝ちを送ることはできる。人数（10人）は別のアカウントが要る）。確実にするには、戦闘の記録（乱数の種・行動の列）をサーバーで再計算して勝ちを確かめる仕組みが要る（戦闘は決定的なので可能だが、大きな作業）。
- **ゲームの送信待ちと送り直し**（`RBMBattleResultReporter`・`RBMBattleResultOutbox`）: 決着した結果に1つだけの id（UUID）をつけて手元（アカウントごとのファイル、Steam Cloud には入れない）に残してから送る。通信が切れた・ゲームを終えた結果は、挑戦トップを開いた時・次の挑戦を始めた時（1分以上の間隔）に同じ id でまとめて送り直す。答えが来たもの（数えた・数え済み・数えられない）だけを消す。30日（チケットの期限）を過ぎたものは捨てる。途中でやり直した戦闘は結果が出ていないので同じチケットを使い続ける。Steam の ticket の取得から通信の終わりまでを1本ずつ順に行う（`RBMOnlineChallengeRecorder`）。
  - 通信できずに始めた戦闘（チケットが無い）の結果は、後で送っても数えない（勝ったことを確かめられない結果を無条件に受け付けないため）。その勝ちの討伐記録（手元）は、今までどおり旧来のクリアの記録の応答（作者本人か）で決める（通信できなければ記録しない）。案: 通信できる時に、よく挑戦するボスのチケットを数枚あらかじめ受け取っておく（期限内なら後で送れる）。
- **難関ボス討伐の認定**（作者本人を除く）: 結果50回以上・挑戦者10人以上・通常クリア率5%以下（`20 × クリアした人 ≤ 挑戦者`、整数で比べる）。認定されるのは、初めて結果でクリアした時に「ほかの人」（作者・本人を除く挑戦者）のクリア率が5%以下だったプレイヤー。ほかに挑戦者がいなかった時（最初のクリア）は 0% と決めつけず判定保留とし、ボスが条件を満たした時に認定する。初回クリア時に5%を超えていた人は対象外。条件に届いていなければ保留し、後で満たした時にさかのぼって認定する。一度認定したら取り消さない（DB のトリガーで守る）。数えるのも認定するのも DB（`submit_boss_battle_result` の中の `award_hard_defeats`。1ボス分の行だけを boss_id の索引で読む）。クリアした人が1人以上いると、5%以下には挑戦者20人以上が要るので、「10人以上」はその時いつも満たされる。
- 適用の順序: migration `20261023000000_hard_defeat_award`（本番で空実行してから）→ 関数のデプロイ（`record-challenge-attempt`・新しい `issue-battle-ticket`・`submit-battle-result`・`list-my-hard-awards`、数え方の `list-bosses`・`search-bosses`・`random-boss`・`list-unchallenged-bosses`・`list-popular-bosses`・`list-hard-bosses`）→ ゲームの更新。逆にすると、無い関数・列を呼んで失敗する（ゲームは失敗しても戦闘を止めず、旧版のサーバーとしてチケットを頼まない）。確かめ: `supabase/tools/verify_hard_defeat_checks.sql`（境界・チケット・遡及・権限。取り消し付き）。戻し方: 関数を前の版へ戻してから `supabase/rollback/20261023000000_drop_hard_defeat_award.sql`。

## 読み取りの関数と公開範囲

| 関数 | 内容 | 読むもの |
|---|---|---|
| `list-bosses` | オンライン・新着の一覧 | 2026-10-18（2026-10-20 デプロイ）: DBで絞り・並べ・打ち切る。1回 limit+1 件（カードの列だけ）＋そのページの挑戦記録。以前は公開中の全ボスを payload ごと読んでいた |
| `list-unchallenged-bosses` | 未挑戦 | 2026-10-18（2026-10-20 デプロイ）: 公開ボスをDBの並び順で100件ずつ（カードの列だけ）読み、自分の挑戦済みを除いて limit 件で止める＋自分の挑戦記録＋そのページの挑戦記録 |
| `list-popular-bosses`・`list-hard-bosses` | 人気・高難度 | 公開ボスの全件（2026-10-18（2026-10-20 デプロイ）からカードの列だけ。modeはDBで絞る）と挑戦記録の全件 |
| `get-boss` | 1体の詳細（payload） | 1件。2026-10-18（2026-10-20 デプロイ）から公開した人の SteamID は返さない |
| `search-bosses`（2026-10-17） | 名前・作者名・公開ID（id の先頭8文字）で検索 | 条件に合う最大21件（カードの列だけ）＋そのページの挑戦記録 |
| `random-boss`（2026-10-17） | ランダム挑戦 | 数える1回（行は読まない）＋1件＋その挑戦記録 |

- 公開ボスの問い合わせには必ず `is_published=eq.true` を付ける。返すのはカードの項目だけ（owner_steam_id・battle_hash・挑戦者の SteamID などは返さない）。
- 表への直接の権限（2026-10-21、migration `20261021000000_revoke_direct_table_access.sql`）: ゲームの公開用の鍵（anon）・authenticated は `bosses`・`boss_challenge_records`・`boss_connection_tests` を REST から直接読めない・書けない（すべて関数＝service_role 経由）。確かめ: `supabase db query --linked -f supabase/tools/inspect_public_access.sql`、`verify_revoke_checks.sql`（関数の権限での読み書きも確かめ、最後に取り消す）。戻し方: `supabase/rollback/20261021000000_restore_direct_table_access.sql`。
- これから作る物の既定の権限（2026-10-21、migration `20261021100100`・`20261021100200`）: postgres（migration・ダッシュボード・SQL エディター）が public に作る表・順序・関数には、anon・authenticated の権限が付かない。postgres が作る関数には、どのスキーマでも PUBLIC の EXECUTE が付かない。**service_role にも、表の読み書き・関数の EXECUTE は自動では付かない**（表の TRUNCATE・REFERENCES・TRIGGER・MAINTAIN だけ）。既にある表・関数は変わっていない。Supabase の内部機能（認証・ストレージなど）と、ダッシュボードで入れる拡張機能（supabase_admin が作る）には効かない。
- 新しい表・関数を足す時の決まり（同じ migration の中で書く）:
  - 表: `alter table public.<表> enable row level security;`、`revoke all on table public.<表> from anon, authenticated, public;`、Edge Functions が使う分だけ `grant select, insert, update on table public.<表> to service_role;`（要る物だけ。例: `20260917010000_grant_service_role_online_permissions.sql`）。
  - 関数: `set search_path = ''` を付け、本体の表・関数の参照には `public.` などのスキーマを付ける。`revoke all on function public.<関数>(<引数の型>) from public, anon, authenticated;` と、呼ぶ役割にだけ `grant execute on function public.<関数>(<引数の型>) to service_role;`。SECURITY DEFINER は必要な時だけ。
  - 当てる前: 本番で「当てて確かめて取り消す」空実行（`supabase/tools/dry_run_migration.sh`）。当てた後: `supabase db query --linked -f supabase/tools/check_no_client_access.sql`（読み取りだけ。anon・authenticated・PUBLIC が public の表・順序・関数に触れない、service_role に要る権限がある、を確かめる）と `supabase db advisors --linked --type security`。
- トリガー関数の search_path（2026-10-21、migration `20261021100000`）: `bosses_set_updated_at`・`boss_challenge_records_set_updated_at` は `search_path = ''`。確かめ: `supabase/tools/verify_default_privileges_checks.sql`（`begin;` と `rollback;` で挟んで流す）。
- `search-bosses`・`random-boss` は、DBの失敗の文を利用者へ返さず関数のログにだけ残す（`error_kind: db_error` と決まった文だけを返す）。既存の関数は今もDBの失敗の文を `message` に入れて返している（直すなら同じ形に）。

## 今後の改善課題

**関数ごとのアクセス回数の制限が無い**（2026-10-17 記録）

- 今の状態: 読み取りの関数は、ゲームに含まれる publishable key があれば誰でも何度でも呼べる。関数の中にも回数の制限は無い（Supabase 側の全体の制限だけ）。
- 無料枠への影響のリスク: 誰かが短い間隔で大量に呼ぶと、Edge Function の呼び出し回数・DBの読み取り・転送量を消費する。無料枠の上限に達すると、**この関数だけでなくプロジェクト全体（公開・挑戦の記録・一覧など、既存のオンライン機能すべて）**が止まる・制限されるおそれがある。特に `list-bosses`・`list-unchallenged-bosses`・`list-popular-bosses`・`list-hard-bosses` は1回で公開ボス（や挑戦記録）の全件を読むため、公開ボスが増えるほど1回が重くなる。`search-bosses`・`random-boss` は1回の読み取りが上限で抑えてあるが、回数の制限は同じく無い。
- ゲームの側でしていること: 検索は検索ボタン・Enter の時だけ、読み込み中の同じ検索・抽選中の「更新」は通信を重ねない、通信1本に12秒の上限。ただしゲーム以外からの呼び出しには効かない。
- 対策の候補: ①一覧の応答に `Cache-Control` を付け、同じ内容は CDN から返す ②呼び出し元（IP など）ごとの簡易な回数制限（DBの小さな表か KV） ③一覧の関数を、`search-bosses` と同じく「DBで絞って必要な列だけ読む」形に直す（**2026-10-18 に list-bosses・list-unchallenged-bosses で実装、人気・高難度は payload を読まないところまで。2026-10-20 にデプロイ**） ④Supabase の利用量の通知を設定する ⑤人気・高難度の集計をDBのビュー（挑戦記録をボスごとに数える）で行い、上位 limit 件だけを読む（DBの変更が要る。2026-10-20 のユーザーの判断で本番には入れず、検証計画を `supabase/plans/ranking_db_view.md` に残した）。
- ゲームの側（2026-10-18）: 人気・高難度は同じモードの結果を60秒覚え、選び直したボスの詳細は版（revision）が同じなら取り直さない（`rbm_online_boss_list_view.gd`・`rbm_online_challenge_loader.gd`）。
