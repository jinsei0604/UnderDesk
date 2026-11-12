class_name RBMHeroFxBase
extends Node2D
## ヒーロー（hero_boss）のエフェクト1種類の土台（表示専用。戦闘の状態・乱数には触れない）。
## back（キャラの後ろ）・mid（味方より前・ボスより後ろ）・front（いちばん前）の層に部品を置き、advance(t) で時刻だけから見た目を決める。
## 座標は 640×360 の論理ドット（ステージの2分の1）。本体の絵は持たず、受け取るのは今のポーズ名・足元・味方の位置だけ。

var back: Node2D
var front: Node2D
## 味方より前・ボスより後ろの層。ボスの動きを隠したくない大きな効果はここへ置く。
var mid: Node2D
## 単体攻撃で、狙う相手が基準の位置（右手前の味方）からどれだけずれているか。setup() の前に入れる。
var focus_delta := Vector2.ZERO
## 基準の並びの4か所（味方の番号の順）に、今回の相手がいるか。いない所には当たりの効果を出さない。
var present: Array = [true, true, true, true]
var view := {}
var ctx := {}
var pose := "normal"
var foot := Vector2(390, 238)
var body_foot := Vector2(390, 238)
var targets: Array = []

func setup(back_layer: Node2D, front_layer: Node2D, target_points: Array) -> void:
	back = back_layer
	front = front_layer
	targets = target_points
	_build()

func _build() -> void:
	pass

## t 秒の状態を作る。view に結果（暗さ・カメラ・味方の反応・全画面処理）を入れる。
func advance(t: float, pose_name: String, foot_pos: Vector2, body_foot_pos: Vector2 = foot_pos) -> void:
	pose = pose_name
	foot = foot_pos
	body_foot = body_foot_pos
	view = {"dim": 0.0, "dim_col": Color(13.0 / 255, 15.0 / 255, 31.0 / 255), "shake": Vector2.ZERO,
		"allies": [{}, {}, {}, {}], "hero": {}, "post": {}, "rings": []}
	_step(t)

func _step(_t: float) -> void:
	pass

func anchor(which: String) -> Vector2:
	return RBMHeroFxAnchors.point(pose, which, body_foot)

func target_chest(i: int) -> Vector2:
	return Vector2(targets[i]) + Vector2(0, -22)

func batch(parent: Node, additive: bool = true) -> RBMHeroFxBatch:
	var b := RBMHeroFxBatch.new()
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		b.material = m
	parent.add_child(b)
	return b

func quad(parent: Node, rect: Rect2, shader_name: String, params: Dictionary = {}) -> ColorRect:
	var q := ColorRect.new()
	q.position = rect.position
	q.size = rect.size
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = RBMHeroFx.shader(shader_name)
	q.material = m
	q.visible = false
	sp(q, params)
	parent.add_child(q)
	return q

func ribbon(parent: Node, pal_hex: Array, params: Dictionary = {}) -> RBMHeroFxRibbon:
	var r := RBMHeroFxRibbon.new()
	var m := ShaderMaterial.new()
	m.shader = RBMHeroFx.shader("ribbon")
	r.material = m
	r.visible = false
	sp(r, {"pal": RBMHeroFx.pal(pal_hex)})
	sp(r, params)
	parent.add_child(r)
	return r

func sp(node: CanvasItem, params: Dictionary) -> void:
	var m := node.material as ShaderMaterial
	for k in params:
		m.set_shader_parameter(k, params[k])

func blast_quad(parent: Node, pal_a: Array, pal_b: Array, params: Dictionary = {}) -> ColorRect:
	var p := {"size": RBMHeroFx.WORLD.size, "pal_a": RBMHeroFx.pal(pal_a), "pal_b": RBMHeroFx.pal(pal_b)}
	p.merge(params, true)
	var q := quad(parent, RBMHeroFx.WORLD, "blast", p)
	# 色が付きうる範囲の計算に使う値（blast.gdshader の既定値と同じ）
	q.set_meta("blast_reach", Vector3(float(p.get("amp", 18.0)), float(p.get("k", 0.09)), float(p.get("glow_r", 40.0))))
	return q

func ring_quad(parent: Node, pal_hex: Array, params: Dictionary = {}) -> ColorRect:
	var p := {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(pal_hex)}
	p.merge(params, true)
	return quad(parent, RBMHeroFx.WORLD, "ring", p)

## 世界座標 → ワールド矩形内の座標
func w(p: Vector2) -> Vector2:
	return p - RBMHeroFx.WORLD.position

## 帯の表示: 頭と尾の位置と不透明度。0以下なら隠す。
func show_ribbon(r: RBMHeroFxRibbon, on: bool, params: Dictionary = {}) -> void:
	r.visible = on
	if on:
		sp(r, params)

## 画面の屈折だけの衝撃波（輪を描かない）。
func refract_wave(center: Vector2, age: float, life: float, reach: float, speed: float, power: float) -> void:
	if age >= 0.0 and age < life:
		view["rings"].append(Vector4(center.x, center.y, reach * RBMHeroFx.burst(age, speed), power * (1.0 - age / life)))

func show_ring(q: ColorRect, center: Vector2, age: float, life: float, reach: float, thick: float, speed: float = 5.0, refract: float = 0.0) -> void:
	q.visible = age >= 0.0 and age < life
	if not q.visible:
		return
	var u := age / life
	var radius := reach * RBMHeroFx.burst(age, speed)
	sp(q, {"center": w(center), "radius": radius, "thick": thick * (1.0 - u * 0.75) + 0.8, "fade": 1.0 - RBMHeroFx.ramp(u, 0.55, 1.0)})
	if refract > 0.0:
		view["rings"].append(Vector4(center.x, center.y, radius, refract * (1.0 - u)))

## 揺れは大きな命中の時だけ、小さく短く。全部の揺れの強さは SHAKE_SCALE で一括して変えられる。
const SHAKE_SCALE := 0.3
const SPARK_DENSITY := 0.5

func hit_shake(age: float, power: float, freq: float = 95.0, life: float = 0.32) -> Vector2:
	if age < 0.0 or age > life:
		return Vector2.ZERO
	var k := (1.0 - age / life)
	k *= k
	return Vector2(cos(age * freq * 0.55), sin(age * freq * 0.7) * 0.6) * power * k * SHAKE_SCALE

func set_post(values: Dictionary) -> void:
	for k in values:
		var v: Variant = values[k]
		if view["post"].has(k) and (v is float) and (view["post"][k] is float):
			view["post"][k] = maxf(float(view["post"][k]), float(v))
		else:
			view["post"][k] = v

## 味方の被弾（のけぞり）。Codex の動きと同じ計算。
func ally_hits(t: float, events: Array, strength: float = 1.0) -> void:
	for ev in events:
		var a: float = t - float(ev[0])
		var i: int = ev[1]
		if a < 0.0:
			continue
		var f := RBMHeroFx.env(a, 0.0, 0.075, 0.095, 0.51) * strength
		var cur: Dictionary = view["allies"][i]
		cur["force"] = maxf(float(cur.get("force", 0.0)), f)
		if a < 0.11:
			cur["flash"] = maxf(float(cur.get("flash", 0.0)), 0.6 * (1.0 - RBMHeroFx.ramp(a, 0.02, 0.16)))

## 味方が爆風で跳ね上がる。
func ally_launch(t: float, at: float, dur: float, kick: float, roll: float) -> void:
	for i in range(4):
		var delay: float = [0.035, 0.09, 0.115, 0.16][i]
		var q: float = (t - (at + delay)) / dur
		if q <= 0.0 or q >= 1.0:
			continue
		var arc_h: float = 4.0 * q * (1.0 - q)
		var cur: Dictionary = view["allies"][i]
		cur["lift"] = arc_h * kick
		cur["back"] = arc_h * (8.0 + 3.0 * float(i % 2))
		cur["roll"] = float(i % 2 * 2 - 1) * roll * arc_h

func ally_light(power: float, col: Color, hero_power: float = -1.0) -> void:
	for i in range(4):
		view["allies"][i]["lit"] = power
		view["allies"][i]["lit_col"] = col
	view["hero"]["lit"] = power if hero_power < 0.0 else hero_power
	view["hero"]["lit_col"] = col

# --- 粒の部品 -------------------------------------------------------------

func sparks(b: RBMHeroFxBatch, o: Vector2, age: float, life: float, n: int, seed_: int, speed: float, head: Color, tail: Color, ang: float = 0.0, spread: float = TAU, grav: float = 120.0, wide: float = 1.8) -> void:
	if age < 0.0 or age > life * 1.05:
		return
	for i in range(int(n * SPARK_DENSITY)):
		var li := life * (0.45 + 0.55 * RBMHeroFx.r(i, seed_ + 1))
		var a := age - RBMHeroFx.r(i, seed_ + 2) * 0.03
		if a < 0.0 or a > li:
			continue
		var q := a / li
		var th := ang + (RBMHeroFx.r(i, seed_) - 0.5) * spread
		var sp_ := speed * (0.3 + 0.7 * RBMHeroFx.r(i, seed_ + 3))
		var dir := Vector2.from_angle(th)
		var k := 5.0
		var p := o + dir * sp_ * (1.0 - exp(-k * a)) / k + Vector2(0, grav * a * a)
		var v := dir * sp_ * exp(-k * a) + Vector2(0, 2.0 * grav * a)
		var length := clampf(v.length() * 0.05, 2.5, 60.0)
		var h := head
		h.a *= 1.0 - q * q
		var tl := tail
		tl.a = 0.0
		b.streak(p - v.normalized() * length, p, wide * (1.0 - q * 0.6), h, tl)

func shards(b: RBMHeroFxBatch, o: Vector2, age: float, life: float, n: int, seed_: int, speed: float, size_: float, lit: Color, dark: Color, grav: float = 220.0, ang: float = 0.0, spread: float = TAU) -> void:
	if age < 0.0 or age > life:
		return
	for i in range(n):
		var li := life * (0.55 + 0.45 * RBMHeroFx.r(i, seed_ + 1))
		if age > li:
			continue
		var q := age / li
		var th := ang + (RBMHeroFx.r(i, seed_) - 0.5) * spread
		var sp_ := speed * (0.35 + 0.65 * RBMHeroFx.r(i, seed_ + 3))
		var dir := Vector2.from_angle(th)
		var k := 3.4
		var p := o + dir * (22.0 + 46.0 * RBMHeroFx.r(i, seed_ + 7)) + dir * sp_ * (1.0 - exp(-k * age)) / k + Vector2(0, grav * age * age)
		var sz := size_ * (0.4 + 0.9 * RBMHeroFx.r(i, seed_ + 4)) * (1.0 - q * q) * RBMHeroFx.ramp(age, 0.0, 0.07)
		b.shard(p, sz, age * (4.0 + 8.0 * RBMHeroFx.r(i, seed_ + 5)) * (1 if i % 2 == 0 else -1), i + seed_, lit, dark)

func star(b: RBMHeroFxBatch, o: Vector2, s: float, n: int, seed_: int, length: float, wide: float, cols: Array) -> void:
	if s <= 0.0:
		return
	for layer in range(cols.size()):
		var k := 1.0 - float(layer) * 0.27
		var col: Color = cols[layer]
		var tip := col
		tip.a *= 0.75
		for i in range(n):
			var th := float(i) / n * TAU + (RBMHeroFx.r(i, seed_) - 0.5) * 0.5 + float(layer) * 0.09
			var long := 1.5 if i % 4 == 0 else 1.0
			var l := length * (0.42 + 0.7 * RBMHeroFx.r(i, seed_ + 1)) * long * k * s
			b.spike(o, Vector2.from_angle(th), l, wide * k * s * (1.0 if i % 4 != 0 else 1.5), col, tip)

## 集まってくる光の線。
func inward(b: RBMHeroFxBatch, o: Vector2, t: float, n: int, seed_: int, r0: float, r1: float, wide: float, col: Color, power: float, rate: float = 1.9) -> void:
	if power <= 0.0:
		return
	for i in range(int(n * SPARK_DENSITY)):
		var q := fmod(t * rate * (0.7 + 0.6 * RBMHeroFx.r(i, seed_ + 1)) + RBMHeroFx.r(i, seed_), 1.0)
		var th := RBMHeroFx.r(i, seed_ + 2) * TAU + q * 0.7
		var rad := lerpf(r1, r0, q * q)
		var dir := Vector2.from_angle(th)
		var length := lerpf(8.0, 64.0, q * q)
		var c := col
		c.a *= sin(q * PI) * power
		var tl := col
		tl.a = 0.0
		b.streak(o + dir * (rad + length), o + dir * rad, wide, c, tl)

## 立ち上る火の粉。
func embers(b: RBMHeroFxBatch, region: Rect2, t: float, n: int, seed_: int, rise: float, col: Color, power: float, size_: float = 2.0, sway: float = 12.0) -> void:
	if power <= 0.0:
		return
	for i in range(n):
		var q := fmod(t * (0.35 + 0.4 * RBMHeroFx.r(i, seed_ + 1)) + RBMHeroFx.r(i, seed_), 1.0)
		var p := Vector2(region.position.x + RBMHeroFx.r(i, seed_ + 2) * region.size.x, region.end.y - q * rise - (1.0 - RBMHeroFx.r(i, seed_ + 3)) * region.size.y)
		p.x += sin(t * 2.0 + float(i)) * sway
		var c := col
		c.a *= sin(q * PI) * power
		b.dot_px(p, size_ * (0.6 + RBMHeroFx.r(i, seed_ + 4)), c)

## 稲妻（枝分かれあり）。seed を変えると形が変わる。
func arc(b: RBMHeroFxBatch, a: Vector2, c: Vector2, seed_: int, wide: float, col: Color, core: Color, segs: int = 9, amp: float = 0.2, branch: bool = true) -> void:
	var d := c - a
	var nv := Vector2(-d.y, d.x).normalized()
	var length := d.length()
	var prev := a
	for i in range(1, segs + 1):
		var u := float(i) / segs
		var p := a + d * u
		if i < segs:
			p += nv * (RBMHeroFx.r(i, seed_) - 0.5) * 2.0 * amp * length * sin(u * PI)
		b.line(prev, p, wide * 2.2, col, col)
		b.line(prev, p, wide, core, core)
		if branch and i % 3 == 1 and i < segs:
			var th := d.angle() + (RBMHeroFx.r(i, seed_ + 5) - 0.5) * 2.4
			arc(b, p, p + Vector2.from_angle(th) * length * 0.3, seed_ + i * 7, wide * 0.6, col, core, 4, amp, false)
		prev = p

## 飛び散る岩。
func rocks(b: RBMHeroFxBatch, o: Vector2, age: float, life: float, n: int, seed_: int, speed: float, size_: float, up: float = 0.0) -> void:
	shards(b, o + Vector2(0, -up), age, life, n, seed_, speed, size_, Color("#6b6880"), Color("#2c2a3a"), 360.0, -PI * 0.5, PI * 1.05)

## 爆発の玉を作る。center から楕円に広がり、外側ほど冷える。blue は外側を pal_b にする割合。
func blobs(center: Vector2, age: float, n: int, seed_: int, rx: float, ry: float, base_r: float, up: float, cooling: float, blue: float, speed: float = 7.5) -> PackedVector4Array:
	var out := PackedVector4Array()
	var ex := RBMHeroFx.burst(age, speed)
	for i in range(n):
		var ang := RBMHeroFx.r(i, seed_) * TAU
		var dist := pow(RBMHeroFx.r(i, seed_ + 1), 0.62)
		var rise := age * age * 26.0 * (0.4 + RBMHeroFx.r(i, seed_ + 2))
		var p := center + Vector2(cos(ang) * rx * dist, sin(ang) * ry * dist - up * dist * (0.4 + RBMHeroFx.r(i, seed_ + 5))) * ex + Vector2(0, -rise)
		var rad := base_r * (0.42 + 0.85 * RBMHeroFx.r(i, seed_ + 3)) * pow(ex, 0.55) * (1.0 + age * 0.22)
		var heat := clampf(1.08 - dist * 0.46 - age * cooling * (0.7 + 0.6 * RBMHeroFx.r(i, seed_ + 4)), 0.02, 1.0)
		if RBMHeroFx.r(i, seed_ + 6) < blue * smoothstep(0.35, 0.95, dist):
			heat = -heat
		out.append(Vector4(p.x - RBMHeroFx.WORLD.position.x, p.y - RBMHeroFx.WORLD.position.y, rad, heat))
	return out

func show_blast(q: ColorRect, data: PackedVector4Array, age: float, params: Dictionary) -> void:
	q.visible = true
	var p := {"blobs": data, "count": data.size(), "flow": age * 2.4}
	p.merge(params, true)
	var area := blast_area(q, data)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		q.visible = false
		return
	q.position = RBMHeroFx.WORLD.position + area.position
	q.size = area.size
	p["origin"] = area.position
	p["size"] = area.size
	sp(q, p)

## 爆炎の矩形のうち、色が付きうる範囲（ワールド矩形内の座標）。性能のため（2026-11-10）、矩形をこの範囲へ縮めて描く。
## blast.gdshader は、玉の距離場 d0 が glow_r*4+amp 以上の所では必ず透明を出す。d0 は一番近い玉までの距離から
## log(玉の数)/k より小さくならないので、全部の玉から m 以上離れた所は描かなくても結果は同じ（見た目は変わらない）。
## 遠い所の距離は 260 で頭打ちになり、玉が多いと画面全体に薄い光が残ることがある。その時は縮めない（今までどおり全体）。
func blast_area(q: ColorRect, data: PackedVector4Array) -> Rect2:
	var full := Rect2(Vector2.ZERO, RBMHeroFx.WORLD.size)
	var n := data.size()
	if n == 0:
		return Rect2()
	if n > 48:
		return full
	var reach: Vector3 = q.get_meta("blast_reach", Vector3.ZERO)
	var k := reach.y
	if k <= 0.0:
		return full
	var limit := exp(-k * (reach.z * 4.0 + reach.x)) - 1e-6
	if limit <= 0.0:
		return full
	var m := log(float(n) / limit) / k
	if m > 260.0:
		return full
	# 2px格子への丸め・補間の誤差のぶんの余白
	m += 4.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in mini(n, 48):
		var b := data[i]
		var e := b.z + m
		lo = lo.min(Vector2(b.x - e, b.y - e))
		hi = hi.max(Vector2(b.x + e, b.y + e))
	lo = lo.floor().max(full.position)
	hi = hi.ceil().min(full.end)
	if hi.x <= lo.x or hi.y <= lo.y:
		return Rect2()
	return Rect2(lo, hi - lo)
