-- 復旧用（問題が出た時だけ手で流す。migration ではない）: 20261023000000_hard_defeat_award.sql の直前に戻す。
-- 先に、戦闘チケット・結果の受け付け・認定の一覧の Edge Functions（issue-battle-ticket・submit-battle-result・
-- list-my-hard-awards）を止め、集計の関数（一覧・検索・ランダム・未挑戦・人気・高難度・挑戦の記録）を前の版へ戻してから流す。
-- 注意: 足した列（挑戦結果の回数・初回クリアの数・難関の認定日時）とチケットの表の中身は消える。手元・Steam Cloud の
-- 討伐記録に既に入った「難関」は消えない（ゲームは消さない）。
-- 流し方（リポジトリの直下）: supabase db query --linked -f supabase/rollback/20261023000000_drop_hard_defeat_award.sql
-- 続けて: supabase migration repair --status reverted 20261023000000
begin;
drop function if exists public.submit_boss_battle_result(uuid, uuid, text, uuid, text);
drop function if exists public.issue_boss_battle_ticket(uuid, text);
drop function if exists public.award_hard_defeats(uuid);
drop function if exists public.boss_hard_defeat_qualifies(bigint, bigint, bigint);
drop function if exists public.boss_hard_defeat_stats(uuid, text);
drop table if exists public.boss_battle_tickets;
drop trigger if exists boss_challenge_records_keep_permanent on public.boss_challenge_records;
drop function if exists public.boss_challenge_records_keep_permanent();
alter table public.boss_challenge_records drop constraint if exists boss_challenge_records_hard_fields_valid;
alter table public.boss_challenge_records
    drop column if exists hard_awarded_at,
    drop column if exists first_clear_clearers,
    drop column if exists first_clear_challengers,
    drop column if exists result_clear_count,
    drop column if exists result_count;
commit;
