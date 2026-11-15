extends "res://src/bossmaker/visuals/rbm_character_visual.gd"
## 白磁のカラー／喪華のカラー女王（flower）の立ち絵。覚醒後（flower_awakened）は常時の喪華の深紅紫のオーラ（2026-11-14 ユーザー採用）をまとう。
## オーラは立ち姿のキーポーズの輪郭から焼いた距離（RBMFlowerSunAura）で描き、本体の絵は変えない。表示専用。

const AWAKENED_ID := "flower_awakened"

var _aura: RBMFlowerSunAura
var _aura_t := 0.0

func setup(id: String, height: float) -> void:
	super.setup(id, height)
	if is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null
	if id == AWAKENED_ID:
		_aura = RBMFlowerSunAura.new()
		_aura.name = "FlowerSunAura"
		_aura.show_behind_parent = true
		_aura.scale = Vector2.ONE * _pixel_scale
		# オーラはキーポーズ（320×180）の座標で描く。立ち絵はその STANCE_CROP を切り出した物
		_aura.position = -Vector2(RBMFlowerMotion.STANCE_CROP.position) * _pixel_scale
		add_child(_aura)
		_aura.setup()
		_update_aura()

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_aura) and is_visible_in_tree():
		_aura_t += delta
		_update_aura()

func _update_aura() -> void:
	var stance: Array = RBMFlowerMotion.STANCE["post"]
	_aura.show_pose(str(stance[0]), int(stance[1]), Vector2.ZERO, RBMFlowerMotion.ORIGIN, 1.0, _aura_t)
