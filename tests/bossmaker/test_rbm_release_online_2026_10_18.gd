extends GutTest

## 配布版の確認の作業（2026-10-18）で直した UI・Steam の不具合の回帰テスト。
## - 技の一覧の説明: 枠に収まる時は今までどおり1項目1行、収まらない時だけ短い項目を2つずつ1行に、
##   それでも収まらなければ効果の括弧書き・名前の行を省く（技が5つのハンマー使いで「戻る」が隠れていた）
## - Steam Cloud: AppID が無い時は Steam に問い合わせない（初期化していない Steam の誤りを毎回出していた）
## - 保存の画面: 保存した後の窓の見出しは「保存したボス」
## 保存は一時のフォルダ。通信・本物の Steam は使わない。

const TEST_DIR := "user://bossmaker_test_release_online_2026_10_18"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR + "/stages")

func after_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	_remove_recursive(TEST_DIR)
	await get_tree().process_frame

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

# =============================================================================
# 技の一覧の説明
# =============================================================================

## 戦闘画面と同じ組み方（見える高さの決まったスクロールの中に、技のボタン・説明・「戻る」）
func _skill_list(scroll_height: float, buttons: int) -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(0, 0)
	scroll.size = Vector2(288, scroll_height)
	add_child_autofree(scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	for i in buttons:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 44)
		b.text = "Skill %d" % i
		panel.add_child(b)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	var back := Button.new()
	back.custom_minimum_size = Vector2(150, 44)
	back.text = "Back"
	panel.add_child(back)
	return {"scroll": scroll, "panel": panel, "label": label, "back": back}

func _tank_skill(id: String) -> Dictionary:
	for s in RBMDataLoader.load_dict("res://data_bossmaker/allies/tank.json").get("skills", []):
		if str(s.get("id", "")) == id:
			return s
	return {}

func _settle() -> void:
	for i in 4:
		await get_tree().process_frame

func test_a_detail_that_fits_keeps_one_item_per_line() -> void:
	var ui := await _skill_list(1000.0, 4)
	var skill := _tank_skill("tank_smash")
	RBMBattleUiKit.show_skill_detail(ui.label, skill)
	await _settle()
	assert_eq(ui.label.text, RBMBattleUiKit.skill_detail_text(skill), "収まる時は今までどおり（名前＋1項目1行）")
	assert_eq(ui.label.text.split("\n").size(), 1 + RBMBattleUiKit.skill_detail_lines(skill, true).size())

func test_a_detail_that_does_not_fit_is_packed_and_back_stays_visible() -> void:
	var ui := await _skill_list(378.0, 5)
	var skill := _tank_skill("tank_smash")
	RBMBattleUiKit.show_skill_detail(ui.label, skill)
	await _settle()
	var full_lines := 1 + RBMBattleUiKit.skill_detail_lines(skill, true).size()
	assert_lt(ui.label.text.split("\n").size(), full_lines, "短い項目を2つずつ1行にまとめた")
	assert_true(ui.label.text.contains(TranslationServer.translate("消費SP：%d") % int(skill.sp_cost)), "まとめても項目は消さない")
	assert_lte((ui.panel as Control).get_combined_minimum_size().y, (ui.scroll as Control).size.y, "一覧が枠に収まる")
	assert_true((ui.scroll as Control).get_global_rect().encloses((ui.back as Control).get_global_rect()), "「戻る」が枠の中に見える")

func test_a_long_effect_drops_the_repeated_name_only_when_needed() -> void:
	var ui := await _skill_list(378.0, 5)
	var skill := _tank_skill("tank_iron_wall")
	RBMBattleUiKit.show_skill_detail(ui.label, skill)
	await _settle()
	assert_lte((ui.panel as Control).get_combined_minimum_size().y, (ui.scroll as Control).size.y, "長い効果の技でも一覧が枠に収まる")
	assert_true((ui.scroll as Control).get_global_rect().encloses((ui.back as Control).get_global_rect()), "「戻る」が枠の中に見える")
	assert_true(ui.label.text.contains(TranslationServer.translate("効果時間：%dターン") % int(skill.duration_turns)), "効果時間は残す")

func test_reopening_with_room_restores_the_full_detail() -> void:
	var ui := await _skill_list(378.0, 5)
	var skill := _tank_skill("tank_smash")
	RBMBattleUiKit.show_skill_detail(ui.label, skill)
	await _settle()
	(ui.scroll as Control).size.y = 1000.0
	RBMBattleUiKit.fit_skill_detail(ui.label)
	assert_eq(ui.label.text, RBMBattleUiKit.skill_detail_text(skill), "枠が広ければ、いつも元の1項目1行に戻す")

# =============================================================================
# Steam Cloud
# =============================================================================

func test_steam_cloud_is_not_asked_without_an_app_id() -> void:
	if not OS.get_environment("STEAM_APP_ID").is_empty():
		pending("STEAM_APP_ID is set in this machine's environment")
		return
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(TEST_DIR + "/no_such_appid.txt")
	assert_false(RBMSteamConfig.is_configured(), "sanity: AppID 無し（配布版で正式 AppID が未設定の時と同じ）")
	assert_false(RBMSteamCloud.new().is_available(), "AppID が無ければ Steam に問い合わせず「使えない」")

# =============================================================================
# 保存の画面の見出し
# =============================================================================

func test_the_save_window_title_says_saved_after_saving() -> void:
	var entry := RBMCreatorEntry.new()
	entry.size = Vector2(1280, 720)
	add_child_autofree(entry)
	await get_tree().process_frame
	entry.enter_create()
	await get_tree().process_frame
	entry._on_choose_simple_mode_pressed()
	await get_tree().process_frame
	var main := entry.main
	main.draft.boss_name = "見出しのボス"
	main.draft.add_party_character("hero")
	main.press_save()
	await get_tree().process_frame
	var view: Control = main._save_view
	var title := view.find_child("SaveBossWindow", true, false).find_child("WindowTitle", false, false) as Label
	assert_eq(title.text, "保存するボス", "保存の前")
	view._do_save_new()
	await get_tree().process_frame
	assert_eq(title.text, "保存したボス", "保存した後")
	view.open()
	assert_eq(title.text, "保存するボス", "もう一度開いたら元に戻る")

# =============================================================================
# 配布版の保存先（2026-10-20）: 書き出した版だけ製品版の名前のフォルダ。エディター・テストは今までどおり
# =============================================================================

func test_only_the_exported_game_uses_the_product_save_folder() -> void:
	assert_true(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir.template", false)), "書き出した版（template）だけ自分の名前のフォルダを使う")
	assert_eq(str(ProjectSettings.get_setting("application/config/custom_user_dir_name.template", "")), "MakersAndChallengers", "製品版の保存先の名前（空白・記号なし。Steam Cloud の設定でも扱いやすい）")
	assert_false(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)), "エディター・GUT の保存先は変えない（開発中のデータを動かさない）")
	assert_false(OS.has_feature("template"), "sanity: GUT はエディターで動いている")
	assert_true(OS.get_user_data_dir().contains("app_userdata"), "エディター・GUT は今までどおり Godot/app_userdata の下")
