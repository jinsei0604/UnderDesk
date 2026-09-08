extends "res://tools/verify_real_skills_gpu.gd"

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	report = {"cases": [], "errors": [], "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "viewport": [1280, 720]}
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	await _counter_and_cover()
	_validate_counts(EXPECTED_SPECIAL_CASES)
	report["case_count"] = report["cases"].size()
	report["scope"] = "Re-execution of the same six special cases included in real-skills' 56; not six additional distinct cases."
	report["passed"] = report["errors"].is_empty()
	_save_report()
	print("SPECIAL_SKILLS_GPU_DONE passed=" + str(report["passed"]))
	quit(0 if report["passed"] else 1)
