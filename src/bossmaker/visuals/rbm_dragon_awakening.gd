extends Node2D
## Dragon-only awakening overlay. It reads presentation time; no battle/RNG access.
## The owner supplies animated mouth/eye anchors from the same body renderer.
const Body = preload("res://src/bossmaker/visuals/rbm_dragon_body.gd")
const DURATION := 5.45
const REVEAL_TIME := 3.04
const REVEAL := REVEAL_TIME
const DARK_START := 2.32
const DARK_END := 2.68
var age := -1.0
var canvas_size := Vector2(1280, 720)
var home := Vector2.ZERO
var mouth := Vector2.ZERO
var eye := Vector2.ZERO
var body_height := 180.0
var pixel := 3.0
var active := false
var _stage: Control
var _body: Node2D
var _boss_visible := true
var _revealed := false
var _released := false
var _thundered := false
var _erupted := false
var _roared := false
var _shake := Vector2.ZERO

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	stage._playing = true
	stage._phase = "awakening"
	stage._awakened_appearance_applied = false
	canvas_size = stage.size
	home = stage._foot("boss")
	body_height = stage.Assets.display_height(str(stage._asset_ids["boss"]))
	var boss: Control = stage._visuals["boss"]
	_boss_visible = boss.visible
	_body = Body.new()
	# Stage z=3 for the body, z=90 for black fire/darkness above the party.
	z_index = 90
	_body.z_index = -87
	add_child(_body)
	_body.configure(stage)
	boss.visible = false
	_play_sound("dragon_awakening", 0.0)
	advance(0.0)
	var tween := create_tween()
	tween.tween_method(advance, 0.0, DURATION, DURATION)
	tween.tween_callback(stage._finish_awakening_entry)
	return tween

func advance(time: float) -> void:
	_clear_shake()
	age = time
	if active and is_instance_valid(_stage):
		if age >= 0.55 and not _erupted:
			_erupted = true
		if age >= 1.28 and not _roared:
			_roared = true
		if age >= DARK_START and not _revealed:
			_revealed = true
			_stage._awakened_appearance_applied = true
			_stage._apply_awakened_appearance()
			_body.refresh_asset()
		if age >= 1.30 and not _thundered:
			_thundered = true
		if age >= REVEAL_TIME and not _released:
			_released = true
		var state := _body_state(age)
		_body.advance(state)
		# Fallback anchors are replaced by Body's exact pose anchors when available.
		mouth = home + Vector2(-body_height * 0.43, -body_height * 0.88)
		eye = home + Vector2(-body_height * 0.39, -body_height * 0.83)
		if _body.has_method("mouth_point"):
			mouth = _body.call("mouth_point")
		if _body.has_method("eye_point"):
			eye = _body.call("eye_point")
		var force := 0.0
		if age>=.55 and age<2.16: force=2+smoothstep(.55,2.16,age)*4
		if age>=1.30 and age<1.95: force+=12*(1-(age-1.30)/.65)
		if age>=3.04 and age<4.14: force=46*(1-(age-3.04)/1.10)
		if age>=2.16 and age<2.87: force=0.0
		_shake=Vector2(sin(age*107)*force,cos(age*89)*force*.75).round()
		for visual in _stage._visuals.values():
			visual.position += _shake
		position = _shake
	queue_redraw()

func _body_state(time: float) -> Dictionary:
	var crouch := smoothstep(0.0, 0.50, time) * (1.0 - smoothstep(0.83, 1.20, time))
	var roar := smoothstep(1.02, 1.32, time) * (1.0 - smoothstep(2.66, 3.48, time))
	var pose := 10 if time < 0.95 else (9 if time < 3.12 else 0)
	if time < 0.12:
		pose = 0
	var state={"pose":pose,"foot":home,"scale":Vector2(1.0+crouch*.08+roar*.045,1.0-crouch*.16+roar*.10),"neck":0.0}
	if time>=2.16 and time<2.68: state.pose=10
	elif time>=2.68 and time<2.86: state.pose=4
	elif time>=2.86 and time<3.04: state.pose=8
	elif time>=3.04 and time<3.85:
		state.pose=9
		state.scale=Vector2(1.06,1.06)
	elif time>=3.85 and time<4.2: state.pose=4
	elif time>=4.2: state={"pose":0,"foot":home,"scale":Vector2.ONE,"neck":0.0}
	return state

func _play_sound(key: String, gain: float) -> void:
	if is_instance_valid(_stage) and is_instance_valid(_stage._sound):
		_stage._sound.play_sound(key, gain)

func _clear_shake() -> void:
	if _shake != Vector2.ZERO and is_instance_valid(_stage):
		for visual in _stage._visuals.values():
			if is_instance_valid(visual):
				visual.position -= _shake
	_shake = Vector2.ZERO
	position = Vector2.ZERO

func stop() -> void:
	_clear_shake()
	if is_instance_valid(_stage):
		var boss: Control = _stage._visuals.get("boss")
		if is_instance_valid(boss):
			boss.visible = _boss_visible
	active = false
	visible = false
	age = -1.0
	_stage = null

func _draw() -> void:
	if age<0 or age>5.4: return
	# Opaque blackout leaves only the eye visible.
	if age>=2.32 and age<2.68:
		draw_rect(Rect2(Vector2.ZERO,canvas_size),Color.BLACK)
		_draw_eye(1.0)
		return
	var gather=smoothstep(.08,.55,age)*(1-smoothstep(.60,.80,age))
	if gather>0: _draw_ground_gather(gather)
	var eruption=smoothstep(.48,.93,age)
	var escalation=1.0+smoothstep(.95,1.4,age)*.30+smoothstep(1.6,2.1,age)*.42
	var scatter=smoothstep(REVEAL,3.38,age)
	var cover=eruption*(1-scatter)
	if cover>0:
		_draw_black_fire(cover*escalation,scatter)
		for i in range(10):
			var x=(i-4.5)*37
			var h=(75+sin(i*3.7+age*12)*25)*cover*escalation
			_flame(home+Vector2(x,-10),22,h,cos(age*9+i)*7,Color(.018,.014,.024,cover*.85))
	if age>.66 and age<REVEAL: _draw_smoke(eruption,0)
	if age>=1.22 and age<2.32:
		_draw_roar()
		var q=clampf((age-1.30)/.78,0,1)
		if q<1: circle(mouth,35+q*350,Color(.94,.06,.12,(1-q)*.94),8)
	if age>=1.30 and age<1.46:
		# Every bolt uses alternating angular offsets, never sinusoidal near-straight paths.
		var count=3
		var center=home-Vector2(0,110)
		for i in range(count):
			var angle=i*2.399+sin(age*3)*.13
			var dir=Vector2(cos(angle),sin(angle))
			var side=Vector2(-dir.y,dir.x)
			var points=PackedVector2Array()
			for j in range(7):
				points.append(center+dir*(70+j*24)+side*(1 if j%2 else -1)*(22+fposmod(i*13+j*7+int(age*11)*5,21)))
			draw_polyline(_snap(points),Color(.36,.012,.032,.9),6,false)
			draw_polyline(_snap(points),Color(.98,.075,.13,1),3,false)
	if age>=REVEAL and age<4.5:
		var q=(age-REVEAL)/1.46
		for i in range(36):
			var angle=i*2.399
			var dir=Vector2(cos(angle),sin(angle)*.75)
			var p=home-Vector2(0,105)+dir*(100+pow(q,.65)*(1250+i%4*95))
			var radius=(22+i%3*10)*(1-q*.5)
			_block_cloud(p,Vector2(radius*1.3,radius),Color(.035,.027,.045,(1-q)*.88))
			if i%2==0: _flame(p,13*(1-q),58*(1-q),dir.x*5,Color(.10,.015,.027,1-q))
		release_blast(age-REVEAL)
	if age>=.5 and age<4.6:
		var fade=cover if age<REVEAL else 1-smoothstep(REVEAL,4.6,age)
		for i in range(54):
			var q=fposmod(age*.72+i*.173,1)
			var p=home+Vector2(sin(i*8.53)*(140+scatter*240),-q*(220+80*escalation)-scatter*30)
			draw_rect(Rect2(p.snapped(Vector2(3,3)),Vector2(3,6)),Color(.93,.035,.07,sin(q*PI)*fade))
	if age>=2.16 and age<2.32:
		draw_rect(Rect2(Vector2.ZERO,canvas_size),Color(0,0,0,smoothstep(2.16,2.32,age)))
		_draw_eye(smoothstep(2.16,2.32,age))
	elif age>=2.68 and age<2.87:
		var fade=1-smoothstep(2.68,2.87,age)
		draw_rect(Rect2(Vector2.ZERO,canvas_size),Color(0,0,0,fade))
		_draw_eye(fade)

func circle(center: Vector2,radius: float,c: Color,width: float) -> void:
	var points=PackedVector2Array()
	for i in range(49):
		var a=i*TAU/48
		points.append(center+Vector2(cos(a),sin(a))*radius)
	draw_polyline(_snap(points),c,width,false)

func release_blast(t: float) -> void:
	var center=home-Vector2(0,105)
	# A short flash, then three pressure fronts sweep beyond the entire viewport.
	if t<.13:
		draw_rect(Rect2(Vector2(-100,-100),canvas_size+Vector2(200,200)),Color(.93,.87,.88,(1-t/.13)*.88))
	for i in range(3):
		var dt=t-i*.09
		if dt<0 or dt>.95: continue
		var q=dt/.95
		var radius=65+pow(q,.65)*1600
		circle(center,radius,Color(.55,.035,.075,(1-q)*.86),32*(1-q)+5)
		circle(center,radius-14,Color(.91,.83,.85,(1-q)*.9),16*(1-q)+3)
		var points=PackedVector2Array()
		for j in range(65):
			var a=j*TAU/64
			points.append(home+Vector2(cos(a)*radius*1.12,sin(a)*radius*.25))
		draw_polyline(_snap(points),Color(.8,.73,.76,(1-q)*.85),20*(1-q)+4,false)
	for i in range(28):
		var q=clampf(t/1.46,0,1)
		var a=i*TAU/28
		var radius=100+pow(q,.65)*1350
		var pos=home+Vector2(cos(a)*radius,sin(a)*radius*.3-30-q*50)
		var size=28+q*65
		_block_cloud(pos,Vector2(size*1.4,size),Color(.035,.023,.035,(1-q)*.83))

func _draw_ground_gather(amount: float) -> void:
	for i in range(14):
		var angle := TAU * float(i) / 14.0
		var outer := home + Vector2(cos(angle) * 160.0, sin(angle) * 25.0) * (1.0 - amount * 0.52)
		var inner := home + Vector2(cos(angle) * 55.0, sin(angle) * 8.0)
		_segment(outer, inner, Color(0.16, 0.025, 0.045, amount * 0.75), pixel)

func _draw_black_fire(amount: float, scatter: float) -> void:
	# Broad columns completely cover the wings and neck before the transformation.
	for i in range(15):
		var spread := (float(i) - 7.0) / 7.0
		var lift := 0.76 + 0.23 * sin(float(i) * 2.71 + age * 10.0)
		var h := body_height * (1.05 + 0.55 * (1.0 - absf(spread))) * amount * lift
		var origin := home + Vector2(spread * body_height * (0.83 + scatter * 1.1), 8.0 - scatter * 95.0)
		var width := body_height * (0.17 + 0.035 * sin(float(i) * 4.0)) * (1.0 - scatter * 0.45)
		_flame(origin, width, h, sin(age * 8.0 + float(i)) * 14.0, Color(0.18, 0.015, 0.038, amount))
		_flame(origin + Vector2(0, -pixel), width * 0.80, h * 0.92, sin(age * 8.0 + float(i)) * 12.0, Color(0.020, 0.018, 0.029, amount))
	# A lower, continuous black mass prevents isolated gaps from exposing the swap.
	if amount > 0.4 and scatter < 0.2:
		_block_cloud(home - Vector2(0, body_height * 0.36), Vector2(body_height * 0.74, body_height * 0.37), Color(0.020, 0.018, 0.029, amount * 0.92))

func _flame(origin: Vector2, width: float, height: float, bend: float, color: Color) -> void:
	if width < pixel or height < pixel * 2.0 or color.a <= 0.01:
		return
	# Small scattering flames must not bend back through their own outline.
	bend = clampf(bend, -width * 0.35, width * 0.35)
	var points := PackedVector2Array([
		origin + Vector2(-width, 0), origin + Vector2(-width * 0.88, -height * 0.31),
		origin + Vector2(-width * 0.46, -height * 0.25), origin + Vector2(-width * 0.65, -height * 0.63),
		origin + Vector2(-width * 0.16 + bend, -height * 0.55), origin + Vector2(bend, -height),
		origin + Vector2(width * 0.46 + bend, -height * 0.73), origin + Vector2(width * 0.22, -height * 0.44),
		origin + Vector2(width * 0.72, -height * 0.59), origin + Vector2(width * 0.70, -height * 0.23),
		origin + Vector2(width, 0),
	])
	points = _snap(points)
	var outline := PackedVector2Array()
	for point in points:
		if not outline.has(point): outline.append(point)
	if outline.size() >= 3 and not Geometry2D.triangulate_polygon(outline).is_empty():
		draw_colored_polygon(outline, color)

func _draw_smoke(eruption: float, scatter: float) -> void:
	var fade := 1.0 - smoothstep(3.2, 3.7, age)
	for i in range(19):
		var cycle := fposmod((age - 0.55) * 0.52 + float(i) * 0.137, 1.0)
		var side := sin(float(i) * 6.71)
		var center := home + Vector2(side * body_height * (0.69 + cycle * 0.19 + scatter * 1.10), -cycle * body_height * 1.62 - scatter * 86.0)
		var radius := body_height * (0.12 + 0.12 * cycle) * eruption
		var alpha := sin(cycle * PI) * 0.72 * fade
		_block_cloud(center, Vector2(radius * 1.15, radius), Color(0.066, 0.057, 0.083, alpha))
		_block_cloud(center + Vector2(-radius * 0.16, radius * 0.17), Vector2(radius * 0.79, radius * 0.62), Color(0.023, 0.021, 0.032, alpha))

func _block_cloud(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-radius.x, -radius.y * 0.40), center + Vector2(-radius.x * 0.55, -radius.y * 0.40),
		center + Vector2(-radius.x * 0.55, -radius.y), center + Vector2(radius.x * 0.32, -radius.y),
		center + Vector2(radius.x * 0.32, -radius.y * 0.65), center + Vector2(radius.x * 0.86, -radius.y * 0.65),
		center + Vector2(radius.x * 0.86, -radius.y * 0.10), center + Vector2(radius.x, -radius.y * 0.10),
		center + Vector2(radius.x, radius.y * 0.63), center + Vector2(radius.x * 0.48, radius.y * 0.63),
		center + Vector2(radius.x * 0.48, radius.y), center + Vector2(-radius.x * 0.63, radius.y),
		center + Vector2(-radius.x * 0.63, radius.y * 0.60), center + Vector2(-radius.x, radius.y * 0.60),
	])
	if not Geometry2D.triangulate_polygon(_snap(points)).is_empty():
		draw_colored_polygon(_snap(points), color)

func _draw_roar() -> void:
	for i in range(3):
		var t := age - 1.28 - float(i) * 0.24
		if t < 0.0 or t > 0.72:
			continue
		var q := t / 0.72
		var radius := 12.0 + q * 72.0
		var points := PackedVector2Array()
		for j in range(13):
			var a := -PI * 0.91 + float(j) / 12.0 * PI * 0.78
			points.append(mouth + Vector2(cos(a), sin(a)) * radius)
		draw_polyline(_snap(points), Color(0.64, 0.033, 0.07, (1.0 - q) * 0.63), pixel, false)

func _draw_lightning() -> void:
	var pulse := int(age * 13.0)
	for i in range(5):
		if (pulse + i) % 3 == 0:
			continue
		var angle := float(i) * TAU / 5.0 - PI * 0.5
		var start := home - Vector2(0, body_height * 0.63) + Vector2(cos(angle) * 65.0, sin(angle) * 74.0)
		var end := start + Vector2(cos(angle) * 102.0, sin(angle) * 91.0)
		var path := PackedVector2Array([start])
		for j in range(1, 6):
			var q := float(j) / 6.0
			var zigzag := sin(float(i * 7 + j * 11 + pulse * 3)) * 20.0
			path.append(start.lerp(end, q) + Vector2(-sin(angle), cos(angle)) * zigzag)
		path.append(end)
		path = _snap(path)
		draw_polyline(path, Color(0.34, 0.008, 0.035, 0.90), pixel * 3.0, false)
		draw_polyline(path, Color(0.93, 0.045, 0.11, 0.98), pixel, false)

func _draw_eye(amount: float) -> void:
	var anchor := eye.snapped(Vector2.ONE * pixel)
	# Crisp stepped halo and one visible eye preserve the existing side profile.
	draw_rect(Rect2(anchor - Vector2(12, 6), Vector2(24, 12)), Color(0.35, 0.0, 0.025, amount * 0.60))
	draw_rect(Rect2(anchor - Vector2(8, 3), Vector2(16, 6)), Color(0.95, 0.018, 0.06, amount))
	draw_rect(Rect2(anchor - Vector2(2, 3), Vector2(4, 6)), Color(1.0, 0.52, 0.48, amount))
	_segment(anchor - Vector2(24, 0), anchor + Vector2(29, 0), Color(0.88, 0.018, 0.045, amount * 0.55), pixel)

func _draw_release() -> void:
	var t := age - REVEAL_TIME
	if t >= 0.65: return
	var q := clampf(t / 0.65, 0.0, 1.0)
	var fade := 1.0 - q
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var direction := Vector2(cos(angle), sin(angle) * 0.54)
		var center := home - Vector2(0, body_height * 0.54) + direction * (65.0 + q * 250.0)
		_flame(center, (18.0 - q * 12.0), (46.0 - q * 29.0), direction.x * 22.0, Color(0.032, 0.023, 0.039, fade * 0.95))
		_segment(center, center - direction * (24.0 + q * 18.0), Color(0.39, 0.018, 0.047, fade * 0.8), pixel)
	if t < 0.26:
		var ring := PackedVector2Array()
		for i in range(25):
			var angle := TAU * float(i) / 24.0
			ring.append(home + Vector2(cos(angle) * (80.0 + t * 750.0), sin(angle) * (14.0 + t * 115.0)))
		draw_polyline(_snap(ring), Color(0.65, 0.023, 0.07, (1.0 - t / 0.26) * 0.86), pixel * 2.0, false)

func _draw_embers(cover: float, scatter: float) -> void:
	if age < 0.50:
		return
	var fade := maxf(cover * 0.9, scatter * (1.0 - smoothstep(3.38, DURATION, age)))
	for i in range(25):
		var q := fposmod(age * 0.65 + float(i) * 0.173, 1.0)
		var side := sin(float(i) * 8.53)
		var point := home + Vector2(side * (body_height * 0.84 + scatter * 130.0) + sin(age * 4.0 + float(i)) * 10.0, -q * (body_height * 1.75) - scatter * 32.0)
		var alpha := sin(q * PI) * fade
		draw_rect(Rect2(point.snapped(Vector2.ONE * pixel), Vector2(pixel, pixel * 2.0)), Color(0.85, 0.04 + float(i % 3) * 0.03, 0.07, alpha))

func _segment(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(a.snapped(Vector2.ONE * pixel), b.snapped(Vector2.ONE * pixel), color, width, false)

func _snap(points: PackedVector2Array) -> PackedVector2Array:
	for i in range(points.size()):
		points[i] = points[i].snapped(Vector2.ONE * pixel)
	return points
