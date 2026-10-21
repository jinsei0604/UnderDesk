-- 復旧用（問題が出た時だけ手で流す。migration ではない）: 20261021100100_restrict_default_privileges_in_public.sql の直前に戻す。
-- 流し方（リポジトリの直下）: supabase db query --linked -f supabase/rollback/20261021100100_restore_default_privileges_in_public.sql
-- 続けて: supabase migration repair --status reverted 20261021100100
-- 注意: 既定の権限は「この後に作る物」だけに効く。適用中に作った表・関数があれば、その権限は別に確かめる。
begin;
-- 表: 適用前は anon・authenticated に TRUNCATE・REFERENCES・TRIGGER・MAINTAIN
alter default privileges for role postgres in schema public grant truncate, references, trigger, maintain on tables to anon, authenticated;
-- 順序・関数（スキーマ public）: 適用前も anon・authenticated には何も付いていなかったので、戻す物は無い
commit;
