extends Node2D
## A child of the original hero sprite: follows every pose, movement and parent visibility.
const Flame = preload("res://src/bossmaker/visuals/rbm_hero_flame.gd")
# Native 1024x512 frame coordinates, measured at the guard and blade point.
const HANDS = [Vector2(288,326),Vector2(302,324),Vector2(545,270),Vector2(511,310),Vector2(369,276),Vector2(537,293),Vector2(438,232),Vector2(303,253),Vector2(384,180),Vector2(440,382),Vector2(372,290),Vector2(276,360)]
const TIPS = [Vector2(233,436),Vector2(190,424),Vector2(686,181),Vector2(671,356),Vector2(492,274),Vector2(691,291),Vector2(438,99),Vector2(305,123),Vector2(384,64),Vector2(522,464),Vector2(254,194),Vector2(171,447)]
var _stage: Control
var _key := ""
func setup(stage: Control, actor_key: String) -> void:
	_stage=stage
	_key=actor_key
	z_index=2
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	visible=false
func _process(_delta: float) -> void:
	visible=is_instance_valid(_stage) and Flame.is_active(_stage._state,_key)
	if visible: queue_redraw()
func _draw() -> void:
	if not is_instance_valid(_stage) or not Flame.is_active(_stage._state,_key): return
	var actor: Control=get_parent()
	var pose: int=actor.pose
	if pose<0 or pose>=HANDS.size(): return
	var pixel_scale: float=actor._pixel_scale
	Flame.draw_blade(self,HANDS[pose]*pixel_scale,TIPS[pose]*pixel_scale,float(Time.get_ticks_msec())/1000.0)
