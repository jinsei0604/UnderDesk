extends GutTest
## 戦闘画面の HUD（案C、2026-10-23 ユーザーが採用。rbm_fullscreen_battle_ui.gd・rbm_battle_hud_style.gd）。
## 行動順のボスの顔の写真が顔を切り出していること、行動順の下に LOG・やめる、味方のカードの文字（HP・SP の数値）は
## 今までどおり、行動中の味方の札、最新の行動の欄の位置と高さ。表示専用で、戦闘の状態を変えないことも確かめる。

func _definition(party: Array = ["hero", "butler", "healer", "samurai"]) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "HUDの確認"
	draft.hp = 5000
	draft.atk = 30
	draft.spd = 1
	for id in party:
		draft.add_party_character(id)
	var skill_id := draft.add_skill({"name": "攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return draft.to_definition()

func _view(party: Array = ["hero", "butler", "healer", "samurai"]) -> RBMChallengeBattleView:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.size = Vector2(1280, 720)
	await get_tree().process_frame
	view.start_battle(_definition(party), RBMBattleUiKit.ALL_VISIBLE, "appearance_dragon")
	for i in range(3):
		await get_tree().process_frame
	return view

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()

func _row_text(row: Control) -> String:
	var parts: Array[String] = []
	for child in row.get_child(0).get_children():
		if child is Label:
			parts.append((child as Label).text)
	return "".join(parts)

## 2026-10-23 ユーザーの指定「ボスの行動順にある写真はちゃんと顔が映るように」: ボスの行は FACE_REGIONS の顔の範囲を切り出す。
func test_the_turn_order_shows_the_boss_face() -> void:
	var view := await _view()
	var list: Control = view._turn_order_panel.get_node("TurnOrderList")
	assert_eq(list.get_child_count(), 5, "sanity: 4 allies + boss")
	var boss_rows := 0
	for row in list.get_children():
		var entry: Dictionary = row.get_meta("turn_order_entry")
		var face := row.find_child("TurnOrderFacePortrait", true, false) as TextureRect
		assert_not_null(face, "every row has a face picture")
		if not bool(entry["is_boss"]):
			continue
		boss_rows += 1
		assert_true(face.texture is AtlasTexture, "the boss picture is cut out")
		var atlas := face.texture as AtlasTexture
		assert_eq(atlas.region, RBMVisualAssets.face_region("dragon", atlas.atlas.get_size()), "cut at the dragon's face (FACE_REGIONS)")
	assert_eq(boss_rows, 1)
	# 行の文字（▶ と名前）は今までどおり（▶ は見せず、帯と右の ▶ で示す）
	var current := list.get_child(0) as Control
	assert_true(_row_text(current).begins_with("▶"), "the current row still starts with ▶: %s" % _row_text(current))

func test_every_boss_face_is_inside_its_picture() -> void:
	for asset_id in RBMVisualAssets.FACE_REGIONS:
		var texture := RBMVisualAssets.texture(asset_id)
		assert_not_null(texture, "%s has a picture" % asset_id)
		if texture == null:
			continue
		var region := RBMVisualAssets.face_region(asset_id, texture.get_size())
		assert_true(region.has_area(), "%s has a face" % asset_id)
		assert_true(Rect2(Vector2.ZERO, texture.get_size()).encloses(region), "%s face inside the picture" % asset_id)
		assert_almost_eq(region.size.x, region.size.y, 1.0, "%s face is square (not stretched in the 22px frame)" % asset_id)
	assert_eq(RBMVisualAssets.face_region("hero", Vector2(512, 512)), Rect2(), "allies keep the usual portrait cut")

## 2026-10-23 ユーザーの指定「行動順の下に LOG とやめるボタンを設置する」。
func test_log_and_quit_sit_under_the_turn_order() -> void:
	var view := await _view()
	var order := view.find_child("TurnOrderBackdrop", true, false) as Control
	var log_button := view.find_child("LogButton", true, false) as Control
	var quit := view._quit_button
	var screen := Rect2(0, 0, 1280, 720)
	assert_true(screen.encloses(_rect(order)))
	assert_true(_rect(order).encloses(_rect(view._turn_order_panel)), "the rows are inside the turn order panel")
	for b in [log_button, quit]:
		assert_true(screen.encloses(_rect(b)), "%s on screen" % b.name)
		assert_between(_rect(b).position.y - _rect(order).end.y, 0.0, 16.0, "%s right under the turn order" % b.name)
		assert_true(_rect(b).position.x >= _rect(order).position.x - 0.5 and _rect(b).end.x <= _rect(order).end.x + 0.5, "%s within the turn order's width" % b.name)
	assert_lt(_rect(log_button).end.x, _rect(quit).position.x, "LOG on the left, quit on the right")
	assert_eq(_rect(log_button).position.y, _rect(quit).position.y, "one row")
	# 技の一覧を開いても、コマンドの欄は LOG・やめるの下
	view._open_skill_list()
	await get_tree().process_frame
	await get_tree().process_frame
	var command := view.find_child("CommandBackdrop", true, false) as Control
	assert_gt(_rect(command).position.y, _rect(quit).end.y, "the skill list stays below LOG and quit")
	assert_false(_rect(view._world_battle.command_scroll).intersects(_rect(quit)))

func test_party_cards_keep_their_texts_and_mark_the_active_ally() -> void:
	var view := await _view()
	var battle := view.session.battle
	var pending := int(view.session.pending_ally_id())
	assert_gte(pending, 0, "sanity: waiting for an ally")
	for unit in battle.party:
		var card := view._party_rows.find_child("PartyRow_%d" % unit.id, true, false) as Control
		assert_not_null(card)
		assert_eq((card.find_child("PartyRowHP_%d" % unit.id, true, false) as Label).text, "HP %d / %d" % [unit.hp, unit.max_hp], "the HP text is unchanged")
		assert_eq((card.find_child("PartyRowSP_%d" % unit.id, true, false) as Label).text, "SP %d / %d" % [unit.sp, unit.max_sp])
		assert_true((card.find_child("PartyRowName_%d" % unit.id, true, false) as Label).text.contains(tr(unit.display_name)))
		var chip := card.find_child("PartyRowActive_%d" % unit.id, true, false) as Control
		assert_not_null(chip, "each card has an ACTIVE tag")
		assert_eq(chip.visible, unit.id == pending, "only the ally choosing a command is ACTIVE")
	assert_eq(view.find_child("CommandActorName", true, false).text, tr(RBMBattleUiKit.unit_by_id(battle, pending).display_name), "the command panel names the ally")
	assert_true(Rect2(0, 0, 1280, 720).encloses(_rect(view._party_rows)))
	assert_true(_rect(view.find_child("PartyPanel", true, false)).encloses(_rect(view._party_rows)))
	# 行動すると次の味方が ACTIVE になる（HP の文字の同期は presenter のまま）
	view.act_attack(pending)
	for i in range(3):
		await get_tree().process_frame
	var next := int(view.session.pending_ally_id())
	if next >= 0 and next != pending:
		assert_true(view._party_rows.find_child("PartyRowActive_%d" % next, true, false).visible)
		assert_false(view._party_rows.find_child("PartyRowActive_%d" % pending, true, false).visible)

## 最新の行動と結果の欄: ボスの欄のすぐ下、戦場（ステージの絵）の上。高さ 112px のスクロール（UI_UX §5.2）。
func test_the_latest_info_sits_under_the_boss_panel() -> void:
	var view := await _view()
	var message := view.find_child("LatestInfoPanel", true, false) as Control
	var boss_panel := view.find_child("BossPanel", true, false) as Control
	assert_gte(_rect(message).position.y, _rect(boss_panel).end.y, "below the boss panel")
	assert_lte(_rect(message).end.y, _rect(view._battlefield).position.y, "above the battlefield")
	assert_eq(message.size.y, 112.0, "the 112px scroll for every result of an all-target attack")
	assert_gte(message.size.x, 600.0)
	for name in ["TurnOrderBackdrop", "LogButton", "QuitChallengeButton", "RestartButton"]:
		assert_false(_rect(message).intersects(_rect(view.find_child(name, true, false))), "clear of %s" % name)
	var backdrop := view.find_child("LatestInfoBackdrop", true, false) as Control
	view._log_label.text = ""
	await get_tree().process_frame
	assert_false(backdrop.visible, "no empty frame without a message")
	view._log_label.text = "竜：炎のブレス\n炎属性・勇者 に 28 ダメージ"
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(backdrop.visible)
	assert_between(backdrop.size.y, 40.0, 112.0)

func test_the_hud_is_display_only() -> void:
	var view := await _view()
	var before: Dictionary = view.session.battle.snapshot().duplicate(true)
	view._world_battle.update()
	view._world_battle._apply_style()
	await get_tree().process_frame
	assert_eq(view.session.battle.snapshot(), before)
