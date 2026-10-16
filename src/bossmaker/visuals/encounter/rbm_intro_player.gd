extends Node2D
## 戦闘開始前のボスの登場演出（案B シネマ型。表示専用）を再生する。RBMEncounterDirector が作って動かす。
## 本番の戦闘画面（ステージ・HUD）の上で再生し、終わったら通常の戦闘へ戻す。
## - 戦闘の状態・乱数・ターンには触れない（見た目だけ。戦闘は既に始まっていて、まだ最初の行動を見せていない状態）。
## - 再生中は HUD を隠し、コマンドの入力を止める（画面の層の入力を止める板）。終わる時に HUD を短くフェードで戻す。
## - 飛ばせない（ユーザーの決定 2026-10-16）。
## - 前の画面が閉じる部分（時刻 0〜0.30秒）は rbm_screen_close.gd が戦闘を始める前に見せるので、ここは START_AGE から始める。
## - 時間は age（経過秒）で進める。cancel() で、いつでも元の見た目（カメラ・ボス・味方・HUD・音）へ戻す。

signal finished

const Overlay = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_overlay.gd")
const Camera = preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
const FX = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_fx.gd")
const Layer = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_layer.gd")
const Sprites = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_sprites.gd")
const SPRITE_SHADER = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_sprite.gdshader")
const Choreo = preload("res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd")
const Audio = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_audio.gd")
const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
const MushaFrames = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const GentlemanMotion = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const CHOREO := {
	"slime": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_slime.gd"),
	"wolf": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_wolf.gd"),
	"knight": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_knight.gd"),
	"dragon": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_dragon.gd"),
	"ghost": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_ghost.gd"),
	"golem": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_golem.gd"),
	"musha": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_musha.gd"),
	"astronaut": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_astronaut.gd"),
	"gentleman": preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_gentleman.gd"),
}
## 前の画面が閉じる部分の長さ（rbm_screen_close.gd の DURATION と同じ）。
const START_AGE := 0.30
const HUD_FADE := 0.22

var boss := "golem"
var boss_name := ""
var author := ""
var stage: Control
var view: Control
var hud: Control
var sfx: Node

var age := 0.0
var duration := 4.5
var choreo: RefCounted
var overlay: CanvasLayer
var camera: RefCounted
var back: Node2D        # 背景のすぐ上（暗さ・霧・床の光）。キャラより後ろ
var body: Node2D        # ボス本体（シェーダー付き: 色を抜く・粒で現れる）
var flat: Node2D        # ボス本体を単色で重ねる（白く光る・影）
var allies: Node2D      # 味方の差し替え絵
var top: Node2D         # 味方より前（暗さ・目の光・閃き・光の筋）
var fx: FX              # キャラの前の粒
var fx_back: FX         # キャラの後ろの粒

var state := "idle"      # idle / playing / handoff / done
var _fired := {}
var _handoff_age := 0.0
var timeline_log: Array = []
var _ally_saved := {}   # key -> {pose, position, modulate}

## このボスの登場があるか。
static func has_intro(boss_id: String) -> bool:
	return CHOREO.has(boss_id)

## このボスの登場で読む素材（事前読み込みの warm_paths() 用）: ボスの12ポーズ・ボス専用のコマ絵・味方の身構えのポーズ・音。
static func warm_paths(boss_id: String, party: Array) -> Array[String]:
	var out: Array[String] = []
	if not CHOREO.has(boss_id):
		return out
	var consts: Dictionary = (CHOREO[boss_id] as Script).get_script_constant_map()
	out.append_array(Sprites.pose_paths(boss_id))
	out.append_array(frame_paths_of(boss_id, consts.get("FRAMES", [])))
	for a in party:
		if Choreo.READY_POSE.has(str(a)):
			out.append(Assets.frame_path(str(a), int(Choreo.READY_POSE[str(a)])))
	out.append_array(Audio.paths_of(Choreo.COMMON_SOUNDS + Array(consts.get("SOUNDS", []))))
	var unique: Array[String] = []
	for p in out:
		if not p.is_empty() and not unique.has(p):
			unique.append(p)
	return unique

## このボスの登場で鳴らす音の鍵（共通の音＋振付の SOUNDS）。
static func warm_paths_keys(boss_id: String) -> Array:
	if not CHOREO.has(boss_id):
		return []
	var consts: Dictionary = (CHOREO[boss_id] as Script).get_script_constant_map()
	return Choreo.COMMON_SOUNDS + Array(consts.get("SOUNDS", []))

## ボス専用のコマの名前 → 画像の場所（武者: rbm_musha_frames.gd、紳士: motion_frames）。
static func frame_paths_of(boss_id: String, names: Array) -> Array[String]:
	var out: Array[String] = []
	for n in names:
		var p := ""
		match boss_id:
			"musha": p = MushaFrames.texture_path(str(n)) if MushaFrames.has_frame(str(n)) else ""
			"gentleman": p = GentlemanMotion.ROOT + "motion_frames/" + str(n) + ".png"
		if not p.is_empty():
			out.append(p)
	return out

func setup(st: Control, battle_view: Control, battle_hud: Control, audio: Node) -> void:
	stage = st
	view = battle_view
	hud = battle_hud
	sfx = audio

func play() -> void:
	state = "playing"
	age = START_AGE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Sprites.register_stage(stage)
	stage.add_child(self)
	var boss_visual: Control = stage.get("_visuals")["boss"]
	back = _layer("IntroBack", 1, -1)
	fx_back = FX.new()
	fx_back.z_index = 1
	body = _layer("IntroBossBody", 1, 0)
	flat = _layer("IntroBossFlat", 1, 1)
	allies = _layer("IntroAllies", 2, -1)
	top = _layer("IntroTop", 5, -1)
	fx = FX.new()
	fx.z_index = 6
	var at_index := boss_visual.get_index() + 1
	for n in [fx_back, body, flat]:
		stage.add_child(n)
		stage.move_child(n, at_index)
		at_index += 1
	# 背景の暗さ・霧は背景のすぐ上（キャラより後ろ）に置く
	stage.add_child(back)
	stage.move_child(back, 1)
	stage.add_child(allies)
	stage.add_child(top)
	stage.add_child(fx)
	overlay = Overlay.new()
	overlay.fade = 1.0
	view.add_child(overlay)
	camera = Camera.new()
	camera.attach(stage)
	if is_instance_valid(hud):
		hud.visible = false
		hud.modulate.a = 1.0
	boss_visual.visible = false
	_save_allies()
	choreo = CHOREO[boss].new()
	choreo.p = self
	choreo.prepare()
	duration = choreo.duration()
	set_process(true)
	_tick(0.0)

func _layer(n: String, z: int, shader_mode: int) -> Node2D:
	var l: Node2D = Layer.new()
	l.name = n
	l.z_index = z
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if shader_mode >= 0:
		var m := ShaderMaterial.new()
		m.shader = SPRITE_SHADER
		m.set_shader_parameter("mode", shader_mode)
		l.material = m
	return l

func shader(l: Node2D, key: String, value: Variant) -> void:
	(l.material as ShaderMaterial).set_shader_parameter(key, value)

func _process(delta: float) -> void:
	_tick(delta)

func _tick(delta: float) -> void:
	if state == "done" or state == "idle":
		return
	age += delta
	if is_instance_valid(sfx):
		sfx.advance(delta)
	camera.advance(delta)
	fx.advance(delta)
	fx_back.advance(delta)
	match state:
		"playing":
			choreo.advance(age, delta)
			if age >= duration:
				_begin_handoff()
		"handoff":
			_handoff_age += delta
			var k := clampf(_handoff_age / HUD_FADE, 0.0, 1.0)
			if is_instance_valid(hud):
				hud.modulate.a = k
			if k >= 1.0:
				_finish()
				return
	for l in [back, body, flat, allies, top]:
		if is_instance_valid(l):
			l.queue_redraw()
	if is_instance_valid(overlay):
		overlay.refresh()

## once: 時刻 t を過ぎた最初のフレームで1回だけ fn を呼ぶ。
func at(t: float, key: String, fn: Callable) -> void:
	if age >= t and not _fired.has(key):
		_fired[key] = true
		timeline_log.append([snappedf(age, 0.001), key])
		fn.call()

func se(t: float, key: String, gain: float = 0.0, from: float = 0.0, length: float = -1.0, pitch: float = 1.0) -> void:
	at(t, "se:%s@%s" % [key, t], func(): sfx.play(key, gain, from, length, pitch))

## 通常の戦闘へ戻す: カメラ・ボスの見た目・味方を元に戻し、HUD をフェードで出す（入力はまだ止めたまま）。
func _begin_handoff() -> void:
	timeline_log.append([snappedf(age, 0.001), "handoff"])
	state = "handoff"
	_handoff_age = 0.0
	_restore_world()
	if is_instance_valid(overlay):
		overlay.letterbox = 0.0
		overlay.vignette = 0.0
		overlay.title = {}
		overlay.fade = 0.0
		overlay.refresh()
	if is_instance_valid(hud):
		hud.visible = true
		hud.modulate.a = 0.0

func _finish() -> void:
	state = "done"
	timeline_log.append([snappedf(age, 0.001), "done"])
	_dispose()
	finished.emit()

## 途中でやめる（画面が隠れた・戦闘をやり直した・画面を出た）。すぐに元の見た目へ戻す。finished は出さない。
func cancel() -> void:
	if state == "done":
		return
	state = "done"
	timeline_log.append([snappedf(age, 0.001), "cancel"])
	if is_instance_valid(sfx):
		sfx.stop_all()
	_restore_world()
	_dispose()

func _restore_world() -> void:
	if camera != null:
		camera.reset()
	if is_instance_valid(stage):
		var visuals: Dictionary = stage.get("_visuals")
		if visuals.has("boss") and is_instance_valid(visuals["boss"]):
			var boss_visual: Control = visuals["boss"]
			boss_visual.visible = true
			boss_visual.modulate.a = 1.0
		_restore_allies()
		if stage.has_method("_reset_actors"):
			stage.call("_reset_actors")
	for l in [back, body, flat, allies, top]:
		if is_instance_valid(l):
			l.draw_fn = Callable()
	if is_instance_valid(fx):
		fx.clear()
	if is_instance_valid(fx_back):
		fx_back.clear()

func _dispose() -> void:
	set_process(false)
	if is_instance_valid(hud):
		hud.visible = true
		hud.modulate.a = 1.0
	if is_instance_valid(overlay):
		overlay.queue_free()
	for n in [back, fx_back, body, flat, allies, top, fx]:
		if is_instance_valid(n):
			n.queue_free()
	queue_free()

# ---------------------------------------------------------------------------
# 振付から使う道具

func boss_foot() -> Vector2:
	return stage.call("_foot", "boss")

func ally_keys() -> Array:
	return stage.get("_party_keys")

func ally_asset(key: String) -> String:
	return str(stage.get("_asset_ids")[key])

func ally_foot(key: String) -> Vector2:
	return stage.call("_foot", key)

## 味方の見た目のポーズ・位置を変える（本番の見た目をそのまま使う。戦闘の状態は変えない）。
func ally_pose(key: String, pose: int, offset: Vector2 = Vector2.ZERO) -> void:
	var visuals: Dictionary = stage.get("_visuals")
	if not visuals.has(key):
		return
	var v: Control = visuals[key]
	v.call("set_pose", pose)
	v.position = (Vector2(stage.get("_homes")[key]) + offset).round()

func _save_allies() -> void:
	_ally_saved.clear()
	var visuals: Dictionary = stage.get("_visuals")
	for key in visuals:
		if key == "boss":
			continue
		var v: Control = visuals[key]
		_ally_saved[key] = {"pose": int(v.get("pose")) if "pose" in v else 0, "position": v.position, "modulate": v.modulate, "visible": v.visible}

func _restore_allies() -> void:
	var visuals: Dictionary = stage.get("_visuals")
	for key in visuals:
		if key == "boss" or not is_instance_valid(visuals[key]):
			continue
		var v: Control = visuals[key]
		if _ally_saved.has(key):
			var s: Dictionary = _ally_saved[key]
			if v.has_method("set_pose"):
				v.call("set_pose", int(s.pose))
			v.position = s.position
			v.modulate = s.modulate
			v.visible = bool(s.visible)
		else:
			v.visible = true
			v.modulate = Color(1, 1, 1, v.modulate.a)
