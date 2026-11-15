extends RBMLionFxBase
## 金環の聖獣・覚醒前全体「王獣の咆哮」: 構え → 頭を下げて溜める（背に大きな金環が現れて回る）→ 胸を起こして咆哮
## → 金の衝撃波が三重に広がって四人に当たる → 最後に画面いっぱいの金の光の爆発 → 余韻（光の粒が降る）。

const T := {"charge": 0.28, "roar": 1.30, "pulses": [1.34, 1.56, 1.78], "burst": 2.14, "settle": 2.70, "end": 3.70}
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const AMBER := Color("#ff9f29")
const WHITE := Color("#ffffff")

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var rings: Array = []
var blast: ColorRect
var final_share := 0.45

func duration() -> float:
	return T.end

func impact() -> float:
	return T.burst

func hits() -> Array:
	var out := []
	for i in range(4):
		out.append([float(T.pulses[1]) + i * 0.03, i])
	return out

func stops() -> Array:
	return [[T.burst, 0.1]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.charge, 2], [T.roar, 3], [T.settle, 4]]

func move_keys() -> Array:
	return [[0.0, Vector2.ZERO, "snap"], [T.charge, Vector2(4, 0), "snap"], [T.roar, Vector2(4, 0), "snap"], [T.roar + 0.06, Vector2(-6, 0), "out"], [T.settle, Vector2(-6, 0), "snap"], [T.settle + 0.2, Vector2.ZERO, "out"]]

func _build() -> void:
	b_back = batch(back)
	blast = blast_quad(back, GOLDEN, GOLDEN, {"amp": 34., "k": .05, "seed": 6.6, "glow": .6, "glow_col": Vector3(1., .8, .4), "glow_r": 50.})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .35, "seed": 1.0 + i * 2.7, "glow": .5, "glow_col": Vector3(1., .8, .4)}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var mouth := at("top", 3, -23, 23) if t >= T.roar else at("top", 2, -14, 26)
	var party := (target_chest(0) + target_chest(1) + target_chest(2) + target_chest(3)) * 0.25
	# 溜め: 背の大きな金環が現れて回る。光が胸の宝石へ集まる
	var ch := RBMHeroFx.ramp(t, T.charge, T.roar)
	var halo_on := RBMHeroFx.ramp(t, T.charge, T.charge + 0.5) * (1.0 - RBMHeroFx.ramp(t, T.burst, T.burst + 0.4))
	view["dim"] = 0.32 * ch + 0.2 * RBMHeroFx.env(t, T.roar, T.roar + 0.1, T.burst, T.settle)
	view["dim_col"] = Color(0.06, 0.05, 0.02)
	if halo_on > 0.0:
		# 頭の上の金環（今のポーズの頭の上端に合わせる。2026-11-12）
		var hc := at("top", -1, -2, -9)
		var rot := t * 0.8
		var hr := 18.0 + 8.0 * ch
		ring_line(b_add, hc, hr, 2.6, Color(GOLD, 0.9 * halo_on), 0.32)
		ring_line(b_add, hc, hr + 4.0, 1.0, Color(HOT, 0.6 * halo_on), 0.32)
		for i in range(10):
			var a := rot + TAU * i / 10.0
			var p := hc + Vector2(cos(a) * hr, sin(a) * hr * 0.32)
			disc(b_add, p, 1.6 + ch, Color(HOT, 0.9 * halo_on))
		inward(b_add, at("mark", 2), t, 90, 5, 6.0, 120.0, 1.6, GOLD, ch, 2.2)
		embers(b_add, Rect2(HOME.x - 70, HOME.y - 20, 140, 30), t, 30, 7, 80.0, GOLD, ch, 2.0, 6.0)
	view["hero"]["lit"] = 0.6 * ch * (1.0 - RBMHeroFx.ramp(t, T.roar, T.roar + 0.3))
	view["hero"]["lit_col"] = HOT
	# 咆哮: 口から金の衝撃波が三重に広がる。画面の屈折と揺れ
	for i in range(3):
		var at_t: float = T.pulses[i]
		show_ring(rings[i], mouth, t - at_t, 0.9, 420.0, 9.0 - i * 2.0, 4.0, 0.035)
		refract_wave(mouth, t - at_t, 0.8, 440.0, 4.2, 0.03)
		view["shake"] += hit_shake(t - at_t, 6.0 + 3.0 * i, 80.0, 0.3)
	if t >= T.roar and t < T.burst:
		var w := RBMHeroFx.ramp(t, T.roar, T.roar + 0.1)
		for i in range(16):
			var a := PI + (RBMHeroFx.r(i, 31) - 0.5) * 1.6
			var d := fmod(t * 300.0 + RBMHeroFx.r(i, 32) * 300.0, 300.0)
			var p := mouth + Vector2.from_angle(a) * d * Vector2(1.0, 0.6)
			b_add.streak(p + Vector2.from_angle(a) * 26.0, p, 1.6, Color(HOT, 0.6 * w * (1.0 - d / 300.0)), Color(GOLD, 0.0))
	ally_hits(t, [[T.pulses[1], 0], [T.pulses[1] + 0.03, 1], [T.pulses[1] + 0.06, 2], [T.pulses[1] + 0.09, 3]], 0.7)
	# 最後: 四人を包む金の光の爆発（外へ噴き出す炎と同じ描き方を金色で）
	var a := t - T.burst
	var bf := 1.0 - RBMHeroFx.ramp(a, 0.55, 1.0)
	blast.visible = a >= 0.0 and bf > 0.0
	if blast.visible:
		var center := party + Vector2(10, 4)
		var data := blobs(center, a, 44, 13, 380.0, 200.0, 96.0, 110.0, .6, 0.0, 6.0)
		show_blast(blast, data, a, {"flow": a * .22, "cool": .04 + RBMHeroFx.ramp(a, .2, 1.0) * .22, "erode": RBMHeroFx.ramp(a, .32, .98), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .55, "amp": 34.0, "radial_heat": .5, "heat_center": w(center), "heat_radius": 360.0 * RBMHeroFx.burst(a, 6.0), "erode_radial": 200.0, "tone_cap": .95})
		refract_wave(center, a, 0.7, 520.0, 5.0, 0.03)
		sparks(b_add, center, a, 0.9, 140, 41, 900.0, HOT, GOLD, 0.0, TAU, 120.0, 2.2)
		view["shake"] += hit_shake(a, 16.0, 70.0, 0.5)
		ally_light(RBMHeroFx.env(a, 0.0, 0.05, 0.4, 0.9), GOLD, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), RBMHeroFx.env(a, 0.0, 0.05, 0.12, 0.5))
	# 余韻: 金の粒が降る
	var fall_on := RBMHeroFx.env(t, T.burst + 0.4, T.burst + 0.7, T.end - 0.5, T.end)
	embers(b_add, Rect2(40, 20, 420, 40), t, 60, 51, -240.0, GOLD, fall_on, 2.0, 10.0)
	set_post({"vig": 0.3 * ch * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3)), "vig_col": Vector3(.05, .03, 0.0), "vig_r": .3})
	b_back.commit(); b_add.commit(); b_front.commit()
