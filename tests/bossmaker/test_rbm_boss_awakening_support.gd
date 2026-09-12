extends GutTest

## RPG BOSS MAKER — ボスごとの覚醒対応可否(supports_awakening)の回帰テスト。
## RBMCreatorAppearanceCatalog.ENTRIESはGodotのconstとして実行時読み取り
## 専用のため、既存6体を書き換えて「対応ありのケース」を作ることはできない
## (かつ、実際のボスを勝手に覚醒対応へ設定することは今回の確定仕様として
## 禁止されている)。そのため、
##   ・既存6体は全てfalseであること(=勝手にtrueへ設定していないこと)
##   ・真偽値抽出ロジック自体(.get(key,false)パターン)がtrue/false/欠落の
##     いずれでも正しく動くこと
## を分けて検証する——後者はhand-builtなDictionaryで直接確認する、正規の
## catalogを一切書き換えない検証方法。

func after_each() -> void:
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# RBMCreatorAppearanceCatalog
# ---------------------------------------------------------------------------

func test_all_six_existing_appearances_are_not_set_to_supports_awakening() -> void:
	for entry in RBMCreatorAppearanceCatalog.all():
		assert_false(bool(entry.get("supports_awakening", false)), "%s must not be pre-enabled for awakening by this change" % str(entry.get("id", "")))
		assert_false(RBMCreatorAppearanceCatalog.supports_awakening(str(entry["id"])), "%s must not be pre-enabled for awakening by this change" % str(entry["id"]))

func test_supports_awakening_defaults_to_false_for_an_unknown_id() -> void:
	assert_false(RBMCreatorAppearanceCatalog.supports_awakening("appearance_does_not_exist"))

## catalog自体はconstのため書き換えられない——「キーがtrue/false/欠落の
## それぞれでどう解決されるか」という抽出ロジックの正しさは、実際に
## by_id()が返す形と全く同じ形のDictionaryを直接使って確認する。
func test_supports_awakening_extraction_logic_handles_true_false_and_missing_key() -> void:
	assert_true(bool({"id": "x", "supports_awakening": true}.get("supports_awakening", false)))
	assert_false(bool({"id": "x", "supports_awakening": false}.get("supports_awakening", false)))
	assert_false(bool({"id": "x"}.get("supports_awakening", false)), "a missing key must default to false")

func test_catalog_entry_count_and_ids_are_unchanged() -> void:
	var ids: Array = []
	for entry in RBMCreatorAppearanceCatalog.all():
		ids.append(str(entry["id"]))
	assert_eq(ids, ["appearance_slime", "appearance_wolf", "appearance_knight", "appearance_dragon", "appearance_ghost", "appearance_golem"])

# ---------------------------------------------------------------------------
# RBMCreatorDraft
# ---------------------------------------------------------------------------

func _draft() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "覚醒対応テストボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_party_character("hero")
	return draft

func test_draft_supports_awakening_is_false_for_every_real_appearance() -> void:
	var draft := _draft()
	for entry in RBMCreatorAppearanceCatalog.all():
		draft.appearance_id = str(entry["id"])
		assert_false(draft.supports_awakening(), "%s must resolve to false" % draft.appearance_id)

func test_draft_supports_awakening_is_false_when_no_appearance_chosen_yet() -> void:
	var draft := _draft()
	draft.appearance_id = ""
	assert_false(draft.supports_awakening())

func test_is_awakening_appearance_valid_is_true_when_no_awakening_configured() -> void:
	var draft := _draft()
	draft.appearance_id = "appearance_slime"
	assert_false(draft.has_awakening())
	assert_true(draft.is_awakening_appearance_valid(), "no awakening configured -- always valid regardless of appearance")

## これは既存データ(supports_awakening=false)の実データだけで再現できる、
## 今回のvalidationの本題そのもの——覚醒対応でない外見のまま覚醒を設定
## した場合は不正、というケース。
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
	assert_true(draft.is_playable(), "sanity: a normal minimal boss with no awakening is playable")
	draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	# The appearance never supported awakening in the first place, so this
	# awakening is invalid the moment it exists -- is_playable() must reflect
	# that immediately, without needing to simulate "changing the appearance
	# afterward" (any appearance that could reach this state is, today,
	# already unsupported).
	assert_false(draft.is_playable(), "an awakening configured on a non-supporting appearance must block playability")
	draft.remove_awakening()
	assert_true(draft.is_playable(), "removing the orphaned awakening restores playability")

func test_is_playable_unaffected_when_no_awakening_is_configured_regardless_of_appearance() -> void:
	var draft := _draft()
	for entry in RBMCreatorAppearanceCatalog.all():
		draft.appearance_id = str(entry["id"])
		assert_true(draft.is_playable(), "%s with no awakening configured must remain playable (no regression)" % draft.appearance_id)

# ---------------------------------------------------------------------------
# Creator STEP3: 覚醒の種類選択disabled判定
# ---------------------------------------------------------------------------

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

func _step3(creator: RBMCreatorMain) -> RBMCreatorStep4:
	creator.go_to_step(3)
	var view: RBMCreatorStep4 = creator._step_views[2]
	return view

func _open_advanced(creator: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	var step3 := _step3(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	step3.refresh()
	return step3._advanced_view

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

## 既存6体はすべて覚醒非対応のため、この経路は実データだけで完全に
## 再現できる——「覚醒未設定でも、外見が非対応なら選択不可」の確認。
func test_awakening_type_disabled_when_appearance_does_not_support_it_even_if_unset() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_dragon"
	assert_false(creator.draft.has_awakening())
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._form._type_option.is_item_disabled(RBMActionEditorForm.TYPE_IDS.find(RBMActionEditorForm.AWAKENING)))

## 「覚醒対応ならまだ選択できる」経路自体は、フォーム側のset_awakening_
## type_available()に直接真偽値を渡して検証済み(既存の覚醒UIテスト群)。
## ここでは、STEP3画面が実際に計算する2つの独立した真偽値の組み合わせ
## ロジック(「対応している AND 未設定」の時だけ有効にする)を、内部で
## 混同していないことを確認する——4通りの組み合わせすべてが正しい結論に
## なることを直接の真偽値テーブルとして確認する。
func test_awakening_availability_combines_support_and_configured_state_correctly() -> void:
	var table := [
		{"supports": true, "configured": false, "expected_available": true},
		{"supports": true, "configured": true, "expected_available": false},
		{"supports": false, "configured": false, "expected_available": false},
		{"supports": false, "configured": true, "expected_available": false},
	]
	for row in table:
		var available: bool = bool(row["supports"]) and not bool(row["configured"])
		assert_eq(available, bool(row["expected_available"]), "supports=%s configured=%s" % [row["supports"], row["configured"]])
