extends GutTest

## Phase 4C-7 → 公開UI整理（2026-09-10）— Creator STEP5の公開ボタンの
## fake駆動UIテスト。実Steam/実Supabaseへは一切出ない。
##
## ローカル公開（旧PublishButton/UnpublishButton）はユーザー向けUIから
## 廃止され、単一のPublishOnlineButtonが未公開/公開済みで表示・処理を
## 切り替える形に変わった——このファイルはその新しい挙動を検証する。
##
## オンライン公開状態の永続化（2026-09-10、ユーザー確定仕様）: publish()/
## unpublish()成功のたびに実際にディスクへ保存する（_persist_online_state()
## 参照）ため、実プレイヤーのuser://保存ライブラリを一切汚さないよう、
## 専用のテスト用ディレクトリへ差し替えて実行する（test_rbm_challenge_flow.gd
## 等と同じ既存規約）。

const TEST_DIR := "user://bossmaker_test_online_publish_ui/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path + "/" + entry
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

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

## refresh()（go_to_step()経由で呼ばれる）は_ensure_boss_publisher()を通じて
## 可用性を判定するため、実Steam/実HTTPへ一切触れないよう、fakeは必ず
## go_to_step()より前にインストールする——そうしないと最初のrefresh()が
## 実RBMBossPublisherを作ってしまう。
func _install_fake_publisher(summary: RBMCreatorStep7Summary, auth: RBMSteamAuth, api: RBMFakeBossApiAdapter) -> RBMBossPublisher:
	add_child_autofree(api)
	var publisher := RBMBossPublisher.new()
	add_child_autofree(publisher)
	publisher.set_steam_auth_for_testing(auth)
	publisher.set_api_adapter_for_testing(api)
	summary.set_boss_publisher_for_testing(publisher)
	return publisher

# ---------------------------------------------------------------------------
# ローカル公開UIの廃止
# ---------------------------------------------------------------------------

func test_local_publish_buttons_are_removed_from_the_ui() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)

	assert_null(summary.find_child("PublishButton", true, false), "the local Publish button must no longer exist in the UI")
	assert_null(summary.find_child("UnpublishButton", true, false), "the local Unpublish button must no longer exist in the UI")
	assert_null(summary.find_child("PublishStatusLabel", true, false), "the local publish status label must no longer exist in the UI")
	# The underlying local-publish capability itself must still work even
	# though no button calls it anymore (only the UI affordance is removed).
	assert_true(creator.press_publish().get("ok", false), "RBMCreatorMain.press_publish() itself must still work")
	await get_tree().process_frame # drain queued UI-rebuild frees (remove_child+queue_free, see rbm_battle_ui_kit.gd) before GUT's orphan check; real gameplay always gets this frame naturally

# ---------------------------------------------------------------------------
# disabled/表示切替
# ---------------------------------------------------------------------------

func test_online_publish_button_is_disabled_before_clear_check() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	creator.go_to_step(5)

	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	assert_not_null(button)
	assert_true(button.disabled, "クリアチェック未達成の間はオンライン公開ボタンも無効")
	assert_eq(button.text, "オンライン公開")

func test_online_publish_button_is_enabled_after_clear_check_when_steam_is_available() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)

	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	assert_false(button.disabled)
	var unavailable_label: Label = summary.find_child("OnlineUnavailableLabel", true, false)
	assert_false(unavailable_label.visible, "Steam利用可能な間は利用不可メッセージを出さない")

## ユーザー指示: Steamが利用できない場合はボタンを押させて失敗させるのでは
## なく、無効状態にすること。
func test_online_publish_button_stays_disabled_when_steam_is_unavailable_even_after_clear_check() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(false, false)
	var api := RBMFakeBossApiAdapter.new()
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)

	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	assert_true(button.disabled, "Steamが利用できない間はClear Check達成済みでも無効のまま")
	var unavailable_label: Label = summary.find_child("OnlineUnavailableLabel", true, false)
	assert_true(unavailable_label.visible, "利用できない理由の短い説明を表示する")
	assert_eq(api.publish_calls.size(), 0, "無効なボタンなので実際に押さない限りEdge Functionへは送らない")

# ---------------------------------------------------------------------------
# 公開/失敗
# ---------------------------------------------------------------------------

func test_pressing_online_publish_without_steam_shows_a_safe_status_message() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(false, false)
	var api := RBMFakeBossApiAdapter.new()
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)

	var button: Button = summary.find_child("PublishOnlineButton", true, false)
	# A direct signal emit bypasses `disabled` (which only blocks real
	# mouse/keyboard presses) -- the handler itself must still fail safely.
	button.pressed.emit()
	await wait_process_frames(2)

	var status_label: Label = summary.find_child("OnlinePublishStatusLabel", true, false)
	assert_true(status_label.text.length() > 0)
	assert_eq(api.publish_calls.size(), 0, "Steamが使えない間はEdge Functionへ一切送信しない")

func test_pressing_online_publish_succeeds_end_to_end_with_fakes() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	api.configure_publish_response({"ok": true, "boss_id": "abc", "revision": 1})
	var summary := _summary_of(creator)
	var publisher := _install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)

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
	assert_eq(button.text, "公開を取り下げる", "success must flip the same button over to the unpublish label")

# ---------------------------------------------------------------------------
# 未公開 → オンライン公開 → 公開済み → 公開を取り下げる → 未公開 → 再公開
# ---------------------------------------------------------------------------

func test_full_publish_unpublish_republish_cycle() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	api.configure_publish_response({"ok": true, "boss_id": "cycle-boss", "revision": 1})
	api.configure_unpublish_response({"ok": true})
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)
	var fake_steam := auth.adapter_for_testing() as RBMFakeSteamAdapter
	var button: Button = summary.find_child("PublishOnlineButton", true, false)

	# 1) 未公開
	assert_eq(button.text, "オンライン公開")
	assert_false(button.disabled)

	# 2) → オンライン公開 → 公開済み
	button.pressed.emit()
	await wait_process_frames(1)
	fake_steam.fire_ticket_response(fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)
	assert_eq(api.publish_calls.size(), 1)
	assert_eq(button.text, "公開を取り下げる")

	# 3) → 公開を取り下げる → 未公開
	button.pressed.emit()
	await wait_process_frames(1)
	fake_steam.fire_ticket_response(fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)
	assert_eq(api.unpublish_calls.size(), 1)
	assert_eq(api.unpublish_calls[0]["boss_id"], "cycle-boss", "unpublish must target the same boss_id that publish returned")
	assert_eq(button.text, "オンライン公開")

	# 4) → 再公開（同じboss_idを使って復活させる、新規重複投稿にしない）
	button.pressed.emit()
	await wait_process_frames(1)
	fake_steam.fire_ticket_response(fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)
	assert_eq(api.publish_calls.size(), 2)
	assert_eq(api.publish_calls[1]["boss_id"], "cycle-boss", "re-publish must reuse the existing boss_id rather than creating a duplicate")
	assert_eq(button.text, "公開を取り下げる")
	await get_tree().process_frame # drain queued UI-rebuild frees before GUT's orphan check

# ---------------------------------------------------------------------------
# 永続化 — Creatorを閉じて再度開いてもオンライン公開状態が復元されること
# （ユーザー確定仕様、2026-09-10）
# ---------------------------------------------------------------------------

## publish()成功→保存→Creatorを閉じる(別のRBMCreatorMainインスタンスとして
## 再現)→同じstage_idで開き直す、という一連の流れで、online_boss_id/
## online_publishedがディスクから正しく復元され、ボタンが「公開を取り下げる」
## から始まることを検証する。
func test_online_published_state_survives_closing_and_reopening_the_creator() -> void:
	var creator := _new_creator()
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	api.configure_publish_response({"ok": true, "boss_id": "persisted-boss", "revision": 1})
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)
	var fake_steam := auth.adapter_for_testing() as RBMFakeSteamAdapter
	var button: Button = summary.find_child("PublishOnlineButton", true, false)

	button.pressed.emit()
	await wait_process_frames(1)
	fake_steam.fire_ticket_response(fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)
	assert_true(creator.draft.is_online_published(), "sanity: publish must have succeeded")
	var stage_id := creator.current_stage_id
	assert_false(stage_id.is_empty(), "publishing an unsaved draft must implicitly save it, giving it a stage_id")

	# "Creatorを閉じる": 元のcreatorはこのテストの終わりまで生きたままだが
	# （add_child_autofreeが解放するのはテスト終了時）、以後は一切操作しない
	# ——実際のCreator画面破棄/再構築と同じ「保存されたJSONだけを頼りに
	# 別インスタンスから読み直す」状況を再現する。

	# "再度開く"
	var reopened := _new_creator()
	var reopened_summary := _summary_of(reopened)
	var reopened_auth := _ready_steam_auth(true, true)
	var reopened_api := RBMFakeBossApiAdapter.new()
	# サーバー同期（2026-09-11）: start_loaded()は内部で即座にrefresh()を
	# 呼ぶため、fakeはstart_loaded()より前にインストールする必要がある
	# （そうしないと最初のrefresh()が実RBMBossPublisherで同期を発火させ、
	# ガードが立った状態でfakeを差し込むことになる）。ここではサーバー側も
	# 公開中と返すよう設定し、ローカルキャッシュと一致させる。
	reopened_api.configure_get_response({"ok": true, "boss": {"id": "persisted-boss"}})
	_install_fake_publisher(reopened_summary, reopened_auth, reopened_api)
	var load_result := reopened.start_loaded(stage_id)
	assert_true(bool(load_result.get("ok", false)), "sanity: reopening the just-published stage must succeed")
	await wait_process_frames(2)
	assert_true(reopened.draft.is_online_published(), "online_published must survive a close+reopen round trip")
	assert_eq(reopened.draft.online_boss_id(), "persisted-boss", "online_boss_id must survive a close+reopen round trip")

	var reopened_button: Button = reopened_summary.find_child("PublishOnlineButton", true, false)
	assert_eq(reopened_button.text, "公開を取り下げる", "reopening a published stage must show the unpublish label, not オンライン公開")
	await get_tree().process_frame # drain queued UI-rebuild frees before GUT's orphan check

# ---------------------------------------------------------------------------
# サーバー同期（ユーザー確定仕様、2026-09-11）: online_publishedはローカル
# キャッシュに過ぎず、最終的な正はSupabase側。保存済みstageをCreatorで開く
# （＝この画面を初めて表示する）たびに、online_boss_idがあればget-boss経由
# でサーバー側の実際の状態を確認し、ローカルキャッシュ/UIを同期する。
# ---------------------------------------------------------------------------

## ローカル/サーバーの4通りの組み合わせを直接検証するヘルパー。stage_idは
## 毎回新規に発行するため、ローカルキャッシュのtrue/falseを自由に設定
## できる（publish()を経由せず、直接online_boss_id/online_publishedへ
## 値を書き込んで保存する——サーバー同期そのものだけを独立して検証する
## ためのfixtureであり、publish()/unpublish()自体の経路は既に別のテスト
## （test_full_publish_unpublish_republish_cycle等）で検証済み）。
func _save_stage_with_local_online_cache(boss_id: String, local_published: bool) -> String:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "サーバー同期テストボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.set_online_boss_id(boss_id)
	draft.set_online_published(local_published)
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

## RBMCreatorMain.start_loaded()は内部で即座に_refresh()を呼ぶ
## (current_step=STEP_COUNTへ設定した直後、rbm_creator_main.gd参照)ため、
## fakeはstart_loaded()より前にインストールしておく必要がある——そうしない
## と最初のrefresh()が（まだ実RBMBossPublisherしか無い状態で）サーバー
## 同期を先に一度発火させてしまい、_online_state_syncedガードが立った
## 状態でfakeを差し込むことになり、以後のgo_to_step(5)では二度と同期が
## 走らなくなる（実際にこの順序ミスで最初の実装がテスト失敗した）。
func _open_and_sync(stage_id: String, get_response: Dictionary) -> Dictionary:
	var creator := _new_creator()
	var summary := _summary_of(creator)
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	api.configure_get_response(get_response)
	_install_fake_publisher(summary, auth, api)
	var load_result := creator.start_loaded(stage_id)
	assert_true(bool(load_result.get("ok", false)), "sanity: stage must load")
	await wait_process_frames(2)
	return {"creator": creator, "summary": summary}

## 1. ローカルtrue / サーバーtrue → true
func test_sync_local_true_server_true_stays_true() -> void:
	var stage_id := _save_stage_with_local_online_cache("boss-1", true)
	var ctx := await _open_and_sync(stage_id, {"ok": true, "boss": {"id": "boss-1"}})
	var creator: RBMCreatorMain = ctx["creator"]
	var summary: RBMCreatorStep7Summary = ctx["summary"]
	assert_true(creator.draft.is_online_published())
	assert_eq((summary.find_child("PublishOnlineButton", true, false) as Button).text, "公開を取り下げる")
	await get_tree().process_frame

## 2. ローカルfalse / サーバーtrue → true（サーバー側が正、キャッシュが更新される）
func test_sync_local_false_server_true_becomes_true() -> void:
	var stage_id := _save_stage_with_local_online_cache("boss-2", false)
	var ctx := await _open_and_sync(stage_id, {"ok": true, "boss": {"id": "boss-2"}})
	var creator: RBMCreatorMain = ctx["creator"]
	var summary: RBMCreatorStep7Summary = ctx["summary"]
	assert_true(creator.draft.is_online_published(), "server says published -- local cache must follow")
	assert_eq((summary.find_child("PublishOnlineButton", true, false) as Button).text, "公開を取り下げる")

	# サーバーから復帰したtrueが実際にディスクへも保存されていること
	# （必要に応じてローカルへ同期結果を保存する、というユーザー確定仕様）。
	var reloaded := RBMCreatorDraft.new()
	var load_result := RBMLocalStageRepository.load_stage(creator.current_stage_id)
	reloaded.restore_from_saved_dict(load_result.get("draft_data", {}))
	assert_true(reloaded.is_online_published(), "the server-confirmed true must be persisted to disk, not just held in memory")
	await get_tree().process_frame

## 3. ローカルtrue / サーバーfalse → false（サーバー側が正、キャッシュが更新される）
func test_sync_local_true_server_false_becomes_false() -> void:
	var stage_id := _save_stage_with_local_online_cache("boss-3", true)
	var ctx := await _open_and_sync(stage_id, {"ok": false, "error_kind": "http_4xx", "http_status": 404, "message": "not found"})
	var creator: RBMCreatorMain = ctx["creator"]
	var summary: RBMCreatorStep7Summary = ctx["summary"]
	assert_false(creator.draft.is_online_published(), "server says not published (404) -- local cache must follow")
	assert_eq((summary.find_child("PublishOnlineButton", true, false) as Button).text, "オンライン公開")

	var reloaded := RBMCreatorDraft.new()
	var load_result := RBMLocalStageRepository.load_stage(creator.current_stage_id)
	reloaded.restore_from_saved_dict(load_result.get("draft_data", {}))
	assert_false(reloaded.is_online_published(), "the server-confirmed false must be persisted to disk")
	assert_eq(reloaded.online_boss_id(), "boss-3", "unpublishing (even via sync) must keep online_boss_id so it can be re-published")
	await get_tree().process_frame

## 4. ローカルfalse / サーバーfalse → false
func test_sync_local_false_server_false_stays_false() -> void:
	var stage_id := _save_stage_with_local_online_cache("boss-4", false)
	var ctx := await _open_and_sync(stage_id, {"ok": false, "error_kind": "http_4xx", "http_status": 404, "message": "not found"})
	var creator: RBMCreatorMain = ctx["creator"]
	var summary: RBMCreatorStep7Summary = ctx["summary"]
	assert_false(creator.draft.is_online_published())
	assert_eq((summary.find_child("PublishOnlineButton", true, false) as Button).text, "オンライン公開")
	await get_tree().process_frame

## 5. 通信失敗 → ローカル値を変更しない（最重要のユーザー確定仕様）。
## true側・false側の両方で、確認できなかった場合に絶対に書き換わらない
## ことを確認する——「非公開と確認できた」と「サーバーへ接続できなかった」
## を混同しないことの直接証明。
func test_sync_network_failure_never_changes_the_local_cache_when_it_was_true() -> void:
	var stage_id := _save_stage_with_local_online_cache("boss-5", true)
	var ctx := await _open_and_sync(stage_id, {"ok": false, "error_kind": "network_error", "http_status": -1, "message": "DNS failure"})
	var creator: RBMCreatorMain = ctx["creator"]
	var summary: RBMCreatorStep7Summary = ctx["summary"]
	assert_true(creator.draft.is_online_published(), "a network failure must never flip a true cache to false")
	assert_eq(creator.draft.online_boss_id(), "boss-5", "a network failure must never touch online_boss_id")
	assert_eq((summary.find_child("PublishOnlineButton", true, false) as Button).text, "公開を取り下げる")
	var status_label: Label = summary.find_child("OnlinePublishStatusLabel", true, false)
	assert_true(status_label.text.length() > 0, "must show some indication that the check could not be completed")
	await get_tree().process_frame

func test_sync_network_failure_never_changes_the_local_cache_when_it_was_false() -> void:
	var stage_id := _save_stage_with_local_online_cache("boss-6", false)
	var ctx := await _open_and_sync(stage_id, {"ok": false, "error_kind": "http_5xx", "http_status": 503, "message": "server error"})
	var creator: RBMCreatorMain = ctx["creator"]
	var summary: RBMCreatorStep7Summary = ctx["summary"]
	assert_false(creator.draft.is_online_published(), "a failed check must never flip a false cache to true")
	assert_eq(creator.draft.online_boss_id(), "boss-6", "a failed check must never touch online_boss_id")
	assert_eq((summary.find_child("PublishOnlineButton", true, false) as Button).text, "オンライン公開")
	await get_tree().process_frame

## online_boss_idが空の旧/未公開stageでは、サーバーへ一切問い合わせない
## （ユーザー確定仕様「online_boss_idが空：従来通り未公開として扱う」）。
func test_sync_is_skipped_entirely_when_online_boss_id_is_empty() -> void:
	var stage_id := _save_stage_with_local_online_cache("", false)
	var creator := _new_creator()
	var summary := _summary_of(creator)
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	_install_fake_publisher(summary, auth, api)
	creator.start_loaded(stage_id)
	await wait_process_frames(2)
	assert_eq(api.get_calls.size(), 0, "no online_boss_id means nothing to check against the server")
	await get_tree().process_frame

## 6. Creatorを閉じて再度開いても同期される——2で保存したサーバー確定値
## (true)が、さらに別のCreatorセッションを開いた時にも正しく保持/再同期
## されることを、2回連続でreopenして確認する（test_online_published_
## state_survives_closing_and_reopening_the_creatorが「publishした直後の
## reopen」を検証するのに対し、これは「サーバー同期で更新された後の
## reopen」を検証する——別の切り口の回帰）。
func test_reopening_again_after_a_server_sync_keeps_the_synced_value() -> void:
	var stage_id := _save_stage_with_local_online_cache("boss-7", false)
	var first_ctx := await _open_and_sync(stage_id, {"ok": true, "boss": {"id": "boss-7"}})
	var first_creator: RBMCreatorMain = first_ctx["creator"]
	assert_true(first_creator.draft.is_online_published(), "sanity: first sync must have flipped false -> true")

	var second_ctx := await _open_and_sync(stage_id, {"ok": true, "boss": {"id": "boss-7"}})
	var second_creator: RBMCreatorMain = second_ctx["creator"]
	var second_summary: RBMCreatorStep7Summary = second_ctx["summary"]
	assert_true(second_creator.draft.is_online_published(), "the synced value from the first session must still be there on a second reopen")
	assert_eq((second_summary.find_child("PublishOnlineButton", true, false) as Button).text, "公開を取り下げる")
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# 最終確認: オンライン公開 → 公開を取り下げる → Creatorを閉じる →
# 再度stageを開く → get-bossの404で未公開へ同期 → online_boss_idは保持 →
# 再度オンライン公開 → 同じオンラインBossとして正常に再公開
# （ユーザー確定シナリオ、コミット直前の最終回帰）
# ---------------------------------------------------------------------------

func test_full_lifecycle_publish_unpublish_close_reopen_sync_and_republish_reuses_same_boss_id() -> void:
	# 0) 基準値: この一連の流れの前後でClear Check/battle_hashが一切動か
	# ないことを確認するための基準スナップショット。
	var creator := _new_creator()
	var auth := _ready_steam_auth(true, true)
	var api := RBMFakeBossApiAdapter.new()
	api.configure_publish_response({"ok": true, "boss_id": "lifecycle-boss", "revision": 1})
	api.configure_unpublish_response({"ok": true})
	var summary := _summary_of(creator)
	_install_fake_publisher(summary, auth, api)
	_make_cleared(creator)
	creator.go_to_step(5)
	var fake_steam := auth.adapter_for_testing() as RBMFakeSteamAdapter
	var button: Button = summary.find_child("PublishOnlineButton", true, false)

	var hash_before := RBMCanonicalJson.hash_of(creator.draft.battle_content_snapshot())
	var clear_check_before := creator.draft.is_clear_check_currently_valid()

	# 1) オンライン公開
	button.pressed.emit()
	await wait_process_frames(1)
	fake_steam.fire_ticket_response(fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)
	assert_true(creator.draft.is_online_published(), "sanity: initial publish must have succeeded")
	assert_eq(creator.draft.online_boss_id(), "lifecycle-boss")
	var stage_id := creator.current_stage_id
	assert_false(stage_id.is_empty())

	# 2) 公開を取り下げる（同じボタン、online_boss_idは保持されるはず）
	button.pressed.emit()
	await wait_process_frames(1)
	fake_steam.fire_ticket_response(fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)
	assert_false(creator.draft.is_online_published(), "sanity: unpublish must have succeeded")
	assert_eq(creator.draft.online_boss_id(), "lifecycle-boss", "unpublish must keep online_boss_id (soft unpublish)")
	assert_eq(api.unpublish_calls.size(), 1)
	assert_eq(api.unpublish_calls[0]["boss_id"], "lifecycle-boss")

	# 3) "Creatorを閉じる": 元のcreatorはこれ以上操作しない。

	# 4) 再度stageを開く + 5) get-bossの404によって未公開状態へ同期。
	# fakeはstart_loaded()より前にインストールする（既知の順序制約、
	# _open_and_sync()のコメント参照）。
	var reopened := _new_creator()
	var reopened_summary := _summary_of(reopened)
	var reopened_auth := _ready_steam_auth(true, true)
	var reopened_api := RBMFakeBossApiAdapter.new()
	reopened_api.configure_get_response({"ok": false, "error_kind": "http_4xx", "http_status": 404, "message": "not found"})
	reopened_api.configure_publish_response({"ok": true, "boss_id": "lifecycle-boss", "revision": 2})
	_install_fake_publisher(reopened_summary, reopened_auth, reopened_api)
	var load_result := reopened.start_loaded(stage_id)
	assert_true(bool(load_result.get("ok", false)), "sanity: reopening the stage must succeed")
	await wait_process_frames(2)

	assert_false(reopened.draft.is_online_published(), "get-boss 404 must sync the cache to not-published")
	# 5.5) 保存済みのonline_boss_idを保持
	assert_eq(reopened.draft.online_boss_id(), "lifecycle-boss", "syncing via 404 must NOT clear online_boss_id")
	var reopened_button: Button = reopened_summary.find_child("PublishOnlineButton", true, false)
	assert_eq(reopened_button.text, "オンライン公開")

	# Clear Check/battle_hashへ影響なし（ここまでの公開/取り下げ/サーバー
	# 同期を経てもなお、基準値と完全に一致すること）。
	assert_eq(RBMCanonicalJson.hash_of(reopened.draft.battle_content_snapshot()), hash_before, "publish/unpublish/sync must never touch battle_hash")
	assert_eq(reopened.draft.is_clear_check_currently_valid(), clear_check_before, "publish/unpublish/sync must never touch Clear Check")

	# 6) 再度「オンライン公開」
	var reopened_fake_steam := reopened_auth.adapter_for_testing() as RBMFakeSteamAdapter
	reopened_button.pressed.emit()
	await wait_process_frames(1)
	reopened_fake_steam.fire_ticket_response(reopened_fake_steam.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))
	await wait_process_frames(2)

	# 7) 確認点: 新しい重複Bossを作らない・online_boss_idが変わらない・
	# online_published=trueになる・Clear Check/battle_hashへ影響なし。
	assert_eq(reopened_api.publish_calls.size(), 1, "sanity: exactly one publish call for the re-publish")
	assert_eq(reopened_api.publish_calls[0]["boss_id"], "lifecycle-boss", "re-publish must pass the SAME boss_id -- must never create a duplicate boss")
	assert_eq(reopened.draft.online_boss_id(), "lifecycle-boss", "online_boss_id must remain unchanged after re-publish")
	assert_true(reopened.draft.is_online_published(), "online_published must become true again after re-publish")
	assert_eq(reopened_button.text, "公開を取り下げる")
	assert_eq(RBMCanonicalJson.hash_of(reopened.draft.battle_content_snapshot()), hash_before, "the full publish/unpublish/close/reopen/sync/republish cycle must never touch battle_hash")
	assert_eq(reopened.draft.is_clear_check_currently_valid(), clear_check_before, "the full cycle must never touch Clear Check")

	# online_boss_id/online_publishedが実際にディスクへも反映されている
	# こと（メモリ上だけでなく、次にまたCreatorを開いた時にも正しい状態が
	# 復元される保証）。
	var final_reload := RBMCreatorDraft.new()
	var final_load_result := RBMLocalStageRepository.load_stage(stage_id)
	final_reload.restore_from_saved_dict(final_load_result.get("draft_data", {}))
	assert_eq(final_reload.online_boss_id(), "lifecycle-boss")
	assert_true(final_reload.is_online_published())

	await get_tree().process_frame # drain queued UI-rebuild frees before GUT's orphan check
