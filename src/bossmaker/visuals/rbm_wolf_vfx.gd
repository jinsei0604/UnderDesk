extends Node2D
const Motion=preload("res://src/bossmaker/visuals/rbm_wolf_motion.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const SUPPORT=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd").COLORS
var motion: Motion
var kind:="single"
var age:=-1.0
var attack_attribute:="NEUTRAL"
var feet: Array[Vector2]=[]

func dot(p: Vector2,side: int,c: Color) -> void:
	draw_rect(Rect2((p/4).floor(),Vector2(side,side)),c)

func line(a: Vector2,b: Vector2,c: Color,width: float=1) -> void:
	draw_line((a/4).floor(),(b/4).floor(),c,width,false)

func _draw() -> void:
	if age<0: return
	if kind=="single": bite(age-Motion.BITE_HIT)
	elif kind=="aoe": wake()
	else: howl()

func bite(t: float) -> void:
	if t<0 or t>.45: return
	var base: Color=Palette.color_for(attack_attribute)
	var q:=clampf(t/.22,0,1)
	var radius:=18+67*(1-pow(1-q,2))
	var alpha:=1-smoothstep(.17,.36,t)
	for y in range(-64,65,4):
		for x in range(-96,97,4):
			var p:=Vector2(x,y/.64)
			var r:=radius+sin(p.angle()*7)*4
			if p.length()>r or p.length()<r-11 or sin(p.angle()*11)>.94: continue
			var c:=base.lightened(.30)
			c.a=alpha
			dot(motion.contact+Vector2(x,y),1,c)
	# Two opposing tooth-side pressure marks, leaving the muzzle visible.
	if t<.13:
		for sign_y in [-1,1]:
			var c:=base.lightened(.55)
			c.a=1-t/.13
			line(motion.contact+Vector2(-19,sign_y*29),motion.contact+Vector2(-7,sign_y*15),c,2)
	for i in range(6):
		var p:=motion.contact+Vector2(-30-i*8,sin(i*2.3)*70)*t+Vector2(0,90*t*t)
		var c:=base
		c.a=(1-t/.45)*.6
		dot(p,1,c)

func wake() -> void:
	var base: Color=Palette.color_for(attack_attribute)
	# Staggered curls appear only behind locations the wolf has already passed.
	for i in range(15):
		var born:=Motion.AOE_START+.035+i*.053
		var t:=age-born
		if t<0 or t>1.50: continue
		var q:=clampf((born-Motion.AOE_START)/Motion.AOE_RUN,0,1)
		var center:=motion.path_point(q)-Vector2(0,24)
		var direction:=(motion.path_point(minf(q+.02,.999))-motion.path_point(maxf(q-.02,0))).normalized()
		var fade:=smoothstep(0,.06,t)*(1-smoothstep(.60,1.50,t))
		for band in range(4):
			var prev:=Vector2.ZERO
			for step in range(25):
				var u:=float(step)/24
				var turn:=u*PI*(1.10+.16*(i%3))+.3*(i%3)
				var p:=center-direction*(u*(140+band*24)+t*46)+Vector2(cos(turn)*(27+band*11),-sin(turn)*(36+band*14)-t*24-band*15)
				var c:=base.lightened(.12 if band==0 else 0) if band!=2 else Color("b7bbc2")
				c.a=fade*(.92 if band!=2 else .32)*(1-u*.50)
				if step>0 and step%9!=0:
					line(prev,p,c,3 if band==0 else (2 if band==1 else 1))
					if band==0 and u<.6:
						var rim:=base.lightened(.48)
						rim.a=fade*(1-u)*.70
						line(prev-Vector2(0,4),p-Vector2(0,4),rim)
				prev=p
		for chip in range(6):
			var c:=base.lightened(.22)
			c.a=fade*.82
			dot(center-direction*(t*96+chip*14)+Vector2(0,-t*(56+chip*19)),2 if chip%4==0 else 1,c)
	var hit:=age-Motion.AOE_HIT
	if hit>=0 and hit<.38:
		for foot in feet:
			for i in range(3):
				var c:=base.lightened(.28)
				c.a=(1-hit/.38)*.90
				var p:=foot+Vector2(-46+i*22,-24-i*19)
				line(p+Vector2(-hit*80,22),p+Vector2(40+hit*45,-22),c,2)

func howl() -> void:
	if age>.0 and age<2.12:
		var base: Color=SUPPORT[kind]
		var strength:=smoothstep(.15,.48,age)*(1-smoothstep(1.55,2.12,age))
		for i in range(17):
			var t:=age-.12-fmod(i*.173,.55)
			if t<0 or t>1.55: continue
			var c:=base.lightened(.15)
			c.a=strength*(1-smoothstep(.9,1.55,t))*.70
			dot(motion.home+Vector2(sin(i*2.21)*88,-16-fmod(i*13,40)-t*66),2 if i%6==0 else 1,c)
		# Brief upward sound-front arcs from the existing raised muzzle.
		for index in range(2):
			var t:=age-.55-index*.18
			if t<0 or t>.48: continue
			var radius:=16+t*86
			var origin:=motion.home+(Vector2(151,183)-Vector2(256,460))*Motion.SCALE
			var previous:=Vector2.ZERO
			for step in range(13):
				var angle:=lerpf(-2.55,-1.08,step/12.0)
				var p:=origin+Vector2(cos(angle),sin(angle))*radius
				var c:=base.lightened(.30)
				c.a=sin(t/.48*PI)*.65
				if step>0: line(previous,p,c)
				previous=p
