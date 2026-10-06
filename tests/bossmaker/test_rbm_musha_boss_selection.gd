extends GutTest

## 新ボス「朽ちた機械武者」(appearance_musha)のボス選択画面への追加と、ボス数
## 増加に対応した縦スクロール化の回帰テスト。
##
## 既存6体のID/並び/カードサイズ/選択即決定は不変で、新ボスが末尾に「固有の
## 外見ID」で加わる。カードを縮小して詰め込まず、縦スクロールで全ボスへ届く。

const TEST_DIR := "user://bossmaker_test_musha_selection/stages"
const EXISTING_IDS := ["appearance_slime", "appearance_wolf", "appearance_knight", "appearance_dragon", "appearance_ghost", "appearance_golem"]
const MUSHA := "appearance_musha"
const AudioCatalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await get_tree().process_frame

## ボス選択画面を、実際の画面と同じ1280x720の領域へ置く(Creator本体のroot_column内と
## 同じく、親の矩形いっぱいに広がる)。
func _sized_picker() -> RBMCreatorAppearancePicker:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var picker := RBMCreatorAppearancePicker.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(picker)
	return picker

func _frames(n: int = 3) -> void:
	for i in range(n):
		await get_tree().process_frame

func _find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)

# ---------------------------------------------------------------------------
# 外見ID・カタログ・素材
# ---------------------------------------------------------------------------

func test_new_boss_is_appended_with_a_unique_id_and_existing_six_are_untouched() -> void:
	var ids: Array = []
	for entry in RBMCreatorAppearanceCatalog.all():
		ids.append(str(entry["id"]))
	assert_eq(ids.slice(0, 6), EXISTING_IDS, "the six existing ids and their order are unchanged")
	assert_eq(ids.size(), 9)
	assert_eq(ids[6], MUSHA)
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), "ids are unique: %s" % id)
		seen[id] = true

func test_new_boss_entry_and_name() -> void:
	var entry := RBMCreatorAppearanceCatalog.by_id(MUSHA)
	assert_eq(str(entry.get("name", "")), "朽ちた機械武者")
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening(MUSHA), "awakening (v4) is supported")
	assert_eq(RBMCreatorAppearanceCatalog.display_name(MUSHA), "朽ちた機械武者")

func test_english_name_is_localized() -> void:
	var saved := RBMLocale.current_locale()
	RBMLocale.set_locale("en")
	assert_eq(RBMCreatorAppearanceCatalog.display_name(MUSHA), "Decayed Machine Warrior")
	RBMLocale.set_locale(saved)

func test_visual_assets_map_and_existing_mappings_are_unchanged() -> void:
	assert_eq(RBMVisualAssets.boss_asset(MUSHA), "musha")
	var expected := {"appearance_slime": "slime", "appearance_wolf": "wolf", "appearance_knight": "knight",
		"appearance_dragon": "dragon", "appearance_ghost": "ghost", "appearance_golem": "golem"}
	for id in expected:
		assert_eq(RBMVisualAssets.boss_asset(id), expected[id])
	assert_eq(RBMVisualAssets.boss_asset("appearance_unknown"), "", "unknown ids stay explicit unknowns")
	assert_true(RBMVisualAssets.known("musha"))
	assert_eq(RBMVisualAssets.display_height("musha"), 180.0)
	assert_true(RBMVisualAssets.has_awakened_design("musha"), "the awakened design exists, so the preview toggle is enabled")
	assert_eq(RBMVisualAssets.display_height("musha_awakened"), 193.965)

func test_musha_textures_load_and_the_hit_pose_differs_from_idle() -> void:
	var idle := RBMVisualAssets.texture("musha", 0)
	var hit := RBMVisualAssets.texture("musha", 11)
	assert_not_null(idle)
	assert_not_null(hit)
	assert_ne(idle, hit, "pose 11 (bowed, eye off) is a different frame from the idle pose")
	assert_true(RBMVisualAssets.has_pose_frames("musha"), "all 12 pose frames exist (the convention every boss follows)")
	for asset in ["design.png", "poses.png", "ink.png", "ice.png"]:
		assert_true(ResourceLoader.exists("res://assets_bossmaker/battle/musha/" + asset, "Texture2D"), asset)

func test_audio_tracks_are_registered() -> void:
	for key in ["musha_single", "musha_aoe", "musha_buff", "musha_heal"]:
		assert_true(AudioCatalog.FILES.has(key), key)
		assert_true(ResourceLoader.exists(AudioCatalog.FILES[key]), key)

# ---------------------------------------------------------------------------
# ボス選択画面: 9体・縦スクロール・カード非縮小
# ---------------------------------------------------------------------------

func test_picker_shows_all_nine_bosses_with_unchanged_card_sizes() -> void:
	var picker := _sized_picker()
	await _frames()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	assert_eq(grid.columns, 3)
	assert_eq(grid.get_child_count(), 9)
	for card in grid.get_children():
		assert_eq((card as Control).custom_minimum_size, RBMCreatorAppearancePicker.CARD_SIZE, "cards keep their size")
		assert_gte((card as Control).size.x, RBMCreatorAppearancePicker.CARD_SIZE.x - 0.5, "%s is not squeezed horizontally" % card.name)
		assert_gte((card as Control).size.y, RBMCreatorAppearancePicker.CARD_SIZE.y - 0.5, "%s is not squeezed vertically" % card.name)
	assert_not_null(_find(picker, "Appearance_" + MUSHA))
	assert_not_null((_find(picker, "AppearancePreview_" + MUSHA) as TextureRect).texture, "the new boss card shows its image")

func test_picker_scrolls_vertically_only_and_reaches_the_new_boss() -> void:
	var picker := _sized_picker()
	await _frames()
	var scroll := _find(picker, "GridScroll") as ScrollContainer
	assert_not_null(scroll)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "no horizontal scrolling")
	assert_ne(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "vertical scrolling is available")
	var hbar := scroll.get_h_scroll_bar()
	assert_lte(hbar.max_value - hbar.page, 0.5, "cards always fit the width")
	var vbar := scroll.get_v_scroll_bar()
	assert_gt(vbar.max_value - vbar.page, 0.5, "three rows of cards exceed the visible height, so it scrolls")

	var musha_card := _find(picker, "Appearance_" + MUSHA) as Control
	# 一番上では新ボス(3行目)は見切れている → 下へスクロールすると完全に見える。
	scroll.scroll_vertical = 0
	await _frames()
	assert_false(scroll.get_global_rect().encloses(musha_card.get_global_rect()), "not fully visible before scrolling")
	scroll.scroll_vertical = int(vbar.max_value)
	await _frames()
	assert_true(scroll.get_global_rect().encloses(musha_card.get_global_rect()), "fully visible after scrolling down, without shrinking any card")
	scroll.scroll_horizontal = 300
	await _frames()
	assert_eq(scroll.scroll_horizontal, 0)

func test_picker_stays_centered_and_unscrolled_when_everything_fits() -> void:
	# 表示領域が十分大きければ従来どおり(スクロールせず中央寄せ)。
	var host := Control.new()
	host.size = Vector2(1280, 1400)
	add_child_autofree(host)
	var picker := RBMCreatorAppearancePicker.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(picker)
	await _frames()
	var scroll := _find(picker, "GridScroll") as ScrollContainer
	var vbar := scroll.get_v_scroll_bar()
	assert_lte(vbar.max_value - vbar.page, 0.5, "no scrolling needed")
	var grid := _find(picker, "AppearanceGrid") as Control
	var left_gap := grid.get_global_rect().position.x - scroll.get_global_rect().position.x
	var right_gap := scroll.get_global_rect().end.x - grid.get_global_rect().end.x
	assert_almost_eq(left_gap, right_gap, 1.5, "still horizontally centered")

# ---------------------------------------------------------------------------
# 選択の既存挙動(他ボスと統一)
# ---------------------------------------------------------------------------

func test_selecting_the_new_boss_behaves_like_the_others() -> void:
	var picker := _sized_picker()
	await _frames()
	watch_signals(picker)
	picker.open("appearance_golem")
	(_find(picker, "Appearance_" + MUSHA) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(picker, "confirmed", [MUSHA])
	assert_eq(picker._selected_id, MUSHA)
	assert_true((_find(picker, "Appearance_" + MUSHA) as Button).button_pressed)
	assert_false((_find(picker, "Appearance_appearance_golem") as Button).button_pressed, "single selection highlight")

func test_existing_bosses_still_select_and_back_restores_the_opened_boss() -> void:
	var picker := _sized_picker()
	await _frames()
	watch_signals(picker)
	picker.open("appearance_wolf")
	(_find(picker, "Appearance_appearance_slime") as Button).pressed.emit()
	assert_signal_emitted_with_parameters(picker, "confirmed", ["appearance_slime"])
	picker.select(MUSHA)
	(_find(picker, "BackButton") as Button).pressed.emit()
	assert_signal_emitted(picker, "cancelled")
	assert_eq(picker._selected_id, "appearance_wolf", "戻る restores the highlight to the boss it was opened with")

func test_new_boss_shows_the_awakening_badge_and_an_enabled_preview_toggle() -> void:
	var picker := _sized_picker()
	await _frames()
	assert_not_null(_find(picker, "AwakeningCapableBadge_" + MUSHA))
	var toggle := _find(picker, "AwakenedPreviewToggle_" + MUSHA) as Button
	assert_not_null(toggle)
	assert_false(toggle.disabled, "the awakened design exists")
	var preview := _find(picker, "AppearancePreview_" + MUSHA) as TextureRect
	var normal_texture := preview.texture
	toggle.pressed.emit()
	assert_ne(preview.texture, normal_texture, "the awakened design is previewed")
	toggle.pressed.emit()
	assert_eq(preview.texture, normal_texture, "back to the normal design")

func test_awakening_preview_toggle_does_not_leak_into_other_cards_or_selection() -> void:
	var picker := _sized_picker()
	await _frames()
	watch_signals(picker)
	var dragon_preview := _find(picker, "AppearancePreview_appearance_dragon") as TextureRect
	var dragon_texture := dragon_preview.texture
	(_find(picker, "AwakenedPreviewToggle_" + MUSHA) as Button).pressed.emit()
	assert_eq(dragon_preview.texture, dragon_texture, "other cards are unaffected")
	assert_signal_not_emitted(picker, "confirmed", "the toggle never selects a boss")

# ---------------------------------------------------------------------------
# Creator本体・保存データ
# ---------------------------------------------------------------------------

func test_creator_confirms_the_new_boss_and_it_survives_a_save_load_round_trip() -> void:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	creator.draft.boss_name = "機械武者ボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")
	creator.open_appearance_picker()
	creator._appearance_picker.confirmed.emit(MUSHA)
	assert_eq(creator.draft.appearance_id, MUSHA)
	var saved := creator.press_save_as_new()
	assert_true(bool(saved.get("ok", false)))
	var reader := RBMCreatorMain.new()
	add_child_autofree(reader)
	assert_true(bool(reader.start_loaded(str(saved.get("stage_id", ""))).get("ok", false)))
	assert_eq(reader.draft.appearance_id, MUSHA, "the saved appearance id is preserved")

func test_old_saved_appearance_ids_still_resolve() -> void:
	for id in EXISTING_IDS:
		assert_ne(RBMVisualAssets.boss_asset(id), "", "%s still resolves to its art" % id)
		assert_false(RBMCreatorAppearanceCatalog.by_id(id).is_empty())

## ボス選択画面のプレビューはフレームのキャンバスへ収めて表示されるため、通常と覚醒後の
## キャンバス内でのキャラの大きさ・位置(比率)が同じなら、「覚醒後を見る」で見た目の
## 大きさが変わらない。
func _frame_ratios(asset_id: String) -> Dictionary:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets_bossmaker/battle/%s/frames.json" % asset_id))
	var canvas: Array = meta["canvas"]
	var bbox: Array = (meta["poses"] as Array)[0]["bbox"]
	return {
		"height": float(bbox[3]) / float(canvas[1]),
		"top": float(bbox[1]) / float(canvas[1]),
		"center_x": (float(bbox[0]) + float(bbox[2]) * .5) / float(canvas[0]),
	}

func test_normal_and_awakened_previews_show_the_boss_at_the_same_size() -> void:
	var normal := _frame_ratios("musha")
	var awakened := _frame_ratios("musha_awakened")
	assert_almost_eq(float(awakened.height), float(normal.height), 0.01, "same fraction of the preview height")
	assert_almost_eq(float(awakened.top), float(normal.top), 0.01, "same vertical placement")
	assert_almost_eq(float(awakened.center_x), float(normal.center_x), 0.01, "centered like the normal form")

func test_awakened_preview_scale_matches_in_the_real_picker() -> void:
	var picker := _sized_picker()
	await _frames()
	var toggle := _find(picker, "AwakenedPreviewToggle_" + MUSHA) as Button
	var preview := _find(picker, "AppearancePreview_" + MUSHA) as TextureRect
	var normal_texture := preview.texture
	# 表示上のキャラの高さ = (キャラのbbox高さ/キャンバス高さ) * プレビュー領域の高さ(高さで収まる前提)。
	var area_height := preview.size.y
	var normal_visible := float(_frame_ratios("musha").height) * minf(area_height, preview.size.x * normal_texture.get_height() / float(normal_texture.get_width()))
	toggle.pressed.emit()
	var awakened_texture := preview.texture
	var awakened_visible := float(_frame_ratios("musha_awakened").height) * minf(area_height, preview.size.x * awakened_texture.get_height() / float(awakened_texture.get_width()))
	assert_almost_eq(awakened_visible, normal_visible, 2.0, "the boss keeps the same on-screen size when toggling the awakened preview")
