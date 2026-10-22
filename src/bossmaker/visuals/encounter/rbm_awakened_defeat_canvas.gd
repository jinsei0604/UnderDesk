extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## Awakened-defeat drawing primitives and lifetime ownership. Timelines live in each boss.
const Volume = preload("res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_volume.gd")
var field := Volume.new()
var core := Vector2.ZERO
var active := false
var veil: Node2D
var shade := Color(0.02,0.02,0.04,0.0)
var verts := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()

func setup() -> void:
	super.setup()
	core = chest_point()
	veil = p._layer("VictoryAwakenedBackdrop",0,-1)
	veil.draw_fn = func(ci): ci.draw_rect(Rect2(-40,-40,1360,800),shade)
	p.stage.add_child(veil)
	p.top.tree_exiting.connect(cleanup,CONNECT_ONE_SHOT)

func cleanup() -> void:
	if is_instance_valid(veil): veil.queue_free()

func begin() -> void:
	super.begin()
	active = true

func final_blow() -> void:
	# Keep the production hit timing and camera; awakened defeats omit its long light spokes.
	impact_pose()
	p.set_motion_speed(SLOW_SPEED)
	var chest := chest_point()
	p.camera.cut(2,chest+Vector2(-70,14))
	p.fx.flash(chest,44,0.35,Color(1.0,0.97,0.9,0.90))
	p.fx.sparks(chest,10,Color(1,0.95,0.85),Color(0.8,0.5,0.3),PI,PI*1.2,0.5)
	p.camera.shake(4,0.4)
	p.sfx.play("enc:final_hit",0.0)
	white = 1.0

func dim(color: Color, amount: float) -> void:
	field.advance(age)
	shade = Color(color,amount)
	veil.queue_redraw()

func reset_mesh() -> void:
	verts.clear()
	colors.clear()
	indices.clear()

func flush(ci: CanvasItem) -> void:
	if not verts.is_empty(): RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(),indices,verts,colors)

func triangle(a: Vector2,b: Vector2,c: Vector2,color: Color) -> void:
	if color.a < 0.01: return
	var start := verts.size()
	for v in [a,b,c]:
		verts.append(v.snapped(Vector2(2,2)))
		colors.append(color)
	indices.append_array(PackedInt32Array([start,start+1,start+2]))

func line(a: Vector2,b: Vector2,width: float,color: Color) -> void:
	var n := (b-a).normalized().orthogonal()*width*0.5
	triangle(a-n,a+n,b+n,color)
	triangle(a-n,b+n,b-n,color)

func diamond(pos: Vector2,size: Vector2,rotation: float,color: Color) -> void:
	var a := Vector2(size.x,0).rotated(rotation)
	var b := Vector2(0,size.y).rotated(rotation)
	triangle(pos-a,pos+b,pos+a,color)
	triangle(pos-a,pos+a,pos-b,color)

func noise(i: int) -> float:
	return fposmod(sin(float(i)*127.1+73.2)*43758.5453,1.0)
