extends GutTest

## RPG BOSS MAKER — ボス選択画面(RBMCreatorAppearancePicker)の
## 大型化・「覚醒可能」表示・覚醒後プレビュー切替・カードクリック即決定の
## 回帰テスト。
##
## RBMCreatorAppearanceCatalog.ENTRIESはGodotのconstとして実行時読み取り
## 専用のため、既存6体を覚醒対応へ書き換えることはできない(かつ、実際の
## ボスを勝手に覚醒対応へ設定することは今回の確定仕様として禁止されて
## いる)。「覚醒対応の外見が来た場合」の構造テストは、picker._build_card()
## へその場限りのfixture Dictionaryを直接渡すことで、正規のcatalogに
## 一切触れずに検証する——実在の6つのidとは衝突しない専用のfixture id
## ("appearance_test_fixture")だけを使う。

func after_each() -> void:
	await get_tree().process_frame

func _new_picker() -> RBMCreatorAppearancePicker:
	var picker := RBMCreatorAppearancePicker.new()
	add_child_autofree(picker)
	return picker

func _find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)

# ---------------------------------------------------------------------------
# 大型化・Pixel Art品質・レイアウト
# ---------------------------------------------------------------------------

func test_preview_area_is_larger_than_the_old_48px_and_swatch_uses_nearest_filter() -> void:
	var picker := _new_picker()
	var preview_area: Control = _find(picker, "AppearancePreviewArea_appearance_dragon")
	assert_not_null(preview_area)
	assert_true(preview_area.custom_minimum_size.x > 48.0, "must be visibly larger than the old 48x48 icon size")
	assert_true(preview_area.custom_minimum_size.y > 48.0)
	var swatch: TextureRect = _find(picker, "AppearancePreview_appearance_dragon")
	assert_not_null(swatch)
	assert_eq(swatch.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "pixel art must never be smoothed/interpolated")
	assert_eq(swatch.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)

func test_all_six_cards_share_the_identical_preview_box_size() -> void:
	var picker := _new_picker()
	var sizes: Array = []
	for entry in RBMCreatorAppearanceCatalog.all():
		var area: Control = _find(picker, "AppearancePreviewArea_%s" % str(entry["id"]))
		assert_not_null(area)
		sizes.append(area.custom_minimum_size)
	for s in sizes:
		assert_eq(s, sizes[0], "every boss card must share one preview box size regardless of the underlying art's own dimensions")

func test_grid_is_still_three_columns_with_all_six_bosses_present() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	assert_eq(grid.columns, 3)
	assert_eq(grid.get_child_count(), 6)

## 画面再設計(2回目の改修)§1-2: この画面自身がroot_columnの中で実際の
## 表示領域を確保できるよう、size_flags_vertical=EXPAND_FILLを明示している
## ことを確認する——これが無いと(旧実装のバグ)、画面左上に小さくまとまって
## しまう。
func test_picker_root_expands_to_fill_available_vertical_space() -> void:
	var picker := _new_picker()
	assert_eq(picker.size_flags_vertical, Control.SIZE_EXPAND_FILL)

func test_cards_are_notably_larger_than_the_previous_iteration() -> void:
	var picker := _new_picker()
	var card: Button = _find(picker, "Appearance_appearance_dragon")
	assert_not_null(card)
	# 前回改修(200x96の画像枠)よりもカード自体が明確に大きいこと。
	assert_true(card.custom_minimum_size.x >= 300.0)
	assert_true(card.custom_minimum_size.y >= 200.0)

# ---------------------------------------------------------------------------
# カード全体クリック即決定・「決定」ボタン廃止
# ---------------------------------------------------------------------------

func test_decide_button_no_longer_exists() -> void:
	var picker := _new_picker()
	assert_null(_find(picker, "DecideButton"), "二段階確認(決定ボタン)は廃止された仕様")

func test_clicking_a_card_immediately_confirms_that_boss_and_no_other() -> void:
	var picker := _new_picker()
	var confirmed_ids: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.open("")
	_find(picker, "Appearance_appearance_dragon").pressed.emit()
	assert_eq(confirmed_ids, ["appearance_dragon"], "pressing a card must immediately confirm that boss id")

func test_clicking_a_different_card_confirms_the_newly_clicked_boss() -> void:
	var picker := _new_picker()
	var confirmed_ids: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.open("appearance_slime")
	_find(picker, "Appearance_appearance_knight").pressed.emit()
	assert_eq(confirmed_ids, ["appearance_knight"])

func test_boss_name_labels_are_still_present_and_readable() -> void:
	var picker := _new_picker()
	var label: Label = _find(picker, "AppearanceName_appearance_dragon")
	assert_not_null(label)
	assert_eq(label.text, tr("竜"))

# ---------------------------------------------------------------------------
# 「戻る」: 選択内容を変更しない
# ---------------------------------------------------------------------------

func test_back_button_still_exists_and_emits_cancelled_without_confirming() -> void:
	var picker := _new_picker()
	var confirmed_ids: Array = []
	# int等の値型はラムダに値コピーで捕捉されるため、外側から観測できる
	# よう配列(参照型)へappendするカウント方法を使う。
	var cancelled_marks: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.cancelled.connect(func(): cancelled_marks.append(true))
	picker.open("appearance_dragon")
	_find(picker, "BackButton").pressed.emit()
	assert_eq(cancelled_marks.size(), 1)
	assert_true(confirmed_ids.is_empty(), "戻るはconfirmedを一切発火してはならない")

func test_back_button_does_not_change_the_currently_selected_boss() -> void:
	var picker := _new_picker()
	picker.open("appearance_dragon")
	_find(picker, "BackButton").pressed.emit()
	assert_eq(picker._selected_id, "appearance_dragon", "戻るはboss idを変更しない")

# ---------------------------------------------------------------------------
# 「覚醒可能」表示・プレビュー切替: 実データ(全6体が非対応)
# ---------------------------------------------------------------------------

func test_no_real_appearance_shows_the_awakening_badge_or_toggle_yet() -> void:
	var picker := _new_picker()
	for entry in RBMCreatorAppearanceCatalog.all():
		var id := str(entry["id"])
		assert_null(_find(picker, "AwakeningCapableBadge_%s" % id), "%s must not show 「覚醒可能」 -- no appearance is awakening-capable yet" % id)
		assert_null(_find(picker, "AwakenedPreviewToggle_%s" % id), "%s must not show the preview toggle either" % id)

# ---------------------------------------------------------------------------
# fixture経由: 覚醒対応の外見が来た場合の構造(catalog本体は不変のまま)
# ---------------------------------------------------------------------------

func test_fixture_supporting_appearance_shows_badge_and_toggle_disabled_without_asset() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture", "name": "Fixture", "supports_awakening": true})
	var badge: Label = _find(picker, "AwakeningCapableBadge_appearance_test_fixture")
	assert_not_null(badge, "supports_awakening=true must show the badge")
	assert_eq(badge.text, tr("覚醒可能"))
	var toggle: Button = _find(picker, "AwakenedPreviewToggle_appearance_test_fixture")
	assert_not_null(toggle, "supports_awakening=true must show the preview toggle button")
	# supports_awakening=trueと素材の実在は別概念(§3確定) -- fixture idには
	# 実際の覚醒後アセットが存在しないため、クラッシュせずdisabledになる。
	assert_true(toggle.disabled, "no awakened design file exists for this id, so the toggle must be safely disabled")

func test_fixture_non_supporting_appearance_shows_neither_badge_nor_toggle() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_off", "name": "FixtureOff", "supports_awakening": false})
	assert_null(_find(picker, "AwakeningCapableBadge_appearance_test_fixture_off"))
	assert_null(_find(picker, "AwakenedPreviewToggle_appearance_test_fixture_off"))

func test_fixture_missing_supports_awakening_key_defaults_to_no_badge_no_toggle() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_missing", "name": "FixtureMissing"})
	assert_null(_find(picker, "AwakeningCapableBadge_appearance_test_fixture_missing"))
	assert_null(_find(picker, "AwakenedPreviewToggle_appearance_test_fixture_missing"))

## 覚醒対応カードでは、画像・名前・バッジ・切替ボタンのいずれも互いに
## 重ならない専用スペースを持つ——badge/toggleは画像の「下」の専用行
## (overlay_row)に置かれ、名前ラベルはさらにその下にある(前回のGPU検証で
## 発見した文字重なりバグの再発防止、§10確定)。
func test_fixture_supporting_card_keeps_image_name_badge_and_toggle_in_separate_rows() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_layout", "name": "FixtureLayout", "supports_awakening": true})
	var preview_area: Control = _find(picker, "AppearancePreviewArea_appearance_test_fixture_layout")
	var overlay_row: Control = _find(picker, "AwakeningOverlayRow_appearance_test_fixture_layout")
	var name_label: Control = _find(picker, "AppearanceName_appearance_test_fixture_layout")
	assert_not_null(preview_area)
	assert_not_null(overlay_row)
	assert_not_null(name_label)
	# 3つとも同じ親(content VBoxContainer)の直接の子として縦に並んでおり、
	# 兄弟インデックスの順序が画像→バッジ/ボタン行→名前になっていることを
	# 確認する(重なりようがない構造であることの間接的な検証)。
	var parent := preview_area.get_parent()
	assert_eq(overlay_row.get_parent(), parent)
	assert_eq(name_label.get_parent(), parent)
	assert_true(preview_area.get_index() < overlay_row.get_index())
	assert_true(overlay_row.get_index() < name_label.get_index())

# ---------------------------------------------------------------------------
# 覚醒後を見るボタン: 選択確定とは無関係、画面遷移も起こさない
# ---------------------------------------------------------------------------

func test_pressing_the_awakened_preview_toggle_does_not_confirm_or_leave_the_screen() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_e", "name": "E", "supports_awakening": true})
	var confirmed_ids: Array = []
	var cancelled_marks: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.cancelled.connect(func(): cancelled_marks.append(true))
	var toggle: Button = _find(picker, "AwakenedPreviewToggle_appearance_test_fixture_e")
	toggle.pressed.emit()
	assert_true(confirmed_ids.is_empty(), "覚醒後を見るは選択確定を一切発火してはならない")
	assert_eq(cancelled_marks.size(), 0)
	assert_true(is_instance_valid(picker), "覚醒後を見るを押しても画面(picker)自体は生き続ける")

func test_toggle_flips_button_text_and_never_affects_an_unrelated_card() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_a", "name": "A", "supports_awakening": true})
	picker._build_card(grid, {"id": "appearance_test_fixture_b", "name": "B", "supports_awakening": true})
	var toggle_a: Button = _find(picker, "AwakenedPreviewToggle_appearance_test_fixture_a")
	var toggle_b: Button = _find(picker, "AwakenedPreviewToggle_appearance_test_fixture_b")
	assert_eq(toggle_a.text, tr("覚醒後を見る"))
	picker._on_preview_toggle_pressed("appearance_test_fixture_a")
	assert_eq(toggle_a.text, tr("通常時を見る"), "card A must flip to the awakened-preview label")
	assert_eq(toggle_b.text, tr("覚醒後を見る"), "card B must be completely unaffected by card A's toggle")
	picker._on_preview_toggle_pressed("appearance_test_fixture_a")
	assert_eq(toggle_a.text, tr("覚醒後を見る"), "pressing again returns card A to the normal-preview label")

func test_toggling_preview_never_changes_selection_and_card_click_still_confirms_the_real_boss_id() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_c", "name": "C", "supports_awakening": true})
	picker.open("appearance_dragon")
	var toggle: Button = _find(picker, "AwakenedPreviewToggle_appearance_test_fixture_c")
	toggle.pressed.emit()
	assert_eq(picker._selected_id, "appearance_dragon", "toggling an unrelated card's preview must not change the current selection")
	var confirmed_ids: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	_find(picker, "Appearance_appearance_dragon").pressed.emit()
	assert_eq(confirmed_ids, ["appearance_dragon"], "confirming must still report the originally selected boss id, unaffected by any preview toggling")

func test_reopening_the_screen_resets_every_card_to_the_normal_preview() -> void:
	var picker := _new_picker()
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	picker._build_card(grid, {"id": "appearance_test_fixture_d", "name": "D", "supports_awakening": true})
	picker._on_preview_toggle_pressed("appearance_test_fixture_d")
	var toggle: Button = _find(picker, "AwakenedPreviewToggle_appearance_test_fixture_d")
	assert_eq(toggle.text, tr("通常時を見る"), "sanity: the fixture card is now showing the awakened preview")
	picker.open("appearance_dragon")
	assert_eq(toggle.text, tr("覚醒後を見る"), "reopening the screen must reset every card back to its normal-preview label")
	assert_false(bool(picker._preview_awakened.get("appearance_test_fixture_d", true)))
