extends SceneTree

## Actual rendered viewport capture of the three production battle views.
## Run with a GPU renderer (no --headless):
## godot --path <project> --resolution 1280x720 --script res://tools/capture_battle_gpu.gd -- --output <directory>
## This harness only instantiates public Views and their normal definition loader.
## It does not modify production data, saves, combat state, or performance values.

var output_dir := "res://../gpu-baseline"
var report: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--output":
			output_dir = args[i + 1]
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.title = "Makers & Challengers — GPU verification"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	report = {
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"viewport": [root.size.x, root.size.y],
		"headless": DisplayServer.get_name() == "headless",
		"views": [],
	}
	if report["headless"]:
		push_error("GPU capture requires a windowed display; --headless is not valid.")
		quit(2)
		return
	for definition_name in ["test_definition_a", "test_definition_b"]:
		var definition: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/%s.json" % definition_name)
		for view_name in ["test", "clear_check", "challenge"]:
			await _capture_view(view_name, definition_name, definition)
	var f := FileAccess.open(output_dir.path_join("layout-report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("GPU_CAPTURE_DONE " + ProjectSettings.globalize_path(output_dir))
	quit()

func _capture_view(view_name: String, definition_name: String, definition: Dictionary) -> void:
	var view: Control
	match view_name:
		"test":
			view = RBMCreatorTestBattleView.new()
			root.add_child(view)
			view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			view.setup(null)
			view.start(definition, 20260906)
		"clear_check":
			view = RBMCreatorClearCheckView.new()
			root.add_child(view)
			view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			view.setup(null)
			view.start_battle(definition, 20260906)
		_:
			view = RBMChallengeBattleView.new()
			root.add_child(view)
			view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			view.start_battle(definition)
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var capture_name := "%s_%s.png" % [view_name, definition_name]
	var save_error := image.save_png(output_dir.path_join(capture_name))
	var nodes: Array[Dictionary] = []
	_collect_layout(view, view, nodes)
	report["views"].append({
		"view": view_name, "definition": definition_name,
		"screenshot": capture_name, "image_size": [image.get_width(), image.get_height()],
		"save_error": save_error, "nodes": nodes,
	})
	view.queue_free()
	await process_frame

func _collect_layout(node: Node, view: Node, nodes: Array[Dictionary]) -> void:
	if node is Control and node.is_visible_in_tree():
		var control := node as Control
		var rect := control.get_global_rect()
		var item: Dictionary = {
			"path": str(view.get_path_to(node)), "name": str(node.name),
			"class": node.get_class(),
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"minimum": [control.get_combined_minimum_size().x, control.get_combined_minimum_size().y],
		}
		if node is Label or node is Button:
			item["text"] = node.text
		nodes.append(item)
	for child in node.get_children():
		_collect_layout(child, view, nodes)
