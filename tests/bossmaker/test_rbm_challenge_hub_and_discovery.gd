extends GutTest

## CHALLENGE UI再設計（挑戦ハブ + 共通ボス一覧画面、指示書§0〜§28）—
## §25で要求される自動テストの専用ファイル。RBMChallengeUiKitの純粋な
## データ処理（フィルタ/ソート/ランダム）と、RBMChallengeEntry/
## RBMChallengeHubView経由の実UIフローの両方を検証する。

const TEST_DIR := "user://bossmaker_test_hub_discovery/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	if FileAccess.file_exists(_tmp_recorder_steam_appid_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_recorder_steam_appid_path))

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

func _new_entry() -> RBMChallengeEntry:
	var entry := RBMChallengeEntry.new()
	add_child_autofree(entry)
	return entry

func _click_card(card: Control) -> void:
	var fake_click := InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	card.gui_input.emit(fake_click)

## §11に一致する最小限の公開済みdraft。mode=SIMPLE/HARDCOREを選べる。
func _publish(boss_name: String, mode: String = RBMCreatorDraft.CREATOR_MODE_SIMPLE, author_name: String = "") -> String:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	var skill_id := draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	if mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
		draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
		draft.action_sequence.clear()
		draft.add_action_slot({"kind": RBMActionPatternRules.SLOT_KIND_SKILL, "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	if not author_name.is_empty():
		draft.set_author_name(author_name)
	draft.record_clear_check_success()
	assert_true(draft.publish(), "sanity")
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

func _save_unpublished(boss_name: String) -> String:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

# ---------------------------------------------------------------------------
# ■ 挑戦ハブ
# ---------------------------------------------------------------------------

func test_hub_shows_all_9_navigation_entries_and_no_icons() -> void:
	var entry := _new_entry()
	entry.enter_challenge()
	assert_true(entry._hub_view.visible, "sanity: enter_challenge() must show the hub, not the list")

	for button_name in ["SimpleCategoryButton", "HardcoreCategoryButton", "FeaturedCategoryButton", "NewCategoryButton", "UnchallengedCategoryButton", "PopularCategoryButton", "HighDifficultyCategoryButton", "RandomChallengeButton", "SearchBossButton"]:
		var found: Control = entry._hub_view.find_child(button_name, true, false)
		assert_not_null(found, "hub must contain %s" % button_name)

	# §3: 今回はアイコンを一切表示しない——ボタン自体は文字のみ
	# （TextureRect/TextureButton/絵文字混じりのtextを一切持たない）。
	var buttons: Array = entry._hub_view.find_children("*", "Button", true, false)
	for button in buttons:
		assert_eq(button.find_children("*", "TextureRect", true, false).size(), 0, "%s must not contain a TextureRect icon yet" % button.name)
		assert_false(str(button.text).is_empty(), "%s must be text-based" % button.name)

	# Phase 4D-1: 「注目」はランキングアルゴリズム(Phase 5)未確定のままだが、
	# オンライン公開ボス一覧の入口として有効化された——もはや無効状態の
	# プレースホルダーではない。アイコンは追加しない(既存の他ボタンと
	# 同じ文字のみのスタイル)。
	var featured_button: Button = entry._hub_view.find_child("FeaturedCategoryButton", true, false)
	assert_false(featured_button.disabled, "オンライン一覧の入口として有効化された「注目」ボタンは無効化されていてはいけない")
	assert_eq(featured_button.text, "オンライン")
	assert_eq(featured_button.find_children("*", "TextureRect", true, false).size(), 0, "「注目」も他ボタンと同じ文字のみ、アイコンは追加しない")

	var new_button: Button = entry._hub_view.find_child("NewCategoryButton", true, false)
	assert_false(new_button.disabled, "「新着」はオンライン一覧へ接続済みのため無効化されていてはいけない")

	# オンライン版「未挑戦」/「人気」/「高難度」(2026-09)正式実装:
	# 「オンライン」「新着」と同じく全て有効化されている。
	for button_name in ["UnchallengedCategoryButton", "PopularCategoryButton", "HighDifficultyCategoryButton"]:
		var button: Button = entry._hub_view.find_child(button_name, true, false)
		assert_false(button.disabled, "%s はオンライン実装済みのため無効化されていてはいけない" % button_name)

func test_hub_back_to_root_returns_to_common_route() -> void:
	var entry := _new_entry()
	entry.enter_challenge()
	entry.exit_requested.connect(func(): _notify_exit_requested())
	var hub_back: Button = entry._hub_view.find_child("BackToRootButton", true, false)
	assert_not_null(hub_back)
	hub_back.pressed.emit()
	# exit_requestedは呼び出し元（RBMGameRoot）が受け取って画面遷移する
	# ため、このテストではシグナル自体が発火することのみを直接確認する。

var _exit_requested_fired := false
func _notify_exit_requested() -> void:
	_exit_requested_fired = true

# ---------------------------------------------------------------------------
# ■ 公開状態
# ---------------------------------------------------------------------------

## 挑戦ハブ オンライン移行(2026-09): SIMPLE/HARDCORE/オンライン/新着/未挑戦は
## Supabase上の公開ボスへ接続され、ローカルの_list_rowsには一切触れなく
## なった(専用テストtest_online_categories_open_the_online_list_not_the_local_list()
## で別途検証済み)。人気/高難度は今回未実装で、押しても_list_rowsへは
## 到達しない(test_disabled_categories_do_nothing_and_never_reach_any_list()
## で検証)。ローカルの一覧が「未公開ボスを一切含まない」という保証は、
## 今回もローカルを使い続ける検索・ランダムの2経路についてのみ意味を持つ。
func test_unpublished_stage_never_appears_in_search_or_random() -> void:
	_save_unpublished("未公開のみボス")
	_publish("公開済みボス")

	var entry := _new_entry()
	entry.enter_challenge()

	entry._on_hub_search_requested()
	assert_eq(entry._list_rows.get_child_count(), 1, "search (no filter) must show only the published stage")

	var candidates := entry._base_published_playable_entries()
	assert_eq(candidates.size(), 1, "the random pool itself must exclude the unpublished stage")
	assert_eq(str(candidates[0].get("boss_name", "")), "公開済みボス")

func test_search_excludes_unpublished_stages_by_name() -> void:
	_save_unpublished("検索対象未公開ボス")
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	entry._name_search_field.text = "検索対象"
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0, "search must never surface an unpublished stage even when the name matches")

# ---------------------------------------------------------------------------
# ■ SIMPLE / HARDCORE / オンライン / 新着 / 未挑戦（挑戦ハブ オンライン移行、2026-09）
#
# ユーザー確定仕様: この5カテゴリは全てSupabase上の公開ボス一覧
# (RBMOnlineBossListView)へ接続する。ローカルの_list_rows/
# RBMLocalStageRepositoryには一切触れない——RBMFakeBossApiAdapterへ
# 差し替えて、実HTTPへは出ずに検証する。
# ---------------------------------------------------------------------------

func _fake_online_api() -> RBMFakeBossApiAdapter:
	var api := RBMFakeBossApiAdapter.new()
	add_child_autofree(api)
	return api

func _entry_with_online_api(api: RBMFakeBossApiAdapter) -> RBMChallengeEntry:
	var entry := RBMChallengeEntry.new()
	entry.set_online_api_adapter_for_testing(api)
	add_child_autofree(entry)
	return entry

## Steam App ID環境分離——他のSteam関連テストと同じ確立済みパターン
## (test_rbm_steam_auth.gd/test_rbm_boss_publisher.gd参照)。
var _tmp_recorder_steam_appid_path := "user://test_steam_dev_appid_hub_discovery.local.txt"

func _ready_steam_auth_for_recorder(available := true, logged_on := true) -> RBMSteamAuth:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_recorder_steam_appid_path)
	var file := FileAccess.open(_tmp_recorder_steam_appid_path, FileAccess.WRITE)
	file.store_string("480")
	file.close()
	var fake := RBMFakeSteamAdapter.new()
	if available:
		fake.configure_available()
	else:
		fake.configure_unavailable()
	fake.configure_logged_on(logged_on, 76561198000000001, "Tester")
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	add_child_autoqfree(auth)
	auth.initialize()
	return auth

func _schedule_recorder_ticket_success(auth: RBMSteamAuth) -> void:
	_fire_recorder_ticket_success.call_deferred(auth)

func _fire_recorder_ticket_success(auth: RBMSteamAuth) -> void:
	var fake := auth.adapter_for_testing() as RBMFakeSteamAdapter
	fake.fire_ticket_response(fake.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))

func _entry_with_online_api_and_recorder(api: RBMFakeBossApiAdapter, recorder: RBMOnlineChallengeRecorder) -> RBMChallengeEntry:
	var entry := RBMChallengeEntry.new()
	entry.set_online_api_adapter_for_testing(api)
	entry.set_online_recorder_for_testing(recorder)
	add_child_autofree(entry)
	return entry

func _minimal_online_draft(boss_name: String = "オンライン挑戦テストボス") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	return draft

func test_online_categories_open_the_online_list_not_the_local_list() -> void:
	_publish("ローカル公開ボスA")
	_publish("ローカル公開ボスB")

	for category in [RBMChallengeHubView.CATEGORY_FEATURED, RBMChallengeHubView.CATEGORY_NEW, RBMChallengeHubView.CATEGORY_SIMPLE, RBMChallengeHubView.CATEGORY_HARDCORE, RBMChallengeHubView.CATEGORY_UNCHALLENGED, RBMChallengeHubView.CATEGORY_POPULAR, RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY]:
		var api := _fake_online_api()
		api.configure_list_response({"ok": true, "bosses": []})
		var entry := _entry_with_online_api(api)
		entry.enter_challenge()

		entry._on_hub_category_selected(category)
		assert_false(entry._hub_view.visible, "category %s must navigate away from the hub" % category)
		assert_false(entry._list_panel.visible, "category %s must never open the local list panel" % category)
		assert_true(entry._online_list_view.visible, "category %s must open the online list panel" % category)

func test_online_category_requests_no_mode_filter() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_FEATURED)
	assert_eq(api.list_calls.size(), 1)
	assert_eq(str(api.list_calls[0].get("mode", "")), "", "「オンライン」は絞り込みなしの全件取得であること")
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_ONLINE)

func test_new_category_requests_no_mode_filter_and_uses_the_new_category() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_NEW)
	assert_eq(api.list_calls.size(), 1)
	assert_eq(str(api.list_calls[0].get("mode", "")), "")
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_NEW)

func test_simple_category_requests_the_simple_mode_filter() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_SIMPLE)
	assert_eq(api.list_calls.size(), 1)
	assert_eq(str(api.list_calls[0].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(entry._online_list_view.current_mode(), RBMCreatorDraft.CREATOR_MODE_SIMPLE)

func test_hardcore_category_requests_the_advanced_mode_filter() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HARDCORE)
	assert_eq(api.list_calls.size(), 1)
	assert_eq(str(api.list_calls[0].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(entry._online_list_view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)

## 「モードを切り替えたら、現在選択しているカテゴリを維持したまま
## 一覧を再取得/再表示する」の統合確認——挑戦ハブ経由でSIMPLE→HARDCOREと
## 切り替えても、選んでいたのが「新着」カテゴリならcategoryはNEWのまま
## 維持されること。
func test_switching_mode_keeps_the_previously_selected_category() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_NEW)
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_NEW)

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HARDCORE)
	assert_eq(entry._online_list_view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	# モードとカテゴリは独立した状態(§11「SIMPLE + 未挑戦 → 未挑戦SIMPLE
	# だけ」と同じ設計)——HARDCOREボタンはmodeだけを変更し、選択中だった
	# 「新着」カテゴリは維持されたままであること。
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_NEW, "モード切替は現在選択中のカテゴリ(新着)を維持したまま反映されること")

## §11(ユーザー確定仕様)の具体例そのもの: 「SIMPLE + 未挑戦 → 未挑戦SIMPLE
## だけ」「HARDCORE + 未挑戦 → 未挑戦HARDCOREだけ」。
func test_simple_or_hardcore_combined_with_unchallenged_composes_both_filters() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_SIMPLE)
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_UNCHALLENGED)
	assert_eq(entry._online_list_view.current_mode(), RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_UNCHALLENGED)

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HARDCORE)
	assert_eq(entry._online_list_view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_UNCHALLENGED, "未挑戦は維持したままモードだけHARDCOREへ切り替わること")

func test_online_list_shows_published_bosses_returned_by_the_adapter() -> void:
	var api := _fake_online_api()
	api.configure_list_response({
		"ok": true,
		"bosses": [
			{"id": "b1", "boss_name": "公開ボスA", "author_name": "作者A", "creator_mode": "simple"},
			{"id": "b2", "boss_name": "公開ボスB", "author_name": "作者B", "creator_mode": "advanced"},
		],
	})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_FEATURED)
	assert_eq(entry._online_list_view._rows_container.get_child_count(), 2)

func test_online_list_shows_empty_state_with_zero_published_bosses() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_FEATURED)
	assert_eq(entry._online_list_view._rows_container.get_child_count(), 0)
	assert_true(entry._online_list_view._status_label.text.length() > 0)

func test_online_list_shows_an_error_state_on_supabase_failure_without_crashing() -> void:
	var api := _fake_online_api()
	api.configure_list_response({"ok": false, "error_kind": "network_error", "message": "timeout"})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_FEATURED)
	assert_eq(entry._online_list_view._rows_container.get_child_count(), 0)
	assert_true(entry._online_list_view._status_label.text.length() > 0, "communication failure must show a status message, not crash")
	assert_true(entry._online_list_view.visible, "the game must keep running -- the online panel itself must stay usable")

# ---------------------------------------------------------------------------
# ■ 人気 / 高難度（オンライン版、2026-09正式実装）
#
# ランキング自体はSupabase側(list-popular-bosses/list-hard-bosses)で計算
# する——クライアント側は結果をそのまま表示するだけで再計算・再ソートは
# しない(list-bosses/list-unchallenged-bossesと同じ設計方針)。
# ---------------------------------------------------------------------------

func test_popular_category_requests_no_mode_filter_and_uses_the_popular_category() -> void:
	var api := _fake_online_api()
	api.configure_list_popular_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_POPULAR)
	assert_eq(api.list_popular_calls.size(), 1)
	assert_eq(str(api.list_popular_calls[0].get("mode", "")), "")
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_POPULAR)
	assert_false(entry._list_panel.visible, "人気はローカル一覧を使わない")
	assert_true(entry._online_list_view.visible)

func test_high_difficulty_category_requests_no_mode_filter_and_uses_the_high_difficulty_category() -> void:
	var api := _fake_online_api()
	api.configure_list_hard_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY)
	assert_eq(api.list_hard_calls.size(), 1)
	assert_eq(str(api.list_hard_calls[0].get("mode", "")), "")
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY)
	assert_false(entry._list_panel.visible, "高難度はローカル一覧を使わない")
	assert_true(entry._online_list_view.visible)

## §11と同じ「SIMPLE/HARDCORE + カテゴリ」の組み合わせ仕様が人気/高難度でも
## 成立すること。
func test_simple_or_hardcore_combined_with_popular_composes_both_filters() -> void:
	var api := _fake_online_api()
	api.configure_list_popular_response({"ok": true, "bosses": []})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_SIMPLE)
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_POPULAR)
	assert_eq(entry._online_list_view.current_mode(), RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_POPULAR)
	assert_eq(str(api.list_popular_calls[api.list_popular_calls.size() - 1].get("mode", "")), RBMCreatorDraft.CREATOR_MODE_SIMPLE)

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HARDCORE)
	assert_eq(entry._online_list_view.current_mode(), RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(entry._online_list_view.current_category(), RBMOnlineBossListView.CATEGORY_POPULAR, "人気は維持したままモードだけHARDCOREへ切り替わること")

func test_online_list_shows_popular_bosses_returned_by_the_adapter() -> void:
	var api := _fake_online_api()
	api.configure_list_popular_response({
		"ok": true,
		"bosses": [
			{"id": "p1", "boss_name": "人気ボスA", "author_name": "作者A"},
			{"id": "p2", "boss_name": "人気ボスB", "author_name": "作者B"},
		],
	})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_POPULAR)
	assert_eq(entry._online_list_view._rows_container.get_child_count(), 2)

func test_online_list_shows_hard_bosses_returned_by_the_adapter() -> void:
	var api := _fake_online_api()
	api.configure_list_hard_response({
		"ok": true,
		"bosses": [{"id": "h1", "boss_name": "高難度ボスA", "author_name": "作者A"}],
	})
	var entry := _entry_with_online_api(api)
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY)
	assert_eq(entry._online_list_view._rows_container.get_child_count(), 1)

## RBMChallengeUiKitのローカル用フィルタ/ソート関数自体は削除していない
## （ローカル公開ステージ一覧は今回の対象外のまま維持する、ユーザー確定
## 仕様）——挑戦ハブからは到達しないため、純粋関数として直接呼び出す形で
## カバレッジを維持する。
func test_filter_unchallenged_still_works_as_a_pure_function() -> void:
	var entries: Array[Dictionary] = [
		{"stage_id": "a", "challenge_count": 0},
		{"stage_id": "b", "challenge_count": 3},
	]
	var result := RBMChallengeUiKit.filter_unchallenged(entries)
	assert_eq(result.size(), 1)
	assert_eq(str(result[0].get("stage_id", "")), "a")

func test_sort_by_challenge_count_desc_still_works_as_a_pure_function() -> void:
	var entries: Array[Dictionary] = [
		{"stage_id": "low", "challenge_count": 1},
		{"stage_id": "high", "challenge_count": 5},
	]
	var result := RBMChallengeUiKit.sort_by_challenge_count_desc(entries)
	assert_eq(str(result[0].get("stage_id", "")), "high")

func test_sort_by_corrected_clear_rate_asc_still_works_as_a_pure_function() -> void:
	var entries: Array[Dictionary] = [
		{"stage_id": "few_attempts", "challenge_count": 1, "clear_count": 0},
		{"stage_id": "many_low_clear", "challenge_count": 20, "clear_count": 1},
	]
	var result := RBMChallengeUiKit.sort_by_corrected_clear_rate_asc(entries)
	assert_eq(str(result[0].get("stage_id", "")), "many_low_clear", "corrected clear rate must still rank the many-attempts/low-clear entry as harder")

func test_corrected_clear_rate_formula_matches_the_spec_exactly() -> void:
	var entry_dict := {"challenge_count": 4, "clear_count": 1}
	assert_almost_eq(RBMChallengeUiKit.corrected_clear_rate(entry_dict), (1.0 + 1.0) / (4.0 + 2.0), 0.0001)

func test_real_clear_rate_is_zero_percent_for_zero_challenges_not_100_percent() -> void:
	var entry_dict := {"challenge_count": 0, "clear_count": 0}
	assert_almost_eq(RBMChallengeUiKit.real_clear_rate(entry_dict), 0.0, 0.0001)

# ---------------------------------------------------------------------------
# ■ ランダム
# ---------------------------------------------------------------------------

func test_random_pool_is_published_playable_only_and_ignores_mode_and_stats() -> void:
	_save_unpublished("ランダム対象外未公開ボス")
	var uniform_a := _publish("ランダムA", RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	var uniform_b := _publish("ランダムB", RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var uniform_c := _publish("ランダムC", RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	# Cだけ極端に挑戦者数・クリア率を偏らせる——重み付けが働いていれば
	# 選ばれる頻度に明確な偏りが出るはずの構成。
	for i in range(500):
		RBMLocalStageRepository.record_challenge_attempt(uniform_c)
		RBMLocalStageRepository.record_challenge_clear(uniform_c)

	var entry := _new_entry()
	entry.enter_challenge()
	var candidates := entry._base_published_playable_entries()
	assert_eq(candidates.size(), 3, "the unpublished stage must never enter the random pool")

	var picked_ids := {}
	for seed_value in range(300):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var picked := RBMChallengeUiKit.pick_random(candidates, rng)
		picked_ids[str(picked.get("stage_id", ""))] = int(picked_ids.get(str(picked.get("stage_id", "")), 0)) + 1

	assert_true(picked_ids.has(uniform_a), "no weighting: the lowest-stat stage must still be reachable")
	assert_true(picked_ids.has(uniform_b), "no weighting: HARDCORE must not be excluded/favored")
	assert_true(picked_ids.has(uniform_c), "sanity: the highest-stat stage must also be reachable")

func test_random_button_opens_the_common_list_with_the_picked_boss_selected_and_does_not_start_battle() -> void:
	_publish("ランダム抽選対象ボス")
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_random_requested()

	assert_true(entry._list_panel.visible, "random must open the common list+detail screen")
	assert_false(entry._battle_view.visible, "random must never auto-start a battle")
	assert_false(entry._selected_stage_id.is_empty(), "random must leave a stage selected")
	assert_eq(entry._confirm_view.stage_id, entry._selected_stage_id, "the detail panel must show the picked boss")
	assert_null(entry._battle_view.session)

func test_random_with_no_published_stages_does_nothing_safely() -> void:
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_random_requested()
	assert_true(entry._hub_view.visible, "with nothing to pick, the hub must simply stay put (no crash, no broken transition)")

# ---------------------------------------------------------------------------
# ■ 詳細パネル（重複禁止・空状態）
# ---------------------------------------------------------------------------

func test_detail_panel_shows_empty_state_until_a_card_is_selected() -> void:
	_publish("詳細未選択確認ボス")
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	assert_true(entry._confirm_view._empty_state_label.visible, "before any selection, the detail panel must show its empty state")
	assert_false(entry._confirm_view._detail_content.visible)

	var card: PanelContainer = entry._list_rows.get_child(0)
	_click_card(card)
	assert_false(entry._confirm_view._empty_state_label.visible)
	assert_true(entry._confirm_view._detail_content.visible)

func test_detail_panel_never_repeats_challenge_count_or_clear_rate() -> void:
	var stage_id := _publish("重複確認ボス")
	RBMLocalStageRepository.record_challenge_attempt(stage_id)
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))

	# §13: 挑戦回数・クリア率は一覧カード側にのみ表示する——確認画面
	# (RBMChallengeConfirmView)自身のどのLabelにも、それらしい文言が
	# 一切含まれないことを直接確認する。
	# 注意: 「挑戦者が使用するパーティ・使用可能スキル」という既存の見出し
	# （§16、攻略パーティ表示のヘッダ、公開設定に紐づかない別概念）内の
	# 「挑戦者」という単語（人を指す普通名詞、カードの回数表記とは無関係）
	# とは区別するため、カード側の実際の書式（"挑戦 <数字>回"、
	# RBMChallengeUiKit.build_boss_card()参照）に限定した正規表現で
	# チェックする。
	var challenge_count_pattern := RegEx.new()
	challenge_count_pattern.compile("挑戦\\s*\\d+回")
	var all_labels: Array = entry._confirm_view.find_children("*", "Label", true, false)
	for label in all_labels:
		assert_null(challenge_count_pattern.search(str(label.text)), "detail panel must never show the 挑戦 <count>回 card stat (label was: %s)" % label.text)
		assert_false(str(label.text).contains("クリア率"), "detail panel must never show クリア率 (already on the card)")

func test_detail_panel_shows_large_image_author_and_mode() -> void:
	_publish("詳細表示確認ボス", RBMCreatorDraft.CREATOR_MODE_ADVANCED, "テスト作者")
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))

	assert_not_null(entry._confirm_view.find_child("ConfirmBossImage", true, false), "detail panel must show a large boss image area")
	assert_true(entry._confirm_view._author_label.text.contains("テスト作者"))
	assert_eq(entry._confirm_view._mode_label.text, "HARDCORE")

func test_author_name_defaults_to_placeholder_when_empty() -> void:
	_publish("作者名未設定ボス")
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	assert_true(entry._confirm_view._author_label.text.contains("（未設定）"))

# ---------------------------------------------------------------------------
# ■ 戦闘開始（追加確認なし）
# ---------------------------------------------------------------------------

func test_challenge_start_from_detail_panel_immediately_begins_battle_with_no_extra_confirmation() -> void:
	_publish("即戦闘開始ボス")
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	assert_false(entry._battle_view.visible, "sanity: selecting alone must not start battle")

	entry._confirm_view._on_challenge_pressed()
	assert_true(entry._battle_view.visible, "『このボスに挑戦』は追加の確認画面を挟まず即座に戦闘を開始する")
	assert_not_null(entry._battle_view.session)
	assert_true(entry._battle_view.session.start_ok())
	await get_tree().process_frame # drain queued UI-rebuild frees (remove_child+queue_free, see rbm_battle_ui_kit.gd) before GUT's orphan check; real gameplay always gets this frame naturally

func test_challenge_attempt_is_recorded_exactly_once_per_battle_start_not_per_retry() -> void:
	var stage_id := _publish("挑戦回数記録確認ボス")
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	entry._confirm_view._on_challenge_pressed()
	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("challenge_count", 0)), 1)

	# 「最初からやり直す」は新たな挑戦としては数えない（同じ試行の継続）。
	entry._battle_view._on_restart_pressed()
	entry._battle_view._on_restart_confirmed()
	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("challenge_count", 0)), 1, "restarting mid-session must not inflate the challenge count")
	await get_tree().process_frame # drain queued UI-rebuild frees (remove_child+queue_free, see rbm_battle_ui_kit.gd) before GUT's orphan check; real gameplay always gets this frame naturally

## CHALLENGE discovery 最終調整 §5 item2: 「最初からやり直す」（同一
## セッション内の継続）とは異なり、一度一覧へ戻ってから改めて『このボスに
## 挑戦』を押す＝正真正銘の再挑戦は、挑戦回数へさらに加算されること。
func test_challenging_the_same_boss_again_after_returning_to_the_list_increments_challenge_count_further() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "再挑戦回数確認ボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	assert_true(draft.publish(), "sanity")
	var result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(result.get("stage_id", ""))

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over, "sanity")
	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("challenge_count", 0)), 1)

	entry._battle_view._on_return_pressed()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	entry._confirm_view._on_challenge_pressed()
	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("challenge_count", 0)), 2, "challenging the same boss again from the hub (after returning to the list) must increment challenge_count further")
	await get_tree().process_frame # drain queued UI-rebuild frees (remove_child+queue_free, see rbm_battle_ui_kit.gd) before GUT's orphan check; real gameplay always gets this frame naturally

func test_challenge_clear_is_recorded_exactly_once_on_win() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "クリア記録確認ボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	draft.publish()
	var result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(result.get("stage_id", ""))

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over, "sanity")
	assert_eq(entry._battle_view.session.battle.winner, "ally", "sanity")

	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("clear_count", 0)), 1)
	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("challenge_count", 0)), 1)
	await get_tree().process_frame # drain queued UI-rebuild frees (remove_child+queue_free, see rbm_battle_ui_kit.gd) before GUT's orphan check; real gameplay always gets this frame naturally

## CHALLENGE discovery 最終調整 §5 item3: 敗北はclear_countを増やさない
## （挑戦回数は通常どおり1加算される）。
func test_losing_a_battle_does_not_increment_clear_count() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "敗北記録確認ボス"
	draft.hp = 99999
	draft.atk = 9999
	draft.spd = 500
	var atk_id := draft.add_skill({"name": "即死級攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 50.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[atk_id] = 100.0
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	assert_true(draft.publish(), "sanity")
	var result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(result.get("stage_id", ""))

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over, "sanity")
	assert_eq(entry._battle_view.session.battle.winner, "boss", "sanity: this test requires an actual loss")

	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("challenge_count", 0)), 1, "a battle start still counts as a challenge even if it ends in a loss")
	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("clear_count", 0)), 0, "a loss must never increment clear_count")
	await get_tree().process_frame # drain queued UI-rebuild frees (remove_child+queue_free, see rbm_battle_ui_kit.gd) before GUT's orphan check; real gameplay always gets this frame naturally

## CHALLENGE discovery 最終調整 §5 item7: 「人」ではなく「回」で表示される。
func test_card_challenge_count_reads_as_a_count_of_times_not_a_headcount() -> void:
	var stage_id := _publish("表記確認ボス")
	RBMLocalStageRepository.record_challenge_attempt(stage_id)
	RBMLocalStageRepository.record_challenge_attempt(stage_id)
	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_search_requested()
	var card: PanelContainer = entry._list_rows.get_child(0)
	var challenge_count_label: Label = card.find_children("*", "Label", true, false).filter(func(l): return str(l.name).begins_with("BossCardChallengeCountLabel_"))[0]
	assert_true(challenge_count_label.text.contains("2"), "sanity: 2 recorded attempts")
	assert_true(challenge_count_label.text.contains("回"), "must read as a count of attempts (回), not a headcount")
	assert_false(challenge_count_label.text.contains("者"), "must not use 挑戦者 (implies a headcount of people)")
	assert_false(challenge_count_label.text.contains("人"), "must not use a headcount word like 人")

# ---------------------------------------------------------------------------
# ■ オンライン版「未挑戦」— 挑戦開始/クリアのオンライン記録(2026-09)
#
# ユーザー確定仕様§9: オンライン/ローカルの判定は既存の明示的な
# _last_browse_was_onlineフラグで行う(UUID形式かどうかの推測判定はしない)。
# §7: 記録はベストエフォート——Steam ticket取得/Edge Function呼び出しが
# 失敗しても、戦闘開始・勝利処理そのものは必ず正常に進む。
# ---------------------------------------------------------------------------

func test_starting_an_online_challenge_calls_record_challenge_attempt_with_the_boss_id() -> void:
	var auth := _ready_steam_auth_for_recorder()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)

	var browse_api := _fake_online_api()
	var entry := _entry_with_online_api_and_recorder(browse_api, recorder)
	entry.enter_challenge()
	entry._on_online_boss_selected("online-boss-1", _minimal_online_draft(), "オンライン挑戦テストボス", "")

	_schedule_recorder_ticket_success(auth)
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(3)

	assert_true(entry._battle_view.visible, "sanity: challenge must still start")
	assert_eq(recorder_api.record_attempt_calls.size(), 1)
	assert_eq(recorder_api.record_attempt_calls[0]["boss_id"], "online-boss-1")
	await get_tree().process_frame # drain queued UI-rebuild frees, matching the existing local equivalents in this file

func test_starting_a_local_challenge_never_calls_the_online_record_attempt_api() -> void:
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_api_adapter_for_testing(recorder_api)

	var stage_id := _publish("ローカル挑戦記録確認ボス")
	var browse_api := _fake_online_api()
	var entry := _entry_with_online_api_and_recorder(browse_api, recorder)
	entry.enter_challenge()
	entry._on_hub_search_requested()
	_click_card(entry._list_rows.get_child(0))
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(2)

	assert_eq(recorder_api.record_attempt_calls.size(), 0, "a local challenge must never reach the online record-challenge-attempt endpoint")
	assert_eq(int(RBMLocalStageRepository.read_stage_stats(stage_id).get("challenge_count", 0)), 1, "sanity: the local counter must still be used")
	await get_tree().process_frame

func test_online_challenge_attempt_recording_failure_never_blocks_battle_start() -> void:
	# Steamが利用不可(recorderがticket取得に失敗する)状況を想定——記録は
	# 諦めるが、戦闘は必ず開始する(§7、通信失敗でゲームを止めない)。
	var auth := _ready_steam_auth_for_recorder(false, false)
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)

	var browse_api := _fake_online_api()
	var entry := _entry_with_online_api_and_recorder(browse_api, recorder)
	entry.enter_challenge()
	entry._on_online_boss_selected("online-boss-2", _minimal_online_draft(), "オンライン挑戦テストボス", "")

	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(2)

	assert_true(entry._battle_view.visible, "battle must start even though the recording call could never even acquire a ticket")
	assert_not_null(entry._battle_view.session)
	assert_true(entry._battle_view.session.start_ok())
	assert_eq(recorder_api.record_attempt_calls.size(), 0, "sanity: the call never reached the API because ticket acquisition failed first")
	await get_tree().process_frame

func test_winning_an_online_challenge_calls_record_challenge_clear_with_the_boss_id() -> void:
	var auth := _ready_steam_auth_for_recorder()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)

	var browse_api := _fake_online_api()
	var entry := _entry_with_online_api_and_recorder(browse_api, recorder)
	entry.enter_challenge()
	entry._on_online_boss_selected("online-boss-3", _minimal_online_draft(), "オンライン挑戦テストボス", "")

	_schedule_recorder_ticket_success(auth)
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(3)
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over, "sanity")
	assert_eq(entry._battle_view.session.battle.winner, "ally", "sanity")

	_schedule_recorder_ticket_success(auth)
	await wait_process_frames(3)

	assert_eq(recorder_api.record_clear_calls.size(), 1)
	assert_eq(recorder_api.record_clear_calls[0]["boss_id"], "online-boss-3")
	assert_eq(recorder_api.record_attempt_calls.size(), 1, "sanity: the earlier attempt call must also have gone through")
	await get_tree().process_frame

func test_online_clear_recording_failure_never_blocks_the_win_flow() -> void:
	var auth := _ready_steam_auth_for_recorder()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	recorder_api.configure_record_clear_response({"ok": false, "error_kind": "db_error", "message": "boom"})
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)

	var browse_api := _fake_online_api()
	var entry := _entry_with_online_api_and_recorder(browse_api, recorder)
	entry.enter_challenge()
	entry._on_online_boss_selected("online-boss-4", _minimal_online_draft(), "オンライン挑戦テストボス", "")

	_schedule_recorder_ticket_success(auth)
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(3)
	entry._battle_view.act_attack(0)

	assert_true(entry._battle_view.session.battle.battle_over, "the win flow itself must complete regardless of the recording server error")
	assert_eq(entry._battle_view.session.battle.winner, "ally")
	_schedule_recorder_ticket_success(auth)
	await wait_process_frames(3)
	assert_eq(recorder_api.record_clear_calls.size(), 1, "sanity: the call was made even though it reported failure")
	await get_tree().process_frame

## §12(ユーザー確定仕様)「一度挑戦したbossが次回未挑戦から消える」——
## 実際に「消える」ことを保証する除外ロジックはサーバー側
## (list-unchallenged-bosses、challenge_count>0を除外)にあり、
## supabase/functions/list-unchallenged-bosses/index.test.ts::
## "returns only bosses this Steam user has never challenged"で既に
## 検証済み。このテストではクライアント側の配線——挑戦記録
## (record_challenge_attempt)と未挑戦一覧取得(list_unchallenged_bosses)が
## 同じrecorder(同じSteam ticket経路・同じAPIアダプター)を通ることだけを
## 確認する(fakeアダプターは実DB状態を保持しないため、「本当に消える」
## こと自体はサーバー側テストの責務)。
func test_attempt_recording_and_unchallenged_fetch_go_through_the_same_recorder() -> void:
	var auth := _ready_steam_auth_for_recorder()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)

	var browse_api := _fake_online_api()
	browse_api.configure_list_response({"ok": true, "bosses": [{"id": "online-boss-5", "boss_name": "未挑戦確認ボス", "author_name": ""}]})
	var entry := _entry_with_online_api_and_recorder(browse_api, recorder)
	entry.enter_challenge()
	entry._on_online_boss_selected("online-boss-5", _minimal_online_draft(), "未挑戦確認ボス", "")

	_schedule_recorder_ticket_success(auth)
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(3)
	assert_eq(recorder_api.record_attempt_calls.size(), 1)
	assert_eq(recorder_api.record_attempt_calls[0]["boss_id"], "online-boss-5")

	entry._on_battle_returned_to_list()
	_schedule_recorder_ticket_success(auth)
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_UNCHALLENGED)
	await wait_process_frames(3)

	assert_eq(recorder_api.list_unchallenged_calls.size(), 1, "未挑戦一覧の取得も同じrecorder(同じAPIアダプター)を経由すること")
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# ■ 公開日時（初回公開日時として固定、CHALLENGE discovery 最終調整 §2）
# ---------------------------------------------------------------------------

## §5 item8: 初回公開時のみ公開日時が設定される。
func test_published_at_is_set_only_on_first_publish() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "初回公開日時確認ボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	assert_eq(draft.published_at_unix_time(), 0, "sanity: never published yet")
	draft.record_clear_check_success()
	assert_true(draft.publish())
	assert_true(draft.published_at_unix_time() > 0, "the first publish must set the timestamp")

## §5 item9: 公開取り下げで公開日時が消えない。
func test_unpublishing_does_not_clear_the_published_at_timestamp() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "取り下げ日時保持確認ボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	draft.publish()
	var first_timestamp := draft.published_at_unix_time()
	assert_true(first_timestamp > 0, "sanity")

	draft.unpublish()
	assert_eq(draft.published_at_unix_time(), first_timestamp, "unpublishing must not clear the first-publish timestamp")

## §5 item10: 再公開でも公開日時が変わらない。
func test_republishing_does_not_change_the_published_at_timestamp() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "再公開日時不変確認ボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	draft.publish()
	var first_timestamp := draft.published_at_unix_time()

	draft.unpublish()
	assert_true(draft.publish(), "sanity: re-publish must succeed (Clear Check state is untouched by unpublish)")
	assert_eq(draft.published_at_unix_time(), first_timestamp, "re-publishing must keep the original first-publish timestamp, not refresh it")

## §5 item11: 公開日時は取り下げ→再公開で変動しない（初回公開日時に
## 基づくため）——ドラフト自体の挙動としては上のtest_unpublishing_does_not_clear_the_published_at_timestamp()/
## test_republishing_does_not_change_the_published_at_timestamp()で既に
## 検証済み。「新着」カテゴリ自体の並び替えは、挑戦ハブ オンライン移行
## (2026-09)によりサーバー側(list-bosses、published_at.desc)の責務になった
## ——クライアント側の対応する検証はsupabase/functions/list-bosses/index.test.ts
## と、test_rbm_online_boss_list_view.gd::test_rows_render_in_the_order_the_server_returned_them()
## に移した。

# ---------------------------------------------------------------------------
# ■ オンライン / 新着 / SIMPLE / HARDCORE（挑戦ハブの入口としての検証）
#
# 実際のAPI呼び出し・パネル遷移の検証は上の「SIMPLE / HARDCORE / オンライン
# / 新着」節(test_online_categories_open_the_online_list_not_the_local_list()
# 等)へ統合済み——ここには重複するテストを追加しない。
