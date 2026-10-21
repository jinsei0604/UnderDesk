-- これから postgres（migration・ダッシュボード）が public に作る表・順序・関数に、ゲームの公開用の鍵（anon）・
-- authenticated の権限が自動で付かないようにする（2026-10-21）。既にある表・関数の権限は変わらない
-- （ALTER DEFAULT PRIVILEGES は、この後に作る物だけに効く）。service_role の既定は変えない。
--
-- 適用前の本番（2026-10-21 に記録）:
--   表: anon・authenticated・service_role に TRUNCATE・REFERENCES・TRIGGER・MAINTAIN が付く
--       （SELECT・INSERT・UPDATE・DELETE は Supabase の「新しい表を自動で公開しない」設定で既に外れている）
--   順序・関数: スキーマ public の既定では anon・authenticated に何も付かない（下の2行は、その状態を明示して固定する）
-- 関数の PUBLIC の EXECUTE（PostgreSQL の全体の既定）は、スキーマ単位では外せないので、次の migration（20261021100200）で外す。
-- 戻し方: supabase/rollback/20261021100100_restore_default_privileges_in_public.sql

alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;
