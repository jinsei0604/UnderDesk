extends SceneTree
## 金環の聖獣／日蝕の獅皇（lion）の5技の時刻（T・ヒットストップ・長さ・最後の一撃・途中の当たり）を、
## 音の作り方（tools/lion/audio/build.mjs）へ渡すために tools/lion/audio/timing.json へ書き出す。
## 2026-11-13: 登場（intro。音は登場の再生の 0.34秒から鳴るので origin=0.34）・撃破（fall）・支援（support）も書き出す。
## 使い方: godot --headless --path . --script res://tools/lion/dump_lion_timing.gd
const FX_ROOT := "res://src/bossmaker/visuals/lion/rbm_lion_fx_%s.gd"
## 技のほかの演出: 名前 → 音の始まる時刻（演出の時刻で何秒の所が音の0秒か）
const EXTRA := {"intro": 0.34, "fall": 0.0, "fall_awakened": 0.0, "support": 0.0}

func _init() -> void:
	var moves := {}
	for move in RBMLionMotion.MOVES + EXTRA.keys():
		# 覚醒後の撃破は撃破と同じスクリプトの TA（覚醒後の時刻）
		var awakened_fall: bool = move == "fall_awakened"
		var script: GDScript = load(FX_ROOT % ("fall" if awakened_fall else move))
		var fx = script.new()
		if awakened_fall:
			fx.awakened = true
		var origin := float(EXTRA.get(move, 0.0))
		moves[move] = {"T": script.get_script_constant_map().get("TA" if awakened_fall else "T", {}), "stops": fx.stops(), "duration": fx.duration(), "impact": fx.impact(), "hits": fx.hits(), "real_duration": fx.unwarp(fx.duration()) - origin, "origin": origin}
		fx.free()
	var f := FileAccess.open(ProjectSettings.globalize_path("res://tools/lion/audio/timing.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"lion": moves}, "\t"))
	f.close()
	print("LION_TIMING_DONE")
	quit()
