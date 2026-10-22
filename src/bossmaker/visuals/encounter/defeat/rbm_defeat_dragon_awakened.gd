extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## Approved V2: awakened dragon detonates across the battlefield.
## Only presentation state is touched. Deterministic geometry; no battle RNG.
const SOUNDS := ["enc:dragon_cry", "enc:dragon_burn", "enc:dragon_detonation"]
const BLAST := 0.58
const INK := Color("17111e")
const COAL := Color("342032")
const RED := Color("b32a41")
const FIRE := Color("f16a36")
const GOLD := Color("ffbb66")
const HOT := Color("fff0c6")
var core := Vector2.ZERO
var active := false
var veil: Node2D
var cloud_shapes: Array[PackedVector2Array] = []
var cloud_indices := PackedInt32Array()
var batch_vertices := PackedVector2Array()
var batch_colors := PackedColorArray()
var batch_indices := PackedInt32Array()

func duration() -> float:
	return 2.65

func setup() -> void:
	super.setup()
	# Cached star-shaped fans remain valid even when adjacent pixel-snapped points coincide.
	for j in range(48): cloud_indices.append_array(PackedInt32Array([0,j+1,(j+1)%48+1]))
	for seed in range(24):
		var shape := PackedVector2Array()
		for j in range(48):
			var a := j*TAU/48.0
			var r := 1.0+0.10*sin(a*5+seed)+0.075*sin(a*9+seed*2.1)+0.045*sin(a*17+seed)
			shape.append(Vector2(cos(a),sin(a))*r)
		cloud_shapes.append(shape)
	core = chest_point() + Vector2(10, 12)
	veil = p._layer("VictoryDragonDetonationLighting", 0, -1)
	veil.draw_fn = _draw_veil
	p.stage.add_child(veil)
	# The owning victory layer exits on cancel, retry, hidden view, or tree teardown.
	p.top.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)

func begin() -> void:
	super.begin()
	active = true

func advance(t: float, _dt: float) -> void:
	age = t
	# Use original recoil/roar frames at their original scale and fixed foot anchor.
	bs.pose = 11 if t < 0.20 else 9
	bs.foot = home() + Vector2(18, 0)
	white = smoothstep(0.28, BLAST, t) * 0.78
	p.at(0.0, "overloaded_roar", func(): p.sfx.play("enc:dragon_cry", -1.0, 0.0, 0.65, 0.78))
	p.at(BLAST, "screen_filling_detonation", func():
		p.sfx.play("enc:dragon_detonation")
		p.sfx.play("enc:dragon_burn", -5.0, 0.0, 1.20, 0.65)
		p.camera.shake(8, 0.48)
		p.fx_back.shock(home(), 100, 1150, 0.56, Color(GOLD, 0.75), 22, 0.28))
	# The body disappears inside the first blast; it never reappears in the smoke.
	if t >= BLAST + 0.10: gone = true
	p.overlay.vignette = 0.40 * smoothstep(0.0, 0.30, t) * (1.0 - smoothstep(1.20, 2.12, t))
	veil.queue_redraw()

func cleanup() -> void:
	if is_instance_valid(veil): veil.queue_free()

func _draw_veil(ci: CanvasItem) -> void:
	if not active: return
	var dim := smoothstep(0.0, 0.30, age) * (1.0 - smoothstep(1.20, 2.12, age))
	ci.draw_rect(Rect2(-40, -40, 1360, 800), Color(0.025, 0.012, 0.04, dim * 0.68))

func draw_top(ci: CanvasItem) -> void:
	if not active: return
	if age < BLAST:
		_charge(ci)
		return
	var e := age - BLAST
	var light := (1.0 - smoothstep(0.04, 0.50, e))
	# One warm exposure lift, not repeated full-screen flashes.
	if light > 0:
		ci.draw_rect(Rect2(-40, -40, 1360, 800), Color(1.0, 0.65, 0.38, light * 0.23))
	_pressure_front(ci, e)
	_rays(ci, e)
	_fireball(ci, e)
	_embers(ci, e)

func _charge(ci: CanvasItem) -> void:
	var q := smoothstep(0.0, BLAST, age)
	# Edge-to-core flecks telegraph energy throughout the entire screen.
	for i in range(20):
		var a := i * 2.39996
		var u := fmod(age * 1.7 + i * 0.137, 1.0)
		var dir := Vector2(cos(a), sin(a) * 0.68)
		var tip := core + dir * (40 + 770 * (1.0-u))
		var tail := tip + dir * (18 + q * 50)
		_streak(ci, tail, tip, 2 + q * 2, Color(RED.lerp(GOLD, q), sin(PI*u)*q*0.8))
	# A few irregular cracks in the energy surrounding the body, never in its UVs.
	for i in range(7):
		var a := -PI + i * TAU / 7.0
		var dir := Vector2(cos(a), sin(a))
		var perp := dir.orthogonal()
		var r := 26 + q * 90
		var pts := PackedVector2Array([core+dir*14, core+dir*r*0.48+perp*12, core+dir*r*0.59-perp*8, core+dir*r])
		ci.draw_polyline(pts, Color(RED, q*0.9), 7, false)
		ci.draw_polyline(pts, Color(HOT, q*q*0.9), 2, false)
	if q > 0.6:
		var r := (q-0.6)*24
		ci.draw_rect(Rect2(core-Vector2(r,r),Vector2(r*2,r*2)), Color(HOT,q))

func _pressure_front(ci: CanvasItem, e: float) -> void:
	if e > 0.66: return
	var q := clampf(e / 0.66, 0.0, 1.0)
	var radius := 45 + 1550 * (1.0-pow(1.0-q,2.0))
	var alpha := 1.0 - q
	# Expanding pressure front reaches all four edges, then exits the frame.
	_ring(ci, core, radius, 0.79, Color(GOLD,alpha*0.65), 16*(1-q)+3)
	_ring(ci, core, radius+24, 0.79, Color(HOT,alpha*0.65), 3)
	_ring(ci, home(), radius*1.12, 0.27, Color(RED,alpha*0.8), 12*(1-q)+2)

func _rays(ci: CanvasItem, e: float) -> void:
	if e > 0.62: return
	var q := clampf(e/0.62,0.0,1.0)
	var travel := 1.0-pow(1.0-q,4.0)
	var alpha := 1.0-smoothstep(0.12,0.62,e)
	for i in range(24):
		var a := i*TAU/24.0 + sin(i*9.2)*0.05
		var dir := Vector2(cos(a),sin(a)*0.83)
		var distance := (650 + _hash(i)*650)*travel
		var start := core + dir*(30+290*q)
		var end := core + dir*distance
		var width := (18 + _hash(i+3)*34)*(1-q)
		_streak(ci,start,end,width,Color(RED,alpha*0.9))
		_streak(ci,start,end,width*0.55,Color(GOLD,alpha*0.9))
		_streak(ci,start,end,width*0.16,Color(HOT,alpha))

func _fireball(ci: CanvasItem, e: float) -> void:
	if e > 1.83: return
	batch_vertices.clear()
	batch_colors.clear()
	batch_indices.clear()
	var travel := 1.0 - exp(-e*5.0)
	var fade := 1.0 - smoothstep(0.75,1.83,e)
	var hot_fade := 1.0-smoothstep(0.15,0.82,e)
	var bulk := 45 + 315*travel
	# Solid central fireball, then a hollow crown of outward-moving rolling flames.
	if e < 0.72:
		var alpha := 1.0-smoothstep(0.33,0.72,e)
		_cloud(ci,core,Vector2(bulk*1.08,bulk*0.85),2,Color(RED,alpha))
		_cloud(ci,core,Vector2(bulk,bulk*0.79),2,Color(FIRE,alpha))
		_cloud(ci,core,Vector2(bulk*0.84,bulk*0.66),2,Color(GOLD,alpha))
		_cloud(ci,core,Vector2(bulk*0.62,bulk*0.50),2,Color(HOT,alpha))
	# Rolling black flames expand well beyond the original dragon silhouette.
	for layer in range(4):
		for i in range(18):
			var a := i*TAU/18.0 + 0.09*sin(i*2.1)
			var dir := Vector2(cos(a),sin(a)*0.77)
			var distance := (150+_hash(i+7)*235)*travel + e*e*85
			var pos := core + dir*distance + Vector2(0,-e*38)
			var size := (43 + _hash(i+4)*60) * (0.45+travel*1.05)
			var color := Color("642135").lerp(INK,smoothstep(0.12,0.65,e))
			var scale_factor := 1.0
			if layer == 1:
				color = RED.lerp(COAL,smoothstep(0.25,1.2,e))
				scale_factor = 0.96
				pos -= dir*size*0.10
			elif layer == 2:
				color = FIRE
				scale_factor = 0.79
				pos -= dir*size*0.22
			elif layer == 3:
				color = GOLD.lerp(HOT,0.25)
				scale_factor = 0.51
				pos -= dir*size*0.35
			var alpha := fade * (hot_fade if layer >= 2 else 1.0)
			_cloud(ci,pos,Vector2(size,size*0.85)*scale_factor,i,Color(color,alpha))
			if layer == 3 and hot_fade > 0.05:
				# Broken facets make the rolling flame read as hot gas, not flat rings.
				for j in range(4):
					var a2 := _hash(i*5+j)*TAU
					var facet_pos := pos+Vector2(cos(a2),sin(a2))*size*0.42
					var facet_size := size*(0.10+_hash(i*7+j+3)*0.14)
					_cloud(ci,facet_pos,Vector2(facet_size,facet_size*0.65),j+i,Color(HOT.lerp(FIRE,_hash(i+j)),alpha*0.85))
	# Bright center punches through the first rolling flames only once.
	if e < 0.22:
		var a := 1.0-smoothstep(0.07,0.22,e)
		_cloud(ci,core,Vector2(bulk*0.76,bulk*0.60),3,Color(HOT,a))
	if not batch_vertices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(),batch_indices,batch_vertices,batch_colors)

func _embers(ci: CanvasItem, e: float) -> void:
	if e > 2.04: return
	for i in range(112):
		var lifetime := 0.8+_hash(i+30)*1.23
		if e > lifetime: continue
		var a := i*2.39996
		var speed := 180+_hash(i+5)*1050
		var dir := Vector2(cos(a),sin(a)*0.82)
		var pos := core+dir*speed*e+Vector2(0,155*e*e)
		var alpha := 1.0-smoothstep(lifetime*0.55,lifetime,e)
		var size := 2+floorf(_hash(i+9)*3)*2
		var color := GOLD.lerp(RED,clampf(e/lifetime,0,1))
		if i%2 == 0:
			_streak(ci,pos-dir*minf(110,speed*0.09),pos,size*0.5,Color(FIRE,alpha*0.7))
		if i%7 == 0:
			_streak(ci,pos-Vector2(18,0),pos+Vector2(18,0),1.0,Color(HOT,alpha*0.65))
		ci.draw_rect(Rect2(pos.snapped(Vector2(2,2)),Vector2(size,size)),Color(color,alpha))
	# A fading scorched energy pool anchors the vanished dragon to its old footprint.
	if e > 0.48:
		_ring(ci,home(),220+e*75,0.18,Color(RED,(1.0-smoothstep(0.65,1.8,e))*0.4),4)

func _hash(i: int) -> float:
	return fposmod(sin(float(i)*127.1+73.2)*43758.5453,1.0)

func _cloud(_ci: CanvasItem, pos: Vector2, size: Vector2, seed: int, color: Color) -> void:
	if color.a < 0.01 or size.x < 2: return
	var offset := batch_vertices.size()
	batch_vertices.append(pos.snapped(Vector2(2,2)))
	batch_colors.append(color)
	for vertex in cloud_shapes[seed%cloud_shapes.size()]:
		batch_vertices.append((pos+vertex*size).snapped(Vector2(2,2)))
		batch_colors.append(color)
	for index in cloud_indices: batch_indices.append(offset+index)

func _streak(ci: CanvasItem, start: Vector2, end: Vector2, width: float, color: Color) -> void:
	if color.a < 0.01 or start.distance_squared_to(end)<4: return
	var perp := (end-start).normalized().orthogonal()*width
	ci.draw_colored_polygon(PackedVector2Array([start-perp,start+perp,end]),color)

func _ring(ci: CanvasItem, center: Vector2, radius: float, sy: float, color: Color, width: float) -> void:
	if color.a<0.01: return
	var points := PackedVector2Array()
	for i in range(65):
		var a := i*TAU/64.0
		points.append((center+Vector2(cos(a)*radius,sin(a)*radius*sy)).snapped(Vector2(2,2)))
	ci.draw_polyline(points,color,width,false)
