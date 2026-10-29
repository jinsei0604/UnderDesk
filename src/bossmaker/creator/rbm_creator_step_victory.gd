class_name RBMCreatorStepVictory
extends Control

## RPG BOSS MAKER — HARDCORE だけの STEP「勝利条件」（2026-10-29 ユーザー確定）。行動の次・攻略パーティの前（4STEP目）。
## 挑戦者がどうすれば勝つかを決める（行動の発動条件とは別の項目、draft.victory_condition）。
##   ボスを撃破する（通常・初期値） … ボスの HP を0にすれば勝利
##   指定ターンを生き残る           … 指定したターン目の終わりに味方が1人でも生きていれば勝利。ボスは HP0 でも行動を続ける
## 見た目は STEP2（能力）と同じカードとセクション見出し。選んでいる方は、作成画面のほかの切り替えボタンと同じ水色の枠。

const CONTENT_SIDE_MARGIN_PX := 80.0
const TURNS_SPIN_MIN_SIZE := Vector2(140.0, 0.0)

var draft: RBMCreatorDraft
var main: Node

var _defeat_button: Button
var _survive_button: Button
var _turns_block: VBoxContainer
var _turns_spin: SpinBox

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.name = "VictoryColumn"
	column.anchor_right = 1.0
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.add_theme_constant_override("separation", 24)
	add_child(column)

	var card := PanelContainer.new()
	card.name = "VictoryCard"
	column.add_child(card)
	var card_column := VBoxContainer.new()
	card_column.add_theme_constant_override("separation", 14)
	card.add_child(card_column)
	card_column.add_child(RBMCreatorUiKit.build_section_title(tr("勝利条件")))

	var group := ButtonGroup.new()
	_defeat_button = _choice(card_column, group, "VictoryDefeatBossButton", tr("ボスを撃破する（通常）"), _on_defeat_pressed)
	_note(card_column, tr("ボスの HP を0にすると勝利です。"), "VictoryDefeatBossNote")
	_survive_button = _choice(card_column, group, "VictorySurviveTurnsButton", tr("指定ターンを生き残る"), _on_survive_pressed)
	_note(card_column, tr("指定したターンの終わりまで味方が1人でも生き残れば勝利です。ボスの HP を0にしても戦闘は終わらず、ボスは行動を続けます。途中で味方が全滅すると敗北です。"), "VictorySurviveTurnsNote")

	_turns_block = VBoxContainer.new()
	_turns_block.name = "SurviveTurnsBlock"
	_turns_block.add_theme_constant_override("separation", 8)
	card_column.add_child(_turns_block)
	var turns_row := HBoxContainer.new()
	turns_row.name = "SurviveTurnsRow"
	turns_row.add_theme_constant_override("separation", 12)
	_turns_block.add_child(turns_row)
	var turns_label := Label.new()
	turns_label.text = tr("生き残るターン数")
	turns_row.add_child(turns_label)
	_turns_spin = SpinBox.new()
	_turns_spin.name = "SurviveTurnsSpin"
	_turns_spin.min_value = RBMActionPatternRules.SURVIVE_TURNS_MIN
	_turns_spin.max_value = RBMActionPatternRules.SURVIVE_TURNS_MAX
	_turns_spin.step = 1
	_turns_spin.suffix = tr("ターン")
	_turns_spin.custom_minimum_size = TURNS_SPIN_MIN_SIZE
	_turns_spin.value_changed.connect(_on_turns_changed)
	turns_row.add_child(_turns_spin)
	_note(_turns_block, tr("%d〜%dターン") % [RBMActionPatternRules.SURVIVE_TURNS_MIN, RBMActionPatternRules.SURVIVE_TURNS_MAX], "SurviveTurnsRange")

	## 公開設定との関係（新しい公開項目は作らない）: 既存の「勝利条件」の公開設定でそのまま見せる/隠す。
	_note(column, tr("挑戦する人に勝利条件を見せるかどうかは、最終確認の公開設定「勝利条件」で決められます。"), "VictoryVisibilityNote")

func _choice(parent: Control, group: ButtonGroup, node_name: String, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0.0, 48.0)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b

func _note(parent: Control, text: String, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = RBMCreatorUiKit.VARIATION_SMALL_LABEL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _on_defeat_pressed() -> void:
	draft.set_victory_defeat_boss()
	_changed()

func _on_survive_pressed() -> void:
	draft.set_victory_survive_turns(int(_turns_spin.value) if draft.is_survival_victory() else RBMActionPatternRules.SURVIVE_TURNS_DEFAULT)
	_changed()

func _on_turns_changed(value: float) -> void:
	if not draft.is_survival_victory():
		return
	draft.set_victory_survive_turns(int(value))
	_changed()

func _changed() -> void:
	refresh()
	if is_instance_valid(main) and main.has_method("_refresh"):
		main.call("_refresh")

func refresh() -> void:
	var survive := draft.is_survival_victory()
	_defeat_button.set_pressed_no_signal(not survive)
	_survive_button.set_pressed_no_signal(survive)
	_turns_block.visible = survive
	_turns_spin.set_value_no_signal(draft.survive_turns() if survive else RBMActionPatternRules.SURVIVE_TURNS_DEFAULT)
	## 選んでいる方は、作成画面のほかの切り替えボタン（STEP2 の弱点など）と同じ水色の枠（RBMWorldUi の枠）。
	var world: Variant = main.get("_world_ui") if is_instance_valid(main) else null
	if world != null:
		var selected_box: StyleBox = world.frame(Color("102a2e"), Color("43efff"))
		for b in [_defeat_button, _survive_button]:
			(b as Button).add_theme_stylebox_override("pressed", selected_box)
			(b as Button).add_theme_stylebox_override("hover_pressed", selected_box)

func is_step_valid() -> bool:
	if not draft.is_survival_victory():
		return true
	var turns := draft.survive_turns()
	return turns >= RBMActionPatternRules.SURVIVE_TURNS_MIN and turns <= RBMActionPatternRules.SURVIVE_TURNS_MAX

func validation_message() -> String:
	return "" if is_step_valid() else tr("生き残るターン数を%d〜%dで設定してください") % [RBMActionPatternRules.SURVIVE_TURNS_MIN, RBMActionPatternRules.SURVIVE_TURNS_MAX]
