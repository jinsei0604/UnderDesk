-- 復旧用（問題が出た時だけ手で流す。migration ではない）: 20261122000000_add_published_edition_to_bosses.sql の直前に戻す。
-- 先に、published_edition を書く publish-boss を前の版へ戻す（列を消してから戻すと、その間の公開が失敗する）。
-- 流し方（リポジトリの直下）: supabase db query --linked -f supabase/rollback/20261122000000_drop_published_edition_from_bosses.sql
-- 続けて: supabase migration repair --status reverted 20261122000000
-- ボスの行・公開状態は消えない（published_edition の列だけを消す）。
begin;
alter table public.bosses drop constraint if exists bosses_published_edition_check;
alter table public.bosses drop column if exists published_edition;
commit;
