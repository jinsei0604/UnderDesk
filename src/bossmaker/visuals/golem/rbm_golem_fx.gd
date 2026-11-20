class_name RBMGolemFx
extends RBMHeroFxBase
## ゴーレムの技のエフェクト（2026-11-20 強化。表示専用。戦闘の状態・乱数には触れない）。
## 2026-11-20 ユーザー「ゴーレムは動きはいいんだけどエフェクトが弱いからその部分お願い」→ 動き（ポーズ・移動・時刻）は今のまま、
## エフェクトだけをヒーロー・聖獣と同じ部品（RBMHeroFxBase の爆炎・衝撃の輪・地割れ・岩・粒・屈折）で描き直す。
## 前の版の平たい圧力の輪（四角い粒の輪）・のっぺりした灰色の岩の板は使わない。
## mode: "punch"（単体の岩拳）・"slam"（全体の地割れ）・"buff"・"heal"（支援）。時刻は各つなぎ（rbm_golem_*.gd）と同じ。
## 座標は 640×360 の論理ドット（ステージの半分）。

## 石の土煙（暗い紫の石 → 明るい砂ぼこり）
const DUST := ["#5a4e56", "#6e6068", "#84747a", "#9a8a8a", "#b2a29c", "#c8b8ae", "#ded0c4", "#f4ecdf"]
const DUST_DARK := ["#4a4048", "#584c54", "#685a62", "#7a6c72", "#8e8084", "#a29496", "#b8aaa8", "#ccc0ba"]
const RING_DUST := ["#3a3444", "#7a7080", "#c8c0c4", "#ffffff"]
const STONE_LIT := Color("#8a7f98")
const STONE_DARK := Color("#2c2638")
const PALE := Color("#fff4e0")

var mode := "punch"
## 色（技の属性の色。支援は強化の赤・回復の緑）
var accent := Color("b7bbc2")
## 単体: 拳が当たる所・相手の足元
var contact := Vector2.ZERO
var target_foot := Vector2.ZERO
## 全体: 叩きつける所・両手が地面に着く所・四人の中心（地割れが噴き出す所）・地割れの道
var slam_center := Vector2.ZERO
var contacts: Array = []
var center := Vector2.ZERO
var route: PackedVector2Array = PackedVector2Array()
## 時刻（つなぎの値をそのまま受け取る）
var hit_time := 0.88
var slam_time := 0.72
var travel := Vector2(0.82, 1.50)
var erupt_time := 1.52
## 単体の重い足取り: 踏みしめた時刻と足元 [[秒, 足元（論理ドット）], ...]
var steps: Array = []

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var cracks_a: ColorRect
var cracks_b: ColorRect
var blast: ColorRect
var blast2: ColorRect
## 単体で相手の足元に上がる砂ぼこり（相手の後ろに置く）
var blast_back: ColorRect
var rings: Array = []

func _build() -> void:
	var glow_col := RBMHeroFx.v3(accent)
	b_back = batch(back, false)
	b_back_add = batch(back)
	blast_back = blast_quad(back, DUST, DUST_DARK, {"amp": 18., "k": .08, "seed": 7.7, "glow": .2, "glow_col": glow_col, "glow_r": 22.})
	# 割れ目の色（真ん中が白い星形に見えないよう、いちばん明るい色も石の色に）
	cracks_a = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#120e16", "#2e2636", "#4a3e54", accent.darkened(0.15).to_html(false)]), "seed": 3.7, "squash": .3, "line_w": .06, "glow_col": glow_col, "glow": .3})
	cracks_b = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#120e16", "#2e2636", "#4a3e54", accent.darkened(0.15).to_html(false)]), "seed": 6.1, "squash": .32, "line_w": .06, "glow_col": glow_col, "glow": .3})
	blast = blast_quad(front, DUST, DUST_DARK, {"amp": 20., "k": .07, "seed": 2.2, "glow": .25, "glow_col": glow_col, "glow_r": 26.})
	blast2 = blast_quad(front, DUST, DUST_DARK, {"amp": 18., "k": .08, "seed": 5.5, "glow": .2, "glow_col": glow_col, "glow_r": 22.})
	for i in range(3):
		rings.append(ring_quad(front, RING_DUST, {"squash": .32, "breakup": .55, "seed": 1.0 + i * 2.1, "glow": .45, "glow_col": glow_col}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_add.reset(); b_front.reset()
	match mode:
		"punch": _punch(t)
		"slam": _slam(t)
		_: _support(t)
	b_back.commit(); b_back_add.commit(); b_add.commit(); b_front.commit()

## 単体（2026-11-20 作り直し。ゴーレムは相手の所まで歩かない）: 踏みしめた所の土煙 → 地面を殴った所の衝撃（土煙・輪・割れ目）
## → 割れ目が地面を走って相手の足元へ（先で土煙と小石が弾ける）→ 相手の足元から岩が突き上がる（大きな岩の塊・砂ぼこり・割れ目・輪・火花）
func _punch(t: float) -> void:
	# 踏みしめるたびに足元から土煙が左右へ広がり、小石が跳ねる
	for k in range(steps.size()):
		var sa := t - float(steps[k][0])
		if sa < 0.0 or sa > 0.7:
			continue
		var p: Vector2 = steps[k][1]
		var q := RBMHeroFx.burst(sa, 6.0)
		var f := 1.0 - RBMHeroFx.ramp(sa, 0.15, 0.7)
		for side in [-1.0, 1.0]:
			for j in range(3):
				RBMHeroRooftop.glow(b_back, p + Vector2(side * (10.0 + 22.0 * q + 6.0 * j), -2.0 - 3.0 * j * q), 4.0 + 5.0 * q, Color(0.62, 0.55, 0.52, 0.42 * f))
		rocks(b_front, p, sa, 0.45, 4, 13 + k, 60.0, 1.2, 1.0)
	var s := t - slam_time
	if s < 0.0:
		return
	# 地面を殴った所: 土煙・輪・割れ目・小石
	if s < 0.1:
		RBMHeroRooftop.glow(b_add, slam_center + Vector2(0, -3), 8.0 + 8.0 * (1.0 - s / 0.1), Color(accent, 0.45 * (1.0 - s / 0.1)))
	show_ring(rings[1], slam_center, s, 0.45, 70.0, 5.0, 6.5, 0.02)
	refract_wave(slam_center, s, 0.45, 140.0, 6.0, 0.025)
	cracks_b.visible = s < 1.6
	if cracks_b.visible:
		sp(cracks_b, {"center": w(slam_center + Vector2(0, 1)), "reveal": 8.0 + 26.0 * RBMHeroFx.burst(s, 8.0), "fade": 1.0 - RBMHeroFx.ramp(s, 1.0, 1.6), "glow": 0.2 + 0.4 * (1.0 - RBMHeroFx.ramp(s, 0.0, 0.6))})
	rocks(b_front, slam_center, s, 0.55, 8, 23, 90.0, 1.4, 1.0)
	var bf := 1.0 - RBMHeroFx.ramp(s, 0.25, 0.65)
	blast2.visible = bf > 0.0
	if blast2.visible:
		show_blast(blast2, blobs(slam_center + Vector2(0, -3), s, 8, 61, 30.0, 8.0, 9.0, 10.0, .3, .5, 9.0), s, {"flow": s * .5, "cool": .05 + RBMHeroFx.ramp(s, 0.0, .5) * .25, "erode": RBMHeroFx.ramp(s, .15, .6), "fade": bf * 0.6, "erode_noise": .6, "detail": .7, "amp": 14.0, "tone_cap": 1.0})
	# 割れ目が地面を走る（殴った所 → 相手の足元。ぎざぎざの線、先で土煙と小石）
	var travel_q := RBMHeroFx.ramp(t, slam_time + 0.03, hit_time)
	var fade_line := 1.0 - RBMHeroFx.ramp(t, hit_time + 0.6, hit_time + 1.2)
	var pts := _crack_path(slam_center, target_foot + Vector2(6, 1))
	var n := pts.size()
	var reach := travel_q * float(n - 1)
	for i in range(n - 1):
		if float(i) >= reach:
			break
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var e := a.lerp(b, clampf(reach - float(i), 0.0, 1.0))
		b_back.line(a, e, 2.2, Color(0.08, 0.06, 0.1, 0.9 * fade_line), Color(0.08, 0.06, 0.1, 0.9 * fade_line))
		b_back_add.line(a + Vector2(0, -0.6), e + Vector2(0, -0.6), 0.8, Color(accent, 0.55 * fade_line), Color(accent, 0.55 * fade_line))
	if travel_q > 0.0 and travel_q < 1.0:
		var tip := _crack_at(pts, travel_q)
		RBMHeroRooftop.glow(b_back, tip + Vector2(0, -3), 5.0, Color(0.62, 0.55, 0.52, 0.5))
		RBMHeroRooftop.glow(b_back_add, tip, 4.0, Color(accent, 0.45))
		for k in range(3):
			var age_k := fmod(t * 9.0 + k * 0.33, 1.0) * 0.12
			var v := Vector2((RBMHeroFx.r(k + int(t * 20.0), 5) - 0.5) * 30.0, -30.0 - 20.0 * RBMHeroFx.r(k, 6))
			b_front.dot_px(tip + v * age_k + Vector2(0, 80.0 * age_k * age_k), 1.0, Color(STONE_LIT, 0.9))
	# 相手の足元から岩が突き上がる
	var a := t - hit_time
	if a < 0.0:
		return
	if a < 0.1:
		var k := 1.0 - a / 0.1
		RBMHeroRooftop.glow(b_add, target_foot + Vector2(0, -14), 12.0 + 8.0 * k, Color(PALE, 0.7 * k))
		RBMHeroRooftop.glow(b_add, target_foot + Vector2(0, -14), 22.0 + 8.0 * k, Color(accent, 0.5 * k))
	_boulders(target_foot, a)
	cracks_a.visible = a < 1.6
	if cracks_a.visible:
		sp(cracks_a, {"center": w(target_foot + Vector2(0, 1)), "reveal": 10.0 + 34.0 * RBMHeroFx.burst(a, 8.0), "fade": 1.0 - RBMHeroFx.ramp(a, 0.9, 1.6), "glow": 0.25 + 0.5 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.6))})
	show_ring(rings[0], target_foot + Vector2(0, -1), a, 0.4, 60.0, 3.0, 6.5, 0.025)
	refract_wave(target_foot + Vector2(0, -10), a, 0.45, 140.0, 6.0, 0.03)
	sparks(b_add, target_foot + Vector2(0, -10), a, 0.5, 50, 31, 280.0, PALE, accent, -PI * 0.5, PI * 0.9, 220.0, 1.8)
	shards(b_front, target_foot + Vector2(0, -8), a, 0.7, 8, 33, 150.0, 2.2, STONE_LIT, STONE_LIT.darkened(0.3), 360.0, -PI * 0.5, PI * 0.9)
	var bfin := 1.0 - RBMHeroFx.ramp(a, 0.3, 0.75)
	blast_back.visible = bfin > 0.0
	if blast_back.visible:
		show_blast(blast_back, blobs(target_foot + Vector2(0, -6), a, 10, 41, 30.0, 14.0, 10.0, 16.0, .3, .5, 9.0), a, {"flow": a * .5, "cool": .05 + RBMHeroFx.ramp(a, 0.0, .6) * .25, "erode": RBMHeroFx.ramp(a, .15, .7), "fade": bfin * 0.25, "erode_noise": .6, "detail": .7, "amp": 16.0, "tone_cap": 1.0})

## 突き上がる岩の柱（丸みのある石の塊を縦に積む。尖った棘にしない）: 相手の後ろから一気に突き出て（相手の頭より高く）→ 少し止まり
## → 崩れて沈む。真ん中がいちばん高く、左右は低い。相手の体の左右と頭の上からはみ出して見える。石の色はゴーレムと同じ紫がかった石。
func _boulders(o: Vector2, a: float) -> void:
	var up := RBMHeroFx.burst(a, 14.0) * (1.0 - RBMHeroFx.ramp(a, 0.5, 0.85))
	if up <= 0.01:
		return
	var sink := RBMHeroFx.ramp(a, 0.5, 0.85)
	for col in [[-17.0, 46.0, 9.0], [17.0, 52.0, 9.0], [0.0, 74.0, 11.0]]:
		var x: float = col[0]
		var h: float = float(col[1]) * up
		var r: float = float(col[2]) * (0.75 + 0.25 * up)
		var n := maxi(1, int(h / (r * 1.5)) + 1)
		for k in range(n):
			var y := -4.0 - float(k) * r * 1.5 + 18.0 * sink
			if -y > h + r:
				break
			_rock(b_back, o + Vector2(x + (RBMHeroFx.r(k, int(x) + 50) - 0.5) * 3.0, y), r * (1.0 - 0.08 * k), int(x) + k * 7 + 60)

## 丸みのある石（7角形、頂点ごとに明るさを変える: 上は明るく、下は暗い）
func _rock(b: RBMHeroFxBatch, c: Vector2, r: float, seed_: int) -> void:
	var n := 7
	var pts: Array = []
	for k in range(n):
		var th := TAU * float(k) / float(n) + RBMHeroFx.r(seed_, 1) * 0.6
		pts.append(c + Vector2(cos(th), sin(th) * 0.85) * r * (0.82 + 0.18 * RBMHeroFx.r(seed_ + k, 2)))
	var mid := STONE_LIT.lerp(STONE_DARK, 0.4)
	for k in range(n):
		var p0: Vector2 = pts[k]
		var p1: Vector2 = pts[(k + 1) % n]
		var c0 := STONE_LIT.lightened(0.15) if p0.y < c.y - r * 0.2 else (STONE_DARK if p0.y > c.y + r * 0.2 else mid)
		var c1 := STONE_LIT.lightened(0.15) if p1.y < c.y - r * 0.2 else (STONE_DARK if p1.y > c.y + r * 0.2 else mid)
		b.tri(c, p0, p1, STONE_LIT, c0, c1)

## 割れ目の道（ぎざぎざ。毎回同じ形）
func _crack_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 14
	var side := (b - a).orthogonal().normalized()
	for i in range(n + 1):
		var u := float(i) / float(n)
		var j := 0.0 if i == 0 or i == n else (RBMHeroFx.r(i, 91) - 0.5) * 7.0
		pts.append(a.lerp(b, u) + side * j)
	return pts

func _crack_at(pts: PackedVector2Array, q: float) -> Vector2:
	var f := clampf(q, 0.0, 1.0) * float(pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - float(i))

## 全体の地割れ: 両手で地面を叩く（土煙が噴き上がり、衝撃の輪・割れ目）→ 割れ目が四人へ走る（道に沿って土煙と石が弾ける）
## → 四人の足元から岩が噴き上がる（大きな割れ目・岩・砂ぼこりの爆発・二重の衝撃の輪）
func _slam(t: float) -> void:
	var s := t - slam_time
	if s >= 0.0:
		if s < 0.1:
			RBMHeroRooftop.glow(b_add, slam_center + Vector2(0, -4), 10.0 + 10.0 * (1.0 - s / 0.1), Color(accent, 0.5 * (1.0 - s / 0.1)))
		show_ring(rings[0], slam_center, s, 0.4, 90.0, 3.5, 6.0, 0.02)
		refract_wave(slam_center, s, 0.5, 200.0, 6.0, 0.03)
		cracks_a.visible = s < 3.4
		if cracks_a.visible:
			sp(cracks_a, {"center": w(slam_center + Vector2(0, 1)), "reveal": 10.0 + 40.0 * RBMHeroFx.burst(s, 7.0), "fade": 1.0 - RBMHeroFx.ramp(t, 3.4, 4.0), "glow": 0.2 + 0.4 * (1.0 - RBMHeroFx.ramp(s, 0.0, 0.8))})
		for i in range(contacts.size()):
			var c: Vector2 = contacts[i]
			rocks(b_front, c, s, 0.6, 7, 51 + i, 110.0, 1.6, 1.0)
		var bfin := 1.0 - RBMHeroFx.ramp(s, 0.3, 0.75)
		blast2.visible = bfin > 0.0
		if blast2.visible:
			show_blast(blast2, blobs(slam_center + Vector2(0, -4), s, 12, 61, 50.0, 12.0, 12.0, 16.0, .3, .5, 9.0), s, {"flow": s * .5, "cool": .05 + RBMHeroFx.ramp(s, 0.0, .5) * .25, "erode": RBMHeroFx.ramp(s, .15, .7), "fade": bfin * 0.6, "erode_noise": .6, "detail": .7, "amp": 16.0, "tone_cap": .8})
	# 割れ目が走る間: 割れ目の先で土煙と小石が弾ける
	var tr := RBMHeroFx.ramp(t, travel.x, travel.y)
	if route.size() > 1 and t >= travel.x and t < travel.y + 0.3:
		var tip := _route_point(tr)
		for k in range(3):
			var back_q := maxf(0.0, tr - 0.06 * k)
			var p := _route_point(back_q)
			RBMHeroRooftop.glow(b_back, p + Vector2(0, -3), 4.0 + 3.0 * k, Color(0.42, 0.38, 0.46, 0.45 * (1.0 - 0.3 * k) * (1.0 - RBMHeroFx.ramp(t, travel.y, travel.y + 0.3))))
		RBMHeroRooftop.glow(b_back_add, tip, 6.0, Color(accent, 0.5 * (1.0 - RBMHeroFx.ramp(t, travel.y, travel.y + 0.2))))
		embers(b_add, Rect2(tip.x - 6, tip.y - 8, 12, 8), t, 6, 71, 30.0, accent, 0.8, 1.2, 4.0)
	# 噴き上がり（2026-11-20 単体と同じ形に）: 四人それぞれの足元から岩の柱が突き上がる（奥の相手から順に、少しずつずれて）。
	# 砂ぼこりは足元の低い所だけ（四人を隠さない）。割れ目の真ん中を白い星形にしない。
	var e := t - erupt_time
	if e < 0.0:
		return
	cracks_b.visible = e < 2.5
	if cracks_b.visible:
		sp(cracks_b, {"center": w(center + Vector2(0, 1)), "reveal": 20.0 + 110.0 * RBMHeroFx.burst(e, 6.0), "fade": 1.0 - RBMHeroFx.ramp(t, 3.4, 4.0), "glow": 0.2 + 0.4 * (1.0 - RBMHeroFx.ramp(e, 0.0, 1.0))})
	var order: Array = []
	for i in range(mini(targets.size(), 4)):
		if present[i]:
			order.append(i)
	order.sort_custom(func(x, y): return Vector2(targets[x]).y < Vector2(targets[y]).y)
	for k in range(order.size()):
		var i: int = order[k]
		var tf: Vector2 = targets[i]
		var a := e - 0.05 * k
		if a < 0.0:
			continue
		if a < 0.1:
			RBMHeroRooftop.glow(b_add, tf + Vector2(0, -14), 10.0 + 8.0 * (1.0 - a / 0.1), Color(PALE, 0.6 * (1.0 - a / 0.1)))
			RBMHeroRooftop.glow(b_add, tf + Vector2(0, -14), 20.0 + 8.0 * (1.0 - a / 0.1), Color(accent, 0.45 * (1.0 - a / 0.1)))
		_boulders(tf, a)
		rocks(b_front, tf, a, 0.8, 6, 91 + i, 120.0, 1.8, 2.0)
		sparks(b_add, tf + Vector2(0, -10), a, 0.5, 30, 101 + i, 240.0, PALE, accent, -PI * 0.5, PI * 0.9, 220.0, 1.6)
	var bfin2 := 1.0 - RBMHeroFx.ramp(e, 0.4, 0.95)
	blast.visible = bfin2 > 0.0
	if blast.visible:
		show_blast(blast, blobs(center + Vector2(0, 4), e, 16, 81, 120.0, 18.0, 14.0, 14.0, .3, .5, 8.0), e, {"flow": e * .4, "cool": .05 + RBMHeroFx.ramp(e, 0.0, 1.0) * .25, "erode": RBMHeroFx.ramp(e, .15, .9), "fade": bfin2 * 0.35, "erode_noise": .6,
			"detail": .7, "amp": 16.0, "tone_cap": 1.0})
	show_ring(rings[1], center, e, 0.5, 170.0, 4.0, 5.5, 0.03)
	refract_wave(center, e, 0.7, 300.0, 5.0, 0.035)
	view["shake"] += hit_shake(e, 10.0, 80.0, 0.45)

func _route_point(q: float) -> Vector2:
	var total := 0.0
	for i in range(route.size() - 1):
		total += route[i].distance_to(route[i + 1])
	var left := total * clampf(q, 0.0, 1.0)
	for i in range(route.size() - 1):
		var d := route[i].distance_to(route[i + 1])
		if left <= d:
			return route[i].lerp(route[i + 1], left / maxf(d, 0.01))
		left -= d
	return route[route.size() - 1]

## 支援: 構える間に足元の石が浮き上がり、地面の割れ目が色に光る → 力を込めた瞬間に色の衝撃の輪と光の粒
func _support(t: float) -> void:
	var impact_t := hit_time
	var gather := RBMHeroFx.env(t, 0.4, 0.9, impact_t, impact_t + 0.2)
	var a := t - impact_t
	# 足元の割れ目が光る
	cracks_a.visible = t >= 0.4 and t < 2.8
	if cracks_a.visible:
		sp(cracks_a, {"center": w(foot + Vector2(0, 1)), "reveal": 6.0 + 26.0 * RBMHeroFx.ramp(t, 0.4, impact_t) + 20.0 * RBMHeroFx.burst(maxf(a, 0.0), 7.0) * (1.0 if a >= 0.0 else 0.0),
			"fade": 1.0 - RBMHeroFx.ramp(t, 2.1, 2.8), "glow": 0.4 + 0.4 * RBMHeroFx.env(t, 0.6, impact_t, impact_t + 0.1, 2.2)})
	# 浮き上がる小石（ゆっくり上る）
	for i in range(10):
		var q := RBMHeroFx.ramp(t, 0.45 + 0.05 * i, impact_t + 0.1)
		var p := foot + Vector2((RBMHeroFx.r(i, 21) - 0.5) * 50.0, -2.0 - 30.0 * q * (0.6 + 0.4 * RBMHeroFx.r(i, 22)))
		var f := gather * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.15)) if a >= 0.0 else gather
		if f > 0.0:
			b_front.dot_px(p, 2.0 if i % 3 else 3.0, Color(STONE_LIT, f))
			b_front.dot_px(p + Vector2(1, 1), 1.0, Color(STONE_DARK, f))
	embers(b_add, Rect2(foot.x - 30, foot.y - 70, 60, 70), t, 24, 31, 40.0, accent, gather + RBMHeroFx.env(a, 0.0, 0.05, 0.6, 1.2) * (1.0 if a >= 0.0 else 0.0), 1.6, 8.0)
	RBMHeroRooftop.glow(b_back_add, foot + Vector2(0, -40), 34.0, Color(accent, 0.18 * gather))
	if a >= 0.0:
		# 力を込めた瞬間: 浮いた小石が弾け飛び、色の衝撃の輪と光
		rocks(b_front, foot + Vector2(0, -10), a, 0.6, 10, 41, 120.0, 1.6, 4.0)
		show_ring(rings[0], foot, a, 0.6, 110.0, 6.0, 6.0, 0.02)
		show_ring(rings[1], foot, a - 0.08, 0.6, 80.0, 4.0, 6.0, 0.0)
		if a < 0.12:
			RBMHeroRooftop.glow(b_add, foot + Vector2(0, -40), 30.0 + 14.0 * (1.0 - a / 0.12), Color(accent, 0.45 * (1.0 - a / 0.12)))
		sparks(b_add, foot + Vector2(0, -36), a, 0.7, 40, 43, 200.0, PALE, accent, -PI * 0.5, PI * 1.4, 80.0, 1.6)
