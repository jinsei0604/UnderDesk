extends "res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_canvas.gd"
## Ink pressure ruptures into a torn brush explosion and broken armor facets.
const SOUNDS := ["enc:musha_break","enc:musha_stance"]
const VFX_PATHS := ["res://assets_bossmaker/effects/awakened_defeat/density.png","res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_ink.gdshader"]
const BURST := 0.62
const INK := Color("11131c")
const EDGE := Color("50434a")
const RED := Color("a63248")
const IVORY := Color("f1dfba")

func duration() -> float: return 2.60

func setup() -> void:
	super.setup()
	field.attach(p.top,"musha",core)

func advance(t: float,_dt: float) -> void:
	age = t
	bs.pose = 11
	bs.foot = home()+Vector2(12,0)
	white = smoothstep(0.35,BURST,t)*0.75
	dim(Color("12121c"),0.5*smoothstep(0.0,0.3,t)*(1.0-smoothstep(1.2,2.2,t)))
	p.at(0.0,"blade_resonance",func(): p.sfx.play("enc:musha_stance",-3.0,0.0,0.55,0.6))
	p.at(BURST,"ink_pressure_rupture",func():
		p.sfx.play("enc:musha_break")
		p.camera.shake(8,0.42))
	if t >= BURST+0.10: gone = true

func draw_top(ci: CanvasItem) -> void:
	if not active or age < BURST: return
	reset_mesh()
	var e := age-BURST
	# Uneven armor flecks follow the ink; only a few catch a small bevel highlight.
	for i in range(48):
		var a := i*2.39996
		var d := Vector2(cos(a),sin(a)*0.72)
		var life := 0.55+noise(i+30)*1.2
		var speed := 220+noise(i+5)*780
		var pos := core+d*speed*(1.0-exp(-e*1.8))*0.75+Vector2(0,130*e*e)
		var f := 1.0-smoothstep(life*0.5,life,e)
		var size := Vector2(3+noise(i+3)*9,2+noise(i+1)*4)*(1.0-smoothstep(0.8,1.8,e)*0.5)
		diamond(pos,size,a+e*1.6,Color(INK.lerp(EDGE,noise(i)),f))
		if i%5 == 0:
			line(pos,pos+Vector2(size.x*.65,1).rotated(a+e*1.6),2,Color(IVORY,f*.45))
	flush(ci)
