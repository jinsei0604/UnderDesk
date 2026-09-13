extends SceneTree

## CHALLENGE UI再設計（挑戦ハブ + 共通ボス一覧画面、指示書§0〜§28）実機確認用
## ハーネス——実GPUレンダリング（非headless）で1280×720にて§26の19項目を
## 実際に操作して確認する。
##   01: 挑戦ハブ
##   02: SIMPLE一覧
##   03: HARDCORE一覧
##   04: 新着一覧
##   05: 未挑戦一覧
##   06: 人気一覧
##   07: 高難度一覧
##   08: 検索
##   09: ボス1件（検索で1件だけに絞り込み）
##   10: ボス複数件（検索クリア、複数件表示）
##   11: ボス多数でスクロール
##   12: 左カード選択
##   13: 右詳細更新
##   14: 公開情報あり
##   15: 非公開情報あり
##   16: 攻略パーティ表示
##   17: 作者メッセージ表示
##   18: ランダム抽選
##   19: このボスに挑戦→戦闘

const OUT_DIR := "res://tools/_ui_pass_shots/out/challenge_hub_ui/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/challenge_hub_ui"

var _root: RBMGameRoot

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

## 正式GPU runner成功判定contract(2026-09-13制定)。詳細はtools/gpu_runner.gd
## 冒頭コメント参照。falseのままならrunnerはexit code 0を返さない。
var _gpu_verification_completed := false

func run_gpu_verification(tree: SceneTree) -> int:
	_tree_override = tree
	print("CHALLENGE hub UI capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	_seed_stages()

	_click(_root, "ChallengeModeButton")
	await _tree().process_frame
	await _tree().process_frame
	print("hub visible: %s" % _root.challenge_entry._hub_view.visible)
	await _shot("01_hub")

	_click(_root.challenge_entry._hub_view, "SimpleCategoryButton")
	await _tree().process_frame
	print("SIMPLE category rows: %d" % _root.challenge_entry._list_rows.get_child_count())
	await _shot("02_simple_list")

	_click(_root.challenge_entry._list_panel, "BackToHubButton")
	await _tree().process_frame
	_click(_root.challenge_entry._hub_view, "HardcoreCategoryButton")
	await _tree().process_frame
	print("HARDCORE category rows: %d" % _root.challenge_entry._list_rows.get_child_count())
	await _shot("03_hardcore_list")

	_click(_root.challenge_entry._list_panel, "BackToHubButton")
	await _tree().process_frame
	_click(_root.challenge_entry._hub_view, "NewCategoryButton")
	await _tree().process_frame
	await _shot("04_new_list")

	_click(_root.challenge_entry._list_panel, "BackToHubButton")
	await _tree().process_frame
	_click(_root.challenge_entry._hub_view, "UnchallengedCategoryButton")
	await _tree().process_frame
	await _shot("05_unchallenged_list")

	_click(_root.challenge_entry._list_panel, "BackToHubButton")
	await _tree().process_frame
	_click(_root.challenge_entry._hub_view, "PopularCategoryButton")
	await _tree().process_frame
	await _shot("06_popular_list")

	_click(_root.challenge_entry._list_panel, "BackToHubButton")
	await _tree().process_frame
	_click(_root.challenge_entry._hub_view, "HighDifficultyCategoryButton")
	await _tree().process_frame
	await _shot("07_high_difficulty_list")

	_click(_root.challenge_entry._list_panel, "BackToHubButton")
	await _tree().process_frame
	_click(_root.challenge_entry._hub_view, "SearchBossButton")
	await _tree().process_frame
	print("search (unfiltered) rows: %d" % _root.challenge_entry._list_rows.get_child_count())
	await _shot("08_search")

	_root.challenge_entry._name_search_field.text = "注目の火竜"
	_root.challenge_entry._refresh_list()
	await _tree().process_frame
	print("search (narrowed to 1) rows: %d" % _root.challenge_entry._list_rows.get_child_count())
	await _shot("09_one_result")

	_root.challenge_entry._name_search_field.text = ""
	_root.challenge_entry._refresh_list()
	await _tree().process_frame
	print("search (cleared, multiple) rows: %d" % _root.challenge_entry._list_rows.get_child_count())
	await _shot("10_multiple_results")

	# --- 11: 多数のボスでスクロール確認。
	for i in range(20):
		_publish_stage("大量ボス%02d" % i, RBMCreatorDraft.CREATOR_MODE_SIMPLE, "量産作者")
	_root.challenge_entry._refresh_list()
	await _tree().process_frame
	print("total rows after seeding 20 more: %d" % _root.challenge_entry._list_rows.get_child_count())
	var list_scroll: ScrollContainer = _root.challenge_entry._list_panel.find_child("ChallengeListScroll", true, false)
	var v_bar := list_scroll.get_v_scroll_bar()
	print("list scroll max_value=%s" % v_bar.max_value)
	list_scroll.scroll_vertical = int(v_bar.max_value)
	await _tree().process_frame
	await _shot("11_scrolled_many_bosses")
	list_scroll.scroll_vertical = 0

	# --- 12/13: 左カード選択→右詳細更新。
	var first_card: PanelContainer = _root.challenge_entry._list_rows.get_child(0)
	_click_card(first_card)
	await _tree().process_frame
	print("selected stage_id: %s" % _root.challenge_entry._selected_stage_id)
	await _shot("12_card_selected")

	var second_card: PanelContainer = _root.challenge_entry._list_rows.get_child(1)
	_click_card(second_card)
	await _tree().process_frame
	print("selection changed to: %s" % _root.challenge_entry._selected_stage_id)
	await _shot("13_detail_updated_after_second_selection")

	# --- 14/15: 公開情報あり/非公開情報あり。
	_root.challenge_entry._name_search_field.text = "公開情報確認ボス"
	_root.challenge_entry._refresh_list()
	await _tree().process_frame
	_click_card(_root.challenge_entry._list_rows.get_child(0))
	await _tree().process_frame
	await _shot("14_visible_info")

	_root.challenge_entry._name_search_field.text = "非公開情報確認ボス"
	_root.challenge_entry._refresh_list()
	await _tree().process_frame
	_click_card(_root.challenge_entry._list_rows.get_child(0))
	await _tree().process_frame
	await _shot("15_hidden_info")

	# --- 16/17: 攻略パーティ・作者メッセージ表示（既にconfirm viewに含まれる
	# ため、直近のスクリーンショットの下部を確認できるようスクロールする）。
	var confirm_scroll: ScrollContainer = _root.challenge_entry._confirm_view.find_child("ChallengeConfirmContent", true, false).get_parent()
	confirm_scroll.scroll_vertical = int(confirm_scroll.get_v_scroll_bar().max_value)
	await _tree().process_frame
	print("author message: %s" % _root.challenge_entry._confirm_view._author_notes_label.text)
	await _shot("16_17_party_and_author_message_scrolled")
	confirm_scroll.scroll_vertical = 0

	_root.challenge_entry._name_search_field.text = ""
	_root.challenge_entry._refresh_list()
	await _tree().process_frame

	# --- 18: ランダム抽選。
	_click(_root.challenge_entry._list_panel, "BackToHubButton")
	await _tree().process_frame
	_click(_root.challenge_entry._hub_view, "RandomChallengeButton")
	await _tree().process_frame
	print("random picked: %s" % _root.challenge_entry._selected_stage_id)
	await _shot("18_random_pick")

	# --- 19: このボスに挑戦→戦闘。
	_click(_root.challenge_entry._confirm_view, "ChallengeStartButton")
	await _tree().process_frame
	print("battle started: %s" % _root.challenge_entry._battle_view.visible)
	await _shot("19_battle_started")

	print("CHALLENGE hub UI capture done")
	_gpu_verification_completed = true
	return 0

func _seed_stages() -> void:
	# 02/03/06/07用: SIMPLE/HARDCORE、挑戦者数/クリア率にばらつきを持たせる。
	var visible_id := _publish_stage("公開情報確認ボス", RBMCreatorDraft.CREATOR_MODE_SIMPLE, "オープン作者", true)
	var hidden_id := _publish_stage("非公開情報確認ボス", RBMCreatorDraft.CREATOR_MODE_ADVANCED, "", false)
	var featured_id := _publish_stage("注目の火竜", RBMCreatorDraft.CREATOR_MODE_SIMPLE, "竜使い", true)
	var popular_id := _publish_stage("大人気ボス", RBMCreatorDraft.CREATOR_MODE_ADVANCED, "人気作者", true)
	var hard_id := _publish_stage("超高難度ボス", RBMCreatorDraft.CREATOR_MODE_ADVANCED, "鬼作者", true)
	var unchallenged_id := _publish_stage("誰も挑んでいないボス", RBMCreatorDraft.CREATOR_MODE_SIMPLE, "新人作者", true)

	for i in range(30):
		RBMLocalStageRepository.record_challenge_attempt(popular_id)
	for i in range(20):
		RBMLocalStageRepository.record_challenge_clear(popular_id)

	RBMLocalStageRepository.record_challenge_attempt(hard_id)
	for i in range(15):
		RBMLocalStageRepository.record_challenge_attempt(hard_id)
	# 0 clears out of 16 attempts -> genuinely hard, and higher-confidence than
	# a 1-attempt/0-clear stage under the corrected-clear-rate formula.

	print("seeded stage ids: visible=%s hidden=%s featured=%s popular=%s hard=%s unchallenged=%s" % [visible_id, hidden_id, featured_id, popular_id, hard_id, unchallenged_id])

func _publish_stage(boss_name: String, mode: String, author_name: String, all_visible: bool = true) -> String:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 2000
	draft.atk = 80
	draft.spd = 40
	draft.toggle_weak_attribute("ICE")
	draft.toggle_resist_attribute("FIRE")
	var skill_id := draft.add_skill({"name": "爪撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.5})
	draft.add_party_character("hero")
	draft.add_party_character("healer")
	if mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
		draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
		draft.action_sequence.clear()
		draft.add_action_slot({"kind": RBMActionPatternRules.SLOT_KIND_SKILL, "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	if not author_name.is_empty():
		draft.set_author_name(author_name)
	draft.set_author_notes("氷属性の攻撃に注意してください。全力で挑んでください！")
	if not all_visible:
		draft.set_all_challenge_info_visible(false)
	draft.record_clear_check_success()
	draft.publish()
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _click_card(card: Control) -> void:
	var fake_click := InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	card.gui_input.emit(fake_click)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)
