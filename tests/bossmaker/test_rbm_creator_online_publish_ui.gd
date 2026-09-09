extends GutTest

## Phase 4C-7 — Creator STEP5のオンライン公開ボタンのfake駆動UIテスト。
## 実Steam/実Supabaseへは一切出ない。既存のローカル公開ボタン
## (PublishButton/UnpublishButton)の挙動には一切触れない。

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _summary_of(creator: RBMCreatorMain) -> RBMCreatorStep7Summary:
	return creator._step_views[4] as RBMCreatorStep7Summary

func _make_cleared(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "オンライン公開UIテストボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")
	creator.draft.record_clear_check_success()

func _ready_steam_auth(available := true, logged_on := true) -> RBMSteamAuth:
	var fake := RBMFakeSteamAdapter.new()
	if available:
		fake.configure_available()
	else:
		fake.configure_unavailable()
	fake.configure_logged_on(logged_on, 76561198000000001, "Tester")
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	add_child_autofree(auth)
	auth.initialize()
	return auth

func _install_fake_publisher(summary: RBMCreatorStep7Summary, auth: RBMSteamAuth, api: RBMFakeBossApiAdapter) -> RBMBossPublisher:
	add_child_autofree(api)
	var publisher := RBMBossPublisher.new()
	add_child_autofree(publisher)
	publisher.set_steam_auth_for_testing(auth)
	publisher.set_api_adapter_for_testing(api)
	summary.set_boss_publisher_for_testing(publisher)
	return publisher

func test_online_publish_button_exists_and_is_disabled_before_clear_check() -> void:
	var creator := _new_creator()
	creator.go_to_step(5)
	var summary := _summary_of(creator)
	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	assert_not_null(button)
	assert_true(button.disabled, "クリアチェック未達成の間はオンライン公開ボタンも無効")

func test_online_publish_button_is_enabled_after_clear_check() -> void:
	var creator := _new_creator()
	_make_cleared(creator)
	creator.go_to_step(5)
	var summary := _summary_of(creator)
	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	assert_false(button.disabled)

func test_online_publish_button_does_not_affect_the_local_publish_button() -> void:
	var creator := _new_creator()
	_make_cleared(creator)
	creator.go_to_step(5)
	var summary := _summary_of(creator)
	var local_button: Button = summary.find_child("PublishButton", true, false)
	assert_not_null(local_button)
	assert_false(local_button.disabled)
	assert_false(creator.draft.is_published(), "opening STEP5 alone must not trigger the existing local publish flow")

func test_pressing_online_publish_without_steam_shows_a_safe_status_message() -> void:
	var creator := _new_creator()
	_make_cleared(creator)
	creator.go_to_step(5)
	var summary := _summary_of(creator)
	var auth := _ready_steam_auth(false, false)
	var api := RBMFakeBossApiAdapter.new()
	_install_fake_publisher(summary, auth, api)

	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	button.pressed.emit()
	await wait_process_frames(2)

	var status_label: Label = summary.find_child("OnlinePublishStatusLabel", true, false)
	assert_true(status_label.text.length() > 0)
	assert_eq(api.publish_calls.size(), 0, "Steamが使えない間はEdge Functionへ一切送信しない")

func test_pressing_online_publish_succeeds_end_to_end_with_fakes() -> void:
	var creator := _new_creator()
	_make_cleared(creator)
	creator.go_to_step(5)
	var summary := _summary_of(creator)
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	api.configure_publish_response({"ok": true, "boss_id": "abc", "revision": 1})
	var publisher := _install_fake_publisher(summary, auth, api)

	var fake_steam := auth.adapter_for_testing() as RBMFakeSteamAdapter
	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	button.pressed.emit()
	await wait_process_frames(1)
	fake_steam.fire_ticket_response(fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)

	assert_eq(publisher.current_state(), RBMBossPublisher.PublishState.SUCCEEDED)
	assert_eq(api.publish_calls.size(), 1)
	var status_label: Label = summary.find_child("OnlinePublishStatusLabel", true, false)
	assert_true(status_label.text.contains("成功"))
