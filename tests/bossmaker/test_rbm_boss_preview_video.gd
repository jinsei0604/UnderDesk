extends GutTest
const Video := preload("res://src/bossmaker/creator/rbm_boss_preview_video.gd")

func after_each() -> void:
	# Profile refresh queues its old feature labels for deletion.
	await get_tree().process_frame

func make_picker() -> RBMCreatorAppearancePicker:
	var picker := RBMCreatorAppearancePicker.new()
	picker.size = Vector2(1280, 720)
	add_child_autofree(picker)
	return picker

func test_only_requested_bosses_have_recordings() -> void:
	for entry in RBMCreatorAppearanceCatalog.all():
		var id := str(entry.id)
		for awakened in [false, true]:
			for kind in ["single", "all"]:
				var path := Video.path_for(id, awakened, kind)
				var expected := id in ["appearance_slime", "appearance_musha", "appearance_astronaut", "appearance_ghost", "appearance_dragon"]
				if awakened: expected = id in ["appearance_musha", "appearance_astronaut"]
				assert_eq(not path.is_empty(), expected, id + str(awakened))
				if expected: assert_true(ResourceLoader.exists(path), path)
	assert_eq(Video.path_for("../slime", false, "single"), "")
	assert_eq(Video.path_for("appearance_slime", false, "heal"), "")

func test_switching_form_and_unavailable_boss_releases_previous_stream() -> void:
	var picker := make_picker()
	picker.select("appearance_musha")
	var video = picker._preview_videos[0]
	assert_true(video.current_path.ends_with("musha_single.ogv"))
	picker._on_preview_toggle_pressed("appearance_musha")
	assert_true(video.current_path.ends_with("musha_awakened_single.ogv"))
	assert_eq(picker.selected_appearance_id(), "appearance_musha")
	picker.select("appearance_wolf")
	assert_null(video.player.stream)
	assert_false(video.player.is_playing())
	assert_false(picker._preview_pause.visible)
	assert_true(picker._preview_frames[0].get_node("PreviewPending").visible)
	picker.select("appearance_ghost")
	assert_true(video.current_path.ends_with("ghost_single.ogv"))
	assert_false(picker._preview_frames[0].get_node("PreviewPending").visible)

func test_pause_and_hidden_parent_stop_decoding_without_confirming() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var picker := RBMCreatorAppearancePicker.new()
	picker.size = Vector2(1280, 720)
	host.add_child(picker)
	for i in 4: await get_tree().process_frame
	watch_signals(picker)
	picker.select("appearance_slime")
	picker._toggle_preview_pause()
	for video in picker._preview_videos:
		assert_true(video.player.paused)
	picker.select("appearance_astronaut")
	for i in 4: await get_tree().process_frame
	for video in picker._preview_videos: assert_true(video.player.paused)
	picker._toggle_preview_pause()
	for video in picker._preview_videos: assert_false(video.player.paused)
	host.hide()
	for video in picker._preview_videos: assert_false(video.player.is_playing())
	host.show()
	for video in picker._preview_videos: assert_true(video.player.is_playing())
	assert_signal_not_emitted(picker, "confirmed")

func test_rapid_selection_and_hiding_cancel_pending_decoder_open() -> void:
	var picker := make_picker()
	picker.select("appearance_astronaut")
	picker._on_preview_toggle_pressed("appearance_astronaut")
	picker.select("appearance_ghost")
	picker.select("appearance_wolf")
	for i in 5: await get_tree().process_frame
	for video in picker._preview_videos:
		assert_null(video.player.stream, "no late movie from a previous selection")
	picker.select("appearance_slime")
	picker.hide()
	for i in 5: await get_tree().process_frame
	for video in picker._preview_videos: assert_null(video.player.stream)
	picker.show()
	for i in 5: await get_tree().process_frame
	for video in picker._preview_videos: assert_true(video.player.is_playing())
