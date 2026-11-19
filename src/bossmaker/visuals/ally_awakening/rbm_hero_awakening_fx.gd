extends RBMLionFxBase
## 勇者の覚醒「炎の誓い」（2026-11-19 第2版。表示専用）。時刻は rbm_hero_awakening_seq.gd の T。座標は論理ドット（足元からの相対で決める）。
## 意味: 片膝で剣を頭上に掲げ、足元から立ちのぼる火の粉を剣先へ集める（力をためる）→ 立ち上がって剣を顔の前に立てる（誓い）と、
## 刃に炎が灯る → 解放: 背後から炎が噴き上がり、床を炎の輪が走り、火の粉が散る。体が一瞬炎の色に光り、そのあと縁が照らされる。
## 平たい図形（輪の線・三角のトゲ・星形）は使わない。炎は爆炎のシェーダー（採用済みの全体技と同じ消え方）、輪は千切れた衝撃の輪。
## 2026-11-19 ユーザー「全部ボスとのつながりが分かるように」→ 対応するボス「金環の聖獣」の金環（獅子の頭上の金の日蝕の輪。rbm_lion_fx_support.gd と同じ
## eclipse シェーダー・色）を入れた: 片膝で集める火の粉が剣先の上で輪になり、剣を立てると金環が灯り、解放で炎の柱の中で燃え上がる。

const T := {"kneel": 0.25, "oath": 1.45, "release": 1.9, "settle": 3.2, "end": 3.6}
## 剣先・柄（足元からの相対、論理ドット。frames/08＝片膝で剣を頭上、frames/06＝剣を顔の前に立てる）
const TIP_KNEEL := Vector2(0, -50)
const HILT_KNEEL := Vector2(0, -34)
const TIP_OATH := Vector2(8, -51)
const HILT_OATH := Vector2(8, -33)
const EMBER := Color("#ffb347")
const HOT := Color("#fff1c8")
const RED := Color("#e8401c")
## 金環（金環の聖獣と同じ色）。剣先の上（frames/08＝片膝、06＝剣を立てる）
const CORONA_GOLD := ["#4a3412", "#7a5418", "#b07a20", "#e0a83a", "#ffd27a", "#fff1c8"]
const HALO_KNEEL := Vector2(0, -60)
const HALO_OATH := Vector2(7, -63)

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var ring: ColorRect
var pillar: ColorRect
var eclipse: ColorRect
## 炎の柱の色（暗い赤 → 白。柱のシェーダーは6色）
const PILLAR_PAL := ["#5a1a10", "#c84a1c", "#ff8a24", "#ffc25e", "#fff0c4", "#ffffff"]

func _build() -> void:
	b_back = batch(back)
	pillar = quad(back, Rect2(0, 0, 60, 120), "pillar", {"pal": RBMHeroFx.pal(PILLAR_PAL), "seed": 3.3, "glow": .6, "glow_col": Vector3(1., .55, .2)})
	eclipse = pquad(back, Rect2(0, 0, 10, 10), "eclipse", {"pal": RBMHeroFx.pal(CORONA_GOLD), "seed": 2.2})
	ring = ring_quad(back, RBMHeroFx.R_AMBER, {"squash": .3, "breakup": .4, "seed": 1.3, "glow": .5, "glow_col": Vector3(1., .55, .2)})
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var ra := t - T.release
	# 暗さ: ためるほど深く → 解放で明るく → 消える
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [0.9, 0.34], [T.oath, 0.44], [T.release, 0.5], [T.release + 0.3, 0.3], [T.end, 0.0]])
	view["dim_col"] = Color(0.04, 0.02, 0.02)
	var kneel := t >= T.kneel and t < T.oath
	var tip := foot + (TIP_KNEEL if t < T.oath else TIP_OATH)
	# ためる: 足元の小さな火・立ちのぼる火の粉が剣先へ集まる・剣先の光が育つ
	var charge := RBMHeroFx.ramp(t, T.kneel, T.oath) * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.05))
	if charge > 0.0:
		_gather(tip, t, charge)
		_tongues(t, charge)
		embers(b_add, Rect2(foot.x - 18, foot.y - 14, 36, 12), t, 14, 43, 40.0, Color(EMBER, 1.0), charge, 1.6, 4.0)
		RBMHeroRooftop.glow(b_add, foot + Vector2(0, -1), 14.0 * charge, Color(RED, 0.25 * charge))
	var tip_glow := RBMHeroFx.ramp(t, T.kneel + 0.2, T.oath) * (1.0 - RBMHeroFx.ramp(ra, 0.05, 0.4))
	if tip_glow > 0.0:
		var pulse := 0.85 + 0.15 * sin(t * 24.0)
		RBMHeroRooftop.glow(b_add, tip, (4.0 + 5.0 * tip_glow) * pulse, Color(EMBER, 0.7 * tip_glow))
		RBMHeroRooftop.glow(b_add, tip, 2.0 + 1.5 * tip_glow, Color(HOT, 0.9 * tip_glow))
	# 誓い: 刃に炎が灯る（柄から切っ先へ走る）
	var oa := t - T.oath
	if oa >= 0.0 and ra < 0.6:
		var run := RBMHeroFx.ramp(oa, 0.0, 0.18)
		var fade := 1.0 - RBMHeroFx.ramp(ra, 0.1, 0.6)
		var hilt := foot + HILT_OATH
		var lit_tip := hilt.lerp(tip, run)
		b_add.streak(hilt, lit_tip, 4.0, Color(EMBER, 0.85 * fade), Color(RED, 0.3 * fade))
		b_add.streak(hilt, lit_tip, 1.6, Color(HOT, fade), Color(EMBER, 0.6 * fade))
		sparks(b_add, lit_tip, fmod(oa, 0.3), 0.3, 6, 51 + int(oa / 0.3), 60.0, HOT, EMBER, -PI * 0.5, 1.2, -30.0, 1.2)
		view["hero"]["lit"] = 0.3 * run * fade
		view["hero"]["lit_col"] = EMBER
	# 解放: 背後から炎が噴き上がる・床を炎の輪が走る・火の粉が散る・体が一瞬炎の色に光る
	# 炎の柱（地面から天へ。細く始まって一気に太り、細りながら消える）
	var pf := 1.0 - RBMHeroFx.ramp(ra, 0.45, 0.85)
	pillar.visible = ra >= 0.0 and pf > 0.0
	if pillar.visible:
		pillar.position = Vector2(foot.x - 30.0, foot.y - 118.0)
		pillar.size = Vector2(60, 120)
		sp(pillar, {"width": lerpf(.06, .62, RBMHeroFx.burst(ra, 14.0)) * (1.0 - .55 * RBMHeroFx.ramp(ra, .2, .85)), "flow": ra * 4.0, "fade": pf, "flare": .8})
	if ra >= 0.0:
		show_ring(ring, foot + Vector2(0, -1), ra, 0.55, 64.0, 4.0, 6.0, 0.0)
		sparks(b_add, foot + Vector2(0, -30), ra, 0.8, 48, 71, 230.0, HOT, EMBER, -PI * 0.5, PI * 1.5, 160.0, 1.4)
		sparks(b_add, tip, ra, 0.5, 18, 73, 160.0, Color.WHITE, EMBER, -PI * 0.5, PI * 0.8, 120.0, 1.2)
		embers(b_add, Rect2(foot.x - 24, foot.y - 70, 48, 64), t, 20, 75, 50.0, Color(EMBER, 1.0), 1.0 - RBMHeroFx.ramp(ra, 0.6, 1.5), 1.6, 5.0)
		view["hero"]["flash"] = 0.75 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.22))
		view["hero"]["flash_col"] = HOT
		view["hero"]["lit"] = maxf(float(view["hero"].get("lit", 0.0)), 0.45 * (1.0 - RBMHeroFx.ramp(ra, 0.2, 1.2)))
		view["hero"]["lit_col"] = EMBER
		set_post({"flash": 0.16 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.1))})
	_halo(t, ra)
	b_back.commit(); b_add.commit(); b_front.commit()

## 金環の聖獣の金環: 片膝で集めた火の粉が剣先の上で淡い輪になり → 剣を立てると灯り、光冠が伸びる → 解放で燃え上がり、炎の柱と一緒に消える
func _halo(t: float, ra: float) -> void:
	var form := RBMHeroFx.ramp(t, T.kneel + 0.4, T.oath)
	var lit := RBMHeroFx.ramp(t, T.oath + 0.1, T.oath + 0.3)
	var flare := RBMHeroFx.env(ra, 0.0, 0.05, 0.3, 0.75) if ra >= 0.0 else 0.0
	var on := (0.35 * form + 0.65 * lit) * (1.0 - RBMHeroFx.ramp(ra, 0.5, 0.95))
	if on <= 0.01:
		eclipse.visible = false
		return
	var c := foot + (HALO_KNEEL if t < T.oath else HALO_OATH)
	show_eclipse(eclipse, c, 6.0 + 2.0 * lit + 1.0 * flare, 4.0 + 6.0 * lit + 3.0 * flare, {"flow": t * 1.2, "power": 0.5 + 0.4 * lit + 0.3 * flare, "fade": on,
		"sun_fill": 1.0, "moon_k": 0.76, "dread": 0.0, "rim": 1.0, "sun_col": Vector3(1.0, 0.86, 0.5)})

## 立ちのぼる火の粉が、床から弧を描いて剣先へ吸い込まれる（短い尾の粒。長い直線にしない）
func _gather(tip: Vector2, t: float, power: float) -> void:
	for i in range(20):
		var q := fmod(t * (0.8 + 0.5 * RBMHeroFx.r(i, 81)) + RBMHeroFx.r(i, 82), 1.0)
		var a0 := RBMHeroFx.r(i, 83) * TAU
		var start := foot + Vector2(cos(a0) * 24.0, -1.0 + sin(a0) * 5.0)
		var ctrl := start.lerp(tip, 0.45) + Vector2(cos(a0 + 1.6) * 16.0, -4.0)
		var e := q * q * (3.0 - 2.0 * q)
		var e2 := maxf(0.0, e - 0.08)
		var p := start.lerp(ctrl, e).lerp(ctrl.lerp(tip, e), e)
		var p2 := start.lerp(ctrl, e2).lerp(ctrl.lerp(tip, e2), e2)
		var a := sin(q * PI) * power
		b_add.streak(p2, p, 1.6, Color(EMBER, 0.9 * a), Color(RED, 0.0))
		b_add.dot_px(p, 1.4, Color(HOT, a))

## 足元で小さな炎がゆらめく（柔らかい光を縦に重ねた炎。先の尖った線は破片に見えたので使わない）
func _tongues(t: float, power: float) -> void:
	for i in range(10):
		var a0 := RBMHeroFx.r(i, 91) * TAU
		var p := foot + Vector2(cos(a0) * (10.0 + 8.0 * RBMHeroFx.r(i, 92)), sin(a0) * 3.0)
		var flick := 0.5 + 0.5 * sin(t * (11.0 + 5.0 * RBMHeroFx.r(i, 93)) + float(i) * 1.7)
		var h := (3.0 + 5.0 * flick) * power
		if h < 1.0:
			continue
		var sway := sin(t * 6.0 + float(i)) * 1.2
		for k in range(3):
			var u := float(k) / 3.0
			var q := p + Vector2(sway * u, -h * u)
			RBMHeroRooftop.glow(b_add, q, (2.4 - 1.4 * u) * (0.7 + 0.3 * power), Color(RED.lerp(EMBER, u), 0.45 * power * (1.0 - 0.4 * u)))
		RBMHeroRooftop.glow(b_add, p + Vector2(0, -1), 1.2, Color(HOT, 0.6 * power))
