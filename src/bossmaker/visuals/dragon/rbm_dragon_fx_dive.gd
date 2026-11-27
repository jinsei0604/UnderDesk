extends RBMDragonFxBase
## 翠鱗の竜・覚醒前単体「天翔墜撃」（2026-11-25 試作 → 2026-11-26 ユーザー承認。前の噛みつきの代わり）:
## その場で咆哮する（声の輪・空気のゆがみ・小さな揺れ）→ 身をかがめて溜める → 翼を広げて一気に空へ舞い上がる（地面に風の輪と砂煙）→ 画面の外へ消える
## → 相手の足元に影が落ち、大きくなっていく（上空で光が瞬く）→ 真上から急降下して叩きつける
## （白い閃光・二色の衝撃コマ・地割れ・岩・衝撃の輪）→ 翼をはためかせて元の位置へ跳んで戻る（着弾の後は咆哮しない）。
## 降りる場所は相手の右（竜の前足が相手に届く所）。体の絵は今の12ポーズだけを使う。

## 2026-11-26 ユーザー「着弾の後の咆哮はいらない。するなら動く前に咆哮して攻撃する」→ 最初に咆哮してから飛び立つ
## 2026-11-26 速さの直し: かがむ・飛び立つ・急降下・着地の後の溜め・跳んで戻るの間を長く（2.70 → 3.50 秒）
const T := {"roar": .04, "roar_end": .84, "crouch": .84, "takeoff": 1.12, "gone": 1.44, "dive": 1.90, "hit": 2.10, "leap": 2.56, "land": 3.04, "end": 3.50}
## 着地の位置: 相手の足元から右へ（ステージの画素）
const LAND_DX := 118.0

var b_back: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_norm: RBMHeroFxBatch
var blast: ColorRect
var ring: ColorRect
var cracks: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.hit

func hits() -> Array:
	return [[T.hit, 0]]

## 咆哮の声（登場・覚醒と同じ素材）。声の山は約1.3秒で、飛び立ちに少し重なる
func sounds() -> Array:
	return [[T.roar, "dragon_roar", -3.0]]

## 着地の点（ワールド）と、ホームからのずれ（ステージの画素）
func _land_w() -> Vector2:
	return Vector2(targets[0]) + Vector2(LAND_DX * 0.5, 0)

func _land_off() -> Vector2:
	return (_land_w() - home) * 2.0

func body_at(t: float) -> Dictionary:
	var s := {"pose": 0, "off": Vector2.ZERO, "scale": Vector2.ONE, "ghosts": []}
	if t < 0.0:
		return s
	var land := _land_off()
	if t < T.roar:
		s.pose = 1
	elif t < T.roar_end:
		s.pose = 4
		s.scale = Vector2(1.0, 1.0 + 0.05 * sin(RBMHeroFx.ramp(t, T.roar, T.roar_end) * PI))
	elif t < T.crouch:
		s.pose = 1
	elif t < T.takeoff:
		var q := RBMHeroFx.ramp(t, T.crouch, T.takeoff)
		s.pose = 10
		s.scale = Vector2(1.0 + 0.06 * q, 1.0 - 0.1 * q)
	elif t < T.gone:
		var q := RBMHeroFx.ramp(t, T.takeoff, T.gone)
		s.pose = 9
		s.off = Vector2(land.x * 0.18 * q, -760.0 * q * q)
		s.scale = Vector2(0.96, 1.06)
		for k in range(3):
			var qq := maxf(0.0, q - 0.07 * (k + 1))
			s.ghosts.append({"pose": 9, "off": Vector2(land.x * 0.18 * qq, -760.0 * qq * qq), "a": 0.24 - 0.07 * k})
	elif t < T.dive:
		s.hidden = true
	elif t < T.hit:
		var q := RBMHeroFx.ramp(t, T.dive, T.hit)
		var y := -820.0 * (1.0 - q * q)
		s.pose = 10
		s.off = land + Vector2(26.0 * (1.0 - q), y)
		s.scale = Vector2(0.94, 1.1)
		for k in range(4):
			var qq := maxf(0.0, q - 0.09 * (k + 1))
			s.ghosts.append({"pose": 10, "off": land + Vector2(26.0 * (1.0 - qq), -820.0 * (1.0 - qq * qq)), "a": 0.3 - 0.06 * k})
	elif t < T.leap:
		var q := RBMHeroFx.ramp(t, T.hit, T.hit + 0.24)
		s.pose = 10
		s.off = land
		s.scale = Vector2(1.12 - 0.12 * q, 0.86 + 0.14 * q)
	elif t < T.land:
		var q := RBMHeroFx.ramp(t, T.leap, T.land)
		s.pose = 9
		s.off = land * (1.0 - q) + Vector2(0, -150.0 * 4.0 * q * (1.0 - q))
		for k in range(2):
			var qq := maxf(0.0, q - 0.08 * (k + 1))
			s.ghosts.append({"pose": 9, "off": land * (1.0 - qq) + Vector2(0, -150.0 * 4.0 * qq * (1.0 - qq)), "a": 0.18 - 0.06 * k})
	elif t < T.land + 0.26:
		var q := RBMHeroFx.ramp(t, T.land, T.land + 0.26)
		s.pose = 10
		s.scale = Vector2(1.06 - 0.06 * q, 0.9 + 0.1 * q)
	return s


const DUST := ["#2c2830", "#38333c", "#45404a", "#524c58", "#605a66", "#6e6874", "#7c7682", "#8a8490"]

var dust_a: ColorRect
var dust_b: ColorRect

func _build() -> void:
	b_back = batch(back)
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#1a1418", "#2e2228", str(ramp8()[3]), str(ramp8()[5])]), "glow_col": col(5), "glow": 0.8})
	ring = ring_quad(back, [str(ramp8()[3]), str(ramp8()[5]), str(ramp8()[6]), "#ffffff"], {"glow_col": col(5), "glow": 0.7})
	dust_a = blast_quad(back, DUST, DUST, {"amp": 18.0, "k": 0.08, "seed": 3.3, "glow": 0.0, "glow_r": 10.0})
	b_norm = batch(mid, false)
	dust_b = blast_quad(mid, DUST, DUST, {"amp": 20.0, "k": 0.07, "seed": 5.1, "glow": 0.0, "glow_r": 10.0})
	blast = blast_quad(mid, ramp8(), ramp8(), {"amp": 20.0, "k": 0.09, "seed": 2.2, "glow": 0.9, "glow_col": RBMHeroFx.v3(col(5)), "glow_r": 30.0})
	b_front = batch(front)

## 砂煙: 大きな玉を、時間とともに外側から溶かし、透かして消す
func _show_dust(q: ColorRect, center: Vector2, a: float, life: float, rx: float, seed_: int) -> void:
	if a < 0.0 or a > life:
		q.visible = false
		return
	var data := blobs(center, a * 0.6, 12, seed_, rx, rx * 0.16, rx * 0.16, rx * 0.12, 0.1, 0.0, 6.0)
	show_blast(q, data, a, {"flow": a * 0.2, "cool": 0.0, "erode": RBMHeroFx.ramp(a, life * 0.3, life), "fade": (1.0 - RBMHeroFx.ramp(a, life * 0.4, life)) * 0.6, "erode_noise": 0.6, "tone_cap": 0.7})

func _step(t: float) -> void:
	for b in [b_back, b_front, b_norm]:
		(b as RBMHeroFxBatch).reset()
	var land := _land_w()
	var target := target_chest(0)
	var c5 := col(5)
	var c6 := col(6)
	var c7 := col(7)
	# 溜め: 足元へ風が集まる
	var crouch := RBMHeroFx.env(t, T.crouch, T.crouch + 0.08, T.takeoff, T.takeoff + 0.1)
	if crouch > 0.0:
		inward(b_front, home + Vector2(0, -50), t, 16, 5, 30.0, 90.0, 1.2, Color(c6, 0.7), crouch * 0.6, 2.0)
	# 飛び立ち: 地面に風の輪、砂煙、舞い上がる風の筋
	var ta := t - T.takeoff
	if ta >= 0.0 and ta < 0.9:
		circle_line(b_back, home, 10.0 + 150.0 * RBMHeroFx.burst(ta, 6.0), 2.4 * (1.0 - ta / 0.9), Color(c6, 0.8 * (1.0 - ta / 0.9)), 40, 0.28)
		circle_line(b_back, home, 6.0 + 100.0 * RBMHeroFx.burst(ta, 7.0), 1.6 * (1.0 - ta / 0.9), Color(c7, 0.6 * (1.0 - ta / 0.9)), 36, 0.28)
		for i in range(16):
			var q := RBMHeroFx.ramp(ta, 0.0, 0.35 + 0.2 * RBMHeroFx.r(i, 3))
			var x := home.x + (RBMHeroFx.r(i, 4) - 0.5) * 120.0
			var y0 := home.y - 10.0 - q * 260.0
			b_front.streak(Vector2(x, y0 + 40.0), Vector2(x, y0), 1.2, Color(c6, 0.6 * (1.0 - q)), Color(c6, 0.0))
	var la := t - T.leap
	if ta >= 0.0 and ta < 0.9:
		_show_dust(dust_a, home + Vector2(0, -6), ta, 0.9, 80.0, 21)
	elif la >= 0.0:
		_show_dust(dust_a, land + Vector2(0, -6), la, 0.7, 60.0, 31)
	else:
		dust_a.visible = false
	# 空にいる間: 相手の足元に影が落ちて大きくなる、落ちてくる所を示す風の線、上空で光が瞬く
	var shadow := RBMHeroFx.ramp(t, T.gone + 0.04, T.hit) * (1.0 - RBMHeroFx.ramp(t, T.hit, T.hit + 0.05))
	if shadow > 0.0:
		var sw := lerpf(10.0, 64.0, shadow * shadow)
		disc(b_norm, land + Vector2(0, 1), sw, sw * 0.22, Color(0.04, 0.03, 0.06, 0.25 + 0.5 * shadow))
		disc(b_norm, land + Vector2(0, 1), sw * 0.6, sw * 0.13, Color(0.02, 0.01, 0.03, 0.3 + 0.5 * shadow))
		for i in range(10):
			var q := fmod(t * 1.5 + RBMHeroFx.r(i, 9), 1.0)
			var x := land.x + (RBMHeroFx.r(i, 10) - 0.5) * 90.0
			var y := lerpf(-60.0, land.y - 20.0, q)
			b_front.streak(Vector2(x, y - 30.0), Vector2(x, y), 1.0, Color(c6, 0.35 * shadow * sin(q * PI)), Color(c6, 0.0))
	var glint := RBMHeroFx.env(t, T.dive - 0.16, T.dive - 0.12, T.dive - 0.08, T.dive)
	if glint > 0.0:
		star(b_front, Vector2(land.x + 6.0, 18.0), glint * 0.5, 8, 41, 36.0, 3.0, [c7, c6])
	# 急降下: 細い風の筋が真上から突き刺さる
	if t >= T.dive and t < T.hit:
		var q := RBMHeroFx.ramp(t, T.dive, T.hit)
		var y := land.y - 410.0 * (1.0 - q * q) - 40.0
		for i in range(10):
			var x := land.x + (RBMHeroFx.r(i, 12) - 0.5) * 90.0 + 13.0
			b_front.streak(Vector2(x, y - 140.0), Vector2(x, y + 10.0 * RBMHeroFx.r(i, 13)), 1.2, Color(c7 if i % 2 else c6, 0.6), Color(c6, 0.0))
		view["dim"] = 0.25 * q
	# 着地の一撃
	var ha := t - T.hit
	if ha >= 0.0:
		var flash := 1.0 - RBMHeroFx.ramp(ha, 0.0, 0.1)
		set_post({"flash": 0.55 * flash, "flash_col": Color(1, 1, 0.95)})
		if ha < 0.07:
			set_post({"impact": 0.9, "impact_hi": Vector3(c7.r, c7.g, c7.b), "impact_lo": Vector3(0.06, 0.05, 0.09), "impact_cut": 0.42})
		view["shake"] = hit_shake(ha, 30.0, 95.0, 0.42)
		view["dim"] = 0.25 * (1.0 - RBMHeroFx.ramp(ha, 0.0, 0.6))
		if ha < 1.2:
			show_ring(ring, land, ha, 0.8, 190.0, 7.0, 7.0, 0.02)
			cracks.visible = true
			sp(cracks, {"center": w(land), "reveal": 160.0 * RBMHeroFx.burst(ha, 9.0), "seed": 4.0, "fade": 1.0 - RBMHeroFx.ramp(ha, 0.6, 1.2), "clip_y": w(land).y - 30.0})
		else:
			ring.visible = false
			cracks.visible = false
		if ha < 0.5:
			var data := blobs(land + Vector2(-14, -10), ha, 18, 51, 52.0, 26.0, 20.0, 22.0, 1.2, 0.0, 10.0)
			show_blast(blast, data, ha, {"cool": RBMHeroFx.ramp(ha, 0.1, 0.4) * 0.2, "erode": RBMHeroFx.ramp(ha, 0.08, 0.4), "fade": 1.0 - RBMHeroFx.ramp(ha, 0.2, 0.42), "erode_noise": 0.4, "flow": ha * 0.3})
		else:
			blast.visible = false
		_show_dust(dust_b, land + Vector2(0, -4), ha, 1.2, 130.0, 61)
		rocks(b_front, land, ha, 0.9, 22, 71, 230.0, 5.0, 6.0)
		sparks(b_front, land + Vector2(-8, -10), ha, 0.6, 40, 81, 240.0, c7, c5, -PI * 0.5, PI * 1.3, 260.0, 2.0)
		sparks(b_front, target, ha, 0.45, 22, 91, 160.0, c7, c6, PI, 1.2, 120.0, 1.8)
		star(b_front, target, RBMHeroFx.env(ha, 0.0, 0.02, 0.05, 0.22), 12, 93, 60.0, 5.0, [c7, c6, c5])
	else:
		ring.visible = false
		cracks.visible = false
		blast.visible = false
		dust_b.visible = false
	# 咆哮の輪（動く前）: 声の輪を3つ、空気のゆがみ、小さな揺れ
	var ra := t - (T.roar + 0.06)
	if ra >= 0.0 and ra < 0.9:
		for k in range(3):
			var rk := ra - k * 0.2
			if rk > 0.0 and rk < 0.6:
				var rr := 10.0 + 110.0 * RBMHeroFx.burst(rk, 4.5)
				circle_line(b_front, mouth, rr, 1.8, Color(c6, 0.65 * (1.0 - rk / 0.6)), 32, 0.75)
				circle_line(b_front, mouth, rr * 0.7, 1.0, Color(c7, 0.45 * (1.0 - rk / 0.6)), 28, 0.75)
		refract_wave(mouth, ra, 0.75, 130.0, 7.0, 0.009)
		view["shake"] = Vector2(view["shake"]) + Vector2(sin(t * 60.0), cos(t * 52.0)) * 2.0 * (1.0 - ra / 0.9)
		view["dim"] = 0.12 * RBMHeroFx.env(ra, 0.0, 0.12, 0.6, 0.9)
	# 跳んで戻る: 翼の風、着地の小さな揺れ
	if la >= 0.0 and la < 0.45:
		circle_line(b_back, land, 10.0 + 90.0 * RBMHeroFx.burst(la, 5.0), 1.8 * (1.0 - la / 0.45), Color(c6, 0.6 * (1.0 - la / 0.45)), 32, 0.28)
	var ld := t - T.land
	if ld >= 0.0 and ld < 0.6:
		view["shake"] = Vector2(view["shake"]) + hit_shake(ld, 8.0, 90.0, 0.22)
	for b in [b_back, b_front, b_norm]:
		(b as RBMHeroFxBatch).commit()
	ally_hits(t, hits(), 1.6)
	ally_light(0.7 * RBMHeroFx.env(t, T.hit - 0.03, T.hit, T.hit + 0.1, T.hit + 0.5), c6, 0.0)
