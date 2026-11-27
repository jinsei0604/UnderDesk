extends RBMDragonFxBase
## 竜の息吹（2026-11-25 試作 → 2026-11-26 ユーザー承認）。
## 覚醒前・全体「翠鱗の息吹」: 体を起こして息を吸う → 口の前に光が集まって玉になる → 玉がぎゅっと縮んで一瞬止まる
## → 解放（閃光と衝撃の輪）→ 渦を巻く炎の流れが四人を呑み込む → 流れが口から離れて燃え尽き、煙と火の粉が残る。
## 覚醒後・単体「黒焔の一閃」（focused）: 黒い稲妻をまとって玉に集め、縮めて解放 → 細く鋭い光線が一人を貫き、
## 黒紅の螺旋と稲妻が光線を這う → 当たった所で爆炎が続き、最後に大きく弾ける。
## 解放・命中の時刻は今の音（dragon_normal_breath / dragon_awakened_breath）に合わせてある。
## 2026-11-26 ユーザーの指摘で: 炎は口の先の丸い玉からあふれ出す（腹からではない）・何回も当たる（TICK ごと、最後に合計）・
## 覚醒後の単体の爆炎は前の作りのまま（_focused_burst）・全体の細かい動きを落ち着かせた（速さの直し）。

var focused := false

const TN := {"inhale": .24, "ball": .48, "squeeze": .64, "release": .78, "hit": 1.02, "cut": 2.40, "gone": 2.64, "end": 4.05}
const TF := {"inhale": .24, "ball": .50, "squeeze": .66, "release": .82, "hit": 1.04, "cut": 2.68, "gone": 2.90, "end": 4.45}

var b_back: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_dark: RBMHeroFxBatch
var b_smoke: RBMHeroFxBatch
var b_licks: RBMHeroFxBatch
var orb: ColorRect
var outer: ColorRect
var inner: ColorRect
## 相手ごとの爆炎（それぞれ自分の時刻で溶けて消える）
var bursts: Array = []
var smoke: ColorRect
const SMOKE := ["#141214", "#1e1a1c", "#2a2426", "#363032", "#433c3e", "#514a4c", "#5e5658", "#6c6466"]

func T(k: String) -> float:
	return float((TF if focused else TN)[k])

func duration() -> float:
	return T("end")

## 何回も当たる（2026-11-26 ユーザー「ブレスの当たりが1回はおかしい」）: 流れが当たっている間 TICK 秒ごとに小さく当たり、
## 流れが口から離れる直前（impact）に最後の一撃で合計を出す（stage.begin_multi_hit と同じ形。戦闘の数値は変えない）。
## 何回も当たる間隔（2026-11-26 速さの直し: 0.28 → 0.34。閃光・火花・小さな数字が出る回数を減らして落ち着かせる）
const TICK := 0.34

func ticks(i: int) -> Array:
	var out := []
	var at := T("hit") + (0.0 if focused else i * 0.035)
	while at < T("cut") - 0.18:
		out.append(at)
		at += TICK
	return out

func impact() -> float:
	return T("cut") - 0.04

func final_share() -> float:
	return 0.25

## 小さな数字・HP の更新の時刻（2026-11-27 ユーザー「案B」）: 当たりの見た目（閃光・火花・のけぞり）は ticks(i) のまま
## 4人へ0.035秒ずつずらすが、数字と HP の更新は一番先に当たる人の時刻に4人同時にまとめる
## （更新が4コマ続くと、バッテリー駆動の時にコマを取りこぼしやすかった）。当たる回数は4人とも同じ。
func multi_plan() -> Dictionary:
	var plan := {}
	var shared := ticks(0)
	for i in range(1 if focused else count):
		plan[i] = shared.duplicate()
	return plan

func hits() -> Array:
	var out := []
	for i in range(1 if focused else count):
		for at in ticks(i):
			out.append([float(at), i])
		out.append([impact(), i])
	return out

func body_at(t: float) -> Dictionary:
	var s := {"pose": 0, "off": Vector2.ZERO, "scale": Vector2.ONE}
	var rel := T("release")
	if t < 0.0:
		return s
	if t < T("inhale"):
		s.pose = 1
	elif t < T("ball"):
		s.pose = 4
		s.scale = Vector2(1.0, 1.0 + 0.05 * sin((t - T("inhale")) / (T("ball") - T("inhale")) * PI))
	elif t < T("gone"):
		s.pose = 5 if focused else 2
		# 溜めでわずかに前へ、解放の反動で後ろへ押される
		var lean := -6.0 * RBMHeroFx.ramp(t, T("ball"), rel)
		var kick := 10.0 * RBMHeroFx.env(t, rel, rel + 0.05, rel + 0.12, rel + 0.5)
		s.off = Vector2(lean + kick, 0)
	elif t < T("gone") + 0.25:
		s.pose = 1
	return s

func _build() -> void:
	var pal := ramp8()
	b_back = batch(back)
	# 炎の流れは味方の後ろ（back）。味方は炎の中に見え、手前には燃える炎の舌（b_licks）と爆炎を重ねる
	outer = breath_strip(back, pal, {"seed": 3.1 if focused else 1.7})
	var hot := [pal[3], pal[4], pal[5], pal[5], pal[6], pal[6], pal[7], pal[7]]
	inner = breath_strip(back, hot, {"seed": 7.3})
	smoke = blast_quad(mid, SMOKE, SMOKE, {"amp": 16.0, "k": 0.08, "seed": 4.4, "glow": 0.0, "glow_r": 12.0})
	for i in range(1 if focused else count):
		bursts.append(blast_quad(mid, pal, pal, {"amp": 18.0, "k": 0.1, "seed": 2.0 + i, "glow": 0.8, "glow_col": RBMHeroFx.v3(col(5)), "glow_r": 26.0}))
	b_licks = batch(mid)
	b_smoke = batch(mid, false)
	orb = quad(front, Rect2(0, 0, 96, 96), "orb", {"pal": RBMHeroFx.pal(pal)})
	b_dark = batch(front, false)
	b_front = batch(front)

func _aim() -> Vector2:
	if focused or count <= 1:
		return target_chest(0)
	var a := Vector2.ZERO
	for i in range(count):
		a += target_chest(i)
	return a / float(count)

func _step(t: float) -> void:
	for b in [b_back, b_front, b_dark, b_smoke, b_licks]:
		(b as RBMHeroFxBatch).reset()
	var rel := T("release")
	var aim := _aim()
	var dir := (aim - mouth).normalized()
	if dir.x > -0.2:
		dir = Vector2(-1, 0.1).normalized()
	var side := Vector2(-dir.y, dir.x)
	# 玉は口の先（2026-11-26 ユーザー「腹からではなく、口元の先に丸い球体を作ってそこから溢れ出す」）
	var ball := mouth + dir * (24.0 if focused else 22.0)
	var c5 := col(5)
	var c6 := col(6)
	var c7 := col(7)
	# 暗さ（溜めで少し暗くし、息吹を目立たせる）
	var dim := 0.22 * RBMHeroFx.ramp(t, T("inhale"), rel) * (1.0 - RBMHeroFx.ramp(t, T("cut"), T("gone") + 0.6))
	if focused:
		dim = 0.42 * RBMHeroFx.ramp(t, T("inhale"), rel) * (1.0 - RBMHeroFx.ramp(t, T("cut"), T("gone") + 0.7))
		view["dim_col"] = Color(0.07, 0.02, 0.05)
		set_post({"vig": 0.45 * dim, "vig_col": Vector3(0.12, 0.0, 0.03)})
	view["dim"] = dim

	# ---- 溜め: 光が集まる → 玉 → 縮む → 一瞬止まる ----
	var gather := RBMHeroFx.env(t, T("inhale"), T("inhale") + 0.12, rel - 0.06, rel)
	if gather > 0.0:
		inward(b_front, ball, t, 34, 11, 4.0, 78.0, 1.4, Color(c6, 0.95), gather, 2.2)
		for i in range(22):
			var q := fmod(t * (0.75 + 0.4 * RBMHeroFx.r(i, 41)) + RBMHeroFx.r(i, 42), 1.0)
			var th := RBMHeroFx.r(i, 43) * TAU + q * 4.5 * (1 if i % 2 == 0 else -1)
			var rad := lerpf(58.0, 3.0, q * q)
			b_front.dot_px(ball + Vector2.from_angle(th) * Vector2(rad, rad * 0.8), 1.0 + float(i % 2), Color(c6 if i % 3 else c7, sin(q * PI) * gather))
		if focused:
			# 黒い稲妻が玉へ吸い込まれる
			for k in range(3):
				var phase := floorf(t * 8.0) + k * 17.0
				var from := ball + Vector2.from_angle(RBMHeroFx.r(int(phase), 5) * TAU) * (46.0 + 18.0 * RBMHeroFx.r(int(phase), 6))
				black_bolt(b_front, b_dark, from, ball, int(phase) * 3 + k, 1.3, gather * (0.5 + 0.5 * RBMHeroFx.r(int(phase), 7)), Color("#ed274c"), 7, 0.25, false)
	# 玉
	var grow := RBMHeroFx.ramp(t, T("ball"), T("squeeze"))
	var squeeze := RBMHeroFx.ramp(t, T("squeeze"), rel - 0.04)
	# 玉は解放の後も口の先に残り、炎はそこから溢れ出し続ける。流れが離れる時に縮んで消える
	var orb_on := t >= T("ball") and t < T("gone")
	orb.visible = orb_on
	var ball_r := 0.0
	if orb_on:
		var rr := lerpf(0.10, 0.44, grow * grow * (3.0 - 2.0 * grow))
		rr = lerpf(rr, 0.15, squeeze * squeeze) * (1.0 + 0.05 * sin(t * 45.0) * squeeze)
		var sustain := RBMHeroFx.ramp(t, rel, rel + 0.08)
		if t >= rel:
			rr = lerpf(0.15, 0.32, sustain) * (1.0 + 0.06 * sin(t * 14.0))
		rr *= 1.0 - RBMHeroFx.ramp(t, T("cut"), T("gone"))
		ball_r = rr * 48.0
		orb.position = ball - Vector2(48, 48)
		var churn := sustain * (1.0 - RBMHeroFx.ramp(t, T("cut"), T("gone")))
		sp(orb, {"radius": rr, "flow": t * (2.0 + 2.5 * squeeze + 2.5 * churn), "seed": 2.0, "spike": 0.3 + 0.5 * squeeze + 0.2 * churn, "glow": 0.7 + 1.6 * squeeze + 0.6 * churn, "glow_col": c5, "fade": 1.0})
		# 玉の縁から前へ溢れ出す炎の舌
		if churn > 0.0:
			for k in range(9):
				var ph := t * (5.0 + 2.5 * RBMHeroFx.r(k, 61)) + RBMHeroFx.r(k, 62) * TAU
				var th := dir.angle() + (RBMHeroFx.r(k, 63) - 0.5) * 2.6
				var o := ball + Vector2.from_angle(th) * ball_r * 0.85
				var d := (Vector2.from_angle(th) * 0.4 + dir).normalized()
				var l := ball_r * (0.9 + 0.7 * RBMHeroFx.r(k, 64)) * (0.75 + 0.25 * sin(ph))
				b_front.spike(o, d, l, ball_r * 0.5, Color(col(5), 0.85 * churn), Color(col(4), 0.0))
				b_front.spike(o, d, l * 0.6, ball_r * 0.28, Color(c6, 0.9 * churn), Color(c6, 0.0))
		# 縮める輪（外から内へ締まる）
		for k in range(2):
			var q := fmod(squeeze * 2.0 + k * 0.5, 1.0)
			if squeeze > 0.0:
				circle_line(b_front, ball, lerpf(34.0, 7.0, q), 1.2, Color(c6, (1.0 - q) * 0.9 * squeeze), 26)
		# 一瞬止まる所: 芯が白く小さく瞬く
		var hold := RBMHeroFx.env(t, rel - 0.06, rel - 0.04, rel - 0.005, rel)
		if hold > 0.0:
			star(b_front, ball, 0.35 * hold, 8, 23, 18.0, 2.5, [c7, c6])
	# ---- 解放 ----
	var e := t - rel
	if e >= 0.0 and e < 0.4:
		var s := RBMHeroFx.env(e, 0.0, 0.02, 0.05, 0.24)
		star(b_front, ball, s, 14, 31, 70.0 if not focused else 84.0, 5.5, [c7, c6, c5])
		var rr := 8.0 + 130.0 * RBMHeroFx.burst(e, 9.0)
		circle_line(b_front, ball, rr, 3.0 * (1.0 - e / 0.4), Color(c6, 1.0 - e / 0.4), 36, 0.8)
		circle_line(b_front, ball, rr * 0.62, 2.0 * (1.0 - e / 0.4), Color(c7, (1.0 - e / 0.4) * 0.8), 30, 0.8)
		refract_wave(ball, e, 0.4, 150.0, 8.0, 0.012)
		set_post({"flash": 0.32 * (1.0 - RBMHeroFx.ramp(e, 0.0, 0.14)), "flash_col": c6})
		if focused:
			set_post({"chroma": 0.004 * (1.0 - e / 0.4)})
		view["shake"] = hit_shake(e, 14.0 if focused else 9.0, 90.0, 0.3)
	# ---- 流れ ----
	var head := 0.0
	if e >= 0.0:
		var g := RBMHeroFx.ramp(e, 0.0, 0.11 if focused else 0.2)
		head = 1.03 * (1.0 - pow(1.0 - g, 3.0))
	var tail := RBMHeroFx.ramp(t, T("cut"), T("gone"))
	var on := e >= 0.0 and tail < 1.0
	outer.visible = on
	inner.visible = on
	var length := maxf(80.0, (ball.x + 60.0) / maxf(-dir.x, 0.15))
	var start := ball
	if on:
		var h := 96.0 if focused else 200.0
		place_strip(outer, start, dir, length, h)
		# 流れの根元の太さを玉の大きさに合わせる（玉から溢れ出して見えるように）
		sp(outer, {"head": head, "tail": tail, "flow": e, "speed": 5.5 if focused else 3.0, "w0": 0.3 if focused else 0.14, "w1": 0.62 if focused else 1.0,
			"rough": 0.22 if focused else 0.34, "core": 0.85 if focused else 0.5, "cool": 0.25 if focused else 0.55, "glow": 0.8, "glow_col": c5, "fade": 1.0})
		place_strip(inner, start, dir, length, h * (0.42 if focused else 0.4))
		sp(inner, {"head": head * 0.98, "tail": tail, "flow": e * 1.2, "speed": 7.0 if focused else 4.2, "w0": 0.42 if focused else 0.22, "w1": 0.55, "rough": 0.2, "core": 1.0, "cool": 0.3, "glow": 0.0, "fade": 1.0})
		# 流れに乗って飛ぶ火の粉
		var alive := 1.0 - tail
		for i in range(54 if focused else 70):
			var u := fmod(e * (1.5 if focused else 0.95) * (0.7 + 0.6 * RBMHeroFx.r(i, 71)) + RBMHeroFx.r(i, 72), 1.0)
			if u > head * 0.98 or u < tail:
				continue
			var half := length * 0.5 * (0.6 if focused else 1.0) * lerpf(0.08, 0.9, pow(u, 0.72)) * (96.0 if focused else 230.0) / length
			var p := start + dir * length * u + side * (RBMHeroFx.r(i, 73) - 0.5) * 2.0 * half
			var cc := c7 if i % 4 == 0 else c6
			cc.a = 0.9 * alive * (1.0 - u * 0.6)
			b_front.streak(p - dir * (8.0 + 10.0 * u), p, 1.6, cc, Color(cc, 0.0))
	if focused and on:
		_focused_extras(t, e, start, dir, side, length, head, tail)
	# ---- 当たり ----
	_impacts(t, dir)
	_smoke(t, dir)
	for b in [b_back, b_front, b_dark, b_smoke, b_licks]:
		(b as RBMHeroFxBatch).commit()
	ally_hits(t, hits(), 1.2 if focused else 1.0)
	var lit := RBMHeroFx.env(t, T("hit") - 0.05, T("hit"), T("cut"), T("gone") + 0.2)
	ally_light(0.85 * lit, c5, 0.5 * lit)

## 覚醒後の光線: 黒紅の螺旋・進む環・光線を這う黒い稲妻
func _focused_extras(t: float, e: float, start: Vector2, dir: Vector2, side: Vector2, length: float, head: float, tail: float) -> void:
	var reach := length * head
	var red := Color("#ed274c")
	for strand in range(2):
		var prev := Vector2.ZERO
		for j in range(33):
			var u := float(j) / 32.0
			if u > head or u < tail:
				prev = Vector2.ZERO
				continue
			var radius := 7.0 + 18.0 * u
			var p := start + dir * reach * u + side * sin(u * 16.0 - e * 18.0 + strand * PI) * radius
			if prev != Vector2.ZERO:
				var cc := red if strand == 0 else col(6)
				cc.a = 0.85 * (1.0 - tail)
				b_front.line(prev, p, 1.6, cc, cc)
			prev = p
	for k in range(5):
		var u := fmod(e * 1.1 + k * 0.2, 1.0) * head
		if u < tail:
			continue
		circle_line(b_front, start + dir * reach * u, 8.0 + 16.0 * u, 1.4, Color(col(6), (1.0 - u) * 0.8 * (1.0 - tail)), 22, 0.32)
	for k in range(3):
		var phase := int(floor(t * 9.0)) * 3 + k
		var u0 := RBMHeroFx.r(phase, 31) * head * 0.9
		var u1 := u0 + 0.12 + 0.1 * RBMHeroFx.r(phase, 32)
		if u0 < tail:
			continue
		var off0 := side * (RBMHeroFx.r(phase, 33) - 0.5) * 30.0
		var off1 := side * (RBMHeroFx.r(phase, 34) - 0.5) * 40.0
		black_bolt(b_front, b_dark, start + dir * reach * u0 + off0, start + dir * reach * minf(u1, head) + off1, phase, 1.2, 0.9 * (1.0 - tail), red, 7, 0.3, false)


## 当たり: 当たった瞬間に爆炎（相手ごとに溶けて消える）、燃えている間は手前に炎の舌、覚醒後の光線は爆炎が続く
func _impacts(t: float, dir: Vector2) -> void:
	var ends := T("cut")
	for bi in range(bursts.size()):
		var q: ColorRect = bursts[bi]
		var i := bi
		var tl: Array = ticks(i)
		var at := float(tl[0])
		var p := target_chest(i) + Vector2(2, 2)
		var a := t - at
		if a < 0.0:
			q.visible = false
			continue
		var last := 0
		for k in range(tl.size()):
			if t >= float(tl[k]):
				last = k
		var la := t - float(tl[last])
		var af := t - impact()
		if focused:
			_focused_burst(q, t, a, ends, p, i, dir)
		else:
			# 最初に当たった瞬間の爆炎は前回（2026-11-25）のまま。途中の当たりと最後の一撃は閃光にする
			# （炎の帯の中で爆炎の玉を何度も弾けさせると、冷えて溶ける玉が茶色い岩の塊・破片に見え、味方を隠す。2026-11-26 確認）
			if a <= 0.55:
				var data := blobs(p, a, 14, 100 + i * 13, 26.0, 20.0, 15.0, 18.0, 1.1, 0.0, 9.5)
				show_blast(q, data, a, {"cool": RBMHeroFx.ramp(a, 0.1, 0.45) * 0.2, "erode": RBMHeroFx.ramp(a, 0.1, 0.42), "fade": 1.0 - RBMHeroFx.ramp(a, 0.24, 0.46), "erode_noise": 0.4, "flow": a * 0.3})
			else:
				q.visible = false
			if last > 0 and la < 0.16:
				_flash(p, la, 0.16, 1.0, 430 + i * 7 + last)
			if af >= 0.0 and af < 0.32:
				_flash(p, af, 0.32, 2.2, 470 + i * 7)
			sparks(b_front, p, a, 0.55, 14, 400 + i, 110.0, col(7), col(5), dir.angle(), 1.4, 160.0, 1.6)
			if last > 0:
				sparks(b_front, p, la, 0.4, 8, 440 + i * 5 + last, 110.0, col(7), col(5), dir.angle(), 1.4, 160.0, 1.6)
		# 燃えている間: 手前に炎の舌（味方が炎の中に見える）
		var burn := RBMHeroFx.env(t, at, at + 0.06, ends, T("gone") + 0.15)
		if burn > 0.0:
			_licks(target_chest(i) + Vector2(0, 18), t, i, burn * (1.3 if focused else 1.0), -dir)

## 覚醒後・単体（集中の息吹）の相手の所の爆炎: 前回（2026-11-25、ユーザー「すごくいい」）の作りそのまま。
## 光線が当たっている間は 0.28 秒ごとに爆炎が弾け直し（= 何回も当たる時刻 ticks と同じ間隔）、光線が切れた時に大きな爆炎。
func _focused_burst(q: ColorRect, t: float, a: float, ends: float, p: Vector2, i: int, dir: Vector2) -> void:
	var la := a
	var seed_ := 100 + i * 13
	var big := 1.0
	if t < ends:
		la = fmod(a, TICK)
		seed_ += int(a / TICK) * 7
		big = 0.8
	var fa := t - ends
	if fa >= 0.0:
		la = fa
		seed_ = 777
		big = 1.6
	if la > 0.55:
		q.visible = false
	else:
		var data := blobs(p, la, 14, seed_, 26.0 * big, 20.0 * big, 15.0 * big, 18.0 * big, 1.1, 0.0, 9.5)
		show_blast(q, data, la, {"cool": RBMHeroFx.ramp(la, 0.1, 0.45) * 0.2, "erode": RBMHeroFx.ramp(la, 0.1, 0.42), "fade": 1.0 - RBMHeroFx.ramp(la, 0.24, 0.46), "erode_noise": 0.4, "flow": la * 0.3})
	sparks(b_front, p, a, 0.55, 26, 400 + i, 150.0, col(7), col(5), dir.angle(), 1.4, 160.0, 1.6)
	if fmod(a, TICK) < 0.1 and t < ends:
		sparks(b_front, p, fmod(a, TICK), 0.4, 18, 430 + int(a / TICK), 180.0, col(7), col(4), dir.angle(), 1.2, 140.0, 1.6)
	if a < 0.6:
		rocks(b_front, target_chest(i) + Vector2(0, 20), a, 0.6, 8, 500, 120.0, 3.0, 4.0)

## 当たりの閃光（白い芯・橙の光・星・輪）。size で大きさ
func _flash(p: Vector2, ea: float, life: float, size: float, seed_: int) -> void:
	var kk := 1.0 - ea / life
	var rr := (7.0 + 14.0 * RBMHeroFx.burst(ea, 12.0)) * size
	disc(b_front, p, rr, rr * 0.85, Color(col(6), 0.55 * kk), Color(col(5), 0.0), 18)
	disc(b_front, p, rr * 0.45, rr * 0.4, Color(col(7), 0.85 * kk * kk), Color(col(6), 0.0), 14)
	star(b_front, p, RBMHeroFx.env(ea, 0.0, 0.02, 0.04, life * 0.8), 8 if size < 1.5 else 10, seed_, 18.0 * size, 2.4 + 0.5 * size, [col(7), col(6), col(5)])
	if size >= 1.5:
		circle_line(b_front, p + Vector2(0, 14), 6.0 + 18.0 * size * RBMHeroFx.burst(ea, 9.0), 1.6, Color(col(6), 0.8 * kk), 24, 0.35)

## 炎の舌（下から上へ揺れながら立ち上る、先の細い炎）
func _licks(base: Vector2, t: float, i: int, power: float, wind: Vector2) -> void:
	for k in range(7):
		var ph := t * (4.5 + 2.0 * RBMHeroFx.r(k, 51 + i)) + RBMHeroFx.r(k, 52 + i) * TAU
		var x := (RBMHeroFx.r(k, 53 + i) - 0.5) * 26.0
		var o := base + Vector2(x, -2.0 * RBMHeroFx.r(k, 54))
		var length := (12.0 + 14.0 * RBMHeroFx.r(k, 55 + i)) * (0.7 + 0.3 * sin(ph)) * power
		var d := (Vector2(0, -1) + wind * 0.55 + Vector2(sin(ph * 1.3) * 0.25, 0)).normalized()
		b_licks.spike(o, d, length, 6.0 * power, Color(col(4), 0.85 * minf(power, 1.0)), Color(col(5), 0.0))
		b_licks.spike(o, d, length * 0.6, 3.0 * power, Color(col(6), 0.9 * minf(power, 1.0)), Color(col(6), 0.0))
	# 熱で浮かぶ火の粉
	embers(b_licks, Rect2(base + Vector2(-16, -30), Vector2(32, 30)), t, 6, 600 + i * 7, 40.0, col(6), power, 1.2, 6.0)

## 燃え尽きた後の煙（薄く透ける）と、地面から昇る火の粉
func _smoke(t: float, _dir: Vector2) -> void:
	var a := t - T("cut")
	if a < 0.0 or a > 2.0:
		smoke.visible = false
		return
	var data := PackedVector4Array()
	for i in range(1 if focused else count):
		var p := target_chest(i) + Vector2(4, -4)
		data.append_array(blobs(p, a * 0.5, 6, 700 + i * 5, 22.0, 14.0, 12.0, 40.0 + 26.0 * a, 0.1, 0.0, 2.0))
	show_blast(smoke, data, a, {"flow": a * 0.15, "cool": 0.0, "erode": RBMHeroFx.ramp(a, 0.8, 2.0), "fade": (1.0 - RBMHeroFx.ramp(a, 1.0, 2.0)) * RBMHeroFx.ramp(a, 0.0, 0.3) * 0.55, "erode_noise": 0.6, "tone_cap": 0.6})
	for i in range(1 if focused else count):
		var base := Vector2(targets[i]) if i < targets.size() else home
		embers(b_front, Rect2(base + Vector2(-26, -10), Vector2(52, 10)), t, 10, 800 + i * 9, 70.0, col(6), 1.0 - RBMHeroFx.ramp(a, 0.8, 1.8), 1.5, 8.0)
