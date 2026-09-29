extends Node2D
## 朽ちた機械武者の専用演出(単体「無音の居合」/全体「縦断・千切」/自己強化・自己回復
## 「機構調律」)。承認済みの映像・音声(単体v3・全体v3・強化回復v1)の本番移植。
##
## 設計:
## - 確定済みの行動結果(対象・足元・守護移動)だけを読んで再生する表示専用の
##   演出。戦闘計算・行動順・乱数・ダメージには触れない。
## - strike(=ダメージ表示の通知)は単体・全体とも「巨大な最終斬撃」へ合わせて
##   一度だけ呼ぶ。初撃・28本の追撃では呼ばない(ダメージ重複実行の禁止)。
## - 音は完成トラックを行動開始時に1回だけ流し、汎用の属性cast/release/impact音や
##   別の納刀音は重ねない(play_sound_phase()で汎用SEを抑止する)。
## - 中断・終了・反撃移行時は本体の可視性/位置/揺れ/筆文字/VFXを必ず元へ戻す。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")
const Body = preload("res://src/bossmaker/visuals/rbm_musha_body.gd")
const VFX = preload("res://src/bossmaker/visuals/rbm_musha_vfx.gd")
const Glyph = preload("res://src/bossmaker/visuals/rbm_musha_glyph.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")

const BUFF_COLOR := Color("ef4847")
const HEAL_COLOR := Color("71da87")
## 単体/全体で対象の胴の中心を求める比率(承認済み配置: 老執事の高さ約105pxに対し51px)。
const HIT_HEIGHT_RATIO := 0.47
const HIT_REACTION_OFFSET := Vector2(-5, 0)

## "single" | "all" | "support"(supportは実行時にbuff/healへ解決される)
var kind := "single"
var action_kind := "single"
var duration := Motion.SINGLE_DURATION
var impact_time := Motion.SINGLE_FINAL
var age := -1.0
var active := false
var motion: Motion

var _stage: Control
var _body: Node2D
var _vfx: Node2D
var _glyph: Sprite2D
var _hit := false
var _boss_visible := true
var _sound_key := ""
var _attribute := "NEUTRAL"
var _color := Color.WHITE
var _target_keys: Array[String] = []
var _hit_points: Array[Vector2] = []
var _center := Vector2.ZERO
var _reacting: Dictionary = {}  # key -> bool
var _awakened := false

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	if kind == "support":
		action_kind = "heal" if str(stage._skill.get("effect", "")) in ["heal", "self_heal"] else "buff"
	else:
		action_kind = kind
	var timeline_kind := "support" if action_kind in ["buff", "heal"] else action_kind
	duration = Motion.duration(timeline_kind)
	impact_time = Motion.strike_time(timeline_kind)
	_sound_key = {"single": "musha_single", "all": "musha_aoe", "buff": "musha_buff", "heal": "musha_heal"}[action_kind]
	stage._playing = true
	stage._phase = "musha_" + action_kind
	stage._motion_offset = Vector2.ZERO
	for key in stage._counters:
		stage._counter_offsets[key] = Vector2.ZERO

	var boss: Control = stage._visuals["boss"]
	_boss_visible = boss.visible
	z_index = 3
	_attribute = str(stage._skill.get("attribute", stage._entry.get("attribute", "NEUTRAL")))
	_color = BUFF_COLOR if action_kind == "buff" else (HEAL_COLOR if action_kind == "heal" else Palette.color_for(_attribute))

	var feet: Array[Vector2] = []
	for key in stage._targets:
		if key == "boss":
			continue
		var foot: Vector2 = stage._foot(key) + Vector2(stage._guard_offsets.get(key, Vector2.ZERO))
		var height: float = stage.Assets.display_height(str(stage._asset_ids[key]))
		_target_keys.append(key)
		feet.append(foot)
		_hit_points.append(foot - Vector2(0, height * HIT_HEIGHT_RATIO))
	_center = _mean(feet) - Vector2(0, 38) if not feet.is_empty() else stage._foot("boss")

	motion = Motion.new()
	motion.configure(stage._foot("boss"), feet[0] if not feet.is_empty() else Vector2.ZERO)

	_awakened = str(stage._asset_ids.get("boss", "")) == "musha_awakened"
	_body = Body.new()
	_body.awakened = _awakened
	add_child(_body)
	_body.configure()
	_glyph = Glyph.new()
	_glyph.z_index = 1
	add_child(_glyph)
	_glyph.configure()
	_vfx = VFX.new()
	_vfx.z_index = 2
	_vfx.kind = "single" if action_kind == "single" else ("all" if action_kind == "all" else "support")
	_vfx.color = _color
	_vfx.hits = _hit_points
	_vfx.center = _center
	_vfx.home = stage._foot("boss")
	_vfx.screen = Rect2(Vector2.ZERO, stage.size)
	_vfx.awakened = _awakened
	add_child(_vfx)

	boss.visible = false
	_advance(0.0)
	if is_instance_valid(stage._sound):
		stage._sound.play_sound(_sound_key, Motion.track_gain(_sound_key))
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

## 完成トラックが音の全てを担うため、ステージの汎用SE(cast/release/impact)は出さない。
func play_sound_phase(_phase: String) -> bool:
	return true

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage):
		return
	age = t
	var timeline_kind := "support" if action_kind in ["buff", "heal"] else action_kind
	var shake := Motion.shake_offset(t, motion.shake_force(timeline_kind, t)).round()
	var body_state: Dictionary = motion.body_state(timeline_kind, t)
	if _awakened:
		body_state["pose"] = Motion.IDLE  # 覚醒後は納刀・俯く姿勢が無く、抜刀待機のまま
		body_state["scale_y"] = 1.0
	_body.advance(body_state)
	_body.position = shake
	_vfx.position = shake
	_vfx.advance(t)
	_update_glyph(timeline_kind, t, shake)
	_layout_party(timeline_kind, t, shake)
	if t >= impact_time and not _hit:
		_hit = true
		_stage._strike()

func _update_glyph(timeline_kind: String, t: float, shake: Vector2) -> void:
	if timeline_kind == "support":
		_glyph.visible = false
		return
	var state: Dictionary = motion.glyph_state(timeline_kind, t)
	var at := _center + Vector2(0, -12)
	if str(state["anchor"]) == "hit" and not _hit_points.is_empty():
		at = _hit_points[0] + Vector2(0, -24)
	_glyph.show_glyph(Motion.glyph_index(_attribute), float(state["age"]), at + shake, float(state["size"]), _color)

## 味方の位置・被弾表現。守護(かばう)移動、命中中の被弾、画面揺れを毎フレーム
## 「ホームからの絶対位置」として再計算する(加算し続けない)。
func _layout_party(timeline_kind: String, t: float, shake: Vector2) -> void:
	for key in _stage._visuals:
		if key == "boss":
			continue
		var at: Vector2 = Vector2(_stage._homes[key])
		if _stage._guards.has(key):
			var progress := smoothstep(0.0, .5, t) * (1.0 - smoothstep(duration - .50, duration, t))
			at += Vector2(_stage._guard_offsets[key]) * progress
			_stage._pose(key, 10)
		elif _target_keys.has(key) and timeline_kind != "support":
			var reacting := Motion.target_reacting(timeline_kind, t, _target_keys.find(key), _target_keys.size())
			if reacting:
				at += HIT_REACTION_OFFSET
			if reacting != bool(_reacting.get(key, false)):
				_reacting[key] = reacting
				_stage._pose(key, _reaction_pose(key, reacting))
		_stage._visuals[key].position = (at + shake).round()

func _reaction_pose(key: String, reacting: bool) -> int:
	if reacting and not _stage._counters.has(key):
		return 11
	if reacting:
		return 10
	var unit: Dictionary = _stage._unit_state(key)
	if unit.get("is_downed", false):
		return 11
	return 10 if unit.get("is_defending", false) or _stage._counters.has(key) else 0

static func _mean(points: Array[Vector2]) -> Vector2:
	var sum := Vector2.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())

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
	if is_instance_valid(_glyph):
		_glyph.visible = false

func stop() -> void:
	_restore_transform()
	active = false
	visible = false
	_stage = null
