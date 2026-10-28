extends Node
## 味方の覚醒の常時オーラ（2026-10-24、表示専用）。Codex のオーラ（res://ally_awakening/scenes/aura.tscn）を、ステージが
## 表示している状態（set_state()。presenter が命中の瞬間に進める）の "awakened" に合わせて味方ごとに付け外しする。
## - 演出の再生中に覚醒した（発動の解放の瞬間）時は 0.4 秒で現し、REWIND・画面の作り直しではすぐ出す。
## - 覚醒が解けた・戦闘不能（覚醒も解ける）・状態に無い時は 0.4 秒で消す（作り直し・別の戦闘ではすぐ消す）。
## - 足元は、その味方の絵を専用の演出が描いている間はその演出の足元（_foot）、それ以外はステージの絵の足元。
## 戦闘の状態・乱数には触れない。
const AllyAwakening = preload("res://src/bossmaker/visuals/rbm_ally_awakening_presentation.gd")
## オーラの奥の層の重なり（味方の絵 z=2 と同じ高さで、ステージの子の先頭へ置いて絵の後ろにする。手前の層は +2 で絵の前）。
const AURA_Z := 2

var stage: Control
## 味方のキー（ステージの _visuals のキー）→ オーラ
var _auras: Dictionary = {}

func configure(st: Control) -> void:
	stage = st

## ステージの表示している状態に合わせる（set_state() のたびに呼ぶ。同じなら何もしない）。
func sync() -> void:
	if not is_instance_valid(stage):
		return
	for key in _auras.keys():
		if not stage._visuals.has(key) or not stage._party_keys.has(key):
			_dispose(key)
	for key in stage._party_keys:
		var unit: Dictionary = stage._unit_state(key)
		var awakened := bool(unit.get("awakened", false)) and not bool(unit.get("is_downed", false))
		var aura: Node2D = _auras.get(key)
		if awakened:
			if aura == null:
				aura = _create(key)
				if aura == null:
					continue
			if not bool(aura.active):
				aura.start(stage.is_playing())
		elif aura != null and bool(aura.active):
			aura.stop(not stage.is_playing())

## すべて消す（別の戦闘へ替わる時・戦闘を出る時）。
func clear() -> void:
	for key in _auras.keys():
		_dispose(key)

## 付いているオーラ（テスト・検証用）。{キー: オーラ}
func auras() -> Dictionary:
	return _auras.duplicate()

func _create(key: String) -> Node2D:
	var asset := str(stage._asset_ids.get(key, ""))
	if not AllyAwakening.IDS.has(asset) or not ResourceLoader.exists(AllyAwakening.AURA_SCENE):
		return null
	var aura: Node2D = (load(AllyAwakening.AURA_SCENE) as PackedScene).instantiate()
	aura.name = "AllyAwakeningAura_%s" % key
	aura.character_id = asset
	aura.foot_provider = _foot_of.bind(key)
	stage.add_child(aura)
	stage.move_child(aura, 0)
	aura.z_index = AURA_Z
	aura.position = _foot_of(key).round()
	_auras[key] = aura
	return aura

func _foot_of(key: String) -> Vector2:
	if not is_instance_valid(stage):
		return Vector2.ZERO
	var presentation = stage._skill_presentation
	if is_instance_valid(presentation) and str(stage._actor) == key and stage._visuals.has(key) and not stage._visuals[key].visible and "_foot" in presentation:
		return Vector2(presentation.get("_foot")) + Vector2(presentation.position)
	return stage._foot(key)

func _dispose(key: String) -> void:
	var aura: Node2D = _auras.get(key)
	_auras.erase(key)
	if is_instance_valid(aura):
		aura.stop(true)
		aura.queue_free()
