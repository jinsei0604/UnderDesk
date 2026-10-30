class_name RBMDemoGuide
extends Control

## 体験版のガイド（2026-10-28、2026-10-29 に作り直し）。体験版のホームの「ガイド」と、初めての起動の歓迎画面
## （RBMDemoWelcome）の「はじめる」の後に出す3ページ: 戦闘の遊び方・自分だけのボスを作ろう・体験版でできること。
## 製品版では作らない（RBMGameRoot が体験版の時だけ置く）。見た目は紺＋水色（RBMChallengeListStyle）。閉じる・前へ・次へ・Esc。
##
## 2026-10-29 ユーザー確定: 文章中心をやめ、各ページに実際のゲームの画面（assets_bossmaker/ui/demo_guide/、体験版を
## 起動して撮って大事な所を切り抜いた画像。日本語・英語それぞれ）を大きく出し、番号の枠（Godot の UI として画像の上に
## 重ねる）と、番号に対応した短い説明を下に並べる。番号の枠の位置は、画像（切り抜いた後）の画素の座標で持つ。

signal closed

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const Menu := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
## 初めての起動で一度だけ自動で出したかを覚えるファイル（体験版の置き場の中）。
const SEEN_FILE := "demo_guide_seen.json"
const PANEL_SIZE := Vector2(1240, 700)
const IMAGE_DIR := "res://assets_bossmaker/ui/demo_guide/"
## 画像を出す枠（パネルの中）。画像は縦横比を保ってこの中に収め、上に寄せる（説明はその下から）。
const IMAGE_BOX := Rect2(20, 58, 1200, 474)
const BUTTON_ROW_Y := 646.0
## 番号の枠と丸の色（ゲームの水色の枠と見分けられる明るい黄色）。
const MARK_COLOR := Color("ffcc4d")
const MARK_TEXT := Color("10161c")

## image: 画像の名前（<image>_<ja|en>.png）。marks: 番号の枠（画像の画素の座標）。lines: 番号の説明（marks と同じ順）。
## notes: 番号の無い小さな補足。
const PAGES := [
	{"title": "戦闘の遊び方", "image": "battle",
		"marks": [Rect2(916, 452, 350, 252), Rect2(248, 652, 208, 32), Rect2(16, 12, 640, 70)],
		# ② の丸は枠の右（カードのすきま）に置く（左上だと HP の数字にかかる）。値は画像の画素の座標（丸の左上）。
		"badges": {1: Vector2(446, 640)},
		"lines": ["味方の番になったら、通常攻撃・スキル・防御から行動を選ぼう", "スキルにはSPを使うよ", "ボスのHPを0にすれば勝利！ 味方が全滅すると敗北だよ"],
		"notes": ["弱点の属性で攻撃すると、ダメージが増えるよ"]},
	{"title": "自分だけのボスを作ろう", "image": "create",
		"marks": [Rect2(365, 207, 286, 36), Rect2(642, 47, 122, 120), Rect2(366, 292, 118, 78)],
		# 英語の画面は行動のカードが折り返して高くなるので、枠の位置が違う
		"marks_en": [Rect2(365, 233, 301, 36), Rect2(606, 65, 154, 118), Rect2(366, 318, 118, 100)],
		"lines": ["技を作って、ボスの行動に加えよう", "使用率で、ボスが技を使う割合を決められるよ", "指定行動では、決めたターンに技を使わせられるよ"],
		"notes": ["ボスや味方の能力・覚醒も自由に調整できるよ。完成したボスは保存でき、クリアチェックを突破するとオンラインに公開できるよ"]},
	{"title": "体験版でできること", "image": "online",
		"marks": [Rect2(16, 140, 412, 116), Rect2(577, 10, 298, 46)],
		"lines": ["一覧から挑戦するボスを選ぼう", "オンラインでは異なるボス15体に挑戦可能！ 同じボスには何度でも挑戦できるよ"],
		"notes": ["体験版では4種類の外見からボスを作れるよ。ボスの保存は5体、オンライン公開は2体まで", "製品版ではHARDCOREが開放！ 体験版のデータも同じPCの製品版に引き継げるよ"]},
]

var _page := 0
var _panel: Panel
var _title: Label
var _image: TextureRect
var _marks: Control
var _body: VBoxContainer
var _page_label: Label
var _prev: Button
var _next: Button

static func seen_path() -> String:
	return RBMEdition.data_root() + "/" + SEEN_FILE

static func was_seen() -> bool:
	return FileAccess.file_exists(seen_path())

static func mark_seen() -> void:
	DirAccess.make_dir_recursive_absolute(RBMEdition.data_root())
	RBMLocalStageRepository._atomic_write(seen_path(), JSON.stringify({"seen": true}))

## そのページの画像（今の言語のもの。無ければ日本語のもの）。
static func image_path(page: int, locale: String) -> String:
	var base := IMAGE_DIR + str(PAGES[page]["image"])
	var lang := "en" if locale.begins_with("en") else "ja"
	if ResourceLoader.exists(base + "_" + lang + ".png"):
		return base + "_" + lang + ".png"
	return base + "_ja.png"

func _ready() -> void:
	name = "DemoGuide"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = Panel.new()
	_panel.name = "DemoGuidePanel"
	_panel.size = PANEL_SIZE
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = -PANEL_SIZE / 2.0
	_panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.98), S.ACCENT_SOFT))
	add_child(_panel)
	var caption := S.label(_panel, tr("体験版ガイド"), Rect2(24, 12, 300, 20), 13, S.MUTED, "DemoGuideCaption")
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title = Menu.shadow(S.label(_panel, "", Rect2(24, 26, PANEL_SIZE.x - 200, 30), 24, S.TEXT, "DemoGuideTitle"))
	_page_label = S.label(_panel, "", Rect2(PANEL_SIZE.x - 140, 18, 116, 30), 16, S.MUTED, "DemoGuidePage")
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_image = TextureRect.new()
	_image.name = "DemoGuideImage"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_image)
	_marks = Control.new()
	_marks.name = "DemoGuideMarks"
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_marks)
	_body = VBoxContainer.new()
	_body.name = "DemoGuideBody"
	_body.add_theme_constant_override("separation", 3)
	_panel.add_child(_body)
	_prev = _button(_panel, tr("前へ"), Rect2(PANEL_SIZE.x - 420, BUTTON_ROW_Y, 120, 44), "DemoGuidePrevButton", func(): _show_page(_page - 1))
	_next = _button(_panel, tr("次へ"), Rect2(PANEL_SIZE.x - 290, BUTTON_ROW_Y, 120, 44), "DemoGuideNextButton", func(): _show_page(_page + 1))
	var close := _button(_panel, tr("閉じる"), Rect2(PANEL_SIZE.x - 160, BUTTON_ROW_Y, 136, 44), "DemoGuideCloseButton", close_guide, true)
	close.focus_mode = Control.FOCUS_ALL
	_show_page(0)

func _button(parent: Control, text: String, rect: Rect2, node_name: String, on_pressed: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 16)
	S.button_style(b, primary)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b

func open_guide() -> void:
	_show_page(0)
	visible = true
	_next.grab_focus()

func close_guide() -> void:
	visible = false
	mark_seen()
	closed.emit()

func current_page() -> int:
	return _page

## 画像を出している矩形（パネルの中）。番号の枠の位置を確かめるテスト・撮影にも使う。
func image_rect() -> Rect2:
	return Rect2(_image.position, _image.size)

func _show_page(index: int) -> void:
	_page = clampi(index, 0, PAGES.size() - 1)
	var page: Dictionary = PAGES[_page]
	_title.text = tr(str(page["title"]))
	_page_label.text = "%d / %d" % [_page + 1, PAGES.size()]
	_prev.disabled = _page == 0
	_next.disabled = _page == PAGES.size() - 1
	# 画像: 縦横比を保って IMAGE_BOX に収め、左右は真ん中・上に寄せる。
	var texture: Texture2D = load(image_path(_page, TranslationServer.get_locale()))
	_image.texture = texture
	var source := Vector2(texture.get_width(), texture.get_height()) if texture != null else IMAGE_BOX.size
	var scale := minf(IMAGE_BOX.size.x / source.x, IMAGE_BOX.size.y / source.y)
	var shown := (source * scale).round()
	_image.position = Vector2(IMAGE_BOX.position.x + roundf((IMAGE_BOX.size.x - shown.x) / 2.0), IMAGE_BOX.position.y)
	_image.size = shown
	# 番号の枠（画像の画素の座標 → パネルの中）。丸は枠の左上の角に重ね、画像の外へは出さない。
	for child in _marks.get_children():
		_marks.remove_child(child)
		child.queue_free()
	var english := TranslationServer.get_locale().begins_with("en") and _image.texture != null and _image.texture.resource_path.ends_with("_en.png")
	var marks: Array = page.get("marks_en", page["marks"]) if english else page["marks"]
	for i in range(marks.size()):
		var r: Rect2 = marks[i]
		var at := Rect2(_image.position + r.position * scale, r.size * scale)
		var frame := Panel.new()
		frame.name = "DemoGuideMark%d" % (i + 1)
		frame.position = at.position.round()
		frame.size = at.size.round()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.draw_center = false
		style.border_color = MARK_COLOR
		style.set_border_width_all(3)
		style.set_corner_radius_all(4)
		frame.add_theme_stylebox_override("panel", style)
		_marks.add_child(frame)
		var badge_pos := at.position - Vector2(14, 14)
		var badges: Dictionary = page.get("badges", {})
		if badges.has(i):
			badge_pos = _image.position + (badges[i] as Vector2) * scale
		badge_pos = badge_pos.clamp(_image.position, _image.position + _image.size - Vector2(30, 30))
		_marks.add_child(_badge(i + 1, badge_pos, "DemoGuideMarkBadge%d" % (i + 1)))
	# 説明: 画像のすぐ下から。番号の丸＋1行（長い時は折り返す）、その後に小さな補足。
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_body.position = Vector2(40, _image.position.y + shown.y + 10)
	_body.size = Vector2(PANEL_SIZE.x - 80, BUTTON_ROW_Y - _body.position.y - 6)
	var lines: Array = page["lines"]
	for i in range(lines.size()):
		var row := HBoxContainer.new()
		row.name = "DemoGuideLine%d" % (i + 1)
		row.add_theme_constant_override("separation", 10)
		_body.add_child(row)
		var badge := _badge(i + 1, Vector2.ZERO, "DemoGuideLineBadge%d" % (i + 1))
		badge.custom_minimum_size = Vector2(24, 24)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var text := Label.new()
		text.text = tr(str(lines[i]))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 17)
		text.add_theme_color_override("font_color", S.TEXT)
		row.add_child(text)
	for note in page["notes"]:
		var n := Label.new()
		n.name = "DemoGuideNote"
		n.text = tr(str(note))
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.add_theme_font_size_override("font_size", 13)
		n.add_theme_color_override("font_color", S.MUTED)
		_body.add_child(n)

## 番号の丸（黄色の丸に暗い数字）。
func _badge(number: int, at: Vector2, node_name: String) -> Panel:
	var badge := Panel.new()
	badge.name = node_name
	badge.position = at.round()
	badge.size = Vector2(28, 28)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = MARK_COLOR
	style.set_corner_radius_all(14)
	style.border_color = MARK_TEXT
	style.set_border_width_all(2)
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = str(number)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MARK_TEXT)
	label.add_theme_font_override("font", S.number_font())
	badge.add_child(label)
	return badge

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_guide()
