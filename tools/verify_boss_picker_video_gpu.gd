extends RefCounted
var _gpu_verification_completed := false
var tree: SceneTree
var output := ""
var errors: Array = []
var samples: Array = []

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	output = directory
	var sample_frames := 60 if "--smoke" in OS.get_cmdline_user_args() else 840
	DirAccess.make_dir_recursive_absolute(output)
	tree.root.content_scale_size = Vector2i(1280,720)
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	RBMLocalStageRepository.set_stages_dir_for_testing("user://preview_video_qa")
	var root := RBMGameRoot.new()
	tree.root.add_child(root)
	await frames(4)
	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	root.creator_entry._on_choose_advanced_mode_pressed()
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.boss_name = "Preview QA"
	main.draft.hp = 2000
	main.draft.atk = 40
	main.draft.spd = 50
	main.draft.add_skill({"name":"Attack", "type":"attack", "target":"single", "attribute":"NEUTRAL", "atk_multiplier":1.0})
	for id in ["hero", "butler", "healer", "samurai"]: main.draft.add_party_character(id)
	main.go_to_step(1)
	main.open_appearance_picker()
	await frames(5)
	var picker: RBMCreatorAppearancePicker = main._appearance_picker
	var selected_before := main.draft.appearance_id
	for resolution in [Vector2i(1280,720), Vector2i(1920,1080)]:
		tree.root.size = resolution
		await frames(10)
		for boss in ["slime", "musha", "astronaut", "ghost", "dragon"]:
			var select_start := Time.get_ticks_usec()
			picker.select("appearance_" + boss)
			var select_ms := float(Time.get_ticks_usec()-select_start)/1000.0
			for awakened in ([false, true] if boss in ["musha", "astronaut"] else [false]):
				var form_start := Time.get_ticks_usec()
				if awakened: picker._on_preview_toggle_pressed("appearance_" + boss)
				var form_ms := float(Time.get_ticks_usec()-form_start)/1000.0
				var tag := "%d_%s_%s" % [resolution.x, boss, "awakened" if awakened else "normal"]
				var startup: Array[float] = []
				var startup_last := Time.get_ticks_usec()
				for i in 10:
					await tree.process_frame
					var now := Time.get_ticks_usec()
					startup.append(float(now-startup_last)/1000.0)
					startup_last = now
				for video in picker._preview_videos:
					check(video.visible and video.player.is_playing(), tag + ": playing")
					check(video.player.volume == 0.0, tag + ": muted")
					check(video.player.get_video_texture() != null, tag + ": decoded texture")
				var initial: float = picker._preview_videos[0].player.stream_position
				var times: Array[float] = []
				var last := Time.get_ticks_usec()
				# 14 s covers the longest 12 s movie, including its peak and loop.
				for i in sample_frames:
					await tree.process_frame
					var now := Time.get_ticks_usec()
					times.append(float(now-last)/1000.0)
					last = now
				var total := 0.0
				for t in times: total += t
				samples.append({"id":tag,"frames":times.size(),"fps":float(sample_frames)*1000.0/total,"max_ms":times.max(),"over20":times.filter(func(t):return t>20).size(),"over33":times.filter(func(t):return t>33).size(),"select_ms":select_ms,"form_ms":form_ms,"startup_max_ms":startup.max()})
				check(not is_equal_approx(initial,picker._preview_videos[0].player.stream_position), tag + ": playback advances")
				await shot(tag)
				check(main.draft.appearance_id == selected_before, "Preview must not confirm the boss")
			if picker.is_showing_awakened("appearance_"+boss): picker._on_preview_toggle_pressed("appearance_"+boss)
	# Pause is keyboard accessible and freezes both previews.
	picker._preview_pause.grab_focus()
	key(KEY_ENTER)
	await frames(2)
	var paused_at: Array = picker._preview_videos.map(func(v): return v.player.stream_position)
	await frames(20)
	for i in 2: check(is_equal_approx(paused_at[i], picker._preview_videos[i].player.stream_position), "pause freezes both movies")
	key(KEY_ENTER)
	await frames(10)
	check(not picker._previews_paused, "keyboard resume")
	# Observe a real end-to-start wrap while the picker remains open.
	picker.select("appearance_slime")
	var wraps := [0,0]
	var previous := [0.0,0.0]
	var deadline := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline and (wraps[0]<2 or wraps[1]<2):
		await tree.process_frame
		for i in 2:
			var pos: float = picker._preview_videos[i].player.stream_position
			if pos < previous[i]-.1: wraps[i]+=1
			previous[i]=pos
	check(wraps[0]>=2 and wraps[1]>=2, "two natural loop boundaries for both clips")
	# Unsupported bosses retain the existing pending display and release movies.
	for boss in ["wolf", "knight", "golem", "gentleman", "plush"]:
		picker.select("appearance_"+boss)
		for v in picker._preview_videos: check(v.player.stream == null, boss+": no video")
	await shot("unsupported")
	# Back cancels; confirmation updates the existing draft; hiding stops playback.
	picker._on_back_pressed()
	await frames(4)
	check(main.draft.appearance_id == selected_before,"back preserves draft")
	for v in picker._preview_videos: check(not v.player.is_playing(),"closed picker stops playback")
	main.open_appearance_picker()
	picker.select("appearance_musha")
	picker._on_confirm_pressed()
	await frames(4)
	check(main.draft.appearance_id == "appearance_musha","confirmation uses existing flow")
	for v in picker._preview_videos: check(not v.player.is_playing(),"confirmed picker stops playback")
	main.press_test_battle()
	await frames(90)
	await shot("test_battle")
	root.queue_free()
	await frames(3)
	# Locale changes recreate menus in production. Build a fresh English picker.
	RBMLocale.set_locale("en")
	picker = RBMCreatorAppearancePicker.new()
	tree.root.add_child(picker)
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.select("appearance_astronaut")
	picker._on_preview_toggle_pressed("appearance_astronaut")
	for resolution in [Vector2i(1280,720),Vector2i(1024,768),Vector2i(960,540)]:
		tree.root.size = resolution
		await frames(15)
		await shot("en_%dx%d" % [resolution.x,resolution.y])
		check(picker.get_global_rect().encloses(picker._confirm_button.get_global_rect()),"confirm fits")
	picker.queue_free()
	await frames(3)
	RBMLocale.set_locale("ja")
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":errors.is_empty(),"errors":errors,"samples":samples,"loop_wraps":wraps},"\t"))
	print("PREVIEW_GPU_DONE ",errors.is_empty()," ",errors)
	_gpu_verification_completed = true
	return 0 if errors.is_empty() else 1

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(output.path_join(tag+".png"))

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
