extends RefCounted
## 戦闘画面の HUD の見た目（2026-10-23 ユーザーが採用した案C「ダークネイビー＋水色」、行動順は案Aの形）。表示専用。
## 色・枠・ボタン・バー・アイコンはここだけにまとめる（戦闘画面の見た目を替える時はここを替える）。
## 試作: prototypes/battle_ui_designs_2026-10-23/tools/mock_battle_hud.gd の _draw_c()。

const CYAN := Color("43efff")
const CYAN_DIM := Color("2f5b61")
const PANEL := Color(0.035, 0.06, 0.1, 0.9)
const TEXT := Color("eef5f6")
const MUTED := Color("93a7ac")
const INK := Color("061019")
const BOSS_NAME := Color("ff9aa6")
const BOSS_EDGE := Color("ff6b7d")
const HP_TOP := Color("ff8a7a")
const HP_BOTTOM := Color("c23a3a")
const SP_TOP := Color("7ad7ff")
const SP_BOTTOM := Color("2f74c8")
## 見出し（BOSS・TURN ORDER・COMMAND・HP・SP・ACTIVE）の文字の大きさ。補足の文字の下限（UI_UX §2）。
const CAPTION_SIZE := 12
## 「覚醒」の札の色（ボスの HP バーの札と同じ。味方のカードの覚醒の札にも使う）。
const AWAKENED_FILL := Color("3a0d33")
const AWAKENED_EDGE := Color("ff7ad9")
const AWAKENED_TEXT := Color("ffd6f1")

static var _font: Font
static var _styles: Dictionary = {}
static var _icons: Dictionary = {}

## 数字・英字の見出しの字体（Oxanium）。日本語の字は無いので、英数字だけに使う。
static func number_font() -> Font:
	if _font == null:
		_font = load("res://assets_bossmaker/fonts/Oxanium-SemiBold.ttf")
	return _font

## 案Cの枠（紺の地・水色の細い線・角の印。accent は発光つき）。Panel にしてあるのは、朽ちた機械武者の着弾の墨が
## UI欄の上に重なる範囲を Panel とボタンから集めるため（rbm_musha_ink_director.gd の _collect_hud_rects）。
class CPanel extends Panel:
	var accent := false:
		set(value):
			if accent != value:
				accent = value
				queue_redraw()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var box := StyleBoxFlat.new()
		box.bg_color = PANEL
		box.set_corner_radius_all(4)
		box.border_color = Color(CYAN, 0.28)
		box.set_border_width_all(1)
		draw_style_box(box, r)
		if accent:
			for i in range(1, 4):
				var glow := StyleBoxFlat.new()
				glow.draw_center = false
				glow.set_corner_radius_all(4 + i)
				glow.border_color = Color(CYAN, 0.12 - i * 0.03)
				glow.set_border_width_all(2)
				draw_style_box(glow, r.grow(i * 2))
		var tick := 12.0
		var col := Color(CYAN, 0.95 if accent else 0.7)
		for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, 0), Vector2(-1, 1)], [Vector2(0, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
			var p: Vector2 = corner[0]
			var d: Vector2 = corner[1]
			draw_line(p, p + Vector2(tick * d.x, 0), col, 2)
			draw_line(p, p + Vector2(0, tick * d.y), col, 2)

static func panel(parent: Control, rect: Rect2, node_name: String, accent := false) -> CPanel:
	var p := CPanel.new()
	p.name = node_name
	p.accent = accent
	parent.add_child(p)
	p.position = rect.position
	p.size = rect.size
	return p

## 枠の見出し（英字・水色・小さめ）。
static func caption(parent: Control, text: String, at: Vector2, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label(l, CAPTION_SIZE, CYAN, number_font())
	parent.add_child(l)
	l.position = at
	return l

## 文字の色・大きさ・字体（字体を渡さない時は画面の字体）。縁取り・影は付けない（紺の地の上の文字）。
## 戦闘画面の更新のたびに呼ばれるので、同じ指定が付いている時は何もしない（設定し直すと全部の大きさの計算がやり直しになる）。
static func label(l: Label, font_size: int, color: Color, font: Font = null) -> void:
	var style_key := str([font_size, color, font])
	if l.get_meta("hud_style", "") == style_key:
		return
	l.set_meta("hud_style", style_key)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.add_theme_constant_override("outline_size", 0)
	if font != null:
		l.add_theme_font_override("font", font)

static func _box(bg: Color, border: Color, width := 1, left := -1, margin := Vector4(12, 6, 12, 6), radius := 4) -> StyleBoxFlat:
	var key := str([bg, border, width, left, margin, radius])
	if _styles.has(key):
		return _styles[key]
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	if left >= 0:
		box.border_width_left = left
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w
	box.anti_aliasing = false
	_styles[key] = box
	return box

## キーボード・パッドで選んでいる時の枠: 外側に2pxの白い線（マウスを重ねた時の水色と見分けられるように。
## 挑戦の一覧の RBMChallengeListStyle.focus_ring() と同じ考え方）。
static func _focus_ring() -> StyleBoxFlat:
	if _styles.has("focus_ring"):
		return _styles["focus_ring"]
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(TEXT, 0.95)
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(5)
	ring.expand_margin_left = 3
	ring.expand_margin_right = 3
	ring.expand_margin_top = 3
	ring.expand_margin_bottom = 3
	ring.anti_aliasing = false
	_styles["focus_ring"] = ring
	return ring

## ボタン（コマンド・LOG・やめる・やり直す・技の一覧・確認）。押せる時・乗せた時・押した時・選んでいる時・押せない時が
## 見分けられる（乗せた時は左に水色の線、押せない時は文字とアイコンも薄く）。
static func button(b: Button, font_size := 15, margin := Vector4(12, 4, 12, 4)) -> void:
	var style_key := str([font_size, margin])
	if b.get_meta("hud_style", "") == style_key:
		return
	b.set_meta("hud_style", style_key)
	b.add_theme_stylebox_override("normal", _box(Color(0.04, 0.08, 0.13, 0.88), Color(CYAN, 0.22), 1, -1, margin))
	b.add_theme_stylebox_override("hover", _box(Color(CYAN, 0.14), Color(CYAN, 0.85), 1, 4, margin))
	b.add_theme_stylebox_override("pressed", _box(Color(CYAN, 0.22), CYAN, 1, 4, margin))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(CYAN, 0.22), CYAN, 1, 4, margin))
	b.add_theme_stylebox_override("focus", _focus_ring())
	b.add_theme_stylebox_override("disabled", _box(Color(0.03, 0.05, 0.08, 0.7), Color(CYAN, 0.08), 1, -1, margin))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, TEXT)
	b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	b.add_theme_constant_override("outline_size", 0)
	for key in ["icon_normal_color", "icon_focus_color"]:
		b.add_theme_color_override(key, MUTED)
	b.add_theme_color_override("icon_disabled_color", Color(MUTED, 0.35))
	for key in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(key, CYAN)
	b.add_theme_font_size_override("font_size", font_size)

## 味方のカードの枠（行動中は水色で光る。光の輪はカードの draw で足す）。
static func card(active: bool) -> StyleBoxFlat:
	if active:
		return _box(Color(0.05, 0.1, 0.16, 0.92), Color(CYAN, 0.95), 2, -1, Vector4(8, 7, 8, 6))
	return _box(Color(0.03, 0.06, 0.1, 0.62), Color(CYAN, 0.2), 1, -1, Vector4(8, 7, 8, 6))

## 顔の写真の額（暗い地に細い線）。
static func face_frame(edge: Color) -> StyleBoxFlat:
	return _box(INK, edge, 1, -1, Vector4(1, 1, 1, 1), 3)

## 「ACTIVE」「覚醒」などの札。
static func pill(fill: Color, edge: Color) -> StyleBoxFlat:
	return _box(fill, edge, 1, -1, Vector4(8, 0, 8, 1), 9)

## 枠の中の小さな欄（技の説明・確認の文など）。
static func inner() -> StyleBoxFlat:
	return _box(Color(0.03, 0.07, 0.11, 0.85), Color(CYAN, 0.18), 1, -1, Vector4(10, 6, 10, 6))

## 詳細の窓（味方・ボスの詳細、戦闘ログ）の枠。
static func window() -> StyleBoxFlat:
	return _box(Color(0.03, 0.055, 0.09, 0.97), Color(CYAN, 0.5), 1, -1, Vector4(20, 16, 20, 16))

## 透明（中身の余白だけ）。
static func clear(margin := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	return _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, -1, margin, 0)

## HP・SP のバー（上が明るい2色、枠は水色の細い線）。
static func bar_fill(top: Color, bottom: Color) -> StyleBoxTexture:
	var key := "fill" + str([top, bottom])
	if _styles.has(key):
		return _styles[key]
	var image := Image.create(1, 4, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, top.lightened(0.35))
	image.set_pixel(0, 1, top)
	image.set_pixel(0, 2, bottom)
	image.set_pixel(0, 3, bottom)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_top = 1
	box.texture_margin_bottom = 2
	_styles[key] = box
	return box

static func bar_track() -> StyleBoxFlat:
	return _box(INK, Color(CYAN, 0.45), 1, -1, Vector4(0, 0, 0, 0), 0)

## コマンドの小さなアイコン（剣・本・盾・戻る）。白で作り、ボタンの色の設定で色を付ける。
static func icon(kind: String) -> ImageTexture:
	if _icons.has(kind):
		return _icons[kind]
	var image := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var w := Color.WHITE
	match kind:
		"attack":
			for i in range(15):
				image.fill_rect(Rect2i(4 + i, 16 - i, 2, 2), w)
			for i in range(7):
				image.fill_rect(Rect2i(4 + i, 9 + i, 2, 2), w)
			image.fill_rect(Rect2i(2, 18, 3, 3), w)
		"skill":
			image.fill_rect(Rect2i(4, 2, 14, 2), w)
			image.fill_rect(Rect2i(4, 18, 14, 2), w)
			image.fill_rect(Rect2i(4, 2, 2, 18), w)
			image.fill_rect(Rect2i(16, 2, 2, 18), w)
			for y in [7, 11, 15]:
				image.fill_rect(Rect2i(8, y - 1, 7 if y != 15 else 5, 2), w)
		"defend":
			for y in range(18):
				var half := 8 if y < 10 else maxi(1, 8 - (y - 10))
				image.fill_rect(Rect2i(11 - half, 2 + y, half * 2, 1), w)
		"back":
			for i in range(6):
				image.fill_rect(Rect2i(5 + i, 10 - i, 2, 2), w)
				image.fill_rect(Rect2i(5 + i, 10 + i, 2, 2), w)
			image.fill_rect(Rect2i(6, 10, 12, 2), w)
	var texture := ImageTexture.create_from_image(image)
	_icons[kind] = texture
	return texture

## 数に3桁ごとの区切りを入れる（ボスの HP。99,999 まで）。
static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
