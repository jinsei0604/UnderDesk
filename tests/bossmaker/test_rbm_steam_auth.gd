extends GutTest

## RBMFakeSteamAdapter経由で、実GodotSteam/実Steamクライアントに一切
## 触れずにticket lifecycle全体を検証する(headless GUT向け)。

var _tmp_path := "user://test_steam_dev_appid_auth.local.txt"

func before_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_path)
	var file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	file.store_string("480")
	file.close()

func after_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	if FileAccess.file_exists(_tmp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_path))

func _new_auth(fake: RBMFakeSteamAdapter) -> RBMSteamAuth:
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	add_child_autofree(auth)
	return auth

# ---------------------------------------------------------------------------
# 初期化 / 可用性
# ---------------------------------------------------------------------------

func test_steam_unavailable_reports_not_available_and_does_not_crash() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_unavailable()
	var auth := _new_auth(fake)
	var result := auth.initialize()
	assert_false(auth.is_available())
	assert_eq(int(result.get("status", -1)), 2)
	assert_false(auth.is_logged_on())
	assert_eq(auth.steam_id(), "")

func test_steam_available_but_appid_not_configured_is_reported_safely() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("user://does_not_exist.local.txt")
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	assert_false(auth.is_available())

func test_steam_available_and_configured_initializes_successfully() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	var result := auth.initialize()
	assert_true(auth.is_available())
	assert_eq(int(result.get("status", -1)), 0)

func test_logged_on_false_is_reported_and_steam_id_is_empty() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	fake.configure_logged_on(false)
	var auth := _new_auth(fake)
	auth.initialize()
	assert_false(auth.is_logged_on())
	assert_eq(auth.steam_id(), "")
	assert_eq(auth.persona_name(), "")

# ---------------------------------------------------------------------------
# SteamID64の文字列化
# ---------------------------------------------------------------------------

func test_steam_id_is_returned_as_a_string_not_a_number() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	fake.configure_logged_on(true, 76561198000000001, "Tester")
	var auth := _new_auth(fake)
	auth.initialize()
	assert_true(auth.is_logged_on())
	var id_string := auth.steam_id()
	assert_typeof(id_string, TYPE_STRING)
	assert_eq(id_string, "76561198000000001")
	assert_eq(auth.persona_name(), "Tester")

# ---------------------------------------------------------------------------
# ticket request / callback成功
# ---------------------------------------------------------------------------

func test_request_starts_requesting_state_and_calls_adapter() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	fake.configure_logged_on(true, 1, "A")
	var auth := _new_auth(fake)
	auth.initialize()
	var started := auth.request_web_api_ticket()
	assert_true(started)
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.REQUESTING)

func test_request_uses_the_fixed_web_api_identity() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	assert_eq(fake.last_requested_identity(), "makers-and-challengers-backend")
	assert_eq(RBMSteamAuth.WEB_API_IDENTITY, "makers-and-challengers-backend")

func test_callback_success_moves_to_ready_with_correct_hex() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	var bytes := PackedByteArray([0x4a, 0xf2, 0x03])
	fake.fire_ticket_response(handle, RBMFakeSteamAdapter.RESULT_OK, bytes.size(), bytes)
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.READY)
	assert_eq(auth.consume_ticket_hex(), "4af203")

func test_callback_failure_moves_to_failed_and_cancels_handle() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	fake.fire_ticket_response(handle, 2, 0, PackedByteArray())
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.FAILED)
	assert_true(auth.failure_reason().length() > 0)
	assert_has(fake.cancelled_handles(), handle)

# ---------------------------------------------------------------------------
# hex変換の専用テスト
# ---------------------------------------------------------------------------

func test_ticket_bytes_to_hex_produces_lowercase_hex_string() -> void:
	var bytes := PackedByteArray([0x4a, 0xf2, 0x03, 0xff, 0x00])
	assert_eq(RBMSteamAuth.ticket_bytes_to_hex(bytes), "4af203ff00")

func test_ticket_bytes_to_hex_trims_to_the_given_size() -> void:
	var bytes := PackedByteArray([0x01, 0x02, 0x03, 0x04])
	assert_eq(RBMSteamAuth.ticket_bytes_to_hex(bytes, 2), "0102")

func test_ticket_bytes_to_hex_handles_empty_buffer() -> void:
	assert_eq(RBMSteamAuth.ticket_bytes_to_hex(PackedByteArray()), "")

# ---------------------------------------------------------------------------
# timeout
# ---------------------------------------------------------------------------

func test_timeout_moves_to_failed_and_cancels_the_pending_handle() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.timeout_seconds = 0.05
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	await wait_seconds(0.2)
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.FAILED)
	assert_has(fake.cancelled_handles(), handle)

func test_late_callback_after_timeout_is_ignored() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.timeout_seconds = 0.05
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	await wait_seconds(0.2)
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.FAILED)
	var reason_after_timeout := auth.failure_reason()
	var bytes := PackedByteArray([0x01])
	fake.fire_ticket_response(handle, RBMFakeSteamAdapter.RESULT_OK, 1, bytes)
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.FAILED)
	assert_eq(auth.failure_reason(), reason_after_timeout)

# ---------------------------------------------------------------------------
# 二重request / 古いcallback混入防止
# ---------------------------------------------------------------------------

func test_second_request_while_requesting_is_rejected() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	assert_true(auth.request_web_api_ticket())
	assert_false(auth.request_web_api_ticket())

func test_second_request_while_ready_is_rejected_until_consumed() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	fake.fire_ticket_response(handle, RBMFakeSteamAdapter.RESULT_OK, 1, PackedByteArray([1]))
	assert_false(auth.request_web_api_ticket())

func test_stale_callback_from_a_previous_request_is_ignored() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	var stale_handle: int = fake.last_issued_handle()
	auth.cancel_ticket()
	auth.request_web_api_ticket()
	var current_handle: int = fake.last_issued_handle()
	assert_ne(stale_handle, current_handle)
	# 古い(cancel済みの)handleに対するcallbackが遅れて届いても無視される。
	fake.fire_ticket_response(stale_handle, RBMFakeSteamAdapter.RESULT_OK, 1, PackedByteArray([9]))
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.REQUESTING)
	# 現在進行中のrequestには正しく反応する。
	fake.fire_ticket_response(current_handle, RBMFakeSteamAdapter.RESULT_OK, 1, PackedByteArray([9]))
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.READY)

# ---------------------------------------------------------------------------
# cancel
# ---------------------------------------------------------------------------

func test_cancel_while_requesting_moves_to_cancelled_and_cancels_handle() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	auth.cancel_ticket()
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.CANCELLED)
	assert_has(fake.cancelled_handles(), handle)

func test_cancel_twice_is_safe_and_does_not_double_report() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	auth.cancel_ticket()
	auth.cancel_ticket()
	var cancelled := fake.cancelled_handles()
	assert_eq(cancelled.count(handle), 1)

func test_cancel_when_idle_is_a_safe_no_op() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.cancel_ticket()
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.IDLE)
	assert_eq(fake.cancelled_handles().size(), 0)

func test_complete_ticket_cancels_handle_and_allows_a_new_request() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := _new_auth(fake)
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	fake.fire_ticket_response(handle, RBMFakeSteamAdapter.RESULT_OK, 1, PackedByteArray([9]))
	auth.consume_ticket_hex()
	auth.complete_ticket()
	assert_eq(auth.current_auth_state(), RBMSteamAuth.AuthState.COMPLETED)
	assert_has(fake.cancelled_handles(), handle)
	assert_true(auth.request_web_api_ticket())

func test_exit_tree_cancels_a_pending_ticket() -> void:
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	add_child(auth)
	auth.initialize()
	auth.request_web_api_ticket()
	var handle: int = fake.last_issued_handle()
	remove_child(auth)
	assert_has(fake.cancelled_handles(), handle)
	auth.queue_free()
	await wait_frames(1)
