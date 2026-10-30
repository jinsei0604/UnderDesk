class_name RBMDemoWelcome
extends Control

## 体験版の初めての起動だけに出す歓迎画面（2026-10-29 ユーザー確定）。ガイド（RBMDemoGuide）とは別の画面。
## 流れ: 体験版を起動 → タイトルの上にこの画面 →「はじめる」→ この画面を閉じる → すぐにガイドを開く（RBMGameRoot）。
## 製品版では作らない（RBMGameRoot が体験版の時だけ置く）。見た目は紺＋水色（RBMChallengeListStyle）。
## 出したかどうかは体験版の保存の置き場（RBMEdition.data_root()）のファイルで覚える（通常の保存・製品版への引き継ぎとは別）。

signal started

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const Menu := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
const SEEN_FILE := "demo_welcome_seen.json"
const PANEL_SIZE := Vector2(760, 440)

var _start_button: Button

static func seen_path() -> String:
	return RBMEdition.data_root() + "/" + SEEN_FILE

static func was_seen() -> bool:
	return FileAccess.file_exists(seen_path())

static func mark_seen() -> void:
	DirAccess.make_dir_recursive_absolute(RBMEdition.data_root())
	RBMLocalStageRepository._atomic_write(seen_path(), JSON.stringify({"seen": true}))

func _ready() -> void:
	name = "DemoWelcome"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := Panel.new()
	panel.name = "DemoWelcomePanel"
	panel.size = PANEL_SIZE
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE / 2.0
	panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.98), S.ACCENT_SOFT))
	add_child(panel)
	S.rect(panel, Rect2(0, 0, PANEL_SIZE.x, 3), S.ACCENT_SOFT)
	var title := Menu.shadow(_centered(panel, tr("ようこそ！"), 56, 40, S.TEXT, "DemoWelcomeTitle"))
	title.size.y = 56
	var game_name := _centered(panel, "Makers & Challengers", 130, 30, S.ACCENT, "DemoWelcomeGameName")
	game_name.add_theme_font_override("font", S.number_font())
	S.rect(panel, Rect2(PANEL_SIZE.x / 2.0 - 160, 186, 320, 1), S.PANEL_EDGE)
	_centered(panel, tr("体験版をプレイしていただきありがとうございます！"), 210, 19, S.TEXT, "DemoWelcomeThanks")
	var intro := _centered(panel, tr("自分だけのボスを作り、ほかのプレイヤーが作ったボスに挑戦しよう！"), 252, 16, S.SILVER, "DemoWelcomeIntro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size = Vector2(PANEL_SIZE.x - 96, 56)
	_start_button = Button.new()
	_start_button.name = "DemoWelcomeStartButton"
	_start_button.text = tr("はじめる")
	_start_button.add_theme_font_size_override("font_size", 18)
	S.button_style(_start_button, true)
	_start_button.size = Vector2(240, 54)
	_start_button.position = Vector2((PANEL_SIZE.x - 240) / 2.0, PANEL_SIZE.y - 90)
	_start_button.pressed.connect(_on_start_pressed)
	panel.add_child(_start_button)

## 中央ぞろえの1行（幅はパネルの内側いっぱい。長い英語は折り返す）。
func _centered(parent: Control, text: String, y: float, font_size: int, color: Color, node_name: String) -> Label:
	var label := S.label(parent, text, Rect2(48, y, PANEL_SIZE.x - 96, font_size + 18), font_size, color, node_name)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func open_welcome() -> void:
	visible = true
	_start_button.grab_focus()

## 「はじめる」（Enter・Esc も同じ）: 出したことを覚えてから閉じ、started を出す（ガイドを開くのは RBMGameRoot）。
## 先に覚えるので、このあとガイドの途中でゲームを終えても、次の起動で歓迎画面は出ない。
func _on_start_pressed() -> void:
	if not visible:
		return
	mark_seen()
	visible = false
	started.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_start_pressed()
