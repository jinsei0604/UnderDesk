extends SceneTree
## 熔鉱炉の番人／噴界炉の巨神（lava）の技・登場・支援・撃破の時刻（T・ヒットストップ・長さ・最後の一撃・途中の当たり）を、
## 音の作り方（tools/lava/audio/build.mjs）へ渡すために tools/lava/audio/timing.json へ書き出す（試作の dump_timing.gd と同じ形）。
## 登場の音は演出の0秒から鳴る（rbm_intro_lava.gd の LEAD で鳴らす）。
## 使い方: godot --headless --path . --script res://tools/lava/dump_lava_timing.gd
const FX := "res://src/bossmaker/visuals/lava/rbm_lava_fx_%s.gd"
## 音の作り方の技の名前 → [本番のエフェクト, 覚醒後か]
const MOVES := {"pre_single": ["pre_single", false], "pre_all": ["pre_all", false], "awaken": ["awaken", false], "post_single": ["post_single", true],
	"post_all": ["post_all", true], "intro": ["intro", false], "pre_support": ["support", false], "post_support": ["support", true],
	"pre_defeat": ["fall", false], "post_defeat": ["fall_awakened", true]}

func _init() -> void:
	var out := {}
	for move in MOVES:
		var script: GDScript = load(FX % str(MOVES[move][0]))
		var fx = script.new()
		if str(MOVES[move][0]) == "support":
			fx.awakened = bool(MOVES[move][1])
		# 継いだ台本は自分の時刻表 TP を持つ（無ければ T）
		var cm := script.get_script_constant_map()
		if not cm.has("T") and not cm.has("TP") and script.get_base_script() != null:
			cm = script.get_base_script().get_script_constant_map()
		out[move] = {"T": cm.get("TP", cm.get("T", {})), "stops": fx.stops(), "duration": fx.duration(), "impact": fx.impact(), "hits": fx.hits(), "real_duration": fx.unwarp(fx.duration())}
		fx.free()
	var f := FileAccess.open(ProjectSettings.globalize_path("res://tools/lava/audio/timing.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("LAVA_TIMING_DONE")
	quit()
