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

## 2026-11-16: 全ボスに通常の録画、覚醒のあるボスには覚醒後の録画もある。
func test_every_boss_has_its_recordings() -> void:
	for entry in RBMCreatorAppearanceCatalog.all():
		var id := str(entry.id)
		for awakened in [false, true]:
			for kind in ["single", "all"]:
				var path := Video.path_for(id, awakened, kind)
				var expected := true
				if awakened: expected = RBMCreatorAppearanceCatalog.supports_awakening(id)
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
	# 動画の無い物を選ぶと前の動画を放す（2026-11-16 から全ボスに動画があるので、存在しない外見で部品を確かめる）
	assert_false(video.configure("appearance_test_fixture_no_video", false, "single"))
	assert_null(video.player.stream)
	assert_false(video.player.is_playing())
	assert_false(video.visible)
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
	# 2026-11-16 から狼にも動画がある: 読み込まれるのは最後に選んだ狼の動画だけで、前に選んだボスの動画が後から出ない
	for video in picker._preview_videos:
		var loaded: String = video.player.stream.resource_path if video.player.stream != null else ""
		assert_true(loaded.is_empty() or loaded.get_file().begins_with("wolf_"), "no late movie from a previous selection: " + loaded)
		assert_false(loaded.contains("astronaut") or loaded.contains("ghost"), "no late movie from a previous selection")
	picker.select("appearance_slime")
	picker.hide()
	for i in 5: await get_tree().process_frame
	for video in picker._preview_videos: assert_null(video.player.stream)
	picker.show()
	for i in 5: await get_tree().process_frame
	for video in picker._preview_videos: assert_true(video.player.is_playing())
