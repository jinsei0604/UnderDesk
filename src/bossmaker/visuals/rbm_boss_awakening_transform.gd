extends Node2D

## ⚠️ 仮の最小限表現(TEMPORARY PLACEHOLDER) — 覚醒(Awakening)の変身演出。
##
## これは正式な演出ではない。今回の実装は「覚醒システム基盤」
## （Creator設定→保存→Battleで正しく一度だけ発動→覚醒状態を保持）を
## 完成させることが目的であり、実際の変身アニメーション・エフェクト・SE・
## 覚醒後の見た目はボスごとに別途制作する予定（ユーザー指示: 「今回まだ
## 決まっていない演出を勝手に作らない」——適当な炎・光・爆発・色変化を
## 正式演出として追加しないこと）。
##
## ここにあるのは、覚醒の発動タイミング・状態遷移が実際に機能している
## ことを目視確認するための、検証可能な最小限のtemporary representation
## （白フラッシュ1回だけ）に過ぎない。ボスごとの正式な覚醒演出を実装する
## 際は、rbm_samurai_wind_finish.gd/rbm_tank_hammer_finish.gdと同じ設計
## 方針（演出内容はボス固有・Camera Shake等の基礎部品は共通）に従って、
## この専用ファイルをボスごとの専用ファイルへ差し替える／新設する
## ——rbm_battle_stage.gd側は"awakening"エントリのディスパッチ先を
## 差し替えるだけでよい構造になっている。

var age := -1.0
var canvas_size := Vector2(1280, 720)

## 白黒フリーズ等ではなく、ごく短い白フラッシュ1回だけ——「変身が起きた」
## ことが分かる最小限の合図。
const DURATION := 0.6

func _draw() -> void:
	if age < 0.0 or age > DURATION:
		return
	var t := age / DURATION
	# 0→1→0の三角形エンベロープ(sin(PI*t))で一瞬だけ明るくなり、すぐ消える。
	var alpha := sin(PI * clampf(t, 0.0, 1.0))
	draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(1.0, 1.0, 1.0, alpha * 0.85))
