extends GutTest

## Phase 4D-1 — RBMOnlineBossListViewのfake駆動テスト。実HTTPへは出ない。
##
## Steamからの切り離し(2026-10): 未挑戦のテストは必ず偽のSteam(RBMFakeSteamAdapter)を
## 注入し、本物のSteamへは一切触れない。開発PCのGit管理外 steam_dev_appid.local.txt や、
## 起動中のSteamクライアントに結果が左右されないよう、このファイルの全テストでApp IDの
## 読み込み先をテスト専用の一時パス(既定は存在しない=未設定)へ差し替え、途中で失敗しても
## after_each()で必ず元に戻す(test_rbm_steam_auth.gd等と同じ確立済みパターン)。
## Steam認証ノードはadd_child_autoqfree(遅延解放)にする: チケット結果のstate_changed.emit()
## の中でテストが最後まで進んで終わることがあり、即時free()だとemit元へ戻った時に解放済みの
## ノードへ触れる(test_rbm_boss_publisher.gdの注記と同じ理由)。

const TMP_STEAM_APPID_PATH := "user://test_steam_dev_appid_online_list_view.local.txt"

## このテストで注入した偽のSteam(本物のチケットを要求していないことの確認に使う)。
var _fake_steam: RBMFakeSteamAdapter

func before_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(TMP_STEAM_APPID_PATH)
	_fake_steam = null

func after_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	if FileAccess.file_exists(TMP_STEAM_APPID_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_STEAM_APPID_PATH))

## 開発用App IDファイルがある状態(=RBMSteamConfig.is_configured())を、テスト専用の一時パスで作る。
func _simulate_dev_app_id_file() -> void:
	var file := FileAccess.open(TMP_STEAM_APPID_PATH, FileAccess.WRITE)
	file.store_string("480")
	file.close()

## 偽のSteamを注入したRBMSteamAuth。available=falseなら「利用不可」に固定する。
func _fake_steam_auth(available: bool, timeout_seconds := RBMSteamAuth.DEFAULT_TICKET_TIMEOUT_SECONDS) -> RBMSteamAuth:
	_fake_steam = RBMFakeSteamAdapter.new()
	if available:
		_fake_steam.configure_available()
		_fake_steam.configure_logged_on(true, 76561198000000001, "Tester")
		_simulate_dev_app_id_file()
	else:
		_fake_steam.configure_unavailable()
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(_fake_steam)
	auth.timeout_seconds = timeout_seconds
	add_child_autoqfree(auth)
	auth.initialize()
	return auth

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
## recorderには「利用不可」に固定した偽のSteamを注入する(既定)——ticket取得は
## 本物のSteamへ行かずに必ず安全に失敗するので、クラッシュせず"呼ばれたかどうか"
## だけを見るこのテストの目的には十分。authを渡せば成功/失敗/timeoutの経路も作れる。
func _view_with_recorder(api: RBMFakeBossApiAdapter, recorder_api: RBMFakeBossApiAdapter, auth: RBMSteamAuth = null) -> RBMOnlineBossListView:
	if auth == null:
		auth = _fake_steam_auth(false)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
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
	assert_true(view._status_label.text.length() > 0, "sanity: ticket acquisition fails safely (Steam is fixed unavailable by the injected fake) and must still show a status message, not crash")
	_assert_no_real_steam_and_no_ticket(view)

func test_unchallenged_category_forwards_the_current_mode_to_the_recorder() -> void:
	# ticket取得自体は失敗するが(偽のSteamを利用不可に固定)、_recorder.list_unchallenged_bosses()
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
	_assert_no_real_steam_and_no_ticket(view)

## 未挑戦の取得に使ったrecorderが、注入した偽のSteamを使い(本物のRBMSteamAuth/
## RBMSteamAdapterを自分で作っていない)、チケットを1枚も要求していないこと。
func _assert_no_real_steam_and_no_ticket(view: RBMOnlineBossListView) -> void:
	var recorder: RBMOnlineChallengeRecorder = view._recorder
	assert_true(recorder._steam_auth.adapter_for_testing() is RBMFakeSteamAdapter, "the recorder uses the injected fake Steam")
	assert_eq(recorder._steam_auth.adapter_for_testing(), _fake_steam)
	for child in recorder.get_children():
		assert_false(child is RBMSteamAuth, "the recorder never builds its own (real) Steam auth")
	assert_false(recorder._steam_auth.is_available(), "Steam is fixed unavailable")
	assert_eq(_fake_steam.last_issued_handle(), 0, "no Steam ticket was requested")

## 開発PCのように開発用App IDファイルがあっても(=RBMSteamConfig.is_configured())、
## 未挑戦のテストは偽のSteamだけを使い、本物のSteamへチケットを要求しない。
func test_unchallenged_tests_never_reach_real_steam_even_with_a_dev_app_id_file() -> void:
	_simulate_dev_app_id_file()
	assert_true(RBMSteamConfig.is_configured(), "sanity: the dev App ID file is visible, like on a developer PC")
	var api := _fake_api()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var view := _view_with_recorder(api, recorder_api)

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦")
	_assert_no_real_steam_and_no_ticket(view)
	assert_eq(recorder_api.list_unchallenged_calls.size(), 0, "without a ticket the server is never asked either")

## 偽のSteamが使える状態での各経路(成功は次のtest_unchallenged_category_renders_bosses_the_recorder_returns)。
## どの経路でも本物のSteamへは行かず、Steam認証ノードは遅延解放なので、チケット結果の
## emitの中でテストが終わっても解放済みのノードに触れない。
func test_unchallenged_ticket_failure_shows_the_error_without_rows() -> void:
	var api := _fake_api()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var view := _view_with_recorder(api, recorder_api, _fake_steam_auth(true))
	_fake_steam.fire_ticket_response.call_deferred(1, RBMSteamAdapter.RESULT_OK + 1, 0, PackedByteArray())

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦")
	assert_eq(view._rows_container.get_child_count(), 0)
	assert_true(view._status_label.text.contains("steam_ticket_failed"), "the failure is shown")
	assert_eq(_fake_steam.last_issued_handle(), 1, "the fake (not real Steam) issued the ticket handle")
	assert_true(_fake_steam.cancelled_handles().has(1), "the failed handle is cancelled")
	assert_eq(recorder_api.list_unchallenged_calls.size(), 0)

func test_unchallenged_ticket_timeout_shows_the_error_without_rows() -> void:
	var api := _fake_api()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	# コールバックを一度も送らない -> 0.1秒のtimeout経路(以前クラッシュした経路と同じ)
	var view := _view_with_recorder(api, recorder_api, _fake_steam_auth(true, 0.1))

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦")
	assert_eq(view._rows_container.get_child_count(), 0)
	assert_true(view._status_label.text.contains("steam_ticket_failed"), "the timeout is shown")
	assert_eq(_fake_steam.last_issued_handle(), 1)
	# RBMSteamAuth._on_timeout()はfailedを知らせた後でhandleを返すので、1フレーム待ってから確かめる
	# (この間もSteam認証ノードは遅延解放なので生きている)。
	await get_tree().process_frame
	assert_true(_fake_steam.cancelled_handles().has(1), "the timed-out handle is cancelled")
	assert_eq(recorder_api.list_unchallenged_calls.size(), 0)

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
	# App IDの読み込み先はbefore_each()でテスト専用の一時パスへ差し替え済み(after_each()で必ず戻す)
	_simulate_dev_app_id_file()
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

# ---------------------------------------------------------------------------
# オンライン版「人気」/「高難度」(2026-09) — CATEGORY_POPULAR/
# CATEGORY_HIGH_DIFFICULTYの配線。ランキング自体はlist-popular-bosses/
# list-hard-bosses(Edge Function)側で計算する——クライアントは結果を
# そのまま表示するだけで再ソートしない。
# ---------------------------------------------------------------------------

func test_popular_category_calls_list_popular_bosses_not_the_plain_list_api() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(api.list_popular_calls.size(), 1)
	assert_eq(api.list_calls.size(), 0, "人気はlist-bossesではなくlist-popular-bosses経由でなければならない")

func test_high_difficulty_category_calls_list_hard_bosses_not_the_plain_list_api() -> void:
	var api := _fake_api()
	api.configure_list_hard_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	assert_eq(api.list_hard_calls.size(), 1)
	assert_eq(api.list_calls.size(), 0, "高難度はlist-bossesではなくlist-hard-bosses経由でなければならない")

func test_popular_category_forwards_the_current_mode() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(str(api.list_popular_calls[0].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_POPULAR)

func test_high_difficulty_category_forwards_the_current_mode() -> void:
	var api := _fake_api()
	api.configure_list_hard_response({"ok": true, "bosses": []})
	var view := _view_with(api)

	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	assert_eq(str(api.list_hard_calls[0].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY)

func test_popular_category_renders_bosses_the_adapter_returns_in_server_order() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({
		"ok": true,
		"bosses": [
			{"id": "most-popular", "boss_name": "最人気ボス", "author_name": "A"},
			{"id": "least-popular", "boss_name": "低人気ボス", "author_name": "B"},
		],
	})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")

	assert_eq(view._rows_container.get_child_count(), 2)
	var first_row: Button = view._rows_container.get_child(0)
	assert_eq(first_row.name, "OnlineBossRow_most-popular")

# ---------------------------------------------------------------------------
# 2026-10 — 人気/高難度の行に順位と数値(人気=挑戦者数、高難度=クリア率)を出す。
# 高難度のクリア率は「クリアした人数/挑戦した人数」の通常の割合で、順位用の
# 補正クリア率は出さない。言語設定に左右されないよう、期待値もtr()と同じ
# TranslationServer.translate()で組み立てる。
# ---------------------------------------------------------------------------

func _row_text(rank: int, boss_name: String, author: String, extra: String = "") -> String:
	var text := "%d　%s" % [rank, TranslationServer.translate("%s　(作者: %s)") % [boss_name, author]]
	return text + ("　" + extra if not extra.is_empty() else "")

## refresh()は前回の行をqueue_free()するので、同じフレーム内では消える予定の行を除いて読む。
func _row_texts(view: RBMOnlineBossListView) -> Array:
	var texts := []
	for row in view._rows_container.get_children():
		if not row.is_queued_for_deletion():
			texts.append((row as Button).text)
	return texts

func test_popular_rows_show_the_rank_and_the_number_of_challengers() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": [
		{"id": "a", "boss_name": "ボスA", "author_name": "AAA", "unique_challengers": 128},
		{"id": "b", "boss_name": "ボスB", "author_name": "BBB", "unique_challengers": 104},
	]})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")

	var people := TranslationServer.translate("挑戦者 %d人")
	assert_eq(_row_texts(view), [
		_row_text(1, "ボスA", "AAA", people % 128),
		_row_text(2, "ボスB", "BBB", people % 104),
	])
	assert_eq(view._rows_container.get_child(0).name, "OnlineBossRow_a", "rows keep their names (selection is unchanged)")

func test_high_difficulty_rows_show_the_rank_and_the_plain_clear_rate_not_the_corrected_one() -> void:
	var api := _fake_api()
	api.configure_list_hard_response({"ok": true, "bosses": [
		{"id": "c", "boss_name": "ボスC", "author_name": "CCC", "unique_challengers": 25, "unique_clearers": 3},
		{"id": "d", "boss_name": "ボスD", "author_name": "DDD", "unique_challengers": 50, "unique_clearers": 9},
	]})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")

	var rate := TranslationServer.translate("クリア率 %s")
	assert_eq(_row_texts(view), [
		_row_text(1, "ボスC", "CCC", rate % "12.0%"),
		_row_text(2, "ボスD", "DDD", rate % "18.0%"),
	])
	# 補正クリア率 (3+1)/(25+2)=14.8% はどこにも出さない
	assert_false(str(_row_texts(view)).contains("14.8"))

func test_ranking_rows_from_a_server_without_numbers_show_the_rank_only() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": [{"id": "a", "boss_name": "ボスA", "author_name": "AAA"}]})
	api.configure_list_hard_response({"ok": true, "bosses": [{"id": "c", "boss_name": "ボスC", "author_name": "CCC"}]})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(_row_texts(view), [_row_text(1, "ボスA", "AAA")], "no misleading 0 challengers")
	await get_tree().process_frame
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	assert_eq(_row_texts(view), [_row_text(1, "ボスC", "CCC")], "no misleading 0% clear rate")

func test_online_and_new_rows_have_no_rank_or_numbers() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": [
		{"id": "a", "boss_name": "ボスA", "author_name": "AAA", "unique_challengers": 128},
	]})
	var view := _view_with(api)
	for category in [RBMOnlineBossListView.CATEGORY_ONLINE, RBMOnlineBossListView.CATEGORY_NEW]:
		await view.refresh_with("", category, "一覧")
		assert_eq(_row_texts(view), [TranslationServer.translate("%s　(作者: %s)") % ["ボスA", "AAA"]], category)
		await get_tree().process_frame

func test_a_failed_ranking_fetch_shows_the_error_and_no_rows() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": false, "error_kind": "db_error", "message": "boom"})
	api.configure_list_hard_response({"ok": false, "error_kind": "network_error", "message": "timeout"})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(view._rows_container.get_child_count(), 0)
	assert_true(view._status_label.text.contains("db_error"), "the status line tells the fetch failed")
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	assert_eq(view._rows_container.get_child_count(), 0)
	assert_true(view._status_label.text.contains("network_error"))

## 2026-10 実画面で発見: 親が既に大きさを持っている時に一覧を作ると、一覧の欄が0の高さに
## なって行が1つも見えなかった(挑戦画面の中では常にこの状態)。親いっぱいに広がり、
## 行が見える範囲に入ることを確かめる。
func test_the_list_fills_its_parent_so_the_rows_are_visible() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": [{"id": "a", "boss_name": "ボスA", "author_name": "AAA", "unique_challengers": 3}]})
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var view := RBMOnlineBossListView.new()
	view.set_api_adapter_for_testing(api)
	host.add_child(view)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	await get_tree().process_frame

	assert_eq(view.size, host.size, "the list covers the whole challenge screen")
	var scroll: ScrollContainer = view.find_child("OnlineListScroll", true, false)
	assert_gt(scroll.size.y, 300.0, "the list area has a real height")
	var row: Control = view._rows_container.get_child(0)
	assert_true(scroll.get_global_rect().encloses(row.get_global_rect()), "the first row is inside the visible list area")
