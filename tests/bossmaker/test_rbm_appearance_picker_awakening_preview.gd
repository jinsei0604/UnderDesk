extends GutTest

## RPG BOSS MAKER — ボス選択画面(RBMCreatorAppearancePicker)の回帰テスト。
## 2026-10-28 ユーザー承認の作り直し: 左にボスの一覧（カードを押すと選ぶだけ）、右にプロフィール（立ち絵・特徴・
## 覚醒できるボスだけ「覚醒後を見る」／「通常に戻す」・単体／全体攻撃のプレビュー枠・「このボスにする」で決定）。
##
## RBMCreatorAppearanceCatalog.ENTRIESはGodotのconstとして実行時読み取り専用のため、覚醒後アセットが無い場合などの
## 構造テストは picker._build_card() へその場限りの fixture Dictionary を直接渡して確かめる（実在の id と衝突しない
## "appearance_test_fixture*" だけを使う）。

const AWAKENING_IDS := ["appearance_dragon", "appearance_musha", "appearance_astronaut", "appearance_gentleman", "appearance_plush"]

func after_each() -> void:
	await get_tree().process_frame

func _new_picker() -> RBMCreatorAppearancePicker:
	var picker := RBMCreatorAppearancePicker.new()
	picker.size = Vector2(1232, 640)
	add_child_autofree(picker)
	return picker

func _find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)

# ---------------------------------------------------------------------------
# 一覧: 全ボス・同じ大きさの絵の枠・ドット絵はぼかさない・スクロール
# ---------------------------------------------------------------------------

func test_thumbnails_share_one_box_size_and_use_nearest_filter() -> void:
	var picker := _new_picker()
	var sizes: Array = []
	for entry in RBMCreatorAppearanceCatalog.all():
		var id := str(entry["id"])
		var area: Control = _find(picker, "AppearancePreviewArea_%s" % id)
		assert_not_null(area)
		sizes.append(area.size)
		var thumb: TextureRect = _find(picker, "AppearancePreview_%s" % id)
		assert_not_null(thumb.texture, "%s shows its image" % id)
		assert_eq(thumb.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "pixel art must never be smoothed")
	for s in sizes:
		assert_eq(s, sizes[0], "every boss card shares one thumbnail box size")

func test_the_list_has_every_boss_in_one_scrolling_column() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	assert_eq(grid.columns, 1, "the boss list is a single column")
	assert_eq(grid.get_child_count(), RBMCreatorAppearanceCatalog.all().size())
	assert_true(grid.get_parent() is ScrollContainer, "the list scrolls when bosses are added")
	assert_eq((grid.get_parent() as ScrollContainer).horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)

func test_picker_root_expands_to_fill_available_vertical_space() -> void:
	var picker := _new_picker()
	assert_eq(picker.size_flags_vertical, Control.SIZE_EXPAND_FILL)

func test_boss_name_labels_are_present_and_readable() -> void:
	var picker := _new_picker()
	var label: Label = _find(picker, "AppearanceName_appearance_dragon")
	assert_not_null(label)
	assert_eq(label.text, tr("竜"))

# ---------------------------------------------------------------------------
# 選ぶ（カード）と決める（このボスにする）
# ---------------------------------------------------------------------------

func test_clicking_a_card_selects_it_and_shows_its_profile_without_confirming() -> void:
	var picker := _new_picker()
	var confirmed_ids: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.open("appearance_slime")
	_find(picker, "Appearance_appearance_dragon").pressed.emit()
	assert_true(confirmed_ids.is_empty(), "a card only selects; the decision is the confirm button")
	assert_eq(picker.selected_appearance_id(), "appearance_dragon")
	assert_true((_find(picker, "Appearance_appearance_dragon") as Button).button_pressed)
	assert_false((_find(picker, "Appearance_appearance_slime") as Button).button_pressed, "single selection highlight")
	assert_eq((_find(picker, "ProfileBossName") as Label).text, tr("竜"))
	assert_not_null((_find(picker, "ProfileBossSprite") as TextureRect).texture)

func test_the_confirm_button_confirms_the_selected_boss_only() -> void:
	var picker := _new_picker()
	var confirmed_ids: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.open("appearance_slime")
	_find(picker, "Appearance_appearance_knight").pressed.emit()
	(_find(picker, "ConfirmAppearanceButton") as Button).pressed.emit()
	assert_eq(confirmed_ids, ["appearance_knight"])

func test_opening_selects_the_current_boss() -> void:
	var picker := _new_picker()
	picker.open("appearance_golem")
	assert_eq(picker.selected_appearance_id(), "appearance_golem")
	assert_true((_find(picker, "Appearance_appearance_golem") as Button).button_pressed)

# ---------------------------------------------------------------------------
# 「戻る」: 選択内容を変更しない
# ---------------------------------------------------------------------------

func test_back_button_emits_cancelled_without_confirming() -> void:
	var picker := _new_picker()
	var confirmed_ids: Array = []
	var cancelled_marks: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.cancelled.connect(func(): cancelled_marks.append(true))
	picker.open("appearance_dragon")
	_find(picker, "BackButton").pressed.emit()
	assert_eq(cancelled_marks.size(), 1)
	assert_true(confirmed_ids.is_empty(), "戻るはconfirmedを一切発火してはならない")

func test_back_button_returns_to_the_boss_it_was_opened_with() -> void:
	var picker := _new_picker()
	picker.open("appearance_dragon")
	_find(picker, "Appearance_appearance_wolf").pressed.emit()
	_find(picker, "BackButton").pressed.emit()
	assert_eq(picker._selected_id, "appearance_dragon", "戻るはboss idを変更しない")

# ---------------------------------------------------------------------------
# 覚醒: 一覧の札・プロフィールの切り替え（覚醒できるボスだけ）
# ---------------------------------------------------------------------------

func test_only_awakening_bosses_show_the_badge_and_the_profile_toggle() -> void:
	var picker := _new_picker()
	var toggle: Button = _find(picker, "AwakenedPreviewToggle")
	for entry in RBMCreatorAppearanceCatalog.all():
		var id := str(entry["id"])
		picker.select(id)
		if id in AWAKENING_IDS:
			assert_not_null(_find(picker, "AwakeningCapableBadge_%s" % id))
			assert_true(toggle.visible, "%s can show its awakened form" % id)
			assert_false(toggle.disabled)
		else:
			assert_null(_find(picker, "AwakeningCapableBadge_%s" % id))
			assert_false(toggle.visible, "%s has no awakened form" % id)

func test_the_toggle_switches_the_profile_and_previews_to_awakened_and_back() -> void:
	var picker := _new_picker()
	picker.open("appearance_dragon")
	var toggle: Button = _find(picker, "AwakenedPreviewToggle")
	var sprite: TextureRect = _find(picker, "ProfileBossSprite")
	var normal_texture := sprite.texture
	assert_eq(toggle.text, tr("覚醒後を見る"))
	assert_eq((_find(picker, "PreviewTitle") as Label).text, tr("攻撃のプレビュー"))
	toggle.pressed.emit()
	assert_true(picker.is_showing_awakened("appearance_dragon"))
	assert_eq(toggle.text, tr("通常に戻す"))
	assert_ne(sprite.texture, normal_texture, "the awakened art is shown")
	assert_eq((_find(picker, "ProfileBossName") as Label).text, tr("%s（覚醒後）") % tr("竜"))
	assert_eq((_find(picker, "PreviewTitle") as Label).text, tr("覚醒後の攻撃のプレビュー"))
	var captions: Array = []
	for frame_name in ["SingleAttackPreview", "AllAttackPreview"]:
		captions.append((_find(_find(picker, frame_name), "PreviewCaption") as Label).text)
	assert_eq(captions, [tr("覚醒後の単体攻撃"), tr("覚醒後の全体攻撃")])
	toggle.pressed.emit()
	assert_false(picker.is_showing_awakened("appearance_dragon"))
	assert_eq(sprite.texture, normal_texture)

## 2026-10-29: 竜の通常の単体攻撃・全体攻撃の動画を足した（覚醒後の竜はまだ録っていないので準備中のまま）。
func test_dragon_plays_its_normal_previews_and_keeps_the_awakened_placeholder() -> void:
	var picker := _new_picker()
	picker.open("appearance_dragon")
	var expected := ["dragon_single.ogv", "dragon_all.ogv"]
	var frame_names := ["SingleAttackPreview", "AllAttackPreview"]
	for i in range(2):
		var frame := _find(picker, frame_names[i])
		assert_not_null(frame)
		assert_false((_find(frame, "PreviewPending") as Label).visible, "dragon now has its normal recordings")
		var players := frame.find_children("*", "VideoStreamPlayer", true, false)
		assert_eq(players.size(), 1)
		assert_true(str(picker._preview_videos[i].current_path).ends_with(expected[i]), str(picker._preview_videos[i].current_path))
		assert_eq(frame.find_children("*", "SubViewport", true, false).size(), 0)
	picker._on_preview_toggle_pressed("appearance_dragon")
	for i in range(2):
		var frame := _find(picker, frame_names[i])
		assert_true((_find(frame, "PreviewPending") as Label).visible, "the awakened dragon is not recorded yet")
		assert_null((frame.find_children("*", "VideoStreamPlayer", true, false)[0] as VideoStreamPlayer).stream)

func test_toggle_never_confirms_and_never_changes_the_selection() -> void:
	var picker := _new_picker()
	var confirmed_ids: Array = []
	var cancelled_marks: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.cancelled.connect(func(): cancelled_marks.append(true))
	picker.open("appearance_musha")
	(_find(picker, "AwakenedPreviewToggle") as Button).pressed.emit()
	assert_true(confirmed_ids.is_empty(), "覚醒後を見るは選択確定を一切発火してはならない")
	assert_eq(cancelled_marks.size(), 0)
	assert_eq(picker.selected_appearance_id(), "appearance_musha")
	(_find(picker, "ConfirmAppearanceButton") as Button).pressed.emit()
	assert_eq(confirmed_ids, ["appearance_musha"], "the real boss id is confirmed, not an awakened asset id")

func test_each_boss_keeps_its_own_preview_state_and_reopening_resets_all() -> void:
	var picker := _new_picker()
	picker.open("appearance_dragon")
	picker._on_preview_toggle_pressed("appearance_dragon")
	picker.select("appearance_musha")
	assert_false(picker.is_showing_awakened("appearance_musha"), "another boss is unaffected")
	assert_eq((_find(picker, "AwakenedPreviewToggle") as Button).text, tr("覚醒後を見る"))
	picker.select("appearance_dragon")
	assert_eq((_find(picker, "AwakenedPreviewToggle") as Button).text, tr("通常に戻す"))
	picker.open("appearance_dragon")
	assert_false(picker.is_showing_awakened("appearance_dragon"), "reopening the screen resets every boss to its normal preview")

# ---------------------------------------------------------------------------
# fixture経由: 覚醒対応の外見が来た場合の構造(catalog本体は不変のまま)
# ---------------------------------------------------------------------------

func test_fixture_supporting_appearance_shows_badge_and_a_disabled_toggle_without_asset() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture", "name": "Fixture", "supports_awakening": true})
	var badge: Label = _find(picker, "AwakeningCapableBadge_appearance_test_fixture")
	assert_not_null(badge, "supports_awakening=true must show the badge")
	assert_eq(badge.text, tr("覚醒あり"))
	picker.select("appearance_test_fixture")
	var toggle: Button = _find(picker, "AwakenedPreviewToggle")
	assert_true(toggle.visible)
	# supports_awakening=trueと素材の実在は別概念 -- fixture idには覚醒後アセットが無いので、クラッシュせずdisabledになる。
	assert_true(toggle.disabled, "no awakened design file exists for this id, so the toggle must be safely disabled")

func test_fixture_non_supporting_or_missing_key_shows_no_badge_and_no_toggle() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_off", "name": "FixtureOff", "supports_awakening": false})
	picker._build_card(grid, {"id": "appearance_test_fixture_missing", "name": "FixtureMissing"})
	for id in ["appearance_test_fixture_off", "appearance_test_fixture_missing"]:
		assert_null(_find(picker, "AwakeningCapableBadge_%s" % id))
		picker.select(id)
		assert_false((_find(picker, "AwakenedPreviewToggle") as Button).visible)

func test_card_contents_do_not_block_the_card_click() -> void:
	var picker := _new_picker()
	var card: Button = _find(picker, "Appearance_appearance_dragon")
	for node in card.find_children("*", "Control", true, false):
		assert_eq((node as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s must let the click reach the card" % node.name)
