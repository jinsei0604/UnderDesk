#!/bin/bash
# 同時の要求の検証（ローカルの PostgreSQL だけ）。使い方は下の関数を参照。
B=${PG_BIN:-/c/src/tools/postgresql/17.6/pgsql/bin}
PSQL="$B/psql.exe -h 127.0.0.1 -p ${PG_PORT:-55432} -U postgres -d postgres -X -q -At"
W=${TMPDIR:-/tmp}
BARRIER=424242
bid() { printf '00000000-0000-4000-8000-%012d' "$1"; }
sql() { $PSQL -c "$1"; }
# プレイヤーの枠を n 体（ボス 1..n）で埋める（前の状態を作るだけ）
prefill() { sql "delete from public.demo_challenge_slots where steam_id = '$1'; insert into public.demo_challenge_slots (steam_id, boss_id) select '$1', ('00000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid from generate_series(1, $2) g where $2 > 0;"; }
count() { sql "select count(*) from public.demo_challenge_slots where steam_id = '$1';"; }
# 同時に送る: 引数は "steam_id:boss番号[:isolation]" の並び。結果は1行ずつ status を返す
burst() {
  local tag=$RANDOM$RANDOM; local outdir=$W/out_$tag; mkdir -p $outdir
  # 門番: 排他のロックを持ったまま待つ。全員がロック待ちに並んでから放す
  $PSQL -c "select pg_advisory_lock($BARRIER); select pg_sleep(60);" >/dev/null 2>&1 &
  local gate=$!
  until [ "$(sql "select count(*) from pg_locks where locktype='advisory' and objid=$BARRIER and granted and mode='ExclusiveLock'")" = 1 ]; do sleep 0.05; done
  local i=0
  for req in "$@"; do
    IFS=: read -r sid b iso <<< "$req"; case "$iso" in rr) iso="repeatable read";; ser) iso="serializable";; *) iso="read committed";; esac
    i=$((i+1))
    $PSQL -c "select pg_advisory_lock_shared($BARRIER); select pg_advisory_unlock_shared($BARRIER);" \
          -c "begin isolation level $iso; set local role service_role; select status || ' ' || used from ${FN:-public.claim_demo_challenge_slot}('$(bid $b)'::uuid, '$sid'); commit;" \
          > $outdir/$i.txt 2> $outdir/$i.err &
  done
  # 全員が門の前で待っていることを確かめてから、門番を切って一斉に放す
  local n=$#; local t=0
  until [ "$(sql "select count(*) from pg_locks where locktype='advisory' and objid=$BARRIER and not granted")" = "$n" ]; do sleep 0.05; t=$((t+1)); [ $t -gt 600 ] && { echo "BARRIER_TIMEOUT"; break; }; done
  sql "select pg_terminate_backend(pid) from pg_locks where locktype='advisory' and objid=$BARRIER and granted and mode='ExclusiveLock'" >/dev/null
  wait $gate 2>/dev/null
  wait
  for f in $outdir/*.txt; do n=${f%.txt}; if [ -s $n.err ]; then echo "error $(head -c 120 $n.err | tr '\n' ' ')"; else grep -v '^$' $f | grep -v -E '^(SET|BEGIN|COMMIT)$' | tail -1; fi; done
  rm -rf $outdir
}
