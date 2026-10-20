-- 公開用の鍵（anon）・ログイン利用者（authenticated）から、表への直接の読み書きの権限を外す（2026-10-21）。
--
-- 理由: bosses は「公開済みの行は誰でも読める」RLS と anon・authenticated への SELECT（全列）を持っていたため、
-- ゲームに入っている公開用の鍵で /rest/v1/bosses を直接読むと、公開した人の SteamID（owner_steam_id）・
-- battle_hash・idempotency_key まで取れた（get-boss で SteamID を返さないようにしても、表を直接読めば同じ）。
-- ゲームは表を直接読まない（一覧・詳細・公開・挑戦の記録はすべて Edge Function 経由。関数は service_role）ので、
-- 直接の権限は要らない。boss_challenge_records・boss_connection_tests も同じく外す（boss_connection_tests は
-- 接続確認の PoC の表。今のゲームでは使っていない。表と中身は消さない）。
--
-- 変えないもの: service_role の権限（bosses の SELECT/INSERT/UPDATE、boss_challenge_records の SELECT、
-- 挑戦の記録の関数の EXECUTE）、各表の RLS の有効化（すべて有効のまま）、表・列・中身、既定の権限（default privileges）。
-- 戻し方: supabase/rollback/20261021000000_restore_direct_table_access.sql（このファイルの直前の状態に戻す）。

-- bosses
revoke all on table public.bosses from anon, authenticated, public;
drop policy if exists "bosses_select_published_only" on public.bosses;
alter table public.bosses enable row level security;

-- boss_challenge_records（SELECT は元から無い。TRUNCATE・TRIGGER・REFERENCES・MAINTAIN も外す）
revoke all on table public.boss_challenge_records from anon, authenticated, public;
alter table public.boss_challenge_records enable row level security;

-- boss_connection_tests（PoC。誰でも読み書きできた）
revoke all on table public.boss_connection_tests from anon, authenticated, public;
drop policy if exists "poc_anon_select_boss_connection_tests" on public.boss_connection_tests;
drop policy if exists "poc_anon_insert_boss_connection_tests" on public.boss_connection_tests;
alter table public.boss_connection_tests enable row level security;
