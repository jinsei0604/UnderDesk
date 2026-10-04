extends Node

## Creator内の不要な横スクロール/横幅はみ出しの実機(実GPU)監査。
##
## 実行はtools/gpu_runner.tscn経由(README参照)。STEP1〜5(SIMPLE/HARDCORE)、
## HARDCORE STEP3の各サブ画面(一覧/新規作成フォーム/ランダム/条件エディタ全種/
## 覚醒)、外見選択、最終確認、TEST BATTLE等を1280x720で順に開き、可視の
## ScrollContainerごとに「横スクロール可能か(範囲)」「横スクロールバーの表示」
## 「子の最小幅と表示幅」、および画面外(x>1280)へはみ出す可視Controlを報告する。
## 出力: 標準出力に`HSA`から始まる行、および各画面のスクリーンショット。

const SCREEN_W := 1280.0
const LONG_NAME := "とても長い名前の行動あいうえおかきくけこ"
const LONG_BOSS_NAME := "とても長い名前のボスあいうえおかきくけこさしすせそたちつてと"

var _gpu_verification_completed := false
var _tree: SceneTree
var _root: RBMGameRoot
var _main: RBMCreatorMain
var _out := ""
var _shot_index := 0
var _issues := 0

func run_gpu_verification(tree: SceneTree, output_dir: String) -> int:
	_tree = tree
	_out = output_dir
	if not DirAccess.dir_exists_absolute(_out):
		DirAccess.make_dir_recursive_absolute(_out)
	RBMLocalStageRepository.set_stages_dir_for_testing("user://bossmaker_hsa_audit")

	_root = RBMGameRoot.new()
	tree.root.add_child(_root)
	for i in range(4):
		await tree.process_frame
	_root._top_monitor_battle.stop_loop()

	for mode in ["advanced", "simple"]:
		await _open_creator(mode)
		await _audit_steps(mode)
		if mode == "advanced":
			await _audit_advanced_step3()
		else:
			await _audit_simple_step3()
		await _audit_subscreens(mode)

	print("HSA_DONE issues=%d" % _issues)
	_gpu_verification_completed = true
	return 0

# ---------------------------------------------------------------------------

func _frames(n: int = 3) -> void:
	for i in range(n):
		await _tree.process_frame

func _open_creator(mode: String) -> void:
	_root._show_only(_root.creator_entry)
	_root.creator_entry.enter_create()
	_root.creator_entry._on_new_pressed()
	if mode == "advanced":
		_root.creator_entry._on_choose_advanced_mode_pressed()
	else:
		_root.creator_entry._on_choose_simple_mode_pressed()
	_main = _root.creator_entry.main
	_main.draft.boss_name = LONG_BOSS_NAME
	_main.draft.hp = 2000
	_main.draft.atk = 100
	_main.draft.spd = 50
	_main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	_main.draft.add_skill({"name": LONG_NAME, "type": "attack", "target": "all", "attribute": "FIRE", "atk_multiplier": 1.5})
	_main.draft.add_party_character("hero")
	_main.draft.add_party_character("butler")
	_main.draft.add_party_character("samurai")
	_main.draft.add_party_character("healer")
	_main._refresh()
	await _frames()

func _btn(node: Node, button_name: String) -> Button:
	var found := node.find_child(button_name, true, false) as Button
	if found == null:
		print("HSA_WARN button not found: %s" % button_name)
	return found

func _press(node: Node, button_name: String) -> void:
	var b := _btn(node, button_name)
	if b != null:
		b.pressed.emit()
	await _frames()

func _audit_steps(mode: String) -> void:
	for step in [1, 2, 4, 5]:
		_main.go_to_step(step)
		await _frames()
		await _audit("%s_step%d" % [mode, step])
	# STEP4(攻略パーティ): 性能調整タブ / 使用可能スキル編集 / キャラ追加候補。
	_main.go_to_step(4)
	await _frames()
	var party: RBMCreatorStep5Party = _main._step_views[3]
	await _press(party, "PerformanceTabButton")
	await _audit("%s_step4_performance_tab" % mode)
	await _press(party, "SkillsTabButton")
	await _press(party, "EditPartySkillsButton_hero")
	await _audit("%s_step4_skills_edit" % mode)
	_main.draft.remove_party_character("healer")
	_main._refresh()
	await _press(party, "AddCharacterButton")
	await _audit("%s_step4_add_candidates" % mode)
	_main.draft.add_party_character("healer")
	_main._refresh()
	await _frames()

# ---------------------------------------------------------------------------
# HARDCORE STEP3
# ---------------------------------------------------------------------------

func _advanced_view() -> RBMCreatorStep4ActionPatterns:
	var step3: RBMCreatorStep4 = _main._step_views[2]
	return step3._advanced_view

func _audit_advanced_step3() -> void:
	_main.go_to_step(3)
	await _frames()
	var adv := _advanced_view()
	await _audit("adv_step3_empty_list")

	# 一覧(複数件、長い名前の行動を含む)。
	for skill in _main.draft.skills:
		_main.draft.add_action_slot({"kind": "skill", "skill_id": str(skill.get("skill_id", "")), "conditions": [], "condition_logic": "AND", "max_uses": -1})
	adv.refresh()
	await _frames()
	await _audit("adv_step3_list")

	# 新規作成フォーム(各種類)。
	await _press(adv, "AddSlotButton")
	await _audit("adv_step3_add_choice")
	await _press(adv, "AddChoicePickExistingButton")
	await _audit("adv_step3_pick_existing")
	await _press(adv, "PickExistingCancelButton")
	await _press(adv, "AddSlotButton")
	await _press(adv, "AddChoiceCreateNewButton")
	adv._form._name_edit.text = LONG_NAME
	await _audit("adv_step3_new_form_attack")

	for type_id in [RBMActionEditorForm.SELF_HEAL, RBMActionEditorForm.ATK_SELF_BUFF]:
		adv._form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(type_id))
		adv._form._on_type_selected(adv._form._type_option.selected)
		await _frames()
		await _audit("adv_step3_new_form_%s" % type_id)
	adv._form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(RBMActionEditorForm.ATTACK))
	adv._form._on_type_selected(adv._form._type_option.selected)
	await _frames()

	# 条件エディタ: 全種類を開いた状態で監査。
	await _press(adv, "AddConditionButton")
	for condition_type in RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES:
		var index: int = adv._active_condition_types.find(condition_type)
		adv._condition_type_option.select(index)
		adv._condition_type_option.item_selected.emit(index)
		await _frames(2)
		await _audit("adv_step3_condition_%s" % condition_type)
	# 長い名前の行動を「前回使った行動」に選ぶ(条件行のラベルが長くなる)。
	var lbs_index: int = adv._active_condition_types.find("last_boss_skill")
	adv._condition_type_option.select(lbs_index)
	adv._condition_type_option.item_selected.emit(lbs_index)
	adv._condition_boss_skill_option.select(1)
	adv._condition_boss_skill_option.item_selected.emit(1)
	await _frames(2)
	await _audit("adv_step3_condition_long_boss_skill_selected")
	# 条件を積み上げて(複数件・AND/OR)。
	for i in range(4):
		await _press(adv, "AddConditionButton")
	await _audit("adv_step3_conditions_stacked")
	adv._uses_limited_check.button_pressed = true
	await _frames()
	await _audit("adv_step3_uses_limited")
	await _press(adv, "SkillSlotCancelButton")

	# 既存スロットの編集(長い名前+条件つき)。
	await _press(adv, "EditSlotButton_1")
	await _audit("adv_step3_edit_slot")
	await _press(adv, "SkillSlotEditPerformanceButton")
	await _audit("adv_step3_edit_performance")
	await _press(adv, "CancelActionButton")
	await _press(adv, "SkillSlotCancelButton")

	# ランダム攻撃。
	await _press(adv, "AddSlotButton")
	await _press(adv, "AddChoiceCreateRandomButton")
	await _audit("adv_step3_random_empty")
	await _press(adv, "RandomAddCandidateButton")
	await _press(adv, "RandomAddChoicePickExistingButton")
	await _audit("adv_step3_random_pick_existing")
	var pick := adv._random_pick_existing_list.find_child("RandomPickExistingSkillButton_1", true, false) as Button
	if pick != null:
		pick.pressed.emit()
	await _frames()
	await _press(adv, "RandomAddCandidateButton")
	await _press(adv, "RandomAddChoicePickExistingButton")
	pick = adv._random_pick_existing_list.find_child("RandomPickExistingSkillButton_0", true, false) as Button
	if pick != null:
		pick.pressed.emit()
	await _frames()
	adv._random_mode_option.select(RBMActionPatternRules.RANDOM_MODES.find(RBMActionPatternRules.RANDOM_MODE_MANUAL))
	adv._on_random_mode_selected(adv._random_mode_option.selected)
	await _frames()
	await _audit("adv_step3_random_manual_two_candidates")
	await _press(adv, "AddConditionButton")
	await _audit("adv_step3_random_condition")
	await _press(adv, "RandomCancelButton")

	# 覚醒(新規作成→覚醒へ切替→条件)。
	await _press(adv, "AddSlotButton")
	await _press(adv, "AddChoiceCreateNewButton")
	adv._form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(RBMActionEditorForm.AWAKENING))
	adv._form._on_type_selected(adv._form._type_option.selected)
	await _frames()
	await _audit("adv_step3_awakening_form")
	await _press(adv._form, "AwakeningAddBuffButton")
	await _press(adv._form, "AwakeningAddHealButton")
	await _audit("adv_step3_awakening_buff_heal")
	await _press(adv, "AddConditionButton")
	for condition_type in RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES:
		var idx: int = adv._active_condition_types.find(condition_type)
		adv._condition_type_option.select(idx)
		adv._condition_type_option.item_selected.emit(idx)
		await _frames(2)
		await _audit("adv_step3_awakening_condition_%s" % condition_type)
	await _press(adv, "SkillSlotConfirmButton")
	await _audit("adv_step3_list_with_awakening")
	await _press(adv, "EditAwakeningButton")
	await _audit("adv_step3_awakening_edit")
	await _press(adv, "SkillSlotCancelButton")

# ---------------------------------------------------------------------------
# SIMPLE STEP3
# ---------------------------------------------------------------------------

func _audit_simple_step3() -> void:
	_main.go_to_step(3)
	await _frames()
	await _audit("simple_step3")
	var step3: RBMCreatorStep4 = _main._step_views[2]
	var simple = step3._simple_view if "_simple_view" in step3 else null
	if simple != null:
		var add := simple.find_child("AddNormalActionButton", true, false) as Button
		if add != null:
			add.pressed.emit()
			await _frames()
			await _audit("simple_step3_new_action_form")

# ---------------------------------------------------------------------------
# その他のサブ画面
# ---------------------------------------------------------------------------

func _audit_subscreens(mode: String) -> void:
	_main.go_to_step(1)
	await _frames()
	_main.open_appearance_picker()
	await _frames(4)
	await _audit("%s_appearance_picker" % mode)
	_main._on_appearance_cancelled()
	await _frames()

	_main.go_to_step(5)
	await _frames()
	await _audit("%s_step5_summary" % mode)

	_main.press_clear_check()
	await _frames(3)
	await _audit("%s_clear_check_confirm" % mode)
	_main._on_clear_check_return_to_creator()
	await _frames()

	_main.press_save()
	await _frames(3)
	await _audit("%s_save_view" % mode)
	_main._on_save_return_to_creator()
	await _frames()

	if mode == "advanced":
		RBMLocalStageRepository.save_new(_main.draft)
		var entry: RBMCreatorEntry = _root.creator_entry
		entry._show_top()
		await _frames(3)
		await _audit("creator_entry_top")
		entry._show_mode_choice()
		await _frames(3)
		await _audit("creator_entry_mode_choice")
		entry._show_list()
		await _frames(3)
		await _audit("creator_entry_saved_list")

# ---------------------------------------------------------------------------
# 監査本体
# ---------------------------------------------------------------------------

func _audit(label: String) -> void:
	await _frames(2)
	_shot_index += 1
	_tree.root.get_texture().get_image().save_png("%s/%03d_%s.png" % [_out, _shot_index, label])

	var findings: Array[String] = []
	for node in _all_nodes(_tree.root):
		if node is ScrollContainer and (node as ScrollContainer).is_visible_in_tree():
			var scroll := node as ScrollContainer
			var hbar := scroll.get_h_scroll_bar()
			var range_x := hbar.max_value - hbar.page
			var child_min := 0.0
			if scroll.get_child_count() > 0 and scroll.get_child(0) is Control:
				child_min = (scroll.get_child(0) as Control).get_combined_minimum_size().x
			var scrollable := range_x > 0.5 and scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			var bar_visible := hbar.visible and scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			# DISABLEDのScrollContainerは子の最小幅に合わせて自身が広がり親からはみ出すため、
			# scroll.sizeではなく親の利用可能幅と比較する。
			var available := scroll.size.x
			if scroll.get_parent() is Control:
				available = (scroll.get_parent() as Control).size.x
			var over_min := child_min > available + 0.5 or scroll.size.x > available + 0.5
			if scrollable or bar_visible or over_min:
				findings.append("HSA_SCROLL %s :: %s mode=%d size_x=%.0f child_min_x=%.0f available_x=%.0f h_range=%.0f bar_visible=%s" % [label, _path(scroll), scroll.horizontal_scroll_mode, scroll.size.x, child_min, available, range_x, bar_visible])
				if over_min:
					findings.append("HSA_WIDEST %s :: %s" % [label, _widest_chain(scroll.get_child(0) as Control, available)])
	# 画面外へはみ出す可視Control。
	for node in _all_nodes(_tree.root):
		if node is Control and (node as Control).is_visible_in_tree():
			var c := node as Control
			if c.size.x <= 0.0 or c.size.y <= 0.0:
				continue
			var r := c.get_global_rect()
			if r.end.x > SCREEN_W + 1.0 and not _inside_scroll_or_clip(c):
				findings.append("HSA_OFFSCREEN %s :: %s right=%.0f" % [label, _path(c), r.end.x])
	if findings.is_empty():
		print("HSA_OK %s" % label)
	else:
		_issues += 1
		print("HSA_ISSUE %s" % label)
		for f in findings:
			print(f)

func _inside_scroll_or_clip(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		if p is Control and (p as Control).clip_contents:
			return true
		p = p.get_parent()
	return false

func _widest_chain(c: Control, limit: float) -> String:
	## 最小幅がlimitを超える連鎖を、最も深い(=原因に近い)ところまで辿る。
	var text := "%s(min_x=%.0f)" % [c.name, c.get_combined_minimum_size().x]
	var culprit: Control = null
	var best := 0.0
	for child in c.get_children():
		if child is Control and (child as Control).visible:
			var m := (child as Control).get_combined_minimum_size().x
			if m > best:
				best = m
				culprit = child as Control
	if culprit != null and best > limit * 0.5:
		return text + " > " + _widest_chain(culprit, limit)
	# 1つの子が支配的でない(=多数の子の合計で幅が膨らんでいる)場合は、
	# 子ごとの最小幅を列挙して原因を特定できるようにする。
	var parts: Array[String] = []
	for child in c.get_children():
		if child is Control and (child as Control).visible:
			parts.append("%s=%.0f" % [child.name, (child as Control).get_combined_minimum_size().x])
	if not parts.is_empty():
		text += " children[" + ", ".join(parts) + "]"
	return text

func _all_nodes(n: Node) -> Array:
	var result: Array = [n]
	for child in n.get_children():
		result.append_array(_all_nodes(child))
	return result

func _path(n: Node) -> String:
	var parts: Array[String] = []
	var cur: Node = n
	while cur != null and cur != _tree.root:
		parts.push_front(cur.name)
		cur = cur.get_parent()
	if parts.size() > 6:
		parts = parts.slice(parts.size() - 6)
	return "/".join(parts)
