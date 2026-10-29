class_name RBMDemoGuide
extends Control

## 体験版のガイド（2026-10-28）。体験版のホームの「ガイド」と、体験版を初めて起動した時に出す、3ページの簡単な案内:
## 基本の戦い方・SIMPLE でボスを作る・体験版でできること。製品版では作らない（RBMGameRoot が体験版の時だけ置く）。
## 見た目は紺＋水色（RBMChallengeListStyle）。閉じる・前へ・次へ・Esc で操作する。

signal closed

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const Menu := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
## 初めての起動で一度だけ自動で出したかを覚えるファイル（体験版の置き場の中）。
const SEEN_FILE := "demo_guide_seen.json"
const PANEL_SIZE := Vector2(760, 470)
const PAGES := [
	{"title": "基本の戦い方", "lines": [
		"味方の番になったら「通常攻撃」「スキル」「防御」から行動を選びます。",
		"スキルは SP を使います。SP が足りないスキルは選べません。",
		"ボスの弱点の属性で攻撃するとダメージが増え、耐性のある属性だと減ります。",
		"「防御」を選ぶと、次の自分の番まで受けるダメージが減ります。",
		"ボスの HP を 0 にすれば勝利です。味方が全員倒れると敗北です。",
	]},
	{"title": "SIMPLE でボスを作る", "lines": [
		"「ボス作成」の「新しいボス戦を作る」から作り始めます。体験版は SIMPLE で作ります。",
		"「外見と基本情報」「能力」「行動」「攻略パーティ」の順に設定します。",
		"「行動」では技を作り、それぞれを使う割合を決めます。",
		"「最終確認」でクリアチェックに勝つと、そのボス戦をオンラインに公開できます。",
	]},
	{"title": "体験版でできること", "lines": [
		"ボスの外見は竜・スライム・幽霊・朽ちた機械武者の4体から選べます。",
		"保存できるボスは5体、オンラインに公開できるボスは2体までです。",
		"オンラインでは、この4体で作られた SIMPLE のボス戦に挑戦できます。",
		"HARDCORE でのボス作成は製品版で遊べます。",
		"体験版で作ったボスと討伐記録は、同じPCの製品版に引き継げます。",
	]},
]

var _page := 0
var _title: Label
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

func _ready() -> void:
	name = "DemoGuide"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := Panel.new()
	panel.name = "DemoGuidePanel"
	panel.size = PANEL_SIZE
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE / 2.0
	panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.98), S.ACCENT_SOFT))
	add_child(panel)
	S.label(panel, tr("体験版ガイド"), Rect2(28, 18, 400, 26), 14, S.MUTED, "DemoGuideCaption")
	_title = Menu.shadow(S.label(panel, "", Rect2(28, 46, PANEL_SIZE.x - 56, 40), 26, S.TEXT, "DemoGuideTitle"))
	S.rect(panel, Rect2(28, 94, PANEL_SIZE.x - 56, 1), S.PANEL_EDGE)
	_body = VBoxContainer.new()
	_body.name = "DemoGuideBody"
	_body.position = Vector2(28, 110)
	_body.size = Vector2(PANEL_SIZE.x - 56, 260)
	_body.add_theme_constant_override("separation", 10)
	panel.add_child(_body)
	_page_label = S.label(panel, "", Rect2(28, PANEL_SIZE.y - 66, 120, 44), 14, S.MUTED, "DemoGuidePage")
	_prev = _button(panel, tr("前へ"), Rect2(PANEL_SIZE.x - 420, PANEL_SIZE.y - 70, 120, 48), "DemoGuidePrevButton", func(): _show_page(_page - 1))
	_next = _button(panel, tr("次へ"), Rect2(PANEL_SIZE.x - 290, PANEL_SIZE.y - 70, 120, 48), "DemoGuideNextButton", func(): _show_page(_page + 1))
	var close := _button(panel, tr("閉じる"), Rect2(PANEL_SIZE.x - 160, PANEL_SIZE.y - 70, 132, 48), "DemoGuideCloseButton", close_guide, true)
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

func _show_page(index: int) -> void:
	_page = clampi(index, 0, PAGES.size() - 1)
	var page: Dictionary = PAGES[_page]
	_title.text = tr(str(page["title"]))
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for line in page["lines"]:
		var l := Label.new()
		l.text = "・" + tr(str(line))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PANEL_SIZE.x - 56, 0)
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", S.SILVER)
		_body.add_child(l)
	_page_label.text = "%d / %d" % [_page + 1, PAGES.size()]
	_prev.disabled = _page == 0
	_next.disabled = _page == PAGES.size() - 1

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_guide()
