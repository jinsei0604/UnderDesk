class_name RBMHomeMonitorPanelDraw
extends Control

## RBMHomeMonitorPanelの見た目（濃紺の塗り＋外周シアン発光＋コーナー
## ブラケット＋BOOT中の十字光／四隅点灯／スキャン）だけを担当する描画専用
## 子ノード。承認済み独立プレビュー（tools/_home3e_panel_draw.gd、確認後に
## 削除済み）のロジックをそのまま本番へ移植したもの。

var rect_size_local := Vector2.ZERO
var fill_color := Color(0.02, 0.05, 0.08, 1.0)
var border_color := Color(0.55, 0.92, 1.0, 1.0)
var border_intensity := 0.4
var corner_len := 8.0
var corner_max := 22.0
var scan_pos := -1.0
var dim := 0.0

# BOOT演出専用
var cross_extent := 0.0
var boot_corner_stage := 0.0
var boot_corner_alpha := 1.0
var full_scan_pos := -1.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, rect_size_local)
	draw_rect(r, fill_color, true)
	if dim > 0.01:
		draw_rect(r, Color(0.0, 0.0, 0.0, dim), true)

	var bw := 1.5 + border_intensity * 1.5
	var bc := Color(border_color.r, border_color.g, border_color.b, 0.35 + border_intensity * 0.65)
	draw_rect(r, bc, false, bw)

	var w := rect_size_local.x
	var h := rect_size_local.y
	var inset := 6.0

	var cl: float = min(corner_len, corner_max)
	if cl > 0.5:
		var cc := Color(border_color.r, border_color.g, border_color.b, 0.55 + border_intensity * 0.45)
		_draw_corner_brackets(w, h, inset, cl, cc)

	if boot_corner_stage > 0.01:
		_draw_boot_corners(w, h, inset)

	if cross_extent > 0.01:
		_draw_cross(w, h)

	if scan_pos >= 0.0 and scan_pos <= 1.0:
		var y := h * scan_pos
		var fade: float = 1.0 - abs(scan_pos - 0.5) * 1.2
		var sc := Color(0.8, 0.98, 1.0, clamp(fade, 0.0, 1.0) * 0.5)
		draw_line(Vector2(0, y), Vector2(w, y), sc, 1.5)

	if full_scan_pos >= 0.0 and full_scan_pos <= 1.0:
		var y2 := h * full_scan_pos
		var band_h := h * 0.12
		var col := Color(0.85, 0.98, 1.0, 0.28)
		draw_rect(Rect2(0, y2 - band_h * 0.5, w, band_h), col, true)
		draw_line(Vector2(0, y2), Vector2(w, y2), Color(1.0, 1.0, 1.0, 0.55), 1.5)

func _draw_corner_brackets(w: float, h: float, inset: float, cl: float, cc: Color) -> void:
	var corners := [
		[Vector2(inset, inset), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(w - inset, inset), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(inset, h - inset), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(w - inset, h - inset), Vector2(-1, 0), Vector2(0, -1)],
	]
	for cdata in corners:
		var origin: Vector2 = cdata[0]
		var dx: Vector2 = cdata[1]
		var dy: Vector2 = cdata[2]
		draw_line(origin, origin + dx * cl, cc, 2.0, true)
		draw_line(origin, origin + dy * cl, cc, 2.0, true)

func _draw_boot_corners(w: float, h: float, inset: float) -> void:
	var order := [
		[Vector2(inset, inset), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(w - inset, inset), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(w - inset, h - inset), Vector2(-1, 0), Vector2(0, -1)],
		[Vector2(inset, h - inset), Vector2(1, 0), Vector2(0, -1)],
	]
	var len_big: float = min(w, h) * 0.14
	for i in range(order.size()):
		var stage_local: float = clamp(boot_corner_stage - float(i), 0.0, 1.0)
		if stage_local <= 0.001:
			continue
		var cdata: Array = order[i]
		var origin: Vector2 = cdata[0]
		var dx: Vector2 = cdata[1]
		var dy: Vector2 = cdata[2]
		var a: float = ease(stage_local, 0.4) * boot_corner_alpha
		var cc := Color(1.0, 1.0, 1.0, 0.85 * a)
		var l: float = len_big * ease(stage_local, 0.4)
		draw_line(origin, origin + dx * l, cc, 2.5, true)
		draw_line(origin, origin + dy * l, cc, 2.5, true)

func _draw_cross(w: float, h: float) -> void:
	var cx := w * 0.5
	var cy := h * 0.5
	var ext_x := cx * cross_extent
	var ext_y := cy * cross_extent
	var col := Color(0.85, 0.98, 1.0, 0.75 * min(1.0, cross_extent * 2.0))
	draw_line(Vector2(cx - ext_x, cy), Vector2(cx + ext_x, cy), col, 2.0, true)
	draw_line(Vector2(cx, cy - ext_y), Vector2(cx, cy + ext_y), col, 2.0, true)
