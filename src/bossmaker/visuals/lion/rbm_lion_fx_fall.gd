extends RBMLionFxBase
## 金環の聖獣／日蝕の獅皇の撃破（2026-11-13 ユーザーの案）: 倒れた聖獣の背に金環日食が現れ、その輪が上から両側へ欠けていき、
## 欠けた所から破片がこぼれ落ちる。輪が欠けるのに合わせて聖獣も上から光の粒になってほどける。
## 消えた後には剣が1本、聖獣のいた床に刺さって残る（2026-11-13 ユーザー指定。結果の画面まで残る）。
## 覚醒前: 金の輪 → 最後のひとかけらが光の剣になって床へ刺さる。
## 覚醒後（ユーザー「覚醒後はもっと派手に」）: 大きな日蝕の光冠が一度燃え上がり、欠けていく間も深紅の閃光が脈打つ
## → 最後のひとかけらが消える瞬間に深紅の大爆発（衝撃波・閃光）→ 煙の中から深紅の大剣が空から落ちて床に突き刺さる。
## 時刻は撃破の演出（RBMVictoryPlayer の begin から）の秒。覚醒前は T、覚醒後は TA（tm() で選ぶ）。
## 2026-11-14 ユーザー「ボスの中心に変なマークが出る」: 聖獣のいた所に出る平らな光の丸（飛ぶ剣の先・最後のかけら・刺さる瞬間・覚醒後の爆発の中心）と
## 刺さる所の平らな光の輪、日蝕の中心の1点から出る火花（小さな星に見えた）をやめた。

const T := {"ring": 0.0, "full": 0.45, "wane": 0.70, "melt": 0.95, "last": 2.25, "sword": 2.30, "stab": 2.48, "gone": 2.55, "end": 3.10}
const TA := {"ring": 0.0, "full": 0.40, "flare": 0.55, "wane": 0.85, "melt": 1.05, "last": 2.35, "burst": 2.42, "gone": 2.50,
	"sword": 2.85, "stab": 3.05, "end": 3.75}
## 覚醒後の、欠けていく間の深紅の閃光の間隔（秒）
const PULSE := 0.3
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const RED := Color("#e0402a")
const RED_HOT := Color("#ffb080")
## 覚醒前の光冠（金）。覚醒後は日蝕の深紅（DREAD）へ移す
const CORONA_GOLD := ["#4a3412", "#7a5418", "#b07a20", "#e0a83a", "#ffd27a", "#fff1c8"]
## 覚醒後の大爆発の色（黒 → 深紅 → 橙 → 金 → 白金）
const CRIMSON_FIRE := ["#08060a", "#2a0608", "#5a0c10", "#a01818", "#e0302a", "#ff8a40", "#ffd27a", "#fff1c8"]

## 覚醒後（深紅・大きく・爆発つき）
var awakened := false

var b_back: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_sword: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var eclipse: ColorRect
var blast: ColorRect
var rings: Array = []

func tm() -> Dictionary:
	return TA if awakened else T

func duration() -> float:
	return float(tm().end)

func _build() -> void:
	b_back = batch(back)
	eclipse = pquad(back, Rect2(0, 0, 10, 10), "eclipse", {"pal": RBMHeroFx.pal(CORONA_GOLD), "seed": 6.4})
	if awakened:
		blast = blast_quad(back, CRIMSON_FIRE, CRIMSON_FIRE, {"amp": 30., "k": .05, "seed": 7.3, "glow": .6, "glow_col": Vector3(1., .35, .2), "glow_r": 46.})
	for i in range(4 if awakened else 1):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if awakened else RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .4, "seed": 4.4 + i * 2.3, "glow": .4,
			"glow_col": Vector3(1., .4, .25) if awakened else Vector3(1., .8, .4)}))
	b_glow = batch(front)
	b_sword = batch(front, false)
	b_add = batch(front)

## 輪の中心（聖獣の背の上）
func center() -> Vector2:
	return HOME + Vector2(14, -88 if awakened else -84)

func radius() -> float:
	return 58.0 if awakened else 46.0

## 剣が刺さる所（聖獣のいた床。足元は撃破の時に少し右へずれている）
func sword_tip() -> Vector2:
	return HOME + Vector2(12, 3)

func wane_at(t: float) -> float:
	var u := RBMHeroFx.ramp(t, float(tm().wane), float(tm().last))
	return u * u * (3.0 - 2.0 * u)

func _step(t: float) -> void:
	b_back.reset(); b_glow.reset(); b_sword.reset(); b_add.reset()
	var tt := tm()
	var c := center()
	var r := radius()
	var appear := RBMHeroFx.ramp(t, tt.ring, tt.full)
	var wane := wane_at(t)
	var col := RED if awakened else GOLD
	var hot := RED_HOT if awakened else HOT
	var last := t - float(tt.last)
	# 覚醒後: 光冠が一度燃え上がる
	var flare := 0.0
	if awakened:
		flare = RBMHeroFx.env(t, tt.flare, float(tt.flare) + 0.08, float(tt.flare) + 0.25, float(tt.flare) + 0.7)
	# 金環日食: 太陽の面に一回り小さい月が重なり、輪だけが残る。上から両側へ欠けていく
	var fade := appear * (1.0 - RBMHeroFx.ramp(last, 0.05 if awakened else 0.12, 0.12 if awakened else 0.3))
	if fade > 0.0:
		var corona := (24.0 if awakened else 18.0) + (14.0 if awakened else 10.0) * appear * (1.0 - wane) + 26.0 * flare
		show_eclipse(eclipse, c, r + 4.0 * flare, corona, {"flow": t * (1.1 if awakened else 0.8), "power": 0.6 + 0.4 * appear + 0.5 * flare, "fade": fade, "sun_fill": 1.0,
			"moon_k": 0.84, "wane": wane, "disc_fade": 1.0 - 0.9 * wane, "dread": 1.0 if awakened else 0.0, "rim": 1.0, "sun_col": Vector3(1.0, 0.42, 0.26) if awakened else Vector3(1.0, 0.86, 0.5)})
	else:
		eclipse.visible = false
	if awakened and flare > 0.0:
		var af := t - float(tt.flare)
		# 火花は光冠の縁から外へ（中心の1点から出すと、聖獣の背に小さな星の印が出た: 2026-11-14 ユーザー「ボスの中心に変なマーク」）
		for k in range(12):
			var dir := Vector2.from_angle(TAU * k / 12.0)
			sparks(b_add, c + dir * r, af, 0.7, 8, 71 + k * 3, 360.0, hot, col, dir.angle(), 0.7, 60.0, 2.0)
		refract_wave(c, af, 0.6, 220.0, 6.0, 0.03)
		view["shake"] += hit_shake(af, 9.0, 80.0, 0.4)
	# 欠けた所から破片がこぼれ落ちる（左右の欠けの縁から）
	if t >= tt.wane and t < float(tt.last) + 0.3:
		var ang := wane * PI
		var n_burst := 6 if awakened else 4
		var step := (float(tt.last) - float(tt.wane)) / float(n_burst)
		for side in [-1.0, 1.0]:
			var edge := c + Vector2(sin(ang) * side, -cos(ang)) * (r * 0.92)
			for k in range(n_burst):
				var born := float(tt.wane) + k * step
				shards(b_add, edge, t - born, 0.9, 9 if awakened else 6, 31 + k * 7 + int(side * 3.0), 160.0 if awakened else 120.0, 4.5 if awakened else 3.0, hot, col, 260.0, PI * 0.5, PI * 0.9)
			disc(b_add, edge, 5.0 if awakened else 4.0, Color(hot, 0.7 * (1.0 - RBMHeroFx.ramp(last, 0.0, 0.2))))
			embers(b_add, Rect2(edge.x - 10, edge.y - 6, 20, 12), t, 14 if awakened else 10, 41 + int(side), 40.0, col, 1.0 - RBMHeroFx.ramp(last, 0.0, 0.3), 2.0, 4.0)
		# 覚醒後: 欠けていく間も深紅の閃光が脈打つ（輪の外へ広がる光の輪・小さな揺れ）
		if awakened and t < float(tt.last):
			var pa := fmod(t - float(tt.wane), PULSE)
			var pk := floori((t - float(tt.wane)) / PULSE)
			ring_line(b_add, c, r + 4.0 + 40.0 * RBMHeroFx.burst(pa, 8.0), 2.0, Color(col, 0.6 * (1.0 - pa / PULSE)))
			disc(b_glow, c, r + 18.0, Color(col, 0.10 * (1.0 - pa / PULSE)))
			view["shake"] += hit_shake(pa, 3.0 + 0.4 * pk, 80.0, 0.2)
	# 聖獣がほどけた光の粒が昇る
	var melt := RBMHeroFx.env(t, tt.melt, float(tt.melt) + 0.3, float(tt.gone) - 0.2, float(tt.gone) + 0.5)
	embers(b_add, Rect2(HOME.x - 50, HOME.y - 90, 100, 90), t, 90 if awakened else 70, 51, 160.0, col.lerp(hot, 0.4), melt, 2.0, 8.0)
	var sword_alpha := 0.0
	var sword_pos := sword_tip()
	var s_at := t - float(tt.stab)
	if awakened:
		# 最後のひとかけらが消える瞬間: 深紅の大爆発（衝撃波・閃光・破片）
		var ab := t - float(tt.burst)
		var bf := 1.0 - RBMHeroFx.ramp(ab, 0.5, 1.0)
		blast.visible = ab >= 0.0 and bf > 0.0
		if blast.visible:
			var bc := c + Vector2(0, 36)
			show_blast(blast, blobs(bc, ab, 32, 23, 280.0, 160.0, 84.0, 120.0, .7, 0.0, 7.0), ab, {"flow": ab * .25, "cool": .06 + RBMHeroFx.ramp(ab, .2, .9) * .26, "erode": RBMHeroFx.ramp(ab, .3, .95), "fade": bf,
				"erode_noise": .4, "polar": 1.0, "detail": .55, "amp": 30.0, "radial_heat": .5, "heat_center": w(bc), "heat_radius": 300.0 * RBMHeroFx.burst(ab, 7.0), "erode_radial": 160.0, "tone_cap": .95})
		if ab >= 0.0:
			shards(b_add, c + Vector2(0, 30), ab, 1.1, 60, 81, 620.0, 5.0, hot, col, 200.0)
			sparks(b_add, c + Vector2(0, 30), ab, 0.9, 140, 83, 900.0, hot, col, 0.0, TAU, 160.0, 2.2)
			view["shake"] += hit_shake(ab, 18.0, 70.0, 0.6)
			set_post({"flash": 0.35 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.2)), "flash_col": Vector3(1.0, 0.55, 0.4)})
		for i in range(3):
			show_ring(rings[1 + i], c + Vector2(0, 40), ab - i * 0.08, 0.8, 420.0, 8.0 - i * 2.0, 5.0, 0.03)
		# 煙の中から深紅の大剣が空から落ちて床に突き刺さる
		if t >= tt.sword:
			var u := RBMHeroFx.ramp(t, tt.sword, tt.stab)
			sword_pos = sword_tip() + Vector2(0, -320.0 * (1.0 - u * u))
			sword_alpha = RBMHeroFx.ramp(t, tt.sword, float(tt.sword) + 0.05)
			if t < tt.stab:
				b_add.streak(sword_pos + Vector2(0, -150), sword_pos + Vector2(0, -20), 6.0, Color(col, 0.0), Color(hot, 0.8))
	else:
		# 最後のひとかけらが光の剣になって、聖獣のいた床へ刺さる
		var frag := c + Vector2(0, r * 0.92)
		if t >= tt.sword:
			var u := RBMHeroFx.ramp(t, tt.sword, tt.stab)
			sword_pos = frag.lerp(sword_tip(), u * u)
			sword_alpha = RBMHeroFx.ramp(t, tt.sword, float(tt.sword) + 0.08)
			if t < tt.stab:
				b_add.streak(frag, sword_pos, 4.0, Color(col, 0.0), Color(hot, 0.7))
	# 床に刺さる: 火花・光の輪・小さな揺れ。その後はずっと残って静かに光る（呼吸するように）
	if s_at < 0.0:
		rings[0].visible = false
	if sword_alpha > 0.0:
		var size := 1.6 if awakened else 1.15
		var settle := 0.65 + 0.12 * sin(t * 2.6)
		var aura := settle + (1.4 * (1.0 - RBMHeroFx.ramp(s_at, 0.0, 0.5)) if s_at >= 0.0 else 0.6)
		draw_sword(b_sword, b_glow, sword_pos, -0.07, 52.0 * size, 5.5 * size, aura, sword_alpha, SWORD_CRIMSON if awakened else SWORD_GOLD)
		if s_at >= 0.0:
			sparks(b_add, sword_tip(), s_at, 0.4, 40 if awakened else 26, 91, 300.0 if awakened else 220.0, hot, col, -PI * 0.5, PI * 0.9, 220.0, 1.6)
			show_ring(rings[0], sword_tip(), s_at, 0.5, 160.0 if awakened else 100.0, 4.0, 6.0, 0.0)
			view["shake"] += hit_shake(s_at, 10.0 if awakened else 5.0, 80.0, 0.3)
			# 残る間: 床の淡い光と、ゆっくり昇る火の粉
			disc(b_glow, sword_tip(), 22.0 * size, Color(col, 0.16 * settle), 0.3)
			embers(b_add, Rect2(sword_tip().x - 16 * size, sword_tip().y - 50 * size, 32 * size, 50 * size), t, 12 if awakened else 8, 97, 30.0, Color(hot, 0.9), RBMHeroFx.ramp(s_at, 0.2, 0.6), 1.5, 4.0)
	# 世界: 輪がある間は暗く、消えると晴れる（覚醒後はもっと暗く、深紅の周辺減光）
	if awakened:
		var ab2 := t - float(tt.burst)
		view["dim"] = RBMHeroFx.key(t, [[0.0, 0.35], [tt.full, 0.62], [tt.last, 0.7], [float(tt.burst) + 0.05, 0.12], [float(tt.burst) + 0.5, 0.4], [tt.stab, 0.35], [tt.end, 0.0]])
		view["dim_col"] = Color(0.05, 0.0, 0.02)
		set_post({"vig": 0.55 * appear * (1.0 - RBMHeroFx.ramp(ab2, 0.0, 0.3)) + 0.3 * RBMHeroFx.env(ab2, 0.3, 0.6, 1.2, 1.4), "vig_col": Vector3(.12, .0, .02), "vig_r": .26})
	else:
		view["dim"] = RBMHeroFx.key(t, [[0.0, 0.3], [tt.full, 0.5], [tt.last, 0.55], [tt.gone, 0.25], [tt.end, 0.0]])
		view["dim_col"] = Color(0.03, 0.02, 0.04)
		set_post({"vig": 0.35 * appear * (1.0 - RBMHeroFx.ramp(last, 0.0, 0.4)), "vig_col": Vector3(.02, .01, .0), "vig_r": .28})
	b_back.commit(); b_glow.commit(); b_sword.commit(); b_add.commit()
