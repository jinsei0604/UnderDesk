extends Node2D
## 味方の覚醒の発動（2026-10-24、表示専用）。発動シーン（SCENES。少女は Codex の採用版、ほか4人は 2026-10-28 に採用した
## 新しい版で、どちらも Codex の sequence.gd の上に作られている）を戦闘のステージで再生するつなぎ。sequence.gd の advance() を
## この演出の Tween の時刻で進める（Codex の _process では進めない。中断・速さの扱いをほかの専用の演出とそろえる）。
## ここが持つのは: 本体の絵（既存のコマ。侍は s:18 と閉じた目）・画面の暗転と閃光・戦場のカメラ（2倍の寄り・揺れ）・
## 命中（impact = 解放の瞬間。HP・SP・覚醒の札・オーラがここで変わる）・後始末。戦闘の状態・乱数には触れない。
## 常時のオーラは別の部品（rbm_ally_awakening_auras.gd）が覚醒の状態に合わせて付け外しする。
const Frames = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_ally_frames.gd")
const ClosedEyes = preload("res://ally_awakening/core/samurai_closed_eyes.gd")
const Camera = preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
const AUDIO_DIR := "res://ally_awakening/audio/"
const AURA_SCENE := "res://ally_awakening/scenes/aura.tscn"
const IDS := ["hero", "butler", "healer", "samurai", "tank"]
## 発動のシーン（2026-10-28 ユーザーの決定: 勇者・老執事・侍・ハンマー使いは新しい版、少女は Codex の版のまま）。
## 2026-11-19 から第2版（ボスの演出と同じ部品で描く。rbm_ally_awakening_seq.gd）へ順に替えている: 勇者・老執事・少女（Codex の版を置き換え）・侍・ハンマー使い（5人とも）。
## 2026-11-19 ユーザー「全部ボスとのつながりが分かるように」: 勇者＝金環の聖獣の金環、老執事＝給仕長の文字盤、少女＝白磁のカラーの花、侍＝機械武者の墨、ハンマー使い＝熔鉱炉の番人の溶岩。
const SCENES := {
	"hero": "res://src/bossmaker/visuals/ally_awakening/rbm_hero_awakening_seq.tscn",
	"butler": "res://src/bossmaker/visuals/ally_awakening/rbm_butler_awakening_seq.tscn",
	"healer": "res://src/bossmaker/visuals/ally_awakening/rbm_healer_awakening_seq.tscn",
	"samurai": "res://src/bossmaker/visuals/ally_awakening/rbm_samurai_awakening_seq.tscn",
	"tank": "res://src/bossmaker/visuals/ally_awakening/rbm_tank_awakening_seq.tscn",
}
## 発動の中で使う既存の12ポーズ（各シーンの pose_at）。中割り（s:N）は Frames.warm_paths が読む。
const BODY_POSES := {"hero": [0, 8, 6], "butler": [0, 6, 8, 5], "healer": [0, 4, 9, 5], "samurai": [0], "tank": [0, 4, 5, 6, 8]}
## 第2版の音（1本。演出の0秒＝音の0秒）。ここに無い味方は Codex の charge/release の2本。
const V2_SOUNDS := {"hero": "res://assets_bossmaker/audio/ally_awakening/hero.wav", "butler": "res://assets_bossmaker/audio/ally_awakening/butler.wav", "healer": "res://assets_bossmaker/audio/ally_awakening/healer.wav", "samurai": "res://assets_bossmaker/audio/ally_awakening/samurai.wav", "tank": "res://assets_bossmaker/audio/ally_awakening/tank.wav"}
## 第2版が使うシェーダー（事前に読んで準備する）
const V2_SHADERS := ["res://src/bossmaker/visuals/hero_boss/shaders/blast.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/pillar.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/cracks.gdshader", "res://src/bossmaker/visuals/clock/shaders/clockface.gdshader", "res://src/bossmaker/visuals/flower/shaders/bloom.gdshader", "res://src/bossmaker/visuals/lion/shaders/eclipse.gdshader", "res://src/bossmaker/visuals/lava/shaders/magma.gdshader", "res://src/bossmaker/visuals/lava/shaders/eruption.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/ribbon.gdshader"]
## 本体に重ねる単色（閃光・照り）の描き方（登場・勝利と同じ、色だけを変えるシェーダー）
const FLAT_SHADER := "res://src/bossmaker/visuals/encounter/rbm_encounter_sprite.gdshader"
## 2倍の寄りの区間と中心（Codex のプレビュー studio.gd と同じ: 0.45 秒から終わりの 1.0 秒前まで、足元から 71px 上）。
const CLOSEUP_START := 0.45
const CLOSEUP_END_BEFORE := 1.0
const CLOSEUP_LIFT := 71.0
## 画面の閃光の色（Codex のプレビューと同じ）。
const FLASH_COLOR := Color(1.0, 0.98, 0.90)

var kind := "awakening_ally"
var active := false
var age := 0.0
var duration := 0.0
var _stage: Control
var _key := ""
var _asset := ""
var _actor: Control
var _sequence: Node2D
var _body: Node2D
## 本体に重ねる単色（第2版の閃光・照り）
var _body_flat: Node2D
var _flat_mat: ShaderMaterial
var _flat_alpha := 0.0
var _camera
var _dark: ColorRect
var _flash: ColorRect
var _frame := "b:0"
## 本体を描いている足元（ステージの座標）。オーラ（rbm_ally_awakening_auras.gd）もここを読む。
var _foot := Vector2.ZERO
var _closeup := false
var _impacted := false

static func has_presentation(asset_id: String) -> bool:
	return IDS.has(asset_id) and ResourceLoader.exists(str(SCENES[asset_id]))

## 再生中に読む物（rbm_presentation_warmup.gd が事前に読む）。発動シーン・音・本体のコマ（既存の12ポーズと中割り）・
## ハンマー使いの土煙・常時のオーラ。
static func warm_paths(asset_id: String, _kind: String) -> Array[String]:
	var paths: Array[String] = []
	if not IDS.has(asset_id):
		return paths
	paths.append(str(SCENES[asset_id]))
	if V2_SOUNDS.has(asset_id):
		paths.append(str(V2_SOUNDS[asset_id]))
		paths.append_array(V2_SHADERS)
		paths.append(FLAT_SHADER)
	else:
		paths.append(AUDIO_DIR + asset_id + "_charge.wav")
		paths.append(AUDIO_DIR + asset_id + "_release.wav")
	paths.append(AURA_SCENE)
	paths.append_array(Frames.warm_paths([asset_id]))
	for pose in BODY_POSES[asset_id]:
		paths.append(RBMVisualAssets.frame_path(asset_id, pose))
	return paths

func play(stage: Control) -> Tween:
	_stage = stage
	_key = str(stage._actor)
	_asset = str(stage._asset_ids.get(_key, ""))
	_actor = stage._visuals.get(_key)
	_foot = stage._foot(_key)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage._playing = true
	stage._phase = "ally_awakening"
	stage.visibility_changed.connect(_on_stage_visibility_changed)
	Frames.hold([_asset])
	# 画面の暗転（戦場だけ。HUD は戦場の外なので暗くならない）→ 発動の VFX → 本体 → 閃光、の順に重ねる。
	_dark = _overlay(Color(0, 0, 0, 0), 2)
	_sequence = (load(str(SCENES[_asset])) as PackedScene).instantiate()
	add_child(_sequence)
	_sequence.set_process(false)
	_sequence.foot_provider = func() -> Vector2: return _foot
	if is_instance_valid(stage._sound) and bool(stage._sound.muted):
		_sequence.sound_gain_db = -80.0
	_sequence.pose_requested.connect(_on_pose)
	_sequence.screen_requested.connect(_on_screen)
	_sequence.shake_requested.connect(_on_shake)
	_sequence.released.connect(_on_released)
	_body = Node2D.new()
	_body.z_index = 3
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.draw.connect(_draw_body)
	add_child(_body)
	_body_flat = Node2D.new()
	_body_flat.z_index = 3
	_body_flat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flat_mat = ShaderMaterial.new()
	_flat_mat.shader = load(FLAT_SHADER)
	_flat_mat.set_shader_parameter("mode", 1)
	_body_flat.material = _flat_mat
	_body_flat.draw.connect(_draw_body_flat)
	add_child(_body_flat)
	_flash = _overlay(Color(FLASH_COLOR, 0.0), 8)
	_camera = Camera.new()
	_camera.attach(stage)
	duration = float(_sequence.duration)
	if is_instance_valid(_actor):
		_actor.visible = false
	if not _sequence.prepare() or not _sequence.play():
		# 素材が無い時は演出を出さず、すぐ結果だけ反映して終える（戦闘は止めない）。
		active = false
		_emit_impact()
		var empty := create_tween()
		empty.tween_interval(0.0)
		empty.tween_callback(stage._finish)
		return empty
	_sequence.set_process(false)
	active = true
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, duration, duration)
	tween.tween_callback(_emit_impact)
	tween.tween_callback(stage._finish)
	return tween

func _overlay(color: Color, z: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = z
	rect.position = Vector2.ZERO
	rect.size = _stage.size
	add_child(rect)
	return rect

func _advance(t: float) -> void:
	if not active:
		return
	var dt := maxf(0.0, t - age)
	age = t
	_sequence.advance(t)
	_apply_body_light()
	if _camera != null:
		if t >= CLOSEUP_START and t < duration - CLOSEUP_END_BEFORE and not _closeup:
			_closeup = true
			_camera.cut(2, _foot - Vector2(0, CLOSEUP_LIFT))
		elif t >= duration - CLOSEUP_END_BEFORE and _closeup:
			_closeup = false
			_camera.cut(1, Vector2.ZERO)
		_camera.advance(dt)

## 第2版: 本体に重ねる単色（閃光が強い方を優先。照りは薄く重ねる）
func _apply_body_light() -> void:
	if not is_instance_valid(_body_flat) or not ("body_flash" in _sequence):
		return
	var flash := float(_sequence.body_flash)
	var lit := float(_sequence.body_lit) * 0.35
	var a := maxf(flash, lit)
	var col: Color = _sequence.body_flash_color if flash >= lit else _sequence.body_lit_color
	if absf(a - _flat_alpha) > 0.002 or a > 0.0:
		_flat_alpha = a
		_flat_mat.set_shader_parameter("flat_color", Color(col, 1.0))
		_body_flat.queue_redraw()

func _draw_body_flat() -> void:
	if _asset.is_empty() or _flat_alpha <= 0.003:
		return
	Frames.draw(_body_flat, _asset, _frame, _foot.round(), Color(1, 1, 1, _flat_alpha))

func _on_pose(frame: String) -> void:
	# 侍は発動の間、納刀（s:18）を保つ（Codex の引継ぎ: b:0 を s:18 へ読み替える）。
	_frame = "s:18" if _asset == "samurai" and frame == "b:0" else frame
	if is_instance_valid(_body):
		_body.queue_redraw()
	if is_instance_valid(_body_flat):
		_body_flat.queue_redraw()

func _on_screen(darkness: float, flash: float) -> void:
	if is_instance_valid(_dark):
		_dark.color.a = darkness
	if is_instance_valid(_flash):
		_flash.color.a = flash

func _on_shake(amplitude: float, shake_duration: float) -> void:
	if _camera != null:
		_camera.shake(amplitude, shake_duration)

## 解放の瞬間に、覚醒した後の HP・SP・札・オーラを出す（presenter がこの impact で表示を進める）。
func _on_released() -> void:
	_emit_impact()

func _emit_impact() -> void:
	if _impacted or not is_instance_valid(_stage):
		return
	_impacted = true
	_stage._phase = "impact"
	_stage.impact.emit(_stage._entry.duplicate(true))

func _draw_body() -> void:
	if _asset.is_empty():
		return
	var foot := _foot.round()
	Frames.draw(_body, _asset, _frame, foot)
	if _asset == "samurai" and _frame == "s:18":
		_body.draw_set_transform(foot)
		ClosedEyes.draw(_body)
		_body.draw_set_transform(Vector2.ZERO)

## 発動の音はステージの音と同じ扱い（ステージの _play_se は鳴らさない）。
func play_sound_phase(_phase: String) -> bool:
	return true

func _on_stage_visibility_changed() -> void:
	if active and is_instance_valid(_stage) and not _stage.is_visible_in_tree():
		_stage.cancel()

func stop() -> void:
	active = false
	if is_instance_valid(_stage) and _stage.visibility_changed.is_connected(_on_stage_visibility_changed):
		_stage.visibility_changed.disconnect(_on_stage_visibility_changed)
	if is_instance_valid(_sequence):
		for connection in [[_sequence.pose_requested, _on_pose], [_sequence.screen_requested, _on_screen], [_sequence.shake_requested, _on_shake], [_sequence.released, _on_released]]:
			if (connection[0] as Signal).is_connected(connection[1]):
				(connection[0] as Signal).disconnect(connection[1])
		_sequence.cancel()
	if _camera != null:
		_camera.reset()
		_camera = null
	if is_instance_valid(_actor):
		_actor.visible = true
	visible = false
