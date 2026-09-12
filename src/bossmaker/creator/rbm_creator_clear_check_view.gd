class_name RBMCreatorClearCheckView
extends Control

var _world_battle = preload("res://src/bossmaker/rbm_fullscreen_battle_ui.gd").new()
var battle_background: String = "night"

## Phase 1 Step 5 — Clear Check: confirms the author can actually beat the
## boss they built (§1), then hosts a real battle using RBMCreatorTestSession
## (§24: Step 4's snapshot()/restore()-based REWIND primitive, reused
## unmodified — this view is the only thing that differs from TEST BATTLE;
## the underlying battle session/REWIND mechanism itself needed zero changes).
##
## §2/§13: never re-implements the win condition. The ONLY place this class
## ever decides "did Clear Check succeed" is _check_clear_check_success(),
## which reads session.battle.winner == "ally" — the exact same field
## RBMCreatorTestBattleView already reads for its own 勝利/敗北 label.
##
## Phase 3.5 Step 4「戦闘UI・情報表示 第一次完成」: RBMCreatorTestBattleViewと
## 完全に同じ新レイアウト・同じRBMBattleUiKit活用方針を、この画面の戦闘部分
## （_battle_panel）へ適用した。confirm画面（§5、変更対象外）はそのまま無
## 改修。Clear Check固有の責務（confirm画面・_check_clear_check_success()・
## 「最初からやり直す」の確認ダイアログ・成功/失敗の出し分け）だけをこの
## Viewが引き続き持ち、それ以外（戦場/行動順/最新情報/累積ログ/味方・ボス
## 詳細/スキル一覧+詳細/対象選択）はRBMBattleUiKitへ委譲する——このファイル
## のヘッダコメントが元々明示していた「意図的な複製」方針は、TEST BATTLEと
## Clear Checkの間でも変わらず維持している。

signal return_to_creator_requested

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

var main: Node
var draft: RBMCreatorDraft
var session: RBMCreatorTestSession

# --- confirmation screen (§5, 無改修) ---
var _confirm_panel: VBoxContainer
var _confirm_boss_name_label: Label
var _confirm_random_notice_label: Label
var _confirm_error_label: Label

# --- battle screen ---
var _battle_panel: VBoxContainer
var _mode_label: Label
var _battlefield: Control
var _battlefield_ally_row: Control
## Tests may explicitly disable presentation; GPU windows enable it by default.
var presentation_enabled: bool = DisplayServer.get_name() != "headless"
var _presenter: RBMBattlePresenter
var _boss_appearance_id: String = ""
var _boss_label: Label
var _party_rows: HBoxContainer
var _turn_order_panel: Control
var _log_label: Label
var _command_area: VBoxContainer
var _main_command_row: VBoxContainer
var _skill_list_panel: VBoxContainer
var _skill_detail_label: Label
var _target_picker: VBoxContainer
var _target_picker_unit_id: int = -1
var _target_picker_skill_id: String = ""

var _restart_button: Button
var _restart_confirm: HBoxContainer
var _quit_button: Button

var _outcome_area: VBoxContainer
var _outcome_label: Label
var _retry_button: Button
var _return_button: Button

var _rewind_list: VBoxContainer

var _battle_log_history: Array[Dictionary] = []
var _log_window_overlay: Dictionary = {}
var _log_window_body_label: Label

var _ally_detail_overlay: Dictionary = {}
var _boss_detail_overlay: Dictionary = {}

func setup(p_main: Node) -> void:
	main = p_main
	_build_ui()
	_world_battle.setup(self)
	visibility_changed.connect(_on_presentation_visibility_changed)

func _build_ui() -> void:
	# Phase 3.5 タイトル画面UI新設 §8/§9/§10: RBMCreatorTestBattleViewと同じ
	# 理由で、この画面自身のルートへ共通Themeを適用する。
	theme = RBMUiTheme.build_theme()
	RBMBattleUiKit.add_root_background(self)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.anchor_right = 1.0
	column.anchor_bottom = 1.0
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.offset_top = CONTENT_TOP_MARGIN_PX
	column.offset_bottom = -20.0
	add_child(column)

	_build_confirm_panel(column)
	_build_battle_panel(column)

# ---------------------------------------------------------------------------
# confirmation screen (§5、無改修)
# ---------------------------------------------------------------------------

func _build_confirm_panel(parent: Control) -> void:
	_confirm_panel = VBoxContainer.new()
	_confirm_panel.name = "ClearCheckConfirmPanel"
	parent.add_child(_confirm_panel)

	var title := Label.new()
	title.name = "ConfirmTitleLabel"
	title.text = tr("クリアチェック")
	title.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	_confirm_panel.add_child(title)

	_confirm_boss_name_label = Label.new()
	_confirm_boss_name_label.name = "ConfirmBossNameLabel"
	_confirm_panel.add_child(_confirm_boss_name_label)

	## §25: ADVANCEDでランダム行動/確率的発動が設定されている場合のみ表示
	## （RBMCreatorDraft.has_random_action_variance()、判定条件はそちらの
	## doc comment参照）。open()のたびdraftから最新の状態を読んで更新する。
	_confirm_random_notice_label = Label.new()
	_confirm_random_notice_label.name = "ConfirmRandomActionNoticeLabel"
	_confirm_random_notice_label.text = tr("このボスにはランダム行動が設定されています。挑戦ごとに行動が変化する場合があります。")
	_confirm_panel.add_child(_confirm_random_notice_label)

	var info1 := Label.new()
	info1.text = tr("この設定で攻略可能か確認します")
	_confirm_panel.add_child(info1)

	var info2 := Label.new()
	info2.text = tr("クリアチェック中はREWINDを使用できます")
	_confirm_panel.add_child(info2)

	_confirm_error_label = Label.new()
	_confirm_error_label.name = "ConfirmErrorLabel"
	_confirm_panel.add_child(_confirm_error_label)

	var button_row := HBoxContainer.new()
	_confirm_panel.add_child(button_row)
	var back_button := Button.new()
	back_button.name = "ConfirmBackButton"
	back_button.text = tr("戻る")
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(_on_confirm_back_pressed)
	button_row.add_child(back_button)
	var start_button := Button.new()
	start_button.name = "ConfirmStartButton"
	start_button.text = tr("開始")
	start_button.pressed.connect(_on_confirm_start_pressed)
	button_row.add_child(start_button)

## §4/§5: called by RBMCreatorMain.press_clear_check() — shows the
## confirmation screen only. No Definition is generated/validated yet (that
## happens on "開始", mirroring §12's TEST開始時validation applied to Clear
## Check) and no battle/session exists yet.
func open(p_draft: RBMCreatorDraft) -> void:
	draft = p_draft
	_confirm_error_label.text = ""
	_confirm_boss_name_label.text = draft.boss_name
	_confirm_random_notice_label.visible = draft.has_random_action_variance()
	_battle_panel.visible = false
	_confirm_panel.visible = true

func _on_confirm_back_pressed() -> void:
	return_to_creator_requested.emit()

func _on_confirm_start_pressed() -> void:
	var result: Dictionary = main.press_clear_check_start()
	if not bool(result.get("ok", false)):
		_confirm_error_label.text = tr("クリアチェックを開始できません（設定を確認してください）")

## §5「開始」: called by RBMCreatorMain.press_clear_check_start() only after
## RBMDefinitionLoader.resolve() has already validated the Definition — never
## a shortcut that skips validation. rng_seed mirrors
## RBMCreatorTestBattleView.start()'s own optional parameter (same default,
## -1 = random) purely for deterministic testability; normal Creator usage
## never passes one.
func start_battle(definition: Dictionary, rng_seed: int = -1) -> void:
	_cancel_presentation()
	if draft != null:
		_boss_appearance_id = draft.appearance_id
	session = RBMCreatorTestSession.new(definition, rng_seed)
	_log_label.text = ""
	_battle_log_history.clear()
	_close_target_picker()
	_close_all_overlays()
	_restart_confirm.visible = false
	_se_outcome_played = false
	_outcome_area.visible = false
	_confirm_panel.visible = false
	_battle_panel.visible = true
	refresh()
	_present_session_opening()
	_check_clear_check_success()

# ---------------------------------------------------------------------------
# battle screen — RBMCreatorTestBattleViewと同じ構造
# ---------------------------------------------------------------------------

func _build_battle_panel(parent: Control) -> void:
	_battle_panel = VBoxContainer.new()
	_battle_panel.name = "ClearCheckBattlePanel"
	parent.add_child(_battle_panel)

	# Phase 3.5 UI統一§14: RBMCreatorTestBattleViewと同じ理由——既存テストが
	# _mode_label.textを直接検証するためtextとNode自体は維持しつつ、見た目
	# の優先度をSectionLabelからSmallLabelへ下げる（このファイルの意図的な
	# 複製方針どおり）。
	_mode_label = Label.new()
	_mode_label.name = "ModeLabel"
	_mode_label.text = tr("クリアチェック")
	_mode_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	_battle_panel.add_child(_mode_label)

	# §33バグ修正: RBMCreatorTestBattleViewと同じ理由・同じ処置（このファイル
	# の意図的な複製方針どおり）——OutcomeAreaを最後尾ではなく最上部
	# （戦場より前）へ構築し、下部の内容がどれだけ多くても勝敗結果が画面外へ
	# 押し出されないようにする。visible=falseが初期値のため通常の戦闘中は
	# 高さ0のまま何も見た目を変えない。
	_outcome_area = VBoxContainer.new()
	_outcome_area.name = "OutcomeArea"
	_se_outcome_played = false
	_outcome_area.visible = false
	_battle_panel.add_child(_outcome_area)
	# Phase 3.5 UI統一§27: RBMCreatorTestBattleViewと同じ理由・同じ処置。
	_outcome_label = Label.new()
	_outcome_label.name = "OutcomeLabel"
	_outcome_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	_outcome_area.add_child(_outcome_label)
	_retry_button = Button.new()
	_retry_button.name = "RetryButton"
	_retry_button.text = tr("もう一度挑戦")
	_retry_button.pressed.connect(_on_retry_pressed)
	_outcome_area.add_child(_retry_button)
	_return_button = Button.new()
	_return_button.name = "ReturnToCreatorButton"
	_return_button.text = tr("Creatorに戻る")
	_return_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_return_button.pressed.connect(_on_return_pressed)
	_outcome_area.add_child(_return_button)

	var arena_row := HBoxContainer.new()
	arena_row.name = "ArenaRow"
	arena_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_panel.add_child(arena_row)
	var battle_column := VBoxContainer.new()
	battle_column.name = "BattleColumn"
	battle_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_row.add_child(battle_column)
	_build_battlefield(battle_column)
	_build_info_row(arena_row)
	_log_label = RBMBattleUiKit.build_battle_message(battle_column)
	_build_bottom_row(battle_column)
	_command_area.reparent(arena_row.get_node("InfoRow"))

	var action_row := HBoxContainer.new()
	_battle_panel.add_child(action_row)
	_restart_button = Button.new()
	_restart_button.name = "RestartButton"
	_restart_button.text = tr("最初からやり直す")
	_restart_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_restart_button.pressed.connect(_on_restart_pressed)
	action_row.add_child(_restart_button)

	_quit_button = Button.new()
	_quit_button.name = "QuitButton"
	_quit_button.text = tr("Creatorに戻る")
	_quit_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_quit_button.pressed.connect(_on_return_pressed)
	action_row.add_child(_quit_button)

	# §9/§10: mid-battle "最初からやり直す" needs its OWN confirmation (unlike
	# the outcome screen's もう一度挑戦, §15, which needs none — the battle is
	# already over there, so there is no in-progress REWIND history to lose).
	_restart_confirm = HBoxContainer.new()
	_restart_confirm.name = "RestartConfirm"
	_restart_confirm.visible = false
	_battle_panel.add_child(_restart_confirm)
	var restart_confirm_label := Label.new()
	restart_confirm_label.text = tr("現在の戦闘履歴は失われます。最初からやり直しますか？")
	_restart_confirm.add_child(restart_confirm_label)
	var restart_cancel_button := Button.new()
	restart_cancel_button.name = "RestartCancelButton"
	restart_cancel_button.text = tr("キャンセル")
	restart_cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	restart_cancel_button.pressed.connect(_on_restart_cancel_pressed)
	_restart_confirm.add_child(restart_cancel_button)
	var restart_confirm_button := Button.new()
	restart_confirm_button.name = "RestartConfirmButton"
	restart_confirm_button.text = tr("やり直す")
	restart_confirm_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	restart_confirm_button.pressed.connect(_on_restart_confirmed)
	_restart_confirm.add_child(restart_confirm_button)

	_ally_detail_overlay = RBMBattleUiKit.build_detail_overlay(self, "AllyDetail")
	_boss_detail_overlay = RBMBattleUiKit.build_detail_overlay(self, "BossDetail")
	_build_log_window()

## Phase 3.5 UI統一§15/§16: RBMChallengeBattleViewと同じ理由・同じ
## RBMBattleUiKit.build_battlefield_stage()呼び出し（このファイルの意図的な
## 複製方針どおり）。
func _build_battlefield(parent: Control) -> void:
	_battlefield = PanelContainer.new()
	_battlefield.name = "Battlefield"
	_battlefield.custom_minimum_size = Vector2(0, 260)
	_battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battlefield.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_battlefield)

	var field_content := VBoxContainer.new()
	field_content.name = "BattlefieldContent"
	field_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battlefield.add_child(field_content)

	_boss_label = Label.new()
	_boss_label.name = "BossLabel"
	_boss_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	_boss_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_boss_label.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			open_boss_detail()
	)

	var stage := RBMBattleUiKit.build_battlefield_stage(field_content, _boss_label)
	_battlefield_ally_row = stage["ally_row"]

func _build_info_row(parent: Control) -> void:
	var row := VBoxContainer.new()
	row.name = "InfoRow"
	row.custom_minimum_size = Vector2(320, 0)
	parent.add_child(row)

	_turn_order_panel = RBMBattleUiKit.build_turn_order_panel()
	row.add_child(_turn_order_panel)


func _build_bottom_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "BottomRow"
	parent.add_child(row)

	var left_column := VBoxContainer.new()
	left_column.name = "LeftBottomColumn"
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_column)

	_party_rows = HBoxContainer.new()
	_party_rows.name = "PartyRows"
	left_column.add_child(_party_rows)

	var log_row := HBoxContainer.new()
	log_row.name = "LogRow"
	left_column.add_child(log_row)
	var log_button := Button.new()
	log_button.name = "LogButton"
	log_button.text = "LOG"
	log_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	log_button.pressed.connect(open_log_window)
	log_row.add_child(log_button)

	_rewind_list = VBoxContainer.new()
	_rewind_list.name = "RewindList"
	var rewind_scroll := ScrollContainer.new()
	rewind_scroll.name = "RewindScroll"
	rewind_scroll.custom_minimum_size = Vector2(240, 43)
	rewind_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewind_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_row.add_child(rewind_scroll)
	_rewind_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewind_scroll.add_child(_rewind_list)

	_command_area = VBoxContainer.new()
	_command_area.name = "CommandArea"
	_command_area.custom_minimum_size = Vector2(220, 0)
	row.add_child(_command_area)

	_main_command_row = VBoxContainer.new()
	_main_command_row.name = "MainCommandRow"
	_command_area.add_child(_main_command_row)

	_skill_list_panel = VBoxContainer.new()
	_skill_list_panel.name = "SkillListPanel"
	_skill_list_panel.visible = false
	# Phase 3.5 UI統一§33バグ修正: RBMBattleUiKit.wrap_skill_list_scroll()参照。
	RBMBattleUiKit.wrap_skill_list_scroll(_command_area, _skill_list_panel)

	_target_picker = VBoxContainer.new()
	_target_picker.name = "TargetPicker"
	_target_picker.visible = false
	_command_area.add_child(_target_picker)

func _build_log_window() -> void:
	_log_window_overlay = RBMBattleUiKit.build_detail_overlay(self, "LogWindow")
	(_log_window_overlay["title_label"] as Label).text = tr("戦闘ログ")
	var scroll := ScrollContainer.new()
	scroll.name = "LogWindowScroll"
	RBMBattleUiKit.fit_log_window(_log_window_overlay, scroll)
	# Phase 3.5 タイトル画面UI新設: RBMCreatorTestBattleViewと同一の理由・
	# 同一の修正（このファイルの意図的な複製方針どおり）。
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	(_log_window_overlay["content"] as Control).add_child(scroll)
	_log_window_body_label = Label.new()
	_log_window_body_label.name = "LogWindowBodyLabel"
	_log_window_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_log_window_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log_window_body_label)

func open_log_window() -> void:
	_log_window_body_label.text = RBMBattleUiKit.format_log_window_text(_battle_log_history, session.battle)
	(_log_window_overlay["overlay"] as Control).visible = true

func open_ally_detail(unit_id: int) -> void:
	if _is_presenting():
		return
	var unit := _unit_by_id(unit_id)
	if unit == null:
		return
	(_ally_detail_overlay["title_label"] as Label).text = tr(unit.display_name)
	RBMBattleUiKit.refresh_ally_detail_content(_ally_detail_overlay["content"], unit, session.battle)
	(_ally_detail_overlay["overlay"] as Control).visible = true

## §5: 作者確認用途——TEST/Clear Checkは常に実値（visibility省略=全項目
## true）を表示する。CHALLENGEだけがdraft.challenge_info_visibilityで
## 一部を伏せる。
func open_boss_detail() -> void:
	if _is_presenting():
		return
	(_boss_detail_overlay["title_label"] as Label).text = session.battle.boss.display_name
	RBMBattleUiKit.refresh_boss_detail_content(_boss_detail_overlay["content"], session.battle)
	(_boss_detail_overlay["overlay"] as Control).visible = true

func _close_all_overlays() -> void:
	(_ally_detail_overlay["overlay"] as Control).visible = false
	(_boss_detail_overlay["overlay"] as Control).visible = false
	(_log_window_overlay["overlay"] as Control).visible = false

# ---------------------------------------------------------------------------
# commands (identical logic to RBMCreatorTestBattleView — see its own
# comments; duplicated rather than shared, per this file's header note)
# ---------------------------------------------------------------------------

func _skill_needs_target(skill: Dictionary) -> bool:
	match str(skill.get("effect", "")):
		"heal":
			return str(skill.get("target", "ally_chosen")) != "ally_all"
		"sp_recover_single_no_self", "guard_redirect":
			return true
		_:
			return false

func act_attack(unit_id: int) -> void:
	_close_target_picker()
	_resolve_and_refresh({"type": "attack"})

func act_defend(unit_id: int) -> void:
	_close_target_picker()
	_resolve_and_refresh({"type": "defend"})

func act_skill(unit_id: int, skill_id: String) -> void:
	if _is_presenting():
		return
	var unit := _unit_by_id(unit_id)
	if unit == null:
		return
	var skill := RBMBattleUiKit.find_skill_on_unit(unit, skill_id)
	if _skill_needs_target(skill):
		_open_target_picker(unit_id, skill_id)
		return
	_close_target_picker()
	_close_skill_list()
	_resolve_and_refresh({"type": "skill", "skill_id": skill_id, "target_id": -1})

func act_skill_with_target(unit_id: int, skill_id: String, target_id: int) -> void:
	_close_target_picker()
	_close_skill_list()
	_resolve_and_refresh({"type": "skill", "skill_id": skill_id, "target_id": target_id})

func _open_skill_list() -> void:
	if _is_presenting():
		return
	_main_command_row.visible = false
	_skill_list_panel.visible = true

func _close_skill_list() -> void:
	_skill_list_panel.visible = false
	_main_command_row.visible = true

## Phase 3.5 Step 3 §2: RBMCreatorTestBattleViewと同一ロジック（このファイルの
## 意図的な複製方針どおり）——RBMBattle.is_valid_skill_target()を候補フィルタ
## として使う。
func _open_target_picker(unit_id: int, skill_id: String) -> void:
	_target_picker_unit_id = unit_id
	_target_picker_skill_id = skill_id
	RBMBattleUiKit.clear_children_safely(_target_picker)
	for unit in session.battle.party:
		if not session.battle.is_valid_skill_target(unit_id, skill_id, unit.id):
			continue
		var button := Button.new()
		button.text = tr(unit.display_name)
		button.pressed.connect(act_skill_with_target.bind(unit_id, skill_id, unit.id))
		_target_picker.add_child(button)
	var back_button := Button.new()
	back_button.name = "TargetPickerBackButton"
	back_button.text = tr("← 戻る")
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(_on_target_picker_back_pressed)
	_target_picker.add_child(back_button)
	_skill_list_panel.visible = false
	_target_picker.visible = true

func _on_target_picker_back_pressed() -> void:
	_close_target_picker()
	if session != null and session.battle != null and session.is_waiting_for_ally_action():
		_skill_list_panel.visible = true

func _close_target_picker() -> void:
	_target_picker.visible = false
	_target_picker_unit_id = -1
	_target_picker_skill_id = ""

func _unit_by_id(unit_id: int) -> RBMUnit:
	return RBMBattleUiKit.unit_by_id(session.battle, unit_id)

## §1/§6: コマンド／対象が確定した「その瞬間」に解決し、HP/SP/状態/ログを
## その場で反映してから次の行動者へ進む。
func _resolve_and_refresh(action: Dictionary) -> void:
	if _is_presenting():
		return
	if session == null or session.battle == null or session.battle.battle_over:
		return
	var before := session.battle.presentation_state()
	var log := session.resolve_ally_action(action)
	_present_batch(log, before)
	_check_clear_check_success()

## §13/§28-2: the ONLY place this whole class decides Clear Check succeeded
## — reads RBMBattle.winner (already set by RBMBattle._check_battle_over(),
## the battle system's own single win-condition implementation) the instant
## an action resolution ends the battle. No independent boss.hp<=0 check
## exists anywhere in this file.
func _check_clear_check_success() -> void:
	if session != null and session.battle != null and session.battle.battle_over and session.battle.winner == "ally":
		draft.record_clear_check_success()

func _render_log(log: Array) -> void:
	_log_label.text = RBMBattleUiKit.format_latest_info(log, session.battle)
	for entry in log:
		_battle_log_history.append(entry)

# ---------------------------------------------------------------------------
# 最初からやり直す (§9/§10) / もう一度挑戦 (§15) — both call session.restart()
# (Step 4's own "new RNG, Turn 1, fresh history" primitive), the only
# difference being whether a confirmation gates the call.
# ---------------------------------------------------------------------------

func _on_restart_pressed() -> void:
	_restart_confirm.visible = true

func _on_restart_cancel_pressed() -> void:
	_restart_confirm.visible = false

func _on_restart_confirmed() -> void:
	_do_restart()

func _on_retry_pressed() -> void:
	_do_restart()

func _do_restart() -> void:
	_cancel_presentation()
	session.restart()
	_log_label.text = ""
	_battle_log_history.clear()
	_close_target_picker()
	_close_all_overlays()
	_se_outcome_played = false
	_outcome_area.visible = false
	_restart_confirm.visible = false
	refresh()
	_present_session_opening()
	_check_clear_check_success()

# ---------------------------------------------------------------------------
# Creatorに戻る (§11/§14/§15) — Draft (including any past Clear Check
# success record) is never touched here; simply not calling
# record_clear_check_success() is what preserves it (§16/§17).
# ---------------------------------------------------------------------------

func _on_return_pressed() -> void:
	_cancel_presentation()
	return_to_creator_requested.emit()

# ---------------------------------------------------------------------------
# REWIND (§7/§8/§18) — identical to RBMCreatorTestBattleView.
# ---------------------------------------------------------------------------

func rewind_to(turn: int) -> void:
	_cancel_presentation()
	if not session.rewind_to(turn):
		refresh()
		return
	preload("res://src/bossmaker/rbm_audio.gd").cue(self, "rewind")
	_log_label.text = ""
	_battle_log_history = RBMBattleUiKit.history_truncated_for_rewind(_battle_log_history, turn)
	_close_target_picker()
	_close_all_overlays()
	_se_outcome_played = false
	_outcome_area.visible = false
	refresh()
	_present_session_opening()

func _refresh_rewind_list() -> void:
	RBMBattleUiKit.clear_children_safely(_rewind_list)
	for turn in session.reachable_turns():
		var button := Button.new()
		button.name = "RewindTurnButton_%d" % turn
		button.text = tr("ターン%d へ REWIND") % turn
		button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		button.pressed.connect(rewind_to.bind(turn))
		_rewind_list.add_child(button)

# ---------------------------------------------------------------------------
# refresh
# ---------------------------------------------------------------------------

func refresh() -> void:
	_world_battle.update.call_deferred()
	if _is_presenting():
		return
	if session == null or session.battle == null:
		return
	var battle := session.battle
	_boss_label.text = tr("%s　（ターン%d）") % [battle.boss.display_name, battle.current_turn]

	RBMBattleUiKit.clear_children_safely(_party_rows)
	for unit in battle.party:
		_party_rows.add_child(RBMBattleUiKit.build_party_card(unit, open_ally_detail))
	RBMBattleUiKit.refresh_battlefield_ally_row(_battlefield_ally_row, battle, open_ally_detail)
	_configure_presentation()

	RBMBattleUiKit.refresh_turn_order_panel(_turn_order_panel, battle)
	_refresh_command_area()
	_refresh_rewind_list()

	if battle.battle_over and not _se_outcome_played and is_visible_in_tree():
		preload("res://src/bossmaker/rbm_audio.gd").cue(self, "ui_clear_check_success" if battle.winner == "ally" else "defeat")
		_se_outcome_played = true
	elif not battle.battle_over:
		_se_outcome_played = false
	_outcome_area.visible = battle.battle_over
	if battle.battle_over:
		var won := battle.winner == "ally"
		# §14: success screen shows ONLY Creatorに戻る. §15: failure screen
		# shows もう一度挑戦 + Creatorに戻る.
		_outcome_label.text = tr("クリアチェック成功") if won else tr("クリアチェック失敗")
		_retry_button.visible = not won

## 実機プレイ改善①§1/§13/Phase 3.5 Step 4 §14/§15: SPD順で入力待ちの味方
## 1人だけのコマンドを表示する（通常攻撃／スキル／防御の3ボタン。スキル
## 一覧は_skill_list_panelへ分離）。RBMBattleUiKit.clear_children_safely()の
## 採用理由はRBMCreatorTestBattleView._refresh_command_area()と同一
## （remove_child()+queue_free()で名前衝突と"Attempted to free a locked
## object"の両方を回避）。
func _refresh_command_area() -> void:
	RBMBattleUiKit.clear_children_safely(_main_command_row)
	RBMBattleUiKit.clear_children_safely(_skill_list_panel)
	_main_command_row.visible = true
	_skill_list_panel.visible = false
	if session.battle.battle_over or not session.is_waiting_for_ally_action():
		return

	var unit_id := session.pending_ally_id()
	var unit := _unit_by_id(unit_id)
	if unit == null:
		return

	var attack_button := Button.new()
	attack_button.name = "AttackButton"
	attack_button.text = tr("通常攻撃")
	attack_button.pressed.connect(act_attack.bind(unit.id))
	_main_command_row.add_child(attack_button)

	var skill_open_button := Button.new()
	skill_open_button.name = "OpenSkillListButton"
	skill_open_button.text = tr("スキル")
	skill_open_button.disabled = unit.skills.is_empty()
	skill_open_button.pressed.connect(_open_skill_list)
	_main_command_row.add_child(skill_open_button)

	var defend_button := Button.new()
	defend_button.name = "DefendButton"
	defend_button.text = tr("防御")
	defend_button.pressed.connect(act_defend.bind(unit.id))
	_main_command_row.add_child(defend_button)

	_build_skill_list(unit)

func _build_skill_list(unit: RBMUnit) -> void:
	var back_button := Button.new()
	back_button.name = "SkillListBackButton"
	back_button.text = tr("← 戻る")
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(_close_skill_list)
	_skill_list_panel.add_child(back_button)

	for skill in unit.skills:
		var skill_id := str(skill.get("id", ""))
		var skill_button := Button.new()
		skill_button.name = "SkillButton_%s" % skill_id
		# Phase 3.5 Step 3 §1: RBMCreatorTestBattleViewと同一ロジック。
		skill_button.text = RBMBattleUiKit.skill_row_text(skill, unit)
		skill_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill_button.disabled = RBMBattleUiKit.skill_is_disabled(skill, unit)
		skill_button.pressed.connect(act_skill.bind(unit.id, skill_id))
		skill_button.mouse_entered.connect(_show_skill_detail.bind(skill))
		skill_button.focus_entered.connect(_show_skill_detail.bind(skill))
		_skill_list_panel.add_child(skill_button)

	_skill_detail_label = Label.new()
	_skill_detail_label.name = "SkillDetailLabel"
	_skill_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_list_panel.add_child(_skill_detail_label)
	if not unit.skills.is_empty():
		_show_skill_detail(unit.skills[0])

func _show_skill_detail(skill: Dictionary) -> void:
	if _skill_detail_label == null:
		return
	var display_name := tr(str(skill.get("display_name", skill.get("id", ""))))
	var lines: Array[String] = [display_name]
	lines.append_array(RBMBattleUiKit.skill_detail_lines(skill, true))
	_skill_detail_label.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# Shared presentation: simulation stays synchronous; HUD follows motion impacts.
# ---------------------------------------------------------------------------

func set_boss_appearance(appearance_id: String) -> void:
	_boss_appearance_id = appearance_id
	if session != null and session.battle != null and not _is_presenting():
		_configure_presentation()

func _is_presenting() -> bool:
	return is_instance_valid(_presenter) and _presenter.is_playing()

func _configure_presentation() -> void:
	if not is_instance_valid(_battlefield_ally_row):
		return
	if not is_instance_valid(_presenter):
		_presenter = RBMBattlePresenter.new()
		_presenter.name = "BattlePresenter"
		add_child(_presenter)
		_presenter.entry_impact.connect(_on_presentation_impact)
		_presenter.finished.connect(_on_presentation_finished)
	_presenter.enabled = presentation_enabled
	var visual_stage: Node = _battlefield_ally_row.get_meta("visual_stage", null) as Node
	_presenter.setup(visual_stage)
	if is_instance_valid(visual_stage) and visual_stage.has_method("configure"):
		visual_stage.call("configure", session.battle, _boss_appearance_id)
		if not visual_stage.is_connected("ally_clicked", open_ally_detail):
			visual_stage.connect("ally_clicked", open_ally_detail)
		if not visual_stage.is_connected("boss_clicked", open_boss_detail):
			visual_stage.connect("boss_clicked", open_boss_detail)
		if not _is_presenting():
			visual_stage.call("set_state", session.battle.presentation_state())

func _present_batch(log: Array, before: Dictionary) -> void:
	_configure_presentation()
	if not is_instance_valid(_presenter) or not _presenter.can_animate() or log.is_empty():
		_render_log(log)
		refresh()
		return
	_close_all_overlays()
	_set_presentation_input_locked(true)
	_se_outcome_played = false
	_outcome_area.visible = false
	RBMBattlePresenter.apply_status_snapshot(self, before)
	_presenter.play(log, session.battle, before)

func _present_session_opening() -> void:
	_configure_presentation()
	var log := session.take_presentation_log()
	# Existing synchronous/headless UI tests retain the historical empty opening log.
	# Real windows replay every opening or rewind interrupt from its pre-action state.
	if not log.is_empty() and is_instance_valid(_presenter) and _presenter.can_animate():
		_present_batch(log, session.presentation_initial_state)

func _on_presentation_impact(entry: Dictionary) -> void:
	RBMBattlePresenter.apply_status_snapshot(self, entry.get("visual_state", {}))
	_battle_log_history.append(entry)
	# Do not replace a meaningful last action with a following boss no-op.
	if str(entry.get("action", "none")) != "none" or _log_label.text.is_empty():
		_log_label.text = RBMBattleUiKit.format_latest_info([entry], session.battle)
	if is_instance_valid(_log_window_body_label):
		_log_window_body_label.text = RBMBattleUiKit.format_log_window_text(_battle_log_history, session.battle)

func _on_presentation_finished() -> void:
	_set_presentation_input_locked(false)
	refresh()

func _cancel_presentation() -> void:
	if is_instance_valid(_presenter):
		_presenter.cancel()
	_set_presentation_input_locked(false)

func _set_presentation_input_locked(locked: bool) -> void:
	if not is_instance_valid(_command_area):
		return
	# Preserve container geometry while a sprite is moving; hiding the command
	# column would resize the battlefield and move actors underneath the animation.
	for node in _command_area.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if locked:
			if not button.has_meta("presentation_was_disabled"):
				button.set_meta("presentation_was_disabled", button.disabled)
			button.disabled = true
		elif button.has_meta("presentation_was_disabled"):
			button.disabled = bool(button.get_meta("presentation_was_disabled"))
			button.remove_meta("presentation_was_disabled")

func _on_presentation_visibility_changed() -> void:
	if not is_visible_in_tree():
		_cancel_presentation()
	elif session != null and session.battle != null:
		refresh()

func _exit_tree() -> void:
	_cancel_presentation()

var _se_outcome_played := false
