extends Node2D
## 朽ちた機械武者の覚醒演出「封剣機構・解放」(承認済みv4)。既存の覚醒基盤
## (rbm_battle_stage.gd の"awakening"エントリ)から呼ばれる専用演出。
##
## 設計:
## - 覚醒は1戦闘1回・通常行動を消費しない既存仕様のまま。ここは確定済みの覚醒
##   エントリを表示するだけで、戦闘計算・条件判定・強化/回復オプションには触れない。
## - 終了時はステージ既存の_finish_awakening_entry()がimpact/finishedを1回ずつ出す。
## - 覚醒後の外見(musha_awakened)への切り替えは、本体が抜刀待機になる時刻に行う。
##   持続オーラは覚醒状態に追従する独立部品(rbm_musha_aura.gd)で、この演出は
##   出現区間(5.15〜5.65秒)の強さだけを渡す。
## - キャンセル/終了時は本体の可視性・揺れ・一時VFX・音を元へ戻す。覚醒後の外見と
##   持続オーラは覚醒状態そのものなので戻さない。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")
const GlyphMotion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")
const Body = preload("res://src/bossmaker/visuals/rbm_musha_awakened_body.gd")
const VFX = preload("res://src/bossmaker/visuals/rbm_musha_awakened_vfx.gd")
const AudioCatalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")

const SOUND_KEY := "musha_awakening"
const DURATION := Motion.AWAKENING_DURATION

var age := -1.0
var active := false
var _stage: Control
var _body: Node2D
var _vfx: Node2D
var _home := Vector2.ZERO
var _boss_visible := true
var _switched := false

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	stage._playing = true
	stage._phase = "awakening"
	stage._awakened_appearance_applied = false
	_home = stage._foot("boss")
	var boss: Control = stage._visuals["boss"]
	_boss_visible = boss.visible
	z_index = 3
	_body = Body.new()
	add_child(_body)
	_body.configure()
	_vfx = VFX.new()
	_vfx.z_index = 1
	_vfx.kind = "awakening"
	_vfx.home = _home
	_vfx.screen = Rect2(Vector2.ZERO, stage.size)
	add_child(_vfx)
	boss.visible = false
	if is_instance_valid(stage._musha_aura):
		stage._musha_aura.power_override = 0.0
		stage._musha_aura.refresh()
	_advance(0.0)
	if is_instance_valid(stage._sound):
		stage._sound.play_sound(SOUND_KEY, GlyphMotion.track_gain(SOUND_KEY))
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, DURATION, DURATION)
	tween.tween_callback(stage._finish_awakening_entry)
	return tween

## 完成トラックが音の全てを担う。
func play_sound_phase(_phase: String) -> bool:
	return true

## 再生の最初に load() する素材(rbm_presentation_warmup.gd が、覚醒する前の戦闘の間に裏で読み込んで持つ)。
## 覚醒後の本体の画像・外見を切り替えた後の待機の画像・完成トラック。
static func warm_paths(_asset_id: String, _kind: String) -> Array[String]:
	return [Body.ROOT + "awakened.png", Body.ROOT + "swing.png", RBMVisualAssets.frame_path("musha_awakened", 0),
		str(AudioCatalog.FILES[SOUND_KEY])]

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage):
		return
	age = t
	var shake := Motion.shake_offset(t, Motion.shake_force("awakening", t)).round()
	_body.advance(Motion.body_state("awakening", t), _home, t)
	_body.position = shake
	_vfx.position = shake
	_vfx.advance(t)
	for key in _stage._visuals:
		if key != "boss" and _stage._homes.has(key):
			_stage._visuals[key].position = (Vector2(_stage._homes[key]) + shake).round()
	if not _switched and t >= Motion.APPEARANCE_SWITCH:
		_switched = true
		_stage._awakened_appearance_applied = true
		_stage._apply_awakened_appearance()
	if is_instance_valid(_stage._musha_aura):
		_stage._musha_aura.power_override = Motion.aura_power(t)

func _restore_transform() -> void:
	if not is_instance_valid(_stage):
		return
	_stage._visuals["boss"].visible = _boss_visible
	_stage._visuals["boss"].position = _stage._homes["boss"]
	for key in _stage._visuals:
		if key != "boss" and _stage._homes.has(key):
			_stage._visuals[key].position = _stage._homes[key]
	if is_instance_valid(_stage._musha_aura):
		_stage._musha_aura.power_override = -1.0
		_stage._musha_aura.refresh()

func stop() -> void:
	_restore_transform()
	active = false
	visible = false
	_stage = null
