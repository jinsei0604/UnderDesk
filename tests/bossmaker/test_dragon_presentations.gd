extends GutTest
## Limited integration coverage for the dragon's production presentation contract.
## 2026-11-26（ユーザー承認）: 攻撃4種は新しい作り（dragon/rbm_dragon_attack_host.gd）。噛みつき→急降下「天翔墜撃」
## （動く前に咆哮し、着弾の後は咆哮しない）、息吹・覚醒後の集中の息吹は口の先の玉からあふれて何回も当たる、
## 隕石の最後の巨大隕石は渦の奥から止まらずにゆっくり迫る。強化・回復は今までどおり（Motion・Body・VFX）。
const Driver = preload("res://src/bossmaker/visuals/rbm_dragon_presentation.gd")
const Host = preload("res://src/bossmaker/visuals/dragon/rbm_dragon_attack_host.gd")
const FxDive = preload("res://src/bossmaker/visuals/dragon/rbm_dragon_fx_dive.gd")
const FxBreath = preload("res://src/bossmaker/visuals/dragon/rbm_dragon_fx_breath.gd")
const FxMeteors = preload("res://src/bossmaker/visuals/dragon/rbm_dragon_fx_meteors.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
## 演出の契約は、事前読み込みが素材を読み終えた状態で検証する(QA-06。読み終えていない時の待ちは
## test_rbm_presentation_warmup.gd が検証する)。
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["dragon"])

func after_all() -> void:
	_ready_assets.clear()

func _fixture(kind: String, attribute: String = "NEUTRAL", awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_dragon"
	draft.boss_name = "Dragon QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "Dragon QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "Dragon support", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
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
	stage.configure(session.battle, "appearance_dragon")
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

func _expected_action(kind: String, awakened: bool) -> String:
	if kind in ["buff", "heal"]: return kind
	return ("focused_breath" if kind == "single" else "meteors") if awakened else ("bite" if kind == "single" else "breath")

func _assert_restored(stage: RBMBattleStage, awakened: bool) -> void:
	assert_null(stage._skill_presentation)
	assert_false(stage.is_playing())
	assert_true(stage._visuals["boss"].visible)
	assert_eq(stage._visuals["boss"].scale, Vector2.ONE)
	assert_eq(stage._visuals["boss"].pivot_offset, Vector2.ZERO)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened" if awakened else "dragon")
	for key in stage._homes: assert_eq(stage._visuals[key].position, stage._homes[key])
	for key in stage._party_keys: assert_eq(stage._visuals[key].self_modulate, Color.WHITE)

func _first_target(stage: RBMBattleStage) -> String:
	for key in stage._targets:
		if key != "boss": return str(key)
	return ""

func test_real_four_attack_actions_all_five_colors_impact_and_cleanup() -> void:
	for awakened in [false, true]:
		for kind in ["single", "aoe"]:
			for attribute in Palette.COLORS:
				var f := _fixture(kind, attribute, awakened)
				assert_false(f.entry.is_empty())
				var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
				var seen: Array = []
				f.stage.impact.connect(func(e): seen.append(e))
				f.stage.play_entry(f.entry, f.skill)
				var d = f.stage._skill_presentation
				assert_true(d is Driver)
				assert_eq(d.kind, kind)
				assert_eq(d.form, "awakened" if awakened else "normal")
				assert_eq(d.action_kind, _expected_action(kind, awakened))
				var host = d._host
				assert_true(is_instance_valid(host), "The four attacks play through the new attack host")
				assert_eq(host.action, Driver.HOST_ACTIONS[d.action_kind])
				assert_eq(host._fx.attr, attribute)
				assert_eq(host._fx.awakened, awakened)
				assert_true(RBMDragonFxBase.RAMPS.has(attribute), "Every attack attribute has its own color ramp")
				assert_eq(host._fx.col(5), Color(str(RBMDragonFxBase.RAMPS[attribute][5])))
				assert_eq(d._body, host._body, "The awakened aura follows the attack body")
				assert_false(f.stage._visuals["boss"].visible)
				f.stage._tween.custom_step(d.impact_time - .01)
				assert_eq(seen.size(), 0)
				assert_almost_eq(float(d.age), d.impact_time - .01, .001, "The presentation clock is the attack host's clock")
				f.stage._tween.custom_step(.02)
				assert_eq(seen.size(), 1)
				assert_eq(seen[0], f.entry)
				if kind == "aoe": assert_eq(f.entry.get("hits", {}).size(), 4)
				f.stage._tween.custom_step(10)
				assert_eq(seen.size(), 1)
				_assert_restored(f.stage, awakened)
				assert_eq(f.session.battle.snapshot(), snapshot)

func test_support_uses_identical_body_motion_in_both_forms() -> void:
	for awakened in [false, true]:
		var reference: Array = []
		for kind in ["buff", "heal"]:
			var f := _fixture(kind, "ICE" if kind == "buff" else "FIRE", awakened)
			var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			assert_true(d is Driver)
			assert_eq(d.action_kind, kind)
			assert_false(is_instance_valid(d._host), "Support keeps the approved roar motion")
			var samples: Array = []
			var step: float = d.duration / 61.0
			for i in range(60):
				f.stage._tween.custom_step(step)
				samples.append(d._body.state.duplicate(true))
			if reference.is_empty(): reference = samples
			else: assert_eq(samples, reference, "The body uses the same roar samples for buff and heal")
			f.stage._tween.custom_step(10)
			assert_eq(seen.size(), 1)
			_assert_restored(f.stage, awakened)
			assert_eq(f.session.battle.snapshot(), snapshot)

## 2026-11-26 ユーザー「着弾の後の咆哮はいらない。するなら動く前に咆哮して攻撃する」
func test_dive_roars_first_then_dives_onto_the_target_and_flies_home() -> void:
	var f := _fixture("single")
	var seen: Array = []
	f.stage.impact.connect(func(e): seen.append(e))
	f.stage._sound.history.clear()
	f.stage.play_entry(f.entry, f.skill)
	var d = f.stage._skill_presentation
	var host = d._host
	assert_eq(host.action, "dive")
	assert_eq(d.duration, float(FxDive.T.end))
	assert_eq(d.impact_time, float(FxDive.T.hit))
	var home: Vector2 = f.stage._foot("boss")
	var key := _first_target(f.stage)
	var target_foot: Vector2 = f.stage._foot(key) + Vector2(f.stage._guard_offsets.get(key, Vector2.ZERO))
	f.stage._tween.custom_step(0.3)
	assert_eq(host._body.state.pose, 4, "Roars at home before moving")
	assert_eq(host._body.state.foot, home)
	assert_eq(f.stage._sound.history.count("dragon_roar"), 1, "The roar is heard before the attack")
	f.stage._tween.custom_step(float(FxDive.T.gone) + 0.1 - 0.3)
	assert_false(host._body.visible, "Out of sight above the battlefield")
	assert_eq(seen.size(), 0)
	f.stage._tween.custom_step(float(FxDive.T.hit) - (float(FxDive.T.gone) + 0.1) + 0.01)
	assert_eq(seen.size(), 1)
	assert_true(host._body.visible)
	assert_lt(Vector2(host._body.state.foot).distance_to(target_foot + Vector2(FxDive.LAND_DX, 0)), 2.0, "Lands right next to the target")
	var t := float(FxDive.T.hit) + 0.01
	while t < float(FxDive.T.end) - 0.05:
		f.stage._tween.custom_step(0.05)
		t += 0.05
		assert_ne(host._body.state.pose, 4, "No roar after landing (t=%.2f)" % t)
	f.stage._tween.custom_step(10)
	assert_eq(seen.size(), 1)
	assert_eq(f.stage._sound.history.count("dragon_roar"), 1)
	_assert_restored(f.stage, false)

func test_cancel_during_windup_strike_and_return_then_replay() -> void:
	for awakened in [false, true]:
		for kind in ["single", "aoe", "buff", "heal"]:
			for progress in [.16, .51, .82]:
				var f := _fixture(kind, "NEUTRAL", awakened)
				var seen: Array = []
				f.stage.impact.connect(func(e): seen.append(e))
				f.stage.play_entry(f.entry, f.skill)
				var d = f.stage._skill_presentation
				f.stage._tween.custom_step(d.duration * progress)
				var count := seen.size()
				f.stage.cancel()
				await get_tree().process_frame
				assert_false(is_instance_valid(d))
				assert_eq(seen.size(), count)
				_assert_restored(f.stage, awakened)
				f.stage.play_entry(f.entry, f.skill)
				f.stage._tween.custom_step(10)
				assert_eq(seen.size(), count + 1)
				_assert_restored(f.stage, awakened)

func test_cover_aims_at_redirected_target_in_both_forms() -> void:
	for awakened in [false, true]:
		var f := _fixture("single", "ICE", awakened)
		var state: Dictionary = f.stage._state.duplicate(true)
		state.party["1"].protecting_ally_id = 0
		f.stage._state = state
		var entry := {"actor": "boss", "action": "attack", "target": 1, "visual_original_target": 0, "amount": 20, "attribute": "ICE"}
		f.stage.play_entry(entry)
		assert_eq(f.stage._guards, ["1"])
		var d = f.stage._skill_presentation
		assert_true(d is Driver)
		assert_eq(d.action_kind, _expected_action("single", awakened))
		var covered: Vector2 = f.stage._foot("1") + Vector2(f.stage._guard_offsets["1"])
		assert_lt((Vector2(d._host._fx.targets[0]) * 2.0).distance_to(covered), 2.0, "The actual covered ally receives the dive/breath")
		if not awakened:
			f.stage._tween.custom_step(d.impact_time)
			assert_lt(Vector2(d._host._body.state.foot).distance_to(covered + Vector2(FxDive.LAND_DX, 0)), 2.0, "The dive lands next to the covering ally")
		f.stage.cancel()
		_assert_restored(f.stage, awakened)

func test_real_counters_finish_once_and_preserve_battle_state() -> void:
	for awakened in [false, true]:
		for kind in ["single", "aoe"]:
			var f := _fixture(kind, "FIRE", awakened, true)
			var counter_count := int(f.entry.get("counter", false))
			for hit in f.entry.get("hits", {}).values(): counter_count += int(hit.get("counter", false))
			assert_eq(counter_count, 1)
			var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			f.stage._tween.custom_step(d.impact_time + .05)
			assert_eq(seen.size(), 0, "Counter entries emit only after the complete combined action")
			for i in range(200):
				if not f.stage.is_playing(): break
				f.stage._tween.custom_step(.1)
			assert_eq(seen.size(), 1)
			assert_eq(seen[0], f.entry)
			_assert_restored(f.stage, awakened)
			assert_false(f.stage._samurai_wind.visible)
			assert_eq(f.session.battle.snapshot(), snapshot)

func test_ranged_sfx_play_once_independent_of_attribute_and_stop_on_cancel() -> void:
	for spec in [["aoe",false,"dragon_normal_breath",4.05],["single",true,"dragon_awakened_breath",4.45],["aoe",true,"dragon_awakened_meteors",6.65]]:
		for attribute in Palette.COLORS:
			var f := _fixture(spec[0],attribute,spec[1])
			f.stage._sound.history.clear()
			f.stage.play_entry(f.entry,f.skill)
			var d = f.stage._skill_presentation
			assert_eq(f.stage._sound.history,[spec[2]],"One attack-specific clip, without attribute cast")
			assert_almost_eq(d.duration,float(spec[3]),.001,"The new presentation keeps the clip's length")
			var stream: AudioStreamWAV=f.stage._sound._cache[spec[2]]
			assert_almost_eq(stream.get_length(),spec[3],.001)
			assert_true(stream.stereo)
			assert_eq(stream.loop_mode,AudioStreamWAV.LOOP_DISABLED)
			f.stage._tween.custom_step(2.9)
			assert_eq(f.stage._sound.history,[spec[2]],"Release/impact do not layer generic attribute SFX")
			f.stage.cancel()
			for player in f.stage._sound._players: assert_false(player.playing)
			f.stage.play_entry(f.entry,f.skill)
			assert_eq(f.stage._sound.history,[spec[2],spec[2]],"Replay starts exactly one fresh clip")
			f.stage.cancel()

func test_dive_uses_the_common_attack_sounds_and_one_roar() -> void:
	for attribute in Palette.COLORS:
		var f := _fixture("single",attribute)
		f.stage._sound.history.clear()
		f.stage.play_entry(f.entry,f.skill)
		f.stage._tween.custom_step(10)
		assert_eq(f.stage._sound.history.count("dragon_roar"),1)
		for clip in Host.RANGED_SOUNDS.values(): assert_false(f.stage._sound.history.has(clip))
		_assert_restored(f.stage,false)

## 2026-11-26 ユーザー「竜の腹からではなく、口元の先に丸い球体を作ってそこから溢れ出たように」
func test_breath_overflows_from_an_orb_at_the_mouth_tip_and_reaches_past_the_left_edge() -> void:
	for awakened in [false,true]:
		var f := _fixture("single" if awakened else "aoe","ICE",awakened)
		f.stage.play_entry(f.entry,f.skill)
		var d = f.stage._skill_presentation
		var host = d._host
		var fx = host._fx
		f.stage._tween.pause()
		for elapsed in [1.1,1.6,2.1]:
			host._advance(elapsed)
			var mouth: Vector2 = fx.mouth
			var ball: Vector2 = fx.orb.position+Vector2(48,48)
			assert_true(fx.orb.visible)
			assert_almost_eq(ball.distance_to(mouth),24.0 if awakened else 22.0,.01,"The orb sits just in front of the mouth")
			assert_lt(ball.x,mouth.x,"In front of the mouth, toward the party")
			var root: Node2D = fx.outer.get_parent()
			assert_lt(root.position.distance_to(ball),.001,"The stream overflows from the orb")
			var tip: Vector2 = root.position+Vector2.from_angle(root.rotation)*fx.outer.size.x
			assert_lt(tip.x,-20.0,"The stream reaches past the left edge")
		host._advance(float((FxBreath.TF if awakened else FxBreath.TN).gone)+.3)
		assert_false(fx.orb.visible,"The orb shrinks away with the stream")
		f.stage.cancel()

## 2026-11-26 ユーザー「ブレスの当たり判定1回はおかしいから複数回あたるように」（覚醒後の単体も同じやり方）
func test_breaths_hit_again_and_again_then_total_on_the_final_blow() -> void:
	for awakened in [false,true]:
		var f := _fixture("single" if awakened else "aoe","FIRE",awakened)
		var seen: Array=[]
		var partials: Array=[]
		f.stage.impact.connect(func(e): seen.append(e))
		f.stage.partial_hits.connect(func(_e,landed): partials.append(landed))
		f.stage.play_entry(f.entry,f.skill)
		var d = f.stage._skill_presentation
		var plan: Dictionary = d._host._fx.multi_plan()
		assert_eq(plan.size(),1 if awakened else 4)
		for slot in plan:
			var ticks: Array = plan[slot]
			assert_gte(ticks.size(),3,"Hits again and again while the stream touches")
			for k in range(1,ticks.size()): assert_almost_eq(float(ticks[k])-float(ticks[k-1]),FxBreath.TICK,.001)
			assert_lt(float(ticks.back()),d.impact_time)
			# 2026-11-27 案B: 数字と HP の更新は4人同時（一番先に当たる人の時刻）。当たりの見た目のずらしは残す
			assert_eq(ticks,plan[0],"Small numbers for everyone land together")
			assert_eq((d._host._fx.ticks(int(slot)) as Array).size(),ticks.size(),"Each ally is visibly hit as many times as numbers appear")
		if not awakened:
			assert_almost_eq(float(d._host._fx.ticks(3)[0])-float(d._host._fx.ticks(0)[0]),.105,.001,"The flames still reach the allies one after another")
		var t := 0.0
		while t<d.impact_time-.06:
			f.stage._tween.custom_step(.05)
			t+=.05
		assert_eq(seen.size(),0)
		assert_gt(partials.size(),2,"Small hits before the final blow")
		f.stage._tween.custom_step(10)
		assert_eq(seen.size(),1,"One combat impact")
		_assert_restored(f.stage,awakened)

func test_meteor_final_impact_precedes_cleanup_and_damage_stays_single() -> void:
	var f := _fixture("aoe","FIRE",true)
	var seen: Array=[]
	var partials: Array=[]
	f.stage.impact.connect(func(entry): seen.append(entry))
	f.stage.partial_hits.connect(func(_entry,landed): partials.append(landed))
	f.stage.play_entry(f.entry,f.skill)
	var d = f.stage._skill_presentation
	var fx = d._host._fx
	assert_eq(fx.meteors.size(),33)
	var last: Dictionary=fx.meteors.back()
	assert_true(bool(last.big))
	assert_almost_eq(float(last.arrival),4.15,.001)
	assert_almost_eq(d.impact_time,4.15,.001)
	f.stage._tween.custom_step(3.0)
	assert_true(f.stage.is_playing())
	# 2026-10-23（ユーザーの決定）: 小さな隕石は小さなダメージの数字と HP の表示だけ（partial_hits）。命中の確定は巨大隕石で1回。
	assert_eq(seen.size(),0,"small meteors only show partial hits")
	assert_gt(partials.size(),0)
	f.stage._tween.custom_step(float(last.arrival)-3.0+.05)
	assert_eq(seen.size(),1,"Repeated visual impacts do not repeat damage")
	assert_gt(d.duration,float(last.arrival)+1.7)
	f.stage._tween.custom_step(10)
	assert_eq(seen.size(),1)
	_assert_restored(f.stage,true)

## 2026-11-26 ユーザー「落下速度をもっと遅く・やばいものが来た感じ」→「渦から出始める所をもっとゆっくり」→「途中で止まって見える」
## → 渦の奥に現れてから着弾まで、ゆっくり動き出して、だんだん速くなる一本の動き（途中で止まらない）。着弾は音に合わせた 4.15 秒のまま。
## 進み具合の元の時刻は RBMHeroFx.ramp()（smoothstep）なので、現れた直後と着弾の直前の一瞬はなめらかに緩む（承認された動画のまま）。
## 止まらないことは、渦から出た後（現れてから 0.2 秒）から着弾の 0.1 秒前までで確かめる。
func test_giant_meteor_emerges_slowly_and_never_stops_on_the_way_down() -> void:
	var fx = FxMeteors.new()
	assert_almost_eq(fx._giant_f(FxMeteors.GIANT_START),0.0,1e-6)
	assert_almost_eq(fx._giant_f(FxMeteors.FINAL),1.0,1e-6)
	assert_lt(FxMeteors.GIANT_START,2.5,"Appears in the vortex well before the impact")
	assert_between(fx._giant_f(FxMeteors.GIANT_START+.5),.02,.08,"Comes out of the vortex slowly")
	var prev: float = fx._giant_f(FxMeteors.GIANT_START+.2)
	var prev_r: float = fx._giant_r(FxMeteors.GIANT_START+.2)
	var t: float = FxMeteors.GIANT_START+.3
	while t<=FxMeteors.FINAL-.1+1e-6:
		var now: float = fx._giant_f(t)
		var r: float = fx._giant_r(t)
		assert_gt(now-prev,.004,"Keeps moving at t=%.2f" % t)
		assert_gt(r,prev_r,"Keeps growing at t=%.2f" % t)
		prev=now
		prev_r=r
		t+=.1
	fx.free()

func test_awakened_aura_follows_the_attack_body() -> void:
	var f := _fixture("single","FIRE",true)
	f.stage.play_entry(f.entry,f.skill)
	var d = f.stage._skill_presentation
	f.stage._tween.custom_step(1.5)
	var aura = f.stage._dragon_aura
	aura._update_anchors()
	assert_true(aura.visible)
	assert_false(aura._body_hidden)
	assert_eq(aura._foot,Vector2(d._host._body.foot_point())+d.position)
	f.stage._tween.custom_step(10)
	_assert_restored(f.stage,true)

## 重さの改善（2026-11-27）: 画面全体の処理（post.gdshader）は、効果がある間だけ出す。効果が無い時のシェーダーは
## 画面をそのまま返すので、消しても絵は変わらない（tools/verify_dragon_gpu.gd で画素も比べる）。
func test_post_processing_runs_only_while_it_changes_the_picture() -> void:
	assert_false(Host.post_active({"post":{"flash":0.0,"vig":0.0,"impact":0.0,"tint":Color.WHITE},"rings":[]}))
	assert_true(Host.post_active({"post":{"vig":.01},"rings":[]}))
	assert_true(Host.post_active({"post":{"tint":Color(1,.9,.9)},"rings":[]}))
	assert_true(Host.post_active({"post":{},"rings":[Vector4(1,1,1,1)]}))
	var f := _fixture("aoe","FIRE",false)
	f.stage.play_entry(f.entry,f.skill)
	var host = f.stage._skill_presentation._host
	f.stage._tween.pause()
	host._advance(float(FxBreath.TN.release)+.02)
	assert_true(host._post.visible,"The release flash uses it")
	host._advance(1.6)
	assert_false(host._post.visible,"Nothing to process while the stream flows")
	host._advance(float(FxBreath.TN.release)+.03)
	assert_true(host._post.visible)
	f.stage.cancel()
	_assert_restored(f.stage,false)
