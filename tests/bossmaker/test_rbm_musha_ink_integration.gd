extends GutTest
## 朽ちた機械武者の「墨」と「コマ送り」の本番組み込み(承認済み 2026-09-27)の契約テスト。
## 見た目・映像の質は GPU 実機(tools/verify_musha_*_gpu.gd)で確認し、ここではステージへの組み込み・片付け・
## 待機中の本体の差し替え・コマの読み込み・消音の尊重・演出と墨の層の時刻の一致を検証する。
const Frames = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const Ink = preload("res://src/bossmaker/visuals/rbm_musha_ink_director.gd")
const FramePresentation = preload("res://src/bossmaker/visuals/rbm_musha_frame_presentation.gd")
const AwakenedFrames = preload("res://src/bossmaker/visuals/rbm_musha_awakened_frame_presentation.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
## 演出の契約は、事前読み込みが素材を読み終えた状態で検証する(QA-06。読み終えていない時の待ちは
## test_rbm_presentation_warmup.gd が検証する)。
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["musha"])

func after_all() -> void:
	_ready_assets.clear()

func after_each() -> void:
	await get_tree().process_frame

func _draft(kind: String = "single") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_musha"
	draft.boss_name = "Musha Ink QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]:
		draft.add_party_character(id)
	var id := draft.add_skill({"name": "Musha QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": "FIRE", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	return draft

func _fixture(kind: String = "single", awakened: bool = false) -> Dictionary:
	var draft := _draft(kind)
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	if awakened:
		session.battle.is_awakened = true
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_musha")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		for e in session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss":
				entry = e
		if not entry.is_empty():
			break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", str(draft.skills[0].get("skill_id", "")), session.battle)
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}

func _ink_sprites(stage: Node) -> int:
	var n := 0
	for child in stage.get_children():
		if child is Sprite2D and (child as Sprite2D).texture is ViewportTexture:
			n += 1
	return n

# ---------------------------------------------------------------------------

func test_musha_stage_owns_one_ink_layer_and_idle_body_and_cleans_up_on_switch() -> void:
	var f := _fixture()
	var stage: RBMBattleStage = f.stage
	var ink = stage.musha_ink_director()
	assert_not_null(ink, "the musha stage has an ink layer")
	assert_true(is_instance_valid(stage._musha_idle), "and an idle body")
	assert_eq(_ink_sprites(stage), 6, "back / mid / top ink canvases, and the same three shown over the battle HUD at the impact")
	stage.configure(f.session.battle, "appearance_musha")
	assert_eq(stage.musha_ink_director(), ink, "reconfiguring the same boss keeps the same layer")
	var boss_visual: Control = stage._visuals["boss"]
	stage.configure(f.session.battle, "appearance_golem")
	assert_null(stage.musha_ink_director(), "another boss has no ink layer")
	assert_null(stage._musha_idle)
	await get_tree().process_frame
	assert_eq(_ink_sprites(stage), 0, "all ink display nodes are removed from the stage")
	assert_eq(stage._visuals["boss"].self_modulate.a, 1.0, "the other boss is drawn normally")
	assert_ne(stage._visuals["boss"], boss_visual)

func test_idle_body_replaces_the_still_image_only_while_idle_in_the_neutral_pose() -> void:
	var f := _fixture()
	var stage: RBMBattleStage = f.stage
	var idle: Node2D = stage._musha_idle
	var boss: Control = stage._visuals["boss"]
	idle._sync()
	assert_true(idle.visible, "idle: the frame body is drawn")
	assert_eq(boss.self_modulate.a, 0.0, "idle: the still image is hidden underneath")
	assert_eq(str(idle.state.fr), "idle")
	stage._pose("boss", 10)
	idle._sync()
	assert_false(idle.visible, "a non-neutral pose (defend/hit) shows the real visual")
	assert_eq(boss.self_modulate.a, 1.0)
	stage._pose("boss", 0)
	stage.play_entry(f.entry, f.skill)
	idle._sync()
	assert_false(idle.visible, "during playback the presentation draws the body")
	assert_eq(boss.self_modulate.a, 1.0, "and the still image is restored (the presentation hides it itself)")
	stage.cancel()
	idle._sync()
	assert_true(idle.visible)

func test_awakened_idle_body_feeds_the_blade_to_the_ink_layer() -> void:
	var f := _fixture("single", true)
	var stage: RBMBattleStage = f.stage
	var idle: Node2D = stage._musha_idle
	idle._sync()
	assert_eq(str(idle.state.fr), "a3", "the drawn-sword wait")
	var ink = stage.musha_ink_director()
	assert_eq(ink.body, idle.state, "the rising ink follows the drawn blade")
	assert_eq(Frames.blade(idle.state).size(), 2)

func test_every_frame_used_by_the_presentations_loads() -> void:
	var names: Array = []
	for keys in [FramePresentation.SINGLE_KEYS, FramePresentation.ALL_KEYS, FramePresentation.SUPPORT_KEYS, AwakenedFrames.SINGLE_KEYS, AwakenedFrames.ALL_KEYS]:
		for k in keys:
			if str(k[1]) != "" and not names.has(str(k[1])):
				names.append(str(k[1]))
	for fl in FramePresentation.FLASHES:
		if not names.has(str(fl[2])):
			names.append(str(fl[2]))
	for extra in ["idle", "a0", "a3"]:
		names.append(extra)
	for name in names:
		assert_true(Frames.has_frame(name), "frame %s exists" % name)
		var fr: Dictionary = Frames.FR[name]
		assert_not_null(Frames.texture(str(fr.tex)), "frame %s has its texture" % name)

func test_ink_display_nodes_never_look_like_the_stage_background() -> void:
	var f := _fixture("single", true)
	var stage: RBMBattleStage = f.stage
	var viewport_rects := 0
	for child in stage.get_children():
		if child is TextureRect and (child as TextureRect).texture is ViewportTexture:
			viewport_rects += 1
	assert_eq(viewport_rects, 0, "the aura looks for the background among TextureRects; the ink canvases are not TextureRects")
	var bg := TextureRect.new()
	bg.texture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	# 背景を最後に足しても(墨の表示部品より後ろでも)、背景が見つかる = 墨の表示部品を背景と取り違えない
	stage.add_child(bg)
	assert_eq(stage._musha_aura._find_background(), bg, "the real background is found, not an ink canvas")

func test_added_sounds_stay_silent_while_the_stage_audio_is_muted() -> void:
	for muted in [true, false]:
		var f := _fixture("aoe", true)
		var stage: RBMBattleStage = f.stage
		stage._sound.muted = muted
		stage.play_entry(f.entry, f.skill)
		var d = stage._skill_presentation
		assert_true(d is AwakenedFrames)
		stage._tween.custom_step(AwakenedFrames.FLASH_CUT_SOUNDS[3][0] + .01)
		var players := 0
		for child in d.get_children():
			if child is AudioStreamPlayer:
				players += 1
		if muted:
			assert_eq(players, 0, "no extra cut sounds while the stage audio is muted")
		else:
			assert_gt(players, 0, "the cut sounds play when the stage audio is on")
		stage.cancel()

func test_awakened_all_presentation_and_ink_layer_share_one_timeline() -> void:
	var f := _fixture("aoe", true)
	var stage: RBMBattleStage = f.stage
	stage.play_entry(f.entry, f.skill)
	var d = stage._skill_presentation
	assert_almost_eq(float(d.strike_at), Ink.A_IMPACT, 0.001, "damage is notified when the ink blast lands")
	assert_almost_eq(float(d.duration), Ink.A_END, 0.001)
	assert_almost_eq(AwakenedFrames.FLURRY_AT, Ink.A_SWEEP, 0.001, "the delayed cuts appear with the ink cuts")
	assert_almost_eq(AwakenedFrames.NOTO_CLICK_AT, Ink.A_CLICK2, 0.001, "the tsuba clicks when the blade is fully sheathed")
	for j in range(Ink.FLASH_CUTS.size()):
		assert_almost_eq(float(AwakenedFrames.FLASH_CUT_SOUNDS[j][0]), Ink.A_FLASH + float(Ink.FLASH_CUTS[j][0]), 0.001, "cut sound %d matches cut %d on the white screen" % [j, j])
		assert_almost_eq(float(AwakenedFrames.FLURRY_DT[j]), float(Ink.FLASH_CUTS[j][0]), 0.001, "the delayed cut %d keeps the same rhythm" % j)
	stage.cancel()

## 着弾の瞬間の確認(2026-09-27): 承認時の動画(UIなし)と比べ、本番ではUI欄が墨の爆発を隠し、描画が重くてコマが落ちていた。
## 描き方をまとめ描きにし(画素は同じ)、着弾の瞬間だけUI欄の上にも墨の層を重ねる。

func _fake_hud(stage: Control) -> Control:
	var hud := Control.new()
	hud.name = "BattleHUD"
	hud.z_index = 20
	stage.get_parent().add_child(hud)
	var status := Panel.new()
	status.position = Vector2(24, 558)
	status.size = Vector2(900, 134)
	hud.add_child(status)
	var card := Panel.new()   # 欄の中の部品(欄の矩形に含まれる)
	card.position = Vector2(12, 10)
	card.size = Vector2(200, 100)
	status.add_child(card)
	var button := Button.new()
	button.position = Vector2(944, 240)
	button.size = Vector2(90, 44)
	hud.add_child(button)
	var dialog := Panel.new()   # 閉じているダイアログ
	dialog.position = Vector2(190, 260)
	dialog.size = Vector2(900, 180)
	dialog.visible = false
	hud.add_child(dialog)
	var label := Label.new()   # 透明な文字(矩形にしない)
	label.position = Vector2(24, 450)
	label.size = Vector2(700, 100)
	label.text = "log"
	hud.add_child(label)
	stage.set_meta("battle_hud", hud)
	autofree(hud)
	return hud

func test_the_impact_is_shown_over_the_battle_hud_only_at_the_peak() -> void:
	var f := _fixture("single", true)
	var stage: RBMBattleStage = f.stage
	_fake_hud(stage)
	var ink = stage.musha_ink_director()
	assert_eq(ink.hud_over.size(), 3)
	var layers: Array = [ink.back, ink.mid, ink.top]
	for i in range(3):
		var s: Sprite2D = ink.hud_over[i]
		assert_gt(s.z_index, 20, "over the battle HUD")
		assert_lt(s.z_index, 60, "under the confirmation dialogs")
		assert_eq(s.texture, (layers[i].disp as Sprite2D).texture, "shows the ink layer itself (no second drawing), back → mid → top")
	stage.play_entry(f.entry, f.skill)
	stage._tween.custom_step(Ink.S_CUT - 0.05)
	assert_false(ink.hud_over[0].visible, "before the impact the HUD stays in front")
	stage._tween.custom_step(0.15)
	assert_true(ink.hud_over[0].visible, "at the impact the ink is shown over the HUD")
	assert_eq(ink._hud_rects.size(), 2, "the visible panel and button only (not the card inside, the closed dialog or the text)")
	assert_true(ink._hud_rects.has(Rect2(24, 558, 900, 134)))
	assert_true(ink._hud_rects.has(Rect2(944, 240, 90, 44)))
	assert_eq(int(ink.hud_over_mat.get_shader_parameter("count")), 2)
	assert_almost_eq(float(ink.hud_over_mat.get_shader_parameter("amount")), 1.0, 0.001)
	stage._tween.custom_step(1.5)
	assert_false(ink.hud_over[0].visible, "after the ink blast the HUD is in front again")
	stage.cancel()

func test_the_all_attack_white_screen_and_blast_are_shown_over_the_hud_only_while_they_last() -> void:
	var f := _fixture("aoe", true)
	var stage: RBMBattleStage = f.stage
	_fake_hud(stage)
	var ink = stage.musha_ink_director()
	stage.play_entry(f.entry, f.skill)
	stage._tween.custom_step(Ink.A_FLASH - 0.05)
	assert_false(ink.hud_over[2].visible, "the stance before the draw: the HUD is in front")
	stage._tween.custom_step(0.35)
	assert_true(ink.hud_over[2].visible, "the white screen covers the HUD as well")
	assert_almost_eq(float(ink.hud_over_mat.get_shader_parameter("amount")), 1.0, 0.001, "as white as the rest of the screen")
	stage._tween.custom_step((Ink.A_FLASH_END - Ink.A_FLASH) - 0.3 + 0.05)
	assert_false(ink.hud_over[2].visible, "right after the white screen the HUD is back in front")
	stage._tween.custom_step(Ink.A_CLICK2 - Ink.A_FLASH_END)
	assert_false(ink.hud_over[2].visible, "the quiet pause before the blast: the HUD is in front")
	stage._tween.custom_step(Ink.A_IMPACT + 0.1 - Ink.A_CLICK2 - 0.05)
	assert_true(ink.hud_over[2].visible, "the ink blast is shown over the HUD")
	stage._tween.custom_step((Ink.A_END - 0.2) - (Ink.A_IMPACT + 0.1))
	assert_true(ink.hud_over[2].visible)
	assert_lt(float(ink.hud_over_mat.get_shader_parameter("amount")), 0.9, "fading out near the end of the attack")
	stage._tween.custom_step(0.17)
	assert_true(stage.is_playing(), "(still inside the attack)")
	assert_false(ink.hud_over[2].visible, "faded out before the attack ends")
	stage.cancel()
	assert_false(ink.hud_over[2].visible)

func test_without_a_battle_hud_nothing_is_shown_over_it() -> void:
	var f := _fixture("aoe", true)
	var stage: RBMBattleStage = f.stage
	var ink = stage.musha_ink_director()
	stage.play_entry(f.entry, f.skill)
	stage._tween.custom_step(Ink.A_IMPACT + 0.1)
	assert_gt(ink._hud_peak(), 0.9, "the all-attack blast is at its peak")
	for s in ink.hud_over:
		assert_false((s as Sprite2D).visible, "no HUD (home monitor etc.): nothing extra")
	stage.cancel()

func test_the_fullscreen_battle_ui_hands_its_hud_to_the_stage() -> void:
	var view := RBMCreatorTestBattleView.new()
	add_child_autofree(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.setup(null)
	view.set_boss_appearance("appearance_musha")
	view.start(_draft().to_definition(), 5)
	for i in range(6):
		await get_tree().process_frame
	var stage: Node = view._battlefield_ally_row.get_meta("visual_stage", null)
	assert_not_null(stage)
	assert_true(stage.has_meta("battle_hud"))
	var hud: Control = stage.get_meta("battle_hud")
	assert_eq(str(hud.name), "BattleHUD")
	assert_eq(hud.z_index, 20)

func test_batched_shapes_keep_the_engine_shapes_and_the_drawing_order() -> void:
	var f := _fixture("single", true)
	var ink = f.stage.musha_ink_director()
	var ci := Node2D.new()
	add_child_autofree(ci)
	var tris: PackedVector2Array = Ink._circle_tris()
	assert_eq(tris.size(), Ink.CIRCLE_SEGMENTS * 3, "the engine's draw_circle: 64 sides")
	assert_eq(tris[0], Vector2.ZERO)
	assert_almost_eq(tris[2].x, cos(TAU / 64.0), 1e-6)
	assert_almost_eq(tris[2].y, sin(TAU / 64.0), 1e-6)
	ink._circle(ci, Vector2(100, 50), 3.0, Ink.INK)
	ink._circle(ci, Vector2(104, 50), 2.0, Ink.INK)
	assert_eq(ink._batch.size(), 2 * tris.size(), "same place and colour: one batch")
	assert_eq(ink._batch[1], Vector2(103, 50), "the circle is moved and scaled, not changed")
	ink._circle(ci, Vector2(100, 50), 1.0, Ink.GLOSS)
	assert_eq(ink._batch.size(), tris.size(), "another colour: the earlier shapes were handed over first (order kept)")
	assert_eq(ink._batch_col, Ink.GLOSS)
	ink._polygon(ci, PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]), Ink.INK)
	assert_eq(ink._batch.size(), 6, "a square: the engine's two triangles")
	ink._flush()
	# 凹んだ形(L字)も、エンジンの draw_colored_polygon と同じ三角形分割になる
	var ell := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 6), Vector2(6, 6), Vector2(6, 20), Vector2(0, 20)])
	ink._polygon(ci, ell, Ink.INK)
	var expected := PackedVector2Array()
	for k in Geometry2D.triangulate_polygon(ell):
		expected.append(ell[k])
	assert_eq(ink._batch, expected)
	ink._flush()
	assert_true(ink._batch.is_empty())
	assert_null(ink._batch_ci)

func test_every_layer_hands_its_batched_shapes_to_the_engine_before_it_ends() -> void:
	var f := _fixture("single", true)
	var stage: RBMBattleStage = f.stage
	var ink = stage.musha_ink_director()
	stage.play_entry(f.entry, f.skill)
	stage._tween.custom_step(Ink.S_CUT + 0.1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(ink._batch.is_empty(), "nothing is left waiting after the layers are drawn")
	assert_null(ink._batch_ci)
	stage.cancel()

func test_remembered_landing_times_are_the_computed_ones() -> void:
	var f := _fixture("single", true)
	var ink = f.stage.musha_ink_director()
	var p0 := Vector2(300, 380)
	var v0 := Vector2(420, -260)
	var gy := 430.0
	assert_gt(ink._splash_pos(p0, v0, 0.95, 2.6, 700.0).y, gy, "this drop lands on the floor within its life")
	# 同じ式で直接求めた値
	var lo := 0.0
	var hi := 0.95
	for i in range(10):
		var mid := (lo + hi) * 0.5
		if ink._splash_pos(p0, v0, mid, 2.6, 700.0).y >= gy:
			hi = mid
		else:
			lo = mid
	var first: float = ink._landing_time(p0, v0, gy, 0.95, 2.6, 700.0)
	assert_eq(first, hi)
	assert_eq(ink._landing_time(p0, v0, gy, 0.95, 2.6, 700.0), first, "the remembered value is the same")
	assert_eq(ink._landing_time(Vector2(300, 480), v0, gy, 0.95, 2.6, 700.0), 1e9, "starts below the floor: never lands")
	assert_gt(ink._landing.size(), 0)
	ink.advance_attack("single", 0.0, Vector2.ZERO, {})
	assert_eq(ink._landing.size(), 0, "forgotten when an attack starts")
	ink.end_attack()

func test_awakened_single_strikes_after_the_charge() -> void:
	var f := _fixture("single", true)
	var stage: RBMBattleStage = f.stage
	stage.play_entry(f.entry, f.skill)
	var d = stage._skill_presentation
	assert_almost_eq(float(d.strike_at), Ink.S_CUT, 0.001, "the strike lands when the space splits")
	assert_almost_eq(float(d.track_at), Ink.SD, 0.001, "the completed track starts after the charge")
	stage.cancel()
