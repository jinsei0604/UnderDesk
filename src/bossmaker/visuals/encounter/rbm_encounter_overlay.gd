extends CanvasLayer
## 登場・勝利の演出で戦場の上に重ねる画面の層（表示専用）。戦場のカメラ（整数倍の寄り）とは別で、拡大されない。
## - シネマの帯（上下。内側に細い水色の線）
## - 周りを暗くする効果（ビネット）
## - ボス名の題字（下地の帯・名前・光が走る・作者名）
## - 黒い幕・勝利の文字などほかの層が描くもの（extra_draw）
## - 入力を止める板: 演出の間、クリックとキー入力を下の戦闘画面へ届けない（演出は飛ばせない。ユーザーの決定 2026-10-16）
## 色はメニュー画面と同じ紺＋水色（RBMChallengeListStyle）。

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const LATIN := preload("res://assets_bossmaker/fonts/Oxanium-SemiBold.ttf")
const SCREEN := Vector2(1280, 720)
const LETTERBOX_H := 80.0

class Blocker:
	extends Control
	func _gui_input(event: InputEvent) -> void:
		accept_event()

var canvas: Control
var blocker: Blocker
var _top: Control
var _vignette: TextureRect
var letterbox := 0.0
var vignette := 0.0
var fade := 0.0
var fade_color := Color.BLACK
# 題字 {name, author, label, t(出てからの秒), out(0〜1 消える), accent}
var title := {}
var extra_draw: Array[Callable] = []
var _focus_owner: Control

func _init() -> void:
	layer = 40
	canvas = Control.new()
	canvas.name = "EncounterOverlay"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = SCREEN
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(canvas)
	# ビネット: 中央が透明で、外側ほど暗い（放射のグラデーション1枚。描画は1回）
	_vignette = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.0, 0.0, 0.02, 0.85))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 256
	tex.height = 144
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vignette.size = SCREEN
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	canvas.add_child(_vignette)
	_top = Control.new()
	_top.size = SCREEN
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.add_child(_top)
	_top.draw.connect(_draw_upper)
	blocker = Blocker.new()
	blocker.name = "EncounterInputBlocker"
	blocker.size = SCREEN
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.focus_mode = Control.FOCUS_ALL
	canvas.add_child(blocker)

func _ready() -> void:
	block_input(true)

## 入力を止める（演出の間）・戻す。止める時は、キー入力でボタンが押されないようにフォーカスを預かる。
func block_input(on: bool) -> void:
	if not is_instance_valid(blocker):
		return
	blocker.visible = on
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on and blocker.is_inside_tree():
		var vp := blocker.get_viewport()
		_focus_owner = vp.gui_get_focus_owner() if vp != null else null
		blocker.grab_focus()
	elif not on and blocker.has_focus():
		blocker.release_focus()

func refresh() -> void:
	_vignette.modulate.a = vignette
	_vignette.visible = vignette > 0.0
	_top.queue_redraw()

static func jp_font() -> Font:
	return ThemeDB.fallback_font

func _draw_upper() -> void:
	var ci := _top
	if letterbox > 0.0:
		var h := roundf(LETTERBOX_H * letterbox)
		ci.draw_rect(Rect2(0, 0, SCREEN.x, h), Color(0.0, 0.0, 0.01))
		ci.draw_rect(Rect2(0, SCREEN.y - h, SCREEN.x, h), Color(0.0, 0.0, 0.01))
		if h > 4:
			ci.draw_rect(Rect2(0, h - 2, SCREEN.x, 1), Color(S.ACCENT_SOFT, 0.55 * letterbox))
			ci.draw_rect(Rect2(0, SCREEN.y - h + 1, SCREEN.x, 1), Color(S.ACCENT_SOFT, 0.55 * letterbox))
	if not title.is_empty():
		_draw_title(ci)
	for f in extra_draw:
		f.call(ci)
	if fade > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(fade_color, fade))

static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

## ボス名の題字（左下）。t: 出てからの秒、out: 0〜1 で左へ抜けて消える。
func _draw_title(ci: CanvasItem) -> void:
	var t: float = title.get("t", 0.0)
	var out: float = title.get("out", 0.0)
	if t < 0.0:
		return
	var name: String = title.get("name", "")
	var author: String = title.get("author", "")
	var label: String = title.get("label", "BOSS BATTLE")
	var accent: Color = title.get("accent", S.ACCENT)
	var font := jp_font()
	var size := fit_size(font, name, author, tr("制作"))
	var name_w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x0 := 72.0 - 28.0 * _ease_out(out)
	var base_y := SCREEN.y - LETTERBOX_H - 34.0
	var a := 1.0 - out
	# 下地の帯（平行四辺形）が左から伸びる
	var band_k := _ease_out(t / 0.22)
	var band_w := roundf((name_w + 150.0) * band_k)
	var top := base_y - 66.0
	var bottom := base_y + 16.0
	var band := PackedVector2Array([Vector2(0, top), Vector2(band_w + 28, top), Vector2(band_w, bottom), Vector2(0, bottom)])
	ci.draw_colored_polygon(band, Color(S.PANEL.darkened(0.2), 0.86 * a))
	ci.draw_line(Vector2(0, top), Vector2(band_w + 28, top), Color(accent, 0.85 * a), 2.0, false)
	ci.draw_line(Vector2(0, bottom), Vector2(band_w, bottom), Color(S.ACCENT_SOFT, 0.5 * a), 1.0, false)
	# 小さな見出し（BOSS BATTLE）
	var lk := _ease_out((t - 0.10) / 0.2)
	if lk > 0.0:
		ci.draw_rect(Rect2(x0, top + 14, roundf(18 * lk), 3), Color(accent, a))
		var lx := x0 + 26
		for ch in label:
			ci.draw_string(LATIN, Vector2(lx, top + 22 + roundf((1.0 - lk) * 6)), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(accent, a * lk))
			lx += LATIN.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 3.0
	# 名前: 左から切り抜きで現れる（影 → 縁取り → 本体）
	var nk := _ease_out((t - 0.14) / 0.28)
	if nk > 0.0:
		var pos := Vector2(x0, base_y)
		var clip_w := roundf((name_w + 8) * nk)
		_clip_string(ci, font, pos + Vector2(3, 3), name, size, Color(0.0, 0.02, 0.05, 0.75 * a), clip_w, 0)
		_clip_string(ci, font, pos, name, size, Color(0.0, 0.02, 0.05, 0.9 * a), clip_w, 8)
		_clip_string(ci, font, pos, name, size, Color(S.TEXT, a), clip_w, 0)
		# 光が名前の上を一度だけ走る
		var sk := (t - 0.42) / 0.32
		if sk > 0.0 and sk < 1.0:
			var sx := x0 - 40 + (name_w + 80) * sk
			ci.draw_colored_polygon(PackedVector2Array([Vector2(sx, base_y - 46), Vector2(sx + 14, base_y - 46), Vector2(sx + 2, base_y + 8), Vector2(sx - 12, base_y + 8)]), Color(1, 1, 1, 0.35 * a))
	# 作者名
	var ak := _ease_out((t - 0.36) / 0.25)
	if ak > 0.0 and not author.is_empty():
		var credit := tr("制作") + "  " + author
		ci.draw_string(font, Vector2(x0 + name_w + 22, base_y - 2), credit, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(S.MUTED.lightened(0.15), a * ak))

## 題字の名前の字の大きさ: 50 を基本に、名前と作者名が画面の幅（左の余白72・右の余白40）に収まるまで小さくする
## （ボス名は最大20文字。下限28）。
static func fit_size(font: Font, name: String, author: String, credit_label: String) -> int:
	var credit_w := 0.0
	if not author.is_empty():
		credit_w = 22.0 + font.get_string_size(credit_label + "  " + author, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var limit := SCREEN.x - 72.0 - 40.0 - credit_w
	var size := 50
	while size > 28 and font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > limit:
		size -= 2
	return size

## 文字を左から w までだけ描く（1文字ずつ。はみ出す文字は描かない）。
func _clip_string(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, color: Color, w: float, outline: int) -> void:
	var x := 0.0
	for ch in text:
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if x + cw * 0.5 > w:
			break
		if outline > 0:
			ci.draw_string_outline(font, pos + Vector2(x, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, color)
		else:
			ci.draw_string(font, pos + Vector2(x, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		x += cw
