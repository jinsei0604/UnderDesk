class_name RBMChallengeBattleView
extends Control

var _world_battle = preload("res://src/bossmaker/rbm_fullscreen_battle_ui.gd").new()
var battle_background: String = "night"

## Phase 1 Step 7 §21〜§34 — CHALLENGE戦闘画面。
##
## RBMCreatorClearCheckView（Step 5で確定済み）と非常に近い構造だが意図的に
## 別クラスとして実装している。
##
## ClearCheckViewとの主な違い:
## - REWINDが一切存在しない（§24）。戦闘セッションはRBMChallengeSessionを
##   使う（REWIND履歴を一切持たない）。
## - 勝利時にdraft.record_clear_check_success()を一切呼ばない（§25）。
## - 「挑戦をやめる」という独自の確認付き途中退出がある（§29）。
## - 勝利・敗北どちらの結果画面も「もう一度挑戦」を表示する（§32/§33）。
## - §30: 勝敗判定はRBMBattle.battle_over/winnerのみを読む。
##
## Phase 3.5 Step 4「戦闘UI・情報表示 第一次完成」: RBMCreatorTestBattleView/
## RBMCreatorClearCheckViewと同じ新レイアウト・同じRBMBattleUiKit活用方針を
## この画面にも適用した。CHALLENGE固有の追加要素は2点のみ:
## ①REWINDボタン・履歴一覧を一切持たない（§18/§24、既存仕様のまま無改修）。
## ②ボス詳細ウィンドウが、draft.challenge_info_visibility（Creator側の
##   公開/非公開設定、§5）に応じて非公開項目を「？？？」で伏せる——これが
##   新設の唯一の実質的な差分（visibility: Dictionaryを新規に受け取り、
##   RBMBattleUiKit.refresh_boss_detail_content()へそのまま渡すだけ）。

signal returned_to_list

## CHALLENGE UI再設計 §4-F/§10: 「クリア者数」記録用の一回性シグナル。
## RBMBattle/RBMChallengeSession自身には一切手を入れず（§22）、この画面が
## 既に持つrefresh()の勝敗判定（battle.winner=="ally"）を横から観測するだけ
## ——実際の記録（stage_statsサイドカーへの書き込み）はRBMChallengeEntry
## （stage_idを知っている側）が行う。
signal challenge_won

## 1戦闘（start_battle〜battle_over）につき最大1回だけchallenge_wonを発火する
## ための一回性ガード。start_battle()/_do_restart()の両方でfalseへ戻す
## ——「もう一度挑戦」「最初からやり直す」は新しい1戦闘として扱う。
var _outcome_recorded: bool = false

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

var session: RBMChallengeSession

## §5/§18: ボス詳細ウィンドウの公開/非公開設定。start_battle()の呼び出し元
## （RBMChallengeEntry._on_challenge_requested()）が、確認画面が既に読み込み
## 済みのdraft.challenge_info_visibilityをそのまま渡す——このView自身は
## draftを保持しない（既存方針どおり、definitionのみで完結する）。
var _visibility: Dictionary = RBMBattleUiKit.ALL_VISIBLE

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
var _quit_confirm: HBoxContainer

var _outcome_area: VBoxContainer
var _outcome_label: Label
var _retry_button: Button
var _return_button: Button

var _battle_log_history: Array[Dictionary] = []
var _log_window_overlay: Dictionary = {}
var _log_window_body_label: Label

var _ally_detail_overlay: Dictionary = {}
var _boss_detail_overlay: Dictionary = {}

func _ready() -> void:
	_build_ui()
	_world_battle.setup(self)
	visibility_changed.connect(_on_presentation_visibility_changed)

func _build_ui() -> void:
	# Phase 3.5 タイトル画面UI新設 §8/§9/§10: RBMCreatorTestBattleView/
	# RBMCreatorClearCheckViewと同じ理由で、この画面自身のルートへ共通Theme
	# を適用する。
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

	# Phase 3.5 UI統一§14: 「挑戦バトル」という大きなモード見出しは削除する
	# ——CHALLENGEから入ったことはプレイヤーが既に理解しているため。空いた
	# 分は戦場（_build_battlefield）へ充てる。TEST/Clear Checkは既存テストが
	# _mode_label.textを直接検証するため、そちらでは最小限の識別として残す
	# （RBMCreatorTestBattleView/RBMCreatorClearCheckView参照）。

	# §33バグ修正: RBMCreatorTestBattleView/RBMCreatorClearCheckViewと同じ
	# 理由・同じ処置（このファイルの意図的な複製方針どおり）——OutcomeArea
	# を最後尾ではなく最上部（戦場より前）へ構築し、下部の内容がどれだけ
	# 多くても勝敗結果が画面外へ押し出されないようにする。visible=falseが
	# 初期値のため通常の戦闘中は高さ0のまま何も見た目を変えない。
	_outcome_area = VBoxContainer.new()
	_outcome_area.name = "OutcomeArea"
	_se_outcome_played = false
	_outcome_area.visible = false
	column.add_child(_outcome_area)
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
	_return_button.name = "ReturnToListButton"
	# 実機プレイ改善③ item8/11: "CHALLENGE一覧へ"混在表記を統一して日本語化。
	_return_button.text = tr("挑戦一覧へ")
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

	var action_row := HBoxContainer.new()
	column.add_child(action_row)
	_restart_button = Button.new()
	_restart_button.name = "RestartButton"
	_restart_button.text = tr("最初からやり直す")
	_restart_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_restart_button.pressed.connect(_on_restart_pressed)
	action_row.add_child(_restart_button)

	_quit_button = Button.new()
	_quit_button.name = "QuitChallengeButton"
	_quit_button.text = tr("挑戦をやめる")
	_quit_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_quit_button.pressed.connect(_on_quit_pressed)
	action_row.add_child(_quit_button)

	# §27/§28: 「最初からやり直す」は途中放棄になるため確認が必要
	# （ClearCheckViewの同名ボタンと同じ理由・同じ構造）。
	_restart_confirm = HBoxContainer.new()
	_restart_confirm.name = "RestartConfirm"
	_restart_confirm.visible = false
	column.add_child(_restart_confirm)
	var restart_confirm_label := Label.new()
	restart_confirm_label.text = tr("最初からやり直しますか？")
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

	# §29: 途中退出も確認が必要。勝ちにも負けにも記録されない。
	_quit_confirm = HBoxContainer.new()
	_quit_confirm.name = "QuitConfirm"
	_quit_confirm.visible = false
	column.add_child(_quit_confirm)
	var quit_confirm_label := Label.new()
	quit_confirm_label.text = tr("挑戦を終了しますか？")
	_quit_confirm.add_child(quit_confirm_label)
	var quit_cancel_button := Button.new()
	quit_cancel_button.name = "QuitCancelButton"
	quit_cancel_button.text = tr("キャンセル")
	quit_cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	quit_cancel_button.pressed.connect(_on_quit_cancel_pressed)
	_quit_confirm.add_child(quit_cancel_button)
	var quit_confirm_button := Button.new()
	quit_confirm_button.name = "QuitConfirmButton"
	quit_confirm_button.text = tr("終了する")
	quit_confirm_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	quit_confirm_button.pressed.connect(_on_quit_confirmed)
	_quit_confirm.add_child(quit_confirm_button)

	_ally_detail_overlay = RBMBattleUiKit.build_detail_overlay(self, "AllyDetail")
	_boss_detail_overlay = RBMBattleUiKit.build_detail_overlay(self, "BossDetail")
	_build_log_window()

## Phase 3.5 UI統一§15/§16: 「巨大な無地Panel」ではなく、BOSSを上部中央・
## 味方をその下へ配置した戦場構成へ——RBMBattleUiKit.build_battlefield_stage
## を使う（3戦闘Viewが共有、この関数自体の詳細はそちら参照）。専用背景
## アートはまだ存在しないため今回は追加しない（Panel自身の共有StyleBox
## ——暗い石を思わせるトーン＋控えめな枠——が既にある程度の雰囲気を担う。
## 将来正式な戦闘背景ドット絵に差し替える際は_battlefield自身へ
## TextureRectを1枚追加するだけでよい構造）。
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

	# §18/§24: CHALLENGEにはREWINDが存在しない——TEST/Clear Checkの
	# _rewind_listに相当する要素はこの画面には一切無い。

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

## §5/§18: CHALLENGEでは既存の公開/非公開設定（_visibility、start_battle()
## で受け取る）を必ず尊重する——このウィンドウを追加したことで、これまで
## 非公開だった項目が漏れないようにする。
func open_boss_detail() -> void:
	if _is_presenting():
		return
	(_boss_detail_overlay["title_label"] as Label).text = session.battle.boss.display_name
	RBMBattleUiKit.refresh_boss_detail_content(_boss_detail_overlay["content"], session.battle, _visibility)
	(_boss_detail_overlay["overlay"] as Control).visible = true

func _close_all_overlays() -> void:
	(_ally_detail_overlay["overlay"] as Control).visible = false
	(_boss_detail_overlay["overlay"] as Control).visible = false
	(_log_window_overlay["overlay"] as Control).visible = false

## §22/§23: definitionは呼び出し元がRBMDefinitionLoader.resolve()で既に検証
## 済みのものを渡す（RBMChallengeSession._init()自身もstart_battle()経由で
## 再度resolve()する——CHALLENGEだけが検証をバイパスする経路は存在しない）。
## 乱数seedは常にランダム（挑戦者が固定できる概念はCHALLENGEに存在しない）。
## visibility: §5/§18向けの新規引数——省略時はRBMBattleUiKit.ALL_VISIBLE
## （既存の呼び出し元・既存テストへの後方互換のためのデフォルト、実際の
## 呼び出し元RBMChallengeEntryは常に明示的にdraft.challenge_info_visibility
## を渡す）。
func start_battle(definition: Dictionary, visibility: Dictionary = RBMBattleUiKit.ALL_VISIBLE, appearance_id: String = "") -> void:
	_cancel_presentation()
	_boss_appearance_id = appearance_id
	session = RBMChallengeSession.new(definition)
	_visibility = visibility
	_log_label.text = ""
	_battle_log_history.clear()
	_close_target_picker()
	_close_all_overlays()
	_restart_confirm.visible = false
	_quit_confirm.visible = false
	_se_outcome_played = false
	_outcome_area.visible = false
	_outcome_recorded = false
	refresh()
	_present_session_opening()

# ---------------------------------------------------------------------------
# commands (RBMCreatorClearCheckView/RBMCreatorTestBattleViewと同一ロジック
# ——このファイルのヘッダコメント参照、意図的に複製している)
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

## Phase 3.5 Step 3 §2: RBMCreatorTestBattleView/RBMCreatorClearCheckViewと
## 同一ロジック（このファイルの意図的な複製方針どおり）——
## RBMBattle.is_valid_skill_target()を候補フィルタとして使う。
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

## §25/§30: session.resolve_ally_action()の結果をそのまま読むだけ——CHALLENGE
## の勝利をClear Check成功として記録する処理は一切ない。勝敗の判定
## （_outcome_labelの表示切り替え）はrefresh()がbattle.winnerを読むだけで
## 行い、ここでは独自のboss.hp判定を一切していない。
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
# 最初からやり直す (§27/§28) / もう一度挑戦 (§32/§33/§34) — どちらも
# session.restart()（同じDefinition・新しいseed・Turn 1・初期状態）を呼ぶだけ。
# 違いは確認ダイアログを経由するかどうかのみ。
# ---------------------------------------------------------------------------

func _on_restart_pressed() -> void:
	_restart_confirm.visible = true

func _on_restart_cancel_pressed() -> void:
	_restart_confirm.visible = false

func _on_restart_confirmed() -> void:
	_do_restart()

func _on_retry_pressed() -> void:
	_do_restart()

## Step 8 最終修正 §5/Phase 3.5 Step 4 §19: start_battle()と同じ理由で、
## 再挑戦時もUI層の残存状態（最新戦闘情報・累積ログ・開いたままの対象選択・
## 詳細/LOGウィンドウ）をクリアする。session.restart()自体は無改修。
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
	_outcome_recorded = false
	refresh()
	_present_session_opening()

# ---------------------------------------------------------------------------
# 挑戦をやめる (§29) — 勝敗いずれとしても記録されない、単に一覧へ戻る。
# ---------------------------------------------------------------------------

func _on_quit_pressed() -> void:
	_quit_confirm.visible = true

func _on_quit_cancel_pressed() -> void:
	_quit_confirm.visible = false

func _on_quit_confirmed() -> void:
	_cancel_presentation()
	_quit_confirm.visible = false
	returned_to_list.emit()

func _on_return_pressed() -> void:
	_cancel_presentation()
	returned_to_list.emit()

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

	if battle.battle_over and not _se_outcome_played and is_visible_in_tree():
		preload("res://src/bossmaker/rbm_audio.gd").cue(self, "victory" if battle.winner == "ally" else "defeat")
		_se_outcome_played = true
	elif not battle.battle_over:
		_se_outcome_played = false
	_outcome_area.visible = battle.battle_over
	if battle.battle_over:
		# §30: RBMBattle.winnerのみを読む。独自のboss.hp判定はしない。
		var won := battle.winner == "ally"
		# 実機プレイ改善③ item8: "CLEAR!"/"DEFEAT"を日本語化。
		_outcome_label.text = tr("クリア！") if won else tr("敗北")
		# §32/§33: 勝利・敗北どちらも「もう一度挑戦」を表示する
		# （ClearCheckViewは敗北時のみ——ここが唯一の意図的な違い）。
		_retry_button.visible = true
		# CHALLENGE UI再設計 §4-F/§10: refresh()は決着後も何度も呼ばれうる
		# （ログウィンドウを開閉するだけでも呼ばれる）ため、この戦闘につき
		# 最初に決着した瞬間だけ一回性でchallenge_wonを発火する。
		if not _outcome_recorded:
			_outcome_recorded = true
			if won:
				challenge_won.emit()

## 実機プレイ改善①§1/§13/Phase 3.5 Step 4 §14/§15: RBMCreatorTestBattleView/
## RBMCreatorClearCheckViewと同一ロジック——SPD順で入力待ちの味方1人だけの
## コマンドを表示する。
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

func _open_skill_list() -> void:
	if _is_presenting():
		return
	_main_command_row.visible = false
	_skill_list_panel.visible = true

func _close_skill_list() -> void:
	_skill_list_panel.visible = false
	_main_command_row.visible = true

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
		# Phase 3.5 Step 3 §1: RBMCreatorTestBattleView/RBMCreatorClearCheckView
		# と同一ロジック。
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
