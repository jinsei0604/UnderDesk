class_name RBMCreatorStep4Actions
extends Control

## SIMPLE「行動」画面（2026-10-17 作り直し: HARDCORE の「攻撃」画面
## （RBMCreatorStep4ActionPatterns）と同じ操作の流れにそろえた）。
##
## 流れ: 一覧（番号付きのカード）→「＋ 通常行動を追加する」「＋ 指定行動を追加する」
## →（既存の行動から選ぶ／新しく行動を作る）→ 1つの設定画面（性能＋SIMPLE の設定）
## → 確定ボタンは1つ（「行動を追加」／「保存」）。編集は一覧のカードの「編集」から同じ設定画面を開く。
## - 性能の入力は共通の RBMActionEditorForm（HARDCORE と同じ部品・同じ使い方: 新しく作る時は
##   フォーム自身の保存/キャンセルを隠して外側の確定ボタン1つ、既存の行動は「性能を編集」）。
## - 性能の1行の要約は RBMActionPatternSummary.skill_performance_line()（HARDCORE と共通）。
## - SIMPLE の設定: 通常行動は「使用率」、指定行動は「いつ使う？」（ターン・タイミング）。
##   SIMPLE の制限（発動条件・使用回数・ランダム攻撃・覚醒が無い）はそのまま。
## - データの形（draft.skills・normal_action_percentages・scripted_actions）・保存の形は変えない。
##   通常行動の一覧は normal_action_percentages のキー（＝通常行動として登録した行動）だけを表示する。
##   同じ行動を通常行動と指定行動の両方で使うこともできる（HARDCORE の「既存の攻撃から選ぶ」と同じ。
##   削除は「どこからも使われなくなった時だけ行動そのものを消す」既存の判定 remove_skill_if_unreferenced()）。
##
## 使用率（プレイ体験監査 PX-02）: 以前は作った通常行動が0%で登録され、ボスが一度も使わないまま
## 先へ進めた。今は、最初の通常行動は100%、2つ目からは「今の使用率が均等なら全部を均等に分け直す／
## そうでなければ残り（100%−合計）」を初期値にする。合計が100%でない時・全部0%の時は先へ進めない
## （RBMCreatorDraft.step4_is_valid()）。

const TIMING_LABELS := {
	"replace": "通常行動の代わりに使う",
	"turn_start_interrupt": "ターン開始時に追加で使う",
	"turn_end_interrupt": "ターン終了時に追加で使う",
}
const TIMING_ORDER := ["replace", "turn_start_interrupt", "turn_end_interrupt"]

const PERCENT_SLIDER_MIN_SIZE := Vector2(320.0, 28.0)
const CONTENT_SIDE_MARGIN_PX := 80.0
## UI再配色パス: 左STEPナビ/右BOSS PROFILEと上端を揃えるため上余白のみ0。下余白はスクロール終端の呼吸代。
const CONTENT_TOP_MARGIN_PX := 0.0
const CONTENT_BOTTOM_MARGIN_PX := 40.0
## 使用率が均等かを見る時の許容差（均等にする計算は0.1%刻みなので、端数の差は0.1%）。
const EVEN_TOLERANCE := 0.11

## 注意・誤りの文字の色（HARDCORE の画面の ConditionErrorLabel と同じ色）。
const WARNING_COLOR := Color(1.0, 0.45, 0.4)

const KIND_NORMAL := "normal"
const KIND_SCRIPTED := "scripted"

var draft: RBMCreatorDraft
var main: Node

var _scroll_container: ScrollContainer
var _scroll_content: VBoxContainer
var _all_views: Array[Control] = []

# --- list_view ---
var _list_view: VBoxContainer
var _normal_list: VBoxContainer
var _normal_capacity_notice: Label
var _add_normal_button: Button
var _equalize_button: Button
var _percentage_total_label: Label
var _percent_rows: Dictionary = {}  # skill_id -> {"slider":HSlider,"spin":SpinBox}
var _scripted_list: VBoxContainer
var _scripted_capacity_notice: Label
var _add_scripted_button: Button

# --- add_choice_view / pick_existing_view ---
var _add_choice_view: VBoxContainer
var _add_choice_title: Label
var _add_choice_pick_existing_button: Button
var _add_choice_create_new_button: Button
var _pick_existing_view: VBoxContainer
var _pick_existing_list: VBoxContainer

# --- editor_view（設定画面: 性能＋SIMPLE の設定＋確定ボタン1つ） ---
var _editor_view: VBoxContainer
var _editor_title: Label
var _performance_summary_row: HBoxContainer
var _performance_summary_label: Label
var _shared_skill_notice: Label
var _form_slot: MarginContainer
var _form: RBMActionEditorForm
var _normal_settings: VBoxContainer
var _editor_percent_slider: HSlider
var _editor_percent_spin: SpinBox
var _editor_percent_hint: Label
var _scripted_settings: VBoxContainer
var _scripted_turn_spin: SpinBox
var _scripted_timing_option: OptionButton
var _editor_actions_row: HBoxContainer
var _confirm_button: Button
var _delete_button: Button
var _editor_error_label: Label

# --- 状態 ---
var _kind := KIND_NORMAL
var _editor_skill_id := ""          # 既存の行動（選んだ／編集中）。新しく作る時は ""
var _editor_is_new_creation := false
var _editor_editing_existing := false  # 一覧のカードの「編集」から開いた
var _editor_scripted_index := -1     # 編集中の指定行動の位置
var _form_active := false
var _form_context := ""              # "" | "edit_performance"
var _has_original_snapshot := false
var _original_skill_snapshot: Dictionary = {}
var _default_percent := 0.0          # 新しい通常行動の使用率の初期値（作者が変えたかを見る）
var _syncing := false

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "Step3SimpleScroll"
	_scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	## 横スクロールは無し(縦のみ)。子コンテンツは表示幅へ収める。
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll_container)

	var margin := MarginContainer.new()
	margin.name = "Step3SimpleScrollMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(CONTENT_SIDE_MARGIN_PX))
	margin.add_theme_constant_override("margin_right", int(CONTENT_SIDE_MARGIN_PX))
	margin.add_theme_constant_override("margin_top", int(CONTENT_TOP_MARGIN_PX))
	margin.add_theme_constant_override("margin_bottom", int(CONTENT_BOTTOM_MARGIN_PX))
	_scroll_container.add_child(margin)

	_scroll_content = VBoxContainer.new()
	_scroll_content.name = "Step3SimpleScrollContent"
	_scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll_content)

	_form = RBMActionEditorForm.new()
	_form.name = "ActionEditorForm"
	_form.setup(draft)
	_form.saved.connect(_on_form_saved)
	_form.cancelled.connect(_on_form_cancelled)

	_list_view = _build_list_view()
	_add_choice_view = _build_add_choice_view()
	_pick_existing_view = _build_pick_existing_view()
	_editor_view = _build_editor_view()
	_all_views = [_list_view, _add_choice_view, _pick_existing_view, _editor_view]
	for view in _all_views:
		_scroll_content.add_child(view)
	_show_only(_list_view)

func _show_only(view: Control) -> void:
	for v in _all_views:
		v.visible = (v == view)
	if is_instance_valid(_scroll_container):
		_scroll_container.scroll_vertical = 0

func _new_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

## 長い文でも横へはみ出さないよう、幅いっぱいで折り返すラベル（HARDCORE の画面と同じ扱い）。
func _wrap_label(parent: Control, text: String, node_name: String = "") -> Label:
	var label := _new_label(text)
	if not node_name.is_empty():
		label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _section_header(parent: Control, text: String, node_name: String) -> Label:
	var header := Label.new()
	header.name = node_name
	header.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	header.text = text
	parent.add_child(header)
	return header

func _hint_label(parent: Control, text: String, node_name: String) -> Label:
	var hint := _wrap_label(parent, text, node_name)
	hint.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	return hint

# ---------------------------------------------------------------------------
# list_view（通常行動・指定行動の番号付きカード）
# ---------------------------------------------------------------------------

func _build_list_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "ListView"

	_section_header(view, tr("通常行動"), "NormalActionHeader")
	_hint_label(view, tr("ボスが毎ターン使う行動です。使用率の割合で選ばれます。"), "NormalActionHint")
	_normal_list = VBoxContainer.new()
	_normal_list.name = "NormalActionList"
	view.add_child(_normal_list)
	_percentage_total_label = _wrap_label(view, "", "PercentageTotalLabel")
	var add_row := HBoxContainer.new()
	add_row.name = "NormalActionAddRow"
	view.add_child(add_row)
	_add_normal_button = Button.new()
	_add_normal_button.name = "AddNormalActionButton"
	_add_normal_button.text = tr("＋ 通常行動を追加する")
	_add_normal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_normal_button.pressed.connect(_on_add_normal_pressed)
	add_row.add_child(_add_normal_button)
	_equalize_button = Button.new()
	_equalize_button.name = "EqualizeButton"
	_equalize_button.text = tr("均等にする")
	_equalize_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_equalize_button.pressed.connect(_on_equalize_pressed)
	add_row.add_child(_equalize_button)
	_normal_capacity_notice = _wrap_label(view, tr("これ以上ボスの行動を追加できません"), "NormalActionCapacityNotice")
	_normal_capacity_notice.visible = false

	var separator := HSeparator.new()
	separator.name = "ScriptedActionSeparator"
	view.add_child(separator)

	_section_header(view, tr("指定行動"), "ScriptedActionHeader")
	_hint_label(view, tr("決まったターンに使う行動です。"), "ScriptedActionHint")
	_scripted_list = VBoxContainer.new()
	_scripted_list.name = "ScriptedActionList"
	view.add_child(_scripted_list)
	_add_scripted_button = Button.new()
	_add_scripted_button.name = "AddScriptedActionButton"
	_add_scripted_button.text = tr("＋ 指定行動を追加する")
	_add_scripted_button.pressed.connect(_on_add_scripted_pressed)
	view.add_child(_add_scripted_button)
	_scripted_capacity_notice = _wrap_label(view, tr("これ以上ボスの行動を追加できません"), "ScriptedActionCapacityNotice")
	_scripted_capacity_notice.visible = false
	return view

func _normal_skill_ids() -> Array[String]:
	var out: Array[String] = []
	for skill in draft.skills:
		var skill_id := str(skill.get("skill_id", ""))
		if draft.normal_action_percentages.has(skill_id):
			out.append(skill_id)
	return out

## remove_child()してからqueue_free()する（同じ名前の新しいノードが自動で改名されないように。
## rbm_creator_step5_party.gd・rbm_creator_step4_action_patterns.gd と同じ対策）。
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _rebuild_normal_list() -> void:
	_clear(_normal_list)
	_percent_rows.clear()
	var ids := _normal_skill_ids()
	for i in range(ids.size()):
		var skill_id := ids[i]
		var skill := draft.find_skill(skill_id)
		var card := VBoxContainer.new()
		card.name = "NormalActionCard_%s" % skill_id
		_normal_list.add_child(card)
		_card_title(card, i + 1, str(skill.get("name", "")), "NormalActionName_%s" % skill_id)
		_wrap_label(card, RBMActionPatternSummary.skill_performance_line(skill), "NormalActionDetail_%s" % skill_id)

		var pct := float(draft.normal_action_percentages.get(skill_id, 0.0))
		var percent_row := HBoxContainer.new()
		percent_row.name = "NormalActionPercentRow_%s" % skill_id
		card.add_child(percent_row)
		percent_row.add_child(_new_label(tr("使用率")))
		var slider := HSlider.new()
		slider.name = "PercentSlider_%s" % skill_id
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 0.1
		slider.value = pct
		slider.custom_minimum_size = PERCENT_SLIDER_MIN_SIZE
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_percentage_control_changed.bind(skill_id))
		percent_row.add_child(slider)
		var spin := SpinBox.new()
		spin.name = "PercentSpin_%s" % skill_id
		spin.min_value = 0.0
		spin.max_value = 100.0
		spin.step = 0.1
		spin.suffix = "%"
		spin.value = pct
		spin.value_changed.connect(_on_percentage_control_changed.bind(skill_id))
		percent_row.add_child(spin)
		_percent_rows[skill_id] = {"slider": slider, "spin": spin}
		if pct < 0.05:
			var zero_note := _hint_label(card, tr("使用率が0%の行動は使われません"), "NormalActionZeroNote_%s" % skill_id)
			zero_note.add_theme_color_override("font_color", WARNING_COLOR)

		var row := HBoxContainer.new()
		row.name = "NormalActionButtons_%s" % skill_id
		card.add_child(row)
		var edit_button := Button.new()
		edit_button.name = "EditNormalActionButton_%s" % skill_id
		edit_button.text = tr("編集")
		edit_button.pressed.connect(_on_edit_normal_pressed.bind(skill_id))
		row.add_child(edit_button)
		var delete_button := Button.new()
		delete_button.name = "DeleteNormalActionButton_%s" % skill_id
		delete_button.text = tr("削除")
		delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		delete_button.pressed.connect(_on_delete_normal_pressed.bind(skill_id))
		row.add_child(delete_button)

func _rebuild_scripted_list() -> void:
	_clear(_scripted_list)
	for i in range(draft.scripted_actions.size()):
		var entry: Dictionary = draft.scripted_actions[i]
		var skill := draft.find_skill(str(entry.get("skill_id", "")))
		var card := VBoxContainer.new()
		card.name = "ScriptedActionCard_%d" % i
		_scripted_list.add_child(card)
		_card_title(card, i + 1, str(skill.get("name", "?")), "ScriptedActionName_%d" % i)
		_wrap_label(card, RBMActionPatternSummary.skill_performance_line(skill), "ScriptedActionDetail_%d" % i)
		_wrap_label(card, _when_line(int(entry.get("turn", 0)), str(entry.get("timing", ""))), "ScriptedActionWhen_%d" % i)
		var row := HBoxContainer.new()
		row.name = "ScriptedActionButtons_%d" % i
		card.add_child(row)
		var edit_button := Button.new()
		edit_button.name = "EditScriptedActionButton_%d" % i
		edit_button.text = tr("編集")
		edit_button.pressed.connect(_on_edit_scripted_pressed.bind(i))
		row.add_child(edit_button)
		var up_button := Button.new()
		up_button.name = "MoveScriptedUpButton_%d" % i
		up_button.text = "↑"
		up_button.pressed.connect(move_scripted_action.bind(i, -1))
		row.add_child(up_button)
		var down_button := Button.new()
		down_button.name = "MoveScriptedDownButton_%d" % i
		down_button.text = "↓"
		down_button.pressed.connect(move_scripted_action.bind(i, 1))
		row.add_child(down_button)
		var delete_button := Button.new()
		delete_button.name = "DeleteScriptedActionButton_%d" % i
		delete_button.text = tr("削除")
		delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		delete_button.pressed.connect(remove_scripted_action.bind(i))
		row.add_child(delete_button)

## カードの1行目: 番号（HARDCORE の一覧と同じ「01」）＋行動名（名前だけのラベル）。
func _card_title(card: Control, ordinal: int, skill_name: String, node_name: String) -> void:
	var row := HBoxContainer.new()
	row.name = node_name + "Row"
	card.add_child(row)
	var number := _new_label("%02d" % ordinal)
	number.name = node_name.replace("Name", "Number")
	number.custom_minimum_size = Vector2(32.0, 0.0)
	row.add_child(number)
	var name_label := _new_label(skill_name)
	name_label.name = node_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)

func _when_line(turn: int, timing: String) -> String:
	return tr("いつ：ターン%d・%s") % [turn, tr(str(TIMING_LABELS.get(timing, "?")))]

# ---------------------------------------------------------------------------
# 使用率
# ---------------------------------------------------------------------------

func set_percentage(skill_id: String, value: float) -> void:
	draft.normal_action_percentages[skill_id] = clampf(value, 0.0, 100.0)
	_sync_normal_actions_enabled_flag()
	refresh()

func _on_percentage_control_changed(v: float, skill_id: String) -> void:
	set_percentage(skill_id, v)

func _on_equalize_pressed() -> void:
	draft.equalize_normal_action_percentages_among_normal_actions()
	_sync_normal_actions_enabled_flag()
	refresh()

## RBMCreatorDraft.step4_is_valid()/_normal_actions_for_definition()が見る normal_actions_enabled は、
## 「0%より大きい通常行動が1つでもあるか」から常にここで導出する（作者がON/OFFを直接触るUIは無い）。
func _sync_normal_actions_enabled_flag() -> void:
	draft.normal_actions_enabled = draft.normal_action_percentage_total() > 0.0

## 使用率がすべて同じ（「均等にする」の結果、または1つだけで100%）か。
func _is_evenly_distributed(ids: Array[String]) -> bool:
	if ids.is_empty():
		return true
	if absf(draft.normal_action_percentage_total() - 100.0) >= 0.05:
		return false
	var first := float(draft.normal_action_percentages.get(ids[0], 0.0))
	for skill_id in ids:
		if absf(float(draft.normal_action_percentages.get(skill_id, 0.0)) - first) > EVEN_TOLERANCE:
			return false
	return true

## 新しい通常行動の使用率の初期値: 最初の1つは100%。今の使用率が均等なら、追加後も均等になる値。
## そうでなければ残り（100%−今の合計、0%未満にはしない）。
func default_percent_for_new_normal() -> float:
	var ids := _normal_skill_ids()
	if ids.is_empty():
		return 100.0
	if _is_evenly_distributed(ids):
		return snappedf(100.0 / float(ids.size() + 1), 0.1)
	return clampf(snappedf(100.0 - draft.normal_action_percentage_total(), 0.1), 0.0, 100.0)

# ---------------------------------------------------------------------------
# 追加: 「＋ 追加する」→ 方法を選ぶ（既存の行動から選ぶ／新しく行動を作る）
# ---------------------------------------------------------------------------

## 選べる既存の行動: 通常行動なら、まだ通常行動に入っていないもの。指定行動なら全部
## （同じ行動を別のターンにも使える）。
func _pickable_skill_ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	for skill in draft.skills:
		var skill_id := str(skill.get("skill_id", ""))
		if kind == KIND_NORMAL and draft.normal_action_percentages.has(skill_id):
			continue
		out.append(skill_id)
	return out

func _on_add_normal_pressed() -> void:
	_begin_add(KIND_NORMAL)

func _on_add_scripted_pressed() -> void:
	_begin_add(KIND_SCRIPTED)

## まだ選べる既存の行動が無い時は、方法を選ぶ画面を飛ばして、新しく作る設定画面を開く。
func _begin_add(kind: String) -> void:
	_kind = kind
	var can_create := draft.can_add_skill()
	var can_pick := not _pickable_skill_ids(kind).is_empty()
	if not can_pick:
		if can_create:
			_open_editor_for_new()
		return
	_add_choice_title.text = tr("通常行動の追加方法を選んでください") if kind == KIND_NORMAL else tr("指定行動の追加方法を選んでください")
	_add_choice_create_new_button.disabled = not can_create
	_show_only(_add_choice_view)

func _build_add_choice_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "AddChoiceView"
	_add_choice_title = _wrap_label(view, "", "AddChoiceTitle")
	_add_choice_pick_existing_button = Button.new()
	_add_choice_pick_existing_button.name = "AddChoicePickExistingButton"
	_add_choice_pick_existing_button.text = tr("既存の行動から選ぶ")
	_add_choice_pick_existing_button.pressed.connect(_on_add_choice_pick_existing_pressed)
	view.add_child(_add_choice_pick_existing_button)
	_add_choice_create_new_button = Button.new()
	_add_choice_create_new_button.name = "AddChoiceCreateNewButton"
	_add_choice_create_new_button.text = tr("新しく行動を作る")
	_add_choice_create_new_button.pressed.connect(_on_add_choice_create_new_pressed)
	view.add_child(_add_choice_create_new_button)
	var cancel := Button.new()
	cancel.name = "AddChoiceCancelButton"
	cancel.text = tr("キャンセル")
	cancel.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel.pressed.connect(func(): _show_only(_list_view))
	view.add_child(cancel)
	return view

func _on_add_choice_pick_existing_pressed() -> void:
	_rebuild_pick_existing_list()
	_show_only(_pick_existing_view)

func _on_add_choice_create_new_pressed() -> void:
	if draft.can_add_skill():
		_open_editor_for_new()

func _build_pick_existing_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "PickExistingView"
	_wrap_label(view, tr("既存の行動から選んでください"), "PickExistingTitle")
	_pick_existing_list = VBoxContainer.new()
	_pick_existing_list.name = "PickExistingList"
	view.add_child(_pick_existing_list)
	var cancel := Button.new()
	cancel.name = "PickExistingCancelButton"
	cancel.text = tr("キャンセル")
	cancel.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel.pressed.connect(func(): _show_only(_add_choice_view))
	view.add_child(cancel)
	return view

## HARDCORE の「既存の攻撃から選ぶ」と同じ行の作り（名前（性能の要約）＋「選択」）。
func _rebuild_pick_existing_list() -> void:
	_clear(_pick_existing_list)
	var ids := _pickable_skill_ids(_kind)
	for i in range(ids.size()):
		var skill := draft.find_skill(ids[i])
		var row := HBoxContainer.new()
		row.name = "SkillPickRow_%d" % i
		var label := Label.new()
		label.text = tr("%s（%s）") % [str(skill.get("name", "?")), RBMActionPatternSummary.skill_performance_line(skill)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var select_button := Button.new()
		select_button.name = "PickExistingSkillButton_%d" % i
		select_button.text = tr("選択")
		select_button.pressed.connect(_open_editor_for_existing_pick.bind(ids[i]))
		row.add_child(select_button)
		_pick_existing_list.add_child(row)

# ---------------------------------------------------------------------------
# editor_view（設定画面: 性能＋SIMPLE の設定、確定ボタンは1つ）
# ---------------------------------------------------------------------------

func _build_editor_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "ActionEditorView"
	_editor_title = _section_header(view, "", "ActionEditorTitle")

	_performance_summary_row = HBoxContainer.new()
	_performance_summary_row.name = "PerformanceSummaryRow"
	view.add_child(_performance_summary_row)
	_performance_summary_label = Label.new()
	_performance_summary_label.name = "PerformanceSummaryLabel"
	_performance_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_performance_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_performance_summary_row.add_child(_performance_summary_label)
	var edit_performance := Button.new()
	edit_performance.name = "EditPerformanceButton"
	edit_performance.text = tr("性能を編集")
	edit_performance.pressed.connect(_on_edit_performance_pressed)
	_performance_summary_row.add_child(edit_performance)
	_shared_skill_notice = _hint_label(view, tr("この行動はほかの所でも使われています。性能を変えると、使っている所すべてに反映されます。"), "SharedSkillNotice")

	## フォームの差し込み場所（MarginContainer: 子の最小サイズを親へ伝える。HARDCORE の
	## _skill_slot_form_slot と同じ理由）。
	_form_slot = MarginContainer.new()
	_form_slot.name = "FormSlot"
	view.add_child(_form_slot)
	_form_slot.add_child(_form)

	# --- 通常行動: 使用率 ---
	_normal_settings = VBoxContainer.new()
	_normal_settings.name = "NormalSettingsBlock"
	view.add_child(_normal_settings)
	_normal_settings.add_child(_new_label(tr("■ 使用率")))
	var percent_row := HBoxContainer.new()
	_normal_settings.add_child(percent_row)
	_editor_percent_slider = HSlider.new()
	_editor_percent_slider.name = "EditorPercentSlider"
	_editor_percent_slider.min_value = 0.0
	_editor_percent_slider.max_value = 100.0
	_editor_percent_slider.step = 0.1
	_editor_percent_slider.custom_minimum_size = PERCENT_SLIDER_MIN_SIZE
	_editor_percent_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	percent_row.add_child(_editor_percent_slider)
	_editor_percent_spin = SpinBox.new()
	_editor_percent_spin.name = "EditorPercentSpin"
	_editor_percent_spin.min_value = 0.0
	_editor_percent_spin.max_value = 100.0
	_editor_percent_spin.step = 0.1
	_editor_percent_spin.suffix = "%"
	percent_row.add_child(_editor_percent_spin)
	_editor_percent_slider.value_changed.connect(_on_editor_percent_changed.bind(_editor_percent_spin))
	_editor_percent_spin.value_changed.connect(_on_editor_percent_changed.bind(_editor_percent_slider))
	_editor_percent_hint = _hint_label(_normal_settings, "", "EditorPercentHint")

	# --- 指定行動: いつ使う？ ---
	_scripted_settings = VBoxContainer.new()
	_scripted_settings.name = "ScriptedWhenPanel"
	view.add_child(_scripted_settings)
	_scripted_settings.add_child(_new_label(tr("■ いつ使う？")))
	var turn_row := HBoxContainer.new()
	_scripted_settings.add_child(turn_row)
	turn_row.add_child(_new_label(tr("ターン")))
	_scripted_turn_spin = SpinBox.new()
	_scripted_turn_spin.name = "ScriptedTurnSpin"
	_scripted_turn_spin.min_value = 1
	_scripted_turn_spin.max_value = 999999  # §4-5: no explicit max turn number
	_scripted_turn_spin.step = 1
	turn_row.add_child(_scripted_turn_spin)
	var timing_row := HBoxContainer.new()
	_scripted_settings.add_child(timing_row)
	timing_row.add_child(_new_label(tr("タイミング")))
	_scripted_timing_option = OptionButton.new()
	_scripted_timing_option.name = "ScriptedTimingOption"
	for timing in TIMING_ORDER:
		_scripted_timing_option.add_item(tr(str(TIMING_LABELS[timing])))
	timing_row.add_child(_scripted_timing_option)

	_editor_error_label = _wrap_label(view, "", "ActionEditorErrorLabel")
	_editor_error_label.add_theme_color_override("font_color", WARNING_COLOR)

	_editor_actions_row = HBoxContainer.new()
	_editor_actions_row.name = "ActionEditorActionsRow"
	view.add_child(_editor_actions_row)
	_confirm_button = Button.new()
	_confirm_button.name = "ActionConfirmButton"
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_editor_actions_row.add_child(_confirm_button)
	var cancel := Button.new()
	cancel.name = "ActionCancelButton"
	cancel.text = tr("キャンセル")
	cancel.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel.pressed.connect(_on_editor_cancel_pressed)
	_editor_actions_row.add_child(cancel)
	_delete_button = Button.new()
	_delete_button.name = "ActionDeleteButton"
	_delete_button.text = tr("この行動を削除")
	_delete_button.pressed.connect(_on_editor_delete_pressed)
	_editor_actions_row.add_child(_delete_button)
	return view

func _on_editor_percent_changed(v: float, paired: Range) -> void:
	if _syncing:
		return
	_syncing = true
	paired.value = v
	_syncing = false
	_refresh_editor_percent_hint()

func _refresh_editor_percent_hint() -> void:
	_editor_percent_hint.text = _editor_percent_hint_text()
	_editor_percent_hint.visible = not _editor_percent_hint.text.is_empty()  # 文が無い時は隙間を作らない

func _editor_percent_hint_text() -> String:
	if _editor_percent_spin.value < 0.05:
		return tr("使用率が0%の行動は使われません")
	if _editor_is_new_creation or not _editor_editing_existing:
		var ids := _normal_skill_ids()
		if not ids.is_empty() and _is_evenly_distributed(ids) and absf(_editor_percent_spin.value - _default_percent) < 0.05:
			return tr("追加すると、通常行動の使用率をすべて均等に分け直します")
	return ""

func _set_editor_error(text: String) -> void:
	_editor_error_label.text = text
	_editor_error_label.visible = not text.is_empty()

## 設定画面を開く共通の処理（種類ごとの設定の初期値・表示）。
func _open_editor(title: String, confirm_text: String, show_delete: bool) -> void:
	_editor_title.text = title
	_confirm_button.text = confirm_text
	_delete_button.visible = show_delete
	_normal_settings.visible = _kind == KIND_NORMAL
	_scripted_settings.visible = _kind == KIND_SCRIPTED
	_set_editor_error("")
	_show_only(_editor_view)
	_refresh_editor_view()

func _set_editor_percent(value: float) -> void:
	_syncing = true
	_editor_percent_slider.value = value
	_editor_percent_spin.value = value
	_syncing = false
	_refresh_editor_percent_hint()

func _set_editor_when(turn: int, timing: String) -> void:
	_scripted_turn_spin.value = turn
	_scripted_timing_option.select(maxi(0, TIMING_ORDER.find(timing)))

func _reset_editor_state() -> void:
	_editor_skill_id = ""
	_editor_is_new_creation = false
	_editor_editing_existing = false
	_editor_scripted_index = -1
	_form_active = false
	_form_context = ""
	_has_original_snapshot = false
	_original_skill_snapshot = {}

## 新しく作る: 性能のフォームをその場で開く（フォーム自身の保存/キャンセルは隠し、確定は外側の1つ）。
func _open_editor_for_new() -> void:
	if not draft.can_add_skill():
		return
	_reset_editor_state()
	_editor_is_new_creation = true
	_form_active = true
	_form.open_for_new(tr("通常行動を作る") if _kind == KIND_NORMAL else tr("指定行動を作る"))
	_form.set_awakening_type_available(false)  # SIMPLE に覚醒は無い
	_form.set_save_cancel_buttons_visible(false)
	_default_percent = default_percent_for_new_normal()
	_set_editor_percent(_default_percent)
	_set_editor_when(1, TIMING_ORDER[0])
	_open_editor(tr("通常行動の設定") if _kind == KIND_NORMAL else tr("指定行動の設定"), tr("行動を追加"), false)

## 既存の行動を選んだ: 性能は要約で見せ、「性能を編集」で開く（HARDCORE と同じ）。
func _open_editor_for_existing_pick(skill_id: String) -> void:
	_reset_editor_state()
	_editor_skill_id = skill_id
	_original_skill_snapshot = draft.find_skill(skill_id).duplicate(true)
	_has_original_snapshot = true
	_default_percent = default_percent_for_new_normal()
	_set_editor_percent(_default_percent)
	_set_editor_when(1, TIMING_ORDER[0])
	_open_editor(tr("通常行動の設定") if _kind == KIND_NORMAL else tr("指定行動の設定"), tr("行動を追加"), false)

func _on_edit_normal_pressed(skill_id: String) -> void:
	_kind = KIND_NORMAL
	_reset_editor_state()
	_editor_skill_id = skill_id
	_editor_editing_existing = true
	_original_skill_snapshot = draft.find_skill(skill_id).duplicate(true)
	_has_original_snapshot = true
	_set_editor_percent(float(draft.normal_action_percentages.get(skill_id, 0.0)))
	_open_editor(tr("通常行動の設定"), tr("保存"), true)

func _on_edit_scripted_pressed(index: int) -> void:
	if index < 0 or index >= draft.scripted_actions.size():
		return
	_kind = KIND_SCRIPTED
	_reset_editor_state()
	var entry: Dictionary = draft.scripted_actions[index]
	_editor_skill_id = str(entry.get("skill_id", ""))
	_editor_editing_existing = true
	_editor_scripted_index = index
	_original_skill_snapshot = draft.find_skill(_editor_skill_id).duplicate(true)
	_has_original_snapshot = true
	_set_editor_when(int(entry.get("turn", 1)), str(entry.get("timing", TIMING_ORDER[0])))
	_open_editor(tr("指定行動の設定"), tr("保存"), true)

func _on_edit_performance_pressed() -> void:
	if _editor_skill_id.is_empty():
		return
	_form_context = "edit_performance"
	_form_active = true
	_form.open_for_editing(_editor_skill_id, tr("行動の性能を編集"))
	_form.set_save_cancel_buttons_visible(true)
	_refresh_editor_view()

## 性能のフォーム（自身の保存/キャンセルを出している「性能を編集」の間）は、外側の確定ボタン行を隠す
## （入力中のまま外側の確定を押せないように。HARDCORE の _refresh_skill_slot_view() と同じ）。
func _refresh_editor_view() -> void:
	_form.visible = _form_active
	_performance_summary_row.visible = not _form_active
	if not _form_active:
		var skill := draft.find_skill(_editor_skill_id)
		_performance_summary_label.text = "%s\n%s" % [str(skill.get("name", "?")), RBMActionPatternSummary.skill_performance_line(skill)]
	_shared_skill_notice.visible = not _editor_skill_id.is_empty() and _skill_use_count(_editor_skill_id) > (1 if _editor_editing_existing else 0)
	_editor_actions_row.visible = not (_form_active and _form_context == "edit_performance")

## その行動を使っている所の数（通常行動・指定行動・HARDCORE の配置を合わせて）。
func _skill_use_count(skill_id: String) -> int:
	var count := 1 if draft.normal_action_percentages.has(skill_id) else 0
	for entry in draft.scripted_actions:
		if str(entry.get("skill_id", "")) == skill_id:
			count += 1
	return count

func _on_form_saved(skill_id: String) -> void:
	if _form_context == "edit_performance":
		_editor_skill_id = skill_id
		_form_active = false
		_form_context = ""
		main.on_skills_changed()
		_refresh_editor_view()

func _on_form_cancelled() -> void:
	if _form_context == "edit_performance":
		_form_active = false
		_form_context = ""
		_refresh_editor_view()

func _on_confirm_pressed() -> void:
	var skill_id := _editor_skill_id
	if _editor_is_new_creation:
		var data := _form.current_action_data()
		if str(data.get("name", "")).strip_edges().is_empty():
			_set_editor_error(tr("行動名を入力してください"))
			return
		skill_id = draft.add_skill(data)
		if skill_id.is_empty():
			return  # MAX_SKILLS 上限（ボタンの無効化をすり抜けた時の防御）
	if skill_id.is_empty():
		return
	if _kind == KIND_NORMAL:
		_commit_normal(skill_id)
	else:
		_commit_scripted(skill_id)
	_has_original_snapshot = false
	_close_editor()
	_sync_normal_actions_enabled_flag()
	main.on_skills_changed()
	refresh()

func _commit_normal(skill_id: String) -> void:
	var value := float(_editor_percent_spin.value)
	if _editor_editing_existing:
		draft.normal_action_percentages[skill_id] = clampf(value, 0.0, 100.0)
		return
	var ids := _normal_skill_ids()
	var was_even := _is_evenly_distributed(ids)
	draft.normal_action_percentages[skill_id] = clampf(value, 0.0, 100.0)
	# 今の使用率が均等で、作者が初期値のまま追加したら、追加後も均等に分け直す
	if not ids.is_empty() and was_even and absf(value - _default_percent) < 0.05:
		draft.equalize_normal_action_percentages_among_normal_actions()

## 編集の時は、元の指定行動をいったん外して入れ直す（add_scripted_action() の
## 「同じ(ターン,タイミング)を連続して並べる」既存の約束をそのまま使うため）。
func _commit_scripted(skill_id: String) -> void:
	if _editor_scripted_index >= 0:
		draft.remove_scripted_action(_editor_scripted_index)
	draft.add_scripted_action(int(_scripted_turn_spin.value), skill_id, TIMING_ORDER[_scripted_timing_option.selected])

## キャンセル: 「性能を編集」で変えた中身は、開いた時の内容へ戻す（HARDCORE と同じ）。
func _on_editor_cancel_pressed() -> void:
	if _has_original_snapshot and not _editor_skill_id.is_empty() and not draft.find_skill(_editor_skill_id).is_empty():
		draft.update_skill(_editor_skill_id, _original_skill_snapshot.duplicate(true))
		main.on_skills_changed()
	_close_editor()
	refresh()

func _on_editor_delete_pressed() -> void:
	if _kind == KIND_NORMAL:
		var skill_id := _editor_skill_id
		_has_original_snapshot = false
		_close_editor()
		_on_delete_normal_pressed(skill_id)
	else:
		var index := _editor_scripted_index
		_has_original_snapshot = false
		_close_editor()
		remove_scripted_action(index)

func _close_editor() -> void:
	_form.visible = false
	_reset_editor_state()
	_show_only(_list_view)

# ---------------------------------------------------------------------------
# 削除・並び替え
# ---------------------------------------------------------------------------

## 削除は「どこからも使われなくなった時だけ行動そのものを消す」（draft.remove_skill_if_unreferenced()）。
## 先にこのエントリ自身の参照を外してから判定する。使用率が均等だった時は、残りを均等に分け直す。
func _on_delete_normal_pressed(skill_id: String) -> void:
	var was_even := _is_evenly_distributed(_normal_skill_ids())
	draft.normal_action_percentages.erase(skill_id)
	draft.remove_skill_if_unreferenced(skill_id)
	if was_even and not _normal_skill_ids().is_empty():
		draft.equalize_normal_action_percentages_among_normal_actions()
	_sync_normal_actions_enabled_flag()
	main.on_skills_changed()
	refresh()

func move_scripted_action(index: int, direction: int) -> void:
	draft.move_scripted_action(index, direction)
	refresh()

func remove_scripted_action(index: int) -> void:
	if index < 0 or index >= draft.scripted_actions.size():
		return
	var skill_id := str(draft.scripted_actions[index].get("skill_id", ""))
	draft.remove_scripted_action(index)
	draft.remove_skill_if_unreferenced(skill_id)
	main.on_skills_changed()
	refresh()

# ---------------------------------------------------------------------------

## 一覧を作り直す（開いている画面は変えない。HARDCORE の refresh() と同じ）。
func refresh() -> void:
	_sync_normal_actions_enabled_flag()
	_rebuild_normal_list()
	_rebuild_scripted_list()
	var can_create := draft.can_add_skill()
	_add_normal_button.disabled = not can_create and _pickable_skill_ids(KIND_NORMAL).is_empty()
	_add_scripted_button.disabled = not can_create and _pickable_skill_ids(KIND_SCRIPTED).is_empty()
	_normal_capacity_notice.visible = not can_create
	_scripted_capacity_notice.visible = not can_create
	var ids := _normal_skill_ids()
	_equalize_button.disabled = ids.size() < 2 and (ids.is_empty() or absf(draft.normal_action_percentage_total() - 100.0) < 0.05)
	_percentage_total_label.visible = true
	if ids.is_empty():
		# 通常行動0件かつ指定行動0件の時だけ知らせる（is_step_valid() はこの時も真）。
		_percentage_total_label.text = tr("このボスは行動しません") if draft.scripted_actions.is_empty() else ""
		_percentage_total_label.visible = not _percentage_total_label.text.is_empty()
	else:
		var total := draft.normal_action_percentage_total()
		if absf(total - 100.0) < 0.05:
			_percentage_total_label.text = tr("使用率の合計: 100.0%")
			_percentage_total_label.remove_theme_color_override("font_color")
		else:
			_percentage_total_label.add_theme_color_override("font_color", WARNING_COLOR)
			# 文字の「%」は、% 演算子の左側では必ず「%%」と書く（実行時の書式の失敗を防ぐ）
			_percentage_total_label.text = tr("発動確率の合計を100%%にしてください（現在%.1f%%）") % total
	if _editor_view.visible:
		_refresh_editor_view()

func is_step_valid() -> bool:
	return draft.step4_is_valid()

func validation_message() -> String:
	var heal_problems := draft.heal_limit_problems()
	if not heal_problems.is_empty():
		return heal_problems[0]
	if draft.has_zero_percent_normal_actions_only():
		return tr("通常行動の使用率がすべて0%です。使用率を設定してください")
	if draft.normal_actions_enabled and absf(draft.normal_action_percentage_total() - 100.0) >= 0.05:
		return tr("発動確率の合計を100%%にしてください（現在%.1f%%）") % draft.normal_action_percentage_total()
	return ""
