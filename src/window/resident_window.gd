class_name UDResidentWindow
extends RefCounted
## OS-dependent resident window handling, isolated per §12-6.
## Borderless, always-on-top, docked to the bottom edge of the usable
## screen area (= directly above the Windows taskbar).


static func setup_resident(window: Window, height_index: int) -> void:
	var win_height: int = UD.WINDOW_HEIGHTS[height_index]
	window.borderless = true
	window.always_on_top = true
	# The compact strip's own hand-tuned layout (_draw_strip_overlay) draws
	# in raw physical pixels and is intentionally left alone (未再設計) —
	# never let the expanded window's content-scale setting leak in here.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	window.min_size = Vector2i(0, 0)
	window.size = Vector2i(UD.MINI_WINDOW_WIDTH, win_height)
	# The OS may clamp the requested size; dock using the size we actually
	# got so the strip never hangs off the bottom edge.
	var actual: Vector2i = window.size
	window.position = Vector2i(
		usable.position.x + UD.MINI_LEFT_MARGIN,
		usable.position.y + usable.size.y - actual.y - UD.MINI_BOTTOM_MARGIN
	)


## Centered management window: reading documents, giving orders.
static func setup_expanded(window: Window) -> void:
	window.borderless = false
	window.always_on_top = false
	window.size = UD.NORMAL_WINDOW_SIZE
	window.move_to_center()
	# レスポンシブUI基盤（2026-08-21実機プレイ報告）: project.godotに
	# window/stretch設定が一切無く（デフォルト=disabled）、main.gdのUI
	# はほぼ全てfixed-pixelのoffset/フォントサイズで組まれているため、
	# ウィンドウを小さくすると部位選択パネル等が見切れ、全画面/最大化
	# すると同じpxのままのUIが広い画面の中で相対的に小さく見えていた。
	# main.gd側の個々のControlを解像度依存から書き直す（大規模改修）
	# 代わりに、GodotのWindow.content_scale機構をexpandedモードにだけ
	# 適用——ゲーム内の座標系（main.gdの`size`、_view_rect()、マウス
	# クリック座標）を常にUD.NORMAL_WINDOW_SIZE(1152x648、この定数が
	# 従来から想定されてきた基準解像度)に固定し、実ウィンドウがどんな
	# 物理pxでも「アスペクト比を保ったまま1枚の絵として一様に拡縮＋
	# レターボックス」する。既存の全Control（固定offsetのものも
	# view.size相対のものも）が無改修のまま一緒に拡縮されるため、個別
	# 修正なしで「見切れる」「全画面で小さい」の両方を同時に解消する。
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = UD.NORMAL_WINDOW_SIZE


## §7.1-2: drop fps while the user works in another app.
static func apply_focus_fps(focused: bool) -> void:
	Engine.max_fps = UD.FPS_ACTIVE if focused else UD.FPS_IDLE


## §7.1-3: stop rendering entirely while minimized; the simulation
## timers keep running. Safe to call every tick.
static func sync_render_loop(window: Window) -> void:
	var minimized := DisplayServer.window_get_mode(window.get_window_id()) \
		== DisplayServer.WINDOW_MODE_MINIMIZED
	RenderingServer.render_loop_enabled = not minimized
