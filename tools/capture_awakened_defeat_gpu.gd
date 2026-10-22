extends "res://tools/verify_awakened_defeat_gpu.gd"
## Live production UI capture. Offline challenge fixture, real resolved awakening/final hit/result.
## --bosses=musha (or astronaut/gentleman/dragon), synchronized by external record.trigger.
var recording: AudioEffectRecord
var capture_start := 0
var capture_duration := 0.0
var marker_layer: CanvasLayer

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	subject = _arg("bosses","musha")
	tree.root.size = Vector2i(1280,720)
	tree.root.content_scale_size = Vector2i(1280,720)
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	tree.root.title = "MC Awakened Defeat Integrated"
	TranslationServer.set_locale("ja")
	DirAccess.make_dir_recursive_absolute(out)
	awakened_case = true
	await _run(subject,"challenge",false,false)
	var failed := checks.filter(func(c): return not c.ok).size()
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"boss":subject,"duration":capture_duration,"checks":checks,"failed":failed},"\t"))
	print("INTEGRATED_CAPTURE_DONE failed=",failed)
	_gpu_verification_completed = true
	return 0 if failed == 0 else 1

func _pace(seconds: float) -> void:
	await super._pace(seconds)
	if not is_equal_approx(seconds,0.8): return
	FileAccess.open(out.path_join("ready.txt"),FileAccess.WRITE).store_string("ready")
	while not FileAccess.file_exists(out.path_join("record.trigger")): await tree.process_frame
	marker_layer = CanvasLayer.new()
	marker_layer.layer = 60
	tree.root.add_child(marker_layer)
	var mark := ColorRect.new()
	mark.position = Vector2(8,8)
	mark.size = Vector2(8,8)
	mark.color = Color.GREEN
	marker_layer.add_child(mark)
	recording = AudioEffectRecord.new()
	recording.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,recording)
	recording.set_recording_active(true)
	capture_start = Time.get_ticks_usec()
	await tree.create_timer(0.5).timeout
	mark.hide()

func _shutdown() -> void:
	if recording != null:
		await tree.create_timer(1.0).timeout
		recording.set_recording_active(false)
		recording.get_recording().save_to_wav(out.path_join("realtime-audio.wav"))
		AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
		capture_duration = (Time.get_ticks_usec()-capture_start)/1000000.0
		marker_layer.queue_free()
	await super._shutdown()
