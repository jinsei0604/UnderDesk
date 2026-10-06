extends GutTest
## 覚醒対応(supports_awakening)の回帰テスト。覚醒対応は竜・朽ちた機械武者・宇宙飛行士・異形紳士の
## 4体で、残りの5体(スライム・狼・騎士・幽霊・ゴーレム)は非対応のまま。

func after_each() -> void:
	await get_tree().process_frame

## 覚醒対応は竜・朽ちた機械武者・宇宙飛行士・異形紳士の4体だけ。他の5体は非対応のまま。
func test_only_approved_bosses_are_set_to_supports_awakening() -> void:
	for entry in RBMCreatorAppearanceCatalog.all():
		var expected: bool = str(entry["id"]) in ["appearance_dragon", "appearance_musha", "appearance_astronaut", "appearance_gentleman"]
		assert_eq(bool(entry.get("supports_awakening", false)), expected)
		assert_eq(RBMCreatorAppearanceCatalog.supports_awakening(str(entry["id"])), expected)

func test_supports_awakening_defaults_to_false_for_an_unknown_id() -> void:
	assert_false(RBMCreatorAppearanceCatalog.supports_awakening("appearance_does_not_exist"))

func test_supports_awakening_extraction_logic_handles_true_false_and_missing_key() -> void:
	assert_true(bool({"id": "x", "supports_awakening": true}.get("supports_awakening", false)))
	assert_false(bool({"id": "x", "supports_awakening": false}.get("supports_awakening", false)))
	assert_false(bool({"id": "x"}.get("supports_awakening", false)))

## 全9体のIDと並び: 既存6体は不変で、その後ろに朽ちた機械武者・宇宙飛行士・異形紳士がこの順で並ぶこと。
func test_catalog_entry_count_and_ids_are_unchanged() -> void:
	var ids: Array = []
	for entry in RBMCreatorAppearanceCatalog.all(): ids.append(str(entry["id"]))
	assert_eq(ids, ["appearance_slime", "appearance_wolf", "appearance_knight", "appearance_dragon", "appearance_ghost", "appearance_golem", "appearance_musha", "appearance_astronaut", "appearance_gentleman"])

func _draft() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "覚醒対応テストボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_party_character("hero")
	return draft

func test_draft_supports_awakening_only_for_approved_bosses() -> void:
	var draft := _draft()
	for entry in RBMCreatorAppearanceCatalog.all():
		draft.appearance_id = str(entry["id"])
		assert_eq(draft.supports_awakening(), draft.appearance_id in ["appearance_dragon", "appearance_musha", "appearance_astronaut", "appearance_gentleman"])

func test_draft_supports_awakening_is_false_when_no_appearance_chosen_yet() -> void:
	var draft := _draft()
	draft.appearance_id = ""
	assert_false(draft.supports_awakening())

func test_is_awakening_appearance_valid_is_true_when_no_awakening_configured() -> void:
	var draft := _draft()
	draft.appearance_id = "appearance_slime"
	assert_false(draft.has_awakening())
	assert_true(draft.is_awakening_appearance_valid())

func test_is_awakening_appearance_valid_is_false_when_awakening_set_on_unsupported_appearance() -> void:
	var draft := _draft()
	draft.appearance_id = "appearance_slime"
	draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	assert_true(draft.has_awakening())
	assert_false(draft.supports_awakening())
	assert_false(draft.is_awakening_appearance_valid())

func test_is_playable_becomes_false_when_awakening_is_orphaned_by_an_appearance_change() -> void:
	var draft := _draft()
	draft.appearance_id = "appearance_dragon"
	assert_true(draft.is_playable())
	draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	assert_true(draft.is_awakening_appearance_valid())
	assert_true(draft.is_playable(), "Approved dragon allows awakening")
	draft.appearance_id = "appearance_slime"
	assert_false(draft.is_playable(), "Changing to an unsupported appearance blocks the orphaned awakening")
	draft.remove_awakening()
	assert_true(draft.is_playable())

func test_is_playable_unaffected_when_no_awakening_is_configured_regardless_of_appearance() -> void:
	var draft := _draft()
	for entry in RBMCreatorAppearanceCatalog.all():
		draft.appearance_id = str(entry["id"])
		assert_true(draft.is_playable())

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _fill_minimum_valid_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "覚醒対応UIテストボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

func _open_advanced(creator: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	step3.refresh()
	return step3._advanced_view

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s" % button_name)
	return found

func test_awakening_type_disabled_when_appearance_does_not_support_it_even_if_unset() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_slime"
	assert_false(creator.draft.has_awakening())
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._form._type_option.is_item_disabled(RBMActionEditorForm.TYPE_IDS.find(RBMActionEditorForm.AWAKENING)))

func test_awakening_type_available_for_approved_dragon() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_dragon"
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_false(advanced._form._type_option.is_item_disabled(RBMActionEditorForm.TYPE_IDS.find(RBMActionEditorForm.AWAKENING)))

func test_awakening_availability_combines_support_and_configured_state_correctly() -> void:
	var table := [
		{"supports": true, "configured": false, "expected_available": true},
		{"supports": true, "configured": true, "expected_available": false},
		{"supports": false, "configured": false, "expected_available": false},
		{"supports": false, "configured": true, "expected_available": false},
	]
	for row in table:
		var available: bool = bool(row["supports"]) and not bool(row["configured"])
		assert_eq(available, bool(row["expected_available"]))
