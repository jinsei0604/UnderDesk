-- migration を全部当てた後に流す（ローカルの検証用だけ）。00_supabase_roles.sql の既定の権限は Supabase の初期状態をまねた物で、
-- 本番では record_boss_challenge_attempt・record_boss_challenge_clear を anon・authenticated が実行できない
-- （2026-10-30 に本番を読み取りで確認）。ローカルもそれに合わせる。
revoke execute on function public.record_boss_challenge_attempt(uuid, text), public.record_boss_challenge_clear(uuid, text) from anon, authenticated;
