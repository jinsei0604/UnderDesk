class_name RBMChallengeListStyle
extends RefCounted

## 挑戦画面のオンライン一覧(左: ボスカード一覧 / 右: 選択中ボスの詳細、2026-10)が共有する
## 見た目の部品。Creator編集画面と同じ系統の配色(濃紺・黒に近い地・銀・青のアクセント、
## RBMWorldUi.CREATOR_*)を使う。表示だけを扱い、戦闘・通信の状態には一切触れない。

const BG := Color("070b10")
const PANEL := Color("0b1117")
const PANEL_EDGE := Color("223640")
const CARD := Color("0e151c")
const CARD_EDGE := Color("2a3a44")
const CARD_HOVER := Color("121c24")
const CARD_SELECTED := Color("10232c")
const INSET := Color("080d12")
const SKELETON := Color("16212a")
const ACCENT := Color("43efff")        # RBMWorldUi.CREATOR_ACCENT
const ACCENT_SOFT := Color("2f8ea0")
const EMPHASIS := Color("8fe3ef")
const SILVER := Color("c3ccd3")
const TEXT := Color("eef5f6")           # RBMWorldUi.CREATOR_TEXT
const MUTED := Color("93a7ac")          # RBMWorldUi.CREATOR_MUTED
const DIM := Color("5d6f76")
const HARD := Color("d08a78")
const HARD_EDGE := Color("7d4337")

const NUMBER_FONT_PATH := "res://assets_bossmaker/fonts/Oxanium-SemiBold.ttf"
const SCREEN_BACKGROUND_PATH := "res://assets_bossmaker/art/creator_top_background.png"

static var _number_font: Font
## asset_id+大きさ -> 切り出し・縮小済みのTexture2D(同じ絵を何度も縮小しない)。
static var _sprite_cache: Dictionary = {}

static func number_font() -> Font:
	if _number_font == null:
		_number_font = load(NUMBER_FONT_PATH)
	return _number_font

static func box(fill: Color, edge: Color, width: int = 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = edge
	b.set_border_width_all(width)
	b.set_corner_radius_all(2)
	b.anti_aliasing = false
	return b

## キーボード/パッドで操作対象になった時の枠: 外側に2pxの白い線(選択中の青枠・マウスを
## 重ねた時の銀枠と見分けられるように)。マウスで押しただけでは出ない(Godotの既定の
## gui/common/show_focus_state_on_pointer_event)。
static func focus_ring() -> StyleBoxFlat:
	var ring := box(Color.TRANSPARENT, Color(TEXT, 0.95), 2)
	ring.draw_center = false
	ring.expand_margin_left = 3
	ring.expand_margin_right = 3
	ring.expand_margin_top = 3
	ring.expand_margin_bottom = 3
	return ring

## primary=「挑戦する」のようなメインの操作(青い枠・少し発光)。それ以外は銀系の控えめなボタン。
static func button_style(b: Button, primary: bool = false) -> void:
	var normal := box(Color("0f2a30") if primary else Color("0d151b"), ACCENT if primary else Color("3a4a53"))
	var hover := box(Color("174650") if primary else Color("16232c"), Color(TEXT, 0.9) if primary else SILVER)
	var disabled := box(Color("0b1116"), Color("1f2a31"))
	for style in [normal, hover, disabled]:
		style.content_margin_left = 18
		style.content_margin_right = 18
	if primary:
		normal.shadow_color = Color(ACCENT, 0.12)
		normal.shadow_size = 4
		hover.shadow_color = Color(ACCENT, 0.22)
		hover.shadow_size = 6
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus_ring())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, TEXT if primary else SILVER)
	b.add_theme_color_override("font_disabled_color", DIM)

## 選択中の切り替えボタン(すべて/SIMPLE/HARDCOREのうち今のモード)は、メインの操作と同じ青い枠で示す。
static func segment_style(b: Button, active: bool) -> void:
	button_style(b, active)

static func label(parent: Node, text: String, rect: Rect2, font_size: int, color: Color, node_name: String = "") -> Label:
	var l := Label.new()
	if not node_name.is_empty():
		l.name = node_name
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func rect(parent: Node, area: Rect2, color: Color, node_name: String = "") -> ColorRect:
	var r := ColorRect.new()
	if not node_name.is_empty():
		r.name = node_name
	r.position = area.position
	r.size = area.size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

## 見出し: 左に短い青の縦線を付けた16pxの文字(Creator画面の「| ボス名」と同じ形)。
static func section_title(parent: Node, text: String, at: Vector2, node_name: String = "") -> Label:
	rect(parent, Rect2(at.x, at.y + 6, 3, 16), ACCENT_SOFT)
	return label(parent, text, Rect2(at.x + 12, at.y, 300, 28), 16, TEXT, node_name)

## SIMPLE/HARDCOREの札。HARDCOREだけ赤みのある色にする。
static func mode_tag(parent: Node, creator_mode: String, at: Vector2) -> Label:
	var hard := creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED
	var tag := Label.new()
	tag.name = "ModeTag"
	tag.text = RBMChallengeUiKit.mode_display_text(creator_mode)
	tag.position = at
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_override("font", number_font())
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", HARD if hard else SILVER)
	var style := box(Color(HARD_EDGE, 0.18) if hard else Color(SILVER, 0.06), HARD_EDGE if hard else Color("5b6a73"))
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	tag.add_theme_stylebox_override("normal", style)
	parent.add_child(tag)
	return tag

## 角の印(Creatorの外見枠と同じ、四隅だけのL字)。
static func corner_marks(parent: Node, area: Rect2, color: Color) -> void:
	var length := 14.0
	var p := area.position - Vector2(3, 3)
	var q := area.end + Vector2(3, 3)
	for corner in [[p, Vector2(1, 1)], [Vector2(q.x, p.y), Vector2(-1, 1)], [Vector2(p.x, q.y), Vector2(1, -1)], [q, Vector2(-1, -1)]]:
		var at: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		rect(parent, Rect2(Vector2(at.x if d.x > 0 else at.x - length, at.y if d.y > 0 else at.y - 2), Vector2(length, 2)), color)
		rect(parent, Rect2(Vector2(at.x if d.x > 0 else at.x - 2, at.y if d.y > 0 else at.y - length), Vector2(2, length)), color)

## 色の移り変わり(from -> to)。horizontal=falseなら上から下へ。start/endは0〜1の位置。
static func gradient_rect(parent: Node, area: Rect2, from: Color, to: Color, horizontal: bool = false, start: float = 0.0, end: float = 1.0) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	g.set_offset(0, start)
	g.set_offset(1, end)
	var texture := GradientTexture2D.new()
	texture.gradient = g
	texture.width = 512
	texture.height = 512
	texture.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	var t := TextureRect.new()
	t.texture = texture
	t.position = area.position
	t.size = area.size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(t)
	return t

## ボスの足元の楕円の影。
static func floor_shadow(parent: Node, area: Rect2) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = g
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var t := TextureRect.new()
	t.texture = texture
	t.position = area.position
	t.size = area.size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(t)
	return t

static func style_scrollbar(bar: VScrollBar) -> void:
	bar.add_theme_stylebox_override("scroll", box(INSET, Color("162229")))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grabber := box(Color("2a4650") if state == "grabber" else ACCENT_SOFT, Color.TRANSPARENT, 0)
		grabber.content_margin_left = 3
		grabber.content_margin_right = 3
		bar.add_theme_stylebox_override(state, grabber)

## ボス/味方の待機画像(frames/00)から、透明な余白を除いた絵だけを切り出し、fitに収まる
## 大きさにしたTexture2D。ドット絵を拡大する時は整数倍(にじませない)、大きな絵を縮小する
## 時はなめらかに縮める。画像を読めない環境では元の絵をそのまま返す(表示側で縮める)。
## 未知のIDならnull。
static func fitted_sprite(asset_id: String, fit: Vector2) -> Texture2D:
	if asset_id.is_empty():
		return null
	var key := "%s|%d|%d" % [asset_id, int(fit.x), int(fit.y)]
	if _sprite_cache.has(key):
		return _sprite_cache[key]
	var source := RBMVisualAssets.texture(asset_id, 0)
	if source == null:
		return null
	var result: Texture2D = source
	var image := source.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			image = image.get_region(used)
			var scale := minf(fit.x / image.get_width(), fit.y / image.get_height())
			if scale >= 1.0:
				var factor := maxi(1, int(floor(scale)))
				image.resize(image.get_width() * factor, image.get_height() * factor, Image.INTERPOLATE_NEAREST)
			else:
				image.resize(maxi(1, int(image.get_width() * scale)), maxi(1, int(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
			result = ImageTexture.create_from_image(image)
	_sprite_cache[key] = result
	return result

## textureをfitの中に縦横比を保って収めた時の大きさ(拡大はしない)。
static func fitted_size(texture: Texture2D, fit: Vector2) -> Vector2:
	var size := texture.get_size()
	if size.x <= 0 or size.y <= 0:
		return Vector2.ZERO
	var scale := minf(1.0, minf(fit.x / size.x, fit.y / size.y))
	return (size * scale).floor()

## list-bossesのpublished_at(UTCのISO 8601、例 2026-10-01T15:00:00+00:00)を、
## 端末の時刻帯(utc_offset_minutes、日本なら540)での日付 YYYY/MM/DD にする。
static func published_date_text(published_at: String, utc_offset_minutes: int) -> String:
	# 形の違う文字列はTimeへ渡さない(エンジンがエラーを出すため)
	if RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}").search(published_at) == null:
		return ""
	var unix_time := Time.get_unix_time_from_datetime_string(published_at)
	if unix_time <= 0:
		return ""
	return Time.get_date_string_from_unix_time(unix_time + utc_offset_minutes * 60).replace("-", "/")

static func local_published_date_text(published_at: String) -> String:
	return published_date_text(published_at, int(Time.get_time_zone_from_system().get("bias", 0)))
