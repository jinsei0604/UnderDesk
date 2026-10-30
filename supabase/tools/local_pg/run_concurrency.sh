#!/bin/bash
# 15体の制限の同時の要求の検証（ローカルの PostgreSQL 17.6 だけ。本番には繋がない）。
source "$(dirname "${BASH_SOURCE[0]}")/conc.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
ng() { FAIL=$((FAIL+1)); echo "  不合格: $*"; }
tally() { sort | uniq -c | awk '{printf "%s×%s ", $2, $1}'; }
seq_ids() { local s=$1 a=$2 b=$3; for x in $(seq $a $b); do printf '%s:%s ' $s $x; done; }

echo "== S1 14体から別々の新しい2体へ同時（50回）"
for r in $(seq 1 50); do
  P=7656119100000$(printf '%04d' $r); prefill $P 14
  res=$(burst $P:101 $P:102 | awk '{print $1}' | sort | tr '\n' ' ')
  c=$(count $P); [ "$res" = "claimed limit " ] && [ "$c" = 15 ] && ok || ng "S1 round $r: $res count=$c"
done
echo "  結果: 合格 $PASS / 不合格 $FAIL"

echo "== S2 13体から別々の新しい3〜10体へ同時（各10回）"
for k in 3 5 10; do for r in $(seq 1 10); do
  P=76561192000$(printf '%02d%04d' $k $r); prefill $P 13
  res=$(burst $(seq_ids $P 101 $((100+k))) | awk '{print $1}')
  cl=$(echo "$res" | grep -c '^claimed'); li=$(echo "$res" | grep -c '^limit'); c=$(count $P)
  [ $cl = 2 ] && [ $li = $((k-2)) ] && [ "$c" = 15 ] && ok || ng "S2 k=$k round $r: claimed=$cl limit=$li count=$c"
done; done
echo "  累計: 合格 $PASS / 不合格 $FAIL"

echo "== S3 0体から別々の新しい40体へ同時（5回）"
for r in $(seq 1 5); do
  P=76561193000000$(printf '%02d' $r); prefill $P 0
  res=$(burst $(seq_ids $P 101 140) | awk '{print $1}')
  cl=$(echo "$res" | grep -c '^claimed'); c=$(count $P)
  [ $cl = 15 ] && [ "$c" = 15 ] && ok || ng "S3 round $r: claimed=$cl count=$c $(echo "$res" | tally)"
done
echo "  累計: 合格 $PASS / 不合格 $FAIL"

echo "== S4 15体の後: 新しいボスは断る・挑戦済みのボスへは同時に何度でも（10回）"
for r in $(seq 1 10); do
  P=76561194000000$(printf '%02d' $r); prefill $P 15
  res=$(burst $P:150 $P:151 $(for x in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do printf '%s:%s %s:%s ' $P $x $P $x; done) | awk '{print $1}')
  li=$(echo "$res" | grep -c '^limit'); al=$(echo "$res" | grep -c '^already'); c=$(count $P)
  [ $li = 2 ] && [ $al = 30 ] && [ "$c" = 15 ] && ok || ng "S4 round $r: limit=$li already=$al count=$c"
done
echo "  累計: 合格 $PASS / 不合格 $FAIL"

echo "== S5 同じボスへの同時の要求は1回だけ数える（10体から20本×10回・14体から20本×10回）"
for base in 10 14; do for r in $(seq 1 10); do
  P=7656119500$(printf '%02d%04d' $base $r); prefill $P $base
  res=$(burst $(for x in $(seq 1 20); do printf '%s:120 ' $P; done) | awk '{print $1}')
  cl=$(echo "$res" | grep -c '^claimed'); al=$(echo "$res" | grep -c '^already'); c=$(count $P)
  [ $cl = 1 ] && [ $al = 19 ] && [ "$c" = $((base+1)) ] && ok || ng "S5 base=$base round $r: claimed=$cl already=$al count=$c"
done; done
echo "  累計: 合格 $PASS / 不合格 $FAIL"

echo "== S6 別々の8人が同時に各20体（160本×5回）・ほかの人を待たせない・数え合わない"
for r in $(seq 1 5); do
  reqs=""; players=""
  for p in $(seq 1 8); do P=7656119600$(printf '%02d%04d' $p $r); players="$players $P"; prefill $P $(( (p-1) % 3 * 6 )); reqs="$reqs $(seq_ids $P 101 120)"; done
  res=$(burst $reqs); errs=$(echo "$res" | grep -c '^error')
  bad=0; for P in $players; do [ "$(count $P)" = 15 ] || bad=$((bad+1)); done
  [ $errs = 0 ] && [ $bad = 0 ] && ok || ng "S6 round $r: errors=$errs 15体でない人=$bad"
done
echo "  累計: 合格 $PASS / 不合格 $FAIL"

echo "合計: 合格 $PASS / 不合格 $FAIL"
