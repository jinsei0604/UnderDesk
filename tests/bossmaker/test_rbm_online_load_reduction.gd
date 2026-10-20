extends GutTest

## Supabase の無料枠への負荷を減らすための、オンライン一覧の覚え書き（2026-10-18）の回帰テスト。
## - 人気・高難度は、同じモードの結果を60秒のあいだ覚え、カテゴリを行き来しても取り直さない
## - 「更新」「もう一度読み込む」は覚えた結果を使わない。失敗は覚えない。挑戦を始めたら忘れる。モードごとに別
## - 選んだボスの詳細（get-boss）は、一覧の行の版（revision）が同じなら選び直しても取り直さない。版が変われば取り直す
## 通信は偽物（RBMFakeBossApiAdapter）。実際の Supabase へは出ない。

## 一覧を作り直す時に queue_free した行が、次のフレームで消えてから終わる（GUT の Orphans の報告を出さない）
func after_each() -> void:
	await get_tree().process_frame

func _fake_api() -> RBMFakeBossApiAdapter:
	var api := RBMFakeBossApiAdapter.new()
	add_child_autofree(api)
	return api

func _view_with(api: RBMFakeBossApiAdapter) -> RBMOnlineBossListView:
	var view := RBMOnlineBossListView.new()
	view.set_api_adapter_for_testing(api)
	add_child_autofree(view)
	return view

func _payload(boss_name: String) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1200
	draft.atk = 50
	draft.spd = 10
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	return RBMOnlineBossPayload.build_for_publish(draft)["payload"]

func _rows(revision: int) -> Array:
	return [
		{"id": "a", "boss_name": "ボスA", "author_name": "A", "published_at": "2026-10-01T00:00:00+00:00", "revision": revision, "creator_mode": "simple", "appearance_id": "appearance_golem", "unique_challengers": 3, "unique_clearers": 1},
		{"id": "b", "boss_name": "ボスB", "author_name": "B", "published_at": "2026-09-30T00:00:00+00:00", "revision": 1, "creator_mode": "simple", "appearance_id": "appearance_slime", "unique_challengers": 1, "unique_clearers": 0},
	]

func _card(view: RBMOnlineBossListView, boss_id: String) -> RBMOnlineBossCard:
	return view._rows_container.get_node_or_null("OnlineBossRow_%s" % boss_id) as RBMOnlineBossCard

func _pick(view: RBMOnlineBossListView, boss_id: String) -> void:
	_card(view, boss_id).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

# =============================================================================
# 人気・高難度
# =============================================================================

func test_popular_and_hard_are_not_fetched_again_when_coming_back_within_a_minute() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": _rows(1)})
	api.configure_list_hard_response({"ok": true, "bosses": _rows(1)})
	api.configure_list_response({"ok": true, "bosses": _rows(1)})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, "高難度")
	assert_eq(api.list_popular_calls.size(), 1, "人気は1回だけ取る")
	assert_eq(api.list_hard_calls.size(), 1, "高難度は1回だけ取る")
	assert_eq(api.list_calls.size(), 1)
	assert_not_null(_card(view, "a"), "覚えた結果でも一覧は同じように出る")
	assert_not_null(_card(view, "b"))

func test_refresh_and_retry_always_fetch_again() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": _rows(1)})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	view._on_refresh_pressed()
	await get_tree().process_frame
	assert_eq(api.list_popular_calls.size(), 2, "「更新」は覚えた結果を使わない")
	view._retry_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(api.list_popular_calls.size(), 3, "「もう一度読み込む」も覚えた結果を使わない")

func test_each_mode_is_remembered_separately_and_failures_are_not_remembered() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": false, "error_kind": "network_error", "message": ""})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	api.configure_list_popular_response({"ok": true, "bosses": _rows(1)})
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(api.list_popular_calls.size(), 2, "失敗は覚えない")
	assert_not_null(_card(view, "a"))
	await view.refresh_with(RBMCreatorDraft.CREATOR_MODE_ADVANCED, RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(api.list_popular_calls.size(), 3, "モードが違えば取る")
	assert_eq(str(api.list_popular_calls[2].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_ADVANCED)

func test_the_remembered_ranking_expires_after_a_minute() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": _rows(1)})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	for key in view._list_cache:
		view._list_cache[key]["at"] = Time.get_ticks_msec() - int(RBMOnlineBossListView.LIST_CACHE_SECONDS * 1000.0) - 1
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(api.list_popular_calls.size(), 2, "60秒を過ぎたら取り直す")

func test_starting_a_challenge_forgets_the_remembered_ranking() -> void:
	var api := _fake_api()
	api.configure_list_popular_response({"ok": true, "bosses": _rows(1)})
	api.configure_get_response({"ok": true, "boss": {"id": "a", "boss_name": "ボスA", "author_name": "A", "revision": 1, "payload": _payload("ボスA")}})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	await _pick(view, "a")
	view._on_challenge_pressed()
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_POPULAR, "人気")
	assert_eq(api.list_popular_calls.size(), 2, "挑戦すると数が変わるので取り直す")

# =============================================================================
# 選んだボスの詳細
# =============================================================================

func test_picking_the_same_boss_again_does_not_fetch_its_details_again() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": _rows(3)})
	api.configure_get_response({"ok": true, "boss": {"id": "a", "boss_name": "ボスA", "author_name": "A", "revision": 3, "payload": _payload("ボスA")}})
	var view := _view_with(api)
	var received := []
	view.boss_selected.connect(func(boss_id, draft, _name, _author): received.append([boss_id, draft]))
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await _pick(view, "a")
	api.configure_get_response({"ok": true, "boss": {"id": "b", "boss_name": "ボスB", "author_name": "B", "revision": 1, "payload": _payload("ボスB")}})
	await _pick(view, "b")
	await _pick(view, "a")
	assert_eq(api.get_calls, ["a", "b"], "同じ版のボスAは取り直さない")
	assert_eq(view.selected_boss_id(), "a")
	assert_eq(received.size(), 3)
	assert_true(received[2][1] is RBMCreatorDraft, "覚えた詳細からも、戦える下書きを毎回作り直す")
	assert_ne(received[2][1], received[0][1], "同じ下書きを使い回さない（毎回検証して作る）")

func test_a_new_revision_of_the_boss_is_fetched_again() -> void:
	var api := _fake_api()
	api.configure_list_response({"ok": true, "bosses": _rows(3)})
	api.configure_get_response({"ok": true, "boss": {"id": "a", "boss_name": "ボスA", "author_name": "A", "revision": 3, "payload": _payload("ボスA")}})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await _pick(view, "a")
	api.configure_list_response({"ok": true, "bosses": _rows(4)})
	api.configure_get_response({"ok": true, "boss": {"id": "a", "boss_name": "ボスA", "author_name": "A", "revision": 4, "payload": _payload("ボスA 改")}})
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await _pick(view, "a")
	assert_eq(api.get_calls, ["a", "a"], "版が変わったら取り直す")

func test_rows_without_a_revision_always_fetch_the_details() -> void:
	var api := _fake_api()
	var rows := _rows(1)
	for row in rows:
		(row as Dictionary).erase("revision")
	api.configure_list_response({"ok": true, "bosses": rows})
	api.configure_get_response({"ok": true, "boss": {"id": "a", "boss_name": "ボスA", "author_name": "A", "revision": 1, "payload": _payload("ボスA")}})
	var view := _view_with(api)
	await view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	await _pick(view, "a")
	await _pick(view, "b")
	await _pick(view, "a")
	assert_eq(api.get_calls, ["a", "b", "a"], "版が分からない時は今までどおり毎回取る")

func test_the_detail_memory_is_bounded() -> void:
	var cache := {}
	var api := _fake_api()
	for i in RBMOnlineChallengeLoader.RESPONSE_CACHE_MAX + 5:
		var id := "boss_%d" % i
		api.configure_get_response({"ok": true, "boss": {"id": id, "boss_name": id, "author_name": "", "revision": 1, "payload": _payload(id)}})
		await RBMOnlineChallengeLoader.load_boss_for_challenge(api, id, cache, 1)
	assert_eq(cache.size(), RBMOnlineChallengeLoader.RESPONSE_CACHE_MAX, "覚える数には上限がある")
	assert_false(cache.has("boss_0"), "古いものから忘れる")
