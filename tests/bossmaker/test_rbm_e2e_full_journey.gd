extends GutTest

## RPG BOSS MAKER Phase 1 Step 8 §8 — Phase 1全体を通すE2Eテスト。
##
## RBMGameRoot（Step 8で新設した唯一の製品起動ルート）を実際にインスタンス化
## し、起動 → CREATE → STEP1〜7設定 → STEP遷移 → TEST BATTLE → Creator復帰
## → Clear Check → 勝利 → 保存 → CREATE終了 → 共通ルート復帰 → CHALLENGE
## → 一覧 → 選択 → 確認画面 → CHALLENGE開始 → 戦闘 → 勝利 → 結果 → 一覧復帰
## → 再度CHALLENGE開始（Turn1/初期HPからの新セッション確認）→ CHALLENGE
## 終了 → 共通ルート復帰、という指示書§8の27項目チェックリスト全体を、
## 可能な限り実際のButton.pressedシグナル（find_child()で取得した本物の
## ノード経由、内部メソッドの直接呼び出しではない）で駆動する。
##
## STEP1〜7の各ページ自身の「ウィジェット→Draft」配線（LineEdit入力、
## スライダー操作等）は既存フェーズ（Phase 1 Step 1〜4）で既に個別に確立・
## 検証済みのため、Step 8が新たに結合する対象ではない——このテストでは
## STEP各画面の"内容"はdraftフィールドへ直接設定し、Step 8が新規に繋いだ
## "ナビゲーション/モード遷移"（次へ・戻る・TEST BATTLE・Creatorに戻る・
## Clear Check・保存・CREATE/CHALLENGE切替・stage選択・確認画面・戦闘・
## 結果・一覧復帰）を実signal経由で検証する。

const TEST_DIR := "user://bossmaker_test_e2e/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path + "/" + entry
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

## CHALLENGE UI再設計: 一覧カード(RBMChallengeUiKit.build_boss_card())は
## Buttonではなくgui_input経由でクリックを検知するPanelContainerのため、
## _btn()では模擬できない——test_rbm_phase35_step4_battle_ui.gdが既に
## 確立している「合成InputEventMouseButtonをgui_inputへ直接emitする」
## 手法をそのまま踏襲する。
func _click_card(card: Control) -> void:
	var fake_click := InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	card.gui_input.emit(fake_click)

func test_full_phase1_journey_launch_through_challenge_result() -> void:
	# =========================================================================
	# 1. RPG BOSS MAKERルート起動
	# =========================================================================
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	assert_true(root._menu_panel.visible, "sanity: launches on the common CREATE/CHALLENGE menu")
	assert_false(root.creator_entry.visible)
	assert_false(root.challenge_entry.visible)

	# =========================================================================
	# 2. CREATE実Button
	# =========================================================================
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.creator_entry.visible, "pressing the real CREATE button must show RBMCreatorEntry")
	assert_false(root._menu_panel.visible)

	# =========================================================================
	# 3. Creator開始
	# =========================================================================
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	# UI改善②: 「新しいボス戦を作る」は今やCreatorへ直接入らず、まず作成
	# 方法（SIMPLE/ADVANCED）選択パネルを経由する——このE2Eジャーニーは
	# SIMPLE Creatorを対象とするため、実ボタンでシンプルを選ぶ。
	assert_true(root.creator_entry._mode_choice_panel.visible, "「新しいボス戦を作る」の直後はまず作成方法選択パネルを見せる")
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	var main: RBMCreatorMain = root.creator_entry.main
	assert_true(main.visible, "the real SIMPLE Creator (STEP1-7) must now be showing")
	assert_eq(main.current_step, 1)
	assert_eq(main.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_SIMPLE)

	# =========================================================================
	# 4. STEP設定 (draftフィールドへ直接設定 — STEP各ウィジェット自身の配線は
	#    既存フェーズで検証済みのためStep 8の新規結合対象ではない)
	# =========================================================================
	main.draft.boss_name = "E2E統合テストボス"

	# 最終テスト補強⑦: STEP2(能力)を実カードUI(EditStatsButton→SpinBox→
	# ConfirmStatsButton)経由へ変更した。STEP1(名前)/STEP5(使用可能スキル)は
	# 今回の明示対象外のためdraftフィールドへ直接設定のまま据え置く
	# （このE2Eテスト自身の主眼は「STEP間ナビゲーション」であり、対象外の
	# STEPまで無理に実UI化するのは無関係なリファクタリングになるため）。
	main.go_to_step(2)
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	assert_true(step2._edit_panel.visible, "能力は最初から編集可能")
	step2._hp_spin.value = 1  # TEST BATTLE/Clear Check/CHALLENGEすべてで確実に1撃勝利させる
	step2._atk_spin.value = 1
	step2._spd_spin.value = 1
	assert_null(step2.find_child("ConfirmStatsButton", true, false), "数値反映に決定は不要")
	assert_eq(main.draft.hp, 1, "sanity: STEP2実UI経由で能力が反映されること")
	assert_eq(main.draft.atk, 1)
	assert_eq(main.draft.spd, 1)

	# 最終テスト補強⑦: STEP4(パーティ)を実カードUI(AddCharacterButton→
	# AddCandidateButton_hero)経由へ変更した。
	main.go_to_step(4)
	var step4_party: RBMCreatorStep5Party = main._step_views[3]
	_btn(step4_party, "AddCharacterButton").pressed.emit()
	(_btn(step4_party, "AddCandidateButton_hero") as CheckBox).button_pressed = true
	_btn(step4_party, "ConfirmAddCandidatesButton").pressed.emit()
	assert_true(main.draft.party_character_ids.has("hero"), "sanity: STEP4実UI経由でパーティが反映されること")

	# 上のSTEP2/STEP4実UI操作でcurrent_stepが動いているため、後段「5. STEP
	# 遷移」の「実『次へ』ボタンでSTEP1→STEP_COUNTを順に経由する」ループが
	# 正しくSTEP1から開始できるよう、明示的にSTEP1へ戻しておく。
	main.go_to_step(1)
	assert_eq(main.current_step, 1, "sanity: STEP2/STEP4実UI操作の後もSTEP1へ戻れること")

	# Step 8 最終修正 §6: add_party_character()はデフォルトで全スキル許可済み
	# にする——「全許可のまま」を期待値にすると、保存/読込のバグで実際には
	# 一切絞り込まれていない状態が誤って合格してしまう（何もしていなくても
	# パスしてしまうテストになる）。意図的に一部だけ許可・一部だけ不許可の、
	# 識別可能な部分集合を設定する（heroは4スキル: hero_slash/hero_blaze_all/
	# hero_flame_wrap/hero_burst_slash、data_bossmaker/allies/hero.json参照）。
	main.draft.set_ally_skill_allowed("hero", "hero_slash", true)
	main.draft.set_ally_skill_allowed("hero", "hero_flame_wrap", true)
	main.draft.set_ally_skill_allowed("hero", "hero_blaze_all", false)
	main.draft.set_ally_skill_allowed("hero", "hero_burst_slash", false)
	var expected_allowed_skill_ids := ["hero_slash", "hero_flame_wrap"]
	assert_true(main.draft.step1_is_valid(), "sanity")
	assert_true(main.draft.step2_is_valid(), "sanity")
	assert_true(main.draft.step5_is_valid(), "sanity")

	# =========================================================================
	# 5. STEP遷移（実「次へ」ボタン、STEP1→7を全て経由）
	# =========================================================================
	for expected_step in range(1, RBMCreatorMain.STEP_COUNT):
		assert_eq(main.current_step, expected_step, "sanity before advancing")
		_btn(main, "NextButton").pressed.emit()
		await get_tree().process_frame
		assert_eq(main.current_step, expected_step + 1, "a real 次へ press must advance from STEP %d" % expected_step)
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT)
	assert_true(main.has_reached_summary)

	var step7: RBMCreatorStep7Summary = main._step_views[4]

	# =========================================================================
	# 6. TEST BATTLE
	# =========================================================================
	_btn(step7, "TestBattleButton").pressed.emit()
	await get_tree().process_frame
	var tb_view: RBMCreatorTestBattleView = main._test_battle_view
	assert_true(tb_view.visible, "TEST BATTLE screen must be showing")
	assert_true(tb_view.session.start_ok())
	# 実機プレイ改善①: 「行動開始」ボタンは廃止された——実際の「通常攻撃」
	# ボタンを押した瞬間に即座に解決される（boss hp=1・hero(spd 100)がboss
	# (spd 1)より速いため、この1押しだけで確実に決着する）。
	_btn(tb_view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(tb_view.session.battle.battle_over, "TEST BATTLE must have actually resolved via the real RBMBattle")
	assert_eq(tb_view.session.battle.winner, "ally")

	# =========================================================================
	# 7. Creator復帰
	# =========================================================================
	_btn(tb_view, "ReturnToCreatorButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._steps_root.visible, "must be back on the STEP1-7 Creator screen")
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT)

	# =========================================================================
	# 8. Clear Check
	# =========================================================================
	_btn(step7, "ClearCheckButton").pressed.emit()
	await get_tree().process_frame
	var cc_view: RBMCreatorClearCheckView = main._clear_check_view
	assert_true(cc_view.visible, "Clear Check confirmation screen must be showing")
	_btn(cc_view, "ConfirmStartButton").pressed.emit()
	await get_tree().process_frame
	assert_not_null(cc_view.session, "the real 開始 button must have started a real Clear Check session")
	assert_true(cc_view.session.start_ok())

	# =========================================================================
	# 9. Clear Check勝利
	# =========================================================================
	# 実機プレイ改善①: 「行動開始」ボタンは廃止された——実際の「通常攻撃」
	# ボタンを押した瞬間に即座に解決される。
	_btn(cc_view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(cc_view.session.battle.battle_over)
	assert_eq(cc_view.session.battle.winner, "ally")

	# =========================================================================
	# 10. 成功状態確認
	# =========================================================================
	assert_true(main.draft.has_ever_cleared(), "the real victory (RBMBattle.winner==ally) must have recorded Clear Check success")
	assert_true(main.draft.is_clear_check_currently_valid())

	_btn(cc_view, "ReturnToCreatorButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._steps_root.visible)

	# =========================================================================
	# 11. 保存
	# =========================================================================
	_btn(step7, "SaveButton").pressed.emit()
	await get_tree().process_frame
	var save_view: RBMCreatorSaveView = main._save_view
	assert_true(save_view.visible, "the real 保存 button must show the save screen")
	assert_true(main.current_stage_id.is_empty(), "sanity: this is a brand-new, never-saved stage")
	_btn(save_view, "SaveNewButton").pressed.emit()
	await get_tree().process_frame
	assert_false(main.current_stage_id.is_empty(), "the real 保存する button must have actually written a new stage and assigned a real stage_id")
	var stage_id := main.current_stage_id
	assert_false(main.has_unsaved_changes(), "a successful save must clear the unsaved-changes flag")

	# Creator UI改修（2026-09-05）§24〜§27（公開機能、ユーザー確定仕様）:
	# 「保存しただけ」ではCHALLENGE側に表示されない——このE2Eの目的
	# （STEP間ナビゲーション/実UI経由の反映）の対象外である保存成功サブ画面
	# には専用の公開ボタンが無いため、本物の公開実効API（main.press_publish()、
	# ローカル公開の既存処理そのもの——公開UI整理でユーザー向けUIからは
	# 廃止されたが、機能自体は無改修のまま残る）を直接呼ぶ——
	# Clear Checkは直前の手順9で既に本物のRBMBattle勝利により達成済み。
	assert_true(bool(main.press_publish().get("ok", false)), "Clear Check達成済みのため公開できること")
	assert_true(main.draft.is_published())

	# 実機プレイ改善③ item4: 保存成功後の実「クリエイター一覧に戻る」ボタンは、
	# STEP7等の中間STEPを一切経由せず保存済みボス一覧へ直接戻る（旧:
	# main._steps_root(STEP7)へ戻っていた——保存成功→Creator→クリエイター
	# 一覧という無駄な1操作を無くすための変更）。
	_btn(save_view, "SuccessReturnButton").pressed.emit()
	await get_tree().process_frame
	assert_false(main.visible, "the real クリエイター一覧に戻る button must leave the STEP1-7 Creator screen entirely, not return to STEP7")
	assert_true(root.creator_entry._list_panel.visible, "...and land directly on the saved-stage list")
	assert_eq(root.creator_entry._list_rows.get_child_count(), 1, "the just-saved stage must already be listed, with no extra navigation needed")

	# =========================================================================
	# 12. CREATE終了
	# =========================================================================
	_btn(root.creator_entry, "ListBackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.creator_entry._top_panel.visible, "the list screen's own 戻る must return to the CREATE top screen")

	_btn(root.creator_entry, "BackToRootButton").pressed.emit()
	await get_tree().process_frame

	# =========================================================================
	# 13. 共通ルート復帰
	# =========================================================================
	assert_true(root._menu_panel.visible, "must be back on the common CREATE/CHALLENGE menu")
	assert_false(root.creator_entry.visible)

	# =========================================================================
	# 14. CHALLENGE実Button
	# =========================================================================
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.challenge_entry.visible, "pressing the real CHALLENGE button must show RBMChallengeEntry")
	assert_false(root._menu_panel.visible)

	# =========================================================================
	# 14.5. CHALLENGE UI再設計: 「挑戦」は必ず挑戦ハブを経由する
	#       （いきなり一覧を出さない）——「ボスを検索」で共通一覧画面を開く。
	# =========================================================================
	assert_true(root.challenge_entry._hub_view.visible, "entering CHALLENGE must show the hub first, not the list immediately")
	_btn(root.challenge_entry._hub_view, "SearchBossButton").pressed.emit()
	await get_tree().process_frame

	# =========================================================================
	# 15. 保存したstageが一覧に存在（§5: CREATE→共通ルート→CHALLENGEと移動した
	#     場合、そのstageが即座に一覧へ表示されること — Repositoryからの
	#     再取得を直接証明する）
	# =========================================================================
	assert_eq(root.challenge_entry._list_rows.get_child_count(), 1, "the just-saved stage must appear in the CHALLENGE list immediately")
	var row: PanelContainer = root.challenge_entry._list_rows.get_child(0)
	var row_name_label: Label = row.find_child("BossCardNameLabel_%s" % stage_id, true, false)
	assert_eq(row_name_label.text, "E2E統合テストボス")
	assert_eq(row.name, "BossCard_%s" % stage_id)

	# =========================================================================
	# 16. stage選択
	# =========================================================================
	_click_card(row)
	await get_tree().process_frame

	# =========================================================================
	# 17. 確認画面
	# =========================================================================
	assert_true(root.challenge_entry._confirm_view.visible, "selecting a stage must show the confirm screen, never start battle immediately")
	assert_false(root.challenge_entry._battle_view.visible)
	assert_true(root.challenge_entry._confirm_view._boss_name_label.text.contains("E2E統合テストボス"))

	# =========================================================================
	# 18. CHALLENGE開始
	# =========================================================================
	_btn(root.challenge_entry._confirm_view, "ChallengeStartButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.challenge_entry._battle_view.visible, "the real 挑戦する button must start the CHALLENGE battle")
	var battle_view: RBMChallengeBattleView = root.challenge_entry._battle_view
	assert_not_null(battle_view.session)
	assert_true(battle_view.session.start_ok())

	# =========================================================================
	# 19. 保存済みDefinitionが再ロードされている（TEST BATTLE用sessionを
	#     CHALLENGEへ流用していないこと・保存された内容そのものであること）
	# =========================================================================
	# battle_view自身はRBMChallengeEntryが1つだけ保持する共有ノードであり、
	# .sessionはそのノード上のミュータブルなプロパティなので、後で
	# battle_view.sessionを読むと「その時点の最新session」になってしまう
	# （2回目のCHALLENGE開始後は新しいsessionを指す）。§27で「前回の
	# 決着済みsessionとは別物」であることを正しく比較するため、ここで
	# 実際のsessionオブジェクト自身への参照を確保しておく。
	var first_session := battle_view.session
	assert_ne(first_session, tb_view.session, "CHALLENGE must never reuse the TEST BATTLE session")
	assert_ne(first_session, cc_view.session, "CHALLENGE must never reuse the Clear Check session")
	assert_true(first_session is RBMChallengeSession)
	assert_eq(battle_view.session.battle.boss.display_name, "E2E統合テストボス")
	assert_eq(battle_view.session.battle.boss.max_hp, 1, "the boss HP saved during CREATE must be exactly what CHALLENGE loaded")

	# =========================================================================
	# 20. party / allowed skills一致 (Step 8 最終修正 §6: 「全許可」ではなく
	#     実際に設定した部分集合とちょうど一致することを検証する)
	# =========================================================================
	var master := RBMCreatorDraft.new().master_character_def("hero")
	var party_unit := battle_view.session.battle.party[0]
	assert_eq(party_unit.display_name, str(master.get("display_name", "hero")), "the saved party character must be re-loaded as the exact same real master character")
	assert_lt(expected_allowed_skill_ids.size(), (master.get("skills", []) as Array).size(), "sanity: the configured subset must be strictly smaller than the full master skill list, so this assertion cannot be satisfied by an accidental all-allowed regression")
	var actual_skill_ids: Array = []
	for skill in party_unit.skills:
		actual_skill_ids.append(str(skill.get("id", "")))
	assert_eq(actual_skill_ids, expected_allowed_skill_ids, "the saved allowed_skill_ids subset (NOT the full master list) must survive save->CHALLENGE-load intact")

	# =========================================================================
	# 21. REWIND UIなし
	# =========================================================================
	assert_false(battle_view.has_node("RewindList"), "CHALLENGE battle screen must never contain a REWIND list")
	assert_false(battle_view.has_method("rewind_to"), "CHALLENGE battle view must never expose a REWIND API")
	assert_false(battle_view.session.has_method("rewind_to"), "RBMChallengeSession must never expose REWIND")

	# =========================================================================
	# 22. 戦闘 (Step 8 最終修正 §7: 1手で即決着させず、まずhero_flame_wrap
	#     （自己強化、対象選択不要）を使ってtimed_effectsを実際に非初期状態へ
	#     してから、次のラウンドで確実な勝利打（boss HP=1）を撃つ——後段で
	#     「第2回CHALLENGE開始でtimed_effectsが本当に空へ戻る」ことを検証する
	#     ための、本物の（捏造ではない）非初期状態を作る)
	# =========================================================================
	# 実機プレイ改善①: 「行動開始」ボタンは廃止された——実際のスキルボタンを
	# 押した瞬間に即座に解決される（hero_flame_wrapは自己強化のため対象選択
	# を経由しない）。
	_btn(battle_view, "SkillButton_hero_flame_wrap").pressed.emit()
	await get_tree().process_frame
	assert_false(battle_view.session.battle.battle_over, "sanity: casting a self-buff must not itself end the battle")
	assert_false(battle_view.session.battle.party[0].timed_effects.is_empty(), "sanity: hero_flame_wrap really populated timed_effects with a genuinely non-initial value")
	# Step 8 最終最小修正 §3: hero_flame_wrap（SP消費30、hero.json参照）を
	# 実際に使った直後、SPが本当に減っていることを直接確認する——これが無いと
	# 「最初からSP満タンだっただけ」で後段(§27)のSP初期化確認が偶然パスして
	# しまう抜け道が生まれる。current_sp < max_sp（実際に消費された）ことを
	# 第1回CHALLENGE終了前のこの時点で明示的に検証する。
	assert_lt(battle_view.session.battle.party[0].sp, battle_view.session.battle.party[0].max_sp, "sanity: hero_flame_wrap must have actually spent SP (not still at max) -- without this, the later 'SP resets to max on a new session' assertion could pass even if SP was never truly max to begin with")

	_btn(battle_view, "AttackButton").pressed.emit()
	await get_tree().process_frame

	# =========================================================================
	# 23. 勝利または敗北
	# =========================================================================
	assert_true(battle_view.session.battle.battle_over)
	assert_eq(battle_view.session.battle.winner, "ally", "boss HP=1 guarantees a real win once the party actually attacks")

	# =========================================================================
	# 24. 結果
	# =========================================================================
	assert_true(battle_view._outcome_area.visible)
	# 実機プレイ改善③ item8: "CLEAR!"は「クリア！」へ日本語化。
	assert_eq(battle_view._outcome_label.text, "クリア！")
	assert_true(battle_view._retry_button.visible)
	assert_true(battle_view._return_button.visible)

	# CHALLENGEの勝利がClear Check成功として重複記録されないこと・保存stageが
	# 無傷であることの結合確認（Step 7で個別に確立済みの保証を、実際に
	# CREATEで保存した本物のstageに対して結合フローの一部として再確認する）。
	var loaded_after_win := RBMLocalStageRepository.load_stage(stage_id)
	var loaded_draft := RBMCreatorDraft.new()
	loaded_draft.restore_clear_check_snapshot(loaded_after_win.get("clear_check_data", {}))
	assert_true(loaded_draft.has_ever_cleared(), "the Clear Check success recorded during CREATE must remain intact in the saved file")

	# =========================================================================
	# 24.5. 第2回CHALLENGE開始の初期化確認に向け、UI層の一時状態もできるだけ
	#   「初期値ではない」状態にする (Step 8 最終修正 §7)。target_pickerは
	#   実プレイでは決着後に触れる経路が無いため、ここは意図的にprivateフィー
	#   ルドへ直接書き込む——「もし本当にリセットし忘れていたら」を確実に
	#   検出するための、意図的なテスト専用の汚し（実際のプレイフローの再現
	#   ではない）。battle log自体は既に本物の2ラウンド分の戦闘結果で非空に
	#   なっている。
	#   実機プレイ改善①: 旧「全員分の行動予約」(_pending_actions)は廃止された
	#   ため、この汚し・後段(§27)の「引き継がれていないこと」確認の両方から
	#   対象を除いた——概念自体が存在しない以上、汚しようも引き継ぎようも
	#   ない。
	# =========================================================================
	battle_view._target_picker_unit_id = party_unit.id
	battle_view._target_picker_skill_id = "hero_slash"
	battle_view._target_picker.visible = true
	assert_true(battle_view._target_picker.visible, "sanity: the target picker really is open right before ending this CHALLENGE")
	assert_eq(battle_view._target_picker_unit_id, party_unit.id, "sanity")
	assert_eq(battle_view._target_picker_skill_id, "hero_slash", "sanity")
	assert_false(battle_view._log_label.text.is_empty(), "sanity: the real battle log from the 2 resolved rounds above is not empty right before ending this CHALLENGE")

	# =========================================================================
	# 25. 一覧へ戻る
	# =========================================================================
	_btn(battle_view, "ReturnToListButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.challenge_entry._list_panel.visible, "the real CHALLENGE一覧へ button must return to the list")
	assert_false(battle_view.visible)

	# =========================================================================
	# 26. 再度CHALLENGE開始
	# =========================================================================
	var row_again: PanelContainer = root.challenge_entry._list_rows.get_child(0)
	_click_card(row_again)
	await get_tree().process_frame
	_btn(root.challenge_entry._confirm_view, "ChallengeStartButton").pressed.emit()
	await get_tree().process_frame
	var second_battle_view: RBMChallengeBattleView = root.challenge_entry._battle_view
	assert_true(second_battle_view.visible)

	# =========================================================================
	# 27. Turn 1・初期HP/SP等から開始（前回の決着済みsessionとは別の、真に
	#     新しいsessionであること） — Step 8 最終修正 §7でチェックリストを
	#     拡張: 新規session/Turn1/boss HP/party HP/party SP/timed_effects/
	#     is_defending/pending actions無し/target picker非表示・情報未引継ぎ/
	#     戦闘ログ引継ぎ無し、を全て検証する。second_battle_viewはbattle_view
	#     と同一の共有ノードなので、直前の24.5で直接汚した状態が本当に
	#     start_battle()（Step 8最終修正§5で修正済み）によってクリアされた
	#     ことをそのまま確認できる。
	# =========================================================================
	assert_ne(second_battle_view.session, first_session, "each CHALLENGE start must construct a brand new session, never reuse a finished one")
	assert_eq(second_battle_view.session.battle.current_turn, 1)
	assert_false(second_battle_view.session.battle.battle_over)
	assert_eq(second_battle_view.session.battle.boss.hp, second_battle_view.session.battle.boss.max_hp, "the boss must start at full HP again, not carrying over the previous session's defeated state")
	var second_party_unit := second_battle_view.session.battle.party[0]
	assert_eq(second_party_unit.hp, second_party_unit.max_hp)
	assert_eq(second_party_unit.sp, second_party_unit.max_sp, "party SP must also restart at full, not carrying over the SP spent casting hero_flame_wrap in the first session")
	assert_true(second_party_unit.timed_effects.is_empty(), "the atk_buff cast during the first session's round 1 must not survive into a brand new session/battle")
	# second_battle_view.sessionはrestart()ではなく「新しいCHALLENGE開始」
	# （ChallengeStartButton経由、new RBMChallengeSession()）そのものなので、
	# is_defendingは第1セッションのRBMUnitから引き継がれる余地が構造的にない
	# ——新しく構築されたUnitインスタンス自身の初期値(false)であることの
	# 確認に留める。
	assert_false(second_party_unit.is_defending, "is_defending must be at its initial false state on a fresh session")

	assert_false(second_battle_view._target_picker.visible, "the target picker must be closed on a fresh CHALLENGE start")
	assert_eq(second_battle_view._target_picker_unit_id, -1, "no leftover target-picker unit id may survive into a fresh CHALLENGE start")
	assert_eq(second_battle_view._target_picker_skill_id, "", "no leftover target-picker skill id may survive into a fresh CHALLENGE start")
	assert_eq(second_battle_view._log_label.text, "", "the previous battle's log text must not survive into a fresh CHALLENGE start")

	# --- 途中退出でCHALLENGEを終了し、一覧→共通ルートへ戻れることも合わせて確認 ---
	_btn(second_battle_view, "QuitChallengeButton").pressed.emit()
	await get_tree().process_frame
	_btn(second_battle_view, "QuitConfirmButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.challenge_entry._list_panel.visible)

	# CHALLENGE UI再設計: 「戻る」(BackToRootButton)は共通一覧画面ではなく
	# 挑戦ハブへ移った——一覧から一旦ハブへ戻ってから、ハブの「戻る」で
	# 共通ルートへ戻る。
	_btn(root.challenge_entry._list_panel, "BackToHubButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.challenge_entry._hub_view.visible, "sanity: back to the hub")

	_btn(root.challenge_entry._hub_view, "BackToRootButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root._menu_panel.visible, "CHALLENGE自体も共通ルートへ戻れる — Phase 1のE2E導線が完全に閉じる")
	assert_false(root.challenge_entry.visible)
