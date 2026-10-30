-- ローカルの検証用のボス（公開200体・非公開5体）。本番には流さない。
insert into public.bosses (id, owner_steam_id, boss_name, schema_version, payload, battle_hash, idempotency_key, is_published, published_at)
select ('00000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, '76561190000000001', 'local-test-' || g, 1,
       '{"draft_fields": {"creator_mode": "simple", "appearance_id": "appearance_slime"}}'::jsonb, repeat('a', 64), 'local-' || g, g <= 200, now()
from generate_series(1, 205) g;
