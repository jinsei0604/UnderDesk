extends RefCounted
## 戦場のカメラ（共通部品・表示専用）。戦場（ステージ = 背景・キャラ・演出）を1つのまとまりとして動かし、HUD は動かさない
## （COMBAT_PRESENTATION §4.2・§4.5）。戦闘の状態・乱数には触れない。
## - 寄りは整数倍（1倍・2倍）のカットだけ。途中の倍率は通らない（ドット絵の画素の幅が不ぞろいにならないように）。
## - 揺れは2px単位。強さはステージの "presentation_shake_strength"（0〜1、既存の演出と同じ設定の入口）を掛ける。
## - 揺らした・寄った時に画面の端が空かないよう、戦場の後ろに同じ背景を暗くして1枚敷く。
## - reset() で必ず元の位置・大きさへ戻す（中断・画面が隠れた時も呼ぶ）。
## 時間は advance(dt) で外から進める（演出の時刻 age と同じ時間）。

const SCREEN := Vector2(1280, 720)
const PATTERN := [Vector2(1, 0), Vector2(-1, 0.5), Vector2(0.5, -1), Vector2(-0.5, 1), Vector2(1, 0.5), Vector2(-1, -0.5)]

var stage: Control
var zoom := 1
var focus := SCREEN * 0.5
var _shakes: Array = []
var _offset := Vector2.ZERO
var _home_pos := Vector2.ZERO
var _home_scale := Vector2.ONE
var _backing: TextureRect
var _tick := 0.0

func attach(st: Control) -> void:
	stage = st
	_home_pos = stage.position
	_home_scale = stage.scale
	var bg := stage.get_node_or_null("FullScreenBattleBackground") as TextureRect
	if bg != null and stage.get_parent() != null:
		_backing = TextureRect.new()
		_backing.name = "BattlefieldCameraBacking"
		_backing.texture = bg.texture
		_backing.expand_mode = bg.expand_mode
		_backing.stretch_mode = bg.stretch_mode
		_backing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backing.modulate = Color(0.55, 0.55, 0.6)
		var parent := stage.get_parent()
		parent.add_child(_backing)
		parent.move_child(_backing, stage.get_index())
		_backing.position = Vector2.ZERO
		_backing.size = SCREEN

func shake_strength() -> float:
	if not is_instance_valid(stage):
		return 1.0
	return clampf(float(stage.get_meta("presentation_shake_strength", 1.0)), 0.0, 1.0)

## 寄りのカット（new_zoom: 1 か 2、new_focus: 寄りの中心のステージ座標）。
func cut(new_zoom: int, new_focus: Vector2) -> void:
	zoom = maxi(1, new_zoom)
	focus = new_focus
	apply()

func shake(amplitude: float, duration: float) -> void:
	if duration <= 0.0:
		return
	_shakes.append({"amp": amplitude, "dur": duration, "age": 0.0})

func advance(dt: float) -> void:
	_tick += dt
	var total := 0.0
	for s in _shakes:
		s.age += dt
		var k: float = 1.0 - clampf(s.age / s.dur, 0.0, 1.0)
		total = maxf(total, s.amp * k * k)
	_shakes = _shakes.filter(func(s): return s.age < s.dur)
	var pattern: Vector2 = PATTERN[int(_tick * 30.0) % PATTERN.size()]
	_offset = (pattern * total * shake_strength()).snapped(Vector2(2, 2))
	apply()

func apply() -> void:
	if not is_instance_valid(stage):
		return
	var z := float(zoom)
	stage.scale = _home_scale * z
	var pos := _home_pos
	if zoom > 1:
		var margin := 8.0
		pos = SCREEN * 0.5 - focus * z
		pos.x = clampf(pos.x, SCREEN.x - SCREEN.x * z + margin, -margin)
		pos.y = clampf(pos.y, SCREEN.y - SCREEN.y * z + margin, -margin)
	stage.position = (pos + _offset).round()

## 寄りと揺れだけ戻す（後ろに敷いた背景は残す。続けて使う時）。
func reset_keep() -> void:
	_shakes.clear()
	_offset = Vector2.ZERO
	zoom = 1
	if is_instance_valid(stage):
		stage.scale = _home_scale
		stage.position = _home_pos

## すべて元へ戻す（後ろに敷いた背景も外す）。
func reset() -> void:
	reset_keep()
	if is_instance_valid(_backing):
		_backing.queue_free()
	_backing = null
