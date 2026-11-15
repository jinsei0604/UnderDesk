extends "res://src/bossmaker/visuals/rbm_character_visual.gd"
## 熔鉱炉の番人／噴界炉の巨神（lava）の立ち絵。覚醒後（lava_awakened）は常時の溶岩色のオーラ（2026-11-14 ユーザー採用）をまとう。
## オーラは立ち姿のキーポーズの輪郭から焼いた距離（RBMLavaSunAura）で描き、本体の絵は変えない。表示専用。

const AWAKENED_ID := "lava_awakened"

var _aura: RBMLavaSunAura
var _aura_t := 0.0

func setup(id: String, height: float) -> void:
	super.setup(id, height)
	if is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null
	if id == AWAKENED_ID:
		_aura = RBMLavaSunAura.new()
		_aura.name = "LavaSunAura"
		_aura.show_behind_parent = true
		_aura.scale = Vector2.ONE * _pixel_scale
		# オーラはキーポーズ（320×180）の座標で描く。立ち絵はその STANCE_CROP を切り出した物
		_aura.position = -Vector2(RBMLavaMotion.STANCE_CROP.position) * _pixel_scale
		add_child(_aura)
		_aura.setup()
		_update_aura()

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_aura) and is_visible_in_tree():
		_aura_t += delta
		_update_aura()

func _update_aura() -> void:
	var stance: Array = RBMLavaMotion.STANCE["post"]
	_aura.show_pose(str(stance[0]), int(stance[1]), Vector2.ZERO, RBMLavaMotion.ORIGIN, 1.0, _aura_t)
