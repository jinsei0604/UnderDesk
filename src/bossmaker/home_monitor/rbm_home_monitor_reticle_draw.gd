class_name RBMHomeMonitorReticleDraw
extends Control

## RBMHomeMonitorPanelのBOOT中央リング（タイトル画面SYSTEM CORE起動演出の
## 後半と同系統の「掃引しながら起動→目盛り点灯→収束」）だけを描く専用の
## 子ノード。承認済み独立プレビュー（tools/_home3e_reticle_draw.gd、確認後
## に削除済み）のロジックをそのまま本番へ移植したもの。時計の針そのものは
## 再表示しない。

var center := Vector2.ZERO
var base_radius := 40.0
var radius_frac := 1.0
var inner_frac := 0.62
var rotation_angle := 0.0
var spinner_angle := 0.0
var tick_count := 8
var lit_ticks := 0
var alpha := 0.0
var flash := 0.0
var activation_sweep := TAU
var ring_color := Color(0.55, 0.92, 1.0, 1.0)
var dim_color := Color(0.25, 0.5, 0.6, 0.5)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if alpha <= 0.001:
		return
	var r := base_radius * radius_frac
	var ir := r * inner_frac
	if r < 1.0:
		return

	var sweep: float = clamp(activation_sweep, 0.0, TAU)
	if sweep >= TAU - 0.01:
		draw_arc(center, r, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * alpha * 0.85), 2.0, true)
		draw_arc(center, ir, 0.0, TAU, 48, Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * alpha * 0.55), 1.5, true)
	else:
		if sweep > 0.02:
			draw_arc(center, r, -PI * 0.5, -PI * 0.5 + sweep, 48, Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * alpha * 0.7), 2.0, true)
			draw_arc(center, ir, -PI * 0.5, -PI * 0.5 + sweep, 32, Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * alpha * 0.45), 1.5, true)
		var head := -PI * 0.5 + sweep
		draw_arc(center, r, head - 0.35, head, 12, Color(1.0, 1.0, 1.0, alpha * 0.95), 3.0, true)

	if sweep >= TAU - 0.01:
		for i in range(tick_count):
			var a := rotation_angle + (float(i) / float(tick_count)) * TAU
			var lit := i < lit_ticks
			var tick_len := 8.0 if lit else 4.0
			var col := ring_color if lit else dim_color
			var p0 := center + Vector2(cos(a), sin(a)) * r
			var p1 := center + Vector2(cos(a), sin(a)) * (r + tick_len)
			var lw: float = 2.5 if lit else 1.5
			draw_line(p0, p1, Color(col.r, col.g, col.b, col.a * alpha), lw, true)

		var spin_len := 1.1
		draw_arc(center, r, spinner_angle, spinner_angle + spin_len, 20, Color(1.0, 1.0, 1.0, alpha * 0.9), 3.0, true)

	if flash > 0.01:
		var flash_r := r * 0.5 * flash
		draw_circle(center, flash_r, Color(1.0, 1.0, 1.0, flash * 0.8))
