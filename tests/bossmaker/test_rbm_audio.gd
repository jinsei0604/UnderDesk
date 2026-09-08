extends GutTest
const Sound = preload("res://src/bossmaker/rbm_audio.gd")
const Motions = preload("res://src/bossmaker/visuals/rbm_motion_catalog.gd")
const Catalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")

func test_approved_variants_load_as_wav() -> void:
	for key in Catalog.FILES:
		assert_true(load(Catalog.FILES[key]) is AudioStreamWAV, key)

func test_normal_attack_ignores_character_affinity() -> void:
	for asset in ["hero", "butler", "healer", "samurai", "tank"]:
		var entry := {"actor": 0, "action":"attack"}
		var result := Sound.event_key(entry, Motions.profile(entry), asset, "impact")
		assert_true(result.begins_with("neutral_"), asset)

func test_boss_attributes_and_aoe_share_one_principal_hit() -> void:
	for attr in ["FIRE", "ICE", "LIGHTNING", "WIND", "NEUTRAL"]:
		for target in ["single", "all"]:
			var entry := {"actor":"boss", "action":"skill", "skill_id":"custom"}
			var skill := {"type":"attack", "attribute":attr, "target":target}
			var result := Sound.event_key(entry, Motions.profile(entry, skill), "dragon", "impact")
			assert_eq(result, "boss_impact_mass" if attr == "NEUTRAL" else attr.to_lower()+"_impact_heavy")

func test_support_and_counter_stance_do_not_attack() -> void:
	var expected := {"healer_heal_single":"heal_hp", "healer_heal_all":"heal_hp", "butler_sp_gift":"heal_sp", "healer_sp_all":"heal_sp", "samurai_counter":"guard_set", "tank_guard_swap":"guard_set"}
	for id in expected:
		var entry := {"actor":0, "action":"skill", "skill_id":id}
		assert_eq(Sound.event_key(entry, Motions.profile(entry), "samurai", "impact"),expected[id])
	assert_eq(Sound.event_key({"failed":true}, {"kind":"failed"}, "hero", "impact"), "")

func test_real_stage_counter_and_cancel_are_presentation_only() -> void:
	var stage := preload("res://src/bossmaker/visuals/rbm_battle_stage.gd").new()
	add_child_autofree(stage)
	var audio: Node = stage.get_node("RBMAudio")
	audio.muted = true
	stage._entry = {"actor":"boss", "action":"attack", "target":1, "counter":true}
	stage._profile = Motions.profile(stage._entry)
	stage._actor = "boss"
	stage._counters.assign(["1"])
	var before: Dictionary = stage._entry.duplicate(true)
	stage._strike()
	assert_eq(audio.history.count("wind_impact_heavy"),0)
	stage._counter_impact()
	assert_eq(audio.history.count("wind_impact_heavy"),1)
	assert_eq(stage._entry,before)
	stage.cancel()
	assert_false(stage.is_playing())
	for player in audio._players: assert_false(player.playing)
