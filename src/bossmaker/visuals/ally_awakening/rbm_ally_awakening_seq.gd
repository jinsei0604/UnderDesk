extends "res://ally_awakening/core/sequence.gd"
## 味方の覚醒の発動の第2版の土台（2026-11-19、ユーザー「パーティー側の覚醒演出を改善してほしい。クオリティがすごく低い」）。
## 再生・合図（ポーズ・暗転・閃光・揺れ・解放の impact）は Codex の sequence.gd と同じ約束のまま、絵はボスの演出と同じ部品
## （RBMHeroFxBase の炎・衝撃の輪・火花・光。シェーダーで描く）で描く。平たい図形（輪の線・三角のトゲ・星形）は使わない。
## 座標: エフェクトは 640×360 の論理ドット（戦場の画素の半分）。この節点は味方の足元に置かれるので、中の世界を -足元 だけずらし、
## 2倍して戦場の座標へ合わせる。奥の層は本体（つなぎの z=3）の後ろ、手前の層は本体の前。
## 音は1本（演出の0秒＝音の0秒。tools/ally_awakening/audio/build.mjs）。本体に重ねる光（閃光・照り）は body_flash などで
## つなぎ（rbm_ally_awakening_presentation.gd）へ渡す。

## エフェクトのスクリプト（RBMHeroFxBase を継いだ物）と音の場所。味方ごとに入れる。
var fx_script: GDScript
var sound_path := ""
## 本体に重ねる光（つなぎが読む）: 閃光の強さと色、照り（縁の光）の強さと色。
var body_flash := 0.0
var body_flash_color := Color.WHITE
var body_lit := 0.0
var body_lit_color := Color.WHITE
var _world: Node2D
var _back: Node2D
var _front: Node2D
var _fx: RBMHeroFxBase

func _ready() -> void:
	super._ready()
	_world = Node2D.new()
	_world.name = "AwakeningWorld"
	_world.scale = Vector2(2, 2)
	add_child(_world)
	_back = Node2D.new()
	_back.name = "AwakeningBack"
	_world.add_child(_back)
	_front = Node2D.new()
	_front.name = "AwakeningFront"
	# 本体（つなぎの z=3）より前。この節点は z=2 なので、相対で +2 にする
	_front.z_index = 2
	_world.add_child(_front)
	_fx = fx_script.new()
	_fx.mid = _back
	_world.add_child(_fx)
	_fx.setup(_back, _front, [])

func prepare() -> bool:
	voice.stream = load(sound_path) if not sound_path.is_empty() and ResourceLoader.exists(sound_path) else null
	return voice.stream != null

func warm_paths() -> Array[String]:
	return [sound_path]

func play() -> bool:
	if voice.stream == null:
		return false
	if active:
		cancel()
	age = 0
	did_release = false
	_pose = ""
	cue_log.clear()
	visible = true
	active = true
	voice.volume_db = sound_gain_db
	voice.pitch_scale = playback_speed
	voice.play()
	advance(0.0)
	return true

func advance(t: float) -> void:
	if not active:
		return
	age = minf(t, duration)
	if foot_provider.is_valid():
		position = Vector2(foot_provider.call()).round()
	_world.position = -position
	if age >= release_time and not did_release:
		did_release = true
		cue_log.append({"cue": "release", "scheduled": release_time, "actual": age})
		released.emit()
		shake_requested.emit(shake_amplitude() * shake_strength, .42)
	var frame := pose_at(age)
	if frame != _pose:
		_pose = frame
		pose_requested.emit(frame)
	var foot := position * 0.5
	_fx.advance(age, frame, foot, foot)
	var view: Dictionary = _fx.view
	var post: Dictionary = view.get("post", {})
	screen_requested.emit(float(view.get("dim", 0.0)), float(post.get("flash", 0.0)) * flash_strength)
	var hero: Dictionary = view.get("hero", {})
	body_flash = float(hero.get("flash", 0.0))
	body_flash_color = hero.get("flash_col", Color.WHITE)
	body_lit = float(hero.get("lit", 0.0))
	body_lit_color = hero.get("lit_col", Color.WHITE)
	if age >= duration:
		active = false
		visible = false
		body_flash = 0.0
		body_lit = 0.0
		screen_requested.emit(0, 0)
		pose_requested.emit("b:0")
		finished.emit()

func cancel() -> void:
	body_flash = 0.0
	body_lit = 0.0
	super.cancel()
