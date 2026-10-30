#!/bin/bash
# 異常系・分離レベル・権限の検証（ローカルの PostgreSQL だけ）
source "$(dirname "${BASH_SOURCE[0]}")/conc.sh"
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  合格: $1"; else FAIL=$((FAIL+1)); echo "  不合格: $1（期待 '$3'・実際 '$2'）"; fi; }
q() { $PSQL -c "$1" 2>&1 | grep -v -E '^(SET|BEGIN|COMMIT|ROLLBACK)$' | tr -d '\r'; }
P=76561198100000001

echo "== S7 エラー・トランザクションの失敗で枠が残らない"
prefill $P 3; prefill 76561198100000002 0
check "非公開のボス → not_found・行なし" "$(q "set role service_role; select status||' '||used from public.claim_demo_challenge_slot('$(bid 201)'::uuid, '$P');")" "not_found 3"
check "存在しないボス → not_found" "$(q "set role service_role; select status from public.claim_demo_challenge_slot(gen_random_uuid(), '$P');")" "not_found"
q "begin; set local role service_role; select * from public.claim_demo_challenge_slot('$(bid 150)'::uuid, '$P'); rollback;" >/dev/null
check "枠を取った後に取り消したトランザクション → 行が残らない" "$(count $P)" "3"
q "begin; set local role service_role; select * from public.claim_demo_challenge_slot('$(bid 151)'::uuid, '$P'); select 1/0; commit;" >/dev/null
check "枠を取った後に同じトランザクションでエラー → 行が残らない" "$(count $P)" "3"
r=$(q "set role service_role; select status from public.claim_demo_challenge_slot('$(bid 152)'::uuid, 'abc');")
check "数字でない SteamID → 制約のエラー（行なし）" "$(echo "$r" | grep -c 'check constraint')" "1"
check "  その時の表の行（abc）" "$(sql "select count(*) from public.demo_challenge_slots where steam_id='abc'")" "0"
# ロックを持ったまま接続が切れた時: ほかの要求は進み、途中の行は残らない
$PSQL -c "begin; set local role service_role; select * from public.claim_demo_challenge_slot('$(bid 153)'::uuid, '$P'); select pg_sleep(30); commit;" >/dev/null 2>&1 &
holder=$!; until [ "$(sql "select count(*) from pg_stat_activity where query like '%pg_sleep(30)%' and state='active' and pid<>pg_backend_pid()")" = 1 ]; do sleep 0.1; done
t0=$(date +%s%N); other=$(q "set role service_role; select status from public.claim_demo_challenge_slot('$(bid 154)'::uuid, '76561198100000002');"); t1=$(date +%s%N)
check "ロック中でも別の人の要求は待たない（1秒未満）" "$(( (t1-t0)/1000000 < 1000 ))" "1"
check "  その結果" "$other" "claimed"
sql "select pg_terminate_backend(pid) from pg_stat_activity where query like '%pg_sleep(30)%' and pid<>pg_backend_pid()" >/dev/null; wait $holder 2>/dev/null
check "ロックを持った接続が切れた → 途中の行は残らない" "$(count $P)" "3"
check "  その後の同じ人の要求は進む" "$(q "set role service_role; select status||' '||used from public.claim_demo_challenge_slot('$(bid 155)'::uuid, '$P');")" "claimed 4"

echo "== S8 分離レベルの安全対策"
prefill $P 14
r=$(q "begin isolation level repeatable read; set local role service_role; select status from public.claim_demo_challenge_slot('$(bid 160)'::uuid, '$P'); commit;")
check "repeatable read → エラーで止まる" "$(echo "$r" | grep -c 'requires read committed isolation (current: repeatable read)')" "1"
check "  上限の表示（limit）にしない" "$(echo "$r" | grep -c -w 'limit')" "0"
check "  行は増えない" "$(count $P)" "14"
r=$(q "begin isolation level serializable; set local role service_role; select status from public.claim_demo_challenge_slot('$(bid 160)'::uuid, '$P'); commit;")
check "serializable → エラーで止まる" "$(echo "$r" | grep -c 'requires read committed isolation (current: serializable)')" "1"
check "  行は増えない" "$(count $P)" "14"
r=$($PSQL -c "set default_transaction_isolation = 'repeatable read'" -c "set role service_role" -c "select status from public.claim_demo_challenge_slot('$(bid 160)'::uuid, '$P')" 2>&1)
check "接続の既定を repeatable read にした時もエラー" "$(echo "$r" | grep -c 'requires read committed')" "1"
r=$(q "begin isolation level repeatable read; set local role service_role; select status from public.claim_demo_challenge_slot('$(bid 3)'::uuid, '$P'); commit;")
check "挑戦済みのボスでも repeatable read ならエラー（何も書かない）" "$(echo "$r" | grep -c 'requires read committed')" "1"
check "read committed では今までどおり（15体目）" "$(q "begin isolation level read committed; set local role service_role; select status||' '||used from public.claim_demo_challenge_slot('$(bid 160)'::uuid, '$P'); commit;")" "claimed 15"
check "状況の読み取り（demo_challenge_status）は repeatable read でも読める" "$(q "begin isolation level repeatable read; set local role service_role; select used from public.demo_challenge_status('$P'); commit;")" "15"
prefill $P 13
res=$(burst $(for x in 101 102 103 104 105 106; do printf '%s:%s:rr ' $P $x; done) | awk '{print $1}' | sort | uniq -c | tr -s ' ' | tr '\n' ',')
check "13体から repeatable read で6本同時 → 全部エラー・行は増えない" "$res|$(count $P)" " 6 error,|13"

echo "== S9 クライアント（anon・authenticated）から直接は触れない"
for role in anon authenticated; do
  for stmt in "select * from public.demo_challenge_slots" "insert into public.demo_challenge_slots values ('1', gen_random_uuid())" "delete from public.demo_challenge_slots" "select * from public.claim_demo_challenge_slot(gen_random_uuid(), '1')" "select * from public.demo_challenge_status('1')"; do
    r=$(q "set role $role; $stmt;"); check "$role: ${stmt:0:60}" "$(echo "$r" | grep -c 'permission denied')" "1"
  done
done
check "service_role も表は直接読めない（関数経由だけ）" "$(q "set role service_role; select count(*) from public.demo_challenge_slots;" | grep -c 'permission denied')" "1"
check "anon・authenticated が実行できる public の関数（トリガー用を除く）の数" "$(sql "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.prorettype <> 'trigger'::regtype and ( has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'))")" "0"
check "トリガー用の関数は直接は呼べない（anon）" "$(q "set role anon; select public.bosses_set_updated_at();" | grep -c 'trigger functions can only be called as triggers')" "1"
check "anon・authenticated が触れる public の表の数" "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where c.relkind='r' and (has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE') or has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE'))")" "0"
echo "合計: 合格 $PASS / 不合格 $FAIL"
