extends Node2D
## One golem motion for both support actions. No combat state or attribute input.
const VFX=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")
const IMPACT:=1.50
const DURATION:=2.85
var age:=-1.0
var mode:="buff"
var active:=false
var _stage: Control
var _vfx: Node2D
var _impact_sent:=false

static func pose_at(t: float) -> int:
	if t<0: return 0
	if t<.38: return 8
	if t<1.50: return 6
	if t<2.16: return 7
	# Approved revision: return directly to idle, with no second crouch.
	return 0

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	mode="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	z_index=3
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	stage._playing=true
	stage._phase="golem_support"
	stage._motion_offset=Vector2.ZERO
	var viewport:=SubViewport.new()
	viewport.size=Vector2i((stage.size/4).ceil())
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_vfx=VFX.new()
	_vfx.origin=stage._foot("boss")-Vector2(0,10)
	_vfx.mode=mode
	viewport.add_child(_vfx)
	var display:=Sprite2D.new()
	display.texture=viewport.get_texture()
	display.centered=false
	display.scale=Vector2(4,4)
	display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(display)
	stage._play_se("cast")
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,DURATION,DURATION)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active: return
	age=t
	_stage._pose("boss",pose_at(t))
	_stage._visuals["boss"].position=_stage._homes["boss"]
	_vfx.age=t
	_vfx.queue_redraw()
	if t>=IMPACT and not _impact_sent:
		_impact_sent=true
		_stage._strike()
	queue_redraw()

func _draw() -> void:
	if not active or not is_instance_valid(_stage): return
	var glow:=smoothstep(.9,1.50,age)*(1-smoothstep(1.52,1.90,age))*.14
	if glow<=0: return
	var visual: Control=_stage._visuals["boss"]
	var tint: Color=VFX.COLORS[mode].lightened(.40)
	tint.a=glow
	draw_texture_rect(visual._texture,Rect2(visual.position,visual.size),false,tint)

func stop() -> void:
	active=false
	visible=false
	_stage=null
