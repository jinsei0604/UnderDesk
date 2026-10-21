-- postgres がこれから作る関数に、PUBLIC の EXECUTE を付けない（2026-10-21）。
--
-- 理由: PostgreSQL は新しい関数に PUBLIC の EXECUTE を付ける（全体の既定）。public に作った関数は、何もしないと
-- ゲームの公開用の鍵で /rest/v1/rpc/<関数> から呼べてしまう（SECURITY DEFINER なら、表の権限を外していても
-- 関数の持ち主の権限で読み書きできる）。スキーマ単位の REVOKE では全体の既定を取り消せないため、スキーマを付けずに行う
-- （PostgreSQL の ALTER DEFAULT PRIVILEGES の説明・Supabase の「Securing your API」の手順と同じ）。
--
-- 効く範囲: postgres が今後作る関数（どのスキーマでも）。既にある関数（挑戦の記録の2関数・トリガー関数・
-- 入っている拡張機能の関数）は変わらない。Supabase の内部機能（認証・ストレージ・リアルタイム・Vault・GraphQL）の関数は
-- 別の役割が作るので効かない。新しく入れる拡張機能は supautils が supabase_admin で作るので効かない（2026-10-21 の空実行で pg_trgm を入れて確認:
-- 持ち主 supabase_admin、31関数すべて PUBLIC の EXECUTE のまま。入れた拡張機能は取り消した）。
-- これから作る関数の決まり: 使う役割へ明示して付ける（例: grant execute on function public.〇〇(引数の型) to service_role;）。
-- 戻し方: supabase/rollback/20261021100200_restore_default_public_function_execute.sql

alter default privileges for role postgres revoke execute on functions from public;
