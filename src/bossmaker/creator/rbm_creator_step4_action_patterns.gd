class_name RBMCreatorStep4ActionPatterns
extends Control

## RPG BOSS MAKER — HARDCORE Creator STEP3「行動」画面（2026-10-28 作り直し、ユーザー確定仕様・案A）。
##
## 「通常行動」は戦闘のターン番号ごとの設定表（RBMCreatorDraft.turn_actions）。N ターン目には N 番目の
## 設定を使い、最後の次は1ターン目へ戻る。各ターンの決め方は「確定」「使用率で抽選」「条件で分岐」の
## どれか1つ（条件と使用率は同じターンで組み合わせない）。使用回数の制限は無い。
## 画面は3段: ① 一覧（通常行動のターンのカード・ターン開始/終了時に追加する行動・覚醒、見出しごとに
## 仕切り線） → ② ターンの設定（ターンのカードを押す） → ③ 行動の詳細（行動のカードを押す。性能の編集・
## 削除・条件・使用率はここ）。カードは SIMPLE の通常行動のカードと同じ見た目（テーマの Button の枠）。
## 使用率は「使用率で抽選」の候補だけに出し、確定・条件で決まる行動には出さない（100% も出さない）。
##
## 旧方式（action_sequence、順番に回して飛ばす）の編集画面は廃止した。旧方式のデータはテスト用のため
## 変換しない（ユーザー確定）。戦闘・読み込みは互換のため RBMBattle / RBMDefinitionLoader に残っている。
##
## 画面遷移は「複数のビューを1つの ScrollContent へ並べ、_show_only() で1つだけ見せる」方式のまま。
## 性能のフォーム(_form)と条件の入力欄(_condition_block)は reparent() で詳細画面の差し込み場所へ移して使う。

var draft: RBMCreatorDraft
var main: Node

const WARNING_COLOR := Color(1.0, 0.45, 0.4)
## 使用率のスライダーの最小の大きさ。この画面は左右に80pxずつ余白があり SIMPLE より中央の欄が狭いので、
## 1280×720 でも数値の入力欄と並んで欄に収まる幅にする（幅いっぱいには広がる）。
const PERCENT_SLIDER_MIN_SIZE := Vector2(200.0, 28.0)
## 条件の入力欄の見出しの幅（「キャラクター」が収まる幅）と、数値の欄の最小の大きさ。
const CONDITION_LABEL_WIDTH := 120.0
const CONDITION_SPIN_MIN_SIZE := Vector2(140.0, 0.0)
## ターン開始・終了時に追加する行動のタイミング（SIMPLE の指定行動と同じ値。HARDCORE では
## 「通常行動の代わり」は使わない——それはターンごとの通常行動が受け持つ）。
const EXTRA_TIMINGS := ["turn_start_interrupt", "turn_end_interrupt"]
const EXTRA_TIMING_LABELS := {"turn_start_interrupt": "ターン開始時に追加で使う", "turn_end_interrupt": "ターン終了時に追加で使う"}

## 詳細画面（③）を何のために開いているか。
const CONTEXT_TURN_ENTRY := "turn_entry"  # ターンの候補・条件の行（_entry_index、-1 は追加）
const CONTEXT_TURN_ELSE := "turn_else"    # 条件で分岐の「それ以外」
const CONTEXT_EXTRA := "extra"            # ターン開始・終了時に追加する行動（_entry_index は scripted_actions の位置、-1 は追加）
const CONTEXT_AWAKENING := "awakening"

# ---------------------------------------------------------------------------
# 画面骨格
# ---------------------------------------------------------------------------

var _scroll_container: ScrollContainer
var _scroll_content: VBoxContainer
var _all_views: Array[Control] = []

var _list_view: VBoxContainer
var _turn_view: VBoxContainer
var _add_choice_view: VBoxContainer
var _pick_existing_view: VBoxContainer
var _entry_view: VBoxContainer

# --- ① 一覧 ---
var _turn_list: VBoxContainer
var _turn_loop_note: Label
var _add_turn_button: Button
var _extra_list: VBoxContainer
var _add_extra_button: Button
var _awakening_container: VBoxContainer
var _add_awakening_button: Button

# --- ② ターンの設定 ---
var _turn_title: Label
var _turn_mode_buttons := {}  # mode -> Button
var _turn_entry_list: VBoxContainer
var _turn_total_label: Label
var _add_turn_entry_button: Button
var _equalize_turn_button: Button
var _turn_problem_label: Label
var _turn_delete_button: Button

# --- 追加の方法・既存の行動から選ぶ ---
var _add_choice_title: Label
var _add_choice_pick_existing_button: Button
var _pick_existing_list: VBoxContainer

# --- ③ 行動の詳細 ---
var _entry_title: Label
var _performance_summary_row: HBoxContainer
var _performance_summary_label: Label
var _shared_skill_notice: Label
var _form_slot: MarginContainer
var _condition_slot: MarginContainer
var _weight_block: VBoxContainer
var _weight_slider: HSlider
var _weight_spin: SpinBox
var _extra_block: VBoxContainer
var _extra_turn_spin: SpinBox
var _extra_timing_option: OptionButton
var _else_note: Label
var _entry_error_label: Label
var _entry_actions_row: HBoxContainer
var _entry_confirm_button: Button
var _entry_delete_button: Button
var _syncing_weight := false

# --- 共有: 性能のフォーム ---
var _form: RBMActionEditorForm
## "" | "edit_performance"（③で「性能を編集」を開いている。フォーム自身の保存/キャンセルを使う）
var _form_context: String = ""

# --- 共有: 条件の入力欄（条件で分岐の行・覚醒） ---
var _condition_block: VBoxContainer
var _condition_list: VBoxContainer
var _condition_logic_option: OptionButton
var _add_condition_button: Button
var _condition_editor: VBoxContainer
var _condition_category_option: OptionButton
var _condition_compare_row: HBoxContainer
var _condition_compare_label: Label
var _condition_compare_option: OptionButton
var _condition_percent_row: HBoxContainer
var _condition_percent_spin: SpinBox
var _condition_turn_row: HBoxContainer
var _condition_turn_spin: SpinBox
var _condition_n_row: HBoxContainer
var _condition_n_spin: SpinBox
var _condition_count_row: HBoxContainer
var _condition_count_spin: SpinBox
var _condition_character_row: HBoxContainer
var _condition_character_option: OptionButton
var _condition_error_label: Label
var _pending_conditions: Array = []
var _pending_condition_logic: String = RBMActionPatternRules.DEFAULT_CONDITION_LOGIC
## 条件の入力欄が今まさに編集している条件の位置（-1 は閉じている）。入力は即時にこの条件へ反映する。
var _editing_condition_index: int = -1

# --- 状態 ---
## ② で編集中のターン（保存で初めて draft へ書く）。_turn_index は -1 なら新しいターン。
var _turn_index: int = -1
var _pending_turn: Dictionary = {}
## ②/③ を開いた時点の draft.skills（キャンセルで元へ戻す。途中で作った行動・性能の変更も戻る）。
var _skills_snapshot: Array[Dictionary] = []
var _skills_snapshot_taken := false
## ③ の状態
var _entry_context: String = ""
var _entry_index: int = -1
var _entry_skill_id: String = ""
var _entry_is_new_creation := false
## ③ を「追加」で開いた時、どの追加の方法から来たか（キャンセルで戻る先）。
var _add_target_context: String = ""
## ターンの並べ替えで動かしているカードと、動かし始めた位置。
var _drag_card: PanelContainer = null
var _drag_from := -1
const DRAG_SCROLL_EDGE := 48.0
const DRAG_SCROLL_STEP := 12

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "Step3AdvancedScroll"
	_scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	## 横スクロールは無し(縦のみ)。子は表示幅へ収める(EXPAND_FILL/折り返し)。
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll_container)

	var margin := MarginContainer.new()
	margin.name = "Step3AdvancedScrollMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 0)
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
	_form.type_changed.connect(_on_form_type_changed)
	_condition_block = _build_condition_block()

	_list_view = _build_list_view()
	_turn_view = _build_turn_view()
	_add_choice_view = _build_add_choice_view()
	_pick_existing_view = _build_pick_existing_view()
	_entry_view = _build_entry_view()
	_all_views = [_list_view, _turn_view, _add_choice_view, _pick_existing_view, _entry_view]
	for view in _all_views:
		_scroll_content.add_child(view)
	_form_slot.add_child(_form)
	_condition_slot.add_child(_condition_block)
	_form.visible = false
	_show_only(_list_view)

func _show_only(view: Control) -> void:
	for v in _all_views:
		v.visible = (v == view)
	_scroll_container.scroll_vertical = 0

# ---------------------------------------------------------------------------
# 小さな部品
# ---------------------------------------------------------------------------

func _new_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

## 長い文でも横へはみ出さないよう、幅いっぱいで折り返すラベル。
func _wrap_label(parent: Control, text: String, node_name: String = "") -> Label:
	var label := _new_label(text)
	if not node_name.is_empty():
		label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _hint_label(parent: Control, text: String, node_name: String) -> Label:
	var hint := _wrap_label(parent, text, node_name)
	hint.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	return hint

func _warning_label(parent: Control, node_name: String) -> Label:
	var label := _wrap_label(parent, "", node_name)
	label.add_theme_color_override("font_color", WARNING_COLOR)
	label.visible = false
	return label

func _section_header(parent: Control, text: String, node_name: String) -> Label:
	var header := Label.new()
	header.name = node_name
	header.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	header.text = text
	parent.add_child(header)
	return header

func _button(parent: Control, text: String, node_name: String, on_pressed: Callable, secondary: bool = false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	if secondary:
		b.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b

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

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _character_display_name(character_id: String) -> String:
	var master := RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id]))
	return tr(str(master.get("display_name", character_id)))

func _skill_name(skill_id: String) -> String:
	var skill := draft.find_skill(skill_id)
	return str(skill.get("name", "")) if not skill.is_empty() else tr("（未設定）")

## カード: 全体を押すと on_pressed を呼ぶ（SIMPLE の通常行動のカードと同じ見た目・操作）。
## 中身は返した VBox へ入れ、入れ終わったら _finish_card() で子の入力を止める（押した操作をカードが受ける）。
func _make_card(parent: Control, node_name: String, on_pressed: Callable) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(card)
	_style_card(card, "normal")
	card.mouse_entered.connect(func(): _style_card(card, "hover"))
	card.mouse_exited.connect(func(): _style_card(card, "focus" if card.has_focus() else "normal"))
	card.focus_entered.connect(func(): _style_card(card, "focus"))
	card.focus_exited.connect(func(): _style_card(card, "normal"))
	card.gui_input.connect(_on_card_gui_input.bind(on_pressed))
	var body := VBoxContainer.new()
	body.name = node_name + "Body"
	card.add_child(body)
	return body

func _finish_card(body: Control) -> void:
	var card := body.get_parent() as Control
	for child in card.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

func _style_card(card: PanelContainer, state: String) -> void:
	if not is_instance_valid(card):
		return
	if card == _drag_card:
		state = "hover"  # 動かしている間は浮いた見た目のまま
	card.add_theme_stylebox_override("panel", card.get_theme_stylebox(state if state != "focus" else "hover", "Button"))

func _on_card_gui_input(event: InputEvent, on_pressed: Callable) -> void:
	var mouse := event as InputEventMouseButton
	var released := mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed
	if released or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		on_pressed.call()

## 名前（左）と使用率（右、無ければ出さない）の1行。
func _name_row(parent: Control, text: String, percent_text: String, node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name + "Row"
	parent.add_child(row)
	var name_label := _wrap_label(row, text, node_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not percent_text.is_empty():
		var percent := _new_label(percent_text)
		percent.name = node_name + "Percent"
		percent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(percent)
	return row

func _usage_text(weight: float) -> String:
	return tr("使用率 %.1f%%") % weight

# ---------------------------------------------------------------------------
# ① 一覧（通常行動・ターン開始/終了時に追加する行動・覚醒。見出しごとに仕切り線）
# ---------------------------------------------------------------------------

func _build_list_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "ListView"
	_section_header(view, tr("通常行動"), "NormalActionsHeader")
	_turn_list = VBoxContainer.new()
	_turn_list.name = "TurnList"
	view.add_child(_turn_list)
	_turn_loop_note = _hint_label(view, "", "TurnLoopNote")
	_add_turn_button = _button(view, tr("＋ ターンを追加する"), "AddTurnButton", _on_add_turn_pressed)

	var extra_separator := HSeparator.new()
	extra_separator.name = "ExtraActionsSeparator"
	view.add_child(extra_separator)
	_section_header(view, tr("ターン開始・終了時に追加する行動"), "ExtraActionsHeader")
	_extra_list = VBoxContainer.new()
	_extra_list.name = "ExtraActionList"
	view.add_child(_extra_list)
	_add_extra_button = _button(view, tr("＋ 追加する"), "AddExtraActionButton", _on_add_extra_pressed)

	var awakening_separator := HSeparator.new()
	awakening_separator.name = "AwakeningSeparator"
	view.add_child(awakening_separator)
	_section_header(view, tr("覚醒"), "AwakeningHeader")
	_awakening_container = VBoxContainer.new()
	_awakening_container.name = "AwakeningCard"
	view.add_child(_awakening_container)
	_add_awakening_button = _button(view, tr("＋ 覚醒を追加する"), "AddAwakeningButton", _on_add_awakening_pressed)
	return view

func refresh() -> void:
	_rebuild_turn_list()
	_rebuild_extra_list()
	_rebuild_awakening_card()

func _rebuild_turn_list() -> void:
	_end_turn_drag()
	_clear(_turn_list)
	for i in range(draft.turn_actions.size()):
		var turn: Dictionary = draft.turn_actions[i]
		var card_body := _make_card(_turn_list, "TurnCard_%d" % i, _open_turn.bind(i))
		var row := HBoxContainer.new()
		row.name = "TurnCardRow_%d" % i
		card_body.add_child(row)
		var body := VBoxContainer.new()
		body.name = "TurnCardInfo_%d" % i
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)
		var title := _new_label(tr("%dターン目") % (i + 1))
		title.name = "TurnCardTitle_%d" % i
		title.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
		body.add_child(title)
		_fill_turn_summary(body, turn, "TurnCard_%d" % i)
		var problem := draft.turn_action_problem(turn)
		if not problem.is_empty():
			var warn := _wrap_label(body, problem, "TurnCardProblem_%d" % i)
			warn.add_theme_color_override("font_color", WARNING_COLOR)
		## 並べ替えのつまみ（四方向矢印）。長押ししてから動かすと、挿入型で並べ替える。
		var handle := RBMTurnMoveHandle.new()
		handle.name = "TurnMoveHandle_%d" % i
		row.add_child(handle)
		var card := card_body.get_parent() as PanelContainer
		card.set_meta("turn_title", title)
		_finish_card(card_body)
		handle.mouse_filter = Control.MOUSE_FILTER_STOP  # _finish_card() が止めた入力を、つまみだけ戻す
		handle.drag_started.connect(_on_turn_drag_started.bind(card))
		handle.drag_moved.connect(_on_turn_drag_moved.bind(card))
		handle.drag_ended.connect(_on_turn_drag_ended.bind(card))
	var count := draft.turn_actions.size()
	_turn_loop_note.text = tr("%dターン目の次は1ターン目に戻ります") % count
	_turn_loop_note.visible = count > 0
	_add_turn_button.disabled = not draft.can_add_turn_action()

# --- ターンの並べ替え（2026-10-29 ユーザー指示: 挿入型ドラッグ＆ドロップ） ---
## 動かしているカードをポインターの位置の順番へ入れ（move_child）、ほかのカードは VBox が自動で詰める。
## 動かしている間もターン番号を位置どおりに付け直す。離した時に draft の順番を1回だけ変える。

func _on_turn_drag_started(card: PanelContainer) -> void:
	_drag_card = card
	_drag_from = card.get_index()
	_style_card(card, "hover")

func _on_turn_drag_moved(global_pos: Vector2, card: PanelContainer) -> void:
	if card != _drag_card:
		return
	## 端の近くでは一覧をスクロールする（長い一覧でも先頭・末尾へ運べる）。
	var scroll_rect := _scroll_container.get_global_rect()
	if global_pos.y < scroll_rect.position.y + DRAG_SCROLL_EDGE:
		_scroll_container.scroll_vertical -= DRAG_SCROLL_STEP
	elif global_pos.y > scroll_rect.end.y - DRAG_SCROLL_EDGE:
		_scroll_container.scroll_vertical += DRAG_SCROLL_STEP
	## ポインターより上にある（中心が上の）ほかのカードの数＝入れる位置。
	var target := 0
	for child in _turn_list.get_children():
		if child == card:
			continue
		var rect := (child as Control).get_global_rect()
		if global_pos.y > rect.position.y + rect.size.y * 0.5:
			target += 1
	if target != card.get_index():
		_turn_list.move_child(card, target)
		_renumber_turn_cards()

func _on_turn_drag_ended(_global_pos: Vector2, card: PanelContainer) -> void:
	if card != _drag_card:
		return
	var from := _drag_from
	var to := card.get_index()
	_drag_card = null
	if draft.move_turn_action(from, to):
		refresh()
	else:
		_style_card(card, "normal")

## ドラッグの途中で一覧を作り直す時は、並べ替えを取り消す（draft はまだ変えていない）。
func _end_turn_drag() -> void:
	_drag_card = null
	_drag_from = -1

func _renumber_turn_cards() -> void:
	for child in _turn_list.get_children():
		var title := (child as Control).get_meta("turn_title", null) as Label
		if title != null:
			title.text = tr("%dターン目") % (child.get_index() + 1)

## 一覧のターンのカードの中身。確定・条件の行動には使用率を出さず、使用率で抽選する候補だけに出す。
func _fill_turn_summary(body: Control, turn: Dictionary, prefix: String) -> void:
	var entries: Array = turn.get("entries", [])
	match str(turn.get("mode", "")):
		RBMActionPatternRules.TURN_MODE_RANDOM:
			for j in range(entries.size()):
				var entry: Dictionary = entries[j]
				_name_row(body, _skill_name(str(entry.get("skill_id", ""))), _usage_text(float(entry.get("weight", 0.0))), "%sEntry_%d" % [prefix, j])
		RBMActionPatternRules.TURN_MODE_CONDITIONAL:
			for j in range(entries.size()):
				var entry: Dictionary = entries[j]
				var when := RBMActionPatternSummary.conditions_text(entry.get("conditions", []), str(entry.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)), draft)
				_name_row(body, tr("%s → %s") % [when if not when.is_empty() else tr("（条件なし）"), _skill_name(str(entry.get("skill_id", "")))], "", "%sEntry_%d" % [prefix, j])
			_name_row(body, tr("それ以外 → %s") % _skill_name(str(turn.get("else_skill_id", ""))), "", "%sElse" % prefix)
		_:
			var skill_id := "" if entries.is_empty() else str((entries[0] as Dictionary).get("skill_id", ""))
			_name_row(body, _skill_name(skill_id), "", "%sEntry_0" % prefix)
			if not skill_id.is_empty():
				_hint_label(body, RBMActionPatternSummary.skill_performance_line(draft.find_skill(skill_id)), "%sDetail_0" % prefix)

func _rebuild_extra_list() -> void:
	_clear(_extra_list)
	for i in range(draft.scripted_actions.size()):
		var entry: Dictionary = draft.scripted_actions[i]
		var timing := str(entry.get("timing", ""))
		if not EXTRA_TIMINGS.has(timing):
			continue  # HARDCORE では「通常行動の代わり」は使わない（作る経路が無い）。
		var body := _make_card(_extra_list, "ExtraActionCard_%d" % i, _open_extra.bind(i))
		var when := _new_label(tr("%dターン目・%s") % [int(entry.get("turn", 1)), tr(str(EXTRA_TIMING_LABELS[timing]))])
		when.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
		body.add_child(when)
		var skill_id := str(entry.get("skill_id", ""))
		_name_row(body, _skill_name(skill_id), "", "ExtraActionName_%d" % i)
		_hint_label(body, RBMActionPatternSummary.skill_performance_line(draft.find_skill(skill_id)), "ExtraActionDetail_%d" % i)
		_finish_card(body)

func _rebuild_awakening_card() -> void:
	_clear(_awakening_container)
	var has_awakening := draft.has_awakening()
	_add_awakening_button.visible = not has_awakening
	## 覚醒は「この外見が覚醒に対応している」時だけ追加できる（選んでからエラーにしない）。
	_add_awakening_button.disabled = not draft.supports_awakening()
	if not has_awakening:
		return
	var awakening := draft.awakening
	var body := _make_card(_awakening_container, "AwakeningCardButton", _open_awakening)
	_wrap_label(body, RBMActionPatternSummary.when_line(awakening.get("conditions", []), str(awakening.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)), draft), "AwakeningWhen")
	_hint_label(body, _awakening_buff_line(awakening), "AwakeningBuff")
	_hint_label(body, _awakening_heal_line(awakening), "AwakeningHeal")
	_finish_card(body)

func _awakening_buff_line(awakening: Dictionary) -> String:
	var buff: Dictionary = awakening.get("buff", {})
	if buff.is_empty():
		return tr("自己強化：なし")
	return tr("自己強化：ATK×%.2f / %dターン") % [float(buff.get("buff_multiplier", 1.0)), int(buff.get("duration_turns", 1))]

func _awakening_heal_line(awakening: Dictionary) -> String:
	var heal: Dictionary = awakening.get("heal", {})
	if heal.is_empty():
		return tr("HP回復：なし")
	if str(heal.get("heal_mode", "fixed")) == "percent":
		return tr("HP回復：最大HPの%.1f%%") % float(heal.get("heal_percent", 0.0))
	return tr("HP回復：HP%d") % int(heal.get("heal_fixed_amount", 0))

# ---------------------------------------------------------------------------
# ② ターンの設定
# ---------------------------------------------------------------------------

func _build_turn_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "TurnView"
	_turn_title = _section_header(view, "", "TurnViewTitle")
	view.add_child(_new_label(tr("決め方")))
	var mode_row := HBoxContainer.new()
	mode_row.name = "TurnModeRow"
	view.add_child(mode_row)
	var group := ButtonGroup.new()
	for mode in RBMActionPatternRules.TURN_MODES:
		var b := _button(mode_row, tr(str(RBMActionPatternRules.TURN_MODE_LABELS[mode])), "TurnModeButton_%s" % mode, _on_turn_mode_pressed.bind(mode))
		b.toggle_mode = true
		b.button_group = group
		_turn_mode_buttons[mode] = b
	_turn_entry_list = VBoxContainer.new()
	_turn_entry_list.name = "TurnEntryList"
	view.add_child(_turn_entry_list)
	_turn_total_label = _wrap_label(view, "", "TurnTotalLabel")
	var add_row := HBoxContainer.new()
	add_row.name = "TurnAddRow"
	view.add_child(add_row)
	_add_turn_entry_button = _button(add_row, "", "AddTurnEntryButton", _on_add_turn_entry_pressed)
	_add_turn_entry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equalize_turn_button = _button(add_row, tr("均等にする"), "EqualizeTurnButton", _on_equalize_turn_pressed, true)
	_turn_problem_label = _warning_label(view, "TurnProblemLabel")
	var actions := HBoxContainer.new()
	actions.name = "TurnActionsRow"
	view.add_child(actions)
	_button(actions, tr("保存"), "TurnConfirmButton", _on_turn_confirm_pressed)
	_button(actions, tr("キャンセル"), "TurnCancelButton", _on_turn_cancel_pressed, true)
	_turn_delete_button = _button(actions, tr("このターンを削除"), "TurnDeleteButton", _on_turn_delete_pressed)
	return view

func _take_skills_snapshot() -> void:
	_skills_snapshot = draft.skills.duplicate(true)
	_skills_snapshot_taken = true

## キャンセル: ②/③ を開いた時点の行動の一覧へ戻す（途中で作った行動・性能の変更を残さない）。
func _restore_skills_snapshot() -> void:
	if not _skills_snapshot_taken:
		return
	draft.skills = _skills_snapshot.duplicate(true)
	_skills_snapshot_taken = false
	main.on_skills_changed()

func _on_add_turn_pressed() -> void:
	if not draft.can_add_turn_action():
		return
	_turn_index = -1
	_pending_turn = {"mode": RBMActionPatternRules.TURN_MODE_FIXED, "entries": []}
	_take_skills_snapshot()
	_show_turn_view()

func _open_turn(index: int) -> void:
	if index < 0 or index >= draft.turn_actions.size():
		return
	_turn_index = index
	_pending_turn = draft.turn_actions[index].duplicate(true)
	_take_skills_snapshot()
	_show_turn_view()

func _show_turn_view() -> void:
	var number := (_turn_index if _turn_index >= 0 else draft.turn_actions.size()) + 1
	_turn_title.text = tr("%dターン目の設定") % number
	_turn_delete_button.visible = _turn_index >= 0
	_show_only(_turn_view)
	_rebuild_turn_view()

func _pending_mode() -> String:
	return str(_pending_turn.get("mode", RBMActionPatternRules.TURN_MODE_FIXED))

func _pending_entries() -> Array:
	if not _pending_turn.has("entries"):
		_pending_turn["entries"] = []
	return _pending_turn["entries"]

func _rebuild_turn_view() -> void:
	var mode := _pending_mode()
	## 選んでいる決め方は、作成画面のほかの切り替えボタン（STEP2 の弱点など）が選ばれた時と同じ水色の枠
	## （RBMWorldUi.walk() が押されたボタンに付ける枠。walk は開いた時にしか付けないので、ここで付ける）。
	var world: Variant = main.get("_world_ui") if is_instance_valid(main) else null
	for m in _turn_mode_buttons.keys():
		var b := _turn_mode_buttons[m] as Button
		b.set_pressed_no_signal(m == mode)
		if world != null:
			var selected_box: StyleBox = world.frame(Color("102a2e"), Color("43efff"))
			b.add_theme_stylebox_override("pressed", selected_box)
			b.add_theme_stylebox_override("hover_pressed", selected_box)
	_clear(_turn_entry_list)
	var entries := _pending_entries()
	match mode:
		RBMActionPatternRules.TURN_MODE_RANDOM:
			for j in range(entries.size()):
				var entry: Dictionary = entries[j]
				var skill_id := str(entry.get("skill_id", ""))
				var body := _make_card(_turn_entry_list, "TurnEntryCard_%d" % j, _open_turn_entry.bind(j))
				_name_row(body, _skill_name(skill_id), _usage_text(float(entry.get("weight", 0.0))), "TurnEntryName_%d" % j)
				_hint_label(body, RBMActionPatternSummary.skill_performance_line(draft.find_skill(skill_id)), "TurnEntryDetail_%d" % j)
				_finish_card(body)
			var total := 0.0
			for entry in entries:
				total += float((entry as Dictionary).get("weight", 0.0))
			_turn_total_label.text = tr("使用率の合計: %.1f%%") % total
			_add_turn_entry_button.text = tr("＋ 候補を追加する")
		RBMActionPatternRules.TURN_MODE_CONDITIONAL:
			for j in range(entries.size()):
				var entry: Dictionary = entries[j]
				var skill_id := str(entry.get("skill_id", ""))
				var body := _make_card(_turn_entry_list, "TurnEntryCard_%d" % j, _open_turn_entry.bind(j))
				var caption := _new_label(tr("条件 %d") % (j + 1))
				caption.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
				body.add_child(caption)
				var when := RBMActionPatternSummary.conditions_text(entry.get("conditions", []), str(entry.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)), draft)
				_name_row(body, tr("%s → %s") % [when if not when.is_empty() else tr("（条件なし）"), _skill_name(skill_id)], "", "TurnEntryName_%d" % j)
				_hint_label(body, RBMActionPatternSummary.skill_performance_line(draft.find_skill(skill_id)), "TurnEntryDetail_%d" % j)
				_finish_card(body)
			var else_id := str(_pending_turn.get("else_skill_id", ""))
			var else_body := _make_card(_turn_entry_list, "TurnElseCard", _open_turn_else)
			var else_caption := _new_label(tr("それ以外"))
			else_caption.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
			else_body.add_child(else_caption)
			_name_row(else_body, _skill_name(else_id), "", "TurnElseName")
			if not else_id.is_empty():
				_hint_label(else_body, RBMActionPatternSummary.skill_performance_line(draft.find_skill(else_id)), "TurnElseDetail")
			_finish_card(else_body)
			_add_turn_entry_button.text = tr("＋ 条件を追加する")
		_:
			if not entries.is_empty():
				var skill_id := str((entries[0] as Dictionary).get("skill_id", ""))
				var body := _make_card(_turn_entry_list, "TurnEntryCard_0", _open_turn_entry.bind(0))
				_name_row(body, _skill_name(skill_id), "", "TurnEntryName_0")
				_hint_label(body, RBMActionPatternSummary.skill_performance_line(draft.find_skill(skill_id)), "TurnEntryDetail_0")
				_finish_card(body)
			_add_turn_entry_button.text = tr("＋ 行動を設定する")
	_turn_total_label.visible = mode == RBMActionPatternRules.TURN_MODE_RANDOM
	_equalize_turn_button.visible = mode == RBMActionPatternRules.TURN_MODE_RANDOM
	var full := entries.size() >= RBMActionPatternRules.MAX_TURN_ENTRIES
	_add_turn_entry_button.visible = not (mode == RBMActionPatternRules.TURN_MODE_FIXED and not entries.is_empty())
	_add_turn_entry_button.disabled = full
	_turn_problem_label.visible = false

## 決め方を切り替える。候補はそのまま残す（確定は先頭の1つだけを使う）。使用率で抽選へ切り替えた時、
## 使用率の無い候補があれば均等に分け直す。
func _on_turn_mode_pressed(mode: String) -> void:
	_pending_turn["mode"] = mode
	if mode == RBMActionPatternRules.TURN_MODE_RANDOM:
		var missing := false
		for entry in _pending_entries():
			if not (entry as Dictionary).has("weight"):
				missing = true
		if missing:
			_equalize_pending_weights()
	_rebuild_turn_view()

func _equalize_pending_weights() -> void:
	var entries := _pending_entries()
	if entries.is_empty():
		return
	## SIMPLE の「均等にする」と同じく、小数第1位で分けて余りを先頭へ寄せる（合計をちょうど100にする）。
	var share := floorf(1000.0 / entries.size()) / 10.0
	for entry in entries:
		(entry as Dictionary)["weight"] = share
	(entries[0] as Dictionary)["weight"] = snappedf(100.0 - share * (entries.size() - 1), 0.1)

func _on_equalize_turn_pressed() -> void:
	_equalize_pending_weights()
	_rebuild_turn_view()

func _on_add_turn_entry_pressed() -> void:
	_open_add_choice(CONTEXT_TURN_ENTRY)

func _on_turn_confirm_pressed() -> void:
	var turn := RBMCreatorDraft.normalized_turn_action(_pending_turn)
	var problem := draft.turn_action_problem(turn)
	if not problem.is_empty():
		_turn_problem_label.text = problem
		_turn_problem_label.visible = true
		return
	var old_ids: Array[String] = []
	if _turn_index >= 0:
		old_ids = RBMCreatorDraft.turn_action_skill_ids(draft.turn_actions[_turn_index])
		draft.update_turn_action(_turn_index, turn)
	else:
		draft.add_turn_action(turn)
	## 決め方を切り替えて外れた行動・作ったが使わなかった行動を片付ける（ほかで使っていれば残る）。
	for skill_id in old_ids + _snapshot_new_skill_ids():
		draft.remove_skill_if_unreferenced(skill_id)
	_skills_snapshot_taken = false
	main.on_skills_changed()
	_show_only(_list_view)
	refresh()

## ②/③ を開いてから新しく作った行動の id。
func _snapshot_new_skill_ids() -> Array[String]:
	var before := {}
	for skill in _skills_snapshot:
		before[str(skill.get("skill_id", ""))] = true
	var out: Array[String] = []
	for skill in draft.skills:
		var sid := str(skill.get("skill_id", ""))
		if not before.has(sid):
			out.append(sid)
	return out

func _on_turn_cancel_pressed() -> void:
	_restore_skills_snapshot()
	_show_only(_list_view)
	refresh()

func _on_turn_delete_pressed() -> void:
	if _turn_index < 0:
		return
	var old_ids := RBMCreatorDraft.turn_action_skill_ids(draft.turn_actions[_turn_index])
	_restore_skills_snapshot()
	draft.remove_turn_action(_turn_index)
	for skill_id in old_ids:
		draft.remove_skill_if_unreferenced(skill_id)
	main.on_skills_changed()
	_show_only(_list_view)
	refresh()

# ---------------------------------------------------------------------------
# 追加の方法（既存の行動から選ぶ / 新しく行動を作る）
# ---------------------------------------------------------------------------

func _build_add_choice_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "AddChoiceView"
	_add_choice_title = _section_header(view, tr("行動の追加方法を選んでください"), "AddChoiceTitle")
	_add_choice_pick_existing_button = _button(view, tr("既存の行動から選ぶ"), "AddChoicePickExistingButton", _on_add_choice_pick_existing_pressed)
	_button(view, tr("新しく行動を作る"), "AddChoiceCreateNewButton", _on_add_choice_create_new_pressed)
	_button(view, tr("キャンセル"), "AddChoiceCancelButton", _on_add_choice_cancel_pressed, true)
	return view

func _open_add_choice(target_context: String) -> void:
	_add_target_context = target_context
	_add_choice_pick_existing_button.disabled = draft.skills.is_empty()
	_show_only(_add_choice_view)

func _on_add_choice_pick_existing_pressed() -> void:
	_rebuild_pick_existing_list()
	_show_only(_pick_existing_view)

func _on_add_choice_create_new_pressed() -> void:
	if not draft.can_add_skill():
		return
	_open_entry_for_new_creation()

func _on_add_choice_cancel_pressed() -> void:
	_back_from_entry()

func _build_pick_existing_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "PickExistingView"
	_section_header(view, tr("既存の行動から選んでください"), "PickExistingTitle")
	_pick_existing_list = VBoxContainer.new()
	_pick_existing_list.name = "PickExistingList"
	view.add_child(_pick_existing_list)
	_button(view, tr("キャンセル"), "PickExistingCancelButton", func(): _show_only(_add_choice_view), true)
	return view

## 使用率で抽選する候補には、同じターンに既にある行動を出さない（同じ行動を2回並べても意味が無い）。
func _rebuild_pick_existing_list() -> void:
	_clear(_pick_existing_list)
	var excluded := {}
	if _add_target_context == CONTEXT_TURN_ENTRY and _pending_mode() == RBMActionPatternRules.TURN_MODE_RANDOM:
		for entry in _pending_entries():
			excluded[str((entry as Dictionary).get("skill_id", ""))] = true
	var shown := 0
	for i in range(draft.skills.size()):
		var skill: Dictionary = draft.skills[i]
		var skill_id := str(skill.get("skill_id", ""))
		if excluded.has(skill_id):
			continue
		var body := _make_card(_pick_existing_list, "PickExistingSkillCard_%d" % i, _on_pick_existing_selected.bind(skill_id))
		_name_row(body, str(skill.get("name", "")), "", "PickExistingSkillName_%d" % i)
		_hint_label(body, RBMActionPatternSummary.skill_performance_line(skill), "PickExistingSkillDetail_%d" % i)
		_finish_card(body)
		shown += 1
	if shown == 0:
		_hint_label(_pick_existing_list, tr("選べる行動がありません"), "PickExistingEmpty")

func _on_pick_existing_selected(skill_id: String) -> void:
	_entry_context = _add_target_context
	_entry_index = -1
	_entry_skill_id = skill_id
	_entry_is_new_creation = false
	_open_entry_view([], RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)

# ---------------------------------------------------------------------------
# ③ 行動の詳細（性能・条件・使用率・ターン開始/終了・削除）
# ---------------------------------------------------------------------------

func _build_entry_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "EntryView"
	_entry_title = _section_header(view, "", "EntryViewTitle")
	_performance_summary_row = HBoxContainer.new()
	_performance_summary_row.name = "EntryPerformanceRow"
	view.add_child(_performance_summary_row)
	_performance_summary_label = _wrap_label(_performance_summary_row, "", "EntryPerformanceLabel")
	_button(_performance_summary_row, tr("性能を編集"), "EntryEditPerformanceButton", _on_edit_performance_pressed)
	_shared_skill_notice = _hint_label(view, tr("この行動はほかの所でも使われています。性能を変えると、使っている所すべてに反映されます。"), "SharedSkillNotice")
	## 差し込み場所は MarginContainer（子の最小サイズを親へ伝える。素の Control だと高さ0になり重なる）。
	_form_slot = MarginContainer.new()
	_form_slot.name = "EntryFormSlot"
	view.add_child(_form_slot)
	_condition_slot = MarginContainer.new()
	_condition_slot.name = "EntryConditionSlot"
	view.add_child(_condition_slot)

	_weight_block = VBoxContainer.new()
	_weight_block.name = "EntryWeightBlock"
	view.add_child(_weight_block)
	_weight_block.add_child(_new_label(tr("■ 使用率")))
	var weight_row := HBoxContainer.new()
	_weight_block.add_child(weight_row)
	_weight_slider = HSlider.new()
	_weight_slider.name = "EntryWeightSlider"
	_weight_slider.min_value = 0.0
	_weight_slider.max_value = 100.0
	_weight_slider.step = 0.1
	_weight_slider.custom_minimum_size = PERCENT_SLIDER_MIN_SIZE
	_weight_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weight_row.add_child(_weight_slider)
	_weight_spin = SpinBox.new()
	_weight_spin.name = "EntryWeightSpin"
	_weight_spin.min_value = 0.0
	_weight_spin.max_value = 100.0
	_weight_spin.step = 0.1
	_weight_spin.suffix = "%"
	weight_row.add_child(_weight_spin)
	_weight_slider.value_changed.connect(_on_weight_changed.bind(_weight_spin))
	_weight_spin.value_changed.connect(_on_weight_changed.bind(_weight_slider))

	_extra_block = VBoxContainer.new()
	_extra_block.name = "EntryExtraBlock"
	view.add_child(_extra_block)
	_extra_block.add_child(_new_label(tr("■ いつ使う？")))
	var turn_row := HBoxContainer.new()
	_extra_block.add_child(turn_row)
	turn_row.add_child(_new_label(tr("ターン")))
	_extra_turn_spin = _new_spin(1, 999999, 1)
	_extra_turn_spin.name = "ExtraTurnSpin"
	turn_row.add_child(_extra_turn_spin)
	var timing_row := HBoxContainer.new()
	_extra_block.add_child(timing_row)
	timing_row.add_child(_new_label(tr("タイミング")))
	_extra_timing_option = OptionButton.new()
	_extra_timing_option.name = "ExtraTimingOption"
	for timing in EXTRA_TIMINGS:
		_extra_timing_option.add_item(tr(str(EXTRA_TIMING_LABELS[timing])))
	timing_row.add_child(_extra_timing_option)

	_else_note = _hint_label(view, tr("どの条件も満たさない時に使います"), "EntryElseNote")
	_entry_error_label = _warning_label(view, "EntryErrorLabel")
	_entry_actions_row = HBoxContainer.new()
	_entry_actions_row.name = "EntryActionsRow"
	view.add_child(_entry_actions_row)
	_entry_confirm_button = _button(_entry_actions_row, tr("保存"), "EntryConfirmButton", _on_entry_confirm_pressed)
	_button(_entry_actions_row, tr("キャンセル"), "EntryCancelButton", _on_entry_cancel_pressed, true)
	_entry_delete_button = _button(_entry_actions_row, tr("この行動を削除"), "EntryDeleteButton", _on_entry_delete_pressed)
	return view

func _on_weight_changed(value: float, paired: Range) -> void:
	if _syncing_weight:
		return
	_syncing_weight = true
	paired.value = value
	_syncing_weight = false

func _open_turn_entry(index: int) -> void:
	var entries := _pending_entries()
	if index < 0 or index >= entries.size():
		return
	var entry: Dictionary = entries[index]
	_entry_context = CONTEXT_TURN_ENTRY
	_entry_index = index
	_entry_skill_id = str(entry.get("skill_id", ""))
	_entry_is_new_creation = false
	_open_entry_view(entry.get("conditions", []), str(entry.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)))

func _open_turn_else() -> void:
	var else_id := str(_pending_turn.get("else_skill_id", ""))
	if else_id.is_empty():
		_open_add_choice(CONTEXT_TURN_ELSE)
		return
	_entry_context = CONTEXT_TURN_ELSE
	_entry_index = -1
	_entry_skill_id = else_id
	_entry_is_new_creation = false
	_open_entry_view([], RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)

func _on_add_extra_pressed() -> void:
	_take_skills_snapshot()
	_open_add_choice(CONTEXT_EXTRA)

func _open_extra(index: int) -> void:
	if index < 0 or index >= draft.scripted_actions.size():
		return
	_take_skills_snapshot()
	_entry_context = CONTEXT_EXTRA
	_entry_index = index
	_entry_skill_id = str(draft.scripted_actions[index].get("skill_id", ""))
	_entry_is_new_creation = false
	_open_entry_view([], RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)

func _on_add_awakening_pressed() -> void:
	if not draft.supports_awakening() or draft.has_awakening():
		return
	_open_awakening()

func _open_awakening() -> void:
	_take_skills_snapshot()
	_entry_context = CONTEXT_AWAKENING
	_entry_index = -1
	_entry_skill_id = ""
	_entry_is_new_creation = false
	var awakening := draft.awakening
	_open_entry_view(awakening.get("conditions", []), str(awakening.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)))

func _open_entry_for_new_creation() -> void:
	_entry_context = _add_target_context
	_entry_index = -1
	_entry_skill_id = ""
	_entry_is_new_creation = true
	_open_entry_view([], RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)

## ③ を開く。何を見せるかは _entry_context と、使用率で抽選・条件で分岐のどちらのターンかで決まる。
func _open_entry_view(conditions: Array, condition_logic: String) -> void:
	_form_context = ""
	var mode := _pending_mode()
	var is_turn := _entry_context == CONTEXT_TURN_ENTRY
	var number := (_turn_index if _turn_index >= 0 else draft.turn_actions.size()) + 1
	match _entry_context:
		CONTEXT_TURN_ENTRY:
			match mode:
				RBMActionPatternRules.TURN_MODE_RANDOM:
					_entry_title.text = tr("%dターン目の候補") % number
				RBMActionPatternRules.TURN_MODE_CONDITIONAL:
					_entry_title.text = tr("%dターン目・条件 %d") % [number, (_entry_index if _entry_index >= 0 else _pending_entries().size()) + 1]
				_:
					_entry_title.text = tr("%dターン目の行動") % number
		CONTEXT_TURN_ELSE:
			_entry_title.text = tr("%dターン目・それ以外") % number
		CONTEXT_EXTRA:
			_entry_title.text = tr("ターン開始・終了時に追加する行動")
		CONTEXT_AWAKENING:
			_entry_title.text = tr("覚醒")
	var uses_conditions := (is_turn and mode == RBMActionPatternRules.TURN_MODE_CONDITIONAL) or _entry_context == CONTEXT_AWAKENING
	_pending_conditions = (conditions as Array).duplicate(true)
	_pending_condition_logic = condition_logic
	_close_condition_editor()  # 行動・覚醒とも同じ4カテゴリ（2026-10-29）。前の画面の入力欄の紐付けは外す。
	_condition_block.visible = uses_conditions
	_refresh_condition_block()

	_weight_block.visible = is_turn and mode == RBMActionPatternRules.TURN_MODE_RANDOM
	if _weight_block.visible:
		var weight := _default_new_weight()
		if _entry_index >= 0:
			weight = float((_pending_entries()[_entry_index] as Dictionary).get("weight", 0.0))
		_weight_spin.value = weight
		_weight_slider.value = weight
	_extra_block.visible = _entry_context == CONTEXT_EXTRA
	if _extra_block.visible:
		var entry: Dictionary = draft.scripted_actions[_entry_index] if _entry_index >= 0 else {}
		_extra_turn_spin.value = int(entry.get("turn", 1))
		_extra_timing_option.select(maxi(0, EXTRA_TIMINGS.find(str(entry.get("timing", EXTRA_TIMINGS[0])))))
	_else_note.visible = _entry_context == CONTEXT_TURN_ELSE

	var is_existing := _entry_index >= 0 or (_entry_context == CONTEXT_TURN_ELSE and not str(_pending_turn.get("else_skill_id", "")).is_empty()) or (_entry_context == CONTEXT_AWAKENING and draft.has_awakening())
	_entry_confirm_button.text = tr("保存") if is_existing else tr("追加")
	_entry_delete_button.visible = is_existing
	_entry_delete_button.text = tr("覚醒を削除") if _entry_context == CONTEXT_AWAKENING else tr("この行動を削除")
	_entry_error_label.visible = false

	if _entry_context == CONTEXT_AWAKENING:
		_form.open_for_awakening(draft.awakening, tr("覚醒を追加") if not draft.has_awakening() else tr("覚醒を編集"))
		_form.set_save_cancel_buttons_visible(false)
		_form.visible = true
	elif _entry_is_new_creation:
		_form.open_for_new(tr("行動を作る"))
		_form.set_awakening_type_available(false)
		_form.set_save_cancel_buttons_visible(false)
		_form.visible = true
	else:
		_form.visible = false
	_show_only(_entry_view)
	_refresh_entry_view()

## 使用率で抽選する候補を新しく追加する時の初期値: 残りの使用率（合計100から今の合計を引いた分）。
func _default_new_weight() -> float:
	var total := 0.0
	for entry in _pending_entries():
		total += float((entry as Dictionary).get("weight", 0.0))
	return clampf(snappedf(100.0 - total, 0.1), 0.0, 100.0)

func _refresh_entry_view() -> void:
	var form_open := _form.visible
	_performance_summary_row.visible = not form_open and not _entry_skill_id.is_empty()
	if _performance_summary_row.visible:
		var skill := draft.find_skill(_entry_skill_id)
		_performance_summary_label.text = "%s\n%s" % [str(skill.get("name", "")), RBMActionPatternSummary.skill_performance_line(skill)]
	_shared_skill_notice.visible = _performance_summary_row.visible and _is_skill_shared(_entry_skill_id)
	## 「性能を編集」のフォームが自分の保存/キャンセルを持つ間は、外側の行を隠す（未保存の入力のまま外側で閉じない）。
	_entry_actions_row.visible = _form_context != "edit_performance"

## この行動が、いま編集している所以外でも使われているか（性能の変更が他にも反映されることを知らせる）。
func _is_skill_shared(skill_id: String) -> bool:
	var uses := 0
	for turn in draft.turn_actions:
		for entry in turn.get("entries", []):
			if str((entry as Dictionary).get("skill_id", "")) == skill_id:
				uses += 1
		if str(turn.get("else_skill_id", "")) == skill_id:
			uses += 1
	for entry in draft.scripted_actions:
		if str(entry.get("skill_id", "")) == skill_id:
			uses += 1
	return uses > 1

func _on_edit_performance_pressed() -> void:
	_form_context = "edit_performance"
	_form.open_for_editing(_entry_skill_id, tr("行動の性能を編集"))
	_form.set_save_cancel_buttons_visible(true)
	_form.visible = true
	_refresh_entry_view()

func _on_form_saved(_skill_id: String) -> void:
	if _form_context != "edit_performance":
		return
	_form_context = ""
	_form.visible = false
	main.on_skills_changed()
	_refresh_entry_view()

func _on_form_cancelled() -> void:
	if _form_context != "edit_performance":
		return
	_form_context = ""
	_form.visible = false
	_refresh_entry_view()

## フォームの種類の切り替え（覚醒は選べないようにしているので、ここでは何もしない）。
func _on_form_type_changed(_type_id: String) -> void:
	pass

func _on_entry_confirm_pressed() -> void:
	## 通常は「性能を編集」の間は外側の行を隠すので来ないが、万一来ても入力中の内容（行動名など）を捨てない。
	if _form_context == "edit_performance" and not _entry_skill_id.is_empty():
		draft.update_skill(_entry_skill_id, _form.current_action_data())
		_form_context = ""
		_form.visible = false
		main.on_skills_changed()
	if _condition_block.visible:
		_refresh_condition_error()
		if not draft.conditions_problem(_pending_conditions).is_empty():
			return
		if _pending_conditions.is_empty() and _entry_context == CONTEXT_TURN_ENTRY:
			_entry_error_label.text = tr("条件を1つ以上つけてください")
			_entry_error_label.visible = true
			return
	if _entry_context == CONTEXT_AWAKENING:
		var form_data := _form.current_action_data()
		draft.set_awakening({
			"conditions": _pending_conditions,
			"condition_logic": _pending_condition_logic,
			"buff": form_data.get("buff", {}),
			"heal": form_data.get("heal", {}),
		})
		_skills_snapshot_taken = false
		_close_entry_to_list()
		return
	var skill_id := _entry_skill_id
	if _entry_is_new_creation:
		skill_id = draft.add_skill(_form.current_action_data())
		if skill_id.is_empty():
			return  # 行動の数の上限（ボタンの無効化をすり抜けた場合の防御）
		_entry_is_new_creation = false
		main.on_skills_changed()
	match _entry_context:
		CONTEXT_TURN_ENTRY:
			var entry := {"skill_id": skill_id}
			match _pending_mode():
				RBMActionPatternRules.TURN_MODE_RANDOM:
					entry["weight"] = snappedf(_weight_spin.value, 0.1)
				RBMActionPatternRules.TURN_MODE_CONDITIONAL:
					entry["conditions"] = _pending_conditions.duplicate(true)
					entry["condition_logic"] = _pending_condition_logic
			var entries := _pending_entries()
			if _entry_index >= 0:
				entries[_entry_index] = entry
			elif _pending_mode() == RBMActionPatternRules.TURN_MODE_FIXED:
				entries.clear()
				entries.append(entry)
			else:
				entries.append(entry)
			_back_to_turn_view()
		CONTEXT_TURN_ELSE:
			_pending_turn["else_skill_id"] = skill_id
			_back_to_turn_view()
		CONTEXT_EXTRA:
			var turn := int(_extra_turn_spin.value)
			var timing: String = EXTRA_TIMINGS[maxi(0, _extra_timing_option.selected)]
			var old_skill_id := ""
			if _entry_index >= 0:
				old_skill_id = str(draft.scripted_actions[_entry_index].get("skill_id", ""))
				draft.remove_scripted_action(_entry_index)
			draft.add_scripted_action(turn, skill_id, timing)
			if not old_skill_id.is_empty() and old_skill_id != skill_id:
				draft.remove_skill_if_unreferenced(old_skill_id)
			_skills_snapshot_taken = false
			main.on_skills_changed()
			_close_entry_to_list()

func _on_entry_cancel_pressed() -> void:
	_back_from_entry()

## ③・追加の方法のキャンセルの戻り先: ターンの中なら②、それ以外は①（行動の一覧を開いた時点へ戻す）。
func _back_from_entry() -> void:
	if _turn_view_is_open():
		_back_to_turn_view()
		return
	_restore_skills_snapshot()
	_close_entry_to_list()

## ②を開いている途中か（③・追加の方法が②から開かれたか）。
func _turn_view_is_open() -> bool:
	return _entry_context in [CONTEXT_TURN_ENTRY, CONTEXT_TURN_ELSE] or _add_target_context in [CONTEXT_TURN_ENTRY, CONTEXT_TURN_ELSE]

func _on_entry_delete_pressed() -> void:
	match _entry_context:
		CONTEXT_TURN_ENTRY:
			var entries := _pending_entries()
			if _entry_index >= 0 and _entry_index < entries.size():
				entries.remove_at(_entry_index)
			_back_to_turn_view()
		CONTEXT_TURN_ELSE:
			_pending_turn["else_skill_id"] = ""
			_back_to_turn_view()
		CONTEXT_EXTRA:
			if _entry_index >= 0:
				var skill_id := str(draft.scripted_actions[_entry_index].get("skill_id", ""))
				_restore_skills_snapshot()
				draft.remove_scripted_action(_entry_index)
				draft.remove_skill_if_unreferenced(skill_id)
				main.on_skills_changed()
			_close_entry_to_list()
		CONTEXT_AWAKENING:
			_restore_skills_snapshot()
			draft.remove_awakening()
			_close_entry_to_list()

func _back_to_turn_view() -> void:
	_close_condition_editor()
	_form.visible = false
	_form_context = ""
	_entry_context = ""
	_add_target_context = ""
	_show_only(_turn_view)
	_rebuild_turn_view()

func _close_entry_to_list() -> void:
	_close_condition_editor()
	_form.visible = false
	_form_context = ""
	_entry_context = ""
	_add_target_context = ""
	_show_only(_list_view)
	refresh()

# ---------------------------------------------------------------------------
# 共有: 条件の入力欄（条件で分岐の行・覚醒）
# ---------------------------------------------------------------------------

func _build_condition_block() -> VBoxContainer:
	var block := VBoxContainer.new()
	block.name = "ConditionBlock"
	block.add_child(_new_label(tr("■ 条件")))
	_condition_list = VBoxContainer.new()
	_condition_list.name = "ConditionList"
	block.add_child(_condition_list)
	_condition_error_label = _warning_label(block, "ConditionErrorLabel")
	_condition_logic_option = OptionButton.new()
	_condition_logic_option.name = "ConditionLogicOption"
	for logic in RBMActionPatternRules.CONDITION_LOGIC_TYPES:
		_condition_logic_option.add_item(tr(str(RBMActionPatternRules.CONDITION_LOGIC_LABELS.get(logic, logic))))
	_condition_logic_option.item_selected.connect(_on_condition_logic_selected)
	block.add_child(_condition_logic_option)
	_add_condition_button = _button(block, tr("＋ 条件をつける"), "AddConditionButton", _on_add_condition_pressed)
	_condition_editor = VBoxContainer.new()
	_condition_editor.name = "ConditionEditor"
	_condition_editor.visible = false
	block.add_child(_condition_editor)
	_build_condition_editor()
	return block

func _build_condition_editor() -> void:
	## 2026-10-29 ユーザー確定: 長い1つのプルダウンをやめ、2段階で選ぶ。
	## 第1段階: カテゴリ（ボスHP・ターン・攻略側生存人数・特定キャラクターの状態）
	## 第2段階: そのカテゴリの比較方法（以下/以上、ちょうど/以降/まで/ごと、…）と、必要な値だけ。
	var category_row := HBoxContainer.new()
	category_row.name = "ConditionCategoryRow"
	_condition_editor.add_child(category_row)
	category_row.add_child(_new_label(tr("条件")))
	_condition_category_option = OptionButton.new()
	_condition_category_option.name = "ConditionCategoryOption"
	for category in RBMActionPatternRules.CONDITION_CATEGORIES:
		_condition_category_option.add_item(tr(str(category["label"])))
	_condition_category_option.item_selected.connect(_on_condition_category_selected)
	category_row.add_child(_condition_category_option)

	_condition_compare_row = HBoxContainer.new()
	_condition_compare_row.name = "ConditionCompareRow"
	_condition_editor.add_child(_condition_compare_row)
	_condition_compare_label = _new_label(tr("比較方法"))
	_condition_compare_row.add_child(_condition_compare_label)
	_condition_compare_option = OptionButton.new()
	_condition_compare_option.name = "ConditionCompareOption"
	_condition_compare_option.item_selected.connect(_on_condition_compare_selected)
	_condition_compare_row.add_child(_condition_compare_option)

	_condition_percent_row = _labeled_spin_row(_condition_editor, tr("数値"), 0.0, 100.0, 1.0)
	_condition_percent_spin = _condition_percent_row.get_child(1)
	_condition_percent_spin.suffix = "%"
	_condition_turn_row = _labeled_spin_row(_condition_editor, tr("ターン数"), 1.0, 999999.0, 1.0)
	_condition_turn_spin = _condition_turn_row.get_child(1)
	_condition_n_row = _labeled_spin_row(_condition_editor, tr("ターン数"), 1.0, 999999.0, 1.0)
	_condition_n_spin = _condition_n_row.get_child(1)
	_condition_count_row = _labeled_spin_row(_condition_editor, tr("人数"), 0.0, 4.0, 1.0)
	_condition_count_spin = _condition_count_row.get_child(1)

	## キャラクターは攻略パーティで選べるキャラクターの一覧（今までの「特定キャラクター」の条件と同じ選び方）。
	_condition_character_row = HBoxContainer.new()
	_condition_character_row.name = "ConditionCharacterRow"
	_condition_editor.add_child(_condition_character_row)
	_condition_character_row.add_child(_new_label(tr("キャラクター")))
	_condition_character_option = OptionButton.new()
	_condition_character_option.name = "ConditionCharacterOption"
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		_condition_character_option.add_item(_character_display_name(character_id))
	_condition_character_row.add_child(_condition_character_option)

	## 見出しの幅をそろえて、入力欄の左端を縦に並べる。数値の欄は「%」まで見える幅にする。
	for row in [category_row, _condition_compare_row, _condition_percent_row, _condition_turn_row, _condition_n_row, _condition_count_row, _condition_character_row]:
		((row as HBoxContainer).get_child(0) as Control).custom_minimum_size = Vector2(CONDITION_LABEL_WIDTH, 0.0)
	for spin in [_condition_percent_spin, _condition_turn_spin, _condition_n_spin, _condition_count_spin]:
		(spin as SpinBox).custom_minimum_size = CONDITION_SPIN_MIN_SIZE
	## 長いキャラクター名で入力欄の幅が広がらないよう、選択中の文字だけ出して省略する。
	for option in [_condition_category_option, _condition_compare_option, _condition_character_option]:
		(option as OptionButton).fit_to_longest_item = false
		(option as OptionButton).clip_text = true
		(option as OptionButton).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## 入力は変えた瞬間に、紐付いている条件へ反映する（外側の保存/キャンセルだけが確定/破棄）。
	for spin in [_condition_percent_spin, _condition_turn_spin, _condition_n_spin, _condition_count_spin]:
		(spin as SpinBox).value_changed.connect(_on_condition_editor_value_changed)
	_condition_character_option.item_selected.connect(_on_condition_editor_value_changed)
	_fill_compare_options(0)

func _refresh_condition_block() -> void:
	_condition_logic_option.select(RBMActionPatternRules.CONDITION_LOGIC_TYPES.find(_pending_condition_logic))
	_rebuild_condition_list()

func _rebuild_condition_list() -> void:
	_clear(_condition_list)
	for i in range(_pending_conditions.size()):
		var condition: Dictionary = _pending_conditions[i]
		var row := HBoxContainer.new()
		row.name = "ConditionRow_%d" % i
		_condition_list.add_child(row)
		## 新しく選べない旧条件（保存済みのデータ）も、そのまま表示して残す（消すのは作者が「削除」を押した時だけ）。
		_wrap_label(row, RBMActionPatternSummary.condition_line(condition, draft))
		_button(row, tr("削除"), "RemoveConditionButton_%d" % i, _remove_condition.bind(i), true)
	_condition_logic_option.visible = _pending_conditions.size() > 1
	_refresh_condition_error()

## 未入力・不正値の条件が残っている間、その理由を条件の一覧の下に出す（保存も同じ判定で止まる）。
func _refresh_condition_error() -> void:
	var problem := draft.conditions_problem(_pending_conditions)
	_condition_error_label.text = problem
	_condition_error_label.visible = not problem.is_empty()

func _on_condition_logic_selected(_index: int) -> void:
	_pending_condition_logic = RBMActionPatternRules.CONDITION_LOGIC_TYPES[_condition_logic_option.selected]

## 「＋ 条件をつける」: 押した時点で新しい条件を作り、入力欄をその条件へ紐付ける（最初はボスHP・以下）。
func _on_add_condition_pressed() -> void:
	_editing_condition_index = -1
	_condition_category_option.select(0)
	_fill_compare_options(0)
	for spin in [_condition_percent_spin, _condition_turn_spin, _condition_n_spin, _condition_count_spin]:
		(spin as SpinBox).set_value_no_signal((spin as SpinBox).min_value)
	if _condition_character_option.item_count > 0:
		_condition_character_option.select(0)
	_refresh_condition_editor_visibility()
	_pending_conditions.append(_build_condition_from_editor())
	_editing_condition_index = _pending_conditions.size() - 1
	_condition_editor.visible = true
	_entry_error_label.visible = false
	_rebuild_condition_list()

## 第2段階の比較方法を、選んだカテゴリのものに入れ替える（最初の比較方法を選んだ状態にする）。
func _fill_compare_options(category_index: int) -> void:
	var category: Dictionary = RBMActionPatternRules.CONDITION_CATEGORIES[category_index]
	_condition_compare_option.clear()
	for label in category["compare_labels"]:
		_condition_compare_option.add_item(tr(str(label)))
	_condition_compare_option.select(0)
	_condition_compare_label.text = tr("状態") if str(category["id"]) == "character" else tr("比較方法")

func _on_condition_category_selected(index: int) -> void:
	_fill_compare_options(index)
	_refresh_condition_editor_visibility()
	_sync_editing_condition()

func _on_condition_compare_selected(_index: int) -> void:
	_refresh_condition_editor_visibility()
	_sync_editing_condition()

## 条件の種類を、2段階の選び方（カテゴリ→比較方法）で選ぶ（人が選ぶのと同じく選んだ通知も出す）。
func _select_condition_type(condition_type: String) -> void:
	var position := RBMActionPatternRules.condition_category_position(condition_type)
	if int(position[0]) < 0:
		return
	_condition_category_option.select(int(position[0]))
	_condition_category_option.item_selected.emit(int(position[0]))
	_condition_compare_option.select(int(position[1]))
	_condition_compare_option.item_selected.emit(int(position[1]))

func _selected_condition_type() -> String:
	var category_index := _condition_category_option.selected
	if category_index < 0 or category_index >= RBMActionPatternRules.CONDITION_CATEGORIES.size():
		return ""
	var types: Array = RBMActionPatternRules.CONDITION_CATEGORIES[category_index]["types"]
	var compare_index := _condition_compare_option.selected
	return str(types[compare_index]) if compare_index >= 0 and compare_index < types.size() else ""

func _on_condition_editor_value_changed(_value: Variant) -> void:
	_sync_editing_condition()

func _sync_editing_condition() -> void:
	if _editing_condition_index < 0 or _editing_condition_index >= _pending_conditions.size():
		return
	_pending_conditions[_editing_condition_index] = _build_condition_from_editor()
	_rebuild_condition_list()

func _close_condition_editor() -> void:
	_editing_condition_index = -1
	_condition_editor.visible = false

## 選んだ比較方法に要る値の欄だけを出す。特定キャラクターの状態は「キャラクター → 状態」の順に並べる。
func _refresh_condition_editor_visibility() -> void:
	var condition_type := _selected_condition_type()
	_condition_percent_row.visible = condition_type in ["hp_at_most", "hp_at_least"]
	_condition_turn_row.visible = condition_type in ["turn_at", "turn_at_least", "turn_at_most"]
	_condition_n_row.visible = condition_type == "turn_every_n"
	_condition_count_row.visible = condition_type in ["allies_at_most", "allies_at_least", "allies_exactly"]
	var is_character := condition_type in ["character_alive", "character_downed"]
	_condition_character_row.visible = is_character
	## キャラクターの行はいつも最後の行なので、状態（比較方法）はその後ろ（最後）、ほかはカテゴリのすぐ下（1番目）へ。
	_condition_editor.move_child(_condition_compare_row, _condition_editor.get_child_count() - 1 if is_character else 1)

## 入力欄の今の値から条件を作る。必須の値が選べない時も捨てずに返し、保存時に conditions_problem() で止める。
func _build_condition_from_editor() -> Dictionary:
	var condition_type := _selected_condition_type()
	if condition_type.is_empty():
		return {}
	var condition := {"type": condition_type}
	match condition_type:
		"hp_at_most", "hp_at_least":
			condition["percent"] = _condition_percent_spin.value
		"turn_at", "turn_at_least", "turn_at_most":
			condition["turn"] = int(_condition_turn_spin.value)
		"turn_every_n":
			condition["n"] = int(_condition_n_spin.value)
		"allies_at_most", "allies_at_least", "allies_exactly":
			condition["count"] = int(_condition_count_spin.value)
		"character_alive", "character_downed":
			var character_ids: Array = RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys()
			var character_index := _condition_character_option.selected
			if character_index >= 0 and character_index < character_ids.size():
				condition["character_id"] = str(character_ids[character_index])
	return condition

func _remove_condition(index: int) -> void:
	if index < 0 or index >= _pending_conditions.size():
		return
	_pending_conditions.remove_at(index)
	if index == _editing_condition_index:
		_close_condition_editor()
	elif index < _editing_condition_index:
		_editing_condition_index -= 1
	_rebuild_condition_list()

# ---------------------------------------------------------------------------

## Esc（PX-13）: 一覧以外を開いている時は Esc で何もしない（STEP も戻らない。閉じる時は各画面のキャンセルで）。
func escape() -> bool:
	return not _list_view.visible

func is_step_valid() -> bool:
	return draft.step4_advanced_is_valid()

func validation_message() -> String:
	var heal_problems := draft.heal_limit_problems()
	if not heal_problems.is_empty():
		return heal_problems[0]
	if draft.turn_actions.is_empty():
		return tr("通常行動を1ターン以上追加してください")
	for i in range(draft.turn_actions.size()):
		var problem := draft.turn_action_problem(draft.turn_actions[i])
		if not problem.is_empty():
			return tr("%dターン目：%s") % [i + 1, problem]
	if not is_step_valid():
		return tr("行動の設定に不備があります")
	return ""
