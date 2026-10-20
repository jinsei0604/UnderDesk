-- 復旧用（migration ではない。問題が出た時だけ手で流す）: 20261021000000_revoke_direct_table_access.sql の直前の
-- 権限・ポリシーに戻す。2026-10-21 の本番の状態（supabase/tools/inspect_public_access.sql で記録）と同じにする。
--
-- 流し方（リポジトリの直下）:
--   supabase db query --linked -f supabase/rollback/20261021000000_restore_direct_table_access.sql
--   supabase migration repair --status reverted 20261021000000   （migration の履歴も「当てていない」に戻す時）
-- 流した後: supabase db query --linked -f supabase/tools/inspect_public_access.sql で、修正前の記録と同じかを確かめる。
--
-- 注意: これを流すと、公開用の鍵で bosses（公開した人の SteamID を含む）を直接読める状態に戻る。

begin;

-- bosses（修正前: anon・authenticated に SELECT・REFERENCES・TRIGGER・TRUNCATE・MAINTAIN、公開済みの行を読む policy）
grant select, references, trigger, truncate, maintain on table public.bosses to anon, authenticated;
drop policy if exists "bosses_select_published_only" on public.bosses;
create policy "bosses_select_published_only"
    on public.bosses
    for select
    to anon, authenticated
    using (is_published);

-- boss_challenge_records（修正前: anon・authenticated に REFERENCES・TRIGGER・TRUNCATE・MAINTAIN。SELECT は無し）
grant references, trigger, truncate, maintain on table public.boss_challenge_records to anon, authenticated;

-- boss_connection_tests（修正前: anon に SELECT・INSERT・REFERENCES・TRIGGER・TRUNCATE・MAINTAIN、
-- authenticated に REFERENCES・TRIGGER・TRUNCATE・MAINTAIN、anon が読み書きできる policy 2つ）
grant select, insert, references, trigger, truncate, maintain on table public.boss_connection_tests to anon;
grant references, trigger, truncate, maintain on table public.boss_connection_tests to authenticated;
drop policy if exists "poc_anon_select_boss_connection_tests" on public.boss_connection_tests;
create policy "poc_anon_select_boss_connection_tests"
    on public.boss_connection_tests
    for select
    to anon
    using (true);
drop policy if exists "poc_anon_insert_boss_connection_tests" on public.boss_connection_tests;
create policy "poc_anon_insert_boss_connection_tests"
    on public.boss_connection_tests
    for insert
    to anon
    with check (true);

commit;
