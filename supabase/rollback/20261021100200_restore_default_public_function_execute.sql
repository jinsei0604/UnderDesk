-- 復旧用（問題が出た時だけ手で流す。migration ではない）: 20261021100200_revoke_default_public_function_execute.sql の直前
-- （PostgreSQL の既定どおり、postgres が作る関数に PUBLIC の EXECUTE が付く）に戻す。
-- 流し方（リポジトリの直下）: supabase db query --linked -f supabase/rollback/20261021100200_restore_default_public_function_execute.sql
-- 続けて: supabase migration repair --status reverted 20261021100200
-- 注意: 適用中に作った関数は PUBLIC の EXECUTE を持たないまま。必要なら、その関数ごとに grant する。
begin;
alter default privileges for role postgres grant execute on functions to public;
commit;
