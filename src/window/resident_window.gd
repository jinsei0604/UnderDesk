class_name UDResidentWindow
extends RefCounted
## OS-dependent resident window handling, isolated per §12-6.
## Borderless, always-on-top, docked to the bottom edge of the usable
## screen area (= directly above the Windows taskbar).


static func setup_resident(window: Window, height_index: int) -> void:
	var win_height: int = UD.WINDOW_HEIGHTS[height_index]
	window.borderless = true
	window.always_on_top = true
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	window.size = Vector2i(usable.size.x, win_height)
	window.position = Vector2i(
		usable.position.x,
		usable.position.y + usable.size.y - win_height
	)


## §7.1-2: drop fps while the user works in another app.
static func apply_focus_fps(focused: bool) -> void:
	Engine.max_fps = UD.FPS_ACTIVE if focused else UD.FPS_IDLE
