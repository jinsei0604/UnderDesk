extends Node2D
const Motion=preload("res://src/bossmaker/visuals/rbm_knight_motion.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const Support=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")
const SUPPORT=Support.COLORS
var motion: RefCounted
var _support: Node2D

func _ready() -> void:
	_support=Support.new()
	add_child(_support)

func advance(t: float) -> void:
	age=t
	_support.origin=motion.home+Vector2(0,-10)
	_support.age=t if kind in SUPPORT else -1.0
	_support.mode=kind if kind in SUPPORT else "buff"
	_support.queue_redraw()
	queue_redraw()
var kind:="single"
var age:=-1.0
var attack_attribute:="NEUTRAL"
var feet: Array[Vector2]=[]

func polygon(points: Array,c: Color) -> void:
	var packed:=PackedVector2Array()
	for p in points: packed.append((Vector2(p)/4).floor())
	# Pixel snapping can collapse the last, nearly invisible frame to a line.
	var area:=0.0
	for i in range(packed.size()): area+=packed[i].cross(packed[(i+1)%packed.size()])
	if absf(area)<1.0: return
	draw_colored_polygon(packed,c)

func line(a: Vector2,b: Vector2,c: Color,width: float=1) -> void:
	draw_line((a/4).floor(),(b/4).floor(),c,width,false)

func _draw() -> void:
	if age<0: return
	if kind=="single": slash()
	elif kind=="aoe": wave()

func slash() -> void:
	var t:=age-Motion.SINGLE_HIT
	if t<0 or t>.38: return
	var base: Color=Palette.color_for(attack_attribute)
	var fade:=1-smoothstep(.15,.38,t)
	var center: Vector2=motion.contact+Vector2(17,-28)
	var axis:=Vector2(-.67,.74)
	var side:=Vector2(-axis.y,axis.x)
	var reach:=66+18*clampf(t/.12,0,1)
	var width:=12*(1-smoothstep(.05,.34,t))
	base.a=fade*.90
	if width>4:
		polygon([center-axis*reach,center-axis*22+side*width,center+axis*reach,center+axis*18-side*width],base)
	var core:=base.lightened(.50)
	core.a=fade
	line(center-axis*reach,center+axis*reach,core,1)
	for i in range(5):
		var p:=center+axis*(i-2)*24+side*(10+t*80)
		var c:=base
		c.a=fade*.65
		line(p-axis*8,p+axis*(9+i*2),c)

# A single curved cutting edge, open behind it. Same launch / travel timing.
func blade_point(u: float, front: Vector2, growth: float) -> Vector2:
	return front+Vector2((177*u*u+27*u)*growth,153*u*growth)

func blade_ribbon(front: Vector2,growth: float,width: float,offset: float,c: Color) -> void:
	var outside: Array=[]
	var inside: Array=[]
	for i in range(17):
		var u: float=-1.0+i/8.0
		var taper:=maxf(0,1-u*u)
		var point:=blade_point(u,front,growth)
		outside.append(point+Vector2(offset*taper*growth,0))
		inside.push_front(point+Vector2((offset+width)*taper*growth,0))
	# Narrow tips can collapse after pixel snapping; render nondegenerate triangles.
	inside.reverse()
	for i in range(outside.size()-1):
		polygon([outside[i],outside[i+1],inside[i]],c)
		polygon([outside[i+1],inside[i+1],inside[i]],c)

func wave() -> void:
	var t:=age-.62
	if t<0 or t>.88: return
	var q:=clampf(t/.66,0,1)
	var front: Vector2=motion.wave_source+Vector2(-650*q,0)
	var growth:=smoothstep(0,.12,t)
	if growth<.15: return
	var fade:=1-smoothstep(.59,.88,t)
	var base: Color=Palette.color_for(attack_attribute)
	# Dark back, attribute blade, narrow bright cutting edge: no filled projectile.
	var wake:=base.darkened(.15)
	wake.a=fade*.38
	blade_ribbon(front,growth,72,21,wake)
	base.a=fade*.92
	blade_ribbon(front,growth,38,0,base)
	var edge:=base.lightened(.55)
	edge.a=fade
	blade_ribbon(front,growth,11,0,edge)
	# Broken curved remnants follow the sword sweep, rather than straight speed bars.
	for fragment in range(5):
		var start: float=[-.94,-.58,-.16,.27,.61][fragment]
		var c:=base
		c.a=fade*(.76-fragment*.08)
		for j in range(4):
			var u:=start+j*.085
			var a:=blade_point(u,front,growth)+Vector2((64+fragment*15)*growth,0)
			var b:=blade_point(u+.085,front,growth)+Vector2((64+fragment*15)*growth,0)
			line(a,b,c,2 if fragment%2==0 else 1)

