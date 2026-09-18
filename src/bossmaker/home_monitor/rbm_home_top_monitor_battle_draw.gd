class_name RBMHomeTopMonitorBattleDraw
extends Control

## 上中央モニター内側だけに、バトル映像のクロップ表示＋軽いCRT/モニター風
## 表現(常時スキャンライン＋周期的な走査帯)を描く。承認済み独立プレビュー
## (tools/_home_top_monitor_battle_draw.gd、確認後に削除済み)のロジックを
## そのまま本番へ移植したもの——数値・発火条件とも変更していない。

var source_tex: Texture2D
var src_rect: Rect2
var scan_time := 0.0

const SCANLINE_SPACING := 4.0
const SCANLINE_ALPHA := 0.10
const BAND_PERIOD := 3.0
const BAND_DURATION := 1.0
const BAND_HEIGHT_FRAC := 0.10
const BAND_ALPHA := 0.07

func _process(delta: float) -> void:
	scan_time += delta
	queue_redraw()

func _draw() -> void:
	if source_tex == null:
		return
	var dest := Rect2(Vector2.ZERO, size)
	draw_texture_rect_region(source_tex, dest, src_rect)

	var y := 0.0
	while y < size.y:
		draw_rect(Rect2(0, y, size.x, 1.0), Color(0.0, 0.0, 0.0, SCANLINE_ALPHA), true)
		y += SCANLINE_SPACING

	var t := fmod(scan_time, BAND_PERIOD)
	if t < BAND_DURATION:
		var raw: float = t / BAND_DURATION
		var progress: float = raw * raw * (3.0 - 2.0 * raw)
		var band_h: float = size.y * BAND_HEIGHT_FRAC
		var band_y: float = size.y * (1.0 - progress) - band_h * 0.5
		draw_rect(Rect2(0, band_y, size.x, band_h), Color(0.75, 0.92, 1.0, BAND_ALPHA), true)
