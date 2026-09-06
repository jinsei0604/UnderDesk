extends GutTest

## RPG BOSS MAKER Phase 1 Step 4 §13/§18 — SIMPLE Creator UI-driving tests.
## Instantiates the real RBMCreatorMain Control tree (matching this project's
## established pattern of instantiating real UI and driving it via its own
## public methods/signals, not scraping node paths) and exercises every
## STEP's required behavior, plus the full STEP1->TEST BATTLE->REWIND->
## Creatorに戻る->修正->再TEST flow end to end (§18).

## Codexレビュー指摘対応⑪ Node Orphans調査: 原因はこのファイルの本番UI側
## リークではない——RBMCreatorStep5Party/RBMCreatorStep6PartySkillsの
## カード再構築（「10.パーティ/その他画面カード化」ラウンドで導入）は
## queue_free()直後の同名add_child()による名前衝突を避けるため、まず
## remove_child()で即座にツリーから切り離してから改めてqueue_free()する
## 実装になっている——これ自体は正しい修正で、切り離された旧ノードは
## 次のアイドルフレームで確実に解放される（実測: toggle_character()を
## 複数回連続で呼んだ直後はPerformance.OBJECT_ORPHAN_NODE_COUNTが一時的に
## 増えるが、await get_tree().process_frame を1回挟むだけで必ず0へ戻る
## ことをデバッグ用の使い捨てスクリプトで確認済み）。本ファイルは
## toggle_character()等を連続で呼ぶテストが多いにもかかわらずafter_each()
## を持たず、次のテストが始まる前にそのアイドルフレームが処理される保証が
## 無かった——GUTのオーファン集計が「まだ解放されていないだけの正常な
## 一時状態」を誤って検出していた、テスト側のcleanup漏れ（本番UIのリーク
## ではない）と判断した。修正はテストの検証内容を一切変えない、単なる
## 1フレーム分の待機追加のみ。
func after_each() -> void:
	await get_tree().process_frame

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _fill_minimum_valid_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "テストボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

## 実機プレイ改善①: 旧resolve_turn(ally_actions)一括APIの廃止に伴い、
## 「unit id 0はattack、それ以外(id 1)はdefend」という1ラウンド分の入力を、
## SPD順で入力待ちになった味方ごとに逐次act_attack()/act_defend()で解決する
## ヘルパー。ラウンド境界の判定は現在のturnがstart_turnのままか、および
## battle_over/入力待ちの有無を"呼び出しのたび"新しく確認する
## （tests/bossmaker/test_rbm_battle_sequential.gd で確立済みの
## 「1回のadvance呼び出しはラウンド境界をまたぎうる」ことへの対処と同じ
## パターン）。
func _play_one_round_hero_attacks_tank_defends(view: RBMCreatorTestBattleView, start_turn: int) -> void:
	while true:
		if view.session.battle.battle_over or view.session.battle.current_turn != start_turn:
			return
		if not view.session.is_waiting_for_ally_action():
			return
		var unit_id := view.session.pending_ally_id()
		if unit_id == 0:
			view.act_attack(unit_id)
		else:
			view.act_defend(unit_id)

# ---------------------------------------------------------------------------
# STEP 1
# ---------------------------------------------------------------------------

func test_step1_empty_name_blocks_next() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = ""
	assert_false(creator.press_next())
	assert_eq(creator.current_step, 1)

func test_step1_one_char_name_allows_next() -> void:
	var creator := _new_creator()
	var step1: RBMCreatorStep1Basic = creator._step_views[0]
	step1.set_boss_name("A")
	assert_true(creator.press_next())
	assert_eq(creator.current_step, 2)

func test_step1_twenty_char_name_allows_next() -> void:
	var creator := _new_creator()
	var step1: RBMCreatorStep1Basic = creator._step_views[0]
	step1.set_boss_name("A".repeat(20))
	assert_true(creator.press_next())

func test_step1_twenty_one_char_input_is_clamped_to_twenty_and_stays_valid() -> void:
	var creator := _new_creator()
	var step1: RBMCreatorStep1Basic = creator._step_views[0]
	step1.set_boss_name("A".repeat(21))
	assert_eq(creator.draft.boss_name.length(), 20, "the API itself never accepts more than the cap, on top of LineEdit.max_length")
	assert_true(creator.press_next())

func test_step1_appearance_selection_is_retained_across_steps() -> void:
	var creator := _new_creator()
	creator.open_appearance_picker()
	creator._appearance_picker.confirmed.emit("appearance_dragon")
	assert_eq(creator.draft.appearance_id, "appearance_dragon")
	creator.draft.boss_name = "A"
	creator.press_next()
	creator.press_back()
	assert_eq(creator.draft.appearance_id, "appearance_dragon", "appearance choice survives step navigation")

# ---------------------------------------------------------------------------
# STEP 2
# ---------------------------------------------------------------------------

func test_step2_hp_atk_spd_boundaries() -> void:
	var creator := _new_creator()
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	step2.set_hp(RBMDefinitionLoader.BOSS_HP_MIN)
	step2.set_atk(RBMDefinitionLoader.BOSS_ATK_MIN)
	step2.set_spd(RBMDefinitionLoader.BOSS_SPD_MIN)
	assert_true(step2.is_step_valid())
	step2.set_hp(RBMDefinitionLoader.BOSS_HP_MAX)
	step2.set_atk(RBMDefinitionLoader.BOSS_ATK_MAX)
	step2.set_spd(RBMDefinitionLoader.BOSS_SPD_MAX)
	assert_true(step2.is_step_valid())

func test_step2_slider_to_spin_sync() -> void:
	var creator := _new_creator()
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	step2._hp_slider.value = 12345
	assert_eq(int(step2._hp_spin.value), 12345)

func test_step2_spin_to_slider_sync() -> void:
	var creator := _new_creator()
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	step2._hp_spin.value = 54321
	assert_eq(int(step2._hp_slider.value), 54321)

func test_step2_multiple_weak_and_resist_selection() -> void:
	var creator := _new_creator()
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	step2.toggle_weak("FIRE")
	step2.toggle_weak("WIND")
	step2.toggle_resist("ICE")
	step2.toggle_resist("LIGHTNING")
	assert_eq(creator.draft.weak_attributes, ["FIRE", "WIND"])
	assert_eq(creator.draft.resist_attributes, ["ICE", "LIGHTNING"])
	assert_true((step2._weak_buttons["FIRE"] as Button).button_pressed)
	assert_true((step2._resist_buttons["ICE"] as Button).button_pressed)

func test_step2_same_attribute_moves_sides_via_ui() -> void:
	var creator := _new_creator()
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	step2.toggle_weak("FIRE")
	step2.toggle_resist("FIRE")
	assert_false((step2._weak_buttons["FIRE"] as Button).button_pressed)
	assert_true((step2._resist_buttons["FIRE"] as Button).button_pressed)

# ---------------------------------------------------------------------------
# 共通行動作成フォーム (RBMActionEditorForm)
#
# Creator UI再設計 §3: 旧STEP3「ボススキル作成」は廃止された——同じ
# フィールド構築・プレビュー計算ロジックは共通行動作成フォームRBMAction
# EditorFormへそのまま切り出されている（旧STEP3テストが検証していた内容
# はここで直接RBMActionEditorFormをインスタンス化して検証する。「使う場所で
# 作る」新モデルでの実際の呼び出し元(通常行動/指定行動/ADVANCED)からの
# 統合的な確認は、STEP3(旧STEP4)自身のテスト（下）とtest_rbm_advanced_
# creator_ui.gdで行う）。
# ---------------------------------------------------------------------------

func _new_action_form(draft: RBMCreatorDraft) -> RBMActionEditorForm:
	var form := RBMActionEditorForm.new()
	add_child_autofree(form)
	form.setup(draft)
	return form

func test_action_editor_form_attack_skill_via_ui() -> void:
	var draft := RBMCreatorDraft.new()
	var form := _new_action_form(draft)
	form.open_for_new()
	form._name_edit.text = "炎獄斬"
	form._type_option.select(0)
	form._on_type_selected(0)
	form._attack_target_option.select(1)
	form._attack_attribute_option.select(RBMDefinitionLoader.VALID_ATTRIBUTES.find("FIRE"))
	form._attack_multiplier_spin.value = 2.5
	form._on_save_pressed()
	var skill: Dictionary = draft.skills[0]
	assert_eq(str(skill["type"]), "attack")
	assert_eq(str(skill["target"]), "all")
	assert_eq(str(skill["attribute"]), "FIRE")
	assert_eq(float(skill["atk_multiplier"]), 2.5)

func test_action_editor_form_self_heal_fixed_via_ui() -> void:
	var draft := RBMCreatorDraft.new()
	draft.hp = 5000
	var form := _new_action_form(draft)
	form.open_for_new()
	form._name_edit.text = "自己再生"
	form._type_option.select(1)
	form._on_type_selected(1)
	form._self_heal_mode_option.select(0)
	form._on_heal_mode_selected(0)
	form._self_heal_fixed_spin.value = 1000
	form._on_save_pressed()
	assert_eq(int(draft.resolved_heal_amount(draft.skills[0])), 1000)

func test_action_editor_form_self_heal_percent_via_ui() -> void:
	var draft := RBMCreatorDraft.new()
	draft.hp = 5000
	var form := _new_action_form(draft)
	form.open_for_new()
	form._name_edit.text = "自己再生"
	form._type_option.select(1)
	form._on_type_selected(1)
	form._self_heal_mode_option.select(1)
	form._on_heal_mode_selected(1)
	form._self_heal_percent_spin.value = 20.0
	form._on_save_pressed()
	assert_eq(int(draft.resolved_heal_amount(draft.skills[0])), 1000)

func test_action_editor_form_atk_self_buff_via_ui() -> void:
	var draft := RBMCreatorDraft.new()
	draft.atk = 200
	var form := _new_action_form(draft)
	form.open_for_new()
	form._name_edit.text = "怒り"
	form._type_option.select(2)
	form._on_type_selected(2)
	form._atk_buff_multiplier_spin.value = 1.5
	form._atk_buff_duration_spin.value = 3
	form._on_save_pressed()
	var skill: Dictionary = draft.skills[0]
	assert_eq(float(skill["buff_multiplier"]), 1.5)
	assert_eq(int(skill["duration_turns"]), 3)

func test_action_editor_form_boundary_values() -> void:
	var draft := RBMCreatorDraft.new()
	var form := _new_action_form(draft)
	assert_eq(form._attack_multiplier_slider.min_value, 0.0)
	assert_eq(form._attack_multiplier_slider.max_value, 100.0)
	assert_eq(form._self_heal_fixed_slider.min_value, 0.0)
	assert_eq(form._self_heal_fixed_slider.max_value, 1000000.0)
	assert_eq(form._self_heal_percent_slider.min_value, 0.0)
	assert_eq(form._self_heal_percent_slider.max_value, 100.0)
	assert_eq(form._atk_buff_multiplier_slider.min_value, 1.0)
	assert_eq(form._atk_buff_multiplier_slider.max_value, 100.0)
	assert_eq(form._atk_buff_duration_spin.min_value, 1.0)
	assert_eq(form._atk_buff_duration_spin.max_value, 99.0)

func test_action_editor_form_baseline_damage_preview_recalculates_live() -> void:
	var draft := RBMCreatorDraft.new()
	draft.atk = 100
	var form := _new_action_form(draft)
	form.open_for_new()
	form._attack_multiplier_spin.value = 2.0
	form._refresh_attack_preview()
	assert_eq(form._attack_preview_label.text, "基準ダメージ: 200")
	form._attack_multiplier_spin.value = 3.0
	form._refresh_attack_preview()
	assert_eq(form._attack_preview_label.text, "基準ダメージ: 300")

func test_action_editor_form_heal_preview_recalculates_live() -> void:
	var draft := RBMCreatorDraft.new()
	draft.hp = 5000
	var form := _new_action_form(draft)
	form.open_for_new()
	form._self_heal_fixed_spin.value = 1000
	form._refresh_self_heal_preview()
	assert_eq(form._self_heal_fixed_preview_label.text, "最大HPの20.0%相当")

func test_action_editor_form_atk_buff_preview_recalculates_live() -> void:
	var draft := RBMCreatorDraft.new()
	draft.atk = 200
	var form := _new_action_form(draft)
	form.open_for_new()
	form._atk_buff_multiplier_spin.value = 1.5
	form._refresh_atk_buff_preview()
	assert_eq(form._atk_buff_preview_label.text, "強化後ATK: 300")

## §1決定: MAX_SKILLSは64（旧8）。上限へ実際に到達したら「＋通常行動を
## 作る」ボタンが無効化されること——draft-level(上限そのものの判定)は
## test_rbm_creator_draft.gdで既に検証済みのため、ここではUI側の
## disabled連動だけを確認する。
func test_step3_add_normal_action_button_disabled_once_max_skills_reached() -> void:
	var creator := _new_creator()
	var step3_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	for i in range(RBMCreatorDraft.MAX_SKILLS):
		creator.draft.add_skill({"name": "S%d" % i, "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	step3.refresh()
	assert_true(step3._add_normal_button.disabled)
	assert_true(step3._normal_capacity_notice.visible, "「これ以上ボスの行動を追加できません」の案内が出る")

# ---------------------------------------------------------------------------
# STEP 4
# ---------------------------------------------------------------------------

## UI改善①: 「通常行動を使用する」ON/OFFトグルUI自体を削除したため、
## normal_actions_enabledは今やset_percentage()経由で自動的にのみ導出
## される（0%超の重みを持つスキルが1つでもあれば有効、無ければ無効）。
func test_step4_normal_actions_enabled_auto_derives_from_percentages() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	var a := creator.draft.add_skill({"name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	step4.set_percentage(a, 100.0)
	assert_true(creator.draft.normal_actions_enabled, "0%超の重みを設定すると自動的に有効化される")
	step4.set_percentage(a, 0.0)
	assert_false(creator.draft.normal_actions_enabled, "全スキルが0%へ戻れば自動的に無効化される")

func test_step4_percentage_sum_100_valid_under_invalid_over_invalid() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	var a := creator.draft.add_skill({"name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var b := creator.draft.add_skill({"name": "B", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	step4.set_percentage(a, 40.0)
	step4.set_percentage(b, 60.0)
	assert_true(step4.is_step_valid())
	step4.set_percentage(b, 40.0)
	assert_false(step4.is_step_valid(), "80% total must be invalid")
	step4.set_percentage(b, 80.0)
	assert_false(step4.is_step_valid(), "120% total must be invalid")

func test_step4_zero_percent_skill_excluded_from_candidates() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	var a := creator.draft.add_skill({"name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var b := creator.draft.add_skill({"name": "B", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	step4.set_percentage(a, 100.0)
	step4.set_percentage(b, 0.0)
	var boss: Dictionary = creator.draft.to_definition()["boss"]
	var ids: Array = []
	for candidate in boss["normal_actions"]:
		ids.append(str(candidate["skill_id"]))
	assert_eq(ids, [a])

## Creator UI再設計: add_skill()はもうnormal_action_percentagesへ自動登録
## しない（rbm_creator_draft.gd参照）——このテストの意図は「均等にする」
## ボタン自体の計算ロジック確認のため、4体とも通常行動として明示登録して
## から均等にするを押す（実際のUIでは「＋通常行動を作る」経由で自動的に
## 登録される、その結果を模した状態）。
func test_step4_equalize_via_ui() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	for i in range(4):
		var skill_id := creator.draft.add_skill({"name": "S%d" % i, "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
		creator.draft.normal_action_percentages[skill_id] = 0.0
	step4._on_equalize_pressed()
	assert_almost_eq(creator.draft.normal_action_percentage_total(), 100.0, 0.0001)

## Creator UI再設計 §7/§8: 「いつ使う？」（ターン＋タイミング）→「何をする？」
## （共通フォームでその場に新規作成）の2段階フローを、実UIのボタン/シグナル
## 経由で3回通す——指定行動は既存スキルから選ばない（1回ごとに新しい
## スキルが作られる）。
func test_step4_scripted_actions_three_timings_via_ui() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	for timing_index in range(3):
		step4._on_add_scripted_pressed()
		step4._scripted_turn_spin.value = timing_index + 1
		step4._scripted_timing_option.select(timing_index)
		step4._on_scripted_when_next_pressed()
		step4._form._name_edit.text = "S%d" % timing_index
		step4._form._on_save_pressed()
	assert_eq(creator.draft.scripted_actions.size(), 3)
	var timings: Array = []
	for entry in creator.draft.scripted_actions:
		timings.append(str(entry["timing"]))
	assert_eq(timings, ["replace", "turn_start_interrupt", "turn_end_interrupt"])

func test_step4_reorder_via_ui_buttons_generates_order() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	var a := creator.draft.add_skill({"name": "A", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 10, "heal_percent": 0.0})
	var b := creator.draft.add_skill({"name": "B", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": 1})
	creator.draft.add_scripted_action(2, a, "replace")
	creator.draft.add_scripted_action(2, b, "replace")
	step4.move_scripted_action(1, -1)
	creator.draft.party_character_ids = ["hero"]
	var scripted: Array = creator.draft.to_definition()["boss"]["scripted_actions"]
	assert_eq(str(scripted[0]["skill_id"]), b)
	assert_eq(int(scripted[0]["order"]), 1)

func test_step4_normal_off_and_zero_scripted_is_valid() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	creator.draft.add_skill({"name": "S", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	assert_true(step4.is_step_valid())

## §2修正: the warning must key off 通常行動OFF && 指定行動0件 -- NOT off
## "boss.skills is empty" (the previous, incorrect condition). All 3 of the
## required patterns, checked in one continuous walk of the same draft so a
## regression in the boundary between them (not just each state in isolation)
## would also be caught.
func test_step4_no_action_warning_shows_only_when_normal_off_and_zero_scripted() -> void:
	var creator := _new_creator()
	var step4_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step4: RBMCreatorStep4Actions = step4_wrapper._simple_view
	var skill_id := creator.draft.add_skill({"name": "S", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_skill({"name": "T", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_skill({"name": "U", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})

	# 警告される例: boss.skills = 3件, 通常行動OFF, 指定行動0件 -> 警告あり.
	step4.refresh()
	assert_eq(step4._percentage_total_label.text, "このボスは行動しません", "3 boss skills exist, but normal OFF + 0 scripted means none of them ever fires")
	assert_true(step4.is_step_valid(), "still a valid Definition -- advisory only, must not block progression")

	# 警告されない例A: 通常行動ON(0%超の重みを設定すると自動的に有効化される)、
	# 通常行動設定あり、指定行動0件 -> 警告なし.
	step4.set_percentage(skill_id, 100.0)
	assert_ne(step4._percentage_total_label.text, "このボスは行動しません", "normal actions ON with a configured candidate -> no 'boss does nothing' warning")

	# 警告されない例B: 通常行動OFF(全スキルを0%へ戻すと自動的に無効化される)、
	# 指定行動1件以上 -> 警告なし.
	step4.set_percentage(skill_id, 0.0)
	creator.draft.add_scripted_action(1, skill_id, "replace")
	step4.refresh()
	assert_ne(step4._percentage_total_label.text, "このボスは行動しません", "at least 1 scripted action -> no 'boss does nothing' warning even with normal OFF")
	assert_true(step4.is_step_valid())

# ---------------------------------------------------------------------------
# STEP 5
# ---------------------------------------------------------------------------

func test_step5_one_and_four_valid_zero_and_five_invalid_no_duplicates() -> void:
	var creator := _new_creator()
	var step5: RBMCreatorStep5Party = creator._step_views[3]
	assert_false(step5.is_step_valid())
	step5.toggle_character("hero")
	assert_true(step5.is_step_valid())
	step5.toggle_character("butler")
	step5.toggle_character("healer")
	step5.toggle_character("samurai")
	assert_eq(creator.draft.party_character_ids.size(), 4)
	assert_true(step5.is_step_valid())
	step5.toggle_character("tank")  # 5th
	assert_eq(creator.draft.party_character_ids.size(), 4, "a 5th character must not be added")
	step5.toggle_character("hero")  # remove
	step5.toggle_character("hero")  # re-add, not a duplicate now
	assert_eq(creator.draft.party_character_ids.count("hero"), 1)

# ---------------------------------------------------------------------------
# STEP 6
# ---------------------------------------------------------------------------

## Creator UI改修（STEP4統合、2026-09-05）: 旧・独立STEP6「使用可能スキル」
## （RBMCreatorStep6PartySkills）は新STEP4（RBMCreatorStep5Party）へ統合
## されたため、同じ_step_views[3]が両方の役割を持つ。
func test_step6_zero_skills_all_on_all_off_and_no_leak_for_unselected_character() -> void:
	var creator := _new_creator()
	var step5: RBMCreatorStep5Party = creator._step_views[3]
	step5.toggle_character("hero")
	step5.toggle_character("tank")

	step5.set_all_for_character("hero", false)
	assert_true(creator.draft.ally_allowed_skill_ids["hero"].is_empty())
	assert_true(creator.draft.step6_is_valid())

	step5.set_all_for_character("hero", true)
	assert_eq(creator.draft.ally_allowed_skill_ids["hero"], creator.draft.all_master_skill_ids("hero"))

	step5.toggle_character("tank")  # remove tank from the party
	var party_ids: Array = []
	for entry in creator.draft.to_definition()["party"]:
		party_ids.append(str(entry["character_id"]))
	assert_false(party_ids.has("tank"), "a removed character's skill settings never reach the generated Definition")

# ---------------------------------------------------------------------------
# STEP 6 (最終確認、旧STEP7)
# ---------------------------------------------------------------------------

func test_step7_edit_buttons_navigate_to_the_right_step() -> void:
	var creator := _new_creator()
	creator.edit_step(2)
	assert_eq(creator.current_step, 2)
	creator.edit_step(4)
	assert_eq(creator.current_step, 4)

func test_step7_next_from_an_edited_earlier_step_goes_to_the_next_step_not_forced_back() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.go_to_step(RBMCreatorMain.STEP_COUNT)
	creator.has_reached_summary = true
	creator.edit_step(2)  # §7-2 example: edit STEP 2 from the summary
	assert_true(creator.press_next())
	assert_eq(creator.current_step, 3, "次へ from an edited STEP 2 must land on STEP 3, not be forced back to STEP 7")

func test_step7_return_to_summary_only_after_first_reaching_it() -> void:
	var creator := _new_creator()
	assert_false(creator.has_reached_summary)
	assert_false(creator.press_return_to_summary())
	_fill_minimum_valid_boss(creator)
	for i in range(RBMCreatorMain.STEP_COUNT - 1):
		assert_true(creator.press_next())
	assert_true(creator.has_reached_summary)
	creator.press_back()
	assert_true(creator.press_return_to_summary())
	assert_eq(creator.current_step, RBMCreatorMain.STEP_COUNT)

func test_step7_party_damage_preview_and_atk_self_buff_variants_are_shown() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.add_skill({"name": "怒り", "type": "atk_self_buff", "buff_multiplier": 2.0, "duration_turns": 2})
	var step7: RBMCreatorStep7Summary = creator._step_views[4]
	step7.refresh()
	var attack_skill: Dictionary = creator.draft.attack_skills()[0]
	var normal: Dictionary = creator.draft.party_damage_preview(attack_skill, 1.0)
	var buffed: Dictionary = creator.draft.party_damage_preview(attack_skill, 2.0)
	assert_true(int(normal["hero"]) > 0)
	assert_ne(int(normal["hero"]), int(buffed["hero"]), "the buffed preview differs from the normal one")

func test_step7_recalculates_after_editing_atk() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var attack_skill: Dictionary = creator.draft.attack_skills()[0]
	var before: int = creator.draft.party_damage_preview(attack_skill, 1.0)["hero"]
	creator.draft.atk = int(creator.draft.atk * 5)
	var after: int = creator.draft.party_damage_preview(attack_skill, 1.0)["hero"]
	assert_ne(before, after)

## §1修正の再指示: reading Draft dictionaries (as the tests above do) can
## never catch "the setting exists but STEP 7 never actually renders it" --
## these instead walk the REAL, live RBMCreatorStep7Summary Control tree
## after a real refresh() and read actual Label.text values.
##
## Pre-order walk collecting every Label's .text, in the same top-to-bottom
## order they are actually drawn (VBoxContainer children render in child
## order) -- this is what lets _step7_detail_lines_for() below find the
## 1-2 detail lines that immediately FOLLOW one specific skill's own name
## label, i.e. exactly the lines _add_skill_summary() generated for THAT
## skill, not merely "this text appears somewhere on the whole page".
func _collect_label_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		out.append_array(_collect_label_texts(child))
	return out

## Creator UI再設計: STEP7（最終確認）はもう個別スキルの詳細（種類/対象/
## 属性/威力等）を1行ずつ展開しない——その水準の詳細は今やSTEP3「行動」の
## カード自身（_skill_detail_line()）が担う。旧来のテストが検証していた
## 「各設定値が実際にUIへ反映されるか」という関心事自体は変わらないため、
## 対象をSTEP7からSTEP3の通常行動カードへ移した——ここでも実際にUIツリーを
## 歩いてLabel.textを読む方針は維持する（Draft辞書を直接読むだけでは
## 「値はあるが実際には描画されていない」を検出できないため）。
func _step3_detail_line_for(step3: RBMCreatorStep4Actions, skill_name: String) -> String:
	var texts := _collect_label_texts(step3._normal_list)
	var index := texts.find(skill_name)
	assert_true(index != -1, "STEP3 must render a card with exactly the skill's own name: %s" % skill_name)
	if index == -1 or index + 1 >= texts.size():
		return ""
	return texts[index + 1]

func test_step3_renders_attack_skill_target_attribute_and_atk_multiplier() -> void:
	var creator := _new_creator()
	var step3_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	var skill_id := creator.draft.add_skill({"name": "炎獄斬", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.5})
	creator.draft.normal_action_percentages[skill_id] = 100.0
	step3.refresh()
	var line := _step3_detail_line_for(step3, "炎獄斬")
	assert_true(line.contains("攻撃"), "type (攻撃) must be rendered: %s" % line)
	assert_true(line.contains("単体"), "target=single must be rendered as 単体: %s" % line)
	# 実機プレイ改善③ item8/11: 属性は内部ID"FIRE"ではなく日本語ラベル「炎」
	# （RBMDefinitionLoader.ATTRIBUTE_LABELS経由）で表示される。
	assert_true(line.contains("炎"), "attribute must be rendered as its Japanese label: %s" % line)
	assert_true(line.contains("威力150"), "atk_multiplier 1.5 must render as 威力150: %s" % line)

func test_step3_renders_self_heal_mode_and_configured_amount_for_both_fixed_and_percent() -> void:
	var creator := _new_creator()
	var step3_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	var fixed_id := creator.draft.add_skill({"name": "再生", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 1000, "heal_percent": 0.0})
	var percent_id := creator.draft.add_skill({"name": "大回復", "type": "self_heal", "heal_mode": "percent", "heal_fixed_amount": 0, "heal_percent": 20.0})
	creator.draft.normal_action_percentages[fixed_id] = 50.0
	creator.draft.normal_action_percentages[percent_id] = 50.0
	step3.refresh()

	var fixed_line := _step3_detail_line_for(step3, "再生")
	assert_true(fixed_line.contains("自己回復"), "type (自己回復) must be rendered: %s" % fixed_line)
	assert_true(fixed_line.contains("固定値"), "fixed mode must be rendered: %s" % fixed_line)
	assert_true(fixed_line.contains("1000"), "the exact configured fixed heal amount (1000) must be rendered: %s" % fixed_line)

	var percent_line := _step3_detail_line_for(step3, "大回復")
	assert_true(percent_line.contains("自己回復"))
	assert_true(percent_line.contains("最大HP割合"), "percent mode must be rendered: %s" % percent_line)
	assert_true(percent_line.contains("20.0"), "the exact configured percent (20.0) must be rendered: %s" % percent_line)

func test_step3_renders_atk_self_buff_multiplier_and_duration() -> void:
	var creator := _new_creator()
	var step3_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	var skill_id := creator.draft.add_skill({"name": "狂化", "type": "atk_self_buff", "buff_multiplier": 2.0, "duration_turns": 3})
	creator.draft.normal_action_percentages[skill_id] = 100.0
	step3.refresh()
	var line := _step3_detail_line_for(step3, "狂化")
	assert_true(line.contains("ATK自己強化"), "type (ATK自己強化) must be rendered: %s" % line)
	assert_true(line.contains("2.00"), "the exact configured buff_multiplier (2.00) must be rendered: %s" % line)
	assert_true(line.contains("3ターン"), "the exact configured duration_turns (3ターン) must be rendered: %s" % line)

# ---------------------------------------------------------------------------
# STEP 8 / TEST BATTLE
# ---------------------------------------------------------------------------

func test_step8_valid_definition_starts_test_battle() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.go_to_step(RBMCreatorMain.STEP_COUNT)
	var result := creator.press_test_battle()
	assert_true(bool(result.get("ok", false)))
	assert_true(creator._test_battle_view.visible)
	assert_true(creator._test_battle_view.session.start_ok())

func test_step8_invalid_definition_does_not_start_test_battle() -> void:
	var creator := _new_creator()
	# no party at all -> RBMDefinitionLoader must reject this.
	creator.draft.boss_name = "X"
	creator.draft.add_skill({"name": "S", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var result := creator.press_test_battle()
	assert_false(bool(result.get("ok", true)))
	assert_true((result["errors"] as Array).size() > 0)
	assert_false(creator._test_battle_view.visible)

func test_step8_returning_to_creator_preserves_draft_settings() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.go_to_step(RBMCreatorMain.STEP_COUNT)
	creator.press_test_battle()
	var name_before := creator.draft.boss_name
	creator._test_battle_view.return_to_creator_requested.emit()
	assert_eq(creator.draft.boss_name, name_before)
	assert_eq(creator.current_step, RBMCreatorMain.STEP_COUNT)
	assert_false(creator._test_battle_view.visible)

func test_step8_retry_restarts_the_battle() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.go_to_step(RBMCreatorMain.STEP_COUNT)
	creator.press_test_battle()
	var view := creator._test_battle_view
	view.act_defend(view.session.battle.party[0].id)
	assert_true(view.session.reachable_turns().size() > 1)
	view.retry()
	assert_eq(view.session.reachable_turns(), [1])

# ---------------------------------------------------------------------------
# REWIND via the UI layer (logic itself is covered exhaustively in
# test_rbm_battle_snapshot.gd / test_rbm_creator_test_session.gd)
# ---------------------------------------------------------------------------

func test_rewind_button_list_and_rewind_via_ui() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.go_to_step(RBMCreatorMain.STEP_COUNT)
	creator.press_test_battle()
	var view := creator._test_battle_view
	for i in range(3):
		view.act_defend(view.session.battle.party[0].id)
	view.refresh()
	assert_eq(view._rewind_button_by_turn.keys().size(), 4)
	view.rewind_to(1)
	assert_eq(view.session.battle.current_turn, 1)
	assert_eq(view._rewind_button_by_turn.keys().size(), 1, "the rewind list itself shrinks to match the truncated history")

# ---------------------------------------------------------------------------
# §18: full end-to-end flow
# ---------------------------------------------------------------------------

func test_full_end_to_end_flow_step1_through_rewind_and_re_test() -> void:
	var creator := _new_creator()

	# STEP 1
	var step1: RBMCreatorStep1Basic = creator._step_views[0]
	step1.set_boss_name("エンドツーエンド・ボス")
	creator.open_appearance_picker()
	creator._appearance_picker.confirmed.emit("appearance_slime")
	assert_true(creator.press_next())

	# STEP 2
	assert_eq(creator.current_step, 2)
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	step2.set_hp(3000)
	step2.set_atk(150)
	step2.set_spd(80)
	step2.toggle_weak("ICE")
	step2.toggle_resist("FIRE")
	assert_true(creator.press_next())

	# STEP 3（行動、Creator UI再設計で旧STEP3のスキル作成＋旧STEP4の通常
	# 行動割り当てが1つの画面へ統合された——「その場で作る」共通フォーム
	# 経由でスキルを作り、そのままカードの使用率スライダーで100%にする）。
	assert_eq(creator.current_step, 3)
	var step3_wrapper: RBMCreatorStep4 = creator._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	step3._on_add_normal_pressed()
	step3._form._name_edit.text = "爪撃"
	step3._form._type_option.select(0)
	step3._form._on_type_selected(0)
	step3._form._attack_target_option.select(0)
	step3._form._attack_attribute_option.select(RBMDefinitionLoader.VALID_ATTRIBUTES.find("NEUTRAL"))
	step3._form._attack_multiplier_spin.value = 1.0
	step3._form._on_save_pressed()
	assert_eq(creator.draft.skills.size(), 1)
	var skill_id := str(creator.draft.skills[0]["skill_id"])
	step3.set_percentage(skill_id, 100.0)
	assert_true(creator.press_next())

	# STEP 4 (攻略パーティ、Creator UI改修§13/§17で旧「使用可能スキル」STEPを
	# 統合済み——押した「次へ」は直接STEP5「最終確認」へ進む)
	assert_eq(creator.current_step, 4)
	var step4: RBMCreatorStep5Party = creator._step_views[3]
	step4.toggle_character("hero")
	step4.toggle_character("tank")
	assert_true(creator.press_next())

	# STEP 5 (最終確認、旧STEP7)
	assert_eq(creator.current_step, RBMCreatorMain.STEP_COUNT)
	assert_true(creator.has_reached_summary)
	var step5_summary: RBMCreatorStep7Summary = creator._step_views[4]
	step5_summary.refresh()

	# TEST BATTLE
	var start_result := creator.press_test_battle()
	assert_true(bool(start_result.get("ok", false)), "errors: %s" % str(start_result.get("errors", [])))
	var view := creator._test_battle_view
	assert_true(view.visible)

	# a couple of turns
	_play_one_round_hero_attacks_tank_defends(view, 1)
	_play_one_round_hero_attacks_tank_defends(view, 2)
	assert_eq(view.session.battle.current_turn, 3)

	# REWIND back to turn 1
	view.rewind_to(1)
	assert_eq(view.session.battle.current_turn, 1)

	# back to Creator
	view.return_to_creator_requested.emit()
	assert_eq(creator.current_step, RBMCreatorMain.STEP_COUNT)
	assert_eq(creator.draft.boss_name, "エンドツーエンド・ボス", "settings survived the whole trip")

	# 修正: edit STEP 2's HP
	creator.edit_step(2)
	var step2_again: RBMCreatorStep2Stats = creator._step_views[1]
	step2_again.set_hp(9000)
	creator.press_return_to_summary()
	assert_eq(creator.draft.hp, 9000)

	# 再TEST
	var second_start := creator.press_test_battle()
	assert_true(bool(second_start.get("ok", false)))
	assert_eq(creator._test_battle_view.session.battle.boss.max_hp, 9000)
