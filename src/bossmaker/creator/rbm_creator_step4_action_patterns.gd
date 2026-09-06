class_name RBMCreatorStep4ActionPatterns
extends Control

## RPG BOSS MAKER — HARDCORE Creator STEP3「攻撃」画面（2026-09-05全面再設計）。
##
## 旧「行動パターン」ブロックUI（条件/行動/追加ルール/瞬間発動後の複数
## セクションを持つ"パターン"編集画面）を完全に撤去し、「ボスが使用する攻撃を
## 作り、行動する順番に並べる」という新モデルへ作り直した。トップ画面は
## action_sequence（配置スロット）の番号付き一覧だけを表示し、「＋攻撃を
## 追加する」から(1)既存の攻撃から選ぶ (2)新しく攻撃を作る (3)ランダム攻撃を
## 作る、の3択に入る（§4）。
##
## RBMActionPatternRules自体（語彙の共有定数）・RBMCreatorDraft側の
## action_sequence CRUD（add_action_slot等）・RBMBattle側の判定ロジックは
## 一切変更していない——ここは既存のCRUD APIをそのまま呼ぶ、新方式「スロット」
## のUI層のみの全面書き直し。RBMActionEditorForm（性能作成/編集の共通
## フォーム部品）も既存のまま再利用し、show_save_cancel_buttons/
## set_save_cancel_buttons_visible/current_action_data()の3点だけを新設
## （§6「性能・条件・使用回数を1画面にまとめ、確定ボタンは1つだけ」を
## 実現するための最小限の拡張、既存呼び出し元の動作には影響しない）。
##
## §9「既存スキルから選ぶUIは作らない」の唯一の例外はlast_boss_skill条件
## （「前回使った行動」——実装前調査報告書で確認済みのとおり、既存スキルを
## 指し示す参照が定義上どうしても必要）。攻撃の性能自体（通常攻撃・ランダム
## 候補）は§4/§11のとおり「既存の攻撃から選ぶ」と「新しく攻撃を作る」の
## 両方を持つ——新設計ではdraft.skillsが「作成済み攻撃」として全スロットから
## 再利用可能な共有ライブラリになったため（§2）。
##
## 画面遷移は「複数のビュー（VBoxContainer）を1つのScrollContentへ並べて
## 持ち、_show_only()で常に1つだけをvisibleにする」方式——性能作成/編集
## フォーム(_form)と発動条件・使用回数の共有ブロック(_condition_uses_block)
## は、reparent()で現在アクティブなビューの中の「差し込み場所」へ都度移動
## させて使い回す（条件タイプ一覧・AND/OR切替等のUI構築コードを複数箇所に
## 複製しない）。

var draft: RBMCreatorDraft
var main: Node

# ---------------------------------------------------------------------------
# 画面骨格
# ---------------------------------------------------------------------------

var _scroll_container: ScrollContainer
var _scroll_content: VBoxContainer

var _list_view: VBoxContainer
var _add_choice_view: VBoxContainer
var _pick_existing_view: VBoxContainer
var _skill_slot_view: VBoxContainer
var _random_editor_view: VBoxContainer
var _random_add_choice_view: VBoxContainer
var _random_pick_existing_view: VBoxContainer
var _random_create_new_view: VBoxContainer

var _all_views: Array[Control] = []

# --- list_view（§3） ---
var _slot_list: VBoxContainer
var _add_slot_button: Button

# --- pick_existing_view（§5） ---
var _pick_existing_list: VBoxContainer

# --- skill_slot_view（通常攻撃の配置編集: 新規作成/既存選択後/既存編集 共通） ---
var _skill_slot_performance_summary_row: HBoxContainer
var _skill_slot_performance_summary_label: Label
## reparent()で共有フォーム/条件・使用回数ブロックを受け取る「差し込み
## 場所」。STEP8レイアウト回帰テストで発見: これらを素の`Control.new()`に
## すると、VBoxContainer（RBMActionEditorForm自身/_condition_uses_block）
## である子の最小サイズを親（このビュー自身のVBoxContainer）へ一切
## 伝播しない——素のControlはContainerと違い子の最小サイズを自動集約しない
## ため、フォーム展開後もこのビュー全体の高さが実際にはほぼ0のまま
## （確定/キャンセル行と目に見えない形で重なる）というバグになっていた。
## `MarginContainer`（余白0）はContainerサブクラスとして子の最小サイズを
## 正しく自分の最小サイズへ集約するため、この1点だけの変更で伝播チェーンが
## 復活する——視覚的な見た目（余白なし・1個の子をそのまま表示）はControl
## と変わらない。
var _skill_slot_form_slot: Control
var _skill_slot_condition_uses_slot: Control
var _skill_slot_confirm_button: Button
var _skill_slot_delete_button: Button

# --- random_editor_view（ランダム攻撃の配置編集、§10） ---
var _random_mode_option: OptionButton
var _random_candidate_list: VBoxContainer
var _random_condition_uses_slot: Control  # MarginContainer、上のskill_slot_form_slotと同じ理由
var _random_confirm_button: Button
var _random_delete_button: Button

# --- random_pick_existing_view（§11） ---
var _random_pick_existing_list: VBoxContainer

# --- random_create_new_view（§11、フォームの差し込み場所のみ） ---
var _random_create_new_form_slot: Control  # MarginContainer、上のskill_slot_form_slotと同じ理由

# --- 共有: 性能作成/編集フォーム ---
var _form: RBMActionEditorForm
var _form_context: String = ""  # ""|"skill_slot_edit_performance"|"random_candidate_new"|"random_candidate_edit_performance"

# --- 共有: 発動条件・使用回数ブロック（§6/§7/§8/§10/§12） ---
var _condition_uses_block: VBoxContainer
var _condition_list: VBoxContainer
var _condition_logic_option: OptionButton
var _add_condition_button: Button
var _condition_editor: VBoxContainer
var _condition_type_option: OptionButton
var _condition_percent_row: HBoxContainer
var _condition_percent_spin: SpinBox
var _condition_percent_range_row: HBoxContainer
var _condition_percent_min_spin: SpinBox
var _condition_percent_max_spin: SpinBox
var _condition_turn_row: HBoxContainer
var _condition_turn_spin: SpinBox
var _condition_turn_range_row: HBoxContainer
var _condition_turn_min_spin: SpinBox
var _condition_turn_max_spin: SpinBox
var _condition_n_row: HBoxContainer
var _condition_n_spin: SpinBox
var _condition_count_row: HBoxContainer
var _condition_count_spin: SpinBox
var _condition_character_row: HBoxContainer
var _condition_character_option: OptionButton
var _condition_boss_skill_row: HBoxContainer
var _condition_boss_skill_option: OptionButton
var _condition_ally_skill_row: HBoxContainer
var _condition_ally_skill_option: OptionButton
var _condition_attribute_row: HBoxContainer
var _condition_attribute_option: OptionButton
var _uses_unlimited_check: CheckBox
var _uses_limited_check: CheckBox
var _uses_count_spin: SpinBox

# --- 状態: 発動条件・使用回数（共有ブロックが編集する対象、確定時に
#     呼び出し元がスロットのconditions/condition_logic/max_usesへ書き込む） ---
var _pending_conditions: Array = []
var _pending_condition_logic: String = RBMActionPatternRules.DEFAULT_CONDITION_LOGIC
var _pending_max_uses: int = RBMActionPatternRules.UNLIMITED_USES

# --- 状態: skill_slot_view ---
var _skill_slot_editing_slot_id: String = ""  # ""なら新規配置
var _skill_slot_skill_id: String = ""
var _skill_slot_is_new_creation: bool = false  # true=「新しく攻撃を作る」フロー（confirm時にadd_skill）
var _skill_slot_form_active: bool = false      # フォームが現在このビューに表示されているか
var _skill_slot_has_original_snapshot: bool = false
var _skill_slot_original_skill_snapshot: Dictionary = {}

# --- 状態: random_editor_view ---
var _random_editing_slot_id: String = ""  # ""なら新規配置
var _random_candidates: Array = []
var _random_mode: String = RBMActionPatternRules.RANDOM_MODE_EVEN
var _random_original_candidate_ids: Array[String] = []
var _random_original_skill_snapshots: Dictionary = {}  # skill_id -> Dictionary

## §11: 新規作成セッション中（「新しく攻撃を作る」経由）にdraft.skillsへ
## 保存したものの、まだ正式にどこからも参照されていないskill_idの一覧。
## キャンセル・候補削除の時点で、ここに残っているskill_idはdraft.remove_
## skill()で片付ける——新モデルでは同じskill_idが複数箇所から再利用され
## うるため（§2）、ここへ入るのは「このセッションで新規に発行したID」だけ
## （既存skillを選んだ/参照しただけの場合はここへ入れない）。
var _newly_created_skill_ids_this_session: Array[String] = []

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "Step3AdvancedScroll"
	_scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll_container)

	var margin := MarginContainer.new()
	margin.name = "Step3AdvancedScrollMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	_scroll_container.add_child(margin)

	_scroll_content = VBoxContainer.new()
	_scroll_content.name = "Step3AdvancedScrollContent"
	_scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll_content)

	_form = RBMActionEditorForm.new()
	_form.name = "SharedActionEditorForm"
	_form.setup(draft)
	_form.saved.connect(_on_form_saved)
	_form.cancelled.connect(_on_form_cancelled)

	_condition_uses_block = _build_condition_uses_block()
	_condition_uses_block.visible = false

	_list_view = _build_list_view()
	_add_choice_view = _build_add_choice_view()
	_pick_existing_view = _build_pick_existing_view()
	_skill_slot_view = _build_skill_slot_view()
	_random_editor_view = _build_random_editor_view()
	_random_add_choice_view = _build_random_add_choice_view()
	_random_pick_existing_view = _build_random_pick_existing_view()
	_random_create_new_view = _build_random_create_new_view()

	_all_views = [
		_list_view, _add_choice_view, _pick_existing_view, _skill_slot_view,
		_random_editor_view, _random_add_choice_view, _random_pick_existing_view,
		_random_create_new_view,
	]
	for view in _all_views:
		_scroll_content.add_child(view)

	_scroll_content.add_child(_form)
	_scroll_content.add_child(_condition_uses_block)

	_show_only(_list_view)

func _show_only(view: Control) -> void:
	for v in _all_views:
		v.visible = (v == view)

func _new_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _add_label(parent: Control, text: String) -> Label:
	var label := _new_label(text)
	parent.add_child(label)
	return label

func _new_spin(min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	return spin

func _labeled_spin_row(parent: Node, label_text: String, min_value: float, max_value: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_new_label(label_text))
	row.add_child(_new_spin(min_value, max_value, step))
	return row

func _character_display_name(character_id: String) -> String:
	var master := RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id]))
	return str(master.get("display_name", character_id))

# ---------------------------------------------------------------------------
# list_view（§3: 攻撃の一覧、番号付きカード）
# ---------------------------------------------------------------------------

func _build_list_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "ListView"

	var header := Label.new()
	header.name = "AttacksHeader"
	header.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	header.text = "攻撃"
	view.add_child(header)

	_slot_list = VBoxContainer.new()
	_slot_list.name = "SlotList"
	view.add_child(_slot_list)

	_add_slot_button = Button.new()
	_add_slot_button.name = "AddSlotButton"
	_add_slot_button.text = "＋ 攻撃を追加する"
	_add_slot_button.pressed.connect(_on_add_slot_pressed)
	view.add_child(_add_slot_button)

	return view

func _rebuild_slot_list() -> void:
	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()
	for i in range(draft.action_sequence.size()):
		var slot: Dictionary = draft.action_sequence[i]
		var slot_id := str(slot.get("slot_id", ""))
		var summary := RBMActionPatternSummary.slot_summary(slot, draft, i)
		var card := VBoxContainer.new()
		card.name = "SlotCard_%d" % i
		_slot_list.add_child(card)
		_add_label(card, "%02d  %s" % [int(summary["ordinal"]), str(summary["name"])])
		_add_label(card, str(summary["performance"]))
		_add_label(card, str(summary["condition"]))
		_add_label(card, str(summary["uses"]))
		var row := HBoxContainer.new()
		card.add_child(row)
		var edit_button := Button.new()
		edit_button.name = "EditSlotButton_%d" % i
		edit_button.text = "編集"
		edit_button.pressed.connect(_on_edit_slot_pressed.bind(slot_id))
		row.add_child(edit_button)
		var up_button := Button.new()
		up_button.name = "MoveSlotUpButton_%d" % i
		up_button.text = "↑"
		up_button.pressed.connect(_on_move_slot_pressed.bind(slot_id, -1))
		row.add_child(up_button)
		var down_button := Button.new()
		down_button.name = "MoveSlotDownButton_%d" % i
		down_button.text = "↓"
		down_button.pressed.connect(_on_move_slot_pressed.bind(slot_id, 1))
		row.add_child(down_button)
		var delete_button := Button.new()
		delete_button.name = "DeleteSlotButton_%d" % i
		delete_button.text = "削除"
		delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		delete_button.pressed.connect(_on_delete_slot_from_list_pressed.bind(slot_id))
		row.add_child(delete_button)
	_add_slot_button.disabled = not draft.can_add_action_slot()

func _on_add_slot_pressed() -> void:
	if not draft.can_add_action_slot():
		return
	_show_only(_add_choice_view)

func _on_edit_slot_pressed(slot_id: String) -> void:
	var slot := draft.find_action_slot(slot_id)
	if slot.is_empty():
		return
	if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
		_open_random_editor_for_edit(slot_id)
	else:
		_open_skill_slot_for_edit(slot_id)

func _on_move_slot_pressed(slot_id: String, direction: int) -> void:
	draft.move_action_slot(slot_id, direction)
	refresh()

## §19: 一覧カードから直接削除する経路（編集画面を開かない）。編集画面からの
## 削除（_on_skill_slot_delete_pressed/_on_random_delete_pressed）と同じ
## 「削除前に参照していた全skill_idを収集してから削除し、そのあと未参照なら
## 実体も片付ける」手順を踏む。
func _on_delete_slot_from_list_pressed(slot_id: String) -> void:
	var slot := draft.find_action_slot(slot_id)
	var referenced_ids := _collect_slot_referenced_skill_ids(slot)
	draft.remove_action_slot(slot_id)
	for skill_id in referenced_ids:
		draft.remove_skill_if_unreferenced(skill_id)
	main.on_skills_changed()
	refresh()

func _collect_slot_referenced_skill_ids(slot: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
		for candidate_variant in slot.get("candidates", []):
			var sid := str((candidate_variant as Dictionary).get("skill_id", ""))
			if not sid.is_empty() and not ids.has(sid):
				ids.append(sid)
	else:
		var sid := str(slot.get("skill_id", ""))
		if not sid.is_empty() and not ids.has(sid):
			ids.append(sid)
	for condition_variant in slot.get("conditions", []):
		var condition: Dictionary = condition_variant
		if str(condition.get("type", "")) == "last_boss_skill":
			var sid := str(condition.get("skill_id", ""))
			if not sid.is_empty() and not ids.has(sid):
				ids.append(sid)
	return ids

# ---------------------------------------------------------------------------
# add_choice_view（§4: 追加方法の3択）
# ---------------------------------------------------------------------------

func _build_add_choice_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "AddChoiceView"
	_add_label(view, "攻撃の追加方法を選んでください")

	var pick_existing := Button.new()
	pick_existing.name = "AddChoicePickExistingButton"
	pick_existing.text = "既存の攻撃から選ぶ"
	pick_existing.pressed.connect(_on_add_choice_pick_existing_pressed)
	view.add_child(pick_existing)

	var create_new := Button.new()
	create_new.name = "AddChoiceCreateNewButton"
	create_new.text = "新しく攻撃を作る"
	create_new.pressed.connect(_on_add_choice_create_new_pressed)
	view.add_child(create_new)

	var create_random := Button.new()
	create_random.name = "AddChoiceCreateRandomButton"
	create_random.text = "ランダム攻撃を作る"
	create_random.pressed.connect(_on_add_choice_create_random_pressed)
	view.add_child(create_random)

	var cancel := Button.new()
	cancel.name = "AddChoiceCancelButton"
	cancel.text = "キャンセル"
	cancel.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel.pressed.connect(_on_add_choice_cancel_pressed)
	view.add_child(cancel)

	return view

func _on_add_choice_pick_existing_pressed() -> void:
	_show_only(_pick_existing_view)
	_rebuild_pick_existing_list()

func _on_add_choice_create_new_pressed() -> void:
	if not draft.can_add_skill():
		return
	_open_skill_slot_for_new_creation()

func _on_add_choice_create_random_pressed() -> void:
	_open_random_editor_for_new()

func _on_add_choice_cancel_pressed() -> void:
	_show_only(_list_view)

# ---------------------------------------------------------------------------
# pick_existing_view（§5: 既存の攻撃から選ぶ）
# ---------------------------------------------------------------------------

func _build_pick_existing_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "PickExistingView"
	_add_label(view, "既存の攻撃から選んでください")

	_pick_existing_list = VBoxContainer.new()
	_pick_existing_list.name = "PickExistingList"
	view.add_child(_pick_existing_list)

	var cancel := Button.new()
	cancel.name = "PickExistingCancelButton"
	cancel.text = "キャンセル"
	cancel.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel.pressed.connect(_on_pick_existing_cancel_pressed)
	view.add_child(cancel)

	return view

func _rebuild_pick_existing_list() -> void:
	_rebuild_skill_pick_list(_pick_existing_list, "PickExistingSkillButton_%d", _on_pick_existing_skill_selected)

## §5/§11共有: draft.skills一覧を「選択」ボタン付きの行として描画する
## 共通ヘルパー——通常攻撃の「既存の攻撃から選ぶ」とランダム候補の
## 「既存の攻撃から選ぶ」は、対象が同じdraft.skillsであることを除けば
## 全く同じUIのため複製しない。
func _rebuild_skill_pick_list(list_container: VBoxContainer, button_name_format: String, on_selected: Callable) -> void:
	for child in list_container.get_children():
		list_container.remove_child(child)
		child.queue_free()
	for i in range(draft.skills.size()):
		var skill: Dictionary = draft.skills[i]
		var skill_id := str(skill.get("skill_id", ""))
		var row := HBoxContainer.new()
		row.name = "SkillPickRow_%d" % i
		var label := Label.new()
		label.text = "%s（%s）" % [str(skill.get("name", "?")), RBMActionPatternSummary.skill_performance_line(skill)]
		row.add_child(label)
		var select_button := Button.new()
		select_button.name = button_name_format % i
		select_button.text = "選択"
		select_button.pressed.connect(on_selected.bind(skill_id))
		row.add_child(select_button)
		list_container.add_child(row)

func _on_pick_existing_skill_selected(skill_id: String) -> void:
	_open_skill_slot_for_existing_pick(skill_id)

func _on_pick_existing_cancel_pressed() -> void:
	_show_only(_add_choice_view)

# ---------------------------------------------------------------------------
# skill_slot_view（通常攻撃の配置編集: 性能サマリ/フォーム + 発動条件・
# 使用回数、§6/§19）
# ---------------------------------------------------------------------------

func _build_skill_slot_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "SkillSlotView"
	_add_label(view, "攻撃の設定")

	_skill_slot_performance_summary_row = HBoxContainer.new()
	_skill_slot_performance_summary_row.name = "SkillSlotPerformanceSummaryRow"
	view.add_child(_skill_slot_performance_summary_row)
	_skill_slot_performance_summary_label = Label.new()
	_skill_slot_performance_summary_label.name = "SkillSlotPerformanceSummaryLabel"
	_skill_slot_performance_summary_row.add_child(_skill_slot_performance_summary_label)
	var edit_performance_button := Button.new()
	edit_performance_button.name = "SkillSlotEditPerformanceButton"
	edit_performance_button.text = "性能を編集"
	edit_performance_button.pressed.connect(_on_skill_slot_edit_performance_pressed)
	_skill_slot_performance_summary_row.add_child(edit_performance_button)

	_skill_slot_form_slot = MarginContainer.new()
	_skill_slot_form_slot.name = "SkillSlotFormSlot"
	view.add_child(_skill_slot_form_slot)

	_skill_slot_condition_uses_slot = MarginContainer.new()
	_skill_slot_condition_uses_slot.name = "SkillSlotConditionUsesSlot"
	view.add_child(_skill_slot_condition_uses_slot)

	var actions_row := HBoxContainer.new()
	view.add_child(actions_row)
	_skill_slot_confirm_button = Button.new()
	_skill_slot_confirm_button.name = "SkillSlotConfirmButton"
	_skill_slot_confirm_button.pressed.connect(_on_skill_slot_confirm_pressed)
	actions_row.add_child(_skill_slot_confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "SkillSlotCancelButton"
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_skill_slot_cancel_pressed)
	actions_row.add_child(cancel_button)
	_skill_slot_delete_button = Button.new()
	_skill_slot_delete_button.name = "SkillSlotDeleteButton"
	_skill_slot_delete_button.text = "この攻撃を削除"
	_skill_slot_delete_button.pressed.connect(_on_skill_slot_delete_pressed)
	actions_row.add_child(_skill_slot_delete_button)

	return view

func _open_skill_slot_for_new_creation() -> void:
	_skill_slot_editing_slot_id = ""
	_skill_slot_skill_id = ""
	_skill_slot_is_new_creation = true
	_skill_slot_has_original_snapshot = false
	_pending_conditions = []
	_pending_condition_logic = RBMActionPatternRules.DEFAULT_CONDITION_LOGIC
	_pending_max_uses = RBMActionPatternRules.UNLIMITED_USES
	_form.reparent(_skill_slot_form_slot)
	_form.open_for_new("攻撃を作る")
	_form.set_save_cancel_buttons_visible(false)
	_skill_slot_form_active = true
	_condition_uses_block.reparent(_skill_slot_condition_uses_slot)
	_condition_uses_block.visible = true
	_skill_slot_confirm_button.text = "攻撃を追加"
	_skill_slot_delete_button.visible = false
	_show_only(_skill_slot_view)
	_refresh_skill_slot_view()

func _open_skill_slot_for_existing_pick(skill_id: String) -> void:
	_skill_slot_editing_slot_id = ""
	_skill_slot_skill_id = skill_id
	_skill_slot_is_new_creation = false
	_skill_slot_original_skill_snapshot = draft.find_skill(skill_id).duplicate(true)
	_skill_slot_has_original_snapshot = true
	_pending_conditions = []
	_pending_condition_logic = RBMActionPatternRules.DEFAULT_CONDITION_LOGIC
	_pending_max_uses = RBMActionPatternRules.UNLIMITED_USES
	_form.visible = false
	_skill_slot_form_active = false
	_condition_uses_block.reparent(_skill_slot_condition_uses_slot)
	_condition_uses_block.visible = true
	_skill_slot_confirm_button.text = "攻撃を追加"
	_skill_slot_delete_button.visible = false
	_show_only(_skill_slot_view)
	_refresh_skill_slot_view()

func _open_skill_slot_for_edit(slot_id: String) -> void:
	var slot := draft.find_action_slot(slot_id)
	_skill_slot_editing_slot_id = slot_id
	_skill_slot_skill_id = str(slot.get("skill_id", ""))
	_skill_slot_is_new_creation = false
	_skill_slot_original_skill_snapshot = draft.find_skill(_skill_slot_skill_id).duplicate(true)
	_skill_slot_has_original_snapshot = true
	_pending_conditions = (slot.get("conditions", []) as Array).duplicate(true)
	_pending_condition_logic = str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC))
	_pending_max_uses = int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES))
	_form.visible = false
	_skill_slot_form_active = false
	_condition_uses_block.reparent(_skill_slot_condition_uses_slot)
	_condition_uses_block.visible = true
	_skill_slot_confirm_button.text = "保存"
	_skill_slot_delete_button.visible = true
	_show_only(_skill_slot_view)
	_refresh_skill_slot_view()

func _on_skill_slot_edit_performance_pressed() -> void:
	_form_context = "skill_slot_edit_performance"
	_form.reparent(_skill_slot_form_slot)
	_form.open_for_editing(_skill_slot_skill_id, "攻撃の性能を編集")
	_form.set_save_cancel_buttons_visible(true)
	_skill_slot_form_active = true
	_refresh_skill_slot_view()

func _refresh_skill_slot_view() -> void:
	_skill_slot_performance_summary_row.visible = not _skill_slot_form_active
	_form.visible = _skill_slot_form_active
	if not _skill_slot_form_active:
		var skill := draft.find_skill(_skill_slot_skill_id)
		_skill_slot_performance_summary_label.text = "%s\n%s" % [str(skill.get("name", "?")), RBMActionPatternSummary.skill_performance_line(skill)]
	_refresh_condition_uses_block()

func _on_skill_slot_confirm_pressed() -> void:
	var skill_id := _skill_slot_skill_id
	if _skill_slot_is_new_creation:
		var data := _form.current_action_data()
		var new_id := draft.add_skill(data)
		if new_id.is_empty():
			return  # MAX_SKILLS上限（呼び出し元のボタン無効化をすり抜けた場合の防御）
		skill_id = new_id
	var slot := {
		"kind": RBMActionPatternRules.SLOT_KIND_SKILL,
		"skill_id": skill_id,
		"conditions": _pending_conditions,
		"condition_logic": _pending_condition_logic,
		"max_uses": _pending_max_uses,
	}
	if _skill_slot_editing_slot_id.is_empty():
		draft.add_action_slot(slot)
	else:
		draft.update_action_slot(_skill_slot_editing_slot_id, slot)
	_skill_slot_has_original_snapshot = false
	_close_skill_slot_view()
	main.on_skills_changed()
	refresh()

## §19の巻き戻し: 「性能を編集」で既存skillの中身をフォーム経由で変更した
## 後にキャンセルした場合、編集開始時点の内容へ戻す——新規作成フロー
## （_skill_slot_is_new_creation）はconfirm時にしかadd_skill()を呼ばない
## ため、_skill_slot_has_original_snapshotが立たずここでは何もしない。
func _on_skill_slot_cancel_pressed() -> void:
	if _skill_slot_has_original_snapshot and not _skill_slot_skill_id.is_empty():
		draft.update_skill(_skill_slot_skill_id, _skill_slot_original_skill_snapshot.duplicate(true))
		main.on_skills_changed()
	_close_skill_slot_view()
	refresh()

func _on_skill_slot_delete_pressed() -> void:
	var skill_id := _skill_slot_skill_id
	draft.remove_action_slot(_skill_slot_editing_slot_id)
	draft.remove_skill_if_unreferenced(skill_id)
	_skill_slot_has_original_snapshot = false
	_close_skill_slot_view()
	main.on_skills_changed()
	refresh()

func _close_skill_slot_view() -> void:
	_form.visible = false
	_skill_slot_form_active = false
	_form_context = ""
	_skill_slot_has_original_snapshot = false
	_show_only(_list_view)

# ---------------------------------------------------------------------------
# random_editor_view（ランダム攻撃の配置編集、§10/§12）
# ---------------------------------------------------------------------------

func _build_random_editor_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "RandomEditorView"
	_add_label(view, "ランダム攻撃の設定")

	_add_label(view, "■ 使用する攻撃")

	var mode_row := HBoxContainer.new()
	view.add_child(mode_row)
	mode_row.add_child(_new_label("確率設定"))
	_random_mode_option = OptionButton.new()
	_random_mode_option.name = "RandomModeOption"
	for mode in RBMActionPatternRules.RANDOM_MODES:
		_random_mode_option.add_item(str(RBMActionPatternRules.RANDOM_MODE_LABELS.get(mode, mode)))
	_random_mode_option.item_selected.connect(_on_random_mode_selected)
	mode_row.add_child(_random_mode_option)

	_random_candidate_list = VBoxContainer.new()
	_random_candidate_list.name = "RandomCandidateList"
	view.add_child(_random_candidate_list)

	var add_candidate_button := Button.new()
	add_candidate_button.name = "RandomAddCandidateButton"
	add_candidate_button.text = "＋ 攻撃を追加する"
	add_candidate_button.pressed.connect(_on_random_add_candidate_pressed)
	view.add_child(add_candidate_button)

	_random_condition_uses_slot = MarginContainer.new()
	_random_condition_uses_slot.name = "RandomConditionUsesSlot"
	view.add_child(_random_condition_uses_slot)

	var actions_row := HBoxContainer.new()
	view.add_child(actions_row)
	_random_confirm_button = Button.new()
	_random_confirm_button.name = "RandomConfirmButton"
	_random_confirm_button.pressed.connect(_on_random_confirm_pressed)
	actions_row.add_child(_random_confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "RandomCancelButton"
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_random_cancel_pressed)
	actions_row.add_child(cancel_button)
	_random_delete_button = Button.new()
	_random_delete_button.name = "RandomDeleteButton"
	_random_delete_button.text = "このランダム攻撃を削除"
	_random_delete_button.pressed.connect(_on_random_delete_pressed)
	actions_row.add_child(_random_delete_button)

	return view

func _open_random_editor_for_new() -> void:
	_random_editing_slot_id = ""
	_random_candidates = []
	_random_mode = RBMActionPatternRules.RANDOM_MODE_EVEN
	_pending_conditions = []
	_pending_condition_logic = RBMActionPatternRules.DEFAULT_CONDITION_LOGIC
	_pending_max_uses = RBMActionPatternRules.UNLIMITED_USES
	_random_original_candidate_ids.clear()
	_random_original_skill_snapshots.clear()
	_random_confirm_button.text = "ランダム攻撃を追加"
	_random_delete_button.visible = false
	_condition_uses_block.reparent(_random_condition_uses_slot)
	_condition_uses_block.visible = true
	_show_only(_random_editor_view)
	_refresh_random_editor_view()

func _open_random_editor_for_edit(slot_id: String) -> void:
	var slot := draft.find_action_slot(slot_id)
	_random_editing_slot_id = slot_id
	_random_candidates = (slot.get("candidates", []) as Array).duplicate(true)
	_random_mode = str(slot.get("mode", RBMActionPatternRules.RANDOM_MODE_EVEN))
	_pending_conditions = (slot.get("conditions", []) as Array).duplicate(true)
	_pending_condition_logic = str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC))
	_pending_max_uses = int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES))
	_random_original_candidate_ids.clear()
	for candidate_variant in _random_candidates:
		var sid := str((candidate_variant as Dictionary).get("skill_id", ""))
		if not sid.is_empty() and not _random_original_candidate_ids.has(sid):
			_random_original_candidate_ids.append(sid)
	_random_original_skill_snapshots.clear()
	for sid in _random_original_candidate_ids:
		var s := draft.find_skill(sid)
		if not s.is_empty():
			_random_original_skill_snapshots[sid] = s.duplicate(true)
	_random_confirm_button.text = "保存"
	_random_delete_button.visible = true
	_condition_uses_block.reparent(_random_condition_uses_slot)
	_condition_uses_block.visible = true
	_show_only(_random_editor_view)
	_refresh_random_editor_view()

func _refresh_random_editor_view() -> void:
	_random_mode_option.select(RBMActionPatternRules.RANDOM_MODES.find(_random_mode))
	_rebuild_random_candidate_list()
	_refresh_condition_uses_block()

func _on_random_mode_selected(index: int) -> void:
	_random_mode = RBMActionPatternRules.RANDOM_MODES[index]
	_rebuild_random_candidate_list()

func _rebuild_random_candidate_list() -> void:
	for child in _random_candidate_list.get_children():
		_random_candidate_list.remove_child(child)
		child.queue_free()
	var is_manual := _random_mode == RBMActionPatternRules.RANDOM_MODE_MANUAL
	for i in range(_random_candidates.size()):
		var candidate: Dictionary = _random_candidates[i]
		var skill := draft.find_skill(str(candidate.get("skill_id", "")))
		var row := HBoxContainer.new()
		row.name = "RandomCandidateRow_%d" % i
		var label := Label.new()
		label.text = "%s（%s）" % [str(skill.get("name", "?")), RBMActionPatternSummary.skill_performance_line(skill)]
		row.add_child(label)
		if is_manual:
			var weight_spin := SpinBox.new()
			weight_spin.name = "RandomCandidateWeightSpin_%d" % i
			weight_spin.min_value = 0.0
			weight_spin.max_value = 100.0
			weight_spin.step = 0.1
			weight_spin.value = float(candidate.get("weight", 0.0))
			weight_spin.value_changed.connect(_set_random_candidate_weight.bind(i))
			row.add_child(weight_spin)
		var edit_button := Button.new()
		edit_button.name = "EditRandomCandidateButton_%d" % i
		edit_button.text = "編集"
		edit_button.pressed.connect(_edit_random_candidate_performance.bind(i))
		row.add_child(edit_button)
		var delete_button := Button.new()
		delete_button.name = "DeleteRandomCandidateButton_%d" % i
		delete_button.text = "削除"
		delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		delete_button.pressed.connect(_remove_random_candidate.bind(i))
		row.add_child(delete_button)
		_random_candidate_list.add_child(row)

func _set_random_candidate_weight(index: int, value: float) -> void:
	if index < 0 or index >= _random_candidates.size():
		return
	(_random_candidates[index] as Dictionary)["weight"] = value

func _remove_random_candidate(index: int) -> void:
	if index < 0 or index >= _random_candidates.size():
		return
	var skill_id := str((_random_candidates[index] as Dictionary).get("skill_id", ""))
	_random_candidates.remove_at(index)
	_forget_or_delete_provisional_skill(skill_id)
	_rebuild_random_candidate_list()

## §12確定: 候補自身は性能だけを参照する（条件・使用回数という概念は
## 存在しない）——ここで開くのは常に性能編集フォームのみ。
func _edit_random_candidate_performance(index: int) -> void:
	if index < 0 or index >= _random_candidates.size():
		return
	var skill_id := str((_random_candidates[index] as Dictionary).get("skill_id", ""))
	_form_context = "random_candidate_edit_performance"
	_form.reparent(_random_create_new_form_slot)
	_form.open_for_editing(skill_id, "候補の性能を編集")
	_form.set_save_cancel_buttons_visible(true)
	_show_only(_random_create_new_view)

func _on_random_add_candidate_pressed() -> void:
	_show_only(_random_add_choice_view)

func _on_random_confirm_pressed() -> void:
	if _random_candidates.is_empty():
		return
	var slot := {
		"kind": RBMActionPatternRules.SLOT_KIND_RANDOM,
		"mode": _random_mode,
		"candidates": _random_candidates,
		"conditions": _pending_conditions,
		"condition_logic": _pending_condition_logic,
		"max_uses": _pending_max_uses,
	}
	if _random_editing_slot_id.is_empty():
		draft.add_action_slot(slot)
	else:
		draft.update_action_slot(_random_editing_slot_id, slot)
	var previously_referenced := _random_original_candidate_ids.duplicate()
	_newly_created_skill_ids_this_session.clear()
	_random_original_candidate_ids.clear()
	_random_original_skill_snapshots.clear()
	for skill_id in previously_referenced:
		draft.remove_skill_if_unreferenced(skill_id)
	_close_random_editor_view()
	main.on_skills_changed()
	refresh()

func _on_random_cancel_pressed() -> void:
	for skill_id in _newly_created_skill_ids_this_session.duplicate():
		draft.remove_skill(skill_id)
	var changed := not _newly_created_skill_ids_this_session.is_empty()
	for skill_id in _random_original_skill_snapshots.keys():
		draft.update_skill(skill_id, (_random_original_skill_snapshots[skill_id] as Dictionary).duplicate(true))
		changed = true
	_newly_created_skill_ids_this_session.clear()
	_random_original_candidate_ids.clear()
	_random_original_skill_snapshots.clear()
	if changed:
		main.on_skills_changed()
	_close_random_editor_view()
	refresh()

func _on_random_delete_pressed() -> void:
	var referenced_ids: Array[String] = []
	for candidate_variant in _random_candidates:
		var sid := str((candidate_variant as Dictionary).get("skill_id", ""))
		if not sid.is_empty() and not referenced_ids.has(sid):
			referenced_ids.append(sid)
	draft.remove_action_slot(_random_editing_slot_id)
	for skill_id in referenced_ids:
		draft.remove_skill_if_unreferenced(skill_id)
	_newly_created_skill_ids_this_session.clear()
	_random_original_candidate_ids.clear()
	_random_original_skill_snapshots.clear()
	_close_random_editor_view()
	main.on_skills_changed()
	refresh()

func _close_random_editor_view() -> void:
	_show_only(_list_view)

## §11: このセッションで新規作成しただけで一度も正式に保存されていない
## skill_idだけを実際に削除し、それ以外には一切触れない。
func _forget_or_delete_provisional_skill(skill_id: String) -> void:
	if skill_id.is_empty():
		return
	var index := _newly_created_skill_ids_this_session.find(skill_id)
	if index < 0:
		return
	_newly_created_skill_ids_this_session.remove_at(index)
	draft.remove_skill(skill_id)
	main.on_skills_changed()

# ---------------------------------------------------------------------------
# random_add_choice_view（§11: ランダム攻撃内「＋攻撃を追加する」の2択）
# ---------------------------------------------------------------------------

func _build_random_add_choice_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "RandomAddChoiceView"
	_add_label(view, "候補の追加方法を選んでください")

	var pick_existing := Button.new()
	pick_existing.name = "RandomAddChoicePickExistingButton"
	pick_existing.text = "既存の攻撃から選ぶ"
	pick_existing.pressed.connect(_on_random_add_choice_pick_existing_pressed)
	view.add_child(pick_existing)

	var create_new := Button.new()
	create_new.name = "RandomAddChoiceCreateNewButton"
	create_new.text = "新しく攻撃を作る"
	create_new.pressed.connect(_on_random_add_choice_create_new_pressed)
	view.add_child(create_new)

	var cancel := Button.new()
	cancel.name = "RandomAddChoiceCancelButton"
	cancel.text = "キャンセル"
	cancel.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel.pressed.connect(_on_random_add_choice_cancel_pressed)
	view.add_child(cancel)

	return view

func _on_random_add_choice_pick_existing_pressed() -> void:
	_show_only(_random_pick_existing_view)
	_rebuild_random_pick_existing_list()

func _on_random_add_choice_create_new_pressed() -> void:
	if not draft.can_add_skill():
		return
	_form_context = "random_candidate_new"
	_form.reparent(_random_create_new_form_slot)
	_form.open_for_new("候補となる攻撃を作る")
	_form.set_save_cancel_buttons_visible(true)
	_show_only(_random_create_new_view)

func _on_random_add_choice_cancel_pressed() -> void:
	_show_only(_random_editor_view)

# ---------------------------------------------------------------------------
# random_pick_existing_view（§11: 候補を既存の攻撃から選ぶ）
# ---------------------------------------------------------------------------

func _build_random_pick_existing_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "RandomPickExistingView"
	_add_label(view, "既存の攻撃から選んでください")

	_random_pick_existing_list = VBoxContainer.new()
	_random_pick_existing_list.name = "RandomPickExistingList"
	view.add_child(_random_pick_existing_list)

	var cancel := Button.new()
	cancel.name = "RandomPickExistingCancelButton"
	cancel.text = "キャンセル"
	cancel.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel.pressed.connect(_on_random_pick_existing_cancel_pressed)
	view.add_child(cancel)

	return view

func _rebuild_random_pick_existing_list() -> void:
	_rebuild_skill_pick_list(_random_pick_existing_list, "RandomPickExistingSkillButton_%d", _on_random_pick_existing_skill_selected)

func _on_random_pick_existing_skill_selected(skill_id: String) -> void:
	_random_candidates.append({"skill_id": skill_id, "weight": 0.0})
	_show_only(_random_editor_view)
	_rebuild_random_candidate_list()

func _on_random_pick_existing_cancel_pressed() -> void:
	_show_only(_random_add_choice_view)

# ---------------------------------------------------------------------------
# random_create_new_view（§11: 候補を新しく作る、フォームの差し込み場所のみ）
# ---------------------------------------------------------------------------

func _build_random_create_new_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "RandomCreateNewView"
	_add_label(view, "新しく攻撃を作る")

	_random_create_new_form_slot = MarginContainer.new()
	_random_create_new_form_slot.name = "RandomCreateNewFormSlot"
	view.add_child(_random_create_new_form_slot)

	return view

# ---------------------------------------------------------------------------
# 共有フォーム(RBMActionEditorForm)からのコールバック
# ---------------------------------------------------------------------------

func _on_form_saved(skill_id: String) -> void:
	match _form_context:
		"skill_slot_edit_performance":
			_skill_slot_skill_id = skill_id
			_skill_slot_form_active = false
			_form_context = ""
			main.on_skills_changed()
			_show_only(_skill_slot_view)
			_refresh_skill_slot_view()
		"random_candidate_new":
			_random_candidates.append({"skill_id": skill_id, "weight": 0.0})
			_newly_created_skill_ids_this_session.append(skill_id)
			_form_context = ""
			main.on_skills_changed()
			_show_only(_random_editor_view)
			_rebuild_random_candidate_list()
		"random_candidate_edit_performance":
			_form_context = ""
			main.on_skills_changed()
			_show_only(_random_editor_view)
			_rebuild_random_candidate_list()

func _on_form_cancelled() -> void:
	match _form_context:
		"skill_slot_edit_performance":
			_skill_slot_form_active = false
			_form_context = ""
			_show_only(_skill_slot_view)
			_refresh_skill_slot_view()
		"random_candidate_new":
			_form_context = ""
			_show_only(_random_add_choice_view)
		"random_candidate_edit_performance":
			_form_context = ""
			_show_only(_random_editor_view)

# ---------------------------------------------------------------------------
# 共有: 発動条件・使用回数ブロック（§6/§7/§8/§10/§12）
# ---------------------------------------------------------------------------

func _build_condition_uses_block() -> VBoxContainer:
	var block := VBoxContainer.new()
	block.name = "ConditionUsesBlock"

	_add_label(block, "■ 発動条件")

	_condition_list = VBoxContainer.new()
	_condition_list.name = "ConditionList"
	block.add_child(_condition_list)

	_condition_logic_option = OptionButton.new()
	_condition_logic_option.name = "ConditionLogicOption"
	for logic in RBMActionPatternRules.CONDITION_LOGIC_TYPES:
		_condition_logic_option.add_item(str(RBMActionPatternRules.CONDITION_LOGIC_LABELS.get(logic, logic)))
	_condition_logic_option.item_selected.connect(_on_condition_logic_selected)
	block.add_child(_condition_logic_option)

	_add_condition_button = Button.new()
	_add_condition_button.name = "AddConditionButton"
	_add_condition_button.text = "＋ 条件をつける"
	_add_condition_button.pressed.connect(_on_add_condition_pressed)
	block.add_child(_add_condition_button)

	_condition_editor = VBoxContainer.new()
	_condition_editor.name = "ConditionEditor"
	_condition_editor.visible = false
	block.add_child(_condition_editor)
	_build_condition_editor()

	_add_label(block, "■ 使用回数")

	var uses_row := HBoxContainer.new()
	block.add_child(uses_row)
	var uses_group := ButtonGroup.new()
	_uses_unlimited_check = CheckBox.new()
	_uses_unlimited_check.name = "UsesUnlimitedCheck"
	_uses_unlimited_check.text = "制限なし"
	_uses_unlimited_check.button_group = uses_group
	_uses_unlimited_check.toggled.connect(_on_uses_unlimited_toggled)
	uses_row.add_child(_uses_unlimited_check)
	_uses_limited_check = CheckBox.new()
	_uses_limited_check.name = "UsesLimitedCheck"
	_uses_limited_check.text = "回数を指定"
	_uses_limited_check.button_group = uses_group
	_uses_limited_check.toggled.connect(_on_uses_limited_toggled)
	uses_row.add_child(_uses_limited_check)
	_uses_count_spin = SpinBox.new()
	_uses_count_spin.name = "UsesCountSpin"
	_uses_count_spin.min_value = 1
	_uses_count_spin.max_value = 999
	_uses_count_spin.step = 1
	_uses_count_spin.value_changed.connect(_on_uses_count_changed)
	uses_row.add_child(_uses_count_spin)

	return block

func _build_condition_editor() -> void:
	var type_row := HBoxContainer.new()
	_condition_editor.add_child(type_row)
	var type_caption := Label.new()
	type_caption.text = "条件の種類"
	type_row.add_child(type_caption)
	_condition_type_option = OptionButton.new()
	_condition_type_option.name = "ConditionTypeOption"
	for condition_type in RBMActionPatternRules.NORMAL_CONDITION_TYPES:
		_condition_type_option.add_item(str(RBMActionPatternRules.CONDITION_TYPE_LABELS.get(condition_type, condition_type)))
	_condition_type_option.item_selected.connect(_on_condition_type_selected)
	type_row.add_child(_condition_type_option)

	_condition_percent_row = _labeled_spin_row(_condition_editor, "パーセント (%)", 0.0, 100.0, 1.0)
	_condition_percent_spin = _condition_percent_row.get_child(1)

	_condition_percent_range_row = HBoxContainer.new()
	_condition_editor.add_child(_condition_percent_range_row)
	_condition_percent_range_row.add_child(_new_label("下限%"))
	_condition_percent_min_spin = _new_spin(0.0, 100.0, 1.0)
	_condition_percent_range_row.add_child(_condition_percent_min_spin)
	_condition_percent_range_row.add_child(_new_label("上限%"))
	_condition_percent_max_spin = _new_spin(0.0, 100.0, 1.0)
	_condition_percent_range_row.add_child(_condition_percent_max_spin)

	_condition_turn_row = _labeled_spin_row(_condition_editor, "ターン", 1.0, 999999.0, 1.0)
	_condition_turn_spin = _condition_turn_row.get_child(1)

	_condition_turn_range_row = HBoxContainer.new()
	_condition_editor.add_child(_condition_turn_range_row)
	_condition_turn_range_row.add_child(_new_label("下限ターン"))
	_condition_turn_min_spin = _new_spin(1.0, 999999.0, 1.0)
	_condition_turn_range_row.add_child(_condition_turn_min_spin)
	_condition_turn_range_row.add_child(_new_label("上限ターン"))
	_condition_turn_max_spin = _new_spin(1.0, 999999.0, 1.0)
	_condition_turn_range_row.add_child(_condition_turn_max_spin)

	_condition_n_row = _labeled_spin_row(_condition_editor, "○ターンごと", 1.0, 999999.0, 1.0)
	_condition_n_spin = _condition_n_row.get_child(1)

	_condition_count_row = _labeled_spin_row(_condition_editor, "人数", 0.0, 4.0, 1.0)
	_condition_count_spin = _condition_count_row.get_child(1)

	_condition_character_row = HBoxContainer.new()
	_condition_editor.add_child(_condition_character_row)
	_condition_character_row.add_child(_new_label("キャラクター"))
	_condition_character_option = OptionButton.new()
	_condition_character_option.name = "ConditionCharacterOption"
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		_condition_character_option.add_item(_character_display_name(character_id))
	_condition_character_row.add_child(_condition_character_option)

	## §7: ユーザー向けには「既存スキルを選択」ではなく「前回使った行動」
	## として見せる——last_boss_skill条件のみの唯一の例外（draft.skills、
	## この画面が編集中のスロット自身が参照する攻撃も含む「作成済み攻撃」
	## 全体から選ぶ）。
	_condition_boss_skill_row = HBoxContainer.new()
	_condition_editor.add_child(_condition_boss_skill_row)
	_condition_boss_skill_row.add_child(_new_label("前回使った行動"))
	_condition_boss_skill_option = OptionButton.new()
	_condition_boss_skill_option.name = "ConditionBossSkillOption"
	_condition_boss_skill_row.add_child(_condition_boss_skill_option)

	_condition_ally_skill_row = HBoxContainer.new()
	_condition_editor.add_child(_condition_ally_skill_row)
	_condition_ally_skill_row.add_child(_new_label("味方の行動"))
	_condition_ally_skill_option = OptionButton.new()
	_condition_ally_skill_option.name = "ConditionAllySkillOption"
	for skill_id in RBMActionPatternSummary.all_known_ally_skill_ids():
		_condition_ally_skill_option.add_item(RBMActionPatternSummary.ally_skill_display_name(skill_id))
	_condition_ally_skill_row.add_child(_condition_ally_skill_option)

	_condition_attribute_row = HBoxContainer.new()
	_condition_editor.add_child(_condition_attribute_row)
	_condition_attribute_row.add_child(_new_label("属性"))
	_condition_attribute_option = OptionButton.new()
	_condition_attribute_option.name = "ConditionAttributeOption"
	for attribute in RBMDefinitionLoader.VALID_ATTRIBUTES:
		_condition_attribute_option.add_item(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute, attribute)))
	_condition_attribute_row.add_child(_condition_attribute_option)

	var confirm_row := HBoxContainer.new()
	_condition_editor.add_child(confirm_row)
	var confirm_button := Button.new()
	confirm_button.name = "ConfirmConditionButton"
	confirm_button.text = "追加する"
	confirm_button.pressed.connect(_on_confirm_condition_pressed)
	confirm_row.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelConditionButton"
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(func(): _condition_editor.visible = false)
	confirm_row.add_child(cancel_button)

func _refresh_condition_uses_block() -> void:
	_condition_logic_option.select(RBMActionPatternRules.CONDITION_LOGIC_TYPES.find(_pending_condition_logic))
	_rebuild_condition_list()
	if _pending_max_uses == RBMActionPatternRules.UNLIMITED_USES:
		_uses_unlimited_check.button_pressed = true
		_uses_count_spin.editable = false
		_uses_count_spin.value = 1
	else:
		_uses_limited_check.button_pressed = true
		_uses_count_spin.editable = true
		_uses_count_spin.value = float(_pending_max_uses)

func _rebuild_condition_list() -> void:
	for child in _condition_list.get_children():
		_condition_list.remove_child(child)
		child.queue_free()
	for i in range(_pending_conditions.size()):
		var condition: Dictionary = _pending_conditions[i]
		var row := HBoxContainer.new()
		row.name = "ConditionRow_%d" % i
		var label := Label.new()
		label.text = RBMActionPatternSummary.condition_line(condition, draft)
		row.add_child(label)
		var delete_button := Button.new()
		delete_button.name = "RemoveConditionButton_%d" % i
		delete_button.text = "削除"
		delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		delete_button.pressed.connect(_remove_condition.bind(i))
		row.add_child(delete_button)
		_condition_list.add_child(row)
	_condition_logic_option.visible = _pending_conditions.size() > 1

func _on_condition_logic_selected(_index: int) -> void:
	_pending_condition_logic = RBMActionPatternRules.CONDITION_LOGIC_TYPES[_condition_logic_option.selected]

func _on_add_condition_pressed() -> void:
	_condition_type_option.select(0)
	## §7: 「前回使った行動」プルダウンは、開くたびにその時点のdraft.skills
	## から作り直す。
	_condition_boss_skill_option.clear()
	for skill in draft.skills:
		_condition_boss_skill_option.add_item(str(skill.get("name", "?")))
	_refresh_condition_editor_visibility()
	_condition_editor.visible = true

func _on_condition_type_selected(_index: int) -> void:
	_refresh_condition_editor_visibility()

func _refresh_condition_editor_visibility() -> void:
	var condition_type := RBMActionPatternRules.NORMAL_CONDITION_TYPES[_condition_type_option.selected]
	_condition_percent_row.visible = condition_type in ["hp_at_most", "hp_at_least"]
	_condition_percent_range_row.visible = condition_type == "hp_between"
	_condition_turn_row.visible = condition_type in ["turn_at", "turn_at_least", "turn_at_most"]
	_condition_turn_range_row.visible = condition_type == "turn_between"
	_condition_n_row.visible = condition_type == "turn_every_n"
	_condition_count_row.visible = condition_type in ["allies_at_most", "allies_at_least", "allies_exactly"]
	_condition_character_row.visible = condition_type in ["character_alive", "character_downed"]
	_condition_boss_skill_row.visible = condition_type == "last_boss_skill"
	_condition_ally_skill_row.visible = condition_type == "last_received_skill"
	_condition_attribute_row.visible = condition_type == "last_received_attribute"

func _on_confirm_condition_pressed() -> void:
	var condition_type := RBMActionPatternRules.NORMAL_CONDITION_TYPES[_condition_type_option.selected]
	var condition := {"type": condition_type}
	match condition_type:
		"hp_at_most", "hp_at_least":
			condition["percent"] = _condition_percent_spin.value
		"hp_between":
			condition["percent_min"] = _condition_percent_min_spin.value
			condition["percent_max"] = _condition_percent_max_spin.value
		"turn_at", "turn_at_least", "turn_at_most":
			condition["turn"] = int(_condition_turn_spin.value)
		"turn_every_n":
			condition["n"] = int(_condition_n_spin.value)
		"turn_between":
			condition["turn_min"] = int(_condition_turn_min_spin.value)
			condition["turn_max"] = int(_condition_turn_max_spin.value)
		"allies_at_most", "allies_at_least", "allies_exactly":
			condition["count"] = int(_condition_count_spin.value)
		"character_alive", "character_downed":
			condition["character_id"] = str(RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys()[_condition_character_option.selected])
		"last_boss_skill":
			if draft.skills.is_empty():
				return
			condition["skill_id"] = str(draft.skills[_condition_boss_skill_option.selected].get("skill_id", ""))
		"last_received_skill":
			var ally_skill_ids := RBMActionPatternSummary.all_known_ally_skill_ids()
			if ally_skill_ids.is_empty():
				return
			condition["skill_id"] = str(ally_skill_ids[_condition_ally_skill_option.selected])
		"last_received_attribute":
			condition["attribute"] = str(RBMDefinitionLoader.VALID_ATTRIBUTES[_condition_attribute_option.selected])
		_:
			pass
	_pending_conditions.append(condition)
	_condition_editor.visible = false
	_rebuild_condition_list()

func _remove_condition(index: int) -> void:
	if index < 0 or index >= _pending_conditions.size():
		return
	_pending_conditions.remove_at(index)
	_rebuild_condition_list()

func _on_uses_unlimited_toggled(pressed: bool) -> void:
	if not pressed:
		return
	_pending_max_uses = RBMActionPatternRules.UNLIMITED_USES
	_uses_count_spin.editable = false

func _on_uses_limited_toggled(pressed: bool) -> void:
	if not pressed:
		return
	_pending_max_uses = maxi(1, int(_uses_count_spin.value))
	_uses_count_spin.editable = true

func _on_uses_count_changed(value: float) -> void:
	if _uses_limited_check.button_pressed:
		_pending_max_uses = maxi(1, int(value))

# ---------------------------------------------------------------------------

func refresh() -> void:
	_rebuild_slot_list()

func is_step_valid() -> bool:
	return draft.step4_advanced_is_valid()

func validation_message() -> String:
	if not is_step_valid():
		return "攻撃の設定に不備があります（ランダム攻撃の候補が0件、または「自分で設定」の確率合計が100%%になっていないランダム攻撃があります）"
	return ""
