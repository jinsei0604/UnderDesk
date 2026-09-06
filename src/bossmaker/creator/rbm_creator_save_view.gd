class_name RBMCreatorSaveView
extends Control

## Phase 1 Step 6 §38/§39/§40 — 保存フロー画面。RBMCreatorMainの兄弟ビューと
## して実装（RBMCreatorTestBattleView/RBMCreatorClearCheckViewと同じ既存
## パターン）。実際のRepository呼び出しはすべてmain.press_save_as_new()/
## main.press_overwrite_save()/main.boss_name_already_saved_elsewhere()
## 経由——このビュー自身はUI提示のみを担う。

signal return_to_creator_requested

## 実機プレイ改善③ item4: 保存成功画面専用の戻り先シグナル。既存の
## return_to_creator_requested（選択画面の「戻る」——保存せずSTEP7へ戻る、
## 無改修）とは意図的に別のシグナルにした——保存"成功後"だけ、STEP7を経由
## せずクリエイター一覧へ直帰させるため。
signal return_to_creator_list_requested

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

var main: Node  # RBMCreatorMain

var _choice_panel: VBoxContainer
var _boss_name_label: Label
var _save_new_button: Button       # §39 新規stage: [保存する]
var _overwrite_button: Button      # §39 保存済みstage: [上書き保存]
var _save_as_new_button: Button    # §39 保存済みstage: [新しいボスとして保存]
var _back_button: Button
var _error_label: Label

var _same_name_panel: VBoxContainer
var _same_name_message_label: Label
var _same_name_confirm_button: Button
var _same_name_cancel_button: Button
var _pending_same_name_action: String = ""

var _success_panel: VBoxContainer
var _success_stage_id_label: Label
var _success_return_button: Button

func setup(p_main: Node) -> void:
	main = p_main
	_build_ui()

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.anchor_right = 1.0
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.offset_top = CONTENT_TOP_MARGIN_PX
	add_child(column)

	_build_choice_panel(column)
	_build_same_name_panel(column)
	_build_success_panel(column)

func _build_choice_panel(parent: Control) -> void:
	_choice_panel = VBoxContainer.new()
	_choice_panel.name = "SaveChoicePanel"
	parent.add_child(_choice_panel)

	var title := Label.new()
	title.name = "SaveTitleLabel"
	title.text = "保存"
	_choice_panel.add_child(title)

	_boss_name_label = Label.new()
	_boss_name_label.name = "SaveBossNameLabel"
	_choice_panel.add_child(_boss_name_label)

	_error_label = Label.new()
	_error_label.name = "SaveErrorLabel"
	_choice_panel.add_child(_error_label)

	var button_row := HBoxContainer.new()
	_choice_panel.add_child(button_row)

	_save_new_button = Button.new()
	_save_new_button.name = "SaveNewButton"
	_save_new_button.text = "保存する"
	_save_new_button.pressed.connect(_on_save_new_pressed)
	button_row.add_child(_save_new_button)

	_overwrite_button = Button.new()
	_overwrite_button.name = "OverwriteButton"
	_overwrite_button.text = "上書き保存"
	_overwrite_button.pressed.connect(_on_overwrite_pressed)
	button_row.add_child(_overwrite_button)

	_save_as_new_button = Button.new()
	_save_as_new_button.name = "SaveAsNewButton"
	_save_as_new_button.text = "新しいボスとして保存"
	_save_as_new_button.pressed.connect(_on_save_as_new_pressed)
	button_row.add_child(_save_as_new_button)

	_back_button = Button.new()
	_back_button.name = "SaveBackButton"
	_back_button.text = "戻る"
	_back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_back_button.pressed.connect(_on_back_pressed)
	button_row.add_child(_back_button)

func _build_same_name_panel(parent: Control) -> void:
	_same_name_panel = VBoxContainer.new()
	_same_name_panel.name = "SameNameWarningPanel"
	_same_name_panel.visible = false
	parent.add_child(_same_name_panel)

	_same_name_message_label = Label.new()
	_same_name_message_label.name = "SameNameMessageLabel"
	_same_name_message_label.text = "同じ名前のボス戦がすでに保存されています。\nそれでも保存しますか？"
	_same_name_panel.add_child(_same_name_message_label)

	var row := HBoxContainer.new()
	_same_name_panel.add_child(row)
	_same_name_confirm_button = Button.new()
	_same_name_confirm_button.name = "SameNameConfirmButton"
	_same_name_confirm_button.text = "保存する"
	_same_name_confirm_button.pressed.connect(_on_same_name_confirmed)
	row.add_child(_same_name_confirm_button)
	_same_name_cancel_button = Button.new()
	_same_name_cancel_button.name = "SameNameCancelButton"
	_same_name_cancel_button.text = "キャンセル"
	_same_name_cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_same_name_cancel_button.pressed.connect(_on_same_name_cancelled)
	row.add_child(_same_name_cancel_button)

func _build_success_panel(parent: Control) -> void:
	_success_panel = VBoxContainer.new()
	_success_panel.name = "SaveSuccessPanel"
	_success_panel.visible = false
	parent.add_child(_success_panel)

	var title := Label.new()
	title.name = "SaveSuccessTitleLabel"
	title.text = "保存しました"
	_success_panel.add_child(title)

	_success_stage_id_label = Label.new()
	_success_stage_id_label.name = "SuccessStageIdLabel"
	_success_panel.add_child(_success_stage_id_label)

	_success_return_button = Button.new()
	_success_return_button.name = "SuccessReturnButton"
	_success_return_button.text = "クリエイター一覧に戻る"
	_success_return_button.pressed.connect(_on_success_return_pressed)
	_success_panel.add_child(_success_return_button)

## §39: 新規stage(current_stage_id空)か保存済みstageかでボタン構成を切り替える。
func open() -> void:
	_error_label.text = ""
	_pending_same_name_action = ""
	_same_name_panel.visible = false
	_success_panel.visible = false
	_choice_panel.visible = true
	_boss_name_label.text = main.draft.boss_name
	var has_current_stage: bool = not main.current_stage_id.is_empty()
	_save_new_button.visible = not has_current_stage
	_overwrite_button.visible = has_current_stage
	_save_as_new_button.visible = has_current_stage

func _on_back_pressed() -> void:
	return_to_creator_requested.emit()

# --- §23 新規stageの初回保存 / §25 新しいボスとして保存 ---
# Repository視点では同一操作（save_new）——ボタンの見た目だけが異なる。

func _on_save_new_pressed() -> void:
	_try_save_new()

func _on_save_as_new_pressed() -> void:
	_try_save_new()

func _try_save_new() -> void:
	if bool(main.boss_name_already_saved_elsewhere()):
		_pending_same_name_action = "save_new"
		_choice_panel.visible = false
		_same_name_panel.visible = true
		return
	_do_save_new()

func _on_same_name_confirmed() -> void:
	_same_name_panel.visible = false
	if _pending_same_name_action == "save_new":
		_do_save_new()
	_pending_same_name_action = ""

func _on_same_name_cancelled() -> void:
	_same_name_panel.visible = false
	_choice_panel.visible = true
	_pending_same_name_action = ""

func _do_save_new() -> void:
	var result: Dictionary = main.press_save_as_new()
	if not bool(result.get("ok", false)):
		_choice_panel.visible = true
		_error_label.text = "保存に失敗しました"
		return
	_show_success(str(result.get("stage_id", "")))

# --- §24 上書き保存（自分自身と同名なのは当然なので同名警告なし、§26末尾） ---

func _on_overwrite_pressed() -> void:
	var result: Dictionary = main.press_overwrite_save()
	if not bool(result.get("ok", false)):
		_error_label.text = "保存に失敗しました"
		return
	_show_success(main.current_stage_id)

func _show_success(stage_id: String) -> void:
	_choice_panel.visible = false
	_same_name_panel.visible = false
	_success_panel.visible = true
	_success_stage_id_label.text = "ステージID：%s" % stage_id

## 実機プレイ改善③ item4: 保存成功後「クリエイター一覧に戻る」は、STEP7等の
## 中間STEPを一切経由せず、保存済みボス一覧（RBMCreatorEntryの「保存した
## ボス戦を編集」一覧画面）へ直接戻る。保存成功→Creator（STEP7）→
## クリエイター一覧、という無駄な1操作を無くすための専用シグナル
## （RBMCreatorMain._on_save_return_to_creator_list()参照）。保存内容・
## stage_id・未保存変更状態はこのシグナル発火より前（_do_save_new()/
## _on_overwrite_pressed()）で既に確定済みのため、ここでは一切触れない。
func _on_success_return_pressed() -> void:
	return_to_creator_list_requested.emit()

