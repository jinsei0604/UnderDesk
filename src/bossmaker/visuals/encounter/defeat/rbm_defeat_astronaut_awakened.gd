extends "res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_canvas.gd"
## Gravity locks inward; a stellar core detonates into orbital ejecta.
const SOUNDS := ["enc:astro_collapse","enc:astro_static"]
const VFX_PATHS := ["res://assets_bossmaker/effects/awakened_defeat/density.png","res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_nebula.gdshader"]
const BURST := 0.70
const DARK := Color("211634")
const PURPLE := Color("7853c8")
const PINK := Color("d9a4ef")
const WHITE := Color("fff2ff")

func duration() -> float: return 2.70

func setup() -> void:
	super.setup()
	field.attach(p.top,"astronaut",core)

func advance(t: float,_dt: float) -> void:
	age = t
	bs.pose = 11
	bs.foot = home()+Vector2(10,0)
	white = smoothstep(0.2,BURST,t)*0.95
	dim(DARK,0.70*smoothstep(0.0,0.4,t)*(1.0-smoothstep(1.35,2.4,t)))
	p.at(0.0,"radio_cut",func(): p.sfx.play("enc:astro_static",-4.0,0.0,0.5,0.65))
	p.at(BURST,"stellar_detonation",func():
		p.sfx.play("enc:astro_collapse")
		p.camera.shake(7,0.48))
	if t >= BURST+0.10: gone = true

func draw_top(ci: CanvasItem) -> void:
	if not active: return
	reset_mesh()
	if age < BURST:
		var q := smoothstep(0.0,BURST,age)
		for i in range(30):
			var a := i*2.39996+q*.18
			var r := (120+noise(i)*430)*(1.0-q*.94)
			var pos := core+Vector2(cos(a),sin(a)*.8)*r
			diamond(pos,Vector2(2,2),0,Color(PINK,q*.65))
	else:
		var e := age-BURST
		for i in range(82):
			var life := .5+noise(i+80)*1.25
			var a := i*2.39996
			var d := Vector2(cos(a),sin(a)*.78)
			var r := (170+noise(i+3)*1000)*(1.0-exp(-e*2.2))
			var pos := core+d.rotated(e*.10)*r
			var f := (1.0-smoothstep(life*.4,life,e))*(.5+noise(i)*.5)
			var size := 1.5+noise(i+4)*2
			diamond(pos,Vector2(size,size),0,Color(PINK.lerp(WHITE,noise(i)),f))
			if i%11==0:
				line(pos-Vector2(0,4),pos+Vector2(0,4),2,Color(WHITE,f*.65))
	flush(ci)
