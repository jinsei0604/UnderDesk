extends "res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_canvas.gd"
## Gunpowder pressure erupts sideways; the black coat disappears inside rolling smoke.
const SOUNDS := ["enc:gentleman_burst","enc:gent_vanish"]
const VFX_PATHS := ["res://assets_bossmaker/effects/awakened_defeat/density.png","res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_powder.gdshader"]
const BURST := 0.48
const BLACK := Color("171820")
const SMOKE := Color("49414b")
const RIM := Color("837078")
const FIRE := Color("d89b61")
const HOT := Color("ffe2b0")

func duration() -> float: return 2.65

func setup() -> void:
	super.setup()
	field.attach(p.top,"gentleman",core)

func advance(t: float,_dt: float) -> void:
	age = t
	bs.pose = 11
	bs.foot = home()+Vector2(10,0)
	white = smoothstep(0.2,BURST,t)*0.7
	dim(BLACK,0.48*smoothstep(0.0,0.3,t)*(1.0-smoothstep(1.2,2.3,t)))
	p.at(BURST,"powder_pressure_burst",func():
		p.sfx.play("enc:gentleman_burst")
		p.sfx.play("enc:gent_vanish",-7.0,0.0,1.7,0.7)
		p.camera.shake(8,0.38))
	if t >= BURST+0.10: gone = true

func draw_top(ci: CanvasItem) -> void:
	if not active or age < BURST: return
	reset_mesh()
	var e := age-BURST
	for i in range(52):
		var a := i*2.39996
		var d := Vector2(cos(a),sin(a)*.72)
		var life := .50+noise(i)*1.15
		var speed := 260+noise(i+7)*1100
		var pos := core+d*speed*(1.0-exp(-e*2.0))*.7+Vector2(0,125*e*e)
		var f := 1.0-smoothstep(life*.45,life,e)
		if i%4==0:
			diamond(pos,Vector2(5+noise(i)*5,2+noise(i)*3),a+e,Color(BLACK,f))
		else:
			# Short spent embers decelerate; no screen-wide light spokes.
			var tail := d*(3+noise(i)*12)*exp(-e*2)
			line(pos-tail,pos,2,Color(FIRE,f*.6))
			diamond(pos,Vector2(2,2),0,Color(HOT,f*.85))
	flush(ci)
