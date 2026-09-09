extends GutTest

## Phase 4C — RBMBossPublisherのfake駆動E2Eテスト。実Steam/実Supabaseへは
## 一切出ない。正式AppID取得後、RBMSteamAuthの中身をfakeから実アダプター
## へ差し替えるだけでこの経路がそのまま本番動作する設計であることを
## この一連のテストで裏付ける。
##
## publish()はGDScriptのcoroutineのため、呼び出し箇所では必ずawaitする
## 必要がある(静的解析でも強制される)。callback到着を待っている最中の
## 状態を検証したい場合は、call_deferred()でcallback発火を1フレーム後へ
## 予約してからawaitする(publish()は自分のawait _steam_auth.state_changed
## で一旦中断するため、その中断中にdeferred呼び出しが実行される)。

func _playable_draft(boss_name: String = "公開E2Eボス") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	return draft

func _cleared_draft(boss_name: String = "公開E2Eボス") -> RBMCreatorDraft:
	var draft := _playable_draft(boss_name)
	draft.record_clear_check_success()
	return draft

func _ready_steam_auth(available := true, logged_on := true) -> RBMSteamAuth:
	var fake := RBMFakeSteamAdapter.new()
	if available:
		fake.configure_available()
	else:
		fake.configure_unavailable()
	fake.configure_logged_on(logged_on, 76561198000000001, "Tester")
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	# add_child_autoqfree (queue_free), not add_child_autofree (free): when a
	# test fires the fake ticket callback via call_deferred() and then makes
	# no further await before returning, GUT's teardown can run while `auth`
	# is still nested inside its own state_changed.emit() call (the signal
	# emission that is resuming this whole await chain) -- Godot refuses an
	# immediate .free() on a Node that is still "locked" like that. queue_free()
	# defers the actual free past that point instead of erroring.
	add_child_autoqfree(auth)
	auth.initialize()
	return auth

func _publisher(auth: RBMSteamAuth, api: RBMFakeBossApiAdapter) -> RBMBossPublisher:
	# RBMBossApiAdapter extends Node (its real subclass owns an HTTPRequest
	# child), so the fake must also be parented somewhere and freed --
	# RBMBossPublisher.set_api_adapter_for_testing() only stores a reference,
	# it does not adopt ownership.
	add_child_autofree(api)
	var publisher := RBMBossPublisher.new()
	add_child_autofree(publisher)
	publisher.set_steam_auth_for_testing(auth)
	publisher.set_api_adapter_for_testing(api)
	return publisher

func _fake_steam_adapter_of(auth: RBMSteamAuth) -> RBMFakeSteamAdapter:
	return auth.adapter_for_testing() as RBMFakeSteamAdapter

## publish()内部のawaitで中断している間に、次のidleフレームで実際に
## callback(成功)を発火させる。
func _schedule_ticket_success(auth: RBMSteamAuth) -> void:
	_fire_ticket_success.call_deferred(auth)

func _fire_ticket_success(auth: RBMSteamAuth) -> void:
	var fake := _fake_steam_adapter_of(auth)
	fake.fire_ticket_response(fake.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))

# ---------------------------------------------------------------------------

func test_publish_rejects_a_draft_without_clear_check_without_touching_steam_or_the_api() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)
	var draft := _playable_draft() # never cleared

	var ok: bool = await publisher.publish(draft)
	assert_false(ok)
	assert_eq(publisher.last_error_kind(), "clear_check_not_valid")
	assert_eq(api.publish_calls.size(), 0)

func test_publish_rejects_when_content_changed_after_clear_check() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)
	var draft := _cleared_draft()
	draft.hp += 1 # invalidates is_clear_check_currently_valid()

	var ok: bool = await publisher.publish(draft)
	assert_false(ok)
	assert_eq(publisher.last_error_kind(), "clear_check_not_valid")
	assert_eq(api.publish_calls.size(), 0)

func test_publish_fails_safely_when_steam_is_unavailable() -> void:
	var auth := _ready_steam_auth(false, false)
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)
	var draft := _cleared_draft()

	var ok: bool = await publisher.publish(draft)
	assert_false(ok)
	assert_eq(publisher.last_error_kind(), "steam_unavailable")
	assert_eq(api.publish_calls.size(), 0)

func test_publish_fails_safely_when_steam_is_available_but_not_logged_on() -> void:
	var auth := _ready_steam_auth(true, false)
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)
	var draft := _cleared_draft()

	var ok: bool = await publisher.publish(draft)
	assert_false(ok)
	assert_eq(publisher.last_error_kind(), "steam_not_logged_on")
	assert_eq(api.publish_calls.size(), 0)

func test_publish_succeeds_end_to_end_with_fake_steam_ticket_and_fake_api() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.configure_publish_response({"ok": true, "boss_id": "abc-123", "revision": 1})
	var publisher := _publisher(auth, api)
	var draft := _cleared_draft()

	_schedule_ticket_success(auth)
	var ok: bool = await publisher.publish(draft)

	assert_true(ok)
	assert_eq(publisher.current_state(), RBMBossPublisher.PublishState.SUCCEEDED)
	assert_eq(publisher.last_boss_id(), "abc-123")
	assert_eq(api.publish_calls.size(), 1)
	assert_true((api.publish_calls[0]["ticket"] as String).length() > 0, "the hex ticket from Steam must actually be sent")

func test_publish_never_sends_the_ticket_before_the_steam_callback_arrives() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)
	var draft := _cleared_draft()

	var states_seen: Array = []
	publisher.state_changed.connect(func(s): states_seen.append(s))

	_schedule_ticket_success(auth)
	var ok: bool = await publisher.publish(draft)

	assert_true(ok)
	# REQUESTING_TICKET must have been observed before UPLOADING/SUCCEEDED --
	# the API call never happens until the callback (and thus the real hex
	# ticket) is in hand.
	assert_eq(states_seen[0], RBMBossPublisher.PublishState.REQUESTING_TICKET)
	assert_true(states_seen.has(RBMBossPublisher.PublishState.UPLOADING))
	assert_eq(api.publish_calls.size(), 1)

func test_publish_surfaces_edge_function_rejection_as_failure() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.configure_publish_response({"ok": false, "error_kind": "not_configured", "message": "Steam auth not ready"})
	var publisher := _publisher(auth, api)
	var draft := _cleared_draft()

	_schedule_ticket_success(auth)
	var ok: bool = await publisher.publish(draft)

	assert_false(ok, "a not_configured response from the server must never be treated as a successful publish")
	assert_eq(publisher.last_error_kind(), "not_configured")

func test_double_tap_while_publishing_is_ignored_not_a_second_request() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)
	var draft := _cleared_draft()

	# Both deferred calls are queued below, but neither can actually run
	# until this test function itself suspends -- which only happens once
	# the first publish() call underneath reaches its own internal await
	# (after already flipping state to REQUESTING_TICKET synchronously).
	# So by the time the deferred "second attempt" runs, the first call is
	# guaranteed to already be mid-flight.
	var second_result := {"started": true}
	var second_attempt := func():
		second_result["started"] = await publisher.publish(draft)
	second_attempt.call_deferred()
	_schedule_ticket_success(auth)

	var first_ok: bool = await publisher.publish(draft)
	await wait_process_frames(2)

	assert_true(first_ok)
	assert_false(second_result["started"], "a publish already in flight must reject a concurrent duplicate call")
	assert_eq(api.publish_calls.size(), 1)
