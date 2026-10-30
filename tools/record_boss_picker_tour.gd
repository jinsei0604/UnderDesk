extends RefCounted
## Review-only movie of the actual picker; no production game state is changed.
var _gpu_verification_completed := false
func run_gpu_verification(tree: SceneTree, _directory: String) -> int:
	tree.root.size = Vector2i(1280,720)
	tree.root.content_scale_size = Vector2i(1280,720)
	RBMLocalStageRepository.set_stages_dir_for_testing("user://preview_video_tour")
	var root := RBMGameRoot.new()
	tree.root.add_child(root)
	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	root.creator_entry._on_choose_advanced_mode_pressed()
	root.creator_entry.main.open_appearance_picker()
	var picker: RBMCreatorAppearancePicker = root.creator_entry.main._appearance_picker
	for item in [["slime",false,5.0],["musha",false,8.0],["musha",true,12.5],["astronaut",false,8.5],["astronaut",true,12.5],["ghost",false,9.0]]:
		picker.select("appearance_"+item[0])
		if item[1]: picker._on_preview_toggle_pressed("appearance_"+item[0])
		var scroll := picker.find_child("GridScroll",true,false) as ScrollContainer
		scroll.ensure_control_visible(picker._entry_buttons["appearance_"+item[0]])
		for i in int(float(item[2])*30): await tree.process_frame
	root.queue_free()
	await tree.process_frame
	_gpu_verification_completed = true
	return 0
