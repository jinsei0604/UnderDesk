extends SceneTree
## One-shot visual smoke test: boots the real main scene, forces the
## expanded window, captures the idle battle view and the boss arena to
## PNGs, then quits. Never writes the save: autosave fires on a 60s
## timer we quit long before, and SceneTree.quit() does not emit
## NOTIFICATION_WM_CLOSE_REQUEST (the only other save path).

const OUT := "C:/Users/jinch/AppData/Local/Temp/claude/C--src-underdesk/6fface6a-af13-4854-9b42-ba0bf7c0b720/scratchpad/"

var _main: Node
var _frame := 0


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	if _frame == 1:
		var scene: PackedScene = load("res://src/ui/main.tscn")
		_main = scene.instantiate()
		root.add_child(_main)
	elif _frame == 3:
		# Force the expanded window WITHOUT _expand() (that would write
		# the user's settings file). A save loaded mid-boss-fight would
		# hide the idle view, so flee first (in-memory only, never saved).
		_main.settings.resident_mode = false
		_main._apply_window_mode()
		_main._refresh_button_texts()
		if _main.sim.boss_active:
			_main.sim.flee_boss_fight()
			_main._hide_boss_panel()
		_main.queue_redraw()
	elif _frame == 12:
		_capture("shot_idle.png")
		if _main.sim.start_boss_fight():
			_main._show_boss_panel()
			_main.queue_redraw()
		else:
			print("BOSS FIGHT DID NOT START (stage=", _main.sim.stage_index, ")")
	elif _frame == 20:
		_capture("shot_boss.png")
		print("stage=", _main.sim.stage_index,
			" boss_active=", _main.sim.boss_active,
			" boss=", _main.sim.boss_enemy_id)
		quit(0)


func _capture(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + fname)
	print("captured ", fname, " (", img.get_width(), "x", img.get_height(), ")")
