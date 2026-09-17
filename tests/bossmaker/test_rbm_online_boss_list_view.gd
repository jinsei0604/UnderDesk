extends GutTest

## Phase 4D-1 — RBMOnlineBossListViewのfake駆動テスト。実HTTPへは出ない。

func _view_with(api: RBMFakeBossApiAdapter) -> RBMOnlineBossListView:
	var view := RBMOnlineBossListView.new()
	view.set_api_adapter_for_testing(api)
	add_child_autofree(view)
	return view

func _fake_api() -> RBMFakeBossApiAdapter:
	var api := RBMFakeBossApiAdapter.new()
	add_child_autofree(api)
	return api

## オンライン版「未挑戦」(2026-09) — recorder自身のSteam ticket取得成功/
## 失敗の詳細な挙動はtest_rbm_online_challenge_recorder.gdで、挑戦開始/
## クリア記録との組み合わせはtest_rbm_challenge_hub_and_discovery.gdで
## それぞれ別途検証済み。ここではview自身の責務——「category==UNCHALLENGED
## の時だけ_api_adapter.list_bosses()ではなくrecorder経由の
## list_unchallenged_bosses()を呼ぶ」という配線だけを検証する。
## Steamが未設定(is_available()==false)の素のrecorderを渡す——ticket取得
## 自体は必ず安全に失敗するので、クラッシュせず"呼ばれたかどうか"だけを
## 見るこのテストの目的には十分。
func _view_with_recorder(api: RBMFakeBossApiAdapter, recorder_api: RBMFakeBossApiAdapter) -> RBMOnlineBossListView:
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_api_adapter_for_testing(recorder_api)
	var view := RBMOnlineBossListView.new()
	view.set_api_adapter_for_testing(api)
	view.set_recorder_for_testing(recorder)
	add_child_autofree(view)
	return view

func test_refresh_shows_an_empty_state_message_when_there_are_no_published_bosses() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh()
	assert_eq(view._rows_container.get_child_count(), 0)
	assert_true(view._status_label.text.length() > 0)

func test_refresh_populates_one_row_per_boss() -> void:
	var api := _fake_api()
	api.configure_list_response({
		"ok": true,
		"bosses": [
			{"id": "b1", "boss_name": "ボスA", "author_name": "作者A"},
			{"id": "b2", "boss_name": "ボスB", "author_name": "作者B"},
		],
	})
	var view := _view_with(api)

	await view.refresh()
	assert_eq(view._rows_container.get_child_count(), 2)
	assert_eq(view._status_label.text, "")

func test_refresh_shows_an_error_message_on_network_failure() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": false, "error_kind": "network_error", "message": "timeout"})
	var view := _view_with(api)

	await view.refresh()
	assert_eq(view._rows_container.get_child_count(), 0)
	assert_true(view._status_label.text.length() > 0)

func test_selecting_a_row_emits_boss_selected_with_a_battle_ready_draft() -> void:
	var maker_draft := RBMCreatorDraft.new()
	maker_draft.boss_name = "選択テストボス"
	maker_draft.hp = 1000
	maker_draft.atk = 100
	maker_draft.spd = 50
	maker_draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	maker_draft.add_party_character("hero")
	maker_draft.record_clear_check_success()
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(maker_draft)["payload"]

	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": [{"id": "b1", "boss_name": "選択テストボス", "author_name": ""}]})
	api.configure_get_response({"ok": true, "boss": {"id": "b1", "boss_name": "選択テストボス", "author_name": "", "revision": 1, "payload": payload}})
	var view := _view_with(api)
	await view.refresh()

	var received: Array = []
	view.boss_selected.connect(func(boss_id, draft, boss_name, author_name): received.append([boss_id, draft, boss_name, author_name]))

	var row: Button = view._rows_container.get_child(0)
	row.pressed.emit()
	await wait_process_frames(1)

	assert_eq(received.size(), 1)
	assert_eq(received[0][0], "b1")
	assert_true(received[0][1] is RBMCreatorDraft)
	assert_eq(received[0][2], "選択テストボス")

func test_back_requested_signal_fires_on_back_button_press() -> void:
	var api := _fake_api()
	var view := _view_with(api)
	# GDScript lambdas capture outer local variables by value, not by
	# reference -- a plain `var back_fired := false` mutated inside the
	# connected lambda would never be visible here. Use a Dictionary (an
	# Object reference) so the mutation is actually observable.
	var state := {"back_fired": false}
	view.back_requested.connect(func(): state["back_fired"] = true)
	var back_button: Button = view.find_child("OnlineListBackButton", true, false)
	assert_not_null(back_button, "OnlineListBackButton must exist once the view has entered the tree")
	back_button.pressed.emit()
	assert_true(state["back_fired"])

# ---------------------------------------------------------------------------
# 挑戦ハブ SIMPLE/HARDCORE/新着連携(2026-09) — current mode/category、
# およびlist-bossesへの受け渡し。
# ---------------------------------------------------------------------------

func test_default_state_is_online_category_with_no_mode_filter() -> void:
	var api := _fake_api()
	var view := _view_with(api)
	assert_eq(view.current_mode(), "")
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_ONLINE)

func test_refresh_with_passes_mode_through_to_the_api_adapter() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMOnlineBossListView.CATEGORY_ONLINE, "SIMPLE")
	assert_eq(api.list_calls.size(), 1)
	assert_eq(str(api.list_calls[0].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(view.current_mode(), RBMCreatorDraft.CREATOR_MODE_SIMPLE)

	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_ONLINE, "HARDCORE")
	assert_eq(api.list_calls.size(), 2)
	assert_eq(str(api.list_calls[1].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)

func test_refresh_with_updates_current_category_and_title() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_NEW, "新着")
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_NEW)
	var title_label: Label = view.find_child("OnlineListTitleLabel", true, false)
	assert_eq(title_label.text, "新着")

## 「モードを切り替えたら、現在選択しているカテゴリを維持したまま
## 一覧を再取得/再表示する」——素のrefresh()(例: 「更新」ボタン)は
## 直前にrefresh_with()で設定したmode/categoryをそのまま使い続ける。
func test_plain_refresh_reuses_the_last_mode_and_category() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_NEW, "HARDCORE・新着")
	await view.refresh()

	assert_eq(api.list_calls.size(), 2)
	assert_eq(str(api.list_calls[1].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_NEW)

# ---------------------------------------------------------------------------
# オンライン版「未挑戦」(2026-09) — CATEGORY_UNCHALLENGEDの配線。
# ---------------------------------------------------------------------------

func test_unchallenged_category_calls_the_recorder_not_the_plain_list_api() -> void:
	var api := _fake_api()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var view := _view_with_recorder(api, recorder_api)

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦")

	assert_eq(api.list_calls.size(), 0, "未挑戦はlist-bossesではなくlist-unchallenged-bosses経由でなければならない")
	assert_true(view._status_label.text.length() > 0, "sanity: ticket acquisition fails safely (Steam not configured in tests) and must still show a status message, not crash")

func test_unchallenged_category_forwards_the_current_mode_to_the_recorder() -> void:
	# ticket取得自体は失敗するが(Steam未設定)、_recorder.list_unchallenged_bosses()
	# 呼び出し自体がmodeを正しく受け取って渡すことは、recorderがticketを
	# 取得する前にmode引数を保持している時点で検証できる——ここでは
	# view.current_mode()がrefresh_with()の引数どおり更新されることを確認する
	# (実際にAPIへ渡るところまではtest_rbm_online_challenge_recorder.gdで
	# 別途検証済み)。
	var api := _fake_api()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var view := _view_with_recorder(api, recorder_api)

	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦")
	assert_eq(view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_UNCHALLENGED)
	assert_eq(api.list_calls.size(), 0)

func test_unchallenged_category_renders_bosses_the_recorder_returns() -> void:
	var api := _fake_api()
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	recorder.set_api_adapter_for_testing(recorder_api)
	# Steamが利用可能かどうかに関わらずrecorderの呼び出し結果をそのまま
	# 描画するというview側の責務だけを検証したいので、ここではrecorder
	# 自体をテスト用にオーバーライドする代わりに、RBMOnlineChallengeRecorder
	# を経由せず直接list-unchallenged-bosses相当の結果を返すfakeにする
	# ——RBMFakeBossApiAdapter.configure_list_unchallenged_response()は
	# recorderがSteam ticket取得に成功して初めて呼ばれるため、この
	# テストではrecorder自体のticket取得成功パスを再現する。
	var fake_steam := RBMFakeSteamAdapter.new()
	fake_steam.configure_available()
	fake_steam.configure_logged_on(true, 76561198000000001, "Tester")
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake_steam)
	add_child_autoqfree(auth)
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("user://test_steam_dev_appid_online_list_view.local.txt")
	var file := FileAccess.open("user://test_steam_dev_appid_online_list_view.local.txt", FileAccess.WRITE)
	file.store_string("480")
	file.close()
	auth.initialize()
	recorder.set_steam_auth_for_testing(auth)
	recorder_api.configure_list_unchallenged_response({
		"ok": true,
		"bosses": [{"id": "u1", "boss_name": "未挑戦ボス", "author_name": "作者"}],
	})

	var view := RBMOnlineBossListView.new()
	view.set_api_adapter_for_testing(api)
	view.set_recorder_for_testing(recorder)
	add_child_autofree(view)

	fake_steam.fire_ticket_response.call_deferred(1, RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	# request_web_api_ticket()が発行するhandleは1から始まる(このrecorder
	# インスタンスの最初の要求のため)——test_rbm_online_challenge_recorder.gd
	# の_schedule_ticket_success()と同じ理由でcall_deferred()を使う。
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦")

	assert_eq(view._rows_container.get_child_count(), 1)
	assert_eq(view._status_label.text, "")

	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	if FileAccess.file_exists("user://test_steam_dev_appid_online_list_view.local.txt"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_steam_dev_appid_online_list_view.local.txt"))

## サーバー側(list-bosses)が既にpublished_at降順で返す前提——クライアントは
## 受け取った順のままカードを並べる(再ソートしない)。
func test_rows_render_in_the_order_the_server_returned_them() -> void:
	var api := _fake_api()
	api.configure_list_response({
		"ok": true,
		"bosses": [
			{"id": "newer", "boss_name": "後で公開", "author_name": "A", "creator_mode": "simple"},
			{"id": "older", "boss_name": "先に公開", "author_name": "B", "creator_mode": "simple"},
		],
	})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_NEW, "新着")

	assert_eq(view._rows_container.get_child_count(), 2)
	var first_row: Button = view._rows_container.get_child(0)
	assert_eq(first_row.name, "OnlineBossRow_newer")
