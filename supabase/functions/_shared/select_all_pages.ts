// 人気/高難度ランキング(list-popular-bosses/list-hard-bosses)用 — テーブルの
// 条件に合う全行を、1回の応答の行数上限に関係なく取り切る。
//
// PostgRESTは1回の応答で返す行数に上限がある(Supabaseの「Max rows」、既定
// 1000)。上限を超えた分は黙って切り捨てられるため、1回のselectだけで集計
// すると、記録が増えたときに途中の行が欠けたランキングになる。
//
// そのためidの昇順でキーセット・ページング(id=gt.<前のページの最後のid>)
// しながら読み、「空のページが返るまで」続ける。
//   - 「要求した件数より少ないページ=最後」とは判定しない。サーバー側の上限が
//     PAGE_SIZEより小さく設定されていても、途中で打ち切らないため。
//   - offsetではなくidで進めるので、読んでいる最中に行が追加されても、既存の
//     行を読み飛ばしたり二重に数えたりしない(途中で追加された行は、idが
//     まだ読んでいない側にあれば含まれ、読んだ側にあれば含まれないだけ)。
//   - どこか1ページでも失敗したら、途中までの行は返さずにエラーを返す
//     (欠けたランキングを正しいものとして返さない)。
//
// queryにはselect(idを含めること)と絞り込みだけを渡す。order/limitはこの
// 関数が付ける。

import { RestResult, SupabaseRestClient } from "./supabase_rest_client.ts";

export const PAGE_SIZE = 1000;
// 1000行×10000ページ=1000万行。ここに達するのは異常(idが進まない等)なので、
// 黙って打ち切らずエラーにする。
export const MAX_PAGES = 10000;

export async function selectAllPages<T extends { id: unknown }>(
  db: SupabaseRestClient,
  table: string,
  query: string,
  pageSize: number = PAGE_SIZE,
): Promise<RestResult<T>> {
  const rows: T[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < MAX_PAGES; page++) {
    const keyset: string = cursor === null ? "" : `&id=gt.${cursor}`;
    const result: RestResult<T> = await db.select<T>(table, `${query}${keyset}&order=id.asc&limit=${pageSize}`);
    if (!result.ok) {
      return { ok: false, rows: [], status: result.status, errorMessage: result.errorMessage };
    }
    if (result.rows.length === 0) {
      return { ok: true, rows, status: 200 };
    }
    rows.push(...result.rows);
    const last = String(result.rows[result.rows.length - 1].id);
    if (last === cursor) {
      return { ok: false, rows: [], status: 500, errorMessage: `selectAllPages(${table}): the id cursor did not advance` };
    }
    cursor = last;
  }
  return { ok: false, rows: [], status: 500, errorMessage: `selectAllPages(${table}): more than ${MAX_PAGES} pages` };
}
