extends GutTest
const Driver = preload("res://src/bossmaker/visuals/rbm_gentleman_presentation.gd")
const Timeline = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const TempoMap = preload("res://src/bossmaker/visuals/rbm_tempo_map.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
## 演出の契約は、事前読み込みが素材を読み終えた状態で検証する(QA-06。読み終えていない時の待ちは
## test_rbm_presentation_warmup.gd が検証する)。
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["gentleman"])

func after_all() -> void:
	_ready_assets.clear()
func _fixture(kind: String, attribute: String = "NEUTRAL", awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_gentleman"
	draft.boss_name = "異形紳士"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "異形紳士 skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "宇宙装備", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
	var id := draft.add_skill(spec)
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_gentleman")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and session.pending_ally_id() == 0 else {"type": "defend"}
		var entries := session.resolve_ally_action(action)
		for e in entries:
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)
	if kind in ["buff", "heal"]: skill.attribute = attribute
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}


func after_each() -> void:
	await get_tree().process_frame

func test_all_attributes_and_both_forms_deliver_one_impact_and_preserve_combat() -> void:
	for awakened in [false,true]:
		for kind in ["single","aoe"]:
			for attribute in ["NEUTRAL","FIRE","ICE","LIGHTNING","WIND"]:
				var f := _fixture(kind,attribute,awakened)
				var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
				var seen: Array=[]
				f.stage.impact.connect(func(e):seen.append(e))
				f.stage.play_entry(f.entry,f.skill)
				var d=f.stage._skill_presentation
				assert_true(d is Driver)
				assert_eq(d._vfx.attribute,attribute)
				# 戦闘テンポ（2026-10-16）: 命中は演出の時刻 impact_time のまま。実際の経過時間では、詰めた区間（Timeline.tempo）の分だけ早く着く。
				var hit: float=TempoMap.real_time_at(d.impact_time,d.duration,d.tempo())
				assert_lte(hit,d.impact_time)
				f.stage._tween.custom_step(hit-.01)
				assert_eq(seen.size(),0)
				f.stage._tween.custom_step(.02)
				assert_eq(seen.size(),1)
				f.stage._tween.custom_step(30)
				assert_eq(seen.size(),1)
				assert_eq(seen[0],f.entry)
				assert_false(f.stage.is_playing())
				assert_true(f.stage._visuals.boss.visible)
				assert_null(f.stage._skill_presentation)
				assert_eq(f.session.battle.snapshot(),snapshot)
				for key in f.stage._homes:assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_v8_frames_bow_hold_two_guns_and_support_motion() -> void:
	for kind in ["all","awakened_all"]:
		var data: Dictionary=Timeline.clip(kind)
		var last: Dictionary=data.shadows.back()
		assert_gt(float(data.bow.rise),float(last.hit))
		assert_gt(float(data.bow.bow),float(data.bow.all_visible))
		assert_eq(Timeline.frame(kind,float(last.hit)),"bow_down_15")
	for kind in ["awakened_single","awakened_all"]:
		var data: Dictionary=Timeline.clip(kind)
		assert_eq(data.host.size(),2)
		assert_ne(data.host[0].hand,data.host[1].hand)
		for e in data.host:
			assert_gt(Timeline.muzzle(kind,float(e.time),"far").distance_to(Timeline.muzzle(kind,float(e.time),"near")),12.0)
	assert_eq(Timeline.clip("buff").frames,Timeline.clip("heal").frames)
	assert_almost_eq(float(Timeline.clip("all").duration)+float(Timeline.clip("awakened_single").duration)+float(Timeline.clip("awakened_all").duration),30.3,.001)

func test_awakening_aura_and_rewind_restore_normal_form() -> void:
	var f:=_fixture("single")
	var seen: Array=[]
	f.stage.impact.connect(func(e):seen.append(e))
	f.stage.play_entry({"actor":"boss","action":"awakening"},{})
	var d=f.stage._skill_presentation
	assert_true(d is Driver)
	# 2026-11-20 作り直した覚醒（rbm_gentleman_fx_awaken.gd）: 姿が変わるのは演出の解放の時刻（前の版の 8.08 秒より早い）
	assert_not_null(d._fx)
	assert_almost_eq(d.impact_time,float(d._fx.impact()),.001)
	assert_lt(d.duration,8.0,"派手にして短く（前の版は12秒）")
	f.stage._tween.custom_step(d.impact_time-.05)
	assert_eq(f.stage._asset_ids.boss,"gentleman")
	f.stage._tween.custom_step(.10)
	assert_eq(f.stage._asset_ids.boss,"gentleman_awakened")
	assert_eq(seen.size(),0)
	f.stage._tween.custom_step(20)
	assert_eq(seen.size(),1)
	assert_true(f.stage._gentleman_aura.visible)
	assert_true(f.stage._visuals.boss.visible)
	var restored: Dictionary=f.session.battle.presentation_state()
	restored.is_awakened=false;f.stage.set_state(restored)
	assert_eq(f.stage._asset_ids.boss,"gentleman")
	assert_false(f.stage._gentleman_aura.visible)

func test_cancel_hides_effects_stops_audio_and_restores_body() -> void:
	for kind in ["single","aoe","buff","heal"]:
		var f:=_fixture(kind,"NEUTRAL",true)
		f.stage.play_entry(f.entry,f.skill)
		var d=f.stage._skill_presentation
		f.stage._tween.custom_step(1.0)
		assert_false(f.stage._visuals.boss.visible)
		f.stage.cancel()
		assert_false(d._audio.playing)
		assert_false(d._picture.visible)
		assert_true(f.stage._visuals.boss.visible)
		assert_eq(d._viewport.render_target_update_mode,SubViewport.UPDATE_DISABLED)

func test_support_and_counter_each_complete_one_resolved_entry() -> void:
	for kind in ["single","aoe","buff","heal"]:
		var f:=_fixture(kind,"WIND",true,kind in ["single","aoe"])
		var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		var d=f.stage._skill_presentation
		if kind=="single":
			var key: String=f.stage._targets[0]
			assert_eq(d.target,f.stage._foot(key)+Vector2(f.stage._guard_offsets.get(key,Vector2.ZERO)))
		f.stage._tween.custom_step(40)
		assert_eq(seen.size(),1)
		assert_false(f.stage.is_playing())
		assert_eq(f.session.battle.snapshot(),snapshot)

const Vfx = preload("res://src/bossmaker/visuals/rbm_gentleman_vfx.gd")
const Sheets = preload("res://src/bossmaker/visuals/rbm_gentleman_impact_sheets.gd")

func _sheet_stage(appearance: String = "appearance_gentleman", awakening: bool = true) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = appearance
	draft.boss_name = "異形紳士"
	draft.hp = 3000
	draft.atk = 1
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]: draft.add_party_character(id)
	var single := draft.add_skill({"name": "単体", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.0})
	draft.add_skill({"name": "全体", "type": "attack", "target": "all", "attribute": "ICE", "atk_multiplier": 1.0})
	draft.add_skill({"name": "回復", "type": "self_heal", "heal_amount": 200})
	if awakening:
		draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 10.0}], "condition_logic": "AND", "buff": {}, "heal": {}})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[single] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, appearance)
	stage.set_state(session.battle.presentation_state())
	return {"stage": stage, "session": session, "skill": single}

## Lets the stage's sheet keeper notice the boss and finish its background reads.
func _settle(stage: RBMBattleStage) -> Array:
	var sheets = stage._gentleman_impacts
	for i in 300:
		await get_tree().process_frame
		if sheets._boss_id == str(stage._asset_ids.boss) and sheets._pending.is_empty(): break
	var held: Array = sheets._held.keys()
	held.sort()
	return held

func _sheets(pairs: Array) -> Array:
	var paths: Array = []
	for pair in pairs: paths.append(Vfx.impact_path(pair[0], pair[1]))
	paths.sort()
	return paths

func test_impact_sheets_are_no_longer_read_for_any_form_or_attribute() -> void:
	# 2026-11-20: 命中は rbm_gentleman_vfx.gd の hit() が毎回描く（白い星形の衝撃の絵 impacts/*.png は使わない）。
	# 戦闘中に 2560x2240 の絵を持たないので、読み込み係は覚醒の前も後も何も持たない。
	assert_true(Vfx.IMPACT_STYLES.is_empty())
	var f := _sheet_stage()
	var stage: RBMBattleStage = f.stage
	assert_eq(await _settle(stage), [])
	var awakened: Dictionary = f.session.battle.presentation_state()
	awakened.is_awakened = true
	stage.set_state(awakened)
	assert_eq(await _settle(stage), [])
	for attribute in ["NEUTRAL", "FIRE", "ICE", "LIGHTNING", "WIND"]:
		stage._gentleman_impacts.request(attribute, "awakened_single")
	assert_true(stage._gentleman_impacts._held.is_empty())
	assert_true(stage._gentleman_impacts._pending.is_empty())

func test_impact_sheets_without_awakening_and_for_other_bosses() -> void:
	var f := _sheet_stage("appearance_gentleman", false)
	assert_eq(await _settle(f.stage), [])
	var other := _sheet_stage("appearance_slime")
	assert_eq(await _settle(other.stage), [])

func test_single_bullet_flies_along_the_gun() -> void:
	# 2026-11-20 ユーザー「銃弾の角度がおかしい」: 単体の弾は銃口から水平に対して3度以内。
	var f := _fixture("single")
	f.stage.play_entry(f.entry, f.skill)
	var d = f.stage._skill_presentation
	var v = d._vfx
	var mouth: Vector2 = v.duel_foot() + Timeline.gun(Timeline.AIM_POSE, "near").p
	var dest: Vector2 = v.aim(mouth, Vector2(v.foot(0).x + 4, v.line_y(0, mouth.x)))
	assert_lte(absf(dest.y - mouth.y), absf(dest.x - mouth.x) * Vfx.SLOPE + .01, "単体の弾の傾き")
	f.stage._tween.custom_step(40)

func test_ricochet_draws_a_pentagram_through_everyone_and_lands_once() -> void:
	# 2026-11-23 覚醒前の全体を「跳弾」に作り直し（ユーザー「狼と同じすごい速さで」「軌道は五芒星に。弾は画面の外へ行かず、
	# 最後に当たった所で止まる」「最後の着弾地点はパーティー側の誰かに」）: 弾は伸ばした腕の銃口から出て、星の頂点で一つ飛ばしに
	# 跳ね返って五芒星を描き、最初の頂点へ戻ると一番近い一人の胸へ食い込んで止まる。五本の線で四人全員を貫く。一本は狼の駆け抜けと同じくらい速い。小さな数字は一人3つまで、最後の一撃は1回。
	var f := _fixture("aoe")
	var seen: Array = []
	f.stage.impact.connect(func(e): seen.append(e))
	f.stage.play_entry(f.entry, f.skill)
	var d = f.stage._skill_presentation
	assert_true(d._fx != null and d._fx.get_script() == Driver.V2_FX["all"], "跳弾の演出")
	var fx = d._fx
	f.stage._tween.custom_step(fx.T.fire + 0.01)
	var path: Array = fx.path
	assert_eq(path.size(), fx.COUNT + 3, "銃口・最初の頂点・一つ飛ばしの五本・一人の胸")
	assert_lt(Vector2(path[0]).distance_to(fx.foot + fx.MUZZLE * fx.UNIT), 0.5, "弾は伸ばした腕の銃口から出る")
	assert_eq(Vector2(path[fx.COUNT + 1]), Vector2(path[1]), "五本で最初の頂点へ戻る（星が閉じる）")
	var lodged := -1
	for i in range(4):
		if Vector2(path.back()).distance_to(fx.target_chest(i)) < 0.5:
			lodged = i
	assert_gte(lodged, 0, "最後はパーティの一人の胸で止まる（画面の外へ行かない）")
	var verts := {}
	for k in range(1, fx.COUNT + 1):
		verts[Vector2(path[k])] = true
		assert_true(Rect2(0, 0, 640, 320).has_point(path[k]), "頂点 %d は画面の中" % k)
	assert_eq(verts.size(), 5, "五つの頂点")
	# 五芒星: 星の中心から見て、続く頂点は 144 度ずつ回る
	var c := Vector2.ZERO
	for v in verts:
		c += Vector2(v)
	c /= 5.0
	for k in range(1, fx.COUNT + 1):
		var turn := absf(wrapf((Vector2(path[k + 1]) - c).angle() - (Vector2(path[k]) - c).angle(), -PI, PI))
		assert_almost_eq(turn, deg_to_rad(144.0), deg_to_rad(12.0), "星の線 %d" % k)
	var bl: Dictionary = fx._bullet(fx.T.click - 0.01)
	assert_true(bool(bl.get("stopped", false)) and Vector2(bl.p) == Vector2(path.back()), "弾は一人の胸に食い込んで止まっている")
	var who := {}
	for ps in fx.passes:
		var k: int = ps.seg
		var a: Vector2 = path[k]
		var b: Vector2 = path[k + 1]
		var u := clampf((Vector2(ps.p) - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
		assert_lt(a.lerp(b, u).distance_to(ps.p), 0.6, "貫く所は星の線の上")
		who[int(ps.who)] = true
	for i in range(4):
		assert_true(who.has(i), "相手 %d も貫く" % i)
	assert_lte(fx.STEP, 0.08, "一本は狼の駆け抜けと同じくらい速い")
	var per := {}
	for h in fx.hits():
		assert_lt(float(h[0]), fx.impact(), "途中の当たりは最後の一撃より前")
		per[int(h[1])] = int(per.get(int(h[1]), 0)) + 1
	for i in per:
		assert_lte(int(per[i]), fx.MAX_SMALL, "小さな数字は一人3つまで")
	f.stage._tween.custom_step(40)
	assert_eq(seen.size(), 1, "最後の一撃は1回")

## 全体攻撃の場面: 味方の顔ぶれ（ids）と、攻撃の前に倒れている味方（downed: ids の番号）を変えられる
func _aoe_fixture(ids: Array, downed: Array = []) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_gentleman"
	draft.boss_name = "異形紳士"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ids: draft.add_party_character(id)
	var id := draft.add_skill({"name": "異形紳士 skill", "type": "attack", "target": "all", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	for i in downed:
		session.battle.party[int(i)].hp = 0
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_gentleman")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		for e in session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	return {"stage": stage, "session": session, "entry": entry, "skill": RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)}

func test_ricochet_follows_the_party_size_and_formation() -> void:
	# 2026-11-23 ユーザー「最後の跳弾が当たるのは、ちゃんと今のパーティの人数や配置に対応したものに。味方一人なら誰もいない所へ
	# 行かないように」: 1〜4人・倒れている味方がいる時も、弾が貫く相手と最後に食い込む相手は、今の攻撃の対象（生きている味方）だけ。
	for spec in [[["hero"], []], [["hero", "butler"], []], [["hero", "butler", "healer"], []], [["hero", "butler", "healer", "samurai"], [1, 2]]]:
		var ids: Array = spec[0]
		var downed: Array = spec[1]
		var label := "%d人（倒れている %d人）" % [ids.size(), downed.size()]
		var f := _aoe_fixture(ids, downed)
		assert_false(f.entry.is_empty(), label + ": 紳士の全体攻撃")
		f.stage.play_entry(f.entry, f.skill)
		var d = f.stage._skill_presentation
		var fx = d._fx
		f.stage._tween.custom_step(fx.T.fire + 0.01)
		var live: Array = []
		for i in range(4):
			if fx.present[i]:
				live.append(i)
		assert_eq(live.size(), ids.size() - downed.size(), label + ": 対象は生きている味方だけ")
		assert_has(live, fx.last_target, label + ": 最後は生きている味方の胸で止まる")
		assert_lt(Vector2(fx.path.back()).distance_to(fx.target_chest(fx.last_target)), 0.5, label + ": 止まる所はその味方の胸")
		var key: String = d._fx_keys[fx.last_target]
		assert_true(f.stage._targets.has(key) and not (f.stage._unit_state(key).get("is_downed", false)), label + ": 止まる味方は今の対象 %s" % key)
		var passed := {}
		for ps in fx.passes:
			assert_has(live, int(ps.who), label + ": 貫くのは生きている味方だけ")
			passed[int(ps.who)] = true
		for i in live:
			assert_true(passed.has(i), label + ": 味方 %d も貫く" % i)
		for k in range(1, fx.path.size()):
			assert_true(Rect2(0, 0, 640, 320).has_point(fx.path[k]), label + ": 弾の通る点 %d は画面の中" % k)
		f.stage._tween.custom_step(40)
		await get_tree().process_frame

func test_rebuilt_awakened_all_hits_everyone_once_and_cleans_up() -> void:
	# 2026-11-20 作り直した覚醒後の全体「深紅の終幕」（rbm_gentleman_fx_post_all.gd）: 途中の弾は小さな数字、最後の一撃で1回だけ impact。
	var f := _fixture("aoe", "FIRE", true)
	var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
	var seen: Array = []
	f.stage.impact.connect(func(e): seen.append(e))
	f.stage.play_entry(f.entry, f.skill)
	var d = f.stage._skill_presentation
	assert_eq(d.action_kind, "awakened_all")
	assert_not_null(d._fx)
	assert_eq(d._audio.stream.resource_path, "res://assets_bossmaker/audio/gentleman/awakened_all.wav")
	assert_almost_eq(d._audio.stream.get_length(), d.duration, .05, "音の長さ＝演出の長さ")
	var plan: Dictionary = d._v2_hit_plan()
	assert_eq(plan.size(), 4, "途中の弾は四人全員に当たる")
	f.stage._tween.custom_step(d.impact_time - .01)
	assert_eq(seen.size(), 0)
	f.stage._tween.custom_step(.02)
	assert_eq(seen.size(), 1)
	f.stage._tween.custom_step(30)
	await get_tree().process_frame
	assert_eq(seen.size(), 1)
	assert_false(f.stage.is_playing())
	assert_true(f.stage._visuals.boss.visible)
	for key in f.stage._party_keys:
		assert_eq(f.stage._visuals[key].self_modulate, Color.WHITE, "味方の暗さを戻す")
	assert_eq(f.session.battle.snapshot(), snapshot)

func test_each_attack_draws_exactly_the_sheets_kept_for_it() -> void:
	for setup in [["single", false], ["single", true], ["aoe", true], ["aoe", false]]:
		var f := _fixture(setup[0], "WIND", setup[1])
		var stage: RBMBattleStage = f.stage
		await _settle(stage)
		var kept: Array = stage._gentleman_impacts._held.keys()
		stage.play_entry(f.entry, f.skill)
		var d = stage._skill_presentation
		# The presentation frees itself when it ends; keep what it drew.
		var used: Dictionary = d._vfx._impact_textures
		var action: String = d.action_kind
		var duration: float = d.duration
		var t := 0.0
		while stage.is_playing() and t < duration:
			stage._tween.custom_step(1.0 / 30)
			t += 1.0 / 30
			await get_tree().process_frame
		var drawn: Array = used.keys()
		drawn.sort()
		var expected: Array = Vfx.IMPACT_STYLES.get(action, []).duplicate()
		expected.sort()
		assert_eq(drawn, expected, action)
		for style in drawn: assert_true(kept.has(Vfx.impact_path("WIND", style)), action + " " + style)
		if stage.is_playing(): stage._tween.custom_step(30)
		assert_false(stage.is_playing())

func test_boss_catalog_art_and_fixed_background() -> void:
	const Backgrounds=preload("res://src/bossmaker/visuals/rbm_battle_backgrounds.gd")
	assert_eq(RBMCreatorAppearanceCatalog.by_id("appearance_gentleman").name,"異形紳士")
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening("appearance_gentleman"))
	assert_eq(RBMVisualAssets.boss_asset("appearance_gentleman"),"gentleman")
	assert_true(RBMVisualAssets.has_awakened_design("gentleman"))
	for id in ["gentleman","gentleman_awakened"]:
		assert_true(RBMVisualAssets.has_pose_frames(id))
		for time in ["day","night"]:assert_eq(Backgrounds.path_for(id,time),"res://assets_bossmaker/battle/backgrounds/gentleman/background.png")
	var saved:=RBMLocale.current_locale()
	RBMLocale.set_locale("en")
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_gentleman"),"Faceless Gentleman")
	RBMLocale.set_locale(saved)
