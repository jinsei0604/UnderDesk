extends Node2D
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const Motion=preload("res://src/bossmaker/visuals/rbm_dragon_bite_motion.gd")
var kind:="bite"
var attack_attribute:="NEUTRAL"
var motion: RefCounted
var body: Node2D
var feet: Array[Vector2]=[]
var hits: Array[Vector2]=[]
var age:=-1.0

func prepare() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	z_index=-1 # Keep the approved open/closed jaw silhouettes in front of the impact.

func advance(t: float) -> void:
	age=t
	queue_redraw()

func segment(a: Vector2,b: Vector2,c: Color,width: float=3.0) -> void:
	draw_line(a.snapped(Vector2(3,3)),b.snapped(Vector2(3,3)),c,width,false)

func _draw() -> void:
	if age<0 or not is_instance_valid(body): return
	impact(age-Motion.HIT)
	for landing in [.68,1.08,2.67,3.27]:
		var h:=age-float(landing)
		if h>=0 and h<.18: dust(body.foot_point()-Vector2(100,0),h)

func impact(t: float) -> void:
	if t<0 or t>.36: return
	var q:=t/.36
	var c: Color=Palette.color_for(attack_attribute)
	c.a=1-smoothstep(.35,1,q)
	for i in range(16):
		var a:=float(i)*TAU/16
		var b:=float(i+1)*TAU/16
		var radius:=Vector2(22+q*54,17+q*38)
		if i%5!=0: segment(motion.contact+Vector2(cos(a),sin(a))*radius,motion.contact+Vector2(cos(b),sin(b))*radius,c,3)
	for i in range(7):
		var angle:=float(i)*TAU/7
		var direction:=Vector2(cos(angle),sin(angle))
		segment(motion.contact+direction*(28+q*24),motion.contact+direction*(36+q*42),c,3)

func dust(at: Vector2,t: float) -> void:
	for i in range(5):
		var point:=at+Vector2((i-2)*t*90,-sin(t/.18*PI)*(4+i%2*3))
		draw_rect(Rect2(point.snapped(Vector2(3,3)),Vector2(6,3)),Color(.39,.36,.33,.50*(1-t/.18)))
