extends "res://src/bossmaker/visuals/rbm_character_visual.gd"
## 振り子の給仕長／終刻の給仕長（clock）の立ち絵。覚醒後（clock_awakened）は常時の真夜中の青緑のオーラをまとう。
## オーラは立ち姿のキーポーズの輪郭から焼いた距離（RBMClockSunAura）で描き、本体の絵は変えない。表示専用。

const AWAKENED_ID := "clock_awakened"

var _aura: RBMClockSunAura
var _aura_t := 0.0

func setup(id: String, height: float) -> void:
	super.setup(id, height)
	if is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null
	if id == AWAKENED_ID:
		_aura = RBMClockSunAura.new()
		_aura.name = "ClockSunAura"
		_aura.show_behind_parent = true
		_aura.scale = Vector2.ONE * _pixel_scale
		# オーラはキーポーズ（320×180）の座標で描く。立ち絵はその STANCE_CROP を切り出した物
		_aura.position = -Vector2(RBMClockMotion.STANCE_CROP.position) * _pixel_scale
		add_child(_aura)
		_aura.setup()
		_update_aura()

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_aura) and is_visible_in_tree():
		_aura_t += delta
		_update_aura()

func _update_aura() -> void:
	var stance: Array = RBMClockMotion.STANCE["post"]
	_aura.show_pose(str(stance[0]), int(stance[1]), Vector2.ZERO, RBMClockMotion.ORIGIN, 1.0, _aura_t)
