-- トリガー関数の search_path を空に固定する（2026-10-21、Supabase のセキュリティ診断 0011 function_search_path_mutable の2件）。
--
-- 対象: updated_at を入れる BEFORE UPDATE のトリガー関数2つ（bosses・boss_challenge_records）。
-- 今の状態: どちらも SECURITY INVOKER（SECURITY DEFINER ではない）、本体は new.updated_at := now() だけ、
-- 表を名前で参照しない。now() は pg_catalog の関数で、pg_catalog は search_path に無くても先に探されるので、
-- 今の中身のままなら呼び出し側の search_path で別の物にすり替わることは無い（実際の危険はほぼ無い）。
-- 固定する理由: 今後この関数に表や関数の参照を書き足した時に、呼び出し側（service_role・postgres）の
-- search_path で解決先が変わらないようにする予防。中身・動き・権限・トリガーは変えない（ALTER FUNCTION の SET だけ）。
-- 空の search_path にした後に参照を書き足す時は、必ず public.〇〇 のようにスキーマを付ける。
-- 空実行（本番で当ててから取り消す）で、更新すると updated_at が今までどおり now() になることを確かめた。
-- 戻し方: supabase/rollback/20261021100000_reset_trigger_function_search_path.sql

alter function public.bosses_set_updated_at() set search_path = '';
alter function public.boss_challenge_records_set_updated_at() set search_path = '';
