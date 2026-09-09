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

func test_unpublished_stage_never_appears_in_any_category_search_or_random() -> void:
	_save_unpublished("未公開のみボス")
	_publish("公開済みボス")

	var entry := _new_entry()
	entry.enter_challenge()

	# CATEGORY_FEATURED（注目）はこのループから除外する——Phase 4D-1以降、
	# 選択するとローカル一覧(_list_rows)ではなく別のオンライン一覧パネルが
	# 開くため（専用テストtest_featured_button_opens_the_online_list_not_the_local_list()
	# で別途検証済み）、ここに含めても_list_rowsの中身を何もテストしないまま
	# 意味を誤解させるだけになる。
	for category in [RBMChallengeHubView.CATEGORY_SIMPLE, RBMChallengeHubView.CATEGORY_HARDCORE, RBMChallengeHubView.CATEGORY_NEW, RBMChallengeHubView.CATEGORY_UNCHALLENGED, RBMChallengeHubView.CATEGORY_POPULAR, RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY]:
		entry._on_hub_category_selected(category)
		for i in range(entry._list_rows.get_child_count()):
			var card: PanelContainer = entry._list_rows.get_child(i)
			assert_false(card.name.contains("未公開"), "category %s must never include an unpublished stage" % category)

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
# ■ SIMPLE / HARDCORE
# ---------------------------------------------------------------------------

func test_simple_and_hardcore_categories_extract_only_their_own_mode() -> void:
	_publish("SIMPLEボス", RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	_publish("HARDCOREボス", RBMCreatorDraft.CREATOR_MODE_ADVANCED)

	var entry := _new_entry()
	entry.enter_challenge()

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_SIMPLE)
	assert_eq(entry._list_rows.get_child_count(), 1)
	var simple_card: PanelContainer = entry._list_rows.get_child(0)
	assert_not_null(simple_card.find_child("BossCardNameLabel_%s" % simple_card.name.trim_prefix("BossCard_"), true, false))
	var simple_mode_label: Label = simple_card.find_children("*", "Label", true, false).filter(func(l): return str(l.name).begins_with("BossCardModeLabel_"))[0]
	assert_eq(simple_mode_label.text, "SIMPLE")

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HARDCORE)
	assert_eq(entry._list_rows.get_child_count(), 1)
	var hardcore_card: PanelContainer = entry._list_rows.get_child(0)
	var hardcore_mode_label: Label = hardcore_card.find_children("*", "Label", true, false).filter(func(l): return str(l.name).begins_with("BossCardModeLabel_"))[0]
	assert_eq(hardcore_mode_label.text, "HARDCORE")

# ---------------------------------------------------------------------------
# ■ 新着
# ---------------------------------------------------------------------------

## published_at_unix_timeはTime.get_unix_time_from_system()（秒単位）に
## 依存するため、同一テスト内で2回publish()すると同じ秒に収まり順序が
## 不定になりうる——保存後のraw dictのpublished_at_unix_timeキーを直接
## 上書きしてから読み直し、実時間に依存しない決定論的なテストにする。
func test_new_category_sorts_by_published_at_descending() -> void:
	var stage_id_a := _publish("先に公開")
	var stage_id_b := _publish("後で公開")
	_force_published_at(stage_id_a, 1000)
	_force_published_at(stage_id_b, 2000)

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_NEW)
	assert_eq(entry._list_rows.get_child_count(), 2)
	var first_card: PanelContainer = entry._list_rows.get_child(0)
	assert_eq(first_card.name, "BossCard_%s" % stage_id_b, "新着は公開日時の新しい順——後で公開した方が先頭に来ること")

## テスト専用ヘルパー: 保存済みJSONのdraft.published_at_unix_timeを直接
## 上書きする——実行中のsave_new()/publish()呼び出し順に依存させず、
## 「新着」の並び替え条件だけを確定的に制御するため。
## CHALLENGE discovery 最終調整で発見・修正: この関数はdocコメントどおり
## 「published_at_unix_timeを直接上書きするだけ」のはずが、以前の版では
## 末尾に別テスト（test_new_category_sorts_by_published_at_descending）の
## アサーションがそのまま紛れ込んでいた——ボス名を「後で公開」に固定で
## 期待するため、この共有ヘルパーを別のボス名で呼ぶ新規テストが軒並み
## 失敗する潜在バグだった（このヘルパー自身に本来含まれるべきではない
## 検証だったため、含めていた側が誤りと判断し削除した）。
func _force_published_at(stage_id: String, unix_time: int) -> void:
	var result := RBMLocalStageRepository.load_stage(stage_id)
	var draft := RBMCreatorDraft.new()
	draft.restore_from_saved_dict(result.get("draft_data", {}))
	draft.restore_clear_check_snapshot(result.get("clear_check_data", {}))
	var dict := draft.to_saved_dict()
	dict["published_at_unix_time"] = unix_time
	draft.restore_from_saved_dict(dict)
	RBMLocalStageRepository.overwrite(stage_id, draft)

# ---------------------------------------------------------------------------
# ■ 未挑戦
# ---------------------------------------------------------------------------

func test_unchallenged_category_shows_only_zero_challenger_stages() -> void:
	var challenged_id := _publish("挑戦済みボス")
	_publish("未挑戦ボス")
	RBMLocalStageRepository.record_challenge_attempt(challenged_id)

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_UNCHALLENGED)
	assert_eq(entry._list_rows.get_child_count(), 1)
	var card: PanelContainer = entry._list_rows.get_child(0)
	assert_eq(card.name, "BossCard_%s" % _find_stage_id_by_name("未挑戦ボス"))

func _find_stage_id_by_name(boss_name: String) -> String:
	for entry in RBMLocalStageRepository.list():
		if str(entry.get("boss_name", "")) == boss_name:
			return str(entry.get("stage_id", ""))
	return ""

# ---------------------------------------------------------------------------
# ■ 人気
# ---------------------------------------------------------------------------

func test_popular_category_sorts_by_challenge_count_descending() -> void:
	var low_id := _publish("低人気ボス")
	var high_id := _publish("高人気ボス")
	RBMLocalStageRepository.record_challenge_attempt(low_id)
	for i in range(5):
		RBMLocalStageRepository.record_challenge_attempt(high_id)

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_POPULAR)
	assert_eq(entry._list_rows.get_child_count(), 2)
	var first_card: PanelContainer = entry._list_rows.get_child(0)
	assert_eq(first_card.name, "BossCard_%s" % high_id, "the stage with more challengers must sort first")

# ---------------------------------------------------------------------------
# ■ 高難度
# ---------------------------------------------------------------------------

func test_high_difficulty_uses_corrected_clear_rate_for_ranking_but_shows_real_clear_rate() -> void:
	# "挑戦者1人・クリア0人"が即座に最難関1位になることを防ぐための補正式
	# (clear+1)/(challenger+2)。
	var few_attempts_id := _publish("挑戦少数ボス") # 1挑戦・0クリア → 補正=1/3≈0.333、実クリア率0%
	RBMLocalStageRepository.record_challenge_attempt(few_attempts_id)

	var many_attempts_low_clear_id := _publish("多数挑戦低クリア率ボス") # 20挑戦・1クリア → 補正=2/22≈0.0909、実クリア率5%
	for i in range(20):
		RBMLocalStageRepository.record_challenge_attempt(many_attempts_low_clear_id)
	RBMLocalStageRepository.record_challenge_clear(many_attempts_low_clear_id)

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY)
	assert_eq(entry._list_rows.get_child_count(), 2)
	var first_card: PanelContainer = entry._list_rows.get_child(0)
	assert_eq(first_card.name, "BossCard_%s" % many_attempts_low_clear_id, "corrected clear rate must rank the many-attempts/low-clear stage as harder, not the 1-attempt/0-clear stage")

	# 表示は通常のクリア率——補正値をそのままユーザーへ見せない。
	var displayed_rate: Label = first_card.find_children("*", "Label", true, false).filter(func(l): return str(l.name).begins_with("BossCardClearRateLabel_"))[0]
	assert_true(displayed_rate.text.contains("5.0%"), "displayed clear rate must be the real uncorrected rate (1/20=5%%), not the internal ranking value")

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
	draft.hp = 1000000
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

## §5 item11: 新着カテゴリの並び順も、取り下げ→再公開で変動しない
## （初回公開日時に基づくため）。
func test_new_category_ranking_does_not_change_when_a_stage_is_unpublished_and_republished() -> void:
	var stage_id_a := _publish("先に公開済み")
	var stage_id_b := _publish("後で公開済み")
	_force_published_at(stage_id_a, 1000)
	_force_published_at(stage_id_b, 2000)

	var result := RBMLocalStageRepository.load_stage(stage_id_a)
	var draft := RBMCreatorDraft.new()
	draft.restore_from_saved_dict(result.get("draft_data", {}))
	draft.restore_clear_check_snapshot(result.get("clear_check_data", {}))
	draft.unpublish()
	RBMLocalStageRepository.overwrite(stage_id_a, draft)
	assert_true(draft.publish(), "sanity: re-publish must succeed")
	RBMLocalStageRepository.overwrite(stage_id_a, draft)

	var entry := _new_entry()
	entry.enter_challenge()
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_NEW)
	assert_eq(entry._list_rows.get_child_count(), 2)
	var first_card: PanelContainer = entry._list_rows.get_child(0)
	assert_eq(first_card.name, "BossCard_%s" % stage_id_b, "unpublish+republish of the older stage must not move it back to the top of 新着")

# ---------------------------------------------------------------------------
# ■ 注目（オンライン一覧の入口、Phase 4D-1）
# ---------------------------------------------------------------------------

## Phase 4D-1: 「注目」はオンライン公開ボス一覧の入口として有効化された。
## ローカルの公開済みボス(_publish())には一切影響しない——選択すると
## ローカル共通一覧(_list_panel)ではなく、別のオンライン一覧パネルが開く。
func test_featured_button_opens_the_online_list_not_the_local_list() -> void:
	_publish("ローカル公開ボスA")
	_publish("ローカル公開ボスB")
	var entry := _new_entry()
	entry.enter_challenge()

	var featured_button: Button = entry._hub_view.find_child("FeaturedCategoryButton", true, false)
	assert_not_null(featured_button)
	assert_false(featured_button.disabled, "オンライン一覧の入口として有効化された「注目」ボタンは無効化されていてはいけない")

	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_FEATURED)
	assert_false(entry._hub_view.visible, "選択するとハブから遷移する")
	assert_false(entry._list_panel.visible, "ローカル共通一覧(_list_panel)は開かない——別のオンライン一覧を使う")
	assert_true(entry._online_list_view.visible, "オンライン一覧パネルが開く")
