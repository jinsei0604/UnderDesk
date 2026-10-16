class_name RBMMenuUi
extends RefCounted

## 挑戦ハブ・ボス戦作成の入口・作成方法の選択・保存したボス戦の一覧（2026-10 刷新、ユーザーが完成イメージで承認）が
## 共有する見た目の部品。配色と枠は挑戦側のオンライン一覧と同じ RBMChallengeListStyle を使う。
## 表示だけを扱い、画面遷移・データ・戦闘には触れない。
##
## これらの画面は RBMWorldUi.walk() の旧来の金の再配色を受けない（画面のルートに meta "world_skip" を付ける）。

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const WorldUi := preload("res://src/bossmaker/rbm_world_ui.gd")

const HEADER_TITLE_SIZE := 27
const BACK_BUTTON_POSITION := Vector2(24, 20)
const BACK_BUTTON_MIN_SIZE := Vector2(150, 42)
## 選択肢のカードの色の切り替え（マウスを重ねた時・キーボードで選んだ時）にかける時間（UI_UX §3 の目安）。
const HIGHLIGHT_SECONDS := 0.12

## 背景: 城などの絵を使わず、ホーム画面のモニターの「中の画面」のような地を図形だけで描く
## （黒に近い紺・ごく薄い格子・上の淡い光・外周の細い線・四隅の水色の角）。動かない。
class Backdrop:
	extends Control
	var _glow: TextureRect
	var _floor: TextureRect

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow = _gradient(true, Color(0.16, 0.42, 0.52, 0.30), Color(0.16, 0.42, 0.52, 0.0))
		_floor = _gradient(false, Color(0.16, 0.42, 0.52, 0.0), Color(0.16, 0.42, 0.52, 0.10))
		resized.connect(_layout)
		_layout()

	func _gradient(radial: bool, from: Color, to: Color) -> TextureRect:
		var g := Gradient.new()
		g.set_color(0, from)
		g.set_color(1, to)
		var texture := GradientTexture2D.new()
		texture.gradient = g
		texture.width = 128
		texture.height = 128
		if radial:
			texture.fill = GradientTexture2D.FILL_RADIAL
			texture.fill_from = Vector2(0.5, 0.5)
			texture.fill_to = Vector2(1.0, 0.5)
		else:
			texture.fill_to = Vector2(0, 1)
		var t := TextureRect.new()
		# 拡大の設定を先に決める（大きさを入れた後だと、テクスチャの大きさより小さくできない）。
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.texture = texture
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(t)
		return t

	func _layout() -> void:
		var k := size.x / 1280.0 if size.x > 0 else 1.0
		_glow.position = Vector2(-160, -420) * k
		_glow.size = Vector2(1600, 1000) * k
		_floor.position = Vector2(0, size.y - 80.0 * k)
		_floor.size = Vector2(size.x, 80.0 * k)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), S.BG)
		var grid := Color(0.55, 0.85, 0.95, 0.022)
		for x in range(0, int(size.x) + 1, 32):
			draw_rect(Rect2(x, 0, 1, size.y), grid)
		for y in range(0, int(size.y) + 1, 32):
			draw_rect(Rect2(0, y, size.x, 1), grid)
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		draw_rect(r, Color(S.ACCENT, 0.10), false, 1.0)
		var c := Color(S.ACCENT, 0.5)
		for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
			var p: Vector2 = corner[0]
			var d: Vector2 = corner[1]
			draw_line(p, p + Vector2(d.x * 36.0, 0), c, 2.0)
			draw_line(p, p + Vector2(0, d.y * 36.0), c, 2.0)

## 右向きの小さな矢印（共通のドット絵アイコン icon("right") と同じ形を、画像を使わず描く）。14×14。
class Arrow:
	extends Control
	const CELLS := [[4, 2], [4, 3], [5, 3], [4, 4], [5, 4], [6, 4], [4, 5], [5, 5], [4, 6]]
	var color := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(14, 14)

	func set_color(value: Color) -> void:
		if value == color:
			return
		color = value
		queue_redraw()

	func _draw() -> void:
		for cell in CELLS:
			draw_rect(Rect2(cell[0] * 2, cell[1] * 2, 2, 2), color)

static func add_backdrop(parent: Control, node_name: String) -> Control:
	var b := Backdrop.new()
	b.name = node_name
	parent.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return b

static func icon(kind: String, color: Color) -> ImageTexture:
	return WorldUi.new().icon(kind, color)

static func arrow(parent: Node, at: Vector2, color: Color, node_name: String = "Arrow") -> Arrow:
	var a := Arrow.new()
	a.name = node_name
	a.position = at
	a.color = color
	parent.add_child(a)
	return a

## 文字の影（背景の上の見出し用、UI_UX §2）。
static func shadow(l: Label) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 2)
	return l

static func number_font(c: Control) -> Control:
	c.add_theme_font_override("font", S.number_font())
	return c

## 文字の幅に合わせる（後ろに続く文字の位置を決めるため）。
static func fit_width(l: Label) -> Label:
	l.size.x = l.get_combined_minimum_size().x
	return l

## 上部: 左上の戻る（呼び出し側が作った Button をそのまま使う）＋ 青い縦線付きの見出し ＋ 補足 ＋ 1px の区切り線。
## 挑戦側のオンライン一覧と同じ位置・大きさ。見出しの Label を返す。
static func header(parent: Control, back: Button, back_text: String, title_text: String, subtitle_text: String = "", title_name: String = "MenuTitleLabel", subtitle_name: String = "MenuSubtitleLabel") -> Label:
	back.text = back_text
	back.icon = icon("left", S.SILVER)
	back.add_theme_font_size_override("font_size", 15)
	S.button_style(back)
	back.focus_mode = Control.FOCUS_ALL
	if back.get_parent() != parent:
		if back.get_parent() != null:
			back.get_parent().remove_child(back)
		parent.add_child(back)
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.position = BACK_BUTTON_POSITION
	# 英語など文字が長い言語でもはみ出さないよう、文字に合わせて広げてから見出しを右に置く。
	back.size = Vector2(maxf(BACK_BUTTON_MIN_SIZE.x, back.get_combined_minimum_size().x), BACK_BUTTON_MIN_SIZE.y)
	var tx := back.position.x + back.size.x + 22.0
	S.rect(parent, Rect2(tx, 28, 4, 26), S.ACCENT_SOFT)
	var title := fit_width(shadow(S.label(parent, title_text, Rect2(tx + 16, 18, 760, 46), HEADER_TITLE_SIZE, S.TEXT, title_name)))
	if not subtitle_text.is_empty():
		fit_width(shadow(S.label(parent, subtitle_text, Rect2(title.position.x + title.size.x + 20, 26, 620, 32), 14, S.MUTED, subtitle_name)))
	S.rect(parent, Rect2(24, 76, 1232, 1), Color(S.PANEL_EDGE, 0.9))
	S.rect(parent, Rect2(24, 76, 64, 1), S.ACCENT_SOFT)
	return title

## 見出し（左に短い青の縦線）に文字の影を付けたもの。
static func section(parent: Node, text: String, at: Vector2, node_name: String = "") -> Label:
	return shadow(S.section_title(parent, text, at, node_name))

## 大きな選択肢のカード（Button）の見た目。primary は主な行動（水色の枠・淡い発光）。
## 状態: ふつう／マウスを重ねた時（少し明るく、銀か白の枠）／押した時（少し暗く）／キーボードの操作対象（外側の白い枠）。
## content: Button 自身の文字を置く余白（左・上・右・下）。文字をカードの見出しとして使う時に指定する。
static func card_styles(b: Button, primary: bool, content: Vector4 = Vector4.ZERO) -> void:
	var normal := S.box(Color(S.CARD, 0.93), S.CARD_EDGE)
	var hover := S.box(Color(S.CARD_HOVER, 0.96), Color(S.SILVER, 0.7))
	if primary:
		normal = S.box(Color("0d222a", 0.94), Color(S.ACCENT, 0.7))
		normal.shadow_color = Color(S.ACCENT, 0.12)
		normal.shadow_size = 6
		hover = S.box(Color("123540", 0.96), Color(S.TEXT, 0.9))
		hover.shadow_color = Color(S.ACCENT, 0.24)
		hover.shadow_size = 8
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("0b1f24", 0.98)
	var disabled := S.box(Color("0b1116"), Color("1f2a31"))
	for style in [normal, hover, pressed, disabled]:
		style.content_margin_left = content.x
		style.content_margin_top = content.y
		style.content_margin_right = content.z
		style.content_margin_bottom = content.w
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", S.focus_ring())
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## カードの見出しを Button 自身の文字で出す（左寄せ。位置は card_styles の content で決める）。
static func card_title(b: Button, text: String, font_size: int, color: Color, latin: bool = false) -> void:
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	if latin:
		b.add_theme_font_override("font", S.number_font())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, color)
	b.add_theme_color_override("font_disabled_color", S.DIM)

## カードの左端の縦線。
static func accent_bar(card: Control, color: Color, height: float) -> ColorRect:
	return S.rect(card, Rect2(0, 10, 3, height - 20), color, "AccentBar")

## 小さな札（「公開中」「覚醒」など）。
static func tag(parent: Node, text: String, at: Vector2, fg: Color, edge: Color, fill: Color, latin: bool = false, node_name: String = "") -> Label:
	var t := Label.new()
	if not node_name.is_empty():
		t.name = node_name
	t.text = text
	t.position = at
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if latin:
		t.add_theme_font_override("font", S.number_font())
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", fg)
	var style := S.box(fill, edge)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	t.add_theme_stylebox_override("normal", style)
	parent.add_child(t)
	return t

## カードの中の「この方法で作成を始める」などの帯（表示だけ。押すのはカード全体）。lit で水色に光る。
class CtaStrip:
	extends Panel
	var label: Label
	var arrow: Arrow
	var lit := 0.0
	var strong := 0.0

	func setup(text: String, font_size: int) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		label = Label.new()
		label.name = "CtaLabel"
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", font_size)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		arrow = Arrow.new()
		arrow.name = "CtaArrow"
		add_child(arrow)
		resized.connect(apply)
		apply()

	func set_lit(value: float, strong_value: float = 0.0) -> void:
		lit = value
		strong = strong_value
		apply()

	func apply() -> void:
		if label == null:
			return
		var box := S.box(Color(S.INSET, 0.9).lerp(Color("0f2a30"), lit), Color("2a3a44").lerp(S.ACCENT, lit))
		box.shadow_color = Color(S.ACCENT, 0.12 * lit + 0.12 * strong)
		box.shadow_size = int(round(6.0 * maxf(lit, strong)))
		add_theme_stylebox_override("panel", box)
		label.size = size
		label.add_theme_color_override("font_color", S.SILVER.lerp(S.TEXT, lit))
		arrow.position = Vector2(size.x - 40.0, roundf(size.y / 2.0 - 7.0))
		arrow.set_color(S.SILVER.lerp(S.ACCENT, lit))

static func cta_strip(parent: Control, rect: Rect2, text: String, font_size: int = 18, node_name: String = "CtaStrip") -> CtaStrip:
	var c := CtaStrip.new()
	c.name = node_name
	c.position = rect.position
	c.size = rect.size
	parent.add_child(c)
	c.setup(text, font_size)
	return c

## Button にマウスが重なった・キーボードの操作対象になった時と、それが外れた時に callback(光らせるか) を呼ぶ。
static func on_highlight(b: Button, callback: Callable) -> void:
	b.mouse_entered.connect(func() -> void: callback.call(true))
	b.mouse_exited.connect(func() -> void: callback.call(b.has_focus()))
	b.focus_entered.connect(func() -> void: callback.call(true))
	b.focus_exited.connect(func() -> void: callback.call(b.is_hovered()))
	b.visibility_changed.connect(func() -> void: callback.call(b.is_visible_in_tree() and (b.is_hovered() or b.has_focus())))

## 検索欄（挑戦側の一覧と同じ暗い地。入力中は水色の枠）。
static func search_field(le: LineEdit) -> void:
	le.add_theme_font_size_override("font_size", 14)
	le.add_theme_color_override("font_color", S.TEXT)
	le.add_theme_color_override("font_placeholder_color", S.MUTED)
	le.add_theme_color_override("caret_color", S.ACCENT)
	le.add_theme_color_override("selection_color", Color(S.ACCENT, 0.35))
	le.add_theme_color_override("clear_button_color", S.MUTED)
	le.add_theme_color_override("clear_button_color_pressed", S.ACCENT)
	var normal := S.box(S.INSET, Color("2a3a44"))
	var hover := S.box(S.INSET, Color(S.SILVER, 0.7))
	var focus := S.box(S.INSET, S.ACCENT)
	for style in [normal, hover, focus]:
		style.content_margin_left = 12
		style.content_margin_right = 12
	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("hover", hover)
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_stylebox_override("read_only", normal)

## 削除など取り消せない操作のボタン（控えめな赤。主な行動の水色と見分けられる、UI_UX §12）。
static func danger_style(b: Button) -> void:
	var normal := S.box(Color("140c0d"), Color(S.HARD_EDGE, 0.9))
	var hover := S.box(Color("2a1414"), S.HARD)
	var pressed := S.box(Color("0e0809"), S.HARD)
	for style in [normal, hover, pressed]:
		style.content_margin_left = 16
		style.content_margin_right = 16
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", S.focus_ring())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, S.HARD)
	b.focus_mode = Control.FOCUS_ALL

## 文字を持たないカード（子の Label で見せる Button）に、読み上げ用の名前を付ける（エンジンが対応していれば）。
static func accessible_name(c: Control, text: String) -> void:
	if "accessibility_name" in c:
		c.set("accessibility_name", text)
