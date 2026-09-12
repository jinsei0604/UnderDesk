class_name RBMCreatorTestBattleView
extends Control

var _world_battle = preload("res://src/bossmaker/rbm_fullscreen_battle_ui.gd").new()
var battle_background: String = "night"

## Phase 1 Step 4 §8/§9 — TEST BATTLE screen: CREATOR TEST明示（§8-1）、
## Clear Check要素なし（§8-2）、勝敗後「もう一度テスト」「Creatorに戻る」
## （§8-3）、「テストを終了」＋確認ダイアログ（§8-4）、Turn REWIND UI（§9）。
##
## Owns exactly one RBMCreatorTestSession — the ONLY place besides its own
## tests that ever constructs one.
##
## Phase 3.5 Step 4「戦闘UI・情報表示 第一次完成」: 旧来の「常時HP/SP付き
## 単一列レイアウト」から、戦場を主役にした新レイアウト（戦場／行動順＋
## 最新戦闘情報／味方ステータス＋コマンド）へ全面再構成した。実際のControl
## 生成の大半はRBMBattleUiKit（TEST/Clear Check/CHALLENGE 3画面が共有する
## 新設の共通ヘルパー、src/bossmaker/rbm_battle_ui_kit.gd参照）へ委譲し、
## このViewはセッション駆動・REWIND・確認ダイアログ・結果画面のボタン構成
## など「TEST BATTLE固有の責務」だけを保持する（§21）。
##
## 既存の変数名・Control名（_log_label/_party_rows/_command_area/
## _target_picker/AttackButton/DefendButton/SkillButton_%s/_outcome_area/
## _retry_button/_return_button/_rewind_list/_quit_button/_quit_confirm等）
## は、既存の複数テストファイルがこれらへ直接依存しているため、意味を
## 変えないものはすべて維持している——_log_labelは「累積ログ」ではなく
## 新設の「最新戦闘情報」パネルのテキストソースとして再利用する（挙動
## そのもの: 行動のたび更新・start/retryで空になる、は無改修）。

signal return_to_creator_requested

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

var main: Node
var session: RBMCreatorTestSession

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

var _quit_button: Button
var _quit_confirm: HBoxContainer

var _outcome_area: VBoxContainer
var _retry_button: Button
var _return_button: Button

var _rewind_list: VBoxContainer
var _rewind_button_by_turn: Dictionary = {}

## Phase 3.5 Step 4 §10/§18: 累積戦闘ログ履歴（rbm_battle.gd._log_entry()が
## 付与した"turn"タグ付きのentryをそのまま保持する）。start/retry/REWINDの
## たび、RBMBattleUiKitのヘルパーで初期化/切り詰めする——書式化ロジック
## 自体はこのViewで持たない（RBMBattleUiKit.format_log_window_text()参照）。
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
	# Phase 3.5 タイトル画面UI新設 §8/§9/§10: この画面自身のルートへ共通Theme
	# を適用する——RBMGameRoot自体には適用しない（Creatorへ意図せず波及させ
	# ないため）。以後の子孫Controlは既定でこのThemeを継承する。
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

	# Phase 3.5 UI統一§14: TEST BATTLE/Clear Checkは「必要な識別がある場合
	# だけ最小限に」——既存テストが_mode_label.textを直接検証しているため
	# textとNode自体は維持しつつ、見た目の優先度をSectionLabelから
	# SmallLabelへ下げ、戦場（_build_battlefield）へ視覚的な主役を譲る。
	_mode_label = Label.new()
	_mode_label.name = "ModeLabel"
	_mode_label.text = tr("テストバトル")
	_mode_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	column.add_child(_mode_label)

	# §33バグ修正: 勝敗結果（OutcomeArea）は、columnがスクロールしない
	# VBoxContainerであるため、下部（戦場/行動順/党カード/REWIND一覧/
	# 終了ボタン列）が既存の内容だけで画面をほぼ埋め切る戦闘後半では、
	# 最後尾に積むと画面外へ押し出され「勝敗を確認する手段が無い」という
	# 致命的な状態になっていた（実際にheadlessで battle_over=true・
	# _outcome_area.visible=true でも画面上に何も見えないことを確認済み）。
	# 中身（テキスト・ボタンの名前や処理）には一切触れず、構築順だけを
	# 最上部（戦場より前）へ移す——visible=falseが初期値のため通常の
	# 戦闘中は高さ0のまま何も見た目を変えない。
	_outcome_area = VBoxContainer.new()
	_outcome_area.name = "OutcomeArea"
	_se_outcome_played = false
	_outcome_area.visible = false
	column.add_child(_outcome_area)
	# Phase 3.5 UI統一§27: 勝敗結果はRPGの戦闘結果として自然に見えるよう、
	# 通常本文より大きく強調する（TitleLabelほど巨大にはせず、他の見出しと
	# 同じSectionLabelに揃える——過剰な演出は避ける）。
	var outcome_label := Label.new()
	outcome_label.name = "OutcomeLabel"
	outcome_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	_outcome_area.add_child(outcome_label)
	_retry_button = Button.new()
	_retry_button.name = "RetryButton"
	_retry_button.text = tr("もう一度テスト")
	_retry_button.pressed.connect(retry)
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
	column.add_child(arena_row)
	var battle_column := VBoxContainer.new()
	battle_column.name = "BattleColumn"
	battle_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_row.add_child(battle_column)
	_build_battlefield(battle_column)
	_build_info_row(arena_row)
	_log_label = RBMBattleUiKit.build_battle_message(battle_column)
	_build_bottom_row(battle_column)
	_command_area.reparent(arena_row.get_node("InfoRow"))

	var quit_row := HBoxContainer.new()
	column.add_child(quit_row)
	_quit_button = Button.new()
	_quit_button.name = "QuitTestButton"
	_quit_button.text = tr("テストを終了")
	_quit_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_quit_button.pressed.connect(_on_quit_pressed)
	quit_row.add_child(_quit_button)

	_quit_confirm = HBoxContainer.new()
	_quit_confirm.name = "QuitConfirm"
	_quit_confirm.visible = false
	column.add_child(_quit_confirm)
	var quit_confirm_label := Label.new()
	quit_confirm_label.text = tr("テスト戦闘を終了しますか？")
	_quit_confirm.add_child(quit_confirm_label)
	var cancel_button := Button.new()
	cancel_button.name = "QuitCancelButton"
	cancel_button.text = tr("キャンセル")
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(func(): _quit_confirm.visible = false)
	_quit_confirm.add_child(cancel_button)
	var confirm_quit_button := Button.new()
	confirm_quit_button.name = "QuitConfirmButton"
	confirm_quit_button.text = tr("終了する")
	confirm_quit_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	confirm_quit_button.pressed.connect(_on_quit_confirmed)
	_quit_confirm.add_child(confirm_quit_button)

	_ally_detail_overlay = RBMBattleUiKit.build_detail_overlay(self, "AllyDetail")
	_boss_detail_overlay = RBMBattleUiKit.build_detail_overlay(self, "BossDetail")
	_build_log_window()

# ---------------------------------------------------------------------------
# §1/§2: 戦場（大部分の面積、ボスのクリック対象のみ配置。HP等は常設しない）
# ---------------------------------------------------------------------------

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

	# §2/§5: 戦場上のボス表示——クリックで詳細ウィンドウを開く（味方カードと
	# 同じgui_input方式、name/text自体は既存テストが直接参照する"_boss_label"
	# のまま維持する）。§2: HP/HPバーはここへ常設しない（詳細ウィンドウでのみ
	# 確認する）。
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

# ---------------------------------------------------------------------------
# §7/§9: 行動順 + 最新戦闘情報
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# §10: LOGウィンドウ（累積ログ、スクロール可能）
# ---------------------------------------------------------------------------

func _build_log_window() -> void:
	_log_window_overlay = RBMBattleUiKit.build_detail_overlay(self, "LogWindow")
	(_log_window_overlay["title_label"] as Label).text = tr("戦闘ログ")
	var scroll := ScrollContainer.new()
	scroll.name = "LogWindowScroll"
	RBMBattleUiKit.fit_log_window(_log_window_overlay, scroll)
	# Phase 3.5 タイトル画面UI新設: 横スクロールを禁止し、ScrollContainer自身の
	# 幅をLabelへそのまま与える——これが無いと折り返し対象の幅が定まらず、
	# 実スクリーンショットで確認したとおり1文字ごとに改行される（AUTOWRAP_WORD
	# 自体は無改修）。
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

# ---------------------------------------------------------------------------
# §4/§5: 味方/ボス詳細ウィンドウ
# ---------------------------------------------------------------------------

func open_ally_detail(unit_id: int) -> void:
	if _is_presenting():
		return
	var unit := _unit_by_id(unit_id)
	if unit == null:
		return
	(_ally_detail_overlay["title_label"] as Label).text = tr(unit.display_name)
	RBMBattleUiKit.refresh_ally_detail_content(_ally_detail_overlay["content"], unit, session.battle)
	(_ally_detail_overlay["overlay"] as Control).visible = true

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
# lifecycle
# ---------------------------------------------------------------------------

## §12: always goes through RBMDefinitionLoader (via RBMCreatorTestSession's
## own constructor) — never a shortcut. Returns the same
## {"ok":bool,"errors":Array} shape RBMCreatorTestSession.start_errors() would
## report, so a caller can show a readable reason without ever needing to
## start a battle to find out it would have failed.
func start(definition: Dictionary, rng_seed: int = -1) -> bool:
	_cancel_presentation()
	if main != null:
		var creator_draft: RBMCreatorDraft = main.get("draft") as RBMCreatorDraft
		if creator_draft != null:
			_boss_appearance_id = creator_draft.appearance_id
	session = RBMCreatorTestSession.new(definition, rng_seed)
	# Phase 3.5 Step 3 §4/Step 4 §19: 新しい戦闘セッション開始時は前セッション
	# の表示情報（最新戦闘情報・累積ログ）を一切持ち越さない。
	_log_label.text = ""
	_battle_log_history.clear()
	_close_target_picker()
	_close_all_overlays()
	_quit_confirm.visible = false
	_se_outcome_played = false
	_outcome_area.visible = false
	if session.start_ok():
		refresh()
		_present_session_opening()
	return session.start_ok()

func retry() -> void:
	_cancel_presentation()
	session.restart()
	_log_label.text = ""
	_battle_log_history.clear()
	_close_target_picker()
	_close_all_overlays()
	_se_outcome_played = false
	_outcome_area.visible = false
	refresh()
	_present_session_opening()

func _on_return_pressed() -> void:
	_cancel_presentation()
	return_to_creator_requested.emit()

func _on_quit_pressed() -> void:
	_quit_confirm.visible = true

func _on_quit_confirmed() -> void:
	_cancel_presentation()
	_quit_confirm.visible = false
	return_to_creator_requested.emit()

# ---------------------------------------------------------------------------
# commands (実機プレイ改善①: 「予約」ではなく即座に解決する)
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

## §15: スキルボタンを押した瞬間の挙動そのものは無改修（対象が要るなら
## _open_target_picker()、不要ならすぐ解決）——変わったのは「スキル」ボタンを
## 経由してこの一覧へ到達する導線だけ。
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

## §15: 「スキル」ボタン — メインコマンド行を隠し、スキル一覧を表示する。
func _open_skill_list() -> void:
	if _is_presenting():
		return
	_main_command_row.visible = false
	_skill_list_panel.visible = true

## §15: 「← 戻る」— スキル一覧を閉じ、メインコマンド行へ戻る。
func _close_skill_list() -> void:
	_skill_list_panel.visible = false
	_main_command_row.visible = true

## Phase 3.5 Step 3 §2: 「選択不可能な対象をターゲット候補から除外する」——
## RBMBattle.is_valid_skill_target()（Battle側の対象判定そのもの、ここでは
## 一切再実装しない）を候補フィルタとして使う。
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

## §17: 「キャンセル時は自然にスキル選択へ戻れるようにしてください」——対象
## 選択は必ずスキル一覧経由でしか到達しないため（通常攻撃/防御は対象を
## 要らない）、対象選択の「← 戻る」はメインコマンド行ではなくスキル一覧へ
## 戻す。
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
## その場で反映してから次の行動者へ進む。session.resolve_ally_action()自身が
## そのすぐ後のボスの番（あれば）や指定行動も一緒に自動で解決してくれるため、
## ここでは戻り値のログを表示してrefresh()するだけでよい。
func _resolve_and_refresh(action: Dictionary) -> void:
	if _is_presenting():
		return
	if session == null or session.battle == null or session.battle.battle_over:
		return
	var before := session.battle.presentation_state()
	var log := session.resolve_ally_action(action)
	_present_batch(log, before)

func _render_log(log: Array) -> void:
	_log_label.text = RBMBattleUiKit.format_latest_info(log, session.battle)
	for entry in log:
		_battle_log_history.append(entry)

# ---------------------------------------------------------------------------
# REWIND (§9/§18)
# ---------------------------------------------------------------------------

func rewind_to(turn: int) -> void:
	_cancel_presentation()
	if not session.rewind_to(turn):
		refresh()
		return
	# §18: 巻き戻した未来側の最新戦闘情報/累積ログを両方とも除去する。
	preload("res://src/bossmaker/rbm_audio.gd").cue(self, "rewind")
	_log_label.text = ""
	_battle_log_history = RBMBattleUiKit.history_truncated_for_rewind(_battle_log_history, turn)
	_close_target_picker()
	_close_all_overlays()
	_se_outcome_played = false
	_outcome_area.visible = false
	refresh()
	_present_session_opening()

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
		preload("res://src/bossmaker/rbm_audio.gd").cue(self, "victory" if battle.winner == "ally" else "defeat")
		_se_outcome_played = true
	elif not battle.battle_over:
		_se_outcome_played = false
	_outcome_area.visible = battle.battle_over
	if battle.battle_over:
		var outcome_label: Label = _outcome_area.get_node("OutcomeLabel")
		outcome_label.text = tr("勝利") if battle.winner == "ally" else tr("敗北")

## §14/§15: 現在SPD順で入力待ちの味方1人だけのコマンドを表示する
## （通常攻撃／スキル／防御の3ボタン。スキル一覧は_skill_list_panelへ分離）。
## _main_command_row/_skill_list_panelは_build_bottom_row()で一度だけ生成した
## 永続コンテナ（毎refresh()で作り直さない）——旧コード（現Clear Check/
## CHALLENGE、無改修）は"CommandRow_%d"の外枠ごと毎回作り直していたため
## 気づかれなかった2つの問題（①queue_free()単体だと次フレームまで実削除
## されず、同一フレーム内でrefresh()が2回呼ばれた場合に新しいボタン
## （"AttackButton"等、固定名）が旧・削除待ちの同名ボタンと衝突しGodotが
## 新しい方を自動リネームする ②逆にfree()単体だと、まさにそのボタンの
## pressed信号ハンドラの中からそのボタン自身を含む親を再構築しようとして
## "Attempted to free a locked object"実行時エラーになる）を、
## RBMBattleUiKit.clear_children_safely()（remove_child()+queue_free()の
## 組み合わせ）が両方まとめて解決する。
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

## §15/§16: 「← 戻る」+ スキル名/必要SP行 + フォーカス中のスキル詳細。
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
		# Phase 3.5 Step 3 §1: SP不足でも押せてしまい、Battle側で
		# insufficient_sp判定を受けるまでボタン自体は選択可能だった問題の
		# 修正——判定条件はRBMBattleUiKit.skill_is_disabled()へ一本化。
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

## §16: 現在のマスターデータに実在する情報だけを表示する（推測・捏造しない）。
func _show_skill_detail(skill: Dictionary) -> void:
	if _skill_detail_label == null:
		return
	var display_name := tr(str(skill.get("display_name", skill.get("id", ""))))
	var lines: Array[String] = [display_name]
	lines.append_array(RBMBattleUiKit.skill_detail_lines(skill, true))
	_skill_detail_label.text = "\n".join(lines)

func _refresh_rewind_list() -> void:
	RBMBattleUiKit.clear_children_safely(_rewind_list)
	_rewind_button_by_turn.clear()
	for turn in session.reachable_turns():
		var button := Button.new()
		button.name = "RewindTurnButton_%d" % turn
		button.text = tr("ターン%d へ REWIND") % turn
		button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		button.pressed.connect(rewind_to.bind(turn))
		_rewind_list.add_child(button)
		_rewind_button_by_turn[turn] = button


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
