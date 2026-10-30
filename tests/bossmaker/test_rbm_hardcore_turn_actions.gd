extends GutTest

## HARDCORE の通常行動＝ターンごとの行動（2026-10-28 ユーザー確定仕様・案A）のテスト。
## - N ターン目には N 番目の設定を使い、最後の次は1ターン目へ戻る（位置がずれない）
## - 決め方は「確定」「使用率で抽選」「条件で分岐（上から順に最初に満たしたもの、どれも満たさなければそれ以外）」
## - 使用率は抽選の候補だけに出し、確定・条件の行動には出さない（100% も出さない）
## - 見出し「通常行動」「ターン開始・終了時に追加する行動」「覚醒」と仕切り線、「ランダム攻撃を作る」は無い

const DEFEND := {"type": "defend"}

func after_each() -> void:
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# 戦闘（解決済みの boss_def を直接渡す。test_rbm_advanced_battle.gd と同じ慣習）
# ---------------------------------------------------------------------------

func _party_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json"))
	return out

func _boss_def(turn_actions: Array, extra := {}) -> Dictionary:
	var def := {
		"id": "turn_boss", "display_name": "TurnBoss", "hp": 1000, "atk": 1, "spd": 10,
		"skills": [
			{"id": "boss_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "boss_hit2", "display_name": "Hit2", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "boss_aoe", "display_name": "AoE", "effect": "damage", "target": "ally_all", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "boss_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 50},
		],
		"normal_action_candidates": [],
		"turn_actions": turn_actions,
	}
	def.merge(extra, true)
	return def

func _fixed(skill_id: String) -> Dictionary:
	return {"mode": "fixed", "entries": [{"skill_id": skill_id}]}

func _boss_skill_ids_of_one_round(battle: RBMBattle) -> Array:
	var log: Array = []
	var start_turn := battle.current_turn
	while true:
		log.append_array(battle.advance_to_next_decision())
		if battle.battle_over or battle.current_turn != start_turn or not battle.is_waiting_for_ally_action():
			break
		log.append_array(battle.resolve_pending_ally_action(DEFEND))
	var out: Array = []
	for entry in log:
		if str(entry.get("actor", "")) == "boss":
			out.append(str(entry.get("skill_id", "")))
	return out

## ユーザーの例そのまま: 1ターン目 単体・2ターン目 50%/50%・3ターン目 全体・4ターン目 HP50%以下なら回復、それ以外なら単体。
## 2ターン目にどちらが選ばれても3ターン目は必ず全体攻撃。4ターン目の次は1ターン目へ戻る。
func test_each_battle_turn_uses_its_own_setting_and_loops_back_to_turn_one() -> void:
	var turns := [
		_fixed("boss_hit"),
		{"mode": "random", "entries": [{"skill_id": "boss_hit2", "weight": 50.0}, {"skill_id": "boss_heal", "weight": 50.0}]},
		_fixed("boss_aoe"),
		{"mode": "conditional", "entries": [{"skill_id": "boss_heal", "conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND"}], "else_skill_id": "boss_hit"},
	]
	for rng_seed in [1, 2, 3, 4, 5, 6]:
		var battle := RBMBattle.new(_party_defs(), _boss_def(turns), rng_seed)
		var seen := []
		for _i in range(8):
			seen.append(_boss_skill_ids_of_one_round(battle))
		assert_eq(seen[0], ["boss_hit"], "1ターン目")
		assert_true(seen[1] == ["boss_hit2"] or seen[1] == ["boss_heal"], "2ターン目は抽選: %s" % [seen[1]])
		assert_eq(seen[2], ["boss_aoe"], "2ターン目の結果に関係なく3ターン目は全体攻撃")
		assert_eq(seen[3], ["boss_hit"], "HPが満タンなので『それ以外』")
		assert_eq(seen[4], ["boss_hit"], "5ターン目は1ターン目へ戻る")
		assert_eq(seen[6], ["boss_aoe"], "7ターン目は3ターン目と同じ")

func test_conditional_uses_the_first_matching_condition_from_the_top() -> void:
	var turns := [{"mode": "conditional", "entries": [
		{"skill_id": "boss_heal", "conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND"},
		{"skill_id": "boss_hit2", "conditions": [{"type": "hp_at_most", "percent": 80.0}], "condition_logic": "AND"},
	], "else_skill_id": "boss_hit"}]
	var battle := RBMBattle.new(_party_defs(), _boss_def(turns), 1)
	battle.boss.hp = 300
	assert_eq(_boss_skill_ids_of_one_round(battle), ["boss_heal"], "HP30%は両方の条件を満たすが、上の条件が先")
	battle.boss.hp = 700
	assert_eq(_boss_skill_ids_of_one_round(battle), ["boss_hit2"])
	battle.boss.hp = 1000
	assert_eq(_boss_skill_ids_of_one_round(battle), ["boss_hit"], "どれも満たさなければ『それ以外』")

func test_random_turn_draws_by_usage_rate() -> void:
	var turns := [{"mode": "random", "entries": [{"skill_id": "boss_hit", "weight": 0.0}, {"skill_id": "boss_hit2", "weight": 100.0}]}]
	var battle := RBMBattle.new(_party_defs(), _boss_def(turns), 7)
	for _i in range(4):
		assert_eq(_boss_skill_ids_of_one_round(battle), ["boss_hit2"])

## ターンごとの行動があれば、旧方式（action_sequence）と SIMPLE の通常行動・置き換えの指定行動は使わない。
## ターン開始・終了時に追加する行動は今までどおり別に動く。
func test_turn_actions_win_over_old_sequence_and_simple_but_turn_start_extra_still_fires() -> void:
	var def := _boss_def([_fixed("boss_aoe")], {
		"normal_action_candidates": [{"skill_id": "boss_hit", "weight": 100.0}],
		"action_sequence": [{"slot_id": "s1", "kind": "skill", "skill_id": "boss_hit2", "conditions": [], "condition_logic": "AND", "max_uses": -1}],
		"scripted_actions": [
			{"turn": 1, "skill_id": "boss_hit", "timing": "replace", "order": 0},
			{"turn": 1, "skill_id": "boss_heal", "timing": "turn_start_interrupt", "order": 0},
		],
	})
	var battle := RBMBattle.new(_party_defs(), def, 1)
	var ids := _boss_skill_ids_of_one_round(battle)
	assert_true(ids.has("boss_aoe"), "ターンごとの行動を使う: %s" % [ids])
	assert_false(ids.has("boss_hit2"), "旧方式は使わない")
	assert_true(ids.has("boss_heal"), "ターン開始時に追加する行動は動く")

# ---------------------------------------------------------------------------
# 下書き・定義・保存
# ---------------------------------------------------------------------------

func _draft() -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = "ターンのボス"
	d.appearance_id = "appearance_dragon"
	d.hp = 1000
	d.atk = 100
	d.spd = 50
	d.add_skill({"name": "単体攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	d.add_skill({"name": "全体攻撃", "type": "attack", "target": "all", "attribute": "FIRE", "atk_multiplier": 0.8})
	d.add_skill({"name": "回復", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 100})
	d.add_party_character("hero")
	d.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	return d

func _sid(d: RBMCreatorDraft, index: int) -> String:
	return str(d.skills[index].get("skill_id", ""))

func _example_turns(d: RBMCreatorDraft) -> Array:
	return [
		{"mode": "fixed", "entries": [{"skill_id": _sid(d, 0)}]},
		{"mode": "random", "entries": [{"skill_id": _sid(d, 0), "weight": 50.0}, {"skill_id": _sid(d, 2), "weight": 50.0}]},
		{"mode": "fixed", "entries": [{"skill_id": _sid(d, 1)}]},
		{"mode": "conditional", "entries": [{"skill_id": _sid(d, 2), "conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND"}], "else_skill_id": _sid(d, 0)},
	]

## 2026-10-29 ユーザー確定: 行動が0件でも完成できる（ターンが無いボスは行動しない）。ターンがあれば、その中身は今までどおり検証する。
func test_hardcore_allows_no_turns_but_still_checks_each_turn() -> void:
	var d := _draft()
	assert_true(d.step4_advanced_is_valid(), "ターンが1つも無くても次へ進める（2026-10-29）")
	d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(d, 0)}]})
	assert_true(d.step4_advanced_is_valid())
	d.add_turn_action({"mode": "random", "entries": [{"skill_id": _sid(d, 0), "weight": 100.0}]})
	assert_false(d.step4_advanced_is_valid(), "抽選は2つ以上")
	d.update_turn_action(1, {"mode": "random", "entries": [{"skill_id": _sid(d, 0), "weight": 60.0}, {"skill_id": _sid(d, 2), "weight": 30.0}]})
	assert_false(d.step4_advanced_is_valid(), "使用率の合計は100")
	d.update_turn_action(1, {"mode": "conditional", "entries": [{"skill_id": _sid(d, 2), "conditions": [{"type": "hp_at_most", "percent": 50.0}]}]})
	assert_false(d.step4_advanced_is_valid(), "条件で分岐は『それ以外』が必要")
	d.update_turn_action(1, {"mode": "conditional", "entries": [{"skill_id": _sid(d, 2), "conditions": []}], "else_skill_id": _sid(d, 0)})
	assert_false(d.step4_advanced_is_valid(), "条件の行は条件が1つ以上")

func test_definition_round_trips_through_the_loader_and_battle() -> void:
	var d := _draft()
	for turn in _example_turns(d):
		d.add_turn_action(turn)
	assert_true(d.step4_advanced_is_valid())
	var definition := d.to_definition()
	assert_eq((definition["boss"]["turn_actions"] as Array).size(), 4)
	var result := RBMDefinitionLoader.resolve(definition)
	assert_true(bool(result.get("ok", false)), "読み込みのエラーが無い: %s" % [result.get("errors", [])])
	var boss_def: Dictionary = result.get("boss_def", {})
	assert_eq((boss_def.get("turn_actions", []) as Array).size(), 4)
	assert_eq(str(boss_def["turn_actions"][3]["else_skill_id"]), _sid(d, 0))

func test_snapshot_has_no_turn_actions_key_when_unused_so_old_clear_records_stay_valid() -> void:
	var d := RBMCreatorDraft.new()
	assert_false(d.battle_content_snapshot().has("turn_actions"))
	var hd := _draft()
	hd.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(hd, 0)}]})
	assert_true(hd.battle_content_snapshot().has("turn_actions"))
	hd.record_clear_check_success()
	var saved := hd.clear_check_snapshot_for_save()
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(hd.to_saved_dict())
	restored.restore_clear_check_snapshot(JSON.parse_string(JSON.stringify(saved)))
	assert_true(restored.is_clear_check_currently_valid(), "保存・読み込みの後もクリアチェックは有効")

func test_save_and_load_keep_the_turns() -> void:
	var d := _draft()
	for turn in _example_turns(d):
		d.add_turn_action(turn)
	var data: Dictionary = JSON.parse_string(JSON.stringify(d.to_saved_dict()))
	assert_true(RBMLocalStageRepository.validate_draft_shape_for_online(data))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(data)
	assert_eq(restored.turn_actions, d.turn_actions)

func test_adding_a_turn_clears_the_old_sequence_and_skills_in_turns_are_not_deleted() -> void:
	var d := _draft()
	d.add_action_slot({"kind": "skill", "skill_id": _sid(d, 0), "conditions": [], "condition_logic": "AND", "max_uses": -1})
	d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(d, 1)}]})
	assert_eq(d.action_sequence.size(), 0, "旧方式は残さない")
	d.remove_skill_if_unreferenced(_sid(d, 1))
	assert_false(d.find_skill(_sid(d, 1)).is_empty(), "ターンで使っている行動は消えない")

# ---------------------------------------------------------------------------
# 画面
# ---------------------------------------------------------------------------

func _view() -> RBMCreatorStep4ActionPatterns:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	creator.draft.boss_name = "画面のボス"
	creator.draft.appearance_id = "appearance_dragon"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "単体攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_skill({"name": "回復", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 100})
	creator.draft.add_party_character("hero")
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.go_to_step(3)
	var step: RBMCreatorStep4 = creator._step_views[2]
	step.refresh()
	return step._advanced_view

func _btn(node: Node, button_name: String) -> Button:
	var found := node.find_child(button_name, true, false) as Button
	assert_not_null(found, "button %s" % button_name)
	return found

func _click(node: Node, card_name: String) -> void:
	var card := node.find_child(card_name, true, false) as Control
	assert_not_null(card, "card %s" % card_name)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)

func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out

func test_list_has_three_headed_sections_with_separators_and_no_random_attack_choice() -> void:
	var view := _view()
	assert_eq((view.find_child("NormalActionsHeader", true, false) as Label).text, tr("通常行動"))
	assert_eq((view.find_child("ExtraActionsHeader", true, false) as Label).text, tr("ターン開始・終了時に追加する行動"))
	assert_eq((view.find_child("AwakeningHeader", true, false) as Label).text, tr("覚醒"))
	assert_not_null(view.find_child("ExtraActionsSeparator", true, false))
	assert_not_null(view.find_child("AwakeningSeparator", true, false))
	assert_null(view.find_child("AddChoiceCreateRandomButton", true, false), "「ランダム攻撃を作る」は無い")
	for b in view.find_children("*", "Button", true, false):
		assert_false((b as Button).text.contains(tr("ランダム攻撃")), (b as Button).text)
	assert_true(view.is_step_valid(), "ターンが無くても次へ進める（2026-10-29）")
	assert_eq((view.find_child("TurnLoopNote", true, false) as Label).text, tr("このボスは行動しません"), "何も無い時は、ボスが行動しないことを知らせる")

## ％は抽選の候補だけ（50%・50%）。確定・条件で決まる行動には出さない（100% も出さない）。
func test_usage_rate_is_shown_only_for_random_turns() -> void:
	var view := _view()
	var d := view.draft
	d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(d, 0)}]})
	d.add_turn_action({"mode": "random", "entries": [{"skill_id": _sid(d, 0), "weight": 50.0}, {"skill_id": _sid(d, 1), "weight": 50.0}]})
	d.add_turn_action({"mode": "conditional", "entries": [{"skill_id": _sid(d, 1), "conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND"}], "else_skill_id": _sid(d, 0)})
	view.refresh()
	var random_texts := _texts(view.find_child("TurnCard_1", true, false))
	assert_eq(random_texts.count(tr("使用率 %.1f%%") % 50.0), 2, "抽選の候補は両方に％: %s" % [random_texts])
	for card_name in ["TurnCard_0", "TurnCard_2"]:
		for text in _texts(view.find_child(card_name, true, false)):
			assert_false(text.contains(tr("使用率")), "%s に使用率を出さない: %s" % [card_name, text])
			assert_false(text.contains("100%") or text.contains("100.0%"), "%s に100%%を出さない: %s" % [card_name, text])
	assert_true(view.is_step_valid())

func test_add_a_fixed_turn_by_creating_a_new_action_then_switch_it_to_random() -> void:
	var view := _view()
	var d := view.draft
	_btn(view, "AddTurnButton").pressed.emit()
	assert_true(view._turn_view.visible)
	assert_true(_btn(view, "TurnModeButton_fixed").button_pressed, "最初は確定")
	_btn(view, "AddTurnEntryButton").pressed.emit()
	_btn(view, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(view._entry_view.visible)
	view._form._name_edit.text = "かみつき"
	_btn(view, "EntryConfirmButton").pressed.emit()
	assert_true(view._turn_view.visible)
	_btn(view, "TurnConfirmButton").pressed.emit()
	assert_true(view._list_view.visible)
	assert_eq(d.turn_actions.size(), 1)
	assert_eq(str(d.turn_actions[0]["mode"]), "fixed")
	assert_eq(str(d.find_skill(str(d.turn_actions[0]["entries"][0]["skill_id"])).get("name", "")), "かみつき")
	# カードを押してターンの設定を開き、使用率で抽選へ切り替えて既存の行動を候補に足す
	_click(view, "TurnCard_0")
	assert_true(view._turn_view.visible)
	_btn(view, "TurnModeButton_random").pressed.emit()
	_btn(view, "AddTurnEntryButton").pressed.emit()
	_btn(view, "AddChoicePickExistingButton").pressed.emit()
	_click(view, "PickExistingSkillCard_1")
	assert_true(view._weight_block.visible, "抽選の候補は詳細画面で使用率を決める")
	_btn(view, "EntryConfirmButton").pressed.emit()
	_btn(view, "EqualizeTurnButton").pressed.emit()
	_btn(view, "TurnConfirmButton").pressed.emit()
	assert_eq(str(d.turn_actions[0]["mode"]), "random")
	var weights := []
	for entry in d.turn_actions[0]["entries"]:
		weights.append(float(entry["weight"]))
	assert_eq(weights, [50.0, 50.0])

func test_conditional_turn_is_built_on_the_detail_screen_with_an_otherwise_action() -> void:
	var view := _view()
	var d := view.draft
	d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(d, 1)}]})
	view.refresh()
	_click(view, "TurnCard_0")
	_btn(view, "TurnModeButton_conditional").pressed.emit()
	_btn(view, "TurnConfirmButton").pressed.emit()
	assert_true((view.find_child("TurnProblemLabel", true, false) as Label).visible, "条件と『それ以外』が無いと保存できない")
	_click(view, "TurnEntryCard_0")
	assert_true(view._condition_block.visible, "条件は行動の詳細で決める")
	assert_false(view._weight_block.visible)
	_btn(view, "AddConditionButton").pressed.emit()
	view._condition_percent_spin.value = 50.0
	_btn(view, "EntryConfirmButton").pressed.emit()
	_click(view, "TurnElseCard")
	_btn(view, "AddChoicePickExistingButton").pressed.emit()
	_click(view, "PickExistingSkillCard_0")
	_btn(view, "EntryConfirmButton").pressed.emit()
	_btn(view, "TurnConfirmButton").pressed.emit()
	assert_true(view._list_view.visible)
	var turn: Dictionary = d.turn_actions[0]
	assert_eq(str(turn["mode"]), "conditional")
	assert_eq(turn["entries"][0]["conditions"], [{"type": "hp_at_most", "percent": 50.0}])
	assert_eq(str(turn["else_skill_id"]), _sid(d, 0))

func test_cancel_restores_actions_created_while_editing_a_turn() -> void:
	var view := _view()
	var d := view.draft
	var before := d.skills.size()
	_btn(view, "AddTurnButton").pressed.emit()
	_btn(view, "AddTurnEntryButton").pressed.emit()
	_btn(view, "AddChoiceCreateNewButton").pressed.emit()
	view._form._name_edit.text = "取り消す技"
	_btn(view, "EntryConfirmButton").pressed.emit()
	_btn(view, "TurnCancelButton").pressed.emit()
	assert_eq(d.skills.size(), before, "作った行動は残らない")
	assert_eq(d.turn_actions.size(), 0)

func test_extra_action_at_turn_start_is_added_from_its_own_section() -> void:
	var view := _view()
	var d := view.draft
	_btn(view, "AddExtraActionButton").pressed.emit()
	_btn(view, "AddChoicePickExistingButton").pressed.emit()
	_click(view, "PickExistingSkillCard_1")
	assert_true(view._extra_block.visible)
	view._extra_turn_spin.value = 3
	view._extra_timing_option.select(0)
	_btn(view, "EntryConfirmButton").pressed.emit()
	assert_eq(d.scripted_actions, [{"turn": 3, "skill_id": _sid(d, 1), "timing": "turn_start_interrupt"}])
	assert_not_null(view.find_child("ExtraActionCard_0", true, false))

# ---------------------------------------------------------------------------
# ターンの並べ替え（2026-10-29 ユーザー指示: カードの右の四方向矢印のつまみを長押ししてドラッグ。挿入型で、
# 2つを入れ替えるのではない。ほかのカードは自動で詰める）
# ---------------------------------------------------------------------------

func test_moving_a_turn_inserts_it_and_shifts_the_others_instead_of_swapping() -> void:
	var d := _draft()
	for i in range(3):
		d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(d, i)}]})
	d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(d, 0)}]})
	var before := d.turn_actions.duplicate(true)
	assert_true(d.move_turn_action(0, 2))
	assert_eq(d.turn_actions, [before[1], before[2], before[0], before[3]], "A,B,C,D → B,C,A,D")
	assert_true(d.move_turn_action(3, 0))
	assert_eq(d.turn_actions, [before[3], before[1], before[2], before[0]], "B,C,A,D → D,B,C,A")
	assert_false(d.move_turn_action(1, 1))
	assert_false(d.move_turn_action(0, 9))

func _mouse(button_pressed: bool, global_pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = button_pressed
	e.global_position = global_pos
	return e

func _motion(global_pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.global_position = global_pos
	return e

func _view_with_four_turns() -> RBMCreatorStep4ActionPatterns:
	var view := _view()
	var d := view.draft
	d.add_skill({"name": "全体攻撃", "type": "attack", "target": "all", "attribute": "FIRE", "atk_multiplier": 0.8})
	for i in [0, 1, 2, 0]:
		d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": _sid(d, i)}]})
	view.refresh()
	return view

func test_each_turn_card_has_a_move_handle_with_the_four_way_arrow_on_its_right() -> void:
	var view := _view_with_four_turns()
	await get_tree().process_frame
	for i in range(4):
		var handle := view.find_child("TurnMoveHandle_%d" % i, true, false) as RBMTurnMoveHandle
		assert_not_null(handle, "handle %d" % i)
		assert_eq(handle.mouse_filter, Control.MOUSE_FILTER_STOP, "the handle takes the press (the card does not open)")
		assert_not_null(handle.icon, "four-way arrow icon")
		var row := handle.get_parent()
		assert_eq(handle.get_index(), row.get_child_count() - 1, "on the right of the action")
	var icon_image := RBMTurnMoveHandle.move_icon(Color.WHITE).get_image()
	for p in [Vector2i(7, 1), Vector2i(1, 7), Vector2i(13, 7), Vector2i(7, 13), Vector2i(7, 7)]:
		assert_gt(icon_image.get_pixelv(p).a, 0.5, "arrow tips up/left/right/down and the center: %s" % p)
	assert_eq(icon_image.get_pixelv(Vector2i(1, 1)).a, 0.0, "corners stay empty (a cross, not a box)")

func test_long_press_and_drag_inserts_the_turn_and_renumbers_while_dragging() -> void:
	var view := _view_with_four_turns()
	var d := view.draft
	var before := d.turn_actions.duplicate(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var handle := view.find_child("TurnMoveHandle_0", true, false) as RBMTurnMoveHandle
	var card := view.find_child("TurnCard_0", true, false) as Control
	var start := handle.get_global_rect().get_center()
	handle._gui_input(_mouse(true, start))
	await get_tree().create_timer(RBMTurnMoveHandle.LONG_PRESS_SEC + 0.15).timeout
	assert_true(handle.is_dragging(), "long press starts the drag")
	var third := view.find_child("TurnCard_2", true, false) as Control
	var below_third := Vector2(start.x, third.get_global_rect().end.y - 4.0)
	handle._gui_input(_motion(below_third))
	assert_eq(card.get_index(), 2, "the dragged card is inserted at the pointer and the others close up")
	assert_eq(((card.get_meta("turn_title") as Label).text), tr("%dターン目") % 3, "renumbered while dragging")
	assert_eq(((view.find_child("TurnCard_1", true, false) as Control).get_meta("turn_title") as Label).text, tr("%dターン目") % 1)
	assert_eq(d.turn_actions, before, "the draft changes only when released")
	handle._gui_input(_mouse(false, below_third))
	assert_eq(d.turn_actions, [before[1], before[2], before[0], before[3]], "insert, not swap")
	assert_true(view._list_view.visible, "dragging does not open the turn")

func test_a_short_press_on_the_handle_does_nothing() -> void:
	var view := _view_with_four_turns()
	var d := view.draft
	var before := d.turn_actions.duplicate(true)
	await get_tree().process_frame
	var handle := view.find_child("TurnMoveHandle_1", true, false) as RBMTurnMoveHandle
	var pos := handle.get_global_rect().get_center()
	handle._gui_input(_mouse(true, pos))
	handle._gui_input(_motion(pos + Vector2(0, 300)))
	handle._gui_input(_mouse(false, pos + Vector2(0, 300)))
	await get_tree().create_timer(RBMTurnMoveHandle.LONG_PRESS_SEC + 0.15).timeout
	assert_false(handle.is_dragging())
	assert_eq(d.turn_actions, before)
	assert_true(view._list_view.visible, "a press on the handle does not open the turn")
