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
	window.min_size = Vector2i(0, 0)
	window.size = Vector2i(usable.size.x, win_height)
	# The OS may clamp the requested size; dock using the size we actually
	# got so the strip never hangs off the bottom edge.
	var actual: Vector2i = window.size
	window.position = Vector2i(
		usable.position.x,
		usable.position.y + usable.size.y - actual.y
	)


## Centered management window: reading documents, giving orders.
static func setup_expanded(window: Window) -> void:
	window.borderless = false
	window.always_on_top = false
	window.size = UD.NORMAL_WINDOW_SIZE
	window.move_to_center()


## §7.1-2: drop fps while the user works in another app.
static func apply_focus_fps(focused: bool) -> void:
	Engine.max_fps = UD.FPS_ACTIVE if focused else UD.FPS_IDLE


## §7.1-3: stop rendering entirely while minimized; the simulation
## timers keep running. Safe to call every tick.
static func sync_render_loop(window: Window) -> void:
	var minimized := DisplayServer.window_get_mode(window.get_window_id()) \
		== DisplayServer.WINDOW_MODE_MINIMIZED
	RenderingServer.render_loop_enabled = not minimized
