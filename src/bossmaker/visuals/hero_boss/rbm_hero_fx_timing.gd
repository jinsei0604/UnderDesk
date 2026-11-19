class_name RBMHeroFxTiming
extends RefCounted
## ヒーロー（hero_boss）の5種類の技の時刻表（秒）。開始・終了・命中はここの数字だけ直せばよい。音（assets_bossmaker/audio/hero_boss）もこの時刻で作った。
## tame_frame・tame_hold: 正式モーション（motion/exposures.json）の指定のコマを止める長さだけ足す（絵と座標は変えない）。
## body_swap: [開始コマ, コマ数, 見せるコマ名, 左上座標]。見せるコマだけを差し替える（2026-11-10 ④の切った後の直立をやめた）。
## offset は技全体をモーションに対して前後へずらす量。モーションが変わったらまず contact 系を合わせる。

const BLADE := {
	"offset": 0.0, "duration": 3.733,
	"tame_frame": 32, "tame_hold": 10,
	"charge": 0.30, "draw": 0.73, "tame": 1.067, "dash": 1.483, "contact": 1.733, "seam": 2.063, "end": 3.333,
}
const ARRAY := {
	"offset": 0.0, "duration": 5.933,
	"tame_frame": 26, "tame_hold": 15,
	"charge": 0.26, "stage2": 1.20, "palms": 2.00, "pinch": 3.08, "fire": 3.33, "pulses": [3.45, 3.71, 3.97, 4.23], "final": 4.50, "cut": 4.84, "end": 5.8,
}
const BREACH := {
	"offset": 0.0, "duration": 6.27,
	"tame_frame": 130, "tame_hold": 18,
	"glitches": [0.57, 0.98, 1.25, 1.63], "runaway": 1.62, "invade": 2.05, "surges": [2.05, 2.33, 2.60], "collapse": 2.86, "blackout": 3.02,
	"release": 3.24, "settle": 3.90, "tame": 4.35, "complete": 5.42, "end": 6.2,
}
const SHEAR := {
	"offset": 0.0, "duration": 4.03,
	"body_swap": [[76, 11, "shear1", [198, 190]]],
	"charge": 0.30, "dash": 1.23, "cut1": 1.45, "cut2": 1.92, "final": 2.24, "end": 3.8,
}
const PRESS := {
	"offset": 0.0, "duration": 6.47,
	"dock": 0.22, "edge": 1.10, "sentence": [1.62, 1.82, 2.02, 2.22], "leap": 1.97, "edge_off": 3.14, "strike": 3.233, "drop": 3.28,
	"jets": [[214, 0.34], [150, 0.38], [280, 0.39], [86, 0.43], [346, 0.44], [22, 0.48], [412, 0.49], [478, 0.54], [-40, 0.53], [544, 0.59], [610, 0.64]],
	"hits": [3.28, 3.34, 3.41, 3.48], "rupture": 3.85, "close": 4.42, "end": 6.2,
}
## 覚醒後の撃破（2026-11-11）: 膝をつく → 闇が暴れ、内から青い光が漏れる（鼓動3回）→ 闇が爆ぜて青い光の柱 → 元の青い姿で膝をつき、光の粒になって昇る。
## 撃破の演出（RBMVictoryPlayer の begin から）の秒。とどめのスローはこの前（全ボス共通）。
const FALL := {
	"offset": 0.0, "duration": 3.1,
	"kneel": 0.16, "beats": [0.42, 0.64, 0.84], "burst": 1.04, "restore": 1.3, "fade": 2.1, "gone": 3.0, "end": 3.1,
}
## 登場（2026-11-17「救難信号」、2026-11-19 ユーザーの指摘で照射器を動かさない・手を突き出すコマを使わない形に）:
## 屋上の2つの照射器が最初から床の着地点を照らしている → 流れ星が光の中へ落ちてヒーロー着地 → 立ち上がり、腕を組む
## → 腕を組んだまま背後で大爆発。登場の再生の秒（LEAD の後の0秒から）。
const INTRO := {
	"offset": 0.0, "duration": 4.4,
	"fall": 0.85, "land": 1.15, "rise": 2.10, "arms": 2.40, "boom": 2.90, "settle": 3.85, "end": 4.4
}
## 覚醒前の撃破（2026-11-17「力尽きる」、2026-11-19 ユーザーの指摘で最後に照射器で照らす所を外した）。撃破の演出（begin から）の秒。
## よろめく（頭を押さえる）・鎧から火花 → 胸の灯が赤く点滅し、だんだん速くなる（力が尽きていく。blink_f0→blink_f1 回/秒）
## → 片膝をつく → 胸の灯が消える（out）→ 光の粒になって昇り（melt→gone）、粒が消えて終わる。
const DOWN := {
	"offset": 0.0, "duration": 3.7,
	"stand": 0.30, "sparks": [0.10, 0.36, 0.60, 0.84, 1.04], "blink": 0.15, "blink_f0": 2.0, "blink_f1": 7.0,
	"kneel": 1.25, "out": 1.80, "melt": 2.00, "gone": 3.00, "end": 3.7
}
## 支援（2026-11-17）: 立ち姿 → 支援のポーズ（1回だけ切り替え）→ 立ち姿。覚醒前の回復＝光の粒が胸の灯へ集まる（照射器は使わない、2026-11-19）、
## 覚醒前の強化＝力をためて青いオーラが燃え上がる、覚醒後の回復＝闇を吸い込む、覚醒後の強化＝黒紅のオーラが燃え上がる。
const SUPPORT := {
	"offset": 0.0, "duration": 2.5,
	"pose": 0.20, "gather": 0.50, "impact": 1.25, "complete": 1.25, "back": 1.95, "end": 2.45
}
