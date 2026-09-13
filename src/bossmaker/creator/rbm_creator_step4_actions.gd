class_name RBMCreatorStep4Actions
extends Control

## Creator UI再設計 §6/§7/§8/§9/§10 — SIMPLE「行動」画面: 通常行動・指定行動を
## それぞれ「使う場所で作る」カード形式で表示する。旧実装（STEP3で先に
## スキルを作り、ここでは既存スキル一覧から選ぶだけ）を全面差し替え——
## どちらのカード列も「＋作る」から共通のRBMActionEditorFormを開き、保存
##結果のskill_idをその場で該当データへ書き込むだけで完結する（既存スキル
## から選ぶUIは一切持たない）。
##
## 通常行動の一覧は「draft.normal_action_percentages.keys()」（＝この画面で
## 作られたスキルだけ）を対象にする——draft.skills全件ではない。指定行動/
## ADVANCED経由で作られたスキルが誤って通常行動候補として混入しないための、
## このファイル最大の設計判断（RBMCreatorDraft.add_skill()が
## normal_action_percentagesを自動で先付けしなくなった変更と対になる）。

const TIMING_LABELS := {
	"replace": "通常行動の代わりに使う",
	"turn_start_interrupt": "ターン開始時に追加で使う",
	"turn_end_interrupt": "ターン終了時に追加で使う",
}
const TIMING_ORDER := ["replace", "turn_start_interrupt", "turn_end_interrupt"]

const PERCENT_SLIDER_MIN_SIZE := Vector2(320.0, 28.0)
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

var draft: RBMCreatorDraft
var main: Node

var _scroll_container: ScrollContainer
var _scroll_content: VBoxContainer

var _form: RBMActionEditorForm
var _form_context: String = ""  # "normal" | "scripted" | ""

var _normal_list: VBoxContainer
var _normal_capacity_notice: Label
var _add_normal_button: Button
var _equalize_button: Button
var _percentage_total_label: Label
var _percent_rows: Dictionary = {}  # skill_id -> {"slider":HSlider,"spin":SpinBox}

var _scripted_list: VBoxContainer
var _scripted_capacity_notice: Label
var _add_scripted_button: Button

var _scripted_when_panel: Control
var _scripted_turn_spin: SpinBox
var _scripted_timing_option: OptionButton
var _pending_scripted_editing_index: int = -1  # -1 while creating a NEW scripted action

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "Step3SimpleScroll"
	_scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll_container)

	var margin := MarginContainer.new()
	margin.name = "Step3SimpleScrollMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(CONTENT_SIDE_MARGIN_PX))
	margin.add_theme_constant_override("margin_right", int(CONTENT_SIDE_MARGIN_PX))
	margin.add_theme_constant_override("margin_top", int(CONTENT_TOP_MARGIN_PX))
	margin.add_theme_constant_override("margin_bottom", int(CONTENT_TOP_MARGIN_PX))
	_scroll_container.add_child(margin)

	_scroll_content = VBoxContainer.new()
	_scroll_content.name = "Step3SimpleScrollContent"
	_scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll_content)

	_build_normal_action_area(_scroll_content)
	_build_scripted_action_area(_scroll_content)

	_form = RBMActionEditorForm.new()
	_form.name = "ActionEditorForm"
	_form.setup(draft)
	_form.saved.connect(_on_form_saved)
	_form.cancelled.connect(_on_form_cancelled)
	_scroll_content.add_child(_form)

# ---------------------------------------------------------------------------
# 通常行動（§6/§8）
# ---------------------------------------------------------------------------

func _build_normal_action_area(parent: Control) -> void:
	var header := Label.new()
	header.name = "NormalActionHeader"
	header.text = "通常行動"
	parent.add_child(header)

	_normal_list = VBoxContainer.new()
	_normal_list.name = "NormalActionList"
	parent.add_child(_normal_list)

	var add_row := HBoxContainer.new()
	parent.add_child(add_row)
	_add_normal_button = Button.new()
	_add_normal_button.name = "AddNormalActionButton"
	_add_normal_button.text = "＋ 通常行動を作る"
	_add_normal_button.pressed.connect(_on_add_normal_pressed)
	add_row.add_child(_add_normal_button)
	_equalize_button = Button.new()
	_equalize_button.name = "EqualizeButton"
	_equalize_button.text = "均等にする"
	_equalize_button.pressed.connect(_on_equalize_pressed)
	add_row.add_child(_equalize_button)

	_normal_capacity_notice = Label.new()
	_normal_capacity_notice.name = "NormalActionCapacityNotice"
	_normal_capacity_notice.text = "これ以上ボスの行動を追加できません"
	_normal_capacity_notice.visible = false
	parent.add_child(_normal_capacity_notice)

	_percentage_total_label = Label.new()
	_percentage_total_label.name = "PercentageTotalLabel"
	parent.add_child(_percentage_total_label)

func _on_add_normal_pressed() -> void:
	if not draft.can_add_skill():
		return
	_form_context = "normal"
	_form.open_for_new("通常行動を作る")

func _on_edit_normal_pressed(skill_id: String) -> void:
	_form_context = "normal"
	_form.open_for_editing(skill_id, "通常行動を編集")

## Codexレビュー指摘対応④: 削除は「未参照なら消す」判定へ統一する
## （draft.remove_skill_if_unreferenced()、判定ロジックはRBMCreatorDraft側
## 1箇所に集約）——新モデルでは通常行動として作られたスキルは通常
## normal_action_percentagesからしか参照されないため実質的な挙動は変わら
## ないが、他画面（ADVANCED等）から万一同じskill_idが参照されている異常
## 状態でも誤って削除しない安全側の判定にする。先に「このエントリ自身の
## 参照」（normal_action_percentages内の該当キー）を取り除いてから判定する
## ——でなければ自分自身の参照によって常に「参照あり」と判定されてしまう。
func _on_delete_normal_pressed(skill_id: String) -> void:
	draft.normal_action_percentages.erase(skill_id)
	draft.remove_skill_if_unreferenced(skill_id)
	_sync_normal_actions_enabled_flag()
	main.on_skills_changed()
	refresh()

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

## RBMCreatorDraft.step4_is_valid()/_normal_actions_for_definition()は
## normal_actions_enabledをゲートとして直接参照する既存の（変更禁止の）
## フローズン戦闘ロジック——このフラグ自体は「0%超の重みを持つ通常行動が
## 1つでもあるか」から常にここで自動導出する（ユーザーがON/OFFを直接
## 触るUIは存在しない、前回のUI改善①からの既存方針をそのまま踏襲）。
func _sync_normal_actions_enabled_flag() -> void:
	draft.normal_actions_enabled = draft.normal_action_percentage_total() > 0.0

## refresh()同様、rebuildのたびに毎回作り直す（既存の確立済みパターン——
## 各コントロールの初期.valueをvalue_changed接続より前に設定するため、
## 再構築自体が自己再帰を起こさない、旧実装のコメントと同じ理由）。
## queue_free()だけだと実際のツリー離脱は次のアイドルフレームまで遅延する
## ため、同一フレーム内で「まだ残っている旧ノードと同じname」を持つ新規
## ノードをadd_child()すると、Godotが名前衝突を検知して新ノードを自動
## リネームしてしまう——remove_child()でツリーから即座に切り離してから
## queue_free()することで名前衝突だけを確実に解消する
## （src/bossmaker/creator/rbm_creator_step5_party.gd の refresh() と同じ
## 対策。rbm_creator_step4_action_patterns.gd の各rebuild関数にも同じ
## 修正が必要だった）。
func _rebuild_normal_list() -> void:
	for child in _normal_list.get_children():
		_normal_list.remove_child(child)
		child.queue_free()
	_percent_rows.clear()
	for skill_id_variant in draft.normal_action_percentages.keys():
		var skill_id := str(skill_id_variant)
		var skill := draft.find_skill(skill_id)
		if skill.is_empty():
			continue
		var card := VBoxContainer.new()
		card.name = "NormalActionCard_%s" % skill_id
		_normal_list.add_child(card)

		var name_row := HBoxContainer.new()
		card.add_child(name_row)
		var name_label := Label.new()
		name_label.text = str(skill.get("name", ""))
		name_row.add_child(name_label)
		var edit_button := Button.new()
		edit_button.name = "EditNormalActionButton_%s" % skill_id
		edit_button.text = "編集"
		edit_button.pressed.connect(_on_edit_normal_pressed.bind(skill_id))
		name_row.add_child(edit_button)
		var delete_button := Button.new()
		delete_button.name = "DeleteNormalActionButton_%s" % skill_id
		delete_button.text = "削除"
		delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		delete_button.pressed.connect(_on_delete_normal_pressed.bind(skill_id))
		name_row.add_child(delete_button)

		var detail_label := Label.new()
		detail_label.text = _skill_detail_line(skill)
		card.add_child(detail_label)

		var pct := float(draft.normal_action_percentages.get(skill_id, 0.0))
		var percent_row := HBoxContainer.new()
		card.add_child(percent_row)
		percent_row.add_child(_new_label("使用率"))
		var slider := HSlider.new()
		slider.name = "PercentSlider_%s" % skill_id
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 0.1
		slider.value = pct
		slider.custom_minimum_size = PERCENT_SLIDER_MIN_SIZE
		slider.value_changed.connect(_on_percentage_control_changed.bind(skill_id))
		percent_row.add_child(slider)
		var spin := SpinBox.new()
		spin.name = "PercentSpin_%s" % skill_id
		spin.min_value = 0.0
		spin.max_value = 100.0
		spin.step = 0.1
		spin.value = pct
		spin.value_changed.connect(_on_percentage_control_changed.bind(skill_id))
		percent_row.add_child(spin)
		_percent_rows[skill_id] = {"slider": slider, "spin": spin}

# ---------------------------------------------------------------------------
# 指定行動（§7/§8）— 「いつ使う？」→「何をする？」の2段階フロー。
# ---------------------------------------------------------------------------

func _build_scripted_action_area(parent: Control) -> void:
	var header := Label.new()
	header.name = "ScriptedActionHeader"
	header.text = "指定行動"
	parent.add_child(header)

	_scripted_list = VBoxContainer.new()
	_scripted_list.name = "ScriptedActionList"
	parent.add_child(_scripted_list)

	_add_scripted_button = Button.new()
	_add_scripted_button.name = "AddScriptedActionButton"
	_add_scripted_button.text = "＋ 指定行動を追加"
	_add_scripted_button.pressed.connect(_on_add_scripted_pressed)
	parent.add_child(_add_scripted_button)

	_scripted_capacity_notice = Label.new()
	_scripted_capacity_notice.name = "ScriptedActionCapacityNotice"
	_scripted_capacity_notice.text = "これ以上ボスの行動を追加できません"
	_scripted_capacity_notice.visible = false
	parent.add_child(_scripted_capacity_notice)

	_build_scripted_when_panel(parent)

func _build_scripted_when_panel(parent: Control) -> void:
	_scripted_when_panel = VBoxContainer.new()
	_scripted_when_panel.name = "ScriptedWhenPanel"
	_scripted_when_panel.visible = false
	parent.add_child(_scripted_when_panel)

	var caption := Label.new()
	caption.text = "いつ使う？"
	_scripted_when_panel.add_child(caption)

	var turn_row := HBoxContainer.new()
	_scripted_when_panel.add_child(turn_row)
	turn_row.add_child(_new_label("ターン"))
	_scripted_turn_spin = SpinBox.new()
	_scripted_turn_spin.name = "ScriptedTurnSpin"
	_scripted_turn_spin.min_value = 1
	_scripted_turn_spin.max_value = 999999  # §4-5: no explicit max turn number
	_scripted_turn_spin.step = 1
	turn_row.add_child(_scripted_turn_spin)

	var timing_row := HBoxContainer.new()
	_scripted_when_panel.add_child(timing_row)
	timing_row.add_child(_new_label("タイミング"))
	_scripted_timing_option = OptionButton.new()
	_scripted_timing_option.name = "ScriptedTimingOption"
	for timing in TIMING_ORDER:
		_scripted_timing_option.add_item(str(TIMING_LABELS[timing]))
	timing_row.add_child(_scripted_timing_option)

	var actions_row := HBoxContainer.new()
	_scripted_when_panel.add_child(actions_row)
	var next_button := Button.new()
	next_button.name = "ScriptedWhenNextButton"
	next_button.text = "次へ"
	next_button.pressed.connect(_on_scripted_when_next_pressed)
	actions_row.add_child(next_button)
	var cancel_button := Button.new()
	cancel_button.name = "ScriptedWhenCancelButton"
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_scripted_when_cancel_pressed)
	actions_row.add_child(cancel_button)

func _on_add_scripted_pressed() -> void:
	if not draft.can_add_skill():
		return
	_pending_scripted_editing_index = -1
	_scripted_turn_spin.value = 1
	_scripted_timing_option.select(0)
	_scripted_when_panel.visible = true

func _on_edit_scripted_pressed(index: int) -> void:
	if index < 0 or index >= draft.scripted_actions.size():
		return
	var entry: Dictionary = draft.scripted_actions[index]
	_pending_scripted_editing_index = index
	_scripted_turn_spin.value = float(entry.get("turn", 1))
	_scripted_timing_option.select(maxi(0, TIMING_ORDER.find(str(entry.get("timing", TIMING_ORDER[0])))))
	_scripted_when_panel.visible = true

func _on_scripted_when_cancel_pressed() -> void:
	_scripted_when_panel.visible = false
	_pending_scripted_editing_index = -1

## §8「いつ使う？」の次へ——ここではまだ何もdraftへ書き込まない。実際の
## コミット（add_scripted_action）は「何をする？」フォーム自身の保存時
## （_on_form_saved()）にまとめて行う。編集時は既存skill_idをそのまま
## フォームへ渡す（フォーム側はupdate_skill()で中身だけ書き換え、skill_id
## は変わらない）。
func _on_scripted_when_next_pressed() -> void:
	_scripted_when_panel.visible = false
	_form_context = "scripted"
	if _pending_scripted_editing_index >= 0:
		var entry: Dictionary = draft.scripted_actions[_pending_scripted_editing_index]
		_form.open_for_editing(str(entry.get("skill_id", "")), tr("指定行動を編集"))
	else:
		_form.open_for_new(tr("指定行動を作る"))

func move_scripted_action(index: int, direction: int) -> void:
	draft.move_scripted_action(index, direction)
	refresh()

## Codexレビュー指摘対応④: 上のdelete_normalと同じ理由で「未参照なら消す」
## 判定へ統一する。scripted_actionsからこのエントリ自身を先に取り除いて
## から（draft.remove_scripted_action()）、それでもなお他から参照されて
## いなければ削除する（draft.remove_skill_if_unreferenced()）——順序が
## 逆だと自分自身の参照により常に「参照あり」と判定されてしまう。
func remove_scripted_action(index: int) -> void:
	if index < 0 or index >= draft.scripted_actions.size():
		return
	var skill_id := str(draft.scripted_actions[index].get("skill_id", ""))
	draft.remove_scripted_action(index)
	draft.remove_skill_if_unreferenced(skill_id)
	main.on_skills_changed()
	refresh()

func _rebuild_scripted_list() -> void:
	for child in _scripted_list.get_children():
		_scripted_list.remove_child(child)
		child.queue_free()
	for i in range(draft.scripted_actions.size()):
		var entry: Dictionary = draft.scripted_actions[i]
		var skill := draft.find_skill(str(entry.get("skill_id", "")))
		var card := VBoxContainer.new()
		card.name = "ScriptedActionCard_%d" % i
		_scripted_list.add_child(card)

		var name_row := HBoxContainer.new()
		card.add_child(name_row)
		var label := Label.new()
		label.text = "ターン%d ・ %s ・ %s" % [int(entry.get("turn", 0)), str(skill.get("name", "?")), str(TIMING_LABELS.get(str(entry.get("timing", "")), "?"))]
		name_row.add_child(label)
		var edit_button := Button.new()
		edit_button.name = "EditScriptedActionButton_%d" % i
		edit_button.text = "編集"
		edit_button.pressed.connect(_on_edit_scripted_pressed.bind(i))
		name_row.add_child(edit_button)
		var up_button := Button.new()
		up_button.text = "↑"
		up_button.pressed.connect(move_scripted_action.bind(i, -1))
		name_row.add_child(up_button)
		var down_button := Button.new()
		down_button.text = "↓"
		down_button.pressed.connect(move_scripted_action.bind(i, 1))
		name_row.add_child(down_button)
		var delete_button := Button.new()
		delete_button.name = "DeleteScriptedActionButton_%d" % i
		delete_button.text = "削除"
		delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		delete_button.pressed.connect(remove_scripted_action.bind(i))
		name_row.add_child(delete_button)

		var detail_label := Label.new()
		detail_label.text = _skill_detail_line(skill)
		card.add_child(detail_label)

# ---------------------------------------------------------------------------
# 共通フォーム(RBMActionEditorForm)からのコールバック
# ---------------------------------------------------------------------------

## §6: 通常行動なら「新規作成時だけnormal_action_percentagesへ0%で登録する」
## （編集時は既にエントリがあるのでそのまま——%自体はカード上のスライダーで
## 個別に管理する）。§8: 指定行動なら「いつ使う？」で確定させておいた
## turn/timingと合わせてadd_scripted_action()で一括コミットする（編集時は
## 一旦remove_scripted_action()してから同じskill_idで入れ直し——
## add_scripted_action()自身の「同一(turn,timing)グループを連続配置に保つ」
## 既存不変条件をそのまま再利用するため、直接turnフィールドを書き換えたり
## しない）。
func _on_form_saved(skill_id: String) -> void:
	match _form_context:
		"normal":
			if not draft.normal_action_percentages.has(skill_id):
				draft.normal_action_percentages[skill_id] = 0.0
		"scripted":
			if _pending_scripted_editing_index >= 0:
				draft.remove_scripted_action(_pending_scripted_editing_index)
			var turn := int(_scripted_turn_spin.value)
			var timing: String = TIMING_ORDER[_scripted_timing_option.selected]
			draft.add_scripted_action(turn, skill_id, timing)
			_pending_scripted_editing_index = -1
	_form_context = ""
	_sync_normal_actions_enabled_flag()
	main.on_skills_changed()
	refresh()

func _on_form_cancelled() -> void:
	_form_context = ""
	_pending_scripted_editing_index = -1

# ---------------------------------------------------------------------------

## §8の完成カード例（"炎 / 全体 / 威力120"）に、種類の言葉（攻撃/自己回復/
## ATK自己強化）を先頭に添えたもの——種類を明示した方がカード単体で内容を
## 誤解なく読めるための判断（例のフォーマットと矛盾しない範囲での改善）。
func _skill_detail_line(skill: Dictionary) -> String:
	var type := str(skill.get("type", ""))
	match type:
		"attack":
			var target_label := "単体" if str(skill.get("target", "single")) == "single" else "全体"
			var attribute_id := str(skill.get("attribute", "NEUTRAL"))
			var power := int(round(float(skill.get("atk_multiplier", 1.0)) * 100.0))
			return "攻撃 / %s / %s / 威力%d" % [str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)), target_label, power]
		"self_heal":
			var mode_label := "最大HP割合" if str(skill.get("heal_mode", "fixed")) == "percent" else "固定値"
			if str(skill.get("heal_mode", "fixed")) == "percent":
				return "自己回復 / %s / 最大HPの%.1f%%" % [mode_label, float(skill.get("heal_percent", 0.0))]
			return "自己回復 / %s / HP%d" % [mode_label, int(skill.get("heal_fixed_amount", 0))]
		"atk_self_buff":
			return "ATK自己強化 / ATK×%.2f / %dターン" % [float(skill.get("buff_multiplier", 1.0)), int(skill.get("duration_turns", 1))]
		_:
			return type

func _new_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func refresh() -> void:
	_sync_normal_actions_enabled_flag()
	_rebuild_normal_list()
	_rebuild_scripted_list()
	_add_normal_button.disabled = not draft.can_add_skill()
	_add_scripted_button.disabled = not draft.can_add_skill()
	_normal_capacity_notice.visible = not draft.can_add_skill()
	_scripted_capacity_notice.visible = not draft.can_add_skill()
	var normal_skill_ids: Array = draft.normal_action_percentages.keys()
	if normal_skill_ids.is_empty():
		# §2修正の既存方針を継続: 通常行動0件かつ指定行動0件の時だけ警告する
		# （このボスが実質何もしない状態を明示的に知らせる、純粋な助言——
		# is_step_valid()はこの状態でも真のまま、次へ/TEST BATTLEを塞がない）。
		_percentage_total_label.text = "このボスは行動しません" if draft.scripted_actions.is_empty() else ""
	else:
		var total := draft.normal_action_percentage_total()
		if absf(total - 100.0) < 0.05:
			_percentage_total_label.text = "発動確率の合計: 100.0%"
		else:
			# every literal "%" in a string used as the % operator's left
			# operand must be escaped as "%%" -- not just ones immediately
			# following a format specifier -- or GDScript tries to parse it
			# as the start of an (invalid) format code and throws at runtime.
			_percentage_total_label.text = "発動確率の合計を100%%にしてください（現在%.1f%%）" % total

func is_step_valid() -> bool:
	return draft.step4_is_valid()

func validation_message() -> String:
	if draft.normal_actions_enabled and absf(draft.normal_action_percentage_total() - 100.0) >= 0.05:
		return "発動確率の合計を100%%にしてください（現在%.1f%%）" % draft.normal_action_percentage_total()
	return ""

