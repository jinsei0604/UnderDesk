extends GutTest
## 体験版の仕上げ（2026-10-29 ユーザー確定）:
## - オンラインで挑戦できる異なるボスは累計15体まで（数えて断るのはサーバー。ゲームは新しいボスだけサーバーの受付を
##   待ってから戦闘を始める。挑戦済みは待たない。通信できなければ始めない。ローカルのボス・製品版は関係しない）
## - 初めての起動だけの歓迎画面 →「はじめる」→ ガイド（別の画面。同時に出さない。2回目以降は自動で出さない）
## - ガイドは3ページ。実際のゲームの画面（日本語・英語）に番号の枠を重ね、番号の説明を下に並べる
## 本物の Steam・Supabase には触れない（偽の Steam・偽のサーバー RBMFakeBossApiAdapter）。サーバーの決まりは
## supabase/functions/demo-challenge-status の deno テストで試す。
const TEST_ROOT := "user://test_rbm_demo_trial_2026_10_29"
const ACCOUNT_A := "76561198000000001"
var _tmp_steam_appid_path := "user://test_steam_dev_appid_demo_trial.local.txt"

func before_each() -> void:
	RBMEdition.reset_for_testing()
	_remove_recursive(TEST_ROOT)
	_remove_recursive(RBMEdition.demo_root())
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_ROOT + "/stages")

func after_each() -> void:
	RBMEdition.reset_for_testing()
	RBMLocale.set_locale("ja")
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	_remove_recursive(TEST_ROOT)
	_remove_recursive(RBMEdition.demo_root())
	DirAccess.remove_absolute(_tmp_steam_appid_path)
	await get_tree().process_frame

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

func _steam_auth() -> RBMSteamAuth:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_steam_appid_path)
	var file := FileAccess.open(_tmp_steam_appid_path, FileAccess.WRITE)
	file.store_string("480")
	file.close()
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	fake.configure_logged_on(true, int(ACCOUNT_A), "Tester")
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	add_child_autoqfree(auth)
	auth.initialize()
	auth.state_changed.connect(func(state):
		if state == RBMSteamAuth.AuthState.REQUESTING:
			_answer_ticket.call_deferred(auth))
	return auth

func _answer_ticket(auth: RBMSteamAuth) -> void:
	if not is_instance_valid(auth):
		return
	var fake := auth.adapter_for_testing() as RBMFakeSteamAdapter
	fake.fire_ticket_response(fake.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))

func _draft() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "体験版の挑戦テストボス"
	draft.appearance_id = "appearance_dragon"
	draft.hp = 9999
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.add_skill({"name": "QA", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	return draft

## 挑戦画面（体験版かどうかは先に決める。オンライン一覧の上の札は作る時に決まるため）。api は偽のサーバー。
func _setup(demo: bool) -> Dictionary:
	RBMEdition.set_demo_for_testing(demo)
	var auth := _steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.demo_limit_enabled = demo
	add_child_autofree(api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(api)
	var browse_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(browse_api)
	var entry := RBMChallengeEntry.new()
	entry.set_online_api_adapter_for_testing(browse_api)
	entry.set_online_recorder_for_testing(recorder)
	entry.set_defeat_record_for_testing(RBMDefeatRecord.new(ACCOUNT_A, RBMFakeSteamCloud.new()))
	add_child_autofree(entry)
	entry.enter_challenge()
	entry._last_browse_was_online = true
	return {"entry": entry, "api": api}

## オンラインのボスを選んで「挑戦する」。戦闘が始まったかを返す。
func _challenge(s: Dictionary, boss_id: String) -> bool:
	var entry: RBMChallengeEntry = s.entry
	entry._battle_view.visible = false
	entry._online_list_view._summaries[boss_id] = {"unique_challengers": 3, "unique_clearers": 1}
	entry._on_online_boss_selected(boss_id, _draft(), "体験版の挑戦テストボス", "")
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(12)
	return entry._battle_view.visible

func _notice_visible(s: Dictionary) -> bool:
	var dialog: AcceptDialog = (s.entry as RBMChallengeEntry)._demo_dialog
	return dialog != null and dialog.visible

func _close_notice(s: Dictionary) -> void:
	var dialog: AcceptDialog = (s.entry as RBMChallengeEntry)._demo_dialog
	if dialog != null:
		dialog.hide()

# ---------------------------------------------------------------------------
# オンライン挑戦 15体
# ---------------------------------------------------------------------------

func test_a_new_boss_starts_after_the_server_accepts_it_and_the_attempt_is_sent_once() -> void:
	var s := _setup(true)
	var api: RBMFakeBossApiAdapter = s.api
	assert_true(await _challenge(s, "boss-1"), "the server accepted: the battle starts")
	assert_eq(api.record_attempt_calls.size(), 1, "the attempt sent before the battle is reused (not sent twice)")
	assert_eq(api.demo_challenged_ids, ["boss-1"])
	var entry: RBMChallengeEntry = s.entry
	assert_eq(entry._demo_status.get("used"), 1)
	assert_eq((entry._online_list_view.find_child("DemoChallengeCountLabel", true, false) as Label).text, tr("オンライン挑戦　%d / %d体") % [1, 15])

func test_re_challenging_the_same_boss_never_uses_another_slot() -> void:
	var s := _setup(true)
	var api: RBMFakeBossApiAdapter = s.api
	for i in range(3):
		assert_true(await _challenge(s, "boss-1"))
	assert_eq(api.demo_challenged_ids.size(), 1, "the same boss is counted once")
	assert_true(await _challenge(s, "boss-2"))
	assert_eq(api.demo_challenged_ids.size(), 2)

func test_at_15_a_new_boss_shows_the_notice_and_no_battle_but_the_15_stay_open() -> void:
	var s := _setup(true)
	var api: RBMFakeBossApiAdapter = s.api
	for i in range(15):
		api.demo_challenged_ids.append("old-%d" % i)
	assert_false(await _challenge(s, "boss-new"), "the 16th new boss does not start")
	assert_true(_notice_visible(s), "the trial notice is shown")
	var text: String = (s.entry as RBMChallengeEntry)._demo_dialog.dialog_text
	for line in ["体験版で新しく挑戦できるボスは15体までです", "挑戦済みのボスには何度でも再挑戦できます", "製品版では、さらに多くのボスに挑戦できます"]:
		assert_true(text.contains(tr(line)), line)
	assert_eq(api.demo_challenged_ids.size(), 15)
	_close_notice(s)
	assert_true(await _challenge(s, "old-3"), "an already-challenged boss can still be challenged")
	assert_eq(api.demo_challenged_ids.size(), 15)
	# 挑戦済みの15体を全部読んだ後（一覧を開いた時）は、新しいボスはサーバーへ送らずに案内を出す
	await (s.entry as RBMChallengeEntry)._refresh_demo_challenge_status()
	_close_notice(s)
	var calls := api.record_attempt_calls.size()
	assert_false(await _challenge(s, "boss-new-2"))
	assert_true(_notice_visible(s))
	assert_eq(api.record_attempt_calls.size(), calls, "known to be at 15: no request for a new boss")
	_close_notice(s)
	assert_true(await _challenge(s, "old-9"), "and a known challenged boss starts without asking")

func test_without_a_connection_a_new_boss_does_not_start_and_uses_no_slot() -> void:
	var s := _setup(true)
	var api: RBMFakeBossApiAdapter = s.api
	api.network_down = true
	assert_false(await _challenge(s, "boss-1"))
	assert_true(_notice_visible(s))
	assert_eq(api.demo_challenged_ids.size(), 0)
	_close_notice(s)
	api.network_down = false
	assert_true(await _challenge(s, "boss-1"), "retrying after the connection is back works and counts once")
	assert_eq(api.demo_challenged_ids.size(), 1)

func test_the_status_shows_unknown_when_it_cannot_be_read_never_zero() -> void:
	var s := _setup(true)
	var entry: RBMChallengeEntry = s.entry
	var api: RBMFakeBossApiAdapter = s.api
	api.demo_status_down = true
	await entry._refresh_demo_challenge_status()
	assert_eq((entry._online_list_view.find_child("DemoChallengeCountLabel", true, false) as Label).text, tr("オンライン挑戦　? / %d体") % 15)
	assert_eq((entry._online_list_view.find_child("DemoChallengeNoteLabel", true, false) as Label).text, tr("通信できないため、残りの数を確認できません"))
	api.demo_status_down = false
	for i in range(15):
		api.demo_challenged_ids.append("old-%d" % i)
	await entry._refresh_demo_challenge_status()
	assert_eq((entry._online_list_view.find_child("DemoChallengeCountLabel", true, false) as Label).text, tr("オンライン挑戦　%d / %d体") % [15, 15])
	assert_eq((entry._online_list_view.find_child("DemoChallengeNoteLabel", true, false) as Label).text, tr("挑戦済みのボスには引き続き挑戦できます"))

func test_local_bosses_are_not_gated_or_counted() -> void:
	var s := _setup(true)
	var entry: RBMChallengeEntry = s.entry
	var api: RBMFakeBossApiAdapter = s.api
	var saved := RBMLocalStageRepository.save_new(_draft())
	entry._last_browse_was_online = false
	entry._confirm_view.open(str(saved.get("stage_id", "")), _draft())
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(12)
	assert_true(entry._battle_view.visible)
	assert_eq(api.record_attempt_calls.size(), 0)
	assert_eq(api.demo_challenged_ids.size(), 0)

func test_the_full_version_has_no_limit_no_meter_and_no_waiting() -> void:
	var s := _setup(false)
	var api: RBMFakeBossApiAdapter = s.api
	var entry: RBMChallengeEntry = s.entry
	assert_null(entry._online_list_view.find_child("DemoChallengeMeter", true, false), "no trial meter in the full version")
	for i in range(20):
		assert_true(await _challenge(s, "boss-%d" % i))
	assert_false(_notice_visible(s))
	assert_eq(api.demo_challenged_ids.size(), 0)

# ---------------------------------------------------------------------------
# 歓迎画面 → ガイド
# ---------------------------------------------------------------------------

func test_first_run_shows_welcome_then_the_guide_and_never_again() -> void:
	RBMEdition.set_demo_for_testing(true)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	var welcome := root.find_child("DemoWelcome", true, false) as RBMDemoWelcome
	var guide := root.find_child("DemoGuide", true, false) as RBMDemoGuide
	assert_not_null(welcome)
	root._on_boot_completed_for_edition()
	assert_true(welcome.visible, "the welcome screen comes first")
	assert_false(guide.visible, "the guide is not shown at the same time")
	assert_eq((welcome.find_child("DemoWelcomeTitle", true, false) as Label).text, tr("ようこそ！"))
	assert_eq((welcome.find_child("DemoWelcomeGameName", true, false) as Label).text, "Makers & Challengers")
	(welcome.find_child("DemoWelcomeStartButton", true, false) as Button).pressed.emit()
	assert_false(welcome.visible)
	assert_true(guide.visible, "the guide opens right after Start")
	assert_eq(guide.current_page(), 0)
	assert_true(RBMDemoWelcome.was_seen())
	assert_true(RBMDemoGuide.was_seen(), "even if the game is closed during the guide, it is not auto-shown again")
	guide.close_guide()
	# 2回目の起動
	var root2 := RBMGameRoot.new()
	add_child_autofree(root2)
	await get_tree().process_frame
	root2._on_boot_completed_for_edition()
	assert_false((root2.find_child("DemoWelcome", true, false) as Control).visible)
	assert_false((root2.find_child("DemoGuide", true, false) as Control).visible)
	assert_not_null(root2.find_child("DemoGuideButton", true, false), "the guide button stays")

func test_the_full_version_has_no_welcome_screen() -> void:
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	assert_null(root.find_child("DemoWelcome", true, false))
	root._on_boot_completed_for_edition()
	assert_false(RBMDemoWelcome.was_seen())

# ---------------------------------------------------------------------------
# ガイド
# ---------------------------------------------------------------------------

func test_the_guide_has_three_pages_with_real_screenshots_and_numbered_frames_in_both_languages() -> void:
	RBMEdition.set_demo_for_testing(true)
	assert_eq(RBMDemoGuide.PAGES.size(), 3)
	for locale in ["ja", "en"]:
		RBMLocale.set_locale(locale)
		var guide := RBMDemoGuide.new()
		guide.size = Vector2(1280, 720)
		add_child_autofree(guide)
		guide.open_guide()
		for page in range(3):
			var path := RBMDemoGuide.image_path(page, locale)
			assert_true(path.ends_with("_%s.png" % locale), "%s page %d has its own screenshot: %s" % [locale, page + 1, path])
			assert_true(ResourceLoader.exists(path), path)
			var image: TextureRect = guide.find_child("DemoGuideImage", true, false)
			assert_not_null(image.texture)
			var rect := guide.image_rect()
			assert_gte(rect.size.x, 1200.0 * 0.70, "the screenshot is large (%s page %d: %d px)" % [locale, page + 1, rect.size.x])
			var marks: int = (RBMDemoGuide.PAGES[page]["marks"] as Array).size()
			assert_between(marks, 2, 3, "2-3 numbered frames")
			for i in range(marks):
				var frame := guide.find_child("DemoGuideMark%d" % (i + 1), true, false) as Control
				assert_not_null(frame)
				assert_true(rect.grow(1).encloses(Rect2(frame.position, frame.size)), "frame %d stays on the screenshot" % (i + 1))
				assert_not_null(guide.find_child("DemoGuideLineBadge%d" % (i + 1), true, false), "each frame has its numbered line")
			await get_tree().process_frame
			var body := guide.find_child("DemoGuideBody", true, false) as Control
			var last := body.get_child(body.get_child_count() - 1) as Control
			var buttons_top := (guide.find_child("DemoGuideCloseButton", true, false) as Control).get_global_rect().position.y
			assert_true(last.get_global_rect().end.y <= buttons_top, "the text fits above the buttons (%s page %d)" % [locale, page + 1])
			assert_eq((guide.find_child("DemoGuidePrevButton", true, false) as Button).disabled, page == 0)
			assert_eq((guide.find_child("DemoGuideNextButton", true, false) as Button).disabled, page == 2)
			assert_eq((guide.find_child("DemoGuidePage", true, false) as Label).text, "%d / 3" % (page + 1))
			if page < 2:
				(guide.find_child("DemoGuideNextButton", true, false) as Button).pressed.emit()
		guide.close_guide()

func test_the_guide_explains_the_trial_limits_that_exist() -> void:
	var text := ""
	for page in RBMDemoGuide.PAGES:
		text += " ".join(page["lines"]) + " ".join(page["notes"])
	for expected in ["15体", "何度でも", "5体", "2体", "4種類", "HARDCORE", "同じPCの製品版"]:
		assert_true(text.contains(expected), expected)
	assert_false(text.contains("Steam Cloud"), "no promise of an unimplemented feature")
	assert_false(text.contains("生き残る"), "the HARDCORE-only survival victory is not explained in the trial")

# ---------------------------------------------------------------------------
# 2026-10-30: 体験版は HARDCORE のボスに挑戦できないので、挑戦の画面に空の HARDCORE の区分を出さない（製品版は今までどおり）
# ---------------------------------------------------------------------------

func test_the_trial_hub_shows_only_simple_and_the_full_version_keeps_both() -> void:
	for locale in ["ja", "en"]:
		RBMLocale.set_locale(locale)
		for demo in [true, false]:
			RBMEdition.set_demo_for_testing(demo)
			var hub := RBMChallengeHubView.new()
			add_child_autofree(hub)
			var simple := hub.find_child("SimpleCategoryButton", true, false) as Control
			var label := "%s demo=%s" % [locale, demo]
			assert_not_null(simple, label)
			assert_eq(hub.find_child("HardcoreCategoryButton", true, false) == null, demo, "HARDCORE category card " + label)
			assert_eq(hub.find_child("DefeatRecordHardcore", true, false) == null, demo, "HARDCORE defeat count " + label)
			var record := hub.find_child("DefeatRecordSimple", true, false) as Control
			if demo:
				# SIMPLE が空いた所まで広がる（右端は製品版の HARDCORE のカードの右端と同じ）
				assert_eq(simple.size.x, RBMChallengeHubView.MODE_CARD_STEP + RBMChallengeHubView.MODE_CARD_SIZE.x, label)
				assert_eq(record.size.x, RBMChallengeHubView.RECORD_WIDTH, label)
				var open := simple.find_child("OpenListLabel", true, false) as Control
				assert_true(open.get_rect().end.x <= simple.size.x, "the open-list label stays inside the wide card " + label)
			else:
				assert_eq(simple.size, RBMChallengeHubView.MODE_CARD_SIZE, label)
			# 数の表示は今までどおり（体験版は HARDCORE の数を出さないだけ）
			hub.set_defeat_counts({"simple": 4, "hardcore": 2, "hard": 1})
			var shown := hub.defeat_counts_shown()
			assert_eq(shown.get("simple"), 4, label)
			assert_eq(shown.has("hardcore"), not demo, label)

func test_the_trial_online_list_has_no_hardcore_switch_and_the_full_version_keeps_it() -> void:
	for locale in ["ja", "en"]:
		RBMLocale.set_locale(locale)
		for demo in [true, false]:
			RBMEdition.set_demo_for_testing(demo)
			var api := RBMFakeBossApiAdapter.new()
			add_child_autofree(api)
			var view := RBMOnlineBossListView.new()
			view.set_api_adapter_for_testing(api)
			add_child_autofree(view)
			var label := "%s demo=%s" % [locale, demo]
			assert_not_null(view.find_child("OnlineListModeAll", true, false), label)
			assert_not_null(view.find_child("OnlineListModeSimple", true, false), label)
			assert_eq(view.find_child("OnlineListModeHardcore", true, false) == null, demo, label)
			if demo:
				# 札（オンライン挑戦 ○ / 15体）と切り替えが重ならない
				var meter := view.find_child("DemoChallengeMeter", true, false) as Control
				var all := view.find_child("OnlineListModeAll", true, false) as Control
				assert_true(meter.get_rect().end.x <= all.get_rect().position.x, "meter and switches do not overlap " + label)
