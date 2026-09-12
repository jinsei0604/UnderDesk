extends Node2D
## Healer HP recovery only. Visuals consume resolved entries; never mutate battle.
const IMPACT_TIME := 3.05
const DURATION := 6.1
var active := false
var _stage: Control
var _emitted := false

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	_emitted = false
	visible = true
	feet.clear()
	var factor := 1.0 if stage.has_meta("fullscreen_formation") else minf(stage.size.x/1280.0,stage.size.y/720.0)
	scale = Vector2.ONE*factor
	for key in stage._targets: feet.append(stage._foot(key)/factor)
	stage._playing = true
	stage._phase = "skill_specific"
	stage._pose(stage._actor,4)
	update_time(0.0)
	var tween := create_tween()
	tween.tween_method(_advance,0.0,DURATION,DURATION)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active: return
	update_time(t)
	if t >= 22.0/60.0: _stage._pose(_stage._actor,5)
	if t >= IMPACT_TIME and not _emitted:
		_emitted = true
		_stage._sound.play_sound("heal_hp",-4.0)
		_stage.impact.emit(_stage._entry.duplicate(true))

func stop() -> void:
	active = false
	visible = false
	_stage = null
	feet.clear()
	if is_instance_valid(mat):
		mat.set_shader_parameter("opacity",0.0)
	queue_redraw()

var age := 0.0
var feet: Array[Vector2] = []
var saint: Sprite2D
var mat: ShaderMaterial
func _ready() -> void:
	saint = Sprite2D.new()
	saint.texture = preload("res://assets_bossmaker/battle/vfx/healer_saint/saint.png")
	saint.centered = false
	saint.position = Vector2(124, 88)
	saint.scale = Vector2(352,440) / Vector2(saint.texture.get_size())
	saint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mat = ShaderMaterial.new()
	mat.shader = preload("res://src/bossmaker/visuals/rbm_healer_saint.gdshader")
	saint.material = mat
	add_child(saint)
	visible = false
func update_time(t: float) -> void:
	age = t
	var appear := smoothstep(0.5,1.65,t)
	var vanish := smoothstep(4.4,5.8,t)
	mat.set_shader_parameter("opacity",0.38*appear*(1.0-vanish))
	mat.set_shader_parameter("dissolve",smoothstep(4.1,5.9,t))
	queue_redraw()
func _draw() -> void:
	var gather := smoothstep(0.0,0.6,age)*(1.0-smoothstep(1.4,2.2,age))
	var spread := smoothstep(1.9,2.8,age)*(1.0-smoothstep(3.4,5.3,age))
	var peak := maxf(0.0,1.0-absf(age-3.05)/0.4)
	for n in range(feet.size()):
		var foot: Vector2 = feet[n]
		# A short trail leads from the praying hands to each recipient.
		for j in range(20):
			var travel := (age-1.9)*1.1-float(j)*0.015
			if travel > 0.0 and travel < 1.0:
				var p := Vector2(396,330).lerp(foot-Vector2(0,42),travel)
				p.y -= sin(travel*PI)*32.0
				p += Vector2(sin(j*4.7+n)*6.0,cos(j*2.3)*5.0)
				p = (p/4.0).floor()*4.0
				draw_rect(Rect2(p,Vector2(4,4)),Color(0.91,0.97,0.76,sin(travel*PI)*0.65))
		# Broken, rising curtains: no rings, stars or geometric glyphs.
		for yy in range(0,156,4):
			for xx in range(-48,49,4):
				var drift := sin(float(yy)*0.055+age*2.0+n)*11.0 + sin(float(yy)*0.13+n)*5.0
				var breadth := 21.0+sin(float(yy)*0.083+n*1.7)*9.0+peak*13.0
				var strength := maxf(0.0,1.0-absf(xx-drift)/breadth)*maxf(0.0,1.0-float(yy)/156.0)
				strength = floorf(strength*5.0)/5.0
				if strength > 0.0:
					draw_rect(Rect2(foot+Vector2(xx,-yy),Vector2(4,4)),Color(0.73,0.95,0.8,strength*(spread*0.28+peak*0.44)))
		for i in range(28):
			var phase := fmod(age*0.31+i*0.137+n*0.11,1.0)
			var x := sin(i*7.13+n*2.0)*52.0*(0.4+phase)
			var p := foot+Vector2(x,-phase*164.0)
			p = (p/4.0).floor()*4.0
			var alpha := sin(phase*PI)*(spread*0.6+gather*0.32)
			draw_rect(Rect2(p,Vector2(4 if i%4 else 8,4)),Color(0.88,0.98,0.76,alpha))
	# Sparse fragments rise from the vanishing veil and shoulders.
	var ending := smoothstep(4.0,4.6,age)*(1.0-smoothstep(5.1,6.1,age))
	for i in range(68):
		var x := 150.0+fmod(i*57.7,280.0)
		var y := 170.0+fmod(i*41.3,300.0)-(age-4.0)*24.0
		var p := (Vector2(x,y)/4.0).floor()*4.0
		draw_rect(Rect2(p,Vector2(4,4)),Color(0.82,0.94,0.8,ending*0.24))
