extends SceneTree

## Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）実機確認用ハーネス——実GPU
## レンダリング（非headless）で1280×720にて新STEP1〜5共通レイアウト・新STEP4
## （攻略パーティ統合）・新STEP5（最終確認画面の全面刷新）・公開機能を
## 実際に操作して確認する。§35の12画面/状態に対応:
##   01: STEP1（共通フレーム: 左ナビ+中央+右BOSS PROFILE）
##   02: STEP2（同上）
##   03: STEP3（既存行動編集、共通フレームへ収まっていること）
##   04: STEP4 初期表示（党カード列+選択キャラの使用可能スキルタブ）
##   05: STEP4 CUSTOMバッジ（能力を上書きした後）
##   06: STEP4 性能調整タブ
##   07: STEP4 使用可能スキルタブの編集モード（チェックボックス）
##   08: STEP4「全員を標準に戻す」コンパクト操作の位置
##   09: STEP5 初期表示（Clear Check未達、保存/テストバトル/クリアチェックのみ）
##   10: STEP5 Clear Check達成後（公開ボタン有効化、まだ未公開）
##   11: STEP5 公開後（公開中ステータス+取り下げるボタン）
##   12: CHALLENGE一覧（公開済みボスが実際に表示される）

const OUT_DIR := "res://tools/_ui_pass_shots/out/step4_step5_new_ui/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/step4_step5_new_ui"

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
	print("STEP4/STEP5 new UI capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	_click(_root, "CreateModeButton")
	await _tree().process_frame
	_click(_root.creator_entry, "NewBossButton")
	await _tree().process_frame
	_click(_root.creator_entry, "ChooseAdvancedModeButton")
	await _tree().process_frame
	await _tree().process_frame

	var main: RBMCreatorMain = _root.creator_entry.main
	main.draft.boss_name = "実機確認ボスUI改修"
	main.draft.hp = 2000
	main.draft.atk = 50
	main.draft.spd = 30
	main.draft.add_skill({"name": "通常斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_party_character("hero")
	main.draft.add_party_character("healer")

	# --- 01/02/03: STEP1〜3の共通フレーム確認。
	main.go_to_step(1)
	await _tree().process_frame
	print("step1: nav visible=%s profile visible=%s nav_row visible=%s" % [main._step_nav_column.visible, main._boss_profile_panel.visible, main._nav_row.visible])
	await _shot("01_step1_common_frame")

	# --- 補足: BOSS PROFILEパネル下部（PARTY欄）がscroll可能で全文が
	# 見えることを確認（§35のscroll失敗チェック対象）。STEP1を表示中に
	# 確認する（この後CHALLENGEへ切り替えるとcreator画面自体が隠れるため）。
	var profile_scroll: ScrollContainer = main._boss_profile_panel.find_child("BossProfileScroll", true, false)
	var bar := profile_scroll.get_v_scroll_bar()
	print("boss profile scroll max_value=%s page=%s" % [bar.max_value, bar.page])
	profile_scroll.scroll_vertical = int(bar.max_value)
	await _tree().process_frame
	await _tree().process_frame
	await _shot("01b_boss_profile_scrolled_to_party")
	profile_scroll.scroll_vertical = 0

	main.go_to_step(2)
	await _tree().process_frame
	await _shot("02_step2_common_frame")

	main.go_to_step(3)
	await _tree().process_frame
	await _shot("03_step3_common_frame")

	# --- 04: STEP4初期表示。
	main.go_to_step(4)
	await _tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	print("step4 view class: %s selected=%s" % [step4.get_class(), step4._selected_character_id])
	await _shot("04_step4_initial")

	# heroを選択して使用可能スキルタブ（既定）を明示的に確認。
	_click(step4, "SelectCharacterButton_hero")
	await _tree().process_frame
	await _shot("04b_step4_hero_selected_skills_tab")

	# --- 05: CUSTOMバッジ（heroの能力を上書き）。
	main.draft.set_ally_stat_override("hero", "hp", 9999)
	step4.refresh()
	await _tree().process_frame
	print("hero customized: %s" % main.draft.is_ally_customized("hero"))
	await _shot("05_step4_custom_badge")

	# --- 06: 性能調整タブ。
	_click(step4, "PerformanceTabButton")
	await _tree().process_frame
	await _shot("06_step4_performance_tab")

	# --- 07: 使用可能スキルタブの編集モード。
	_click(step4, "SkillsTabButton")
	await _tree().process_frame
	_click(step4, "EditPartySkillsButton_hero")
	await _tree().process_frame
	print("skills_editing=%s" % step4._skills_editing)
	await _shot("07_step4_skills_edit_mode")
	_click(step4, "CancelPartySkillsButton_hero")
	await _tree().process_frame

	# --- 08: 「全員を標準に戻す」コンパクト操作。
	await _shot("08_step4_reset_all_control")

	main.draft.reset_all_ally_overrides()
	step4.refresh()

	# --- 09: STEP5初期表示（Clear Check未達）。
	main.go_to_step(RBMCreatorMain.STEP_COUNT)
	await _tree().process_frame
	var step5: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	print("step5: nav visible=%s profile visible=%s nav_row visible=%s publish_disabled=%s" % [main._step_nav_column.visible, main._boss_profile_panel.visible, main._nav_row.visible, step5._publish_online_button.disabled])
	await _shot("09_step5_initial_uncleared")

	var summary_content: Control = step5.find_child("SummaryContent", true, false)
	var summary_scroll: ScrollContainer = summary_content.get_parent()
	var summary_bar := summary_scroll.get_v_scroll_bar()
	summary_scroll.scroll_vertical = int(summary_bar.max_value)
	await _tree().process_frame
	await _tree().process_frame
	await _shot("09b_step5_scrolled_to_clear_check_section")
	summary_scroll.scroll_vertical = 0

	# --- 10: Clear Check達成後（公開ボタン有効化、まだ未公開）。
	main.draft.record_clear_check_success()
	step5.refresh()
	print("step5 after clear: publish_disabled=%s status_text=%s" % [step5._publish_online_button.disabled, step5._clear_check_status_label.text])
	await _shot("10_step5_clear_check_achieved")

	# --- 11: オンライン公開後（成功すればボタンが「公開を取り下げる」に
	# 切り替わる。Steam未設定環境ではここは失敗しボタンのまま——公開UI整理
	# 後、ローカル公開ボタンは廃止されたためオンライン公開ボタンのみを叩く）。
	_click(step5, "PublishOnlineButton")
	await _tree().process_frame
	print("online_published=%s button_text=%s" % [step5.draft.is_online_published(), step5._publish_online_button.text])
	await _shot("11_step5_published")

	# --- 12: CHALLENGE一覧（公開済みボスが表示される）。
	_click(_root, "ChallengeModeButton")
	await _tree().process_frame
	await _tree().process_frame
	print("challenge list rows: %d" % _root.challenge_entry._list_rows.get_child_count())
	await _shot("12_challenge_list_shows_published_boss")

	print("STEP4/STEP5 new UI capture done")
	_gpu_verification_completed = true
	return 0

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)
