class_name RBMSettingsPanel
extends Control

## ホームの「設定」で開く画面（2026-11-08）: 全体・BGM・効果音の音量と、全画面／ウィンドウ。値の持ち主は RBMGameSettings。
## 見た目は紺＋水色（RBMChallengeListStyle。歓迎画面・ガイドと同じ）。閉じる・Esc。スライダーはキーボードの左右でも動く。
## ホームでは BGM が鳴っていないので、BGM のスライダーを動かしている間だけ試聴の曲を流す（効果音・全体は短い音で確かめる）。

signal closed

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const Menu := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
const PANEL_SIZE := Vector2(680, 430)
## [音量の種類, 見出しの文言, ノードの名前の頭]
const ROWS := [["master", "全体の音量", "Master"], ["bgm", "BGMの音量", "Bgm"], ["se", "効果音の音量", "Se"]]
const ROW_Y := 104.0
const ROW_STEP := 62.0
const SLIDER_X := 260.0
const SLIDER_W := 300.0
## 試聴の曲（機械武者の曲。体験版にも入っている）と、触るのをやめてから止めるまでの秒数。
const PREVIEW_BOSS := "musha"
const PREVIEW_HOLD := 1.2

var settings: RBMGameSettings
var _title: Label
var _row_labels: Array[Label] = []
var _sliders := {}
var _percents := {}
var _display_label: Label
var _fullscreen_button: Button
var _window_button: Button
var _close: Button
var _preview: AudioStreamPlayer
var _preview_left := 0.0
var _dragging := false

func setup(game_settings: RBMGameSettings) -> void:
	settings = game_settings

func _ready() -> void:
	name = "SettingsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := Panel.new()
	panel.name = "SettingsWindow"
	panel.size = PANEL_SIZE
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE / 2.0
	panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.98), S.ACCENT_SOFT))
	add_child(panel)
	S.rect(panel, Rect2(0, 0, PANEL_SIZE.x, 3), S.ACCENT_SOFT)
	_title = Menu.shadow(S.label(panel, "", Rect2(40, 28, PANEL_SIZE.x - 80, 44), 30, S.TEXT, "SettingsTitle"))
	S.rect(panel, Rect2(40, 80, PANEL_SIZE.x - 80, 1), S.PANEL_EDGE)
	for i in range(ROWS.size()):
		var row: Array = ROWS[i]
		var y := ROW_Y + i * ROW_STEP
		_row_labels.append(S.label(panel, "", Rect2(40, y, SLIDER_X - 48, 40), 18, S.SILVER, str(row[2]) + "VolumeLabel"))
		_build_slider(panel, str(row[0]), str(row[2]), y)
	var display_y := ROW_Y + ROWS.size() * ROW_STEP
	_display_label = S.label(panel, "", Rect2(40, display_y, SLIDER_X - 48, 44), 18, S.SILVER, "DisplayLabel")
	_fullscreen_button = _button(panel, Rect2(SLIDER_X, display_y, 170, 44), "FullscreenButton", func(): _set_fullscreen(true))
	_window_button = _button(panel, Rect2(SLIDER_X + 180, display_y, 170, 44), "WindowedButton", func(): _set_fullscreen(false))
	_close = _button(panel, Rect2((PANEL_SIZE.x - 200) / 2.0, PANEL_SIZE.y - 66, 200, 48), "SettingsCloseButton", close_settings)
	S.button_style(_close, true)
	_preview = AudioStreamPlayer.new()
	_preview.name = "BgmPreview"
	_preview.bus = RBMBattleBgm.ensure_bus()
	add_child(_preview)
	refresh_locale()
	set_process(false)

func _button(parent: Control, rect: Rect2, node_name: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 16)
	S.button_style(b)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b

func _build_slider(parent: Control, kind: String, prefix: String, y: float) -> void:
	var slider := HSlider.new()
	slider.name = prefix + "VolumeSlider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.position = Vector2(SLIDER_X, y + 8)
	slider.size = Vector2(SLIDER_W, 24)
	slider.focus_mode = Control.FOCUS_ALL
	slider.scrollable = false
	var track := S.box(S.INSET, S.CARD_EDGE)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := S.box(S.ACCENT_SOFT, S.ACCENT_SOFT)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	var fill_hot := S.box(S.ACCENT, S.ACCENT)
	fill_hot.content_margin_top = 3
	fill_hot.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hot)
	slider.add_theme_icon_override("grabber", _grabber(S.SILVER))
	slider.add_theme_icon_override("grabber_highlight", _grabber(S.TEXT))
	parent.add_child(slider)
	var percent := S.label(parent, "", Rect2(SLIDER_X + SLIDER_W + 12, y, 72, 40), 16, S.TEXT, prefix + "VolumePercent")
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sliders[kind] = slider
	_percents[kind] = percent
	slider.value_changed.connect(_on_slider_changed.bind(kind))
	slider.drag_started.connect(func(): _dragging = true)
	slider.drag_ended.connect(func(_changed: bool):
		_dragging = false
		_after_change(kind))

## つまみの絵（小さな縦長の四角。ボス作成のスライダーと同じ素朴な形）。
static func _grabber(color: Color) -> ImageTexture:
	var image := Image.create(10, 22, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func refresh_locale() -> void:
	if _title == null:
		return
	_title.text = tr("設定")
	for i in range(ROWS.size()):
		_row_labels[i].text = tr(str(ROWS[i][1]))
	_display_label.text = tr("画面の表示")
	_fullscreen_button.text = tr("全画面")
	_window_button.text = tr("ウィンドウ")
	_close.text = tr("閉じる")

func open_settings() -> void:
	for kind in _sliders:
		(_sliders[kind] as HSlider).set_value_no_signal(float(settings.volumes[kind]))
		_update_percent(kind)
	_refresh_display_buttons()
	visible = true
	(_sliders["master"] as HSlider).grab_focus()

func close_settings() -> void:
	if not visible:
		return
	_stop_preview()
	visible = false
	closed.emit()

func _update_percent(kind: String) -> void:
	(_percents[kind] as Label).text = "%d%%" % roundi(float(settings.volumes[kind]) * 100.0)

func _refresh_display_buttons() -> void:
	var on := settings.is_fullscreen() if settings.fullscreen_choice == null else bool(settings.fullscreen_choice)
	S.segment_style(_fullscreen_button, on)
	S.segment_style(_window_button, not on)

func _set_fullscreen(on: bool) -> void:
	settings.set_fullscreen(on)
	_refresh_display_buttons()

func _on_slider_changed(value: float, kind: String) -> void:
	settings.set_volume(kind, value)
	_update_percent(kind)
	if kind == "bgm":
		_start_preview()
	elif not _dragging:
		_after_change(kind)

## 音量を決めた時（ドラッグを離した・キーで動かした）に、短い音で確かめる。
func _after_change(kind: String) -> void:
	if kind != "bgm":
		preload("res://src/bossmaker/rbm_audio.gd").cue(settings.get_parent(), "ui_confirm")

func _start_preview() -> void:
	_preview_left = PREVIEW_HOLD
	set_process(true)
	if _preview.playing:
		return
	var path := RBMBossBgm.path_for(PREVIEW_BOSS, false)
	var stream := RBMBossBgm.load_stream(path)
	if stream == null:
		return
	_preview.stream = stream
	_preview.volume_db = RBMBossBgm.volume_db(PREVIEW_BOSS, false)
	_preview.play()

func _stop_preview() -> void:
	set_process(false)
	_preview_left = 0.0
	if is_instance_valid(_preview):
		_preview.stop()

func _process(delta: float) -> void:
	if _dragging:
		_preview_left = PREVIEW_HOLD
		return
	_preview_left -= delta
	if _preview_left <= 0.0:
		_stop_preview()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_settings()
