-- 2026-11-22 体験版のオンライン公開の上限（1人2体）を「体験版から公開した分」だけで数える（ユーザー確定）。
--
-- それまでの publish-boss は、同じ Steam アカウントで公開中のボスを製品版から公開した分も含めて数えていたので、
-- 製品版で公開したボスがあると、体験版では2体に届く前に断られた（ゲームは手元の体験版の保存だけを数えて先へ進むため、
-- 最後にサーバーで 403 demo_publish_limit になっていた）。
--
-- published_edition: そのボスを最後に公開した版。'demo'（体験版のアプリの Steam チケット）／'full'（製品版）。
-- 値は publish-boss が Steam のチケットで確かめた版から入れる（クライアントの申告は使わない）。公開・更新のたびに書き直す。
-- 今ある行は null（どちらから公開したか分からない）。体験版の上限は published_edition='demo' の行だけを数えるので、
-- 今ある行は数えない（既に公開中の体験版のボスも、次に更新・再公開した時から数える）。
--
-- 変えないもの: 公開の決まり（体験版は SIMPLE・体験版の4体だけ）、製品版の利用者（制限なし）、表の権限、RLS。
-- 適用の順序: この migration → publish-boss のデプロイ（逆にすると、無い列へ書いて公開が失敗する）。
-- 戻し方: 先に publish-boss を前の版へ戻してから supabase/rollback/20261122000000_drop_published_edition_from_bosses.sql

alter table public.bosses
    add column if not exists published_edition text;

alter table public.bosses
    drop constraint if exists bosses_published_edition_check;
alter table public.bosses
    add constraint bosses_published_edition_check check (published_edition is null or published_edition in ('demo', 'full'));
