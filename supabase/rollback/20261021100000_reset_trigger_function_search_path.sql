-- 復旧用（問題が出た時だけ手で流す。migration ではない）: 20261021100000_fix_trigger_function_search_path.sql の直前（search_path の設定なし）に戻す。
-- 流し方（リポジトリの直下）: supabase db query --linked -f supabase/rollback/20261021100000_reset_trigger_function_search_path.sql
-- 続けて: supabase migration repair --status reverted 20261021100000
begin;
alter function public.bosses_set_updated_at() reset search_path;
alter function public.boss_challenge_records_set_updated_at() reset search_path;
commit;
