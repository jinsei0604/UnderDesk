extends "res://src/bossmaker/visuals/rbm_character_visual.gd"
## 金環の聖獣／日蝕の獅皇（lion）の立ち絵。覚醒後（lion_awakened）は常時の太陽のオーラ（2026-11-12 ユーザー採用）をまとう。
## オーラは立ち姿のキーポーズの輪郭から焼いた距離（RBMLionSunAura）で描き、本体の絵は変えない。表示専用。

const AWAKENED_ID := "lion_awakened"

var _aura: RBMLionSunAura
var _aura_t := 0.0

func setup(id: String, height: float) -> void:
	super.setup(id, height)
	if is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null
	if id == AWAKENED_ID:
		_aura = RBMLionSunAura.new()
		_aura.name = "LionSunAura"
		_aura.show_behind_parent = true
		_aura.scale = Vector2.ONE * _pixel_scale
		# オーラはキーポーズ（320×180）の座標で描く。立ち絵はその STANCE_CROP を切り出した物
		_aura.position = -Vector2(RBMLionMotion.STANCE_CROP.position) * _pixel_scale
		add_child(_aura)
		_aura.setup()
		_update_aura()

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_aura) and is_visible_in_tree():
		_aura_t += delta
		_update_aura()

func _update_aura() -> void:
	var stance: Array = RBMLionMotion.STANCE["post"]
	_aura.show_pose(str(stance[0]), int(stance[1]), Vector2.ZERO, RBMLionMotion.ORIGIN, 1.0, _aura_t)
