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
# 2026-10 — 人気/高難度のカードに順位と数値(人気=挑戦者数、高難度=クリア率)を出す。
# 高難度のクリア率は「クリアした人数/挑戦した人数」の通常の割合。カード(RBMOnlineBossCard)の
# 各ラベルを名前で読む。言語設定に左右されないよう、期待値もtr()と同じ
# TranslationServer.translate()で組み立てる。
# ---------------------------------------------------------------------------

## カードの中のラベルの文字(無ければ"<none>")。
func _card_text(card: Node, label_name: String) -> String:
	var label := card.find_child(label_name, true, false) as Label
	return label.text if label != null else "<none>"

## 表示中のカードごとに、名前を付けたラベルの文字を集める。
func _card_texts(view: RBMOnlineBossListView, label_name: String) -> Array:
	var texts := []
	for card in view._rows_container.get_children():
		texts.append(_card_text(card, label_name))
	return texts

## カードの中の全ラベルの文字(何かが「どこにも出ていない」ことを確かめる用)。
func _all_card_texts(view: RBMOnlineBossListView) -> String:
	var texts := []
	for label in view._rows_container.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return " | ".join(texts)

func test_popular_rows_show_the_rank_and_the_number_of_challengers() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": [
		{"id": "a", "boss_name": "ボスA", "author_name": "AAA", "unique_challengers": 128, "unique_clearers": 32},
		{"id": "b", "boss_name": "ボスB", "author_name": "BBB", "unique_challengers": 104, "unique_clearers": 13},
	]})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")

	var people := TranslationServer.translate("%d人")
	assert_eq(_card_texts(view, "RankBadge"), ["1", "2"])
	assert_eq(_card_texts(view, "NameLabel"), ["ボスA", "ボスB"])
	assert_eq(_card_texts(view, "AuthorLabel"), [TranslationServer.translate("by %s") % "AAA", TranslationServer.translate("by %s") % "BBB"])
	assert_eq(_card_texts(view, "ChallengersValue"), [people % 128, people % 104])
	assert_eq(_card_texts(view, "ClearRateValue"), ["25.0%", "12.5%"])
	var first: Label = view._rows_container.get_child(0).find_child("ChallengersValue", true, false)
	var other: Label = view._rows_container.get_child(0).find_child("ClearRateValue", true, false)
	assert_gt(first.get_theme_font_size("font_size"), other.get_theme_font_size("font_size"), "popular emphasizes the number of challengers")
	assert_eq(view._rows_container.get_child(0).name, "OnlineBossRow_a", "rows keep their names (selection is unchanged)")

func test_high_difficulty_rows_show_the_rank_and_the_plain_clear_rate_not_the_corrected_one() -> void:
	var api := _fake_api()
	api.configure_list_hard_response({"ok": true, "bosses": [
		{"id": "c", "boss_name": "ボスC", "author_name": "CCC", "unique_challengers": 25, "unique_clearers": 3},
		{"id": "d", "boss_name": "ボスD", "author_name": "DDD", "unique_challengers": 50, "unique_clearers": 9},
	]})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")

	assert_eq(_card_texts(view, "RankBadge"), ["1", "2"])
	assert_eq(_card_texts(view, "ClearRateValue"), ["12.0%", "18.0%"])
	var rate: Label = view._rows_container.get_child(0).find_child("ClearRateValue", true, false)
	var people: Label = view._rows_container.get_child(0).find_child("ChallengersValue", true, false)
	assert_gt(rate.get_theme_font_size("font_size"), people.get_theme_font_size("font_size"), "high difficulty emphasizes the clear rate")
	# 補正クリア率 (3+1)/(25+2)=14.8% はどこにも出さない
	assert_false(_all_card_texts(view).contains("14.8"))

func test_ranking_rows_from_a_server_without_numbers_show_the_rank_only() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": [{"id": "a", "boss_name": "ボスA", "author_name": "AAA"}]})
	api.configure_list_hard_response({"ok": true, "bosses": [{"id": "c", "boss_name": "ボスC", "author_name": "CCC"}]})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(_card_texts(view, "RankBadge"), ["1"])
	assert_eq([_card_texts(view, "ChallengersValue"), _card_texts(view, "ClearRateValue")], [["—"], ["—"]], "no misleading 0 challengers")
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	assert_eq(_card_texts(view, "RankBadge"), ["1"])
	assert_eq([_card_texts(view, "ChallengersValue"), _card_texts(view, "ClearRateValue")], [["—"], ["—"]], "no misleading 0% clear rate")

func test_online_and_new_rows_have_no_rank_but_show_the_numbers() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": [
		{"id": "a", "boss_name": "ボスA", "author_name": "AAA", "unique_challengers": 128, "unique_clearers": 16},
		{"id": "z", "boss_name": "ボスZ", "author_name": "ZZZ", "unique_challengers": 0, "unique_clearers": 0},
	]})
	var view := _view_with(api)
	for category in [RBMOnlineBossListView.CATEGORY_ONLINE, RBMOnlineBossListView.CATEGORY_NEW]:
		await view.refresh_with("", category, "一覧")
		assert_eq(_card_texts(view, "RankBadge"), ["<none>", "<none>"], category)
		assert_eq(_card_texts(view, "ChallengersValue"), [TranslationServer.translate("%d人") % 128, TranslationServer.translate("%d人") % 0], category)
		assert_eq(_card_texts(view, "ClearRateValue"), ["12.5%", "—"], "%s: nobody has challenged yet -> no rate, not 0%%" % category)

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

# ---------------------------------------------------------------------------
# 2026-10 — 「オンライン」は公開中の全ボスを見て回る入口。最初の20件に続けて、
# 「さらに表示」で次の20件を一覧の末尾へ足す(サーバーのnext_cursorで続きを取る)。
# 「新着」は最新20件だけで続きは読まない。人気/高難度/未挑戦にも「さらに表示」は無い。
# ---------------------------------------------------------------------------

## <prefix>-<first>〜のcount件。
func _bosses(prefix: String, first: int, count: int) -> Array:
	var bosses := []
	for i in range(first, first + count):
		bosses.append({"id": "%s-%02d" % [prefix, i], "boss_name": "%s%02d" % [prefix, i], "author_name": "A"})
	return bosses

func _ids(prefix: String, first: int, count: int) -> Array:
	return _bosses(prefix, first, count).map(func(boss): return boss["id"])

## list-bossesの1ページ分の応答。next_cursorが空なら最後のページ。
func _page(bosses: Array, next_cursor: String = "") -> Dictionary:
	var page := {"ok": true, "bosses": bosses, "has_more": not next_cursor.is_empty()}
	if not next_cursor.is_empty():
		page["next_cursor"] = next_cursor
	return page

## 45件を20/20/5件の3ページで返すサーバー。
func _three_pages(api: RBMFakeBossApiAdapter, prefix: String = "b") -> void:
	api.configure_list_pages({
		"": _page(_bosses(prefix, 0, 20), "c1"),
		"c1": _page(_bosses(prefix, 20, 20), "c2"),
		"c2": _page(_bosses(prefix, 40, 5)),
	})

## 表示中の行のboss_id(refresh()でqueue_free()された行は除く)。
func _row_ids(view: RBMOnlineBossListView) -> Array:
	var ids := []
	for row in view._rows_container.get_children():
		if not row.is_queued_for_deletion():
			ids.append(str(row.name).trim_prefix("OnlineBossRow_"))
	return ids

func _load_more_button(view: RBMOnlineBossListView) -> Button:
	return view.find_child("OnlineListLoadMoreButton", true, false)

func _cursors(api: RBMFakeBossApiAdapter) -> Array:
	return api.list_calls.map(func(call): return call["cursor"])

func _wait_until_idle(view: RBMOnlineBossListView) -> void:
	for i in range(60):
		if not view._list_busy:
			return
		await get_tree().process_frame

func test_online_shows_the_first_20_and_a_show_more_button_when_more_exist() -> void:
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	assert_eq(_row_ids(view), _ids("b", 0, 20))
	assert_eq(_cursors(api), [""], "the first page is asked for without a cursor")
	assert_eq(int(api.list_calls[0]["limit"]), 20)
	var button := _load_more_button(view)
	assert_true(button.visible, "more exists -> show more is shown")
	assert_false(button.disabled)
	assert_eq(button.text, TranslationServer.translate("さらに表示"))

func test_show_more_appends_the_next_20_below_the_rows_already_shown() -> void:
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	var first_row := view._rows_container.get_child(0)

	await view.load_more()
	assert_eq(_row_ids(view), _ids("b", 0, 40), "20 -> 40, the new rows go after the old ones")
	assert_eq(view._rows_container.get_child(0), first_row, "the rows already shown are kept, not rebuilt")
	assert_eq(_cursors(api), ["", "c1"], "the next page is asked for with the cursor the server returned")
	assert_eq(str(api.list_calls[1]["mode"]), RBMCreatorDraft.CREATOR_MODE_SIMPLE, "the next page keeps the mode")
	assert_eq(int(api.list_calls[1]["limit"]), 20)
	assert_true(_load_more_button(view).visible)

func test_pressing_the_show_more_button_loads_the_next_page() -> void:
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	_load_more_button(view).pressed.emit()
	await _wait_until_idle(view)
	assert_eq(_row_ids(view), _ids("b", 0, 40))

func test_show_more_never_adds_a_boss_that_is_already_shown() -> void:
	var api := _fake_api()
	api.configure_list_pages({
		"": _page(_bosses("b", 0, 20), "c1"),
		"c1": _page(_bosses("b", 18, 20)), # b-18/b-19 are already on screen
	})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await view.load_more()

	var ids := _row_ids(view)
	assert_eq(ids, _ids("b", 0, 38), "each boss_id appears once, in order")
	var unique := {}
	for id in ids:
		unique[id] = true
	assert_eq(unique.size(), ids.size())

func test_show_more_disappears_after_the_last_page() -> void:
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await view.load_more()
	await view.load_more()

	assert_eq(_row_ids(view), _ids("b", 0, 45), "all 45 bosses: 20 + 20 + 5")
	assert_false(_load_more_button(view).visible, "nothing more -> show more is hidden")
	await view.load_more()
	assert_eq(_cursors(api), ["", "c1", "c2"], "no request past the last page")

func test_online_from_a_server_without_paging_fields_shows_no_show_more() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": _bosses("b", 0, 20)})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	assert_eq(_row_ids(view).size(), 20)
	assert_false(_load_more_button(view).visible, "an older list-bosses (no has_more) means no more pages")

func test_new_category_shows_only_the_newest_20_and_never_a_show_more_button() -> void:
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_NEW, "新着")

	assert_eq(_row_ids(view), _ids("b", 0, 20))
	assert_false(_load_more_button(view).visible, "the new category has no show more even when the server has more")
	await view.load_more()
	assert_eq(_cursors(api), [""], "the new category never asks for the next page")
	assert_eq(str(api.list_calls[0]["mode"]), RBMCreatorDraft.CREATOR_MODE_ADVANCED, "the new category keeps the mode")

func test_ranking_and_unchallenged_categories_never_show_the_show_more_button() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": _bosses("p", 0, 20), "has_more": true, "next_cursor": "x"})
	api.configure_list_hard_response({"ok": true, "bosses": _bosses("h", 0, 20), "has_more": true, "next_cursor": "x"})
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var view := _view_with_recorder(api, recorder_api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(_row_ids(view).size(), 20)
	assert_false(_load_more_button(view).visible)
	await get_tree().process_frame
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	assert_eq(_row_ids(view).size(), 20)
	assert_false(_load_more_button(view).visible)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦")
	assert_false(_load_more_button(view).visible)
	await view.load_more()
	assert_eq(api.list_calls.size(), 0, "none of these categories pages through list-bosses")
	_assert_no_real_steam_and_no_ticket(view)

func test_switching_mode_starts_online_over_from_the_top() -> void:
	var api := _fake_api()
	_three_pages(api, "s")
	var view := _view_with(api)
	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await view.load_more()
	assert_eq(_row_ids(view).size(), 40)

	_three_pages(api, "h")
	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	assert_eq(_row_ids(view), _ids("h", 0, 20), "only the new mode's first page, nothing left from SIMPLE")
	assert_eq(api.list_calls[2], {"limit": 20, "mode": RBMCreatorDraft.CREATOR_MODE_ADVANCED, "cursor": ""}, "the cursor is reset")
	await view.load_more()
	assert_eq(api.list_calls[3]["cursor"], "c1", "paging restarts from the new mode's first page")
	assert_eq(_row_ids(view), _ids("h", 0, 40))

func test_a_failed_show_more_keeps_the_rows_and_can_be_retried() -> void:
	var api := _fake_api()
	api.configure_list_pages({
		"": _page(_bosses("b", 0, 20), "c1"),
		"c1": {"ok": false, "error_kind": "network_error", "message": "timeout"},
	})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await view.load_more()

	assert_eq(_row_ids(view), _ids("b", 0, 20), "the rows already shown stay")
	assert_true(view._more_error_label.visible, "the failure is shown right above show more")
	assert_true(view._more_error_label.text.contains("network_error"))
	assert_eq(view._status_label.text, "", "the list itself is still there, so no list-level message")
	var button := _load_more_button(view)
	assert_true(button.visible, "show more stays so it can be retried")
	assert_false(button.disabled)
	assert_eq(button.text, TranslationServer.translate("さらに表示"))

	api.configure_list_pages({
		"": _page(_bosses("b", 0, 20), "c1"),
		"c1": _page(_bosses("b", 20, 5)),
	})
	await view.load_more()
	assert_eq(_cursors(api), ["", "c1", "c1"], "the retry asks for the same next page")
	assert_eq(_row_ids(view), _ids("b", 0, 25))
	assert_false(view._more_error_label.visible, "the failure line goes away once it works")
	assert_false(button.visible)

func test_show_more_cannot_be_pressed_twice_while_loading() -> void:
	RBMLoadingState.reset_for_testing()
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	api.list_delay_frames = 3

	var button := _load_more_button(view)
	button.pressed.emit()
	assert_true(button.disabled, "disabled while the next page is loading")
	assert_eq(button.text, TranslationServer.translate("読み込み中..."))
	assert_true(RBMLoadingState.active_operation_ids().has(RBMOnlineBossListView.LOADING_OP_MORE), "the shared loading state knows")
	button.pressed.emit()
	view.load_more()
	assert_eq(_cursors(api), ["", "c1"], "a second press while loading sends nothing")

	await _wait_until_idle(view)
	assert_eq(_row_ids(view), _ids("b", 0, 40), "the page was added once")
	assert_false(button.disabled)
	assert_false(RBMLoadingState.is_loading())
	RBMLoadingState.reset_for_testing()

func test_leaving_online_while_show_more_is_loading_drops_its_result() -> void:
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	api.list_delay_frames = 3
	view.load_more()
	view.refresh_with("", RBMOnlineBossListView.CATEGORY_NEW, "新着")
	assert_eq(api.list_calls.size(), 2, "the new category waits for the request in flight instead of overlapping it")

	for i in range(30):
		if api.list_calls.size() >= 3 and not view._list_busy:
			break
		await get_tree().process_frame
	assert_eq(_cursors(api), ["", "c1", ""])
	assert_eq(_row_ids(view), _ids("b", 0, 20), "the new category shows its own 20 rows, not the online page that was loading")
	assert_false(_load_more_button(view).visible)

func test_switching_mode_while_the_first_page_is_loading_never_mixes_modes() -> void:
	var api := _fake_api()
	_three_pages(api, "s")
	api.list_delay_frames = 3
	var view := _view_with(api)
	view.refresh_with(RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	assert_eq(api.list_calls.size(), 1, "HARDCORE waits for the SIMPLE request in flight")
	# SIMPLEの応答が返った直後にHARDCOREの要求が出る。HARDCOREの応答は別のボスにする。
	for i in range(30):
		if api.list_calls.size() >= 2:
			break
		await get_tree().process_frame
	_three_pages(api, "h")
	await _wait_until_idle(view)

	assert_eq(api.list_calls.map(func(call): return call["mode"]), [RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMCreatorDraft.CREATOR_MODE_ADVANCED])
	assert_eq(_row_ids(view), _ids("h", 0, 20), "only HARDCORE rows; the late SIMPLE answer is dropped")
	await view.load_more()
	assert_eq(api.list_calls[2], {"limit": 20, "mode": RBMCreatorDraft.CREATOR_MODE_ADVANCED, "cursor": "c1"})

# 新着の行には公開日(端末の時刻帯の日付 YYYY/MM/DD)を添える。オンラインの行には添えない。

func test_published_date_text_uses_the_local_date() -> void:
	assert_eq(RBMOnlineBossListView._published_date_text("2026-10-01T15:00:00+00:00", 540), "2026/10/02", "UTC 15:00 is the next day in Japan")
	assert_eq(RBMOnlineBossListView._published_date_text("2026-10-01T15:00:00+00:00", 0), "2026/10/01")
	assert_eq(RBMOnlineBossListView._published_date_text("2026-10-01T12:34:56.789012+00:00", 540), "2026/10/01", "fractional seconds are fine")
	assert_eq(RBMOnlineBossListView._published_date_text("", 540), "")
	assert_eq(RBMOnlineBossListView._published_date_text("not a date", 540), "")

func test_new_rows_show_the_publish_date_and_online_rows_do_not() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": [{"id": "a", "boss_name": "ボスA", "author_name": "AAA", "published_at": "2026-10-01T03:00:00+00:00"}]})
	var view := _view_with(api)
	var date := RBMOnlineBossListView._published_date_text("2026-10-01T03:00:00+00:00", int(Time.get_time_zone_from_system().get("bias", 0)))
	assert_true(date.begins_with("2026/"), "sanity: %s" % date)

	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_NEW, "新着")
	assert_eq(_card_texts(view, "DateLabel"), [date])
	assert_eq(_card_texts(view, "NameLabel"), ["ボスA"])
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	assert_eq(_card_texts(view, "DateLabel"), ["<none>"], "only the new category shows the date")

## 2026-10 実画面で発見: 「さらに表示」で下まで読んでからモード/カテゴリを切り替えると、
## 新しい一覧が前のスクロール位置(途中)から表示された。取り直したら先頭から見せ、
## 「さらに表示」では読んでいた位置を動かさない。
func test_refreshing_scrolls_back_to_the_top_but_show_more_keeps_the_position() -> void:
	var api := _fake_api()
	_three_pages(api)
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var view := RBMOnlineBossListView.new()
	view.set_api_adapter_for_testing(api)
	host.add_child(view)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await view.load_more()
	await get_tree().process_frame
	var scroll: ScrollContainer = view.find_child("OnlineListScroll", true, false)
	scroll.scroll_vertical = 600
	await get_tree().process_frame
	assert_eq(scroll.scroll_vertical, 600, "sanity: 40 rows are taller than the list area")

	await view.load_more()
	await get_tree().process_frame
	assert_eq(scroll.scroll_vertical, 600, "show more appends below without moving the rows being read")

	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await get_tree().process_frame
	assert_eq(scroll.scroll_vertical, 0, "a mode switch starts the new list from the top")

# ---------------------------------------------------------------------------
# 2026-10 — 2カラムの画面(左: ボスカード / 右: 選択中ボスの詳細)。自動では選ばず、右は
# 「左の一覧からボスを選択してください」。カードを選ぶと詳細を取得して右に出し、右の
# 「挑戦する」でchallenge_requestedを出す。モード切替(すべて/SIMPLE/HARDCORE)は一覧を
# 先頭から取り直す。一覧が無い時(取得中・空・失敗)は右に案内を出さない。
# ---------------------------------------------------------------------------

## 公開できる(クリアチェック済みの)ボスのpayload。
func _published_payload(boss_name: String, appearance_id: String = "appearance_dragon", background: String = "day") -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.appearance_id = appearance_id
	draft.battle_background = background
	draft.hp = 4800
	draft.atk = 100
	draft.spd = 50
	draft.weak_attributes = ["ICE"]
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.add_party_character("healer")
	draft.record_clear_check_success()
	return RBMOnlineBossPayload.build_for_publish(draft)["payload"]

## 2件の一覧と、選んだ時の詳細(get-boss)を返すサーバー。
func _api_with_two_bosses(payload: Dictionary = {}) -> RBMFakeBossApiAdapter:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": [
		{"id": "a", "boss_name": "ボスA", "author_name": "AAA", "published_at": "2026-09-30T03:00:00+00:00", "creator_mode": "advanced", "appearance_id": "appearance_dragon", "unique_challengers": 10, "unique_clearers": 1},
		{"id": "b", "boss_name": "ボスB", "author_name": "BBB", "published_at": "2026-09-29T03:00:00+00:00", "creator_mode": "simple", "appearance_id": "appearance_golem", "unique_challengers": 4, "unique_clearers": 2},
	]})
	# get-bossのboss_nameを空にして、表示が一覧の行(選んだカード)の名前になることを見分けられるようにする。
	api.configure_get_response({"ok": true, "boss": {"id": "x", "boss_name": "", "author_name": "", "revision": 1, "payload": payload if not payload.is_empty() else _published_payload("詳細ボス")}})
	return api

func _detail_node(view: RBMOnlineBossListView, node_name: String) -> Node:
	return view._detail.find_child(node_name, true, false)

func _detail_text(view: RBMOnlineBossListView, node_name: String) -> String:
	var label := _detail_node(view, node_name) as Label
	return label.text if label != null else "<none>"

func _card(view: RBMOnlineBossListView, boss_id: String) -> RBMOnlineBossCard:
	return view._rows_container.get_node_or_null("OnlineBossRow_%s" % boss_id) as RBMOnlineBossCard

func test_no_boss_is_selected_automatically_and_the_right_side_asks_to_pick_one() -> void:
	var api := _api_with_two_bosses()
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	assert_eq(view.selected_boss_id(), "")
	assert_eq(api.get_calls.size(), 0, "nothing is fetched until a card is picked")
	assert_eq(_detail_text(view, "DetailHint"), TranslationServer.translate("左の一覧からボスを選択してください"))
	assert_null(_detail_node(view, "DetailChallengeButton"), "no challenge button before a boss is picked")
	assert_false(_card(view, "a").is_selected())
	assert_eq(view._count_label.text, TranslationServer.translate("%d件表示中") % 2)

func test_picking_a_card_shows_its_details_and_selects_only_that_card() -> void:
	var api := _api_with_two_bosses()
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	var received := []
	view.boss_selected.connect(func(boss_id, draft, boss_name, author_name): received.append([boss_id, draft, boss_name, author_name]))

	_card(view, "a").pressed.emit()
	await get_tree().process_frame

	assert_eq(api.get_calls, ["a"])
	assert_eq(view.selected_boss_id(), "a")
	assert_true(_card(view, "a").is_selected())
	assert_false(_card(view, "b").is_selected())
	assert_eq(_detail_text(view, "DetailBossName"), "ボスA", "the name of the picked card")
	assert_eq(_detail_text(view, "DetailAuthor"), TranslationServer.translate("by %s") % "AAA")
	assert_eq(_detail_text(view, "DetailPublishedValue"), RBMOnlineBossListView._published_date_text("2026-09-30T03:00:00+00:00", int(Time.get_time_zone_from_system().get("bias", 0))))
	assert_eq(_detail_text(view, "DetailWinConditionValue"), TranslationServer.translate("ボスのHPを0にする"))
	assert_eq(_detail_text(view, "DetailBossHpValue"), "4800")
	assert_eq(_detail_text(view, "DetailWeakValue"), TranslationServer.translate("氷"))
	assert_eq(_detail_text(view, "DetailClearCheck"), TranslationServer.translate("✓ クリアチェック済み"))
	assert_not_null(_detail_node(view, "DetailPartyChip_hero"))
	assert_not_null(_detail_node(view, "DetailPartyChip_healer"))
	assert_null(_detail_node(view, "DetailHint"))
	var go := _detail_node(view, "DetailChallengeButton") as Button
	assert_not_null(go)
	assert_false(go.disabled)
	assert_eq(received.size(), 1)
	assert_eq(received[0][0], "a")
	assert_true(received[0][1] is RBMCreatorDraft)

func test_the_stage_uses_the_same_battle_background_as_the_challenge() -> void:
	var api := _api_with_two_bosses(_published_payload("昼の竜", "appearance_dragon", "day"))
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	_card(view, "a").pressed.emit()
	await get_tree().process_frame

	var background := _detail_node(view, "DetailStageBackground") as TextureRect
	assert_eq(background.texture, RBMBattleBackgrounds.texture_for("dragon", "day"), "boss background if there is one, else the author's day/night courtyard")
	assert_not_null((_detail_node(view, "DetailStageBoss") as TextureRect).texture, "the boss stands on the stage")

func test_hidden_challenge_info_stays_hidden_in_the_details() -> void:
	var payload := _published_payload("秘密のボス")
	var draft_fields: Dictionary = payload["draft_fields"]
	var visibility: Dictionary = draft_fields["challenge_info_visibility"]
	for key in ["hp", "weak_attributes", "win_condition"]:
		visibility[key] = false
	var api := _api_with_two_bosses(payload)
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	_card(view, "a").pressed.emit()
	await get_tree().process_frame

	assert_eq(_detail_text(view, "DetailBossHpValue"), TranslationServer.translate("？？？"))
	assert_eq(_detail_text(view, "DetailWeakValue"), TranslationServer.translate("？？？"))
	assert_eq(_detail_text(view, "DetailWinConditionValue"), TranslationServer.translate("非公開"))

func test_the_author_message_shows_the_draft_notes_or_none() -> void:
	var view := _view_with(_fake_api())
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "メッセージ確認"
	view._detail.show_boss({"boss_name": "メッセージ確認"}, draft)
	assert_eq(_detail_text(view, "DetailMessage"), TranslationServer.translate("（なし）"))
	draft.author_notes = "居合の構えに注意。"
	view._detail.show_boss({"boss_name": "メッセージ確認"}, draft)
	assert_eq(_detail_text(view, "DetailMessage"), "居合の構えに注意。")

func test_while_the_details_load_the_card_info_shows_and_the_challenge_button_waits() -> void:
	RBMLoadingState.reset_for_testing()
	var api := _api_with_two_bosses()
	api.get_delay_frames = 3
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	_card(view, "b").pressed.emit()
	assert_not_null(_detail_node(view, "DetailLoading"))
	assert_eq(_detail_text(view, "DetailBossName"), "ボスB", "the name from the list shows right away")
	var waiting := _detail_node(view, "DetailChallengeButton") as Button
	assert_true(waiting.disabled, "cannot challenge before the details arrive")
	assert_true(RBMLoadingState.active_operation_ids().has(RBMOnlineBossListView.LOADING_OP_DETAIL))

	await _wait_until_idle(view)
	assert_null(_detail_node(view, "DetailLoading"))
	assert_false((_detail_node(view, "DetailChallengeButton") as Button).disabled)
	assert_false(RBMLoadingState.is_loading())
	RBMLoadingState.reset_for_testing()

func test_picking_another_card_while_loading_shows_only_the_last_pick() -> void:
	var api := _api_with_two_bosses()
	api.get_delay_frames = 3
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	var received := []
	view.boss_selected.connect(func(boss_id, _draft, _boss_name, _author_name): received.append(boss_id))

	_card(view, "a").pressed.emit()
	_card(view, "b").pressed.emit()
	for i in range(30):
		if api.get_calls.size() >= 2 and not view._list_busy:
			break
		await get_tree().process_frame

	assert_eq(api.get_calls, ["a", "b"], "one request at a time; the second waits for the first")
	assert_eq(view.selected_boss_id(), "b")
	assert_eq(_detail_text(view, "DetailBossName"), "ボスB")
	assert_eq(received, ["b"], "the late answer for A is dropped")
	assert_false(_card(view, "a").is_selected())

func test_a_failed_detail_fetch_shows_the_error_and_picking_again_retries() -> void:
	var api := _api_with_two_bosses()
	var good: Dictionary = api._get_response.duplicate(true)
	api.configure_get_response({"ok": false, "error_kind": "not_found", "message": "gone"})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	_card(view, "a").pressed.emit()
	await get_tree().process_frame
	assert_true(_detail_text(view, "DetailError").contains("not_found"))
	assert_null(_detail_node(view, "DetailChallengeButton"), "nothing to challenge")

	api.configure_get_response(good)
	_card(view, "a").pressed.emit()
	await get_tree().process_frame
	assert_eq(api.get_calls, ["a", "a"])
	assert_eq(_detail_text(view, "DetailBossName"), "ボスA")

func test_the_challenge_button_asks_to_start_the_picked_boss() -> void:
	var api := _api_with_two_bosses()
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	var requested := []
	view.challenge_requested.connect(func(boss_id, draft): requested.append([boss_id, draft]))
	_card(view, "a").pressed.emit()
	await get_tree().process_frame

	(_detail_node(view, "DetailChallengeButton") as Button).pressed.emit()
	assert_eq(requested.size(), 1)
	assert_eq(requested[0][0], "a")
	assert_true(requested[0][1] is RBMCreatorDraft)
	assert_eq((requested[0][1] as RBMCreatorDraft).boss_name, "詳細ボス", "the downloaded draft, ready for battle")

func test_refreshing_clears_the_selection() -> void:
	var api := _api_with_two_bosses()
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	_card(view, "a").pressed.emit()
	await get_tree().process_frame
	assert_eq(view.selected_boss_id(), "a")

	await view.refresh()
	assert_eq(view.selected_boss_id(), "")
	assert_not_null(_detail_node(view, "DetailHint"))
	assert_false(_card(view, "a").is_selected())

func test_the_mode_switch_refetches_from_the_top_in_the_same_category() -> void:
	var api := _fake_api()
	_three_pages(api)
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await view.load_more()
	var hardcore: Button = view.find_child("OnlineListModeHardcore", true, false)
	var all: Button = view.find_child("OnlineListModeAll", true, false)
	assert_eq((all.get_theme_stylebox("normal") as StyleBoxFlat).border_color, RBMChallengeListStyle.ACCENT, "すべて is active at first")

	hardcore.pressed.emit()
	await _wait_until_idle(view)
	assert_eq(view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_ONLINE)
	assert_eq(api.list_calls[api.list_calls.size() - 1], {"limit": 20, "mode": RBMCreatorDraft.CREATOR_MODE_ADVANCED, "cursor": ""})
	assert_eq(_row_ids(view).size(), 20, "from the top again")
	assert_eq((hardcore.get_theme_stylebox("normal") as StyleBoxFlat).border_color, RBMChallengeListStyle.ACCENT)
	assert_ne((all.get_theme_stylebox("normal") as StyleBoxFlat).border_color, RBMChallengeListStyle.ACCENT)

func test_while_the_list_loads_placeholder_cards_show_and_the_right_side_has_no_hint() -> void:
	var api := _fake_api()
	_three_pages(api)
	api.list_delay_frames = 3
	var view := _view_with(api)
	view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	assert_true(view._skeleton_container.visible)
	assert_eq(view._count_label.text, TranslationServer.translate("読み込み中..."))
	assert_null(_detail_node(view, "DetailHint"), "nothing to pick yet")
	await _wait_until_idle(view)
	assert_false(view._skeleton_container.visible)
	assert_not_null(_detail_node(view, "DetailHint"))

func test_an_empty_list_shows_the_message_without_retry_or_hint() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	assert_eq(view._status_label.text, TranslationServer.translate("公開されているボスはまだありません。"))
	assert_false(view._retry_button.visible)
	assert_false(view._status_title_label.visible)
	assert_null(_detail_node(view, "DetailHint"))

func test_a_failed_list_offers_try_again_which_refetches() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": false, "error_kind": "network_error", "message": "timeout"})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")

	assert_eq(view._status_title_label.text, TranslationServer.translate("一覧を取得できませんでした"))
	assert_true(view._status_label.text.contains("network_error"))
	assert_true(view._retry_button.visible)
	assert_null(_detail_node(view, "DetailHint"))

	api.configure_list_response({"ok": true, "bosses": _bosses("b", 0, 3)})
	view._retry_button.pressed.emit()
	await _wait_until_idle(view)
	assert_eq(api.list_calls.size(), 2)
	assert_eq(_row_ids(view), _ids("b", 0, 3))
	assert_false(view._retry_button.visible)
	assert_eq(view._status_label.text, "")

func test_show_more_waits_for_a_detail_fetch_instead_of_being_dropped() -> void:
	var api := _fake_api()
	_three_pages(api)
	api.configure_get_response({"ok": true, "boss": {"id": "b-00", "boss_name": "", "author_name": "", "revision": 1, "payload": _published_payload("詳細")}})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	api.get_delay_frames = 3

	_card(view, "b-00").pressed.emit()
	view.load_more()
	assert_true(_load_more_button(view).disabled, "show more already shows that it is loading")
	assert_eq(_cursors(api), [""], "but it waits for the detail request in flight")
	for i in range(30):
		if api.list_calls.size() >= 2 and not view._list_busy:
			break
		await get_tree().process_frame
	assert_eq(_cursors(api), ["", "c1"])
	assert_eq(_row_ids(view), _ids("b", 0, 40))
	assert_eq(view.selected_boss_id(), "b-00", "the selection survives show more")
	assert_true(_card(view, "b-00").is_selected())

func test_cards_show_the_boss_thumbnail_from_the_appearance() -> void:
	var api := _api_with_two_bosses()
	api.configure_list_response({"ok": true, "bosses": [
		{"id": "a", "boss_name": "竜", "author_name": "A", "appearance_id": "appearance_dragon"},
		{"id": "n", "boss_name": "外見なし", "author_name": "A"},
	]})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	assert_not_null((_card(view, "a").find_child("ThumbnailSprite", true, false) as TextureRect).texture)
	assert_null((_card(view, "n").find_child("ThumbnailSprite", true, false) as TextureRect).texture, "an unknown appearance shows the empty frame")

func test_card_hover_selection_and_focus_look_different() -> void:
	var api := _api_with_two_bosses()
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	var card := _card(view, "b")
	var normal := card.get_theme_stylebox("normal") as StyleBoxFlat
	var hover := card.get_theme_stylebox("hover") as StyleBoxFlat
	var focus := card.get_theme_stylebox("focus") as StyleBoxFlat
	assert_ne(hover.bg_color, normal.bg_color, "hover is a little brighter")
	assert_eq(hover.border_color, Color(RBMChallengeListStyle.SILVER, 0.55), "hover has a silver edge")
	assert_false(focus.draw_center)
	assert_gt(focus.expand_margin_left, 0.0, "the keyboard/pad focus ring sits outside the card")
	card.set_selected(true)
	var selected := card.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(selected.border_color, Color(RBMChallengeListStyle.ACCENT, 0.75), "selected has the blue edge")
	assert_gt(selected.shadow_size, 0, "and a soft glow")
	assert_true((card.find_child("SelectedBar", true, false) as CanvasItem).visible)

func test_the_title_is_the_category_name() -> void:
	assert_eq(RBMOnlineBossListView.category_title(RBMOnlineBossListView.CATEGORY_ONLINE), TranslationServer.translate("オンライン"))
	assert_eq(RBMOnlineBossListView.category_title(RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY), TranslationServer.translate("高難度"))

# ---------------------------------------------------------------------------
# 2026-10(ユーザー確定仕様) — 作者メッセージ(author_notes)はオンライン公開データに含め、右の詳細に出す。
# 未設定なら「（なし）」。一覧のカードには出さない。
# ---------------------------------------------------------------------------

func _payload_with_message(message: String) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "メッセージ付きボス"
	draft.appearance_id = "appearance_musha"
	draft.hp = 4800
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.set_author_notes(message)
	draft.record_clear_check_success()
	return RBMOnlineBossPayload.build_for_publish(draft)["payload"]

func test_an_online_boss_with_an_author_message_shows_it_in_the_details() -> void:
	var api := _api_with_two_bosses(_payload_with_message("居合の構えに入ったら守りを固めること。"))
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	_card(view, "a").pressed.emit()
	await get_tree().process_frame

	assert_eq(_detail_text(view, "DetailMessage"), "居合の構えに入ったら守りを固めること。")
	assert_false(_all_card_texts(view).contains("居合の構え"), "the cards never show the message")

func test_an_online_boss_without_an_author_message_shows_none() -> void:
	var api := _api_with_two_bosses(_payload_with_message(""))
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	_card(view, "a").pressed.emit()
	await get_tree().process_frame

	assert_eq(_detail_text(view, "DetailMessage"), TranslationServer.translate("（なし）"))
