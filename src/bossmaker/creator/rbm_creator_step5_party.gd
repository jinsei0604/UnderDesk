class_name RBMCreatorStep5Party
extends Control

## Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）§4/§9/§10/§12〜§17:
## 新STEP4「攻略パーティ」——上段にパーティメンバーのカード列（クリックで
## 編集対象として選択、「外す」はカード上の小さな操作）、その下に「選択
## キャラクター設定」（[使用可能スキル]既定/[性能調整]の2タブ）を持つ。
##
## §13/§17: 旧・独立STEP「使用可能スキル」（RBMCreatorStep6PartySkills、
## Creatorのナビゲーションからは撤去）のロジックをそのままこの画面の
## [使用可能スキル]タブへ移設した——draft.is_ally_skill_allowed()/
## set_ally_skill_allowed()/set_all_ally_skills_allowed()自体は無改修、
## 「全キャラを同時に並べて編集する」UIから「選択中の1人だけを編集する」
## UIへ作り直した（旧・複数キャラ同時編集用の_editing_ids/_staged_allowed
## Dictionaryは、選択が常に1人になったことで単一のstaged Dictionaryへ
## 単純化できた）。
##
## §14/§15: 旧「性能を見る」ボタン（ViewPerformanceButton_%s）は廃止し、
## カード自体をクリックして選択する方式へ変更した。カスタム化されている
## （draft.is_ally_customized()）キャラクターのカードには「CUSTOM」表示を
## 追加する——新しい概念ではなく、既存のally_overrides/ally_allowed_skill_ids
## の状態を都度比較する読み取り専用の判定（RBMCreatorDraft.is_ally_customized()
## 参照）。
##
## §16: 旧・画面全体を覆う大きな「攻略側カスタム設定をすべて標準値へ戻す」
## ボタンは、機能（draft.reset_all_ally_overrides()、ADVANCED専用）を一切
## 変更せず、コンパクトな「全員を標準に戻す」として画面上部へ配置し直した。

const CONTENT_SIDE_MARGIN_PX := 40.0
const CONTENT_TOP_MARGIN_PX := 24.0
const PERFORMANCE_SCROLL_HEIGHT_PX := 320.0

const TAB_SKILLS := "skills"
const TAB_PERFORMANCE := "performance"

const SKILL_EFFECT_LABELS := {
	"damage": "攻撃",
	"heal": "HP回復",
	"sp_recover_single_no_self": "SP回復",
	"sp_recover_all_no_self": "全体SP回復",
	"buff_atk_self": "ATK自己強化",
	"buff_next_attack": "次回攻撃強化",
	"counter_stance": "カウンター",
	"guard_redirect": "かばう",
	"guard_boost": "防御強化",
	"party_damage_reduction": "被ダメージ軽減",
}

const SKILL_TARGET_LABELS := {
	"boss": "ボス",
	"ally_chosen": "味方単体",
	"ally_chosen_no_self": "自分以外の味方単体",
	"ally_all": "味方全体",
}

var draft: RBMCreatorDraft
var main: Node

var _party_card_list: HBoxContainer
var _add_button: Button
var _count_label: Label
var _reset_all_button: Button
var _add_candidates_panel: VBoxContainer
var _candidate_buttons: Dictionary = {}  # character_id -> CheckBox
var _pending_party_selection: Array[String] = []

## §12: 現在「選択キャラクター設定」に表示中のキャラクター。空文字列は
## パーティが空である状態のみを表す。
var _selected_character_id: String = ""
var _selected_tab: String = TAB_SKILLS

var _selected_settings_panel: VBoxContainer
var _selected_empty_label: Label
var _selected_header_label: Label
var _tab_row: HBoxContainer
var _skills_tab_button: Button
var _performance_tab_button: Button
var _tab_content: VBoxContainer

## §13相当（旧RBMCreatorStep6PartySkillsから移設）——選択中の1人分のみ
## 保持すればよいため、character_id -> Dictionaryだった旧構造から単純化した。
var _skills_editing := false
var _staged_allowed: Dictionary = {}  # skill_id -> bool

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.anchor_right = 1.0
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.offset_top = CONTENT_TOP_MARGIN_PX
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var header_row := HBoxContainer.new()
	header_row.name = "PartyHeaderRow"
	column.add_child(header_row)
	var header := Label.new()
	header.text = "攻略パーティ"
	header.theme_type_variation = RBMCreatorUiKit.VARIATION_SECTION_LABEL
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)

	## §16: 旧・大きな全幅ボタンから、右上へ寄せたコンパクトな二次操作へ。
	_reset_all_button = Button.new()
	_reset_all_button.name = "ResetAllAllyOverridesButton"
	_reset_all_button.text = "全員を標準に戻す"
	_reset_all_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_reset_all_button.pressed.connect(_on_reset_all_overrides_pressed)
	header_row.add_child(_reset_all_button)

	var card_scroll := ScrollContainer.new()
	card_scroll.name = "PartyCardScroll"
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(card_scroll)
	_party_card_list = HBoxContainer.new()
	_party_card_list.name = "PartyCardList"
	_party_card_list.add_theme_constant_override("separation", 10)
	card_scroll.add_child(_party_card_list)

	var add_row := HBoxContainer.new()
	column.add_child(add_row)
	_add_button = Button.new()
	_add_button.name = "AddCharacterButton"
	_add_button.text = "＋ キャラクターを追加"
	_add_button.pressed.connect(_on_add_button_pressed)
	add_row.add_child(_add_button)
	_count_label = Label.new()
	_count_label.name = "PartyCountLabel"
	add_row.add_child(_count_label)

	_add_candidates_panel = VBoxContainer.new()
	_add_candidates_panel.name = "AddCandidatesPanel"
	_add_candidates_panel.visible = false
	column.add_child(_add_candidates_panel)

	column.add_child(HSeparator.new())

	_selected_settings_panel = VBoxContainer.new()
	_selected_settings_panel.name = "SelectedCharacterSettingsPanel"
	_selected_settings_panel.add_theme_constant_override("separation", 8)
	column.add_child(_selected_settings_panel)

	_selected_empty_label = Label.new()
	_selected_empty_label.name = "SelectedCharacterEmptyLabel"
	_selected_empty_label.text = "攻略パーティにキャラクターがいません。先に攻略パーティを選んでください。"
	_selected_settings_panel.add_child(_selected_empty_label)

	_selected_header_label = Label.new()
	_selected_header_label.name = "SelectedCharacterHeaderLabel"
	_selected_header_label.theme_type_variation = RBMCreatorUiKit.VARIATION_SECTION_LABEL
	_selected_settings_panel.add_child(_selected_header_label)

	_tab_row = HBoxContainer.new()
	_tab_row.name = "SelectedCharacterTabRow"
	_selected_settings_panel.add_child(_tab_row)
	_skills_tab_button = Button.new()
	_skills_tab_button.name = "SkillsTabButton"
	_skills_tab_button.text = "使用可能スキル"
	_skills_tab_button.toggle_mode = true
	_skills_tab_button.pressed.connect(_on_tab_selected.bind(TAB_SKILLS))
	_tab_row.add_child(_skills_tab_button)
	_performance_tab_button = Button.new()
	_performance_tab_button.name = "PerformanceTabButton"
	_performance_tab_button.text = "性能調整"
	_performance_tab_button.toggle_mode = true
	_performance_tab_button.pressed.connect(_on_tab_selected.bind(TAB_PERFORMANCE))
	_tab_row.add_child(_performance_tab_button)

	var tab_scroll := ScrollContainer.new()
	tab_scroll.name = "SelectedCharacterTabScroll"
	tab_scroll.custom_minimum_size = Vector2(0.0, PERFORMANCE_SCROLL_HEIGHT_PX)
	tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_settings_panel.add_child(tab_scroll)
	_tab_content = VBoxContainer.new()
	_tab_content.name = "SelectedCharacterTabContent"
	_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.add_child(_tab_content)

# ---------------------------------------------------------------------------
# パーティ追加/削除（既存API、無改修）
# ---------------------------------------------------------------------------

## 既存プログラム的API（テスト/呼び出し元向け）——「外す」/候補ボタン、
## いずれから呼ばれても同じ経路。add_party_character()/remove_party_character()
## 自体の重複禁止・上限判定は無改修。
func toggle_character(character_id: String) -> void:
	if draft.party_character_ids.has(character_id):
		draft.remove_party_character(character_id)
	else:
		draft.add_party_character(character_id)
	refresh()
	main.on_party_changed()

func _on_add_button_pressed() -> void:
	_pending_party_selection.assign(draft.party_character_ids)
	_add_candidates_panel.visible = true
	_rebuild_add_candidates()

func _on_candidate_toggled(pressed: bool, character_id: String) -> void:
	if pressed:
		if _pending_party_selection.size() >= RBMDefinitionLoader.MAX_PARTY_SIZE:
			var checkbox := _candidate_buttons.get(character_id) as CheckBox
			if checkbox != null:
				checkbox.set_pressed_no_signal(false)
			return
		if not _pending_party_selection.has(character_id):
			_pending_party_selection.append(character_id)
	else:
		_pending_party_selection.erase(character_id)
	_refresh_candidate_availability()

func _on_confirm_candidates_pressed() -> void:
	for character_id in _pending_party_selection:
		if not draft.party_character_ids.has(character_id):
			draft.add_party_character(character_id)
	_pending_party_selection.clear()
	_add_candidates_panel.visible = false
	main.on_party_changed()
	refresh()

func _on_cancel_candidates_pressed() -> void:
	_pending_party_selection.clear()
	_add_candidates_panel.visible = false

func _on_remove_pressed(character_id: String) -> void:
	toggle_character(character_id)

# ---------------------------------------------------------------------------
# キャラクター選択（§12/§14）
# ---------------------------------------------------------------------------

func select_character(character_id: String) -> void:
	if _selected_character_id == character_id:
		return
	_selected_character_id = character_id
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

func _on_reset_all_overrides_pressed() -> void:
	draft.reset_all_ally_overrides()
	refresh()

func _on_tab_selected(tab: String) -> void:
	_selected_tab = tab
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

# ---------------------------------------------------------------------------
# refresh — パーティカード列
# ---------------------------------------------------------------------------

func refresh() -> void:
	if not draft.party_character_ids.has(_selected_character_id):
		_selected_character_id = draft.party_character_ids[0] if not draft.party_character_ids.is_empty() else ""
		_skills_editing = false
		_staged_allowed.clear()

	# queue_free()だけだと実際のツリー離脱は次のアイドルフレームまで遅延する
	# ため、同一フレーム内で「まだ残っている旧ノードと同じname」を持つ新規
	# ノードをadd_child()すると、Godotが名前衝突を検知して新ノードを
	# 自動リネームしてしまう——remove_child()でツリーから即座に切り離して
	# からqueue_free()することで名前衝突だけを確実に解消する。
	for child in _party_card_list.get_children():
		_party_card_list.remove_child(child)
		child.queue_free()
	for character_id in draft.party_character_ids:
		_build_party_card(character_id)

	var at_cap := draft.party_character_ids.size() >= RBMDefinitionLoader.MAX_PARTY_SIZE
	_add_button.disabled = at_cap
	_count_label.text = "%d / %d人" % [draft.party_character_ids.size(), RBMDefinitionLoader.MAX_PARTY_SIZE]
	if _add_candidates_panel.visible:
		_rebuild_add_candidates()

	_reset_all_button.visible = draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED

	_refresh_selected_settings()

func _build_party_card(character_id: String) -> void:
	var master := draft.master_character_def(character_id)
	var card := PanelContainer.new()
	card.name = "PartyCard_%s" % character_id
	_party_card_list.add_child(card)
	var column := VBoxContainer.new()
	card.add_child(column)

	var select_button := Button.new()
	select_button.name = "SelectCharacterButton_%s" % character_id
	select_button.text = str(master.get("display_name", character_id))
	select_button.toggle_mode = true
	select_button.button_pressed = (character_id == _selected_character_id)
	select_button.pressed.connect(select_character.bind(character_id))
	column.add_child(select_button)

	## §15: 既存のCUSTOM/性能・使用可能スキルいずれかがカスタム化されている
	## 場合のみコンパクトに表示する（draft.is_ally_customized()、新しい
	## ゲームデータではなく既存の2状態を都度比較する読み取り専用の判定）。
	if draft.is_ally_customized(character_id):
		var custom_badge := Label.new()
		custom_badge.name = "CustomBadgeLabel_%s" % character_id
		custom_badge.text = "CUSTOM"
		custom_badge.theme_type_variation = RBMCreatorUiKit.VARIATION_SMALL_LABEL
		column.add_child(custom_badge)

	var remove_button := Button.new()
	remove_button.name = "RemoveCharacterButton_%s" % character_id
	remove_button.text = "外す"
	remove_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	remove_button.pressed.connect(_on_remove_pressed.bind(character_id))
	column.add_child(remove_button)

func _rebuild_add_candidates() -> void:
	for child in _add_candidates_panel.get_children():
		_add_candidates_panel.remove_child(child)
		child.queue_free()
	_candidate_buttons.clear()
	var caption := Label.new()
	caption.text = "攻略パーティを選ぶ"
	_add_candidates_panel.add_child(caption)
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		if draft.party_character_ids.has(character_id):
			continue
		var master := draft.master_character_def(character_id)
		var checkbox := CheckBox.new()
		checkbox.name = "AddCandidateButton_%s" % character_id
		checkbox.text = str(master.get("display_name", character_id))
		checkbox.button_pressed = _pending_party_selection.has(character_id)
		checkbox.toggled.connect(_on_candidate_toggled.bind(character_id))
		_add_candidates_panel.add_child(checkbox)
		_candidate_buttons[character_id] = checkbox
	var actions := HBoxContainer.new()
	_add_candidates_panel.add_child(actions)
	var confirm_button := Button.new()
	confirm_button.name = "ConfirmAddCandidatesButton"
	confirm_button.text = "決定"
	confirm_button.pressed.connect(_on_confirm_candidates_pressed)
	actions.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelAddCandidatesButton"
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_cancel_candidates_pressed)
	actions.add_child(cancel_button)
	_refresh_candidate_availability()

func _refresh_candidate_availability() -> void:
	var at_cap := _pending_party_selection.size() >= RBMDefinitionLoader.MAX_PARTY_SIZE
	for character_id in _candidate_buttons:
		var checkbox := _candidate_buttons[character_id] as CheckBox
		checkbox.disabled = at_cap and not checkbox.button_pressed

# ---------------------------------------------------------------------------
# 選択キャラクター設定（§12〜§17）
# ---------------------------------------------------------------------------

func _refresh_selected_settings() -> void:
	var has_selection := not _selected_character_id.is_empty()
	_selected_empty_label.visible = not has_selection
	_selected_header_label.visible = has_selection
	_tab_row.visible = has_selection
	if not has_selection:
		for child in _tab_content.get_children():
			_tab_content.remove_child(child)
			child.queue_free()
		return

	var master := draft.master_character_def(_selected_character_id)
	_selected_header_label.text = str(master.get("display_name", _selected_character_id))
	_skills_tab_button.button_pressed = (_selected_tab == TAB_SKILLS)
	_performance_tab_button.button_pressed = (_selected_tab == TAB_PERFORMANCE)

	for child in _tab_content.get_children():
		_tab_content.remove_child(child)
		child.queue_free()
	if _selected_tab == TAB_SKILLS:
		_build_skills_tab(_selected_character_id, master)
	else:
		_build_performance_tab(_selected_character_id)

# --- 使用可能スキルタブ（旧RBMCreatorStep6PartySkillsから移設） ---------

func _build_skills_tab(character_id: String, master: Dictionary) -> void:
	if _skills_editing:
		_build_skills_edit_panel(character_id, master)
	else:
		_build_skills_normal_panel(character_id, master)

func _build_skills_normal_panel(character_id: String, master: Dictionary) -> void:
	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		var row := HBoxContainer.new()
		_tab_content.add_child(row)
		var label := Label.new()
		label.name = "SkillStatusLabel_%s_%s" % [character_id, skill_id]
		var allowed := draft.is_ally_skill_allowed(character_id, skill_id)
		label.text = "%s   %s" % [str(skill.get("display_name", skill_id)), "使用可" if allowed else "使用不可"]
		row.add_child(label)

	var edit_button := Button.new()
	edit_button.name = "EditPartySkillsButton_%s" % character_id
	edit_button.text = "編集"
	edit_button.pressed.connect(_on_edit_skills_pressed.bind(character_id))
	_tab_content.add_child(edit_button)

func _on_edit_skills_pressed(character_id: String) -> void:
	_skills_editing = true
	var master := draft.master_character_def(character_id)
	var snapshot := {}
	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		snapshot[skill_id] = draft.is_ally_skill_allowed(character_id, skill_id)
	_staged_allowed = snapshot
	refresh()

func _build_skills_edit_panel(character_id: String, master: Dictionary) -> void:
	var bulk_row := HBoxContainer.new()
	_tab_content.add_child(bulk_row)
	var on_button := Button.new()
	on_button.name = "AllOnButton_%s" % character_id
	on_button.text = "すべてON"
	on_button.pressed.connect(_on_staged_all_pressed.bind(true))
	bulk_row.add_child(on_button)
	var off_button := Button.new()
	off_button.name = "AllOffButton_%s" % character_id
	off_button.text = "すべてOFF"
	off_button.pressed.connect(_on_staged_all_pressed.bind(false))
	bulk_row.add_child(off_button)

	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		var row := HBoxContainer.new()
		_tab_content.add_child(row)
		var check := CheckButton.new()
		check.name = "SkillCheck_%s_%s" % [character_id, skill_id]
		check.button_pressed = bool(_staged_allowed.get(skill_id, draft.is_ally_skill_allowed(character_id, skill_id)))
		check.toggled.connect(func(pressed: bool): _on_staged_skill_toggled(skill_id, pressed))
		row.add_child(check)
		var label := Label.new()
		var effect_id := str(skill.get("effect", ""))
		var target_id := str(skill.get("target", ""))
		var target_text := str(SKILL_TARGET_LABELS.get(target_id, target_id)) if not target_id.is_empty() else "-"
		label.text = "%s（%s、対象:%s、SP消費%s）" % [
			str(skill.get("display_name", skill_id)), str(SKILL_EFFECT_LABELS.get(effect_id, effect_id)),
			target_text, str(skill.get("sp_cost", 0)),
		]
		row.add_child(label)

	var confirm_row := HBoxContainer.new()
	_tab_content.add_child(confirm_row)
	var confirm_button := Button.new()
	confirm_button.name = "ConfirmPartySkillsButton_%s" % character_id
	confirm_button.text = "決定"
	confirm_button.pressed.connect(_on_confirm_skills_pressed.bind(character_id))
	confirm_row.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelPartySkillsButton_%s" % character_id
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_cancel_skills_pressed)
	confirm_row.add_child(cancel_button)

func _on_staged_skill_toggled(skill_id: String, pressed: bool) -> void:
	_staged_allowed[skill_id] = pressed

func _on_staged_all_pressed(allowed: bool) -> void:
	var master := draft.master_character_def(_selected_character_id)
	for skill in master.get("skills", []):
		_staged_allowed[str(skill.get("id", ""))] = allowed
	refresh()

func _on_confirm_skills_pressed(character_id: String) -> void:
	for skill_id in _staged_allowed.keys():
		draft.set_ally_skill_allowed(character_id, str(skill_id), bool(_staged_allowed[skill_id]))
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

func _on_cancel_skills_pressed() -> void:
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

## 既存プログラム的API（テスト/呼び出し元向け）——実UIの「編集→決定」フロー
## とは独立して常に即座にドラフトへ反映する、既存の挙動をそのまま維持。
func set_skill_allowed(character_id: String, skill_id: String, allowed: bool) -> void:
	draft.set_ally_skill_allowed(character_id, skill_id, allowed)
	refresh()

func set_all_for_character(character_id: String, allowed: bool) -> void:
	draft.set_all_ally_skills_allowed(character_id, allowed)
	refresh()

# --- 性能調整タブ（旧_populate_character_info()から移設、無改修ロジック） ---

func _build_performance_tab(character_id: String) -> void:
	var master := draft.master_character_def(character_id)
	if master.is_empty():
		return
	var effective := draft.effective_character_def(character_id)
	if draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
		_build_stat_override_editor(character_id, effective)
	else:
		var stats_label := Label.new()
		stats_label.name = "CharacterInfoStatsLabel"
		stats_label.text = "HP：%d\nATK：%d\nSPD：%d" % [
			int(master.get("hp", 0)), int(master.get("atk", 0)), int(master.get("spd", 0)),
		]
		_tab_content.add_child(stats_label)
	var effective_by_id := {}
	for skill_variant in effective.get("skills", []):
		if skill_variant is Dictionary:
			effective_by_id[str((skill_variant as Dictionary).get("id", ""))] = skill_variant
	for skill_variant in master.get("skills", []):
		var master_skill: Dictionary = skill_variant
		var skill_id := str(master_skill.get("id", ""))
		_add_skill_performance_card(character_id, master_skill, effective_by_id.get(skill_id, master_skill))

func _add_skill_performance_card(character_id: String, skill: Dictionary, effective_skill: Dictionary) -> void:
	var skill_id := str(skill.get("id", ""))
	var card := PanelContainer.new()
	card.name = "CharacterSkillCard_%s" % skill_id
	_tab_content.add_child(card)
	var column := VBoxContainer.new()
	card.add_child(column)
	_add_info_label(column, "SkillNameLabel_%s" % skill_id, str(skill.get("display_name", skill_id)))
	var effect := str(skill.get("effect", ""))
	_add_info_label(column, "SkillTypeLabel_%s" % skill_id, "種類：%s" % str(SKILL_EFFECT_LABELS.get(effect, effect)))
	if skill.has("attribute"):
		var attribute_id := str(skill.get("attribute", ""))
		_add_info_label(column, "SkillAttributeLabel_%s" % skill_id, "属性：%s" % str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)))
	if skill.has("target"):
		var target_id := str(skill.get("target", ""))
		_add_info_label(column, "SkillTargetLabel_%s" % skill_id, "対象：%s" % str(SKILL_TARGET_LABELS.get(target_id, target_id)))
	_add_skill_effect_lines(column, draft.effective_character_def(character_id), effective_skill, effect, skill_id)
	if draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
		_add_skill_override_editor(column, character_id, skill, effective_skill)

func _build_stat_override_editor(character_id: String, effective: Dictionary) -> void:
	var caption := Label.new()
	caption.text = "ハードコア ステータス設定"
	_tab_content.add_child(caption)
	var labels := {"hp": "HP", "atk": "ATK", "spd": "SPD", "max_sp": "Max SP"}
	for field in RBMDefinitionLoader.ALLY_STAT_OVERRIDE_FIELDS:
		var row := HBoxContainer.new()
		row.name = "AllyStatOverrideRow_%s_%s" % [character_id, field]
		_tab_content.add_child(row)
		var value_label := Label.new()
		value_label.name = "AllyStatOverrideLabel_%s_%s" % [character_id, field]
		value_label.text = str(labels[field])
		row.add_child(value_label)
		var spin := SpinBox.new()
		spin.name = "AllyStatOverrideSpin_%s_%s" % [character_id, field]
		spin.min_value = 1.0
		spin.max_value = float(RBMDefinitionLoader.ALLY_OVERRIDE_INT_MAX)
		spin.step = 1.0
		spin.value = float(effective[field])
		spin.value_changed.connect(_on_stat_override_changed.bind(character_id, field))
		row.add_child(spin)
	var reset := Button.new()
	reset.name = "ResetAllyStatsButton_%s" % character_id
	reset.text = "キャラクターステータスを標準値へ戻す"
	reset.pressed.connect(_on_reset_character_stats_pressed.bind(character_id))
	_tab_content.add_child(reset)

func _add_skill_override_editor(parent: Control, character_id: String, master_skill: Dictionary, effective_skill: Dictionary) -> void:
	var skill_id := str(master_skill.get("id", ""))
	var labels := {
		"atk_multiplier": "倍率", "heal_amount": "回復量", "sp_amount": "SP回復量",
		"sp_cost": "SP消費", "buff_multiplier": "強化倍率", "duration_turns": "効果時間",
		"new_rate": "防御軽減率", "reduction_rate": "被ダメージ軽減率",
	}
	for field in RBMDefinitionLoader.ally_skill_override_fields(master_skill):
		var row := HBoxContainer.new()
		row.name = "AllySkillOverrideRow_%s_%s_%s" % [character_id, skill_id, field]
		parent.add_child(row)
		var value_label := Label.new()
		value_label.name = "AllySkillOverrideLabel_%s_%s_%s" % [character_id, skill_id, field]
		value_label.text = str(labels[field])
		row.add_child(value_label)
		var spin := SpinBox.new()
		spin.name = "AllySkillOverrideSpin_%s_%s_%s" % [character_id, skill_id, field]
		if ["atk_multiplier", "buff_multiplier"].has(field):
			spin.min_value = 0.0
			spin.max_value = RBMDefinitionLoader.ALLY_OVERRIDE_MULTIPLIER_MAX
			spin.step = 0.01
			spin.allow_greater = false
			spin.value = float(effective_skill[field])
		elif ["new_rate", "reduction_rate"].has(field):
			spin.min_value = 0.0
			spin.max_value = 1.0
			spin.step = 0.01
			spin.allow_greater = false
			spin.value = float(effective_skill[field])
		else:
			spin.min_value = 1.0 if field == "duration_turns" else 0.0
			spin.max_value = float(RBMDefinitionLoader.ALLY_OVERRIDE_INT_MAX)
			spin.step = 1.0
			spin.value = float(effective_skill[field])
		spin.value_changed.connect(_on_skill_override_changed.bind(character_id, skill_id, field))
		row.add_child(spin)
	var reset := Button.new()
	reset.name = "ResetAllySkillButton_%s_%s" % [character_id, skill_id]
	reset.text = "このスキルを標準値へ戻す"
	reset.pressed.connect(_on_reset_skill_pressed.bind(character_id, skill_id))
	parent.add_child(reset)

func _on_stat_override_changed(value: float, character_id: String, field: String) -> void:
	draft.set_ally_stat_override(character_id, field, value)

func _on_skill_override_changed(value: float, character_id: String, skill_id: String, field: String) -> void:
	draft.set_ally_skill_override(character_id, skill_id, field, value)

func _on_reset_character_stats_pressed(character_id: String) -> void:
	draft.reset_ally_character_stats(character_id)
	refresh()

func _on_reset_skill_pressed(character_id: String, skill_id: String) -> void:
	draft.reset_ally_skill(character_id, skill_id)
	refresh()

func _add_skill_effect_lines(parent: Control, master: Dictionary, skill: Dictionary, effect: String, skill_id: String) -> void:
	match effect:
		"damage":
			var base_damage := RBMBattle.compute_damage_amount(float(master.get("atk", 0)), float(skill.get("atk_multiplier", 1.0)), 1.0, 1.0, 1.0)
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "基礎ダメージ：%d" % base_damage)
			_add_info_label(parent, "SkillEffectNoteLabel_%s" % skill_id, "属性補正・一時強化前")
		"heal":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "基本回復量：%d" % int(skill.get("heal_amount", 0)))
			_add_info_label(parent, "SkillEffectNoteLabel_%s" % skill_id, "対象の不足HPまで")
		"sp_recover_single_no_self":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "自分以外の味方単体のSPを%d回復" % int(skill.get("sp_amount", 0)))
		"sp_recover_all_no_self":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "自分以外の味方全体のSPを%d回復" % int(skill.get("sp_amount", 0)))
		"buff_atk_self":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "ATK：%s倍" % str(float(skill.get("buff_multiplier", 1.0))))
			_add_info_label(parent, "SkillDurationLabel_%s" % skill_id, "効果時間：%dターン" % int(skill.get("duration_turns", 1)))
		"buff_next_attack":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "次の攻撃スキル：%s倍" % str(float(skill.get("buff_multiplier", 1.0))))
		"counter_stance":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "攻撃を無効化して反撃（ATK倍率：%s倍）" % str(float(skill.get("atk_multiplier", 1.0))))
		"guard_redirect":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "味方単体への攻撃をかばう")
		"guard_boost":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "防御時の軽減率：%d%%" % int(round(float(skill.get("new_rate", 0.0)) * 100.0)))
			_add_info_label(parent, "SkillDurationLabel_%s" % skill_id, "効果時間：%dターン" % int(skill.get("duration_turns", 1)))
		"party_damage_reduction":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, "パーティの被ダメージ軽減：%d%%" % int(round(float(skill.get("reduction_rate", 0.0)) * 100.0)))
			_add_info_label(parent, "SkillDurationLabel_%s" % skill_id, "効果時間：%dターン" % int(skill.get("duration_turns", 1)))

func _add_info_label(parent: Control, node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func is_step_valid() -> bool:
	return draft.step5_is_valid()

func validation_message() -> String:
	if draft.party_character_ids.is_empty():
		return "パーティを1人以上選んでください"
	return ""
