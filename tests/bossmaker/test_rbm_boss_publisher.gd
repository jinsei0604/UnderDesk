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
##
## Steam App ID環境分離（2026-09-13）: test_rbm_steam_auth.gdと同じ確立済み
## パターン。修正前は_ready_steam_auth()がRBMFakeSteamAdapter.configure_
## available()でfakeを「利用可能」に設定していても、RBMSteamAuth.
## initialize()が先にRBMSteamConfig.is_configured()を確認するため、開発者
## PCのGit管理外ローカルファイル(steam_dev_appid.local.txt)の有無に
## テスト結果が左右されていた（そのファイルが無いfresh checkout/CIでは
## このファイルの公開/取り下げ系テストがsteam_unavailableで失敗する一方、
## たまたまそのファイルが存在する環境ではPASSしてしまう、という再現性の
## ない状態だった）。他のテストへ絶対に影響しないよう、テスト専用の
## 一時パスへ差し替え、after_each()で必ず元に戻す。
var _tmp_steam_appid_path := "user://test_steam_dev_appid_boss_publisher.local.txt"

func before_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_steam_appid_path)
	var file := FileAccess.open(_tmp_steam_appid_path, FileAccess.WRITE)
	file.store_string("480")
	file.close()

func after_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	if FileAccess.file_exists(_tmp_steam_appid_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_steam_appid_path))

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

# ---------------------------------------------------------------------------
# unpublish() — 公開UI整理（2026-09-10）: ソフト取り下げ。DB上のデータは
# 削除せず、既存のunpublish-boss Edge Function(is_published=falseへ戻す
# サーバ側実装、ここでは変更しない)を叩くだけ。認証経路はpublish()と共通。
# ---------------------------------------------------------------------------

func test_unpublish_fails_safely_when_steam_is_unavailable() -> void:
	var auth := _ready_steam_auth(false, false)
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)

	var ok: bool = await publisher.unpublish("some-boss-id")
	assert_false(ok)
	assert_eq(publisher.last_error_kind(), "steam_unavailable")
	assert_eq(api.unpublish_calls.size(), 0)

func test_unpublish_rejects_an_empty_boss_id_without_touching_steam_or_the_api() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(auth, api)

	var ok: bool = await publisher.unpublish("")
	assert_false(ok)
	assert_eq(api.unpublish_calls.size(), 0)

func test_unpublish_succeeds_end_to_end_with_fake_steam_ticket_and_fake_api() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.configure_unpublish_response({"ok": true})
	var publisher := _publisher(auth, api)

	_schedule_ticket_success(auth)
	var ok: bool = await publisher.unpublish("abc-123")

	assert_true(ok)
	assert_eq(publisher.current_state(), RBMBossPublisher.PublishState.SUCCEEDED)
	assert_eq(api.unpublish_calls.size(), 1)
	assert_eq(api.unpublish_calls[0]["boss_id"], "abc-123")
	assert_true((api.unpublish_calls[0]["ticket"] as String).length() > 0, "the hex ticket from Steam must actually be sent")

func test_unpublish_surfaces_edge_function_rejection_as_failure() -> void:
	var auth := _ready_steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.configure_unpublish_response({"ok": false, "error_kind": "forbidden", "message": "not the owner"})
	var publisher := _publisher(auth, api)

	_schedule_ticket_success(auth)
	var ok: bool = await publisher.unpublish("abc-123")

	assert_false(ok)
	assert_eq(publisher.last_error_kind(), "forbidden")

func test_is_steam_available_reflects_the_injected_fake_without_a_network_call() -> void:
	var available_auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher(available_auth, api)
	assert_true(publisher.is_steam_available())

	var unavailable_auth := _ready_steam_auth(false, false)
	var api2 := RBMFakeBossApiAdapter.new()
	var publisher2 := _publisher(unavailable_auth, api2)
	assert_false(publisher2.is_steam_available())

# ---------------------------------------------------------------------------
# check_online_published() — サーバー同期（2026-09-11）: online_publishedは
# ローカルキャッシュに過ぎず最終的な正はSupabase側。既存のget-boss(公開済み
# の行だけを返す)をそのまま使い、新しいAPIは増やさない。Steamチケットは
# 不要（get-bossは認証不要の公開読み取りエンドポイント）——auth無しの
# publisherでもテストできることそのものが、この経路がSteamに依存しない
# ことの裏付けにもなる。
# ---------------------------------------------------------------------------

func _publisher_no_auth(api: RBMFakeBossApiAdapter) -> RBMBossPublisher:
	add_child_autofree(api)
	var publisher := RBMBossPublisher.new()
	add_child_autofree(publisher)
	publisher.set_api_adapter_for_testing(api)
	return publisher

func test_check_online_published_returns_published_when_get_boss_succeeds() -> void:
	var api := RBMFakeBossApiAdapter.new()
	api.configure_get_response({"ok": true, "boss": {"id": "abc-123"}})
	var publisher := _publisher_no_auth(api)

	var result: Dictionary = await publisher.check_online_published("abc-123")
	assert_eq(result.get("state"), "published")
	assert_eq(api.get_calls, ["abc-123"])

## get-boss(supabase/functions/get-boss/index.ts)はis_published=trueの行
## だけをクエリし、該当なしならHTTP 404 + error_kind "not_found" を返す
## （存在しない場合と非公開の場合を区別しない設計、実装済みEdge Function
## のコード確認済み）——自分が過去にpublish()した既知のboss_idに対して
## この404が返るのは、soft unpublishでis_published=falseへ戻された場合
## だけなので、この文脈では安全に「非公開」と解釈できる。
func test_check_online_published_returns_not_published_on_http_404() -> void:
	var api := RBMFakeBossApiAdapter.new()
	api.configure_get_response({"ok": false, "error_kind": "http_4xx", "http_status": 404, "message": "not found"})
	var publisher := _publisher_no_auth(api)

	var result: Dictionary = await publisher.check_online_published("abc-123")
	assert_eq(result.get("state"), "not_published")

## 最重要のユーザー確定仕様: 「非公開と確認できた」と「サーバーへ接続
## できなかった」を混同しない——network_error/5xx/その他の4xx/JSON解析
## 失敗など、404以外のあらゆる失敗はすべて"unknown"にまとめ、呼び出し側
## （RBMCreatorStep7Summary）がローカルキャッシュを一切書き換えない前提を
## 支える。
func test_check_online_published_returns_unknown_on_network_error() -> void:
	var api := RBMFakeBossApiAdapter.new()
	api.configure_get_response({"ok": false, "error_kind": "network_error", "http_status": -1, "message": "DNS failure"})
	var publisher := _publisher_no_auth(api)

	var result: Dictionary = await publisher.check_online_published("abc-123")
	assert_eq(result.get("state"), "unknown")

func test_check_online_published_returns_unknown_on_http_5xx() -> void:
	var api := RBMFakeBossApiAdapter.new()
	api.configure_get_response({"ok": false, "error_kind": "http_5xx", "http_status": 503, "message": "server error"})
	var publisher := _publisher_no_auth(api)

	var result: Dictionary = await publisher.check_online_published("abc-123")
	assert_eq(result.get("state"), "unknown")

## 404以外の4xx（400/403/429等）も"not_found"と混同せず"unknown"に
## まとめる——RBMSupabaseResponse.parse()は全4xxを一律"http_4xx"として
## しか分類しないため、http_statusの実値(404かどうか)だけで判定する必要が
## あることの直接的な裏付け。
func test_check_online_published_treats_non_404_4xx_as_unknown_not_not_published() -> void:
	var api := RBMFakeBossApiAdapter.new()
	api.configure_get_response({"ok": false, "error_kind": "http_4xx", "http_status": 429, "message": "rate limited"})
	var publisher := _publisher_no_auth(api)

	var result: Dictionary = await publisher.check_online_published("abc-123")
	assert_eq(result.get("state"), "unknown")

func test_check_online_published_returns_unknown_for_an_empty_boss_id_without_calling_the_api() -> void:
	var api := RBMFakeBossApiAdapter.new()
	var publisher := _publisher_no_auth(api)

	var result: Dictionary = await publisher.check_online_published("")
	assert_eq(result.get("state"), "unknown")
	assert_eq(api.get_calls.size(), 0)
