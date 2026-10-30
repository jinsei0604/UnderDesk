# 手元の PostgreSQL での確かめ（体験版のオンライン挑戦の15体）

本番とは切り離した、手元だけの PostgreSQL 17.6（本番と同じ版）で、`claim_demo_challenge_slot()` の同時の要求・異常系・
分離レベルの安全対策・権限を確かめる道具（2026-10-30）。本番の Supabase には繋がない。

## 用意
1. PostgreSQL の Windows 版の zip（EDB の公式の配布）を展開する（既定の置き場: `C:\src\tools\postgresql\17.6\pgsql\bin`、別の所なら `PG_BIN`）。
2. 空のデータの置き場を作って起動する（127.0.0.1 だけ・ポート 55432、別なら `PG_PORT`）:
   ```
   initdb -D <データ> -U postgres -A trust -E UTF8 --locale=C
   （postgresql.conf に listen_addresses = '127.0.0.1'・port = 55432・max_connections = 200）
   pg_ctl -D <データ> -l <ログ> -w start
   ```
3. 順に流す: `00_supabase_roles.sql` → `supabase/migrations/*.sql`（名前の順、1つずつ `psql -1`）→ `10_match_production_grants.sql` → `seed.sql`。

## 確かめ
- `bash run_concurrency.sh`: 同時の要求（14体から2体×50回・13体から3/5/10体×各10回・0体から40体・15体の後・同じボスへ20本・8人が同時）。
  約4分。全部「合格」で、最後に `合計: 合格 120 / 不合格 0`。
- `bash run_errors_isolation_privileges.sh`: 取り消し・エラー・接続が切れた時に枠が残らない、分離レベル（repeatable read・serializable は
  エラーで止まり行を増やさない）、anon・authenticated から表・関数に触れない。`合計: 合格 34 / 不合格 0`。
- 同時の要求は、門番の接続が持つ advisory lock の後ろに全員を並べ、全員が待っていることを確かめてから一斉に放す（`conc.sh` の `burst`）。

終わったら `pg_ctl -D <データ> stop` で止め、データの置き場を消してよい（試験のボス・SteamID は架空の値だけ）。
