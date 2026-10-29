extends GutTest

## RPG BOSS MAKER — Creator UI再設計 §10（実装指示書 §12〜§15）:
## STEP1（基本設定）/STEP2（能力）/新STEP4（攻略パーティ）/新STEP5（使用可能
## スキル）のカードUI化。
##
## 「入力フォームを常時見せる」のではなく「現在の完成状態をカードで見せ、
## 必要な時だけ編集する」——4画面とも、①通常表示はカードの要約のみ
## ②「編集」を押した時だけ入力コントロールを展開③決定でDraftへ反映④
## キャンセルで編集開始時点の値を維持、という共通パターンを実UIの実信号
## 経路（ボタン.pressed.emit()、テスト専用の直接API呼び出しではない）で
## 検証する。機能・保存形式・Battle仕様は一切変更していない——変更対象は
## Creator STEP1/2/4/5のUI構造のみ。
##
## test_rbm_realplay1/2/3_ui_polish.gdと同じ既存の確立済み手法（実際に
## RBMGameRootをインスタンス化し、Godot自身のレイアウト計算・実シグナル
## 経路を経た本物のControl.text/value/visibleだけを検証する）を踏襲する。
const TEST_DIR := "user://bossmaker_test_step10_card_ui/stages"
const HEADLESS_WINDOW_SIZE := Vector2(1280, 720)

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await get_tree().process_frame

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

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _label(node: Node, label_name: String) -> Label:
	var found := node.find_child(label_name, true, false) as Label
	assert_not_null(found, "expected a real Label node named %s under %s" % [label_name, node])
	return found

func _all_label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for found in node.find_children("*", "Label", true, false):
		texts.append((found as Label).text)
	return texts

func _number_after_colon(text: String) -> int:
	return text.get_slice("：", 1).to_int()

func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(HEADLESS_WINDOW_SIZE.x, HEADLESS_WINDOW_SIZE.y)
	var root := RBMGameRoot.new()
	add_child_autoqfree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

func _new_creator_main() -> RBMCreatorMain:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	return root.creator_entry.main

# =============================================================================
# §12 STEP1 基本設定 — 必須UIテスト
# =============================================================================

func test_step1_initial_card_display_shows_placeholder_when_name_is_empty() -> void:
	var main := await _new_creator_main()
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	assert_true(step1._name_normal_row.visible, "sanity: normal display must be showing on a fresh screen")
	assert_false(step1._name_edit_row.visible, "the input row must not be shown until 編集 is pressed")
	assert_eq(step1._name_display_label.text, "まだ設定されていません")
	assert_eq(step1._edit_name_button.text, "名前を決める")

func test_step1_edit_name_button_opens_the_input_row() -> void:
	var main := await _new_creator_main()
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	_btn(step1, "EditNameButton").pressed.emit()
	await get_tree().process_frame
	assert_true(step1._name_edit_row.visible, "入力欄はEditNameButtonを押した時だけ展開される")
	assert_false(step1._name_normal_row.visible)

func test_step1_confirm_name_commits_to_draft_and_returns_to_card_display() -> void:
	var main := await _new_creator_main()
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	_btn(step1, "EditNameButton").pressed.emit()
	await get_tree().process_frame
	step1._name_edit.text = "黒炎竜ヴァルガス"
	_btn(step1, "ConfirmNameButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(main.draft.boss_name, "黒炎竜ヴァルガス", "決定でDraftへ反映されること")
	assert_false(step1._name_edit_row.visible, "決定後は通常表示へ戻ること")
	assert_true(step1._name_normal_row.visible)
	assert_eq(step1._name_display_label.text, "黒炎竜ヴァルガス")
	assert_eq(step1._edit_name_button.text, "編集")

func test_step1_cancel_name_edit_discards_the_typed_text() -> void:
	var main := await _new_creator_main()
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	step1.set_boss_name("初期名")
	_btn(step1, "EditNameButton").pressed.emit()
	await get_tree().process_frame
	step1._name_edit.text = "書き換え中の名前"
	_btn(step1, "CancelNameButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(main.draft.boss_name, "初期名", "キャンセルでDraftは変更されないこと")
	assert_eq(step1._name_display_label.text, "初期名", "カード表示も元の値のままであること")
	assert_false(step1._name_edit_row.visible)

func test_step1_appearance_card_reflects_the_current_selection() -> void:
	var main := await _new_creator_main()
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	assert_not_null(step1._appearance_preview_aspect, "将来のTextureRectを収めるAspectRatioContainerが存在すること")
	assert_not_null(step1._appearance_preview_surface, "プレビュー内容を差し替えるためのsurfaceが存在すること")
	assert_true(step1._appearance_preview_swatch.get_parent() == step1._appearance_preview_surface)
	assert_true(step1._appearance_preview_surface.get_parent() == step1._appearance_preview_aspect)
	assert_true(step1._appearance_preview_aspect.custom_minimum_size.y >= 240.0, "横長の細い帯ではなく、立ち絵を表示できる十分な高さを確保すること")
	assert_eq(step1._appearance_preview_label.text, "（未選択）", "sanity: starts unselected")
	var aspect_before := step1._appearance_preview_aspect
	var surface_before := step1._appearance_preview_surface

	main.open_appearance_picker()
	await get_tree().process_frame
	main._appearance_picker.confirmed.emit("appearance_dragon")
	await get_tree().process_frame
	assert_eq(main.draft.appearance_id, "appearance_dragon")
	# 2026-10-18: 名前は「現在の外見：」の次の行（PX-22。名前の途中で折り返さないように）
	assert_eq(step1._appearance_preview_label.text, "現在の外見：%s" % ("\n" + RBMCreatorAppearanceCatalog.display_name("appearance_dragon")), "選択結果がカードへ反映されること")
	assert_true(step1._appearance_preview_aspect == aspect_before, "外見変更後もプレビュー領域のAspect構造を作り直さないこと")
	assert_true(step1._appearance_preview_surface == surface_before, "外見変更後も将来の画像差し替え先surfaceを維持すること")
	assert_not_null(step1._appearance_preview_swatch.texture, "Selected appearance has real sprite artwork")
	assert_eq(step1._appearance_preview_swatch.texture.resource_path, RBMVisualAssets.frame_path("dragon", 0))

func test_step1_appearance_change_button_opens_the_existing_picker() -> void:
	var main := await _new_creator_main()
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	assert_eq(step1._appearance_button.text, "外見を変更")
	_btn(step1, "AppearanceButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._appearance_picker.visible, "「変更」を押した時だけ既存の外見候補選択UIを開く")
	assert_false(main._steps_root.visible)
	main._appearance_picker.cancelled.emit()
	await get_tree().process_frame
	assert_true(main._steps_root.visible, "キャンセルでカード表示（STEP画面）へ戻ること")

# =============================================================================
# §13 STEP2 能力 — 必須UIテスト
# =============================================================================

func test_step2_current_stats_are_shown_in_the_editor() -> void:
	var main := await _new_creator_main()
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	step2.set_hp(5000)
	step2.set_atk(180)
	step2.set_spd(120)
	step2.toggle_weak("FIRE")
	step2.toggle_resist("ICE")
	assert_true(step2._hp_spin.value == 5000.0)
	assert_true(step2._atk_spin.value == 180.0)
	assert_true(step2._spd_spin.value == 120.0)
	assert_true(step2._weak_buttons["FIRE"].button_pressed)
	assert_true(step2._resist_buttons["ICE"].button_pressed)

func test_step2_unset_attributes_are_unselected_in_editor() -> void:
	var main := await _new_creator_main()
	main.go_to_step(2)
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	for attr in RBMDefinitionLoader.VALID_ATTRIBUTES:
		assert_false(step2._weak_buttons[attr].button_pressed)
		assert_false(step2._resist_buttons[attr].button_pressed)

func test_step2_stat_controls_are_available_without_edit_button() -> void:
	var main := await _new_creator_main()
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	assert_null(step2.find_child("EditStatsButton", true, false))
	await get_tree().process_frame
	assert_true(step2._edit_panel.visible, "最初からSlider/SpinBox/属性ボタンが展開される")
	assert_null(step2.find_child("StatsNormalDisplay", true, false))

func test_step2_hp_atk_spd_and_attributes_apply_without_confirm() -> void:
	var main := await _new_creator_main()
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	assert_null(step2.find_child("EditStatsButton", true, false))
	await get_tree().process_frame

	step2._hp_spin.value = 3000
	step2._atk_spin.value = 150
	step2._spd_spin.value = 80
	_btn(step2, "Weak_FIRE").pressed.emit()
	_btn(step2, "Resist_ICE").pressed.emit()
	await get_tree().process_frame
	# 変更時にDraftへ反映されること。
	assert_eq(main.draft.hp, 3000, "入力直後に反映")

	assert_null(step2.find_child("ConfirmStatsButton", true, false))
	await get_tree().process_frame
	assert_eq(main.draft.hp, 3000)
	assert_eq(main.draft.atk, 150)
	assert_eq(main.draft.spd, 80)
	assert_true(main.draft.weak_attributes.has("FIRE"))
	assert_true(main.draft.resist_attributes.has("ICE"))
	assert_true(step2._edit_panel.visible, "変更後も編集を継続できる")

func test_step2_navigation_retains_all_immediate_changes() -> void:
	var main := await _new_creator_main()
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	step2.set_hp(999)
	step2.set_atk(88)
	step2.set_spd(11)
	step2.toggle_weak("WIND")

	assert_null(step2.find_child("EditStatsButton", true, false))
	await get_tree().process_frame
	step2._hp_spin.value = 88888
	step2._atk_spin.value = 1
	step2._spd_spin.value = 1
	_btn(step2, "Weak_WIND").pressed.emit()  # un-toggle it while editing
	_btn(step2, "Resist_LIGHTNING").pressed.emit()
	await get_tree().process_frame

	main.go_to_step(3)
	main.go_to_step(2)
	await get_tree().process_frame
	assert_eq(main.draft.hp, 88888, "工程を離れて戻っても即時反映値を保持")
	assert_eq(main.draft.atk, 1)
	assert_eq(main.draft.spd, 1)
	assert_false(main.draft.weak_attributes.has("WIND"))
	assert_true(main.draft.resist_attributes.has("LIGHTNING"))

# =============================================================================
# §14 新STEP4 攻略パーティ — 必須UIテスト
# =============================================================================

## STEP4 UI 刷新（2026-10-17、ユーザーが案C を採用）: 上に編成（戦場に並ぶ最大4人）、中に5人の仲間の札
## （SelectCharacterButton_%s）、下に人物の札（AddCharacterButton「編成に入れる」／RemoveCharacterButton_%s
## 「編成から外す」／StatusEditButton「ステータス編集」）。以前の「＋キャラクターを追加 → 候補を選んで決定」の
## 流れは無くなり、仲間の札で選んで「編成に入れる」でその場で入る。編成の仕様（1〜4人・重複なし）は変えていない。
func test_step4_only_party_members_stand_in_the_formation_and_all_five_are_on_the_bench() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	step4.toggle_character("butler")
	await get_tree().process_frame
	assert_not_null(step4.find_child("FormationSprite_0", true, false), "1人目が編成に並ぶこと")
	assert_not_null(step4.find_child("FormationSprite_1", true, false), "2人目が編成に並ぶこと")
	assert_null(step4.find_child("FormationSprite_2", true, false), "編成に入っていない枠には誰も立たないこと")
	assert_not_null(step4.find_child("EmptySlot_2", true, false), "空きの枠を示すこと")
	for id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		var tile := _btn(step4, "SelectCharacterButton_%s" % id)
		assert_eq(tile.find_child("InPartyTag", true, false) != null, main.draft.party_character_ids.has(id), "%s: 編成中の印は編成に入っている人だけ" % id)
	assert_eq(_label(step4, "PartyCountLabel").text, "2 / 4人")

func test_step4_bench_tile_shows_that_character_in_the_sheet_without_changing_the_draft() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	await get_tree().process_frame
	var before := main.draft.full_authoring_snapshot()
	_btn(step4, "SelectCharacterButton_butler").pressed.emit()
	await get_tree().process_frame
	assert_eq(_label(step4, "SheetName").text, "老執事")
	assert_true(_btn(step4, "AddCharacterButton").is_visible_in_tree(), "編成に入っていない人は「編成に入れる」が出ること")
	assert_true(_btn(step4, "StatusEditButton").disabled, "編成に入っていない人のステータス編集は押せないこと")
	assert_eq(main.draft.full_authoring_snapshot(), before, "選んで眺めるだけでDraftを変更しないこと")

func test_step4_add_button_adds_the_shown_character_right_away() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	_btn(step4, "SelectCharacterButton_hero").pressed.emit()
	await get_tree().process_frame
	assert_eq(_btn(step4, "AddCharacterButton").text, "編成に入れる")
	_btn(step4, "AddCharacterButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(main.draft.party_character_ids, ["hero"], "「編成に入れる」でその場でDraftへ入ること")
	assert_null(step4.find_child("AddCharacterButton", true, false), "入った人には「編成に入れる」を出さないこと")
	assert_not_null(step4.find_child("RemoveCharacterButton_hero", true, false), "入った人には「編成から外す」が出ること")
	assert_false(_btn(step4, "StatusEditButton").disabled, "入った人はステータス編集を押せること")
	assert_not_null(step4.find_child("FormationSprite_0", true, false), "編成に並ぶこと")

func test_step4_party_cap_blocks_a_fifth_member_and_says_why() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	for id in ["hero", "butler", "healer", "samurai"]:
		_btn(step4, "SelectCharacterButton_%s" % id).pressed.emit()
		_btn(step4, "AddCharacterButton").pressed.emit()
		await get_tree().process_frame
	assert_eq(main.draft.party_character_ids.size(), RBMDefinitionLoader.MAX_PARTY_SIZE)
	_btn(step4, "SelectCharacterButton_tank").pressed.emit()
	await get_tree().process_frame
	var add := _btn(step4, "AddCharacterButton")
	assert_true(add.disabled, "4人そろったら5人目は入れられないこと")
	assert_eq(add.text, "4人そろっています", "押せない理由を文字で示すこと")
	add.pressed.emit()
	await get_tree().process_frame
	assert_false(main.draft.party_character_ids.has("tank"), "押せない状態で信号が来ても入らないこと（防御的ガード）")
	assert_eq(main.draft.party_character_ids.count("hero"), 1, "重複しないこと")

func test_step4_party_built_in_the_ui_round_trips_through_real_save_and_load() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	main.draft.boss_name = "編成保存テスト"
	main.draft.hp = 100
	main.draft.atk = 10
	main.draft.spd = 10
	for id in ["hero", "butler"]:
		_btn(step4, "SelectCharacterButton_%s" % id).pressed.emit()
		_btn(step4, "AddCharacterButton").pressed.emit()
		await get_tree().process_frame
	var save_result := main.press_save_as_new()
	assert_true(bool(save_result.get("ok", false)), "画面で編成したDraftを実ファイル保存できること")
	var loaded := RBMLocalStageRepository.load_stage(str(save_result.get("stage_id", "")))
	assert_true(bool(loaded.get("ok", false)), "保存した実ファイルを読込できること")
	var loaded_draft := RBMCreatorDraft.new()
	loaded_draft.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(loaded_draft.party_character_ids, ["hero", "butler"], "保存→読込後も編成した順のparty_character_idsを維持すること")

func test_step4_remove_button_removes_from_party() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	await get_tree().process_frame
	_btn(step4, "SelectCharacterButton_hero").pressed.emit()
	await get_tree().process_frame
	assert_eq(_btn(step4, "RemoveCharacterButton_hero").text, "編成から外す")
	_btn(step4, "RemoveCharacterButton_hero").pressed.emit()
	await get_tree().process_frame
	assert_false(main.draft.party_character_ids.has("hero"), "「編成から外す」でDraftへ反映されること")
	assert_null(step4.find_child("FormationSprite_0", true, false), "編成から消えること")
	assert_not_null(step4.find_child("AddCharacterButton", true, false), "外した人には「編成に入れる」が戻ること")

func test_step4_a_character_cannot_appear_twice_in_the_party() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	await get_tree().process_frame
	var before_count := main.draft.party_character_ids.size()
	main.draft.add_party_character("hero")  # attempt a duplicate add directly on the draft
	assert_eq(main.draft.party_character_ids.size(), before_count, "重複しないこと（既存のadd_party_character()自身の重複禁止仕様のまま）")
	assert_eq(main.draft.party_character_ids.count("hero"), 1)

## 人物の札は、マスターデータ（HARDCOREの調整後の値）から役割・属性・能力・得意技を出す。
func test_step4_character_sheet_shows_role_attribute_stats_and_signature_from_real_data() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	var expected := {"hero": ["攻撃役", "炎", "炎纏い"], "butler": ["魔法攻撃役", "氷", "氷属性大魔法"], "healer": ["回復役", "雷", "全体HP回復"], "samurai": ["攻撃役", "風", "カウンター"], "tank": ["防御役", "無", "かばう"]}
	for id in expected:
		_btn(step4, "SelectCharacterButton_%s" % id).pressed.emit()
		await get_tree().process_frame
		var sheet := step4.find_child("CharacterSheet", true, false) as Control
		var texts := _all_label_texts(sheet)
		assert_true(texts.any(func(t: String): return t.begins_with(str(expected[id][0]))), "%s: 役割 %s を出すこと" % [id, expected[id][0]])
		assert_true(texts.has(str(expected[id][1])), "%s: 属性 %s を出すこと" % [id, expected[id][1]])
		assert_eq(_label(sheet, "SignatureName").text, str(expected[id][2]), "%s: 得意技" % id)
		var master := main.draft.master_character_def(id)
		for key in ["hp", "atk", "spd", "max_sp"]:
			assert_eq(_label(sheet, "SheetStat_%s" % key).text, str(int(master.get(key, 0))), "%s: %s はマスターデータの値" % [id, key])

## ステータス編集を開く・閉じる。編成に入っていない人では開かない。
func test_step4_status_edit_opens_over_the_formation_and_closes() -> void:
	var main := await _new_creator_main()
	main.go_to_step(main.party_step())
	await get_tree().process_frame
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	await get_tree().process_frame
	_btn(step4, "SelectCharacterButton_butler").pressed.emit()
	step4.open_status_sheet()
	await get_tree().process_frame
	assert_false(step4.is_status_sheet_open(), "編成に入っていない人のステータス編集は開かないこと")
	_btn(step4, "SelectCharacterButton_hero").pressed.emit()
	_btn(step4, "StatusEditButton").pressed.emit()
	await get_tree().process_frame
	assert_true(step4.is_status_sheet_open(), "「ステータス編集」で開くこと")
	assert_true(_btn(step4, "SkillsTabButton").is_visible_in_tree())
	assert_true(_btn(step4, "PerformanceTabButton").is_visible_in_tree())
	_btn(step4, "StatusEditCloseButton").pressed.emit()
	await get_tree().process_frame
	assert_false(step4.is_status_sheet_open(), "「閉じる」で閉じること")

## STEP4 の画面は別のボスを作る・開く時も使い回す（draft の中身だけが入れ替わる）。STEP4 を開いた時は、
## 編成に入っていない人ではなく編成の1人目を見せ、前に開いたままのステータス編集は閉じておく。
func test_step4_opens_on_the_first_party_member_with_the_status_edit_closed() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	# 画面を作った後で編成が入る（保存したボスを開いた時と同じ順）
	main.draft.add_party_character("healer")
	main.draft.add_party_character("tank")
	main.go_to_step(4)
	await get_tree().process_frame
	assert_eq(step4.selected_character_id(), "healer", "編成の1人目を見せること")
	assert_eq(_label(step4, "SheetName").text, "少女")
	# 編成の人を選んでステータス編集を開いたまま、ほかの STEP へ行って戻る
	_btn(step4, "FormationSlot_1").pressed.emit()
	await get_tree().process_frame
	_btn(step4, "StatusEditButton").pressed.emit()
	await get_tree().process_frame
	assert_true(step4.is_status_sheet_open())
	main.go_to_step(3)
	await get_tree().process_frame
	main.go_to_step(4)
	await get_tree().process_frame
	assert_false(step4.is_status_sheet_open(), "STEP4 に戻った時はステータス編集を閉じておくこと")
	assert_eq(step4.selected_character_id(), "tank", "編成の中で選んでいた人はそのまま")
	# 編成に入っていない人を眺めたまま離れ、別のボス（編成の違う下書き）を開いた時
	_btn(step4, "SelectCharacterButton_butler").pressed.emit()
	await get_tree().process_frame
	main.go_to_step(3)
	await get_tree().process_frame
	main.draft.remove_party_character("healer")
	main.draft.remove_party_character("tank")
	main.draft.add_party_character("samurai")
	main.go_to_step(4)
	await get_tree().process_frame
	assert_eq(step4.selected_character_id(), "samurai", "編成に入っていない人を見ていた時は編成の1人目に戻すこと")
	assert_eq(main.draft.party_character_ids, ["samurai"], "見る人を変えるだけで編成は変えないこと")

## Creator UI改修（STEP4統合、2026-09-05）: 旧「性能を見る」ボタン
## （ViewPerformanceButton_%s、全画面差し替えの_info_panel）は廃止され、
## カード自体をクリックして選択→下部「選択キャラクター設定」の[性能調整]
## タブへ切り替える方式になった（PerformanceTabButton、常時表示の
## SelectedCharacterTabContent）。
func test_step4_selected_card_opens_read_only_performance_from_real_master_data() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	await get_tree().process_frame
	assert_null(step4.find_child("ViewPerformanceButton_hero", true, false), "旧「性能を見る」ボタンは廃止されていること")
	_btn(step4, "SelectCharacterButton_hero").pressed.emit()
	await get_tree().process_frame
	_btn(step4, "StatusEditButton").pressed.emit()
	_btn(step4, "PerformanceTabButton").pressed.emit()
	await get_tree().process_frame

	var master := main.draft.master_character_def("hero")
	assert_true(step4.is_status_sheet_open(), "「ステータス編集」で開くこと（2026-10-17 案C）")
	assert_eq(step4._selected_header_label.text, "ステータス編集　勇者")
	assert_eq(_label(step4._tab_content, "CharacterInfoStatsLabel").text, "HP：%d\nATK：%d\nSPD：%d" % [int(master.get("hp", 0)), int(master.get("atk", 0)), int(master.get("spd", 0))])
	assert_false(_all_label_texts(step4._tab_content).any(func(text: String): return text.contains("DEF")), "存在しないDEFを表示しないこと")
	assert_eq(step4._tab_content.find_children("CharacterSkillCard_*", "", true, false).size(), (master.get("skills", []) as Array).size(), "マスターが持つ全スキルだけを表示すること")

	for skill_variant in master.get("skills", []):
		var skill: Dictionary = skill_variant
		var skill_id := str(skill.get("id", ""))
		assert_eq(_label(step4, "SkillNameLabel_%s" % skill_id).text, str(skill.get("display_name", "")))
		assert_not_null(step4.find_child("SkillTypeLabel_%s" % skill_id, true, false), "実在するeffectを人間向け種類として表示すること")
		var attribute_label := step4.find_child("SkillAttributeLabel_%s" % skill_id, true, false) as Label
		if skill.has("attribute"):
			var attribute_id := str(skill.get("attribute", ""))
			assert_eq(attribute_label.text, "属性：%s" % str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)))
		else:
			assert_null(attribute_label, "マスターに属性がないスキルへ属性を発明しないこと")
		var target_label := step4.find_child("SkillTargetLabel_%s" % skill_id, true, false) as Label
		if skill.has("target"):
			assert_not_null(target_label)
		else:
			assert_null(target_label, "マスターにtargetがないスキルへ対象を発明しないこと")

	assert_true(step4._tab_content.find_children("*", "LineEdit", true, false).is_empty())
	assert_true(step4._tab_content.find_children("*", "SpinBox", true, false).is_empty())
	assert_true(step4._tab_content.find_children("*", "CheckBox", true, false).is_empty(), "性能詳細は完全な読み取り専用であること")

func test_step4_attack_base_damage_display_matches_real_neutral_unbuffed_battle_log() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	await get_tree().process_frame
	_btn(step4, "SelectCharacterButton_hero").pressed.emit()
	_btn(step4, "PerformanceTabButton").pressed.emit()
	await get_tree().process_frame
	var effect_label := _label(step4, "SkillEffectLabel_hero_slash")
	var note_label := _label(step4, "SkillEffectNoteLabel_hero_slash")
	assert_true(effect_label.text.begins_with("基礎ダメージ："))
	assert_eq(note_label.text, "属性補正・一時強化前")
	var displayed_damage := _number_after_colon(effect_label.text)

	var hero_master := main.draft.master_character_def("hero")
	var neutral_boss := {"id": "preview_probe", "display_name": "検証ボス", "hp": 100000, "atk": 1, "spd": 1, "skills": [], "normal_action_candidates": []}
	var battle := RBMBattle.new([hero_master], neutral_boss, 1)
	var result := battle._resolve_ally_skill(battle.party[0], "hero_slash", -1)
	assert_eq(displayed_damage, int(result.get("amount", -1)), "性能表示値が同じキャラ・スキルの中立/無強化実Battleログと一致すること")

func test_step4_heal_base_amount_display_matches_real_battle_when_enough_hp_is_missing() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("healer")
	await get_tree().process_frame
	_btn(step4, "SelectCharacterButton_healer").pressed.emit()
	_btn(step4, "PerformanceTabButton").pressed.emit()
	await get_tree().process_frame
	var effect_label := _label(step4, "SkillEffectLabel_healer_heal_single")
	assert_true(effect_label.text.begins_with("基本回復量："))
	assert_eq(_label(step4, "SkillEffectNoteLabel_healer_heal_single").text, "対象の不足HPまで")
	var displayed_heal := _number_after_colon(effect_label.text)

	var healer_master := main.draft.master_character_def("healer")
	var hero_master := main.draft.master_character_def("hero")
	var neutral_boss := {"id": "heal_probe", "display_name": "検証ボス", "hp": 100000, "atk": 1, "spd": 1, "skills": [], "normal_action_candidates": []}
	var battle := RBMBattle.new([healer_master, hero_master], neutral_boss, 1)
	battle.party[1].hp = 1
	var result := battle._resolve_ally_skill(battle.party[0], "healer_heal_single", battle.party[1].id)
	assert_eq(displayed_heal, int(result.get("amount", -1)), "不足HPが十分ある時の実Battle回復ログと基本回復量が一致すること")

## Creator UI改修（STEP4統合、2026-09-05）: 「性能を見る→閉じる」という
## 独立した全画面フローが無くなったため、「選択→タブ切替→別カードを選択」
## という新しい流れでも、①内容が正しいキャラクターへ切り替わる②Draft
## そのものは一切変更されない、という既存契約を確認する。
func test_step4_performance_switches_character_shows_real_effects_and_never_changes_draft() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	step4.toggle_character("hero")
	step4.toggle_character("tank")
	await get_tree().process_frame
	var authoring_before := main.draft.full_authoring_snapshot()
	var battle_before := main.draft.battle_content_snapshot()

	_btn(step4, "SelectCharacterButton_hero").pressed.emit()
	_btn(step4, "PerformanceTabButton").pressed.emit()
	await get_tree().process_frame
	assert_true(_label(step4, "SkillEffectLabel_hero_flame_wrap").text.contains("1.75倍"))
	assert_eq(_label(step4, "SkillDurationLabel_hero_flame_wrap").text, "効果時間：3ターン")

	_btn(step4, "SelectCharacterButton_tank").pressed.emit()
	await get_tree().process_frame
	assert_eq(step4._selected_header_label.text, "ステータス編集　ハンマー使い", "別の仲間を選ぶと内容が正しいキャラクターへ切り替わること")
	assert_eq(_label(step4, "SkillEffectLabel_tank_guard_swap").text, "味方単体への攻撃をかばう")
	assert_eq(_label(step4, "SkillEffectLabel_tank_guard_boost").text, "防御時の軽減率：60%")
	assert_eq(_label(step4, "SkillDurationLabel_tank_guard_boost").text, "効果時間：1ターン")
	assert_eq(_label(step4, "SkillEffectLabel_tank_iron_wall").text, "パーティの被ダメージ軽減：10%")
	assert_eq(main.draft.full_authoring_snapshot(), authoring_before, "選択して眺めるだけでDraft全体を変更しないこと")
	assert_eq(main.draft.battle_content_snapshot(), battle_before, "選択して眺めるだけでbattle_content_snapshotも変更しないこと")

func test_step4_all_fixed_characters_show_every_real_skill_and_special_effect_data() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	var expected_effect_fragments := {
		"butler_sp_gift": "SPを40回復",
		"healer_sp_all": "味方全体のSPを40回復",
		"samurai_iai": "次の攻撃スキル：2.5倍",
		"samurai_counter": "ATK倍率：3.0倍",
		"tank_guard_swap": "攻撃をかばう",
		"tank_guard_boost": "軽減率：60%",
		"tank_iron_wall": "被ダメージ軽減：10%",
	}
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		step4.toggle_character(character_id)
		await get_tree().process_frame
		_btn(step4, "SelectCharacterButton_%s" % character_id).pressed.emit()
		_btn(step4, "PerformanceTabButton").pressed.emit()
		await get_tree().process_frame
		var master := main.draft.master_character_def(character_id)
		assert_eq(step4._tab_content.find_children("CharacterSkillCard_*", "", true, false).size(), (master.get("skills", []) as Array).size(), "%sの実スキルを全件表示すること" % character_id)
		for skill_variant in master.get("skills", []):
			var skill: Dictionary = skill_variant
			var skill_id := str(skill.get("id", ""))
			assert_eq(_label(step4, "SkillNameLabel_%s" % skill_id).text, str(skill.get("display_name", "")))
			assert_not_null(step4.find_child("SkillEffectLabel_%s" % skill_id, true, false), "%sの実effectに対応する説明を表示すること" % skill_id)
			if expected_effect_fragments.has(skill_id):
				assert_true(_label(step4, "SkillEffectLabel_%s" % skill_id).text.contains(str(expected_effect_fragments[skill_id])), "%sの実データ値を表示すること" % skill_id)
		step4.toggle_character(character_id)
		await get_tree().process_frame

## Creator UI改修（STEP4統合、2026-09-05）: 旧「閉じるボタンと重ならない」は
## 独立した「閉じる」概念自体が無くなったため、代わりに「タブ切替行
## （SelectedCharacterTabRow）はスクロール領域の外にあり、最下部までスクロール
## しても常に到達可能であること」を確認する（同じ意図——スクロール可能領域
## と常設の操作導線が重ならないこと）。
## STEP4と下部の帯の重なり修正（2026-10-05）: タブ領域は画面の残りの高さ（最小
## 160px）になり、性能調整のスキルカード1枚（SIMPLE約200px/HARDCORE約320px）は
## 表示領域より高くなりうる。そのため「最後のカード全体が一度に収まる」ことは
## 求めず、最後のカードまでスクロールで届き、最下部でその下端と最後の要素
## （HARDCOREでは最後の操作要素）まで見え、タブ領域が下部の帯（戻る/次へ/
## 作成を終了）に隠れないことを確かめる。
func test_step4_performance_skill_list_scrolls_to_last_skill_without_overlapping_tabs() -> void:
	for mode_button in ["ChooseSimpleModeButton", "ChooseAdvancedModeButton"]:
		var root := await _make_root()
		_btn(root, "CreateModeButton").pressed.emit()
		await get_tree().process_frame
		_btn(root.creator_entry, "NewBossButton").pressed.emit()
		await get_tree().process_frame
		_btn(root.creator_entry, mode_button).pressed.emit()
		await get_tree().process_frame
		var main: RBMCreatorMain = root.creator_entry.main
		main.go_to_step(main.party_step())
		await get_tree().process_frame
		var step4: RBMCreatorStep5Party = main._step_views[3]
		step4.toggle_character("hero")
		await get_tree().process_frame
		_btn(step4, "SelectCharacterButton_hero").pressed.emit()
		_btn(step4, "StatusEditButton").pressed.emit()
		_btn(step4, "PerformanceTabButton").pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var scroll: ScrollContainer = step4.find_child("SelectedCharacterTabScroll", true, false)
		var vbar := scroll.get_v_scroll_bar()
		assert_true(vbar.visible, "%s: 長いスキル一覧では性能パネル内部の縦スクロールを有効にすること" % mode_button)
		assert_gt(vbar.max_value, vbar.page)
		# 最後の技は味方の覚醒（2026-10-24 に hero_burst_slash の後ろへ追加）。
		var last_card := step4._tab_content.find_child("CharacterSkillCard_hero_awakening", true, false) as Control
		assert_not_null(last_card, "最後の実スキルも一覧に存在すること")
		assert_true(step4._tab_row.is_visible_in_tree(), "タブ切替行はスクロール領域外で常に到達可能であること")
		assert_false(scroll.get_global_rect().intersects(step4._tab_row.get_global_rect()), "スクロール領域とタブ切替行が重ならないこと")
		var footer_top: float = min(main._nav_row.get_global_rect().position.y, main._exit_button.get_global_rect().position.y)
		assert_true(scroll.get_global_rect().end.y <= footer_top + 0.5, "%s: タブ領域は下部の帯より上で終わること" % mode_button)
		scroll.scroll_vertical = int(ceil(vbar.max_value))
		await get_tree().process_frame
		assert_gt(scroll.scroll_vertical, 0, "最下部へ実際にスクロールできること")
		var scroll_rect := scroll.get_global_rect()
		var last_rect := last_card.get_global_rect()
		assert_true(last_rect.end.y > scroll_rect.position.y + 0.5, "%s: 最下部スクロール後に最後のスキルが表示領域に入っていること" % mode_button)
		assert_true(last_rect.end.y <= scroll_rect.end.y + 0.5, "%s: 最下部スクロール後に最後のスキルの下端まで確認できること" % mode_button)
		var last_label: Control = null
		var last_operable: Control = null
		for node in last_card.find_children("*", "Control", true, false):
			var c := node as Control
			if not c.is_visible_in_tree() or c.size.y <= 0.0:
				continue
			if c is Label and (last_label == null or c.get_global_rect().end.y > last_label.get_global_rect().end.y):
				last_label = c
			if (c is BaseButton or c is Range) and (last_operable == null or c.get_global_rect().end.y > last_operable.get_global_rect().end.y):
				last_operable = c
		assert_not_null(last_label)
		assert_true(scroll_rect.encloses(last_label.get_global_rect()), "%s: 最後のカードの最後の表示まで表示領域内で確認できること" % mode_button)
		if mode_button == "ChooseAdvancedModeButton":
			assert_not_null(last_operable, "HARDCOREの性能調整カードには操作要素があること")
			assert_true(scroll_rect.encloses(last_operable.get_global_rect()), "HARDCORE: 最後の操作要素まで表示領域内で操作できること")
		root.queue_free()
		await get_tree().process_frame

# =============================================================================
# Creator UI改修（2026-09-05）§13/§17: 旧・独立STEP5「使用可能スキル」
# （RBMCreatorStep6PartySkills）はCreatorのナビゲーションから廃止され、
# ロジックは新STEP4（RBMCreatorStep5Party、main._step_views[3]）の
# 「選択キャラクター設定」内[使用可能スキル]タブへ統合された——ノード名
# （EditPartySkillsButton_%s/AllOnButton_%s/AllOffButton_%s/SkillCheck_%s_%s/
# ConfirmPartySkillsButton_%s/CancelPartySkillsButton_%s）自体は移設元と
# 完全に同じまま維持している。「全キャラを同時に並べて編集する」旧UIから
# 「選択中の1人だけを編集する」新UIへ変わったため、各テストは対象キャラを
# select_character()/SelectCharacterButton_%sで選んでから操作する。
# =============================================================================

func _first_ally_skill_id(main: RBMCreatorMain, character_id: String) -> String:
	var master := main.draft.master_character_def(character_id)
	var skills: Array = master.get("skills", [])
	assert_gt(skills.size(), 0, "sanity: %s master must have at least one skill" % character_id)
	return str((skills[0] as Dictionary).get("id", ""))

## 新モデルでは一度に「選択中の1人」のスキルタブしか表示されない——他の
## パーティメンバーの使用可能スキル編集導線が同時に混ざって表示されない
## ことを確認する（旧「パーティ外のキャラはカード表示しない」の後継）。
func test_step5_only_the_selected_characters_skills_tab_is_shown_at_once() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	main.draft.add_party_character("hero")
	main.draft.add_party_character("butler")
	step4.refresh()
	await get_tree().process_frame
	step4.select_character("hero")
	await get_tree().process_frame
	assert_not_null(step4.find_child("EditPartySkillsButton_hero", true, false), "選択中キャラの使用可能スキルタブが表示されること")
	assert_null(step4.find_child("EditPartySkillsButton_butler", true, false), "未選択の他キャラは同時に表示されないこと")

func test_step5_normal_display_shows_allowed_or_not_allowed_per_skill() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	main.draft.add_party_character("hero")
	var skill_id := _first_ally_skill_id(main, "hero")
	main.draft.set_ally_skill_allowed("hero", skill_id, false)
	step4.refresh()
	await get_tree().process_frame
	var label: Label = step4.find_child("SkillStatusLabel_hero_%s" % skill_id, true, false)
	assert_not_null(label)
	assert_true(label.text.contains("使用不可"))

	main.draft.set_ally_skill_allowed("hero", skill_id, true)
	step4.refresh()
	await get_tree().process_frame
	label = step4.find_child("SkillStatusLabel_hero_%s" % skill_id, true, false)
	assert_true(label.text.contains("使用可"))

func test_step5_edit_button_reveals_checkboxes_for_that_character_only() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	main.draft.add_party_character("hero")
	main.draft.add_party_character("butler")
	step4.refresh()
	await get_tree().process_frame

	_btn(step4, "EditPartySkillsButton_hero").pressed.emit()
	await get_tree().process_frame
	var hero_skill_id := _first_ally_skill_id(main, "hero")
	assert_not_null(step4.find_child("SkillCheck_hero_%s" % hero_skill_id, true, false), "編集を押したキャラだけON/OFFトグルが展開されること")

	step4.select_character("butler")
	await get_tree().process_frame
	var butler_skill_id := _first_ally_skill_id(main, "butler")
	assert_null(step4.find_child("SkillCheck_butler_%s" % butler_skill_id, true, false), "他のキャラへ切り替えたら編集中状態を引き継がず通常表示から始まること")

func test_step5_toggle_and_confirm_commits_to_draft() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	main.draft.add_party_character("hero")
	var skill_id := _first_ally_skill_id(main, "hero")
	main.draft.set_ally_skill_allowed("hero", skill_id, true)
	step4.refresh()
	await get_tree().process_frame

	_btn(step4, "EditPartySkillsButton_hero").pressed.emit()
	await get_tree().process_frame
	var check: CheckButton = step4.find_child("SkillCheck_hero_%s" % skill_id, true, false)
	assert_true(check.button_pressed, "sanity: starts allowed")
	check.button_pressed = false
	check.toggled.emit(false)
	await get_tree().process_frame
	# 変更時にDraftへ反映されること。
	assert_true(main.draft.is_ally_skill_allowed("hero", skill_id))

	_btn(step4, "ConfirmPartySkillsButton_hero").pressed.emit()
	await get_tree().process_frame
	assert_false(main.draft.is_ally_skill_allowed("hero", skill_id), "決定でDraftへ反映されること")

func test_step5_cancel_discards_staged_changes() -> void:
	var main := await _new_creator_main()
	var step4: RBMCreatorStep5Party = main._step_views[3]
	main.draft.add_party_character("hero")
	var skill_id := _first_ally_skill_id(main, "hero")
	main.draft.set_ally_skill_allowed("hero", skill_id, true)
	step4.refresh()
	await get_tree().process_frame

	_btn(step4, "EditPartySkillsButton_hero").pressed.emit()
	await get_tree().process_frame
	var check: CheckButton = step4.find_child("SkillCheck_hero_%s" % skill_id, true, false)
	check.button_pressed = false
	check.toggled.emit(false)
	await get_tree().process_frame

	_btn(step4, "CancelPartySkillsButton_hero").pressed.emit()
	await get_tree().process_frame
	assert_true(main.draft.is_ally_skill_allowed("hero", skill_id), "キャンセルで編集開始時点の値（許可のまま）を維持すること")
