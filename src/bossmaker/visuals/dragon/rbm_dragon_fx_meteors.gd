extends RBMDragonFxBase
## 覚醒後の竜・全体「黒天の隕石」（2026-11-25 試作 → 2026-11-26 ユーザー承認。前の案のまま質を上げた）:
## 身をかがめ → 天へ咆哮 → 空が暗くなり、上空に黒雲の渦と紅い裂け目が開く（中で黒い稲妻）
## → 燃える岩が炎と煙の尾を引いて次々と四人へ降り注ぐ（当たるたびに爆炎・火花・岩・焦げ跡）
## → 竜がもう一度咆哮し、渦の奥から巨大な隕石がゆっくり現れ、重く迫って落ちてくる（足元に影が広がる）
## → 着弾（白い閃光・二色の衝撃コマ・巨大な爆炎・衝撃の輪・地割れ・四人が吹き飛ぶ）→ 煙の柱と火の粉が残る。
## 落ちる時刻は今の音（dragon_awakened_meteors）に合わせて、今と同じ（小さな隕石32個 1.65〜2.78秒、巨大隕石 4.15秒）。

const FINAL := 4.15
const END := 6.65
const FLIGHT := 0.48
const RIFT := Vector2(250, 72)

## 隕石の予定（host が何回も当たる表示に使う）: {arrival, slot, big}
var meteors: Array = []

var b_back: RBMHeroFxBatch
var b_norm: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_dark: RBMHeroFxBatch
var b_tail: RBMHeroFxBatch
var clouds: ColorRect
var big_blast: ColorRect
var smoke: ColorRect
var fireball: ColorRect
var ring: ColorRect
var cracks: ColorRect

func duration() -> float:
	return END

func impact() -> float:
	return FINAL

func multi_plan() -> Dictionary:
	var plan := {}
	for m in meteors:
		if bool(m.big):
			continue
		var slot := int(m.slot)
		if not plan.has(slot):
			plan[slot] = []
		plan[slot].append(float(m.arrival))
	return plan

func hits() -> Array:
	var out := []
	for m in meteors:
		if bool(m.big):
			for i in range(count):
				out.append([FINAL + i * 0.03, i])
		else:
			out.append([float(m.arrival), int(m.slot)])
	return out

func body_at(t: float) -> Dictionary:
	var s := {"pose": 0, "off": Vector2.ZERO, "scale": Vector2.ONE}
	if t < 0.0:
		return s
	if t < 0.26:
		s.pose = 10
	elif t < 0.54:
		s.pose = 4
	elif t < 1.64:
		s.pose = 9
		s.scale = Vector2(1, 1 + 0.04 * sin((t - 0.54) * 6.0))
	elif t < 2.55:
		s.pose = 4
	elif t < 2.95:
		s.pose = 3
	elif t < FINAL:
		s.pose = 9
		s.scale = Vector2(1, 1 + 0.05 * sin((t - 2.95) * 5.0))
	elif t < FINAL + 0.6:
		s.pose = 4
	return s

func _build() -> void:
	meteors.clear()
	for i in range(32):
		meteors.append({"arrival": 1.65 + floor(i / 4.0) * 0.15 + float(i % 4) * 0.025, "slot": i % maxi(count, 1), "big": false, "i": i})
	meteors.append({"arrival": FINAL, "slot": 0, "big": true, "i": 32})
	var smoke_pal := ["#08060c", "#100c14", "#18121c", "#211a26", "#2b2230", "#362b3c", "#433548", "#504056"]
	clouds = blast_quad(back, ["#05030a", "#08050c", "#0d0812", "#140b18", "#1c0e20", "#26102a", "#341230", "#481436"], smoke_pal, {"amp": 18.0, "k": 0.07, "seed": 8.8, "glow": 0.0, "glow_r": 20.0})
	b_back = batch(back)
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#120a10", "#2a1018", str(ramp8()[4]), str(ramp8()[6])]), "glow_col": col(5), "glow": 0.9})
	ring = ring_quad(back, [str(ramp8()[3]), str(ramp8()[5]), str(ramp8()[6]), "#ffffff"], {"glow_col": col(5), "glow": 0.8})
	b_norm = batch(mid, false)
	smoke = blast_quad(mid, smoke_pal, smoke_pal, {"amp": 26.0, "k": 0.06, "seed": 4.4, "glow": 0.0, "glow_r": 20.0})
	big_blast = blast_quad(front, ramp8(), ramp8(), {"amp": 34.0, "k": 0.05, "seed": 6.6, "glow": 0.8, "glow_col": RBMHeroFx.v3(col(5)), "glow_r": 50.0})
	b_tail = batch(front)
	fireball = quad(front, Rect2(0, 0, 200, 200), "orb", {"pal": RBMHeroFx.pal(ramp8())})
	b_dark = batch(front, false)
	b_front = batch(front)

func _final_target() -> Vector2:
	var a := Vector2.ZERO
	for i in range(count):
		a += Vector2(targets[i])
	return a / float(maxi(count, 1)) + Vector2(2, -2)

func _small_target(m: Dictionary) -> Vector2:
	var i: int = m.i
	return target_chest(int(m.slot)) + Vector2(sin(i * 7.3) * 12.0, cos(i * 4.1) * 5.0 + 10.0)

func _small_start(m: Dictionary) -> Vector2:
	var i: int = m.i
	return RIFT + Vector2((RBMHeroFx.r(i, 3) - 0.3) * 260.0, 10.0 + RBMHeroFx.r(i, 4) * 20.0)

func _step(t: float) -> void:
	for b in [b_back, b_norm, b_front, b_dark, b_tail]:
		(b as RBMHeroFxBatch).reset()
	var c5 := col(5)
	var c6 := col(6)
	var c7 := col(7)
	var red := Color("#ed274c")
	# 空が暗くなる
	var dark := RBMHeroFx.ramp(t, 0.5, 1.3) * (1.0 - RBMHeroFx.ramp(t, 5.3, END))
	view["dim"] = 0.5 * dark
	view["dim_col"] = Color(0.07, 0.02, 0.04)
	set_post({"vig": 0.55 * dark, "vig_col": Vector3(0.1, 0.0, 0.02), "desat": 0.15 * dark})
	_rift(t, dark)
	# 小さな隕石
	for m in meteors:
		if bool(m.big):
			continue
		var at: float = m.arrival
		var p0 := _small_start(m)
		var p1 := _small_target(m)
		var q := (t - (at - FLIGHT)) / FLIGHT
		if q >= 0.0 and q < 1.0:
			_rock(p0, p1, q, int(m.i), 1.0)
		var a := t - at
		if a >= 0.0 and a < 0.42:
			var k := 1.0 - a / 0.42
			disc(b_front, p1, 4.0 + 16.0 * RBMHeroFx.burst(a, 9.0), (4.0 + 16.0 * RBMHeroFx.burst(a, 9.0)) * 0.8, Color(c5, 0.75 * k), Color(col(4), 0.0))
			disc(b_front, p1, 3.0 + 8.0 * RBMHeroFx.burst(a, 11.0), 3.0 + 6.0 * RBMHeroFx.burst(a, 11.0), Color(c7, 0.9 * k * k), Color(c6, 0.0))
			star(b_front, p1, RBMHeroFx.env(a, 0.0, 0.02, 0.04, 0.16), 8, 960 + int(m.i), 26.0, 3.0, [c7, c6])
			if a < 0.23:
				view["shake"] = Vector2(view["shake"]) + hit_shake(a, 7.0, 98.0, 0.23)
			sparks(b_front, p1, a, 0.4, 10, 950 + int(m.i), 120.0, c7, c5, -PI * 0.5, PI * 1.2, 220.0, 1.4)
			rocks(b_front, p1 + Vector2(0, 8), a, 0.5, 3, 970 + int(m.i), 110.0, 2.5, 2.0)
			circle_line(b_front, p1 + Vector2(0, 10), 4.0 + 40.0 * RBMHeroFx.burst(a, 8.0), 1.4 * (1.0 - a / 0.42), Color(c6, 1.0 - a / 0.42), 20, 0.3)
		# 焦げ跡と燃え残り
		if a >= 0.0 and t < 5.6:
			var fade := 1.0 - RBMHeroFx.ramp(t, 4.9, 5.6)
			var foot := p1 + Vector2(0, 20)
			disc(b_norm, foot, 9.0, 2.4, Color(0.03, 0.02, 0.03, 0.5 * fade))
			if (int(m.i) + int(t * 9.0)) % 3 == 0:
				b_front.dot_px(foot + Vector2((RBMHeroFx.r(int(m.i), 8) - 0.5) * 12.0, -1), 1.0, Color(c6, 0.8 * fade))
	_giant(t)
	for b in [b_back, b_norm, b_front, b_dark, b_tail]:
		(b as RBMHeroFxBatch).commit()
	ally_hits(t, hits(), 1.1)
	var fin := t - FINAL
	if fin >= 0.0:
		ally_launch(t, FINAL, 0.75, 34.0, 0.0)

## 巨大隕石（着弾 FINAL は音に合わせたまま）: GIANT_START に渦の奥に現れ、着弾まで 1.9 秒、
## ゆっくり動き出して、だんだん速くなる一本のなめらかな動き（2026-11-26 ユーザー「渦から出始める所をもっとゆっくり」→
## 区間に分けて出始めを 7% にしたら「途中で止まって見える」→ 最初から少しずつ進み・大きくなり続ける三次の曲線にした）。
## 進み: 0.5 秒後に約1割、1.1 秒後に約3割、1.6 秒後に約7割、残りを最後の 0.3 秒。
const GIANT_START := 2.25
## 渦が燃え上がる光・手前を流れる雲が消えていく目安
const GIANT_OUT := 3.10

func _giant_f(t: float) -> float:
	var u := RBMHeroFx.ramp(t, GIANT_START, FINAL)
	return 0.18 * u + 0.32 * u * u + 0.5 * u * u * u

## 巨大隕石の半径（ワールド）。5 から 70 へ、近づくほど速く大きくなる
func _giant_r(t: float) -> float:
	var u := RBMHeroFx.ramp(t, GIANT_START, FINAL)
	return 5.0 + 65.0 * (0.25 * u + 0.35 * u * u + 0.4 * u * u * u)

## 巨大隕石の中心（ワールド）。渦から相手の真ん中の上へ
func _giant_pos(t: float) -> Vector2:
	return (RIFT + Vector2(30, -10)).lerp(_final_target() + Vector2(0, -40), _giant_f(t))

## 岩の色（暗い玄武岩。0=いちばん暗い）
const STONE := ["#0a0508", "#170a10", "#28131a", "#3e1e20", "#582b25", "#76402e", "#97593a"]

## 巨大隕石の岩（2026-11-26 ユーザー「最後の隕石の中の岩の形が安っぽい」）:
## ごつごつした13角の岩を、内側の稜線から面ごとに塗り分ける（左上から光、裏は暗い）。
## 落ちる向きの面は熱で赤く、縁は白熱して光る。溶岩のひびが脈打ち、表面のくぼみに影。ゆっくり回りながら落ちる。
func _giant_rock(p: Vector2, R: float, dir: Vector2, t: float) -> void:
	if R < 3.0:
		return
	var n := 13
	var rot := t * 0.55
	var light := Vector3(-0.45, -0.75, 0.5).normalized()
	var outer: Array[Vector2] = []
	var inner: Array[Vector2] = []
	var ks: Array[float] = []
	for i in range(n):
		var k := 0.76 + 0.32 * RBMHeroFx.r(i, 702)
		if i % 5 == 2:
			k *= 0.8
		elif i % 4 == 1:
			k *= 1.08
		ks.append(k)
	for i in range(n):
		var a := TAU * (float(i) + (RBMHeroFx.r(i, 701) - 0.5) * 0.5) / n + rot
		outer.append(p + Vector2(cos(a), sin(a) * 0.92) * R * ks[i])
		var b := TAU * (float(i) + 0.5 + (RBMHeroFx.r(i, 703) - 0.5) * 0.4) / n + rot
		# 内側の稜線は大きくばらつかせる（そろうと宝石のカット面に見える）。外の縁からははみ出さない
		var ir := minf(0.22 + 0.32 * RBMHeroFx.r(i, 704), 0.62 * minf(ks[i], ks[(i + 1) % n]))
		inner.append(p + Vector2(-0.05, -0.06) * R + Vector2(cos(b), sin(b) * 0.92) * R * ir)
	var ridge := p + Vector2(-0.12, -0.16) * R + Vector2.from_angle(rot * 1.3) * R * 0.05
	for i in range(n):
		var j := (i + 1) % n
		_facet(ridge, inner[i], inner[j], p, R, dir, light, i * 3)
		_facet(inner[i], outer[i], outer[j], p, R, dir, light, i * 3 + 1)
		_facet(inner[i], outer[j], inner[j], p, R, dir, light, i * 3 + 2)
	# 表面のくぼみ（暗い穴と、光の反対側の明るい内壁）
	# （黒い点だと穴の開いた球に見えるので、浅く・岩の色に近く）
	for c in range(3):
		var ca := TAU * RBMHeroFx.r(c, 741) + rot
		var cp := p + Vector2(cos(ca), sin(ca) * 0.92) * R * (0.25 + 0.3 * RBMHeroFx.r(c, 742))
		var cr := R * (0.08 + 0.05 * RBMHeroFx.r(c, 743))
		disc(b_dark, cp + Vector2(cr * 0.25, cr * 0.3), cr, cr * 0.6, Color(STONE[5], 0.7), Color(STONE[5], 0.7), 10)
		disc(b_dark, cp, cr, cr * 0.6, Color(STONE[2], 0.85), Color(STONE[2], 0.85), 10)
	var c5 := col(5)
	var c6 := col(6)
	var c7 := col(7)
	# 縁: 落ちる向きは白熱、裏は暗い輪郭
	for i in range(n):
		var j := (i + 1) % n
		var a: Vector2 = outer[i]
		var b: Vector2 = outer[j]
		var h := (((a + b) * 0.5) - p).normalized().dot(dir)
		if h > 0.2:
			var k := (h - 0.2) / 0.8
			b_front.line(a, b, 6.0, Color(c5, 0.4 * k), Color(c5, 0.4 * k))
			b_front.line(a, b, 2.2, Color(c7 if h > 0.7 else c6, 0.95 * k), Color(c6, 0.95 * k))
		else:
			b_dark.line(a, b, 1.6, Color("#05030a"), Color("#05030a"))
	# 溶岩のひび: 真ん中近くから外へ、枝分かれしながら走り、脈打つ
	for k in range(5):
		var a0 := TAU * (float(k) + RBMHeroFx.r(k, 721) * 0.6) / 5.0 + rot
		var pts: Array[Vector2] = [p + Vector2.from_angle(a0) * R * 0.1]
		var ang := a0
		for st in range(4):
			ang += (RBMHeroFx.r(k * 7 + st, 722) - 0.5) * 0.9
			pts.append(pts.back() + Vector2.from_angle(ang) * R * (0.12 + 0.05 * RBMHeroFx.r(k * 7 + st, 723)))
		var pulse := 0.62 + 0.38 * sin(t * 6.0 + k * 1.7)
		var heat := 0.55 + 0.45 * maxf(0.0, Vector2.from_angle(a0).dot(dir))
		for st in range(pts.size() - 1):
			var wk := 1.0 - st * 0.2
			var al := pulse * heat * (1.0 if st < 3 else 0.5)
			b_front.line(pts[st], pts[st + 1], 4.6 * wk, Color(c5, 0.36 * al), Color(c5, 0.3 * al))
			b_front.line(pts[st], pts[st + 1], 1.8 * wk, Color(c7 if st == 0 else c6, 0.95 * al), Color(c6, 0.85 * al))
		var bp: Vector2 = pts[2]
		var ba := ang + (0.9 if k % 2 == 1 else -0.9)
		b_front.line(bp, bp + Vector2.from_angle(ba) * R * 0.15, 1.0, Color(c6, 0.8 * pulse * heat), Color(c5, 0.0))

func _facet(a: Vector2, b: Vector2, c: Vector2, center: Vector2, R: float, dir: Vector2, light: Vector3, id: int) -> void:
	var d := ((a + b + c) / 3.0 - center) / R
	var tilt := Vector2(RBMHeroFx.r(id, 711) - 0.5, RBMHeroFx.r(id, 712) - 0.5) * 0.8
	var n3 := Vector3(d.x * 1.3 + tilt.x, d.y * 1.3 + tilt.y, sqrt(maxf(0.05, 1.0 - d.length_squared()))).normalized()
	var shade := n3.dot(light) * 0.5 + 0.5
	var idx := clampi(int(shade * 6.4 + (RBMHeroFx.r(id, 713) - 0.5) * 1.4) - 1, 0, 6)
	var cc := Color(STONE[idx])
	# 落ちる向き（炎の先頭）の面は、溶けかけた溶岩のように赤→橙→黄へ（4段）。裏側は暗い岩のまま
	var heat := floorf(clampf((Vector2(n3.x, n3.y).dot(dir) + 0.05 + (RBMHeroFx.r(id, 714) - 0.5) * 0.25) / 0.75, 0.0, 1.0) * 4.0)
	if heat >= 4.0:
		cc = col(5)
	elif heat >= 3.0:
		cc = col(4)
	elif heat >= 2.0:
		cc = col(3).lerp(col(4), 0.2)
	elif heat >= 1.0:
		cc = cc.lerp(col(3), 0.55)
	b_dark.tri(a, b, c, cc, cc, cc)

## 炎の尾: 板のような筋ではなく、先へ細くなる炎の舌を何枚も（岩の後ろに描く）と、後ろに残る煙
func _giant_tail(p: Vector2, r: float, dir: Vector2, t: float) -> void:
	var nv := Vector2(-dir.y, dir.x)
	var c4 := col(4)
	var c5 := col(5)
	var c6 := col(6)
	var c7 := col(7)
	for k in range(9):
		var u := (float(k) - 4.0) / 4.0
		var length := r * (2.0 + 0.9 * RBMHeroFx.r(k, 751) - 0.8 * absf(u)) * (1.0 + 0.12 * sin(t * 12.0 + k * 1.9))
		var base := p + nv * u * r * 0.78 - dir * r * 0.2
		var half := nv * r * 0.24
		var tip := base - dir * length + nv * sin(t * 9.0 + k * 2.3) * r * 0.16
		b_tail.tri(base - half, base + half, tip, Color(c5, 0.75), Color(c5, 0.75), Color(c4, 0.0))
		if absf(u) < 0.6:
			var tip2 := base - dir * length * 0.6 + nv * sin(t * 11.0 + k) * r * 0.1
			b_tail.tri(base - half * 0.5, base + half * 0.5, tip2, Color(c7, 0.8), Color(c7, 0.8), Color(c6, 0.0))
	for k in range(7):
		var pos := p - dir * (r * (1.6 + 0.55 * k)) + nv * sin(t * 3.5 + k * 1.3) * r * 0.2
		var rr := r * (0.32 + 0.07 * k)
		disc(b_norm, pos, rr, rr * 0.85, Color(0.07, 0.04, 0.06, 0.55 * (1.0 - k / 7.0)), Color(0.05, 0.03, 0.05, 0.0), 14)

## 落ちる途中で剥がれて後ろへ飛ぶ岩の破片（赤く光り、冷えて暗くなる）
func _giant_chunks(t: float, dir: Vector2) -> void:
	var nv := Vector2(-dir.y, dir.x)
	var c5 := col(5)
	var c6 := col(6)
	for i in range(8):
		var t0 := 3.15 + 0.1 * i + 0.05 * RBMHeroFx.r(i, 731)
		var ca := t - t0
		if ca < 0.0 or ca > 0.5:
			continue
		var r0 := _giant_r(t0) * 0.6
		var side := (RBMHeroFx.r(i, 732) - 0.5) * 2.0
		var start := _giant_pos(t0) + nv * side * r0 - dir * r0 * 0.3
		var v := (-dir * 0.7 + nv * side * 0.9).normalized() * (70.0 + 60.0 * RBMHeroFx.r(i, 733))
		var c := start.lerp(_giant_pos(t), 0.45) + v * ca
		var sz := 2.5 + 3.0 * RBMHeroFx.r(i, 734)
		var spin := t * (3.5 + 2.0 * RBMHeroFx.r(i, 735))
		var pts: Array[Vector2] = []
		for j in range(4):
			pts.append(c + Vector2.from_angle(spin + j * TAU / 4.0 + RBMHeroFx.r(i * 4 + j, 736) * 0.8) * sz * (0.7 + 0.5 * RBMHeroFx.r(i * 4 + j, 737)))
		var cool := RBMHeroFx.ramp(ca, 0.0, 0.35)
		var cc := c5.lerp(Color(STONE[3]), cool)
		cc.a = 1.0 - RBMHeroFx.ramp(ca, 0.35, 0.5)
		b_dark.quad(pts[0], pts[1], pts[2], pts[3], cc, cc, cc, cc)
		if cool < 1.0:
			b_front.line(pts[0], pts[2], sz * 1.2, Color(c6, 0.6 * (1.0 - cool)), Color(c5, 0.0))

## 上空の渦: 黒雲の輪がゆっくり回り、奥に紅い裂け目と黒い稲妻
func _rift(t: float, dark: float) -> void:
	var open := RBMHeroFx.ramp(t, 0.54, 1.2) * (1.0 - RBMHeroFx.ramp(t, 4.6, 5.6))
	if open <= 0.0:
		clouds.visible = false
		return
	var data := PackedVector4Array()
	for i in range(30):
		var th := float(i) / 30.0 * TAU + t * 0.45
		var rad := (60.0 + 40.0 * RBMHeroFx.r(i, 61)) * (0.55 + 0.45 * open)
		var p := RIFT + Vector2(cos(th) * rad * 1.5, sin(th) * rad * 0.28 + 8.0)
		data.append(Vector4(p.x - RBMHeroFx.WORLD.position.x, p.y - RBMHeroFx.WORLD.position.y, (14.0 + 8.0 * RBMHeroFx.r(i, 62)) * open, 0.3 + 0.4 * RBMHeroFx.r(i, 63)))
	show_blast(clouds, data, t * 0.5, {"flow": t * 0.1, "fade": open * 0.9, "cool": 0.0, "erode": 0.0, "erode_noise": 0.6, "tone_cap": 0.8})
	# 渦の腕（紅い光の筋）
	for arm in range(6):
		var prev := Vector2.ZERO
		for j in range(14):
			var u := float(j) / 13.0
			var th := arm * TAU / 6.0 + u * 3.2 - t * 1.6
			var rad := lerpf(6.0, 96.0, u) * open
			var p := RIFT + Vector2(cos(th) * rad * 1.5, sin(th) * rad * 0.3 + 6.0)
			if j > 0:
				var cc := Color("#ed274c")
				cc.a = 0.75 * (1.0 - u) * open
				b_back.line(prev, p, 2.4 * (1.0 - u * 0.6), cc, cc)
			prev = p
	# 裂け目の芯
	disc(b_back, RIFT + Vector2(0, 6), 40.0 * open, 7.0 * open, Color(1.0, 0.25, 0.3, 0.55 * open), Color(0.6, 0.02, 0.1, 0.0))
	disc(b_back, RIFT + Vector2(0, 6), 18.0 * open, 3.0 * open, Color(1.0, 0.85, 0.8, 0.6 * open), Color(1.0, 0.3, 0.3, 0.0))
	# 黒い稲妻（雲の中を走る）
	var phase := int(floor(t * 4.0))
	if RBMHeroFx.r(phase, 66) > 0.45:
		var a := RIFT + Vector2((RBMHeroFx.r(phase, 67) - 0.5) * 260.0, 4.0)
		var c := a + Vector2((RBMHeroFx.r(phase, 68) - 0.5) * 140.0, 26.0 + 20.0 * RBMHeroFx.r(phase, 69))
		black_bolt(b_back, b_dark, a, c, phase * 5, 1.6, open * (1.0 - fmod(t * 4.0, 1.0)), Color("#ed274c"), 8, 0.3, true)

## 燃える岩: 炎の尾（3層）・煙の尾・暗い岩に光るひび
func _rock(p0: Vector2, p1: Vector2, q: float, i: int, size_k: float) -> void:
	var qq := pow(q, 1.5)
	var p := p0.lerp(p1, qq)
	var dir := (p1 - p0).normalized()
	var trail := (14.0 + 46.0 * q) * size_k
	var c4 := col(4)
	var c6 := col(6)
	var c7 := col(7)
	# 煙の尾
	for k in range(6):
		var u := float(k + 1) / 6.0
		var sp_ := p - dir * trail * (0.6 + u * 1.2) + Vector2(RBMHeroFx.r(i * 7 + k, 21) - 0.5, RBMHeroFx.r(i * 7 + k, 22) - 0.5) * 6.0
		disc(b_norm, sp_, (3.0 + u * 5.0) * size_k, (3.0 + u * 5.0) * size_k, Color(0.07, 0.05, 0.08, 0.5 * (1.0 - u)))
	# 炎の尾
	b_front.streak(p - dir * trail * 1.3, p, 9.0 * size_k, Color(c4, 0.85), Color(col(3), 0.0))
	b_front.streak(p - dir * trail, p, 5.5 * size_k, Color(c6, 0.95), Color(c4, 0.0))
	b_front.streak(p - dir * trail * 0.6, p, 2.5 * size_k, Color(c7, 1.0), Color(c6, 0.0))
	disc(b_front, p, 7.0 * size_k, 7.0 * size_k, Color(c6, 0.5), Color(c4, 0.0))
	# 岩（暗い面と、熱で光る面）
	b_norm.shard(p, 3.6 * size_k, q * 9.0 + i, i, Color("#4a3640"), Color("#1a1018"))
	b_front.dot_px(p + Vector2(-1, -1), 1.0, Color(c7, 0.9))

## 巨大隕石: 渦の奥から現れ（渦が燃え上がる）、重くゆっくり迫り（地鳴り・影・暗さ・炎の照り返しが強まる）、最後に落ちる → 着弾
func _giant(t: float) -> void:
	var target := _final_target()
	var c5 := col(5)
	var c6 := col(6)
	var c7 := col(7)
	var q := RBMHeroFx.ramp(t, GIANT_START, FINAL)
	var on := t >= GIANT_START and t < FINAL
	fireball.visible = on
	# 渦の奥が燃え上がる（巨大隕石が押し出されてくる）
	var emerge := RBMHeroFx.env(t, GIANT_START - 0.15, GIANT_START + 0.2, GIANT_OUT, GIANT_OUT + 0.45)
	if emerge > 0.0:
		disc(b_back, RIFT + Vector2(0, 6), 78.0 * emerge, 16.0 * emerge, Color(1.0, 0.35, 0.28, 0.5 * emerge), Color(0.7, 0.05, 0.1, 0.0), 28)
		disc(b_back, RIFT + Vector2(0, 6), 34.0 * emerge, 7.0 * emerge, Color(1.0, 0.85, 0.7, 0.55 * emerge), Color(1.0, 0.4, 0.3, 0.0), 24)
		circle_line(b_back, RIFT + Vector2(0, 6), 20.0 + 90.0 * RBMHeroFx.burst(t - GIANT_START + 0.12, 3.0), 1.6, Color(c6, 0.6 * emerge), 36, 0.22)
	if on:
		var p := _giant_pos(t)
		var r := _giant_r(t)
		var dir := (target - (RIFT + Vector2(30, -10))).normalized()
		# 迫ってくるほど: 地鳴り（低く重い揺れ）が強く、空が暗く、味方が上から炎の色に照らされる
		var near := q * q
		view["dim"] = float(view["dim"]) + 0.16 * near
		set_post({"vig": 0.55 + 0.3 * near, "vig_col": Vector3(0.1, 0.0, 0.02)})
		ally_light(0.75 * pow(q, 2.5), c5, 0.0)
		# 炎の外套（玉のシェーダー）
		fireball.position = p - Vector2(100, 100)
		sp(fireball, {"radius": r / 100.0 * 1.05, "flow": t * 2.6, "seed": 5.0, "spike": 0.55, "glow": 1.0 + q, "glow_col": c5, "fade": 1.0})
		_giant_tail(p, r, dir, t)
		_giant_rock(p + dir * r * 0.08, r * 0.8, dir, t)
		_giant_chunks(t, dir)
		# 渦から出始める間: 渦の雲が隕石の手前を流れて覆う（雲を押し分けて出てくる）。出るほど薄れる
		var veil := 1.0 - RBMHeroFx.ramp(t, GIANT_START + 0.25, GIANT_OUT + 0.15)
		if veil > 0.0:
			for k in range(9):
				var th := float(k) / 9.0 * TAU + t * 0.45
				var rad := 22.0 + 26.0 * RBMHeroFx.r(k, 781)
				var cp := RIFT + Vector2(cos(th) * rad * 1.5, sin(th) * rad * 0.3 + 8.0)
				if sin(th) < -0.2:
					continue
				var cr := 12.0 + 8.0 * RBMHeroFx.r(k, 782)
				var cc := Color(["#140b18", "#1c0e20", "#26102a"][k % 3])
				cc.a = 0.85 * veil
				disc(b_dark, cp, cr, cr * 0.45, cc, Color(cc, 0.0), 14)
		# 足元に広がる影と、熱の揺らぎ
		var sh := RBMHeroFx.ramp(t, 2.85, FINAL)
		var sw := 30.0 + 130.0 * pow(sh, 1.5)
		disc(b_norm, target + Vector2(0, 2), sw, sw * 0.2, Color(0.03, 0.01, 0.03, 0.15 + 0.55 * sh))
		if q > 0.5:
			refract_wave(target, fmod(t, 0.3), 0.3, 60.0 + 80.0 * q, 6.0, 0.006 * q)
		view["shake"] = Vector2(sin(t * 38.0), cos(t * 33.0)) * (0.8 + 3.2 * near)
	# 着弾
	var a := t - FINAL
	if a < 0.0:
		big_blast.visible = false
		ring.visible = false
		cracks.visible = false
		smoke.visible = false
		return
	set_post({"flash": 0.85 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.16)), "flash_col": Color(1, 0.97, 0.92)})
	if a < 0.1:
		set_post({"impact": 1.0, "impact_hi": Vector3(c7.r, c7.g, c7.b), "impact_lo": Vector3(0.1, 0.0, 0.03), "impact_cut": 0.38})
	if a < 0.5:
		set_post({"chroma": 0.006 * (1.0 - a / 0.5), "radial": 0.12 * (1.0 - a / 0.5), "focus_world": target})
	view["shake"] = hit_shake(a, 60.0, 80.0, 1.0)
	if a < 1.3:
		var bb := blobs(target + Vector2(0, -16), a, 34, 1300, 250.0, 100.0, 70.0, 100.0, 0.6, 0.0, 6.6)
		show_blast(big_blast, bb, a, {"flow": a * 0.22, "cool": 0.05 + RBMHeroFx.ramp(a, 0.2, 1.0) * 0.25, "erode": RBMHeroFx.ramp(a, 0.3, 0.95), "fade": 1.0 - RBMHeroFx.ramp(a, 0.7, 1.2), "erode_noise": 0.4})
	else:
		big_blast.visible = false
	if a < 1.4:
		show_ring(ring, target, a, 1.0, 330.0, 10.0, 6.0, 0.03)
		cracks.visible = true
		sp(cracks, {"center": w(target), "reveal": 280.0 * RBMHeroFx.burst(a, 7.0), "seed": 9.0, "fade": 1.0 - RBMHeroFx.ramp(a, 1.0, 1.4), "clip_y": w(target).y - 40.0})
	else:
		ring.visible = false
		cracks.visible = false
	rocks(b_front, target, a, 1.2, 34, 1400, 330.0, 6.0, 10.0)
	sparks(b_front, target + Vector2(0, -20), a, 0.9, 70, 1450, 340.0, c7, c5, -PI * 0.5, PI * 1.4, 300.0, 2.2)
	star(b_front, target + Vector2(0, -30), RBMHeroFx.env(a, 0.0, 0.03, 0.08, 0.35), 16, 1470, 160.0, 9.0, [c7, c6, c5])
	# 煙の柱と火の粉
	if a > 0.4 and a < 2.5:
		var sa := a - 0.4
		var sm := blobs(target + Vector2(0, -60 - sa * 14.0), sa * 0.5, 20, 1500, 160.0, 60.0, 34.0, 90.0, 0.1, 0.0, 2.0)
		show_blast(smoke, sm, sa, {"flow": sa * 0.12, "cool": 0.0, "erode": RBMHeroFx.ramp(sa, 0.9, 2.1), "fade": (1.0 - RBMHeroFx.ramp(sa, 1.1, 2.1)) * RBMHeroFx.ramp(sa, 0.0, 0.4) * 0.7, "erode_noise": 0.6, "tone_cap": 0.6})
	else:
		smoke.visible = false
	embers(b_front, Rect2(target + Vector2(-140, -30), Vector2(280, 30)), t, 40, 1600, 120.0, c6, 1.0 - RBMHeroFx.ramp(a, 1.5, 2.4), 1.6, 14.0)
