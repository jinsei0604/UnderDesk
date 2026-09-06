-- Supabase 最小接続PoC (Phase 4準備の接続確認のみ、本実装ではない)
--
-- ⚠️ このテーブル・ポリシーは「Steam認証導入前のPoC専用」です。
--    本番公開前に削除または置換が必要です。
--    本番用bossesテーブルとは完全に分離されており、
--    本番テーブルへ同じRLS設計（匿名SELECT/INSERT許可）を
--    使ってはいけません。
--
-- 目的: GodotからSupabaseへテスト用ボスデータを1件保存し、
--       そのデータを取得できることだけを確認する。

create table if not exists public.boss_connection_tests (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    boss_data jsonb not null,
    created_at timestamptz not null default now()
);

comment on table public.boss_connection_tests is
    'Supabase接続確認専用のPoCテーブル。Steam認証導入前の一時的なもの。'
    '本番公開前に削除または置換すること。本番bossesテーブルとは分離されている。';

-- Row Level Security を有効化する。
alter table public.boss_connection_tests enable row level security;

-- ⚠️ PoC専用の一時ポリシー: Steam認証がまだ無いため、匿名ユーザー
-- （publishable key経由のanon role）からのSELECT/INSERTのみを許可する。
-- UPDATE/DELETEは許可しない（今回不要、必要以上の権限を与えない）。
--
-- 本番bossesテーブルでは、これと同じ「誰でも書き込める」ポリシーを
-- 絶対に使わないこと——認証済みユーザー（自分の投稿のみ）等、
-- 適切な条件を設計すること。

-- SQL Editorへ誤って二重に貼り付け・実行してもエラーにならないよう、
-- create policyの前にdrop policy if existsを置く（べき等性、安全策）。
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

-- 新規プロジェクトはSupabaseの既定のDEFAULT PRIVILEGESにより通常
-- anon/authenticatedへ自動的にSELECT/INSERT/UPDATE/DELETEが付与されるが、
-- 既定を変更済みの環境でも動くよう明示的にGRANTしておく（UPDATE/DELETEは
-- 付与しない——RLSポリシーが無い操作なのでどのみち拒否されるが、権限自体を
-- 与えないことで「必要以上の権限を付与しない」を二重に保証する）。
grant select, insert on public.boss_connection_tests to anon;

