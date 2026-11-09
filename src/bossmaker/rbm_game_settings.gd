class_name RBMGameSettings
extends Node

## プレイヤーの設定（全体・BGM・効果音の音量、全画面／ウィンドウ）を持ち、保存し、反映する（2026-11-08）。RBMGameRoot の子として1つ置く。
## 戦闘の状態・乱数・ボスの保存データには触れない。保存は版ごとの置き場の game_settings.json（言語の settings.json とは別）。
## - 音量はオーディオバスの音量で変える。すべて 100% のままなら 0dB で、今までの音と同じ。
## - 効果音は個々の再生の場所を直さず、木に入った AudioStreamPlayer のうち Master に出すものを SE バスへ向ける（SE は Master に送るので
##   Master のリミッターはそのまま効く）。BGM は今までどおり Music バス（RBMBattleBgm）。
## - 全画面／ウィンドウは、プレイヤーが選ぶまで触らない（選ぶまでは project.godot の表示のまま）。拡大方式も変えない。

const FILE_NAME := "game_settings.json"
const SE_BUS := "SE"
const WINDOW_SIZE := Vector2i(1280, 720)
const KINDS := ["master", "bgm", "se"]

## 音量（0.0〜1.0）
var volumes := {"master": 1.0, "bgm": 1.0, "se": 1.0}
## 選んだ表示。null はまだ選んでいない
var fullscreen_choice: Variant = null

static func file_path() -> String:
	return RBMEdition.data_root() + "/" + FILE_NAME

func _ready() -> void:
	name = "GameSettings"
	ensure_se_bus()
	var saved := read_file(file_path())
	for kind in KINDS:
		volumes[kind] = float(saved.get(kind, 1.0))
	fullscreen_choice = saved.get("fullscreen", null)
	apply_audio()
	_route_existing(get_tree().root)
	get_tree().node_added.connect(_on_node_added)
	if fullscreen_choice != null:
		_apply_window(bool(fullscreen_choice))

static func ensure_se_bus() -> void:
	if AudioServer.get_bus_index(SE_BUS) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, SE_BUS)
	AudioServer.set_bus_send(index, "Master")

## 保存した設定。無い・壊れている時は空。音量は 0〜1 に収め、数でない値は無かったことにする。
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var out := {}
	for kind in KINDS:
		var value: Variant = json.data.get(kind)
		if value is float or value is int:
			out[kind] = clampf(float(value), 0.0, 1.0)
	if json.data.get("fullscreen") is bool:
		out["fullscreen"] = json.data["fullscreen"]
	return out

## 音量（0〜1）→ dB。100% が 0dB。耳の感じに近づけるため2乗する（50% = -12dB）。
static func volume_to_db(value: float) -> float:
	return linear_to_db(maxf(value * value, 0.00001))

func set_volume(kind: String, value: float) -> void:
	if not volumes.has(kind):
		return
	volumes[kind] = clampf(value, 0.0, 1.0)
	apply_audio()
	save()

func apply_audio() -> void:
	_apply_bus("Master", float(volumes["master"]))
	_apply_bus(RBMBattleBgm.ensure_bus(), float(volumes["bgm"]))
	_apply_bus(SE_BUS, float(volumes["se"]))

static func _apply_bus(bus: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, volume_to_db(value))
	AudioServer.set_bus_mute(index, value <= 0.0)

## 今の表示が全画面か（選んだ値ではなく、実際のウィンドウの状態）。
func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func set_fullscreen(on: bool) -> void:
	fullscreen_choice = on
	_apply_window(on)
	save()

func _apply_window(on: bool) -> void:
	if DisplayServer.get_name() == "headless" or RBMLocalStageRepository.running_under_gut():
		return
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOW_SIZE)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(screen.position + (screen.size - WINDOW_SIZE) / 2)

func save() -> void:
	var data := {"master": volumes["master"], "bgm": volumes["bgm"], "se": volumes["se"]}
	if fullscreen_choice != null:
		data["fullscreen"] = fullscreen_choice
	RBMLocalStageRepository._atomic_write(file_path(), JSON.stringify(data))

func _route_existing(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_route_existing(child)

func _on_node_added(node: Node) -> void:
	if node is AudioStreamPlayer:
		if (node as AudioStreamPlayer).bus == &"Master":
			(node as AudioStreamPlayer).bus = SE_BUS
	elif node is AudioStreamPlayer2D:
		if (node as AudioStreamPlayer2D).bus == &"Master":
			(node as AudioStreamPlayer2D).bus = SE_BUS
