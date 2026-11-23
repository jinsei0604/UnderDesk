extends RBMGentlemanFxBase
## 異形紳士の覚醒「紅の眼差し」（2026-11-23 作り直し。ユーザー「覚醒モーションは全然だめ。根本的に変えてほしい」）。
## 前の案（エフェクトを盛る「異形の目覚め」「帽子の下の闇」、静かな「決闘の手袋」）とは見せ方そのものを変え、画面の色と影絵で見せる。
## 2026-11-23 ユーザー「ズームはいらない。月が出ているところをもう少し長く」→ カメラは引きのまま、月の場面を長く。
## 1 帽子のつばに手をかけ、うつむく → 世界が暗くなり紳士だけが残る。赤い目がゆっくり開き、横に細い光が伸びる（心臓の音が二度）→ 目が燃える
## 2 深紅の空と大きな月を背に、黒い影になった紳士がコートを翻す（四人も影）→ 影のまま二丁を抜いて両腕を広げる。銃口が順に閃く
## 3 覚醒: 色が戻り、二丁を四人へ向けて構えた瞬間、深紅の墨の爆発・衝撃の輪・火花 → 構えを解いて二丁を下げる
## 大時計・鐘（給仕長）、画面を裂く（給仕長・ヒーロー）、時間を止める（紳士の跳弾）は使わない。
## 本体の絵は今ある要所の絵だけ（pose_keys）。音は tools/gentleman/audio/build_v2.mjs の awaken（下の T の時刻で作る）。

## 顔に寄るのは、覚醒の直前の攻撃のダメージの数字が消えてから（寄りで数字が大きく映らないように）
const T := {"bow": 0.15, "close": 0.4, "beat1": 0.55, "eyes": 0.68, "beat2": 0.95, "flare": 1.22, "red": 1.37, "draw": 2.25, "spread": 2.4, "glint1": 2.46, "glint2": 2.56, "awaken": 3.1, "hold": 4.05, "lower": 4.3, "end": 5.1}
## 目（hat_reach_15。足元から、絵の画素）・月の中心
const EYE_L := Vector2(-8, -79)
const EYE_R := Vector2(-4, -80)
const MOON := Vector2(18, -78)
const MOON_R := 64.0
const SKY := Color(0.42, 0.02, 0.05)

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var blast: ColorRect
var cracks: ColorRect
var rings: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.awaken

func pose_keys() -> Array:
	return [[0.0, "hat_reach_00"], [T.bow, "hat_reach_15"], [T.red, "legacy_coat"], [T.draw, "dual_open_raise_07"], [T.spread, "dual_open_raise_15"],
		[T.awaken, "dual_forward_raise_15"], [T.hold, "dual_forward_raise_08"], [T.lower, "legacy_dual_idle"]]

func _build() -> void:
	b_back = batch(back, false)
	b_back_add = batch(back)
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#120308", "#7a1026", "#ff5a6a", "#fff0f2"]), "seed": 8.2, "squash": .3, "line_w": .05, "glow_col": Vector3(1., .2, .3), "glow": .6})
	blast = blast_quad(back, CRIMSON_INK, INK_SMOKE, {"amp": 24., "k": .06, "seed": 4.4, "glow": .7, "glow_col": Vector3(.95, .15, .25), "glow_r": 40.})
	b_mid = batch(mid, false)
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if i != 1 else RBMHeroFx.A4_DARK, {"squash": .3, "breakup": .45, "seed": 1.0 + i * 1.9, "glow": .5, "glow_col": Vector3(.95, .15, .25)}))
	b_add = batch(front)
	b_front = batch(front, false)

func _disc(b: RBMHeroFxBatch, c: Vector2, r: float, col_in: Color, col_out: Color, n: int = 40) -> void:
	for i in range(n):
		var p0 := c + Vector2.from_angle(TAU * i / n) * r
		var p1 := c + Vector2.from_angle(TAU * (i + 1) / n) * r
		b.tri(c, p0, p1, col_in, col_out, col_out)

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_mid.reset(); b_add.reset(); b_front.reset()
	var f := foot
	var ch := chest()
	var a := t - T.awaken
	# --- 暗さ: 目が開く間は真っ暗、深紅の空の間は空が深紅（月を背に影絵）
	var red_shot := t >= T.red and t < T.awaken
	if red_shot:
		view["dim"] = 0.92
		view["dim_col"] = SKY
	else:
		view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.bow, 0.2], [T.close + 0.25, 0.9], [T.red - 0.01, 0.92], [T.awaken, 0.6], [T.awaken + 0.06, 0.38], [T.hold, 0.28], [T.end - 0.4, 0.06], [T.end, 0.0]])
		view["dim_col"] = Color(0.01, 0.0, 0.015)
	set_post({"vig": 0.2 + 0.45 * RBMHeroFx.env(t, T.bow, T.close, T.awaken, T.end), "vig_col": Vector3(.06, .0, .01), "vig_r": .26})
	# --- 2 顔の寄り: 赤い目がゆっくり開き、横に細い光が伸びる → 燃える
	var open := RBMHeroFx.env(t, T.eyes, T.eyes + 0.45, T.red - 0.02, T.red)
	if open > 0.0:
		var burn := 1.0 + 0.8 * RBMHeroFx.env(t, T.flare - 0.04, T.flare, T.flare + 0.06, T.red)
		for e in [EYE_L, EYE_R]:
			var p: Vector2 = f + Vector2(e) * UNIT
			RBMHeroRooftop.glow(b_add, p, 5.0 * open * burn, Color(RED, 0.5 * open))
			RBMHeroRooftop.glow(b_add, p, 1.6 * open * burn, Color(1.0, 0.75, 0.7, open))
		# 横に細く伸びる光（目の高さに一本）
		var y := (f + EYE_L * UNIT).y
		var cx := (f + (EYE_L + EYE_R) * 0.5 * UNIT).x
		var reach := 46.0 * open * burn
		b_add.line(Vector2(cx - reach, y), Vector2(cx, y), 0.5 * burn, Color(RED, 0.0), Color(ROSE, 0.8 * open))
		b_add.line(Vector2(cx, y), Vector2(cx + reach, y), 0.5 * burn, Color(ROSE, 0.8 * open), Color(RED, 0.0))
	view["hero"]["lit"] = 0.35 * RBMHeroFx.env(t, T.eyes, T.flare, T.flare + 0.05, T.red)
	view["hero"]["lit_col"] = RED
	if t >= T.flare and t < T.flare + 0.08:
		set_post({"flash": 0.05})
	# --- 3 深紅の空: 大きな月を背に、黒い影の紳士がコートを翻す
	if red_shot:
		var k := RBMHeroFx.ramp(t, T.red, T.red + 0.06)
		var m := f + MOON * UNIT + Vector2(0, -4)
		_disc(b_back, m, MOON_R + 10.0, Color(0.85, 0.3, 0.32, 0.25 * k), Color(0.6, 0.05, 0.08, 0.0))
		_disc(b_back, m, MOON_R, Color(1.0, 0.9, 0.88, k), Color(0.96, 0.78, 0.76, k))
		view["hero"]["flash"] = 1.0
		view["hero"]["flash_col"] = Color(0.02, 0.0, 0.02)
		# 止まったように舞う花びら（黒い影）
		for i in range(26):
			var p := m + Vector2(-150.0 + 300.0 * RBMHeroFx.r(i, 91), -90.0 + 170.0 * RBMHeroFx.r(i, 92)) + Vector2(-12.0 * (t - T.red), 6.0 * (t - T.red))
			b_front.dot_px(p, 2.0, Color(0.05, 0.0, 0.02, k))
		view["shake"] += hit_shake(t - T.red, 5.0, 60.0, 0.3)
	# --- 4 胸の寄り: 二丁を抜いて広げる。銃口が順に閃く
	for g in [[T.glint1, "near"], [T.glint2, "far"]]:
		var ga: float = t - float(g[0])
		if ga >= 0.0 and ga < 0.2:
			var gun := gun_at("dual_open_raise_15", str(g[1]))
			if not gun.is_empty():
				star(b_add, Vector2(gun.p) + Vector2(gun.d) * 1.5, 1.0 - ga / 0.2, 4, 51, 9.0, 0.8, [Color(PALE, 1.0), Color(ROSE, 0.6)])
	# --- 5 覚醒: 構えた瞬間の深紅の墨の爆発・衝撃の輪・割れ目・火花
	var bfin := 1.0 - RBMHeroFx.ramp(a, 0.35, 0.9)
	blast.visible = a >= 0.0 and bfin > 0.0
	if blast.visible:
		var c := ch + Vector2(4, -4)
		show_blast(blast, blobs(c, a, 22, 47, 110.0, 70.0, 32.0, 40.0, .5, .45, 8.0), a, {"flow": a * .3, "cool": .03 + RBMHeroFx.ramp(a, .15, .9) * .18, "erode": RBMHeroFx.ramp(a, .15, .85), "fade": bfin, "erode_noise": .5,
			"polar": 1.0, "detail": .7, "amp": 24.0, "radial_heat": .4, "heat_center": w(c), "heat_radius": 150.0 * RBMHeroFx.burst(a, 7.0), "erode_radial": 90.0, "tone_cap": 1.0})
	cracks.visible = a >= 0.0 and a < 2.0
	if cracks.visible:
		sp(cracks, {"center": w(f + Vector2(0, 1)), "reveal": 12.0 + 90.0 * RBMHeroFx.burst(a, 7.0), "fade": 1.0 - RBMHeroFx.ramp(a, 1.1, 2.0), "glow": 0.3 + 0.6 * (1.0 - RBMHeroFx.ramp(a, 0.0, 1.0))})
	if a >= 0.0:
		show_ring(rings[0], f + Vector2(0, -2), a, 0.7, 300.0, 8.0, 5.5, 0.03)
		show_ring(rings[1], f + Vector2(0, -2), a - 0.07, 0.75, 230.0, 5.0, 5.0, 0.0)
		show_ring(rings[2], ch, a - 0.03, 0.5, 130.0, 4.0, 6.5, 0.0)
		refract_wave(ch, a, 0.7, 400.0, 4.8, 0.04)
		sparks(b_add, ch, a, 1.0, 150, 61, 700.0, PALE, RED, 0.0, TAU, 160.0, 2.0)
		set_post({"flash": 0.07 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.06)), "chroma": 0.006 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3))})
		view["shake"] += hit_shake(a, 13.0, 75.0, 0.5)
		view["hero"]["flash"] = 0.3 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.14))
		view["hero"]["flash_col"] = ROSE
		ally_light(RBMHeroFx.env(a, 0.0, 0.04, 0.25, 0.7), RED, -1.0)
		view["hero"]["lit"] = maxf(float(view["hero"].get("lit", 0.0)), 0.4 * RBMHeroFx.env(a, 0.1, 0.3, T.hold - T.awaken, T.end - T.awaken))
	embers(b_add, Rect2(f.x - 60, f.y - 70, 120, 70), t, 22, 81, 60.0, Color(RED, 1.0), RBMHeroFx.env(t, T.awaken + 0.1, T.awaken + 0.4, T.end - 0.6, T.end), 1.5, 6.0)
	b_back.commit(); b_back_add.commit(); b_mid.commit(); b_add.commit(); b_front.commit()
