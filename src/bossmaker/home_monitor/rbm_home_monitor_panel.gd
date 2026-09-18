class_name RBMHomeMonitorPanel
extends Control

## ホーム画面（タイトル画面）の左下「挑戦」／右下「ボス作成」モニター。
##
## 承認済み独立プレビュー（tools/preview_home3e_final_gpu.gd等、確認後に
## 削除済み）の見た目・テンポをそのまま本番実装したもの。新デザイン提案は
## 行っていない。
##
## 設計方針（依頼§重要のとおり）:
## - 通常表示／ホバー／クリック判定／BOOT演出／拡大遷移の開始位置は、
##   すべて`home_rect`（1280x720基準の確定Rect、RBMGameRootから渡される）
##   を唯一の基準にする。BOOT開始時に別サイズのControlを新規生成すること
##   はしない——このControl自身（`self`）のposition/sizeを、通常時の
##   home_rectからフルスクリーン(0,0,1280,720)まで直接補間するだけ。
## - 演出が完了すると`activated`シグナルを発火するだけで、実際の画面遷移
##   （Challenge/Creator本体への接続）はRBMGameRoot側の責務のまま。
##   Challenge/Creator内部のロジックには一切触れない。

signal activated

enum _State { IDLE, BOOTING }

const SCREEN_SIZE := Vector2(1280.0, 720.0)

var home_rect: Rect2
var label_key: String
var other_panel: RBMHomeMonitorPanel

var _state: _State = _State.IDLE
var _run_token := 0

var _panel_draw: RBMHomeMonitorPanelDraw
var _label: Label
var _status_label: Label
var _reticle: RBMHomeMonitorReticleDraw

func _ready() -> void:
	position = home_rect.position
	size = home_rect.size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	_panel_draw = RBMHomeMonitorPanelDraw.new()
	_panel_draw.name = "PanelDraw"
	_panel_draw.position = Vector2.ZERO
	_panel_draw.size = home_rect.size
	_panel_draw.rect_size_local = home_rect.size
	_panel_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_draw)

	_label = Label.new()
	_label.name = "HomeMonitorLabel"
	_label.text = tr(label_key)
	_label.position = Vector2.ZERO
	_label.size = home_rect.size
	_label.pivot_offset = home_rect.size / 2.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 0.92))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_status_label = Label.new()
	_status_label.name = "HomeMonitorStatusLabel"
	_status_label.text = ""
	_status_label.position = Vector2.ZERO
	_status_label.size = home_rect.size
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.97, 1.0, 0.98))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.modulate.a = 0.0
	add_child(_status_label)

	_reticle = RBMHomeMonitorReticleDraw.new()
	_reticle.name = "Reticle"
	_reticle.position = Vector2.ZERO
	_reticle.size = home_rect.size
	_reticle.center = home_rect.size / 2.0
	_reticle.base_radius = min(home_rect.size.x, home_rect.size.y) * 0.24
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle)

## タイトルへ戻った際、RBMGameRoot._show_menu()から呼ばれる。BOOT/拡大の
## 途中だった場合でも、通常表示（home_rect・元のposition/size・演出無し）
## へ即座に戻す。進行中のawaitループは_run_tokenの不一致で自然に終了する。
func reset_to_idle() -> void:
	_run_token += 1
	_state = _State.IDLE
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 0
	position = home_rect.position
	size = home_rect.size
	_panel_draw.rect_size_local = home_rect.size
	_panel_draw.dim = 0.0
	_panel_draw.border_intensity = 0.4
	_panel_draw.corner_len = 8.0
	_panel_draw.scan_pos = -1.0
	_panel_draw.cross_extent = 0.0
	_panel_draw.boot_corner_stage = 0.0
	_panel_draw.boot_corner_alpha = 1.0
	_panel_draw.full_scan_pos = -1.0
	_label.text = tr(label_key)
	_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_label.scale = Vector2.ONE
	_status_label.text = ""
	_status_label.modulate.a = 0.0
	_reticle.center = home_rect.size / 2.0
	_reticle.alpha = 0.0
	_reticle.radius_frac = 1.0
	_reticle.flash = 0.0
	_reticle.lit_ticks = 0
	_reticle.activation_sweep = TAU

## ロケール切替時、RBMGameRootから呼ばれる。BOOT中でなければラベルの
## 表示言語だけを更新する（BOOT中の一瞬の切替を避けるだけの単純なガード）。
func refresh_locale() -> void:
	if _state == _State.IDLE:
		_label.text = tr(label_key)

func set_dim(on: bool) -> void:
	var tw := _panel_draw.create_tween()
	tw.tween_property(_panel_draw, "dim", 0.18 if on else 0.0, 0.18)

func set_interactive(on: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE

func _on_mouse_entered() -> void:
	if _state != _State.IDLE:
		return
	var tw := _panel_draw.create_tween()
	tw.tween_property(_panel_draw, "border_intensity", 0.85, 0.18)
	var tw2 := _panel_draw.create_tween()
	tw2.tween_property(_panel_draw, "corner_len", 14.0, 0.18)
	var tw3 := _label.create_tween()
	tw3.tween_property(_label, "modulate:a", 1.0, 0.18)
	_panel_draw.scan_pos = 0.0
	var tw4 := _panel_draw.create_tween()
	tw4.tween_property(_panel_draw, "scan_pos", 1.0, 0.6)
	tw4.tween_callback(func():
		if _state == _State.IDLE:
			_panel_draw.scan_pos = -1.0)
	if is_instance_valid(other_panel):
		other_panel.set_dim(true)

func _on_mouse_exited() -> void:
	if _state != _State.IDLE:
		return
	var tw := _panel_draw.create_tween()
	tw.tween_property(_panel_draw, "border_intensity", 0.4, 0.18)
	var tw2 := _panel_draw.create_tween()
	tw2.tween_property(_panel_draw, "corner_len", 8.0, 0.18)
	var tw3 := _label.create_tween()
	tw3.tween_property(_label, "modulate:a", 0.92, 0.18)
	if is_instance_valid(other_panel):
		other_panel.set_dim(false)

## 二重入力/二重遷移防止: IDLE以外からのクリックは無視する。反対側の
## モニターもBOOT開始と同時にset_interactive(false)で入力を奪うが、それは
## 実際のマウス入力経路（mouse_filter）に対する保護でしかない——念のため
## other_panelの状態も直接見て、どちらか一方が既にBOOT中なら（テスト等で
## mouse_filterを迂回して直接gui_inputを発火された場合でも）二重に起動
## しないようソフトウェア側でも二重に保証する（RBMGameRoot側からではなく、
## このメソッド内で直接行う——別Controlを新規生成しないのと同様、遷移制御
## ロジックもこのクラス自身に閉じる）。
## gui_inputシグナルへの接続を使う（_gui_input()の仮想オーバーライドでは
## なく）——このコードベースの既存パターン（rbm_battle_ui_kit.gd等の
## PanelContainerクリック検知）に合わせるため、かつ合成InputEventを
## `.gui_input.emit()`で直接発火するテスト手法（test_rbm_phase35_step4_
## battle_ui.gd等が既に確立）でそのまま検証できるようにするため。
func _on_gui_input(event: InputEvent) -> void:
	if _state != _State.IDLE:
		return
	if is_instance_valid(other_panel) and other_panel._state != _State.IDLE:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		get_viewport().set_input_as_handled()
		_start_boot_sequence()

func _start_boot_sequence() -> void:
	if _state != _State.IDLE:
		return
	_state = _State.BOOTING
	_run_token += 1
	var token := _run_token
	set_interactive(false)
	if is_instance_valid(other_panel):
		other_panel.set_interactive(false)
	await _run_boot_and_expand(token)
	if token != _run_token:
		return
	activated.emit()

func _ease_in_out_cubic(x: float) -> float:
	if x < 0.5:
		return 4.0 * x * x * x
	var f: float = -2.0 * x + 2.0
	return 1.0 - (f * f * f) / 2.0

func _run_boot_and_expand(token: int) -> void:
	z_index = 5
	if is_instance_valid(other_panel):
		other_panel.set_dim(true)

	# --- クリック直後: 文字が一瞬シアン強発光して縮退/フェード ---
	var flash_dur := 0.10
	var ft := 0.0
	while ft < flash_dur:
		await get_tree().process_frame
		if token != _run_token:
			return
		var dt: float = _delta_time()
		ft += dt
		var w: float = clamp(ft / flash_dur, 0.0, 1.0)
		if w < 0.4:
			_label.modulate = Color(1.4, 1.4, 1.4, 1.0)
			_label.scale = Vector2.ONE
		else:
			var f2: float = (w - 0.4) / 0.6
			_label.modulate = Color(1.4, 1.4, 1.4, 1.0 - f2)
			_label.scale = Vector2.ONE.lerp(Vector2(0.82, 0.82), ease(f2, 0.6))
		_panel_draw.dim = w * 0.15
	_label.modulate.a = 0.0

	var t := 0.0
	var wake_dur := 0.12
	var ring_dur := 0.32
	var connect_dur := 0.34
	var pre_expand_dur := 0.10
	var boot_dur := wake_dur + ring_dur + connect_dur + pre_expand_dur
	var expand_dur := 0.5

	var status_shown := false

	while t < boot_dur:
		await get_tree().process_frame
		if token != _run_token:
			return
		var dt: float = _delta_time()
		t += dt

		if t < wake_dur:
			var w: float = t / wake_dur
			_panel_draw.dim = lerp(0.15, 0.28, w)
			_panel_draw.corner_len = lerp(8.0, 14.0, w)
			_panel_draw.border_intensity = lerp(0.6, 0.9, w)
			_panel_draw.scan_pos = w
		elif t < wake_dur + ring_dur:
			_panel_draw.scan_pos = -1.0
			_panel_draw.dim = lerp(0.28, 0.05, min(1.0, (t - wake_dur) / (ring_dur * 0.6)))
			var rt: float = (t - wake_dur) / ring_dur
			_reticle.alpha = min(1.0, rt / 0.12)
			_reticle.activation_sweep = ease(min(1.0, rt / 0.75), 0.7) * TAU
			_reticle.rotation_angle += dt * 2.4
			_reticle.spinner_angle += dt * 5.5
			_reticle.lit_ticks = int(ceil(rt * 8.0))
			if rt >= 0.8:
				var ct: float = (rt - 0.8) / 0.2
				_reticle.radius_frac = lerp(1.0, 0.92, ct)
		elif t < wake_dur + ring_dur + connect_dur:
			var ct2: float = (t - wake_dur - ring_dur) / connect_dur
			_reticle.radius_frac = lerp(0.92, 0.88, min(1.0, ct2 / 0.3))
			_panel_draw.cross_extent = min(1.0, ct2 / 0.4)
			if ct2 > 0.15:
				_panel_draw.boot_corner_stage = min(4.0, (ct2 - 0.15) / 0.55 * 4.0)
			if ct2 < 0.55:
				_panel_draw.full_scan_pos = ct2 / 0.55
			else:
				_panel_draw.full_scan_pos = -1.0
			if ct2 >= 0.7 and not status_shown:
				status_shown = true
				_status_label.text = "LINK ESTABLISHED"
				var tws := _status_label.create_tween()
				tws.tween_property(_status_label, "modulate:a", 1.0, 0.12)
		else:
			var pt: float = (t - wake_dur - ring_dur - connect_dur) / pre_expand_dur
			_reticle.radius_frac = lerp(0.88, 0.05, ease(pt, 2.0))
			_reticle.flash = pt
			_panel_draw.cross_extent = max(0.0, 1.0 - pt * 1.5)

	_reticle.alpha = 0.0

	# --- 拡大: 同じControl(self)のposition/sizeをease-in-outで直接補間 ---
	var start_pos := position
	var start_size := size
	var end_pos := Vector2.ZERO
	var end_size := SCREEN_SIZE

	var et := 0.0
	while et < expand_dur:
		await get_tree().process_frame
		if token != _run_token:
			return
		var dt2: float = _delta_time()
		et += dt2
		var raw: float = clamp(et / expand_dur, 0.0, 1.0)
		var e: float = _ease_in_out_cubic(raw)

		position = start_pos.lerp(end_pos, e)
		size = start_size.lerp(end_size, e)
		_panel_draw.rect_size_local = size
		_reticle.center = size / 2.0
		_status_label.size = size

		if raw > 0.8:
			var f3: float = (raw - 0.8) / 0.2
			_panel_draw.border_intensity = lerp(1.0, 0.0, f3)
			_panel_draw.boot_corner_alpha = 1.0 - f3
			_status_label.modulate.a = max(0.0, 1.0 - f3 * 1.3)

	position = end_pos
	size = end_size
	_status_label.modulate.a = 0.0
	_panel_draw.boot_corner_stage = 0.0
	_panel_draw.cross_extent = 0.0
	_panel_draw.border_intensity = 0.0

	# --- フルスクリーン後、0.1〜0.2秒だけ接続完了状態を維持してから遷移 ---
	await _hold(0.15, token)

func _hold(seconds: float, token: int) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		if token != _run_token:
			return
		elapsed += _delta_time()

func _delta_time() -> float:
	var dt: float = get_tree().root.get_process_delta_time()
	if dt <= 0.0:
		dt = 1.0 / 60.0
	return dt
