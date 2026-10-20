# 人気・高難度のランキングを DB のビューで集計する（未実装・検証計画）

2026-10-20。ユーザーの判断で **本番には入れず、検証計画として残す**。DB・Edge Function は変えていない。

## 1. 今の作り（list-popular-bosses・list-hard-bosses）
公開中のボスを全件（カードの列だけ）と、挑戦の記録を全件（1,000行ずつ）読み、関数の中で数えて並べ、上位 limit 件を返す。読む量は「公開ボスの数＋挑戦の記録の数」に比例する。

| 公開ボス / 記録 | DB の呼び出し | 読む行 | DB → 関数 |
|---|---|---|---|
| 100 / 約800 | 4回 | 793行 | 約 100KB |
| 1,000 / 約8,000 | 10回 | 7,993行 | 約 1.0MB |
| 5,000 / 約40,000 | 42回 | 39,993行 | 約 5.0MB |

（偽の DB（`functions/_shared/fake_postgrest_client.ts`）に件数を入れ、関数をそのまま動かして測った。2026-10-18）

## 2. 案
| 案 | 中身 | 1回に関数が読む量 | DB の仕事 | 鮮度 | 変えるもの |
|---|---|---|---|---|---|
| **V1 ふつうのビュー**（推奨・最初の一歩） | 記録をボスごとに数えるビュー。関数は `order=…&limit=20` で上位だけ読む | 20行・約5KB（件数に関係なく一定） | 呼ばれるたびに記録を集計（`boss_challenge_records_boss_id_idx` あり） | 常に最新（今と同じ） | ビュー1つ・権限・2関数の読み方 |
| V2 マテリアライズドビュー | V1 を表として保存し、数分ごとに作り直す（pg_cron） | 約5KB | 作り直しの時だけ集計 | 数分遅れる | V1 ＋ 定期の作り直し・一意の索引 |
| V3 書き込み時に集計の表を更新 | 挑戦の記録の関数が、ボスごとの数を1つずつ足す | 約5KB | 書き込みのたびに少し | 常に最新 | 表1つ・記録の2関数・索引 |

効果の見積もり（V1）: 公開ボス1,000件・記録8,000件で、DB → 関数が約1.0MB・10回 → 約5KB・1回（約99.5%減）。5,000件・40,000件で約5.0MB・42回 → 約5KB・1回。

## 3. 今と同じ順位にするための決まり
- ユニーク挑戦者＝そのボスの記録の行数（`unique (boss_id, challenger_steam_id)` で1人1行）、総挑戦回数＝`challenge_count` の合計、クリアした人＝`clear_count > 0` の行数、補正クリア率＝(クリアした人＋1)/(挑戦者＋2)（float8。関数の JS の double と同じ）。
- 人気: `unique_challengers desc, total_challenges desc, published_at desc, id asc`
- 高難度: `unique_challengers >= 5` のうち `corrected_clear_rate asc, unique_challengers desc, published_at desc, id asc`
- モード: `creator_mode = 'advanced'` か、それ以外（null を含む）。
- 返す項目は今と同じ（カードの列＋数）。SteamID の列はビューに入れない。

## 4. V1 の SQL の下書き（未適用・未検証）
```sql
create or replace view public.public_boss_rankings
with (security_invoker = true) as
select
  b.id, b.boss_name, b.author_name, b.published_at, b.revision,
  b.payload -> 'draft_fields' ->> 'creator_mode' as creator_mode,
  b.payload -> 'draft_fields' -> 'appearance_id' as appearance_id,
  coalesce(s.unique_challengers, 0) as unique_challengers,
  coalesce(s.total_challenges, 0) as total_challenges,
  coalesce(s.unique_clearers, 0) as unique_clearers,
  (coalesce(s.unique_clearers, 0) + 1)::float8 / (coalesce(s.unique_challengers, 0) + 2) as corrected_clear_rate
from public.bosses b
left join (
  select boss_id,
         count(*)::int as unique_challengers,
         coalesce(sum(challenge_count), 0)::int as total_challenges,
         (count(*) filter (where clear_count > 0))::int as unique_clearers
  from public.boss_challenge_records
  group by boss_id
) s on s.boss_id = b.id
where b.is_published and b.published_at is not null;

-- 関数（service_role）だけが読む。ゲームの公開用の鍵（anon）からは読めないようにする
revoke all on public.public_boss_rankings from anon, authenticated;
grant select on public.public_boss_rankings to service_role;
```
関数の読み方: 人気 `order=unique_challengers.desc,total_challenges.desc,published_at.desc,id.asc&limit=20`、高難度 `unique_challengers=gte.5&order=corrected_clear_rate.asc,unique_challengers.desc,published_at.desc,id.asc&limit=20`、モード `creator_mode=eq.advanced` / `or=(creator_mode.is.null,creator_mode.neq.advanced)`。

## 5. 検証計画（本番に入れる前に必ず）
1. **開発用の Supabase プロジェクト**（本番以外）に今の migrations を流し、上のビューを作る。無料枠のプロジェクトは2つまでなので、作る前に数を確かめる。
2. 試しのデータを入れる（公開ボス 100・1,000・5,000件、挑戦の記録はボスごとにばらつかせる。同じ挑戦者数・同じ補正クリア率の同点を必ず含める。非公開のボス・記録の無いボス・数字の外見 ID も含める）。
3. **順位の一致**: 今の2関数と、ビューを読む新しい2関数に同じ問い合わせ（モードなし・SIMPLE・HARDCORE、limit 5・20）をし、応答を比べる（`supabase/tools/compare_function_responses.ts` と同じ方法）。違いが0になること。
4. **公開範囲**: 公開用の鍵（anon）でビューを REST から直接読むと拒否されること。応答に SteamID が出ないこと（`functions/_shared/public_exposure.test.ts`）。
5. **重さ**: 開発用のプロジェクトで 1,000件・5,000件の時の関数の応答時間と、DB の負荷（`supabase inspect db`）を、今の関数と比べる。V1 の集計が重ければ V2 を検討する。
6. **関数のテスト**: 偽の DB にビューと同じ並びの表を用意し、deno のテストを足す（順位・モード・limit・同点・空）。
7. **本番へ**: ビューを作る migration → 関数を1つずつデプロイ（人気 → 高難度）→ 今の確認の道具（`supabase/tools/check_deployed_functions.mjs`）で前後を比べる。
8. **戻し方**: 関数を前の版に再デプロイするだけで戻る（ビューは残しても害が無い。消す時は `drop view public.public_boss_rankings`）。
