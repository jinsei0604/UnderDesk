extends GutTest

## Phase 5 — オンライン版「未挑戦」— RBMOnlineChallengeRecorderのfake駆動
## テスト。実Steam/実Supabaseへは一切出ない。RBMSteamTicketProviderの
## Steam ticket取得手順自体はtest_rbm_boss_publisher.gdで既に検証済みの
## ロジックをそのまま再利用しているため、ここでは「recorderが正しく
## ticketを取得し、正しい引数でAPIを呼び、使用後にticketを解放するか」
## だけを検証する。

## Steam App ID環境分離——他のSteam関連テストと同じ確立済みパターン
## (test_rbm_steam_auth.gd/test_rbm_boss_publisher.gd参照)。
var _tmp_steam_appid_path := "user://test_steam_dev_appid_challenge_recorder.local.txt"

func before_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_steam_appid_path)
	var file := FileAccess.open(_tmp_steam_appid_path, FileAccess.WRITE)
	file.store_string("480")
	file.close()

func after_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	if FileAccess.file_exists(_tmp_steam_appid_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_steam_appid_path))

func _ready_steam_auth(available := true, logged_on := true) -> RBMSteamAuth:
	var fake := RBMFakeSteamAdapter.new()
	if available:
		fake.configure_available()
	else:
		fake.configure_unavailable()
	fake.configure_logged_on(logged_on, 76561198000000001, "Tester")
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	add_child_autoqfree(auth) # see test_rbm_boss_publisher.gd for why queue_free, not free
	auth.initialize()
	return auth

func _recorder(auth: RBMSteamAuth, api: RBMFakeBossApiAdapter) -> RBMOnlineChallengeRecorder:
	add_child_autofree(api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(api)
	return recorder

func _fake_steam_adapter_of(auth: RBMSteamAuth) -> RBMFakeSteamAdapter:
	return auth.adapter_for_testing() as RBMFakeSteamAdapter

func _schedule_ticket_success(auth: RBMSteamAuth) -> void:
	_fire_ticket_success.call_deferred(auth)

func _fire_ticket_success(auth: RBMSteamAuth) -> void:
	var fake := _fake_steam_adapter_of(auth)
	fake.fire_ticket_response(fake.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))

# ---------------------------------------------------------------------------
# record_challenge_attempt
# ---------------------------------------------------------------------------

func test_record_challenge_attempt_succeeds_and_forwards_the_ticket_and_boss_id() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.configure_record_attempt_response({"ok": true, "challenge_count": 1})
	var recorder := _recorder(auth, api)

	_schedule_ticket_success(auth)
	var result: Dictionary = await recorder.record_challenge_attempt("boss-123")

	assert_true(bool(result.get("ok", false)))
	assert_eq(result.get("challenge_count"), 1)
	assert_eq(api.record_attempt_calls.size(), 1)
	assert_eq(api.record_attempt_calls[0]["boss_id"], "boss-123")
	assert_true((api.record_attempt_calls[0]["ticket"] as String).length() > 0, "the real hex ticket from Steam must be sent")

func test_record_challenge_attempt_fails_safely_when_steam_is_unavailable_and_never_calls_the_api() -> void:
	var auth := _ready_steam_auth(false, false)
	var api := RBMFakeBossApiAdapter.new()
	var recorder := _recorder(auth, api)

	var result: Dictionary = await recorder.record_challenge_attempt("boss-123")

	assert_false(bool(result.get("ok", false)))
	assert_eq(result.get("error_kind"), "steam_unavailable")
	assert_eq(api.record_attempt_calls.size(), 0)

func test_record_challenge_attempt_completes_the_ticket_after_use() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	var recorder := _recorder(auth, api)

	_schedule_ticket_success(auth)
	await recorder.record_challenge_attempt("boss-123")

	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.COMPLETED, "the ticket handle must be released after the API call, matching RBMBossPublisher's existing contract")

# ---------------------------------------------------------------------------
# record_challenge_clear
# ---------------------------------------------------------------------------

func test_record_challenge_clear_succeeds_and_forwards_the_ticket_and_boss_id() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.configure_record_clear_response({"ok": true, "clear_count": 1})
	var recorder := _recorder(auth, api)

	_schedule_ticket_success(auth)
	var result: Dictionary = await recorder.record_challenge_clear("boss-123")

	assert_true(bool(result.get("ok", false)))
	assert_eq(result.get("clear_count"), 1)
	assert_eq(api.record_clear_calls.size(), 1)
	assert_eq(api.record_clear_calls[0]["boss_id"], "boss-123")

func test_record_challenge_clear_fails_safely_when_steam_is_not_logged_on() -> void:
	var auth := _ready_steam_auth(true, false)
	var api := RBMFakeBossApiAdapter.new()
	var recorder := _recorder(auth, api)

	var result: Dictionary = await recorder.record_challenge_clear("boss-123")

	assert_false(bool(result.get("ok", false)))
	assert_eq(result.get("error_kind"), "steam_not_logged_on")
	assert_eq(api.record_clear_calls.size(), 0)

# ---------------------------------------------------------------------------
# list_unchallenged_bosses
# ---------------------------------------------------------------------------

func test_list_unchallenged_bosses_succeeds_and_forwards_mode_and_limit() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.configure_list_unchallenged_response({"ok": true, "bosses": [{"id": "b1", "boss_name": "未挑戦ボス", "author_name": ""}]})
	var recorder := _recorder(auth, api)

	_schedule_ticket_success(auth)
	var result: Dictionary = await recorder.list_unchallenged_bosses(RBMCreatorDraft.CREATOR_MODE_SIMPLE, 20)

	assert_true(bool(result.get("ok", false)))
	assert_eq((result.get("bosses") as Array).size(), 1)
	assert_eq(api.list_unchallenged_calls.size(), 1)
	assert_eq(api.list_unchallenged_calls[0]["mode"], RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(api.list_unchallenged_calls[0]["limit"], 20)

## §14「ticket取得失敗時の安全なUI」の土台——recorder自体がticket失敗を
## list_bosses()と同じ{"ok":false,...}形へ正規化して返すことを確認する
## (呼び出し側のRBMOnlineBossListView.refresh()が特別分岐なしで既存の
## エラー表示経路をそのまま使えるようにするため)。
func test_list_unchallenged_bosses_reports_ticket_failure_in_the_same_shape_as_a_network_failure() -> void:
	var auth := _ready_steam_auth(false, false)
	var api := RBMFakeBossApiAdapter.new()
	var recorder := _recorder(auth, api)

	var result: Dictionary = await recorder.list_unchallenged_bosses("", 20)

	assert_false(bool(result.get("ok", false)))
	assert_true(str(result.get("error_kind", "")).length() > 0)
	assert_eq(api.list_unchallenged_calls.size(), 0)
