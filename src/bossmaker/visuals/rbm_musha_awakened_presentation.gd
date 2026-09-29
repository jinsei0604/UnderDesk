extends Node2D
## 覚醒後の朽ちた機械武者の専用演出(単体「境」/全体「界」、承認済みv4)。
##
## 設計:
## - 確定済みの行動結果(対象・足元・守護移動)だけを読んで再生する表示専用の演出。
##   戦闘計算・行動順・乱数・ダメージ・属性判定には触れない。
## - strike(=ダメージ表示の通知)は単体2.15秒/全体4.85秒の着弾へ一度だけ。予兆・
##   断裂・爆発のいくつもの見た目を多段ダメージとして扱わない。
## - 音は完成トラックを行動開始時に1回だけ流し、汎用SEは重ねない。
## - 本体は対象へ移動しない(その場で0.1秒の振り下ろし)。攻撃終了で覚醒状態や
##   持続オーラ(rbm_musha_aura.gd)は戻さない。中断・終了・反撃移行時は一時VFX・
##   揺れ・毛筆・本体の可視性を元へ戻す。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")
const Body = preload("res://src/bossmaker/visuals/rbm_musha_awakened_body.gd")
const VFX = preload("res://src/bossmaker/visuals/rbm_musha_awakened_vfx.gd")
const Brush = preload("res://src/bossmaker/visuals/rbm_musha_brush.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const GlyphMotion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")

## 単体の着弾中心(対象の高さの57%: 承認済み配置の老執事(105px)に対し60px)。
const HIT_HEIGHT_RATIO := 0.57
## 全体の中心: 対象の足元の平均から真上へ。
const CENTER_LIFT := 85.0
## 毛筆の位置(画面右上の戦闘領域。行動順パネル・ボス・断裂の中心と重ならない)。
const BRUSH_ANCHOR_X_RATIO := 0.60
const BRUSH_ANCHOR_Y := 205.0

## "single" | "all"
var kind := "single"
var duration := Motion.SINGLE_DURATION
var impact_time := Motion.SINGLE_IMPACT
var age := -1.0
var active := false

var _stage: Control
var _body: Node2D
var _vfx: Node2D
var _brush: Node2D
var _home := Vector2.ZERO
var _hit := false
var _boss_visible := true
var _attribute := "NEUTRAL"
var _target_keys: Array[String] = []
var _reacting: Dictionary = {}

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	duration = Motion.duration(kind)
	impact_time = Motion.impact_time(kind)
	stage._playing = true
	stage._phase = "musha_awakened_" + kind
	stage._motion_offset = Vector2.ZERO
	for key in stage._counters:
		stage._counter_offsets[key] = Vector2.ZERO
	_home = stage._foot("boss")
	var boss: Control = stage._visuals["boss"]
	_boss_visible = boss.visible
	z_index = 3
	_attribute = str(stage._skill.get("attribute", stage._entry.get("attribute", "NEUTRAL")))

	var feet: Array[Vector2] = []
	var hit_points: Array[Vector2] = []
	for key in stage._targets:
		if key == "boss":
			continue
		var foot: Vector2 = stage._foot(key) + Vector2(stage._guard_offsets.get(key, Vector2.ZERO))
		var height: float = stage.Assets.display_height(str(stage._asset_ids[key]))
		_target_keys.append(key)
		feet.append(foot)
		hit_points.append(foot - Vector2(0, height * HIT_HEIGHT_RATIO))
	var center := _home
	if not feet.is_empty():
		var sum := Vector2.ZERO
		for foot in feet:
			sum += foot
		center = sum / float(feet.size()) - Vector2(0, CENTER_LIFT)

	_body = Body.new()
	add_child(_body)
	_body.configure()
	_vfx = VFX.new()
	_vfx.z_index = 1
	_vfx.kind = kind
	_vfx.tint = Palette.color_for(_attribute)
	_vfx.home = _home
	_vfx.hit_at = hit_points[0] if not hit_points.is_empty() else _home
	_vfx.center = center
	_vfx.screen = Rect2(Vector2.ZERO, stage.size)
	_vfx.brush_at = Vector2(stage.size.x * BRUSH_ANCHOR_X_RATIO, BRUSH_ANCHOR_Y)
	add_child(_vfx)
	_brush = Brush.new()
	_brush.z_index = 5
	add_child(_brush)
	_brush.configure()
	boss.visible = false
	_advance(0.0)
	if is_instance_valid(stage._sound) and _plays_track_on_start():
		var track := "musha_awakened_single" if kind == "single" else "musha_awakened_aoe"
		stage._sound.play_sound(track, GlyphMotion.track_gain(track))
		if not stage._guards.is_empty():
			stage._sound.play_sound("cover_move", -5)
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, duration, duration)
	if stage._samurai_finish:
		tween.tween_callback(_restore_transform)
		var counter_duration: float = stage.SAMURAI_WIND_START_DELAY + stage.SamuraiWind.AFTERMATH_START + stage.SamuraiWind.AFTERMATH_DURATION + .05
		tween.tween_method(stage._samurai_finish_progress, 0.0, counter_duration, counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_callback(_restore_transform)
		tween.tween_method(stage._counter_progress, 0.0, 1.0, .20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

func play_sound_phase(_phase: String) -> bool:
	return true

## 完成トラックを行動開始時に鳴らすか(溜めを入れてから鳴らす派生の演出は false にして、自分で1回だけ鳴らす)。
func _plays_track_on_start() -> bool:
	return true

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage):
		return
	age = t
	var shake := Motion.shake_offset(t, Motion.shake_force(kind, t)).round()
	_body.advance(Motion.body_state(kind, t), _home, t)
	_body.position = shake
	_vfx.position = shake
	_vfx.advance(t)
	var anchor := Vector2(_stage.size.x * BRUSH_ANCHOR_X_RATIO, BRUSH_ANCHOR_Y)
	_brush.position = shake
	_brush.show_brush(GlyphMotion.glyph_index(_attribute), kind == "all", Motion.brush_age(kind, t), anchor)
	_layout_party(t, shake)
	if t >= impact_time and not _hit:
		_hit = true
		_stage._strike()

## 味方の位置・被弾表現(着弾から.24秒)と画面揺れ・守護(かばう)移動を、毎フレーム
## 「ホームからの絶対位置」として再計算する。
func _layout_party(t: float, shake: Vector2) -> void:
	for key in _stage._visuals:
		if key == "boss":
			continue
		var at: Vector2 = Vector2(_stage._homes[key])
		if _stage._guards.has(key):
			var progress := smoothstep(0.0, .5, t) * (1.0 - smoothstep(duration - .50, duration, t))
			at += Vector2(_stage._guard_offsets[key]) * progress
			_stage._pose(key, 10)
		elif _target_keys.has(key):
			var reacting := Motion.target_reacting(kind, t)
			if reacting != bool(_reacting.get(key, false)):
				_reacting[key] = reacting
				_stage._pose(key, _reaction_pose(key, reacting))
		_stage._visuals[key].position = (at + shake).round()

func _reaction_pose(key: String, reacting: bool) -> int:
	if reacting:
		return 10 if _stage._counters.has(key) else 11
	var unit: Dictionary = _stage._unit_state(key)
	if unit.get("is_downed", false):
		return 11
	return 10 if unit.get("is_defending", false) or _stage._counters.has(key) else 0

func _restore_transform() -> void:
	if not is_instance_valid(_stage):
		return
	_stage._visuals["boss"].visible = _boss_visible
	_stage._visuals["boss"].position = _stage._homes["boss"]
	for key in _stage._visuals:
		if key != "boss" and _stage._homes.has(key):
			_stage._visuals[key].position = _stage._homes[key]
	if is_instance_valid(_body):
		_body.visible = false
	if is_instance_valid(_vfx):
		_vfx.visible = false
	if is_instance_valid(_brush):
		_brush.hide_brush()

func stop() -> void:
	_restore_transform()
	active = false
	visible = false
	_stage = null
