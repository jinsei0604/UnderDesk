extends SceneTree

## Phase 3.5 UI統一パス — 全画面スクリーンショット撮影ハーネス。
## 実GPUレンダリング（非headless、実OpenGLウィンドウ）でRBMGameRootを
## 実際に操作し、主要画面を撮影する。テストと同じfind_child+.pressed.emit()
## 経路のみを使う（座標クリックには頼らない、Controlベースの画面のため
## こちらの方が確実）。専用のuser://テストディレクトリへ保存データを
## 隔離し、実プレイヤーのセーブを一切汚さない。

const OUT_DIR := "res://tools/_ui_pass_shots/out/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/stages"

var _root: RBMGameRoot
var _shot_index := 0

func _init() -> void:
	print("UI pass screenshot capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	root.add_child(_root)
	await process_frame
	await process_frame

	await _shot("01_title")

	# --- Challengeへ: 一覧にクリアチェック済み1件を用意しておく ---
	var stage_id := _prepare_clear_checked_stage("撮影用ボス")

	_click(_root, "ChallengeModeButton")
	await process_frame
	await _shot("02_challenge_list")

	var challenge_entry: RBMChallengeEntry = _root.challenge_entry
	var row: Control = challenge_entry._list_rows.find_child("ChallengeStageRow_%s" % stage_id, true, false)
	if row == null:
		print("ERROR: challenge stage row not found")
	else:
		_click(row, "ChallengeOpenButton")
		await process_frame
		await _shot("03_challenge_confirm")

		_click(challenge_entry._confirm_view, "ChallengeStartButton")
		await process_frame
		await _shot("04_challenge_battle")

		var battle_view: RBMChallengeBattleView = challenge_entry._battle_view
		# ボス詳細
		battle_view.open_boss_detail()
		await process_frame
		await _shot("05_boss_detail")
		battle_view._close_all_overlays()
		await process_frame

		# 味方詳細（先頭の1人）
		if not battle_view.session.battle.party.is_empty():
			battle_view.open_ally_detail(battle_view.session.battle.party[0].id)
			await process_frame
			await _shot("06_ally_detail")
			battle_view._close_all_overlays()
			await process_frame

		# スキル一覧＋詳細
		var skill_btn: Button = battle_view.find_child("OpenSkillListButton", true, false)
		if skill_btn != null and not skill_btn.disabled:
			skill_btn.pressed.emit()
			await process_frame
			await _shot("07_skill_list_and_detail")
			var back_btn: Button = battle_view.find_child("SkillListBackButton", true, false)
			if back_btn != null:
				back_btn.pressed.emit()
				await process_frame

		# LOG
		battle_view.open_log_window()
		await process_frame
		await _shot("08_log_window")
		battle_view._close_all_overlays()
		await process_frame

		# 一旦Challengeから抜ける
		_click(battle_view, "QuitChallengeButton")
		await process_frame
		_click(battle_view, "QuitConfirmButton")
		await process_frame

	# --- CHALLENGEの勝敗結果画面（§33バグ修正の確認、HP1のボスへ差し替え） ---
	var win_stage_id := _prepare_clear_checked_stage("撮影用ボス（撃破用）", 1)
	challenge_entry._refresh_list()
	await process_frame
	var win_row: Control = challenge_entry._list_rows.find_child("ChallengeStageRow_%s" % win_stage_id, true, false)
	if win_row == null:
		print("ERROR: challenge win stage row not found")
	else:
		_click(win_row, "ChallengeOpenButton")
		await process_frame
		_click(challenge_entry._confirm_view, "ChallengeStartButton")
		await process_frame
		var win_battle_view: RBMChallengeBattleView = challenge_entry._battle_view
		var win_attack_btn: Button = win_battle_view.find_child("AttackButton", true, false)
		if win_attack_btn != null and not win_attack_btn.disabled:
			win_attack_btn.pressed.emit()
			await process_frame
			await _shot("04b_challenge_results_screen")
		_click(win_battle_view, "QuitChallengeButton")
		await process_frame
		_click(win_battle_view, "QuitConfirmButton")
		await process_frame

	_click(challenge_entry, "BackToRootButton")
	await process_frame

	# --- Creatorへ: TEST BATTLEでREWINDを試す ---
	_click(_root, "CreateModeButton")
	await process_frame

	var creator_entry: RBMCreatorEntry = _root.creator_entry
	_click(creator_entry, "NewBossButton")
	await process_frame
	_click(creator_entry, "ChooseSimpleModeButton")
	await process_frame
	await _shot("10_creator_step1")

	var main: RBMCreatorMain = creator_entry.main
	_fill_minimum_draft(main.draft)

	# 実際の「TESTバトル」ボタンが呼ぶのと同じ公開エントリポイント
	# （press_test_battle()、validation→start()→_show_only()を内部で行う）
	# を使う。_test_battle_view.start()を直接叩くだけでは_show_only()が
	# 呼ばれず、画面がSTEP1のまま切り替わらない（実際に踏んだ罠）。
	var result := main.press_test_battle()
	if bool(result.get("ok", false)):
		var test_view := main._test_battle_view
		await process_frame
		await _shot("09_test_battle_with_rewind_list")
		# 1手進めてREWINDリストに要素を作る
		var attack_btn: Button = test_view.find_child("AttackButton", true, false)
		if attack_btn != null:
			attack_btn.pressed.emit()
			await process_frame
			await _shot("09b_test_battle_after_one_turn_rewind_available")
		_click(test_view, "QuitTestButton")
		await process_frame
		_click(test_view, "QuitConfirmButton")
		await process_frame
	else:
		print("ERROR: press_test_battle() failed: %s" % [result])

	# 実際の「テストバトル終了→Creatorに戻る」と同じ経路でSTEP6(Summary)へ
	# 戻っている。同じmain/draftへスキルを追加してからADVANCEDへ切り替える。
	# 注: SIMPLE→ADVANCED自動変換(_auto_populate_action_patterns_from_simple)
	# はSIMPLE側の使用比率設定(normal_action_percentages等、STEP4simple画面で
	# 対話的に設定する値)から変換するため、add_skill()だけでは変換元が空の
	# ままで実際には何も生成されない（1回試して空になることを確認済み）。
	# ADVANCED専用の公開API（add_action_pattern()、クラス冒頭の形コメント
	# 参照）を直接使い、実際にADVANCED編集画面が保存する形と同じ構造の
	# パターンを2つ用意する——情報量の多い画面を撮るのが目的のため。
	var heal_skill_id: String = main.draft.add_skill({"name": "回復の光", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 30})
	var buff_skill_id: String = main.draft.add_skill({"name": "力の咆哮", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": 3})
	var attack_skill_id: String = main.draft.skills[0].get("skill_id", "")
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	main.draft.add_action_pattern({
		"conditions": [{"type": "hp_at_most", "percent": 50.0}],
		"condition_logic": "AND",
		"actions": [{"kind": "skill", "skill_id": heal_skill_id}],
		"post_instant_behavior": "next_turn",
		"max_uses": 2,
		"trigger_probability": 100.0,
		"cooldown_turns": 3,
	})
	main.draft.add_action_pattern({
		"conditions": [{"type": "turn_at", "turn": 1}],
		"condition_logic": "AND",
		"actions": [{"kind": "skill", "skill_id": buff_skill_id}, {"kind": "skill", "skill_id": attack_skill_id}],
		"post_instant_behavior": "resume",
		"max_uses": RBMActionPatternRules.UNLIMITED_USES,
		"trigger_probability": 100.0,
		"cooldown_turns": 0,
	})
	# STEP3番目のツリーノード（"Step3"という名前だが実クラスはRBMCreatorStep4、
	# ADVANCEDモードでは内部の_advanced_view=RBMCreatorStep4ActionPatternsを
	# 表示する——Creator §34項目11「情報量の多い画面」の撮影対象）。
	main.go_to_step(3)
	await process_frame
	await _shot("11_creator_advanced_step4_dense")

	# --- 保存画面 ---
	main.go_to_step(RBMCreatorMain.STEP_COUNT)
	await process_frame
	main.press_save()
	await process_frame
	await _shot("12_creator_save_view")
	var save_view := main._save_view
	var save_new_btn: Button = save_view.find_child("SaveNewButton", true, false)
	if save_new_btn != null:
		save_new_btn.pressed.emit()
		await process_frame
		await _shot("12b_creator_save_success")
	else:
		print("WARN: SaveNewButton not found, dumping save_view children for diagnosis")
		for child in save_view.get_children():
			print("  save_view child: ", child.name)

	# --- 勝敗結果画面（TEST BATTLE、ボスHPを1にして1手で撃破する） ---
	main.draft.hp = 1
	var win_result := main.press_test_battle()
	if bool(win_result.get("ok", false)):
		var win_view := main._test_battle_view
		await process_frame
		var win_attack_btn: Button = win_view.find_child("AttackButton", true, false)
		if win_attack_btn != null and not win_attack_btn.disabled:
			win_attack_btn.pressed.emit()
			await process_frame
			await _shot("13_results_screen")
		else:
			print("WARN: AttackButton missing/disabled on results-screen attempt")
	else:
		print("ERROR: press_test_battle() (results screenshot) failed: %s" % [win_result])

	print("first batch of screenshots captured, quitting")
	quit()

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)

func _prepare_clear_checked_stage(boss_name: String, hp: int = 500) -> String:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = hp
	draft.atk = 40
	draft.spd = 30
	draft.weak_attributes = ["FIRE"]
	draft.add_skill({"name": "爪撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.2})
	draft.add_party_character("hero")
	draft.add_party_character("butler")
	draft.author_notes = "スクリーンショット確認用のボスです。"
	draft.record_clear_check_success()
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

func _fill_minimum_draft(draft: RBMCreatorDraft) -> void:
	draft.boss_name = "TESTバトル用ボス"
	draft.hp = 300
	draft.atk = 20
	draft.spd = 20
	draft.add_skill({"name": "打撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.add_party_character("butler")
