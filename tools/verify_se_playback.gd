extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var host := Control.new()
	root.add_child(host)
	var sound: Node = preload("res://src/bossmaker/rbm_audio.gd").for_owner(host)
	var results: Array = []
	for key in ["fire_impact_heavy", "ice_impact_heavy", "lightning_impact_heavy", "wind_impact_heavy"]:
		sound.play_sound(key)
		await create_timer(0.04).timeout
		var playing := false
		for player in sound._players:
			playing = playing or player.playing
		results.append({"key":key,"playing":playing})
		await create_timer(1.2).timeout
	print("SE_PLAYBACK ", JSON.stringify(results), " driver=", AudioServer.get_driver_name())
	sound.stop_all()
	quit(0 if results.all(func(r): return r.playing) else 1)
