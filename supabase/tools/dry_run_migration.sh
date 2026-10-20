#!/bin/bash
# migration を本番の DB で「当ててから取り消す」空実行（2026-10-21）。Docker が無くローカルの Supabase を使えない時の確かめ。
#   bash supabase/tools/dry_run_migration.sh <migration の .sql> <確かめの .sql>
# 例（リポジトリの直下で）:
#   bash supabase/tools/dry_run_migration.sh supabase/migrations/20261021000000_revoke_direct_table_access.sql supabase/tools/verify_revoke_checks.sql
# 1つの transaction（begin … rollback）で流すので、変更は残らない。確かめが合わなければ例外で止まる（それでも何も残らない）。
# 一時ファイル mc_v1.sql を今いるフォルダに作り、流した後に消す（絶対パスや別の名前の付け方では、CLI が「Access token not provided」で失敗することがあった）。
MIGRATION=$1
CHECKS=$2
{ echo "begin;"; cat "$MIGRATION"; echo; cat "$CHECKS"; echo; echo "rollback;"; } > mc_v1.sql
/c/src/tools/supabase/supabase.exe db query --linked -f mc_v1.sql -o json
rm -f mc_v1.sql
