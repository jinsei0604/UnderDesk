-- 復旧用（問題が出た時だけ手で流す。migration ではない）: 20261022000000_add_by_owner_to_challenge_records.sql の直前に戻す。
-- 先に、by_owner で絞る Edge Functions を前の版へ戻す（列を消してから戻すと、その間の一覧・人気・高難度が失敗する）。
-- 流し方（リポジトリの直下）: supabase db query --linked -f supabase/rollback/20261022000000_drop_by_owner_from_challenge_records.sql
-- 続けて: supabase migration repair --status reverted 20261022000000
-- 挑戦の記録の行・回数は消えない（by_owner の列だけを消す）。
begin;
drop trigger if exists boss_challenge_records_set_by_owner on public.boss_challenge_records;
drop function if exists public.boss_challenge_records_set_by_owner();
alter table public.boss_challenge_records drop column if exists by_owner;
commit;
