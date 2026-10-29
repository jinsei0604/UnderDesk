extends GutTest

## 製品版／体験版（RBMEdition、2026-10-28）。製品版が既定で何も変わらないこと、体験版の制限・保存先・引き継ぎ・ガイド。

const TMP := "user://bossmaker_gut_edition"

func before_each() -> void:
	RBMEdition.reset_for_testing()
	_clean(TMP)
	_clean(RBMEdition.demo_root())
	RBMLocalStageRepository.set_stages_dir_for_testing(TMP + "/full/stages")

func after_each() -> void:
	RBMEdition.reset_for_testing()
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	_clean(TMP)
	_clean(RBMEdition.demo_root())
	await get_tree().process_frame

func _clean(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_clean(path + "/" + sub)
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path + "/" + file_name)
	DirAccess.remove_absolute(path)

func _draft(name: String, appearance: String = "appearance_dragon") -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = name
	d.appearance_id = appearance
	d.hp = 1000
	d.atk = 100
	d.spd = 50
	d.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	d.add_party_character("hero")
	return d

# ---------------------------------------------------------------------------
# 製品版が既定（何も変わらない）

func test_the_full_version_is_the_default_and_unrestricted() -> void:
	assert_false(RBMEdition.is_demo(), "editor runs and the full export have no 'demo' feature")
	assert_eq(RBMEdition.FULL_DATA_ROOT, "user://bossmaker", "the full version keeps its save folder")
	for entry in RBMCreatorAppearanceCatalog.all():
		assert_true(RBMEdition.allows_appearance(str(entry["id"])))
	assert_true(RBMEdition.allows_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED))
	assert_true(RBMEdition.allows_online_boss("advanced", "appearance_golem"))
	assert_eq(RBMSteamConfig.OFFICIAL_APP_ID, 5482410, "the full version's AppID is unchanged")
	assert_eq(RBMSteamConfig.DEMO_APP_ID, 5521380, "the trial has its own AppID (Steamworks, 2026-10-28)")
	assert_ne(RBMSteamConfig.DEMO_APP_ID, RBMSteamConfig.OFFICIAL_APP_ID)
	for i in range(7):
		assert_true(bool(RBMLocalStageRepository.save_new(_draft("full %d" % i)).get("ok", false)), "no save limit in the full version")

# ---------------------------------------------------------------------------
# 体験版の制限

func test_the_trial_allows_four_bosses_and_simple_only() -> void:
	RBMEdition.set_demo_for_testing(true)
	var allowed: Array = []
	for entry in RBMCreatorAppearanceCatalog.all():
		if RBMEdition.allows_appearance(str(entry["id"])):
			allowed.append(str(entry["id"]))
	allowed.sort()
	var expected := ["appearance_dragon", "appearance_ghost", "appearance_musha", "appearance_slime"]
	assert_eq(allowed, expected)
	assert_false(RBMEdition.allows_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED))
	assert_true(RBMEdition.allows_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE))
	assert_false(RBMEdition.allows_online_boss("advanced", "appearance_dragon"))
	assert_false(RBMEdition.allows_online_boss("simple", "appearance_golem"))
	assert_true(RBMEdition.allows_online_boss("simple", "appearance_slime"))

func test_the_trial_saves_in_its_own_folder() -> void:
	RBMEdition.set_demo_for_testing(true)
	assert_ne(RBMEdition.data_root(), RBMEdition.FULL_DATA_ROOT)
	assert_eq(RBMEdition.DEMO_DATA_ROOT, "user://bossmaker_demo")
	var locale_manager = load("res://src/bossmaker/rbm_locale_manager.gd")
	assert_true(str(locale_manager.settings_path()).begins_with(RBMLocalStageRepository.GUT_DEFAULT_ROOT), "tests never touch the real settings")

func test_the_trial_keeps_at_most_five_saved_bosses() -> void:
	RBMEdition.set_demo_for_testing(true)
	for i in range(RBMEdition.DEMO_MAX_LOCAL_SAVES):
		assert_true(bool(RBMLocalStageRepository.save_new(_draft("trial %d" % i)).get("ok", false)))
	var sixth := RBMLocalStageRepository.save_new(_draft("sixth"))
	assert_false(bool(sixth.get("ok", true)))
	assert_eq(str(sixth.get("error", "")), "demo_save_limit")
	assert_eq(RBMLocalStageRepository.stage_count(), RBMEdition.DEMO_MAX_LOCAL_SAVES, "nothing extra was written")

func test_the_trial_picker_lists_only_the_four_bosses() -> void:
	RBMEdition.set_demo_for_testing(true)
	var picker := RBMCreatorAppearancePicker.new()
	picker.size = Vector2(1232, 640)
	add_child_autofree(picker)
	var grid: GridContainer = picker.find_child("AppearanceGrid", true, false)
	assert_eq(grid.get_child_count(), 4)
	for id in ["appearance_dragon", "appearance_slime", "appearance_ghost", "appearance_musha"]:
		assert_not_null(picker.find_child("Appearance_%s" % id, true, false))
	assert_null(picker.find_child("Appearance_appearance_golem", true, false))

func test_the_trial_only_shows_trial_bosses_online() -> void:
	RBMEdition.set_demo_for_testing(true)
	var listed := RBMBossApiAdapter._limit_to_edition({"ok": true, "bosses": [
		{"id": "a", "creator_mode": "simple", "appearance_id": "appearance_dragon"},
		{"id": "b", "creator_mode": "advanced", "appearance_id": "appearance_dragon"},
		{"id": "c", "creator_mode": "simple", "appearance_id": "appearance_golem"},
	]})
	assert_eq((listed["bosses"] as Array).map(func(r): return r["id"]), ["a"])
	var hidden := RBMBossApiAdapter._limit_to_edition({"ok": true, "boss": {"payload": {"draft_fields": {"creator_mode": "advanced", "appearance_id": "appearance_dragon"}}}})
	assert_false(bool(hidden.get("ok", true)))
	assert_eq(str(hidden.get("error_kind", "")), "demo_unavailable")
	assert_ne(RBMOnlineErrorText.describe(hidden), "", "a readable message for the player")
	RBMEdition.set_demo_for_testing(false)
	var full := RBMBossApiAdapter._limit_to_edition({"ok": true, "bosses": [{"id": "b", "creator_mode": "advanced", "appearance_id": "appearance_golem"}]})
	assert_eq((full["bosses"] as Array).size(), 1, "the full version sees everything")

func test_the_trial_counts_published_bosses_for_the_two_boss_limit() -> void:
	RBMEdition.set_demo_for_testing(true)
	for i in range(2):
		var d := _draft("published %d" % i)
		d.set_online_boss_id("boss-%d" % i)
		d.set_online_published(true)
		RBMLocalStageRepository.save_new(d)
	assert_eq(RBMLocalStageRepository.online_published_count(), 2)
	assert_eq(RBMLocalStageRepository.online_published_count("boss-0"), 1, "updating a published boss does not count it twice")

# ---------------------------------------------------------------------------
# 製品版への引き継ぎ

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_the_full_version_carries_over_trial_saves_without_touching_its_own() -> void:
	# 体験版で2体保存（体験版の置き場）
	RBMEdition.set_demo_for_testing(true)
	RBMLocalStageRepository.set_stages_dir_for_testing(RBMEdition.demo_root() + "/stages")
	var trial_a := RBMLocalStageRepository.save_new(_draft("体験版A"))
	var trial_b := RBMLocalStageRepository.save_new(_draft("体験版B", "appearance_slime"))
	_write(RBMEdition.demo_root() + "/defeat_records/local.json", JSON.stringify({"format": "rbm_defeat_records", "version": 1, "account": "local", "bosses": {"online-1": {"mode": "simple", "rate": 0.5, "hard": false, "at": 100}}}))
	# 製品版に1体（同じ id を1つ置いて、上書きしないことを確かめる）
	RBMEdition.set_demo_for_testing(false)
	RBMLocalStageRepository.set_stages_dir_for_testing(TMP + "/full/stages")
	var mine := RBMLocalStageRepository.save_new(_draft("製品版の"))
	var same_id_path := TMP + "/full/stages/%s.json" % str(trial_b["stage_id"])
	_write(same_id_path, FileAccess.get_file_as_string(TMP + "/full/stages/%s.json" % str(mine["stage_id"])))
	var before := FileAccess.get_file_as_string(same_id_path)
	var pending := RBMDemoCarryOver.pending()
	assert_eq(int(pending["stages"]), 1, "only the trial save the full version does not have")
	assert_eq(int(pending["defeat_records"]), 1)
	var result := RBMDemoCarryOver.import_all()
	assert_true(bool(result["ok"]))
	assert_eq(int(result["stages"]), 1)
	assert_true(RBMLocalStageRepository.exists(str(trial_a["stage_id"])))
	assert_eq(FileAccess.get_file_as_string(same_id_path), before, "a full-version file with the same id is never overwritten")
	assert_true(RBMLocalStageRepository.exists(str(mine["stage_id"])))
	var loaded := RBMLocalStageRepository.load_stage(str(trial_a["stage_id"]))
	assert_eq(str((loaded["draft_data"] as Dictionary).get("boss_name", "")), "体験版A")
	var records := RBMDefeatRecord.new()
	assert_true(records.load_records().get("bosses", {}).has("online-1"), "the trial defeat record is merged")
	assert_false(RBMDemoCarryOver.has_pending(), "nothing left to carry over")
	assert_true(FileAccess.file_exists(RBMEdition.demo_root() + "/stages/%s.json" % str(trial_a["stage_id"])), "the trial's own files are kept")

func test_the_trial_itself_never_imports() -> void:
	RBMEdition.set_demo_for_testing(true)
	assert_eq(int(RBMDemoCarryOver.import_all()["stages"]), 0)
	assert_false(RBMDemoCarryOver.has_pending())

# ---------------------------------------------------------------------------
# 体験版のガイド

func test_the_trial_guide_pages_and_seen_flag() -> void:
	RBMEdition.set_demo_for_testing(true)
	var guide := RBMDemoGuide.new()
	add_child_autofree(guide)
	assert_false(guide.visible)
	assert_false(RBMDemoGuide.was_seen())
	guide.open_guide()
	assert_true(guide.visible)
	assert_eq(guide.current_page(), 0)
	(guide.find_child("DemoGuideNextButton", true, false) as Button).pressed.emit()
	(guide.find_child("DemoGuideNextButton", true, false) as Button).pressed.emit()
	assert_eq(guide.current_page(), RBMDemoGuide.PAGES.size() - 1)
	assert_true((guide.find_child("DemoGuideNextButton", true, false) as Button).disabled)
	(guide.find_child("DemoGuideCloseButton", true, false) as Button).pressed.emit()
	assert_false(guide.visible)
	assert_true(RBMDemoGuide.was_seen(), "the first-run guide is not shown again")
	assert_true(RBMDemoGuide.seen_path().begins_with(RBMLocalStageRepository.GUT_DEFAULT_ROOT), "tests never write the real save folder")

func test_carry_over_asks_once_and_never_duplicates() -> void:
	RBMEdition.set_demo_for_testing(true)
	RBMLocalStageRepository.set_stages_dir_for_testing(RBMEdition.demo_root() + "/stages")
	var trial := RBMLocalStageRepository.save_new(_draft("体験版C"))
	RBMEdition.set_demo_for_testing(false)
	RBMLocalStageRepository.set_stages_dir_for_testing(TMP + "/full/stages")
	assert_false(RBMDemoCarryOver.was_prompted())
	RBMDemoCarryOver.mark_prompted()
	assert_true(RBMDemoCarryOver.was_prompted(), "after 'later' the automatic question is not shown again")
	assert_true(RBMDemoCarryOver.has_pending(), "but the manual carry-over is still available")
	assert_eq(int(RBMDemoCarryOver.import_all()["stages"]), 1)
	assert_eq(int(RBMDemoCarryOver.import_all()["stages"]), 0, "running it again copies nothing")
	# 引き継いだボス戦を製品版で消しても、もう一度は写さない（重複・復活しない）
	DirAccess.remove_absolute(TMP + "/full/stages/%s.json" % str(trial["stage_id"]))
	assert_false(RBMDemoCarryOver.has_pending())
	assert_eq(int(RBMDemoCarryOver.import_all()["stages"]), 0)
	assert_eq(RBMLocalStageRepository.stage_count(), 0)

func test_the_full_home_shows_the_carry_over_button_only_when_there_is_something_to_carry() -> void:
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	var button := root.find_child("DemoCarryOverButton", true, false) as Button
	assert_not_null(button)
	assert_false(button.visible, "nothing from a trial: the button stays hidden")
	assert_null(root.find_child("DemoGuideButton", true, false), "the full version has no trial guide")
	RBMEdition.set_demo_for_testing(true)
	RBMLocalStageRepository.set_stages_dir_for_testing(RBMEdition.demo_root() + "/stages")
	RBMLocalStageRepository.save_new(_draft("体験版D"))
	RBMEdition.set_demo_for_testing(false)
	RBMLocalStageRepository.set_stages_dir_for_testing(TMP + "/full/stages")
	root._refresh_carry_over_button()
	assert_true(button.visible, "trial data waiting: the home offers the manual carry-over")
	root._on_carry_over_confirmed()
	assert_false(button.visible, "hidden again once everything is carried over")

func test_the_trial_home_has_the_guide_and_no_carry_over() -> void:
	RBMEdition.set_demo_for_testing(true)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	assert_not_null(root.find_child("DemoGuideButton", true, false))
	assert_not_null(root.find_child("DemoGuide", true, false))
	assert_null(root.find_child("DemoCarryOverButton", true, false))

func test_the_development_argument_cannot_change_an_exported_build() -> void:
	# 書き出した版（"template"）では --mc-demo を見ない。エディターの実行（この GUT）では見る。
	var source := FileAccess.get_file_as_string("res://src/bossmaker/rbm_edition.gd")
	assert_string_contains(source, "not OS.has_feature(\"template\") and OS.get_cmdline_user_args().has(DEV_ARGUMENT)")
	var steam := FileAccess.get_file_as_string("res://src/bossmaker/online/rbm_steam_config.gd").replace("\r", "")  # 取り出し方で CRLF になっても同じに比べる
	assert_string_contains(steam, "if RBMEdition.is_demo() and OS.has_feature(\"template\"):\n\t\treturn DEMO_APP_ID")
