extends RBMLionFxBase
## 金環の聖獣／日蝕の獅皇の支援（回復・強化。2026-11-13 ユーザー「適当に作ってみて、立ち絵を1回変えればいい」）。
## 立ち姿 → 支援のポーズ（覚醒前＝頭を上げた姿 pre_all の4枚目、覚醒後＝咆哮の姿 awaken の4枚目）→ 立ち姿。切り替えは1回だけ。
## 頭の上に小さな金環日食（覚醒後は深紅の光冠）が現れ、光を集めて一気に放つ。
## 回復: 金環から柔らかな光の柱が降りて、淡い金緑の光の粒が降り注ぐ。強化: 金環が燃え上がり、足元から光の筋と火の粉が立ち上る。
## 時刻は技の秒。最後の一撃（impact）で数字が出る（stage._strike()）。

const T := {"pose": 0.20, "halo": 0.24, "gather": 0.46, "impact": 1.20, "back": 1.92, "end": 2.36}
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const AMBER := Color("#ff9f29")
## 回復の光（金に淡い緑）
const LEAF := Color("#d8ffbc")
const RED := Color("#e0402a")
const EMBER := Color("#ff6a2a")
## 覚醒前の光冠（金）。覚醒後は日蝕の深紅（DREAD）へ移す
const CORONA_GOLD := ["#4a3412", "#7a5418", "#b07a20", "#e0a83a", "#ffd27a", "#fff1c8"]

## 覚醒後（深紅の光冠）
var awakened := false
## 回復（false で強化）
var heal := true
## 支援のポーズの番号（seq の何枚目か）
var src_n := 4

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var eclipse: ColorRect
var wave: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.impact

func pose_keys() -> Array:
	return [[0.0, 0], [T.pose, src_n], [T.back, 0]]

func _build() -> void:
	b_back = batch(back)
	eclipse = pquad(back, Rect2(0, 0, 10, 10), "eclipse", {"pal": RBMHeroFx.pal(ECLIPSE if awakened else CORONA_GOLD), "seed": 2.2})
	wave = ring_quad(front, RBMHeroFx.A4_RED if awakened else RBMHeroFx.A4_AMBER, {"squash": .32, "breakup": .3, "seed": 5.1, "glow": .4, "glow_col": Vector3(1., .8, .4)})
	b_add = batch(front)

## 頭の上の金環の中心
func halo_center() -> Vector2:
	return at("top", src_n, 4, -20)

## 縦の光の帯: 上 a から下 c へ、中心の色 → 両縁で透明。
func band(b: RBMHeroFxBatch, a: Vector2, c: Vector2, wd: float, col_a: Color, col_c: Color) -> void:
	var side := Vector2(wd * 0.5, 0.0)
	b.quad(a, c, c + side, a + side, col_a, col_c, Color(col_c, 0.0), Color(col_a, 0.0))
	b.quad(a, c, c - side, a - side, col_a, col_c, Color(col_c, 0.0), Color(col_a, 0.0))

func _step(t: float) -> void:
	b_back.reset(); b_add.reset()
	var c := halo_center()
	var ground := HOME + Vector2(4, 1)
	var chest := at("mark", src_n)
	var a := t - T.impact
	var col := RED if awakened else GOLD
	var light := LEAF if heal else (EMBER if awakened else AMBER)
	var on := RBMHeroFx.env(t, T.halo, T.halo + 0.22, T.back - 0.15, T.end - 0.1)
	var charge := RBMHeroFx.ramp(t, T.gather, T.impact)
	var flare := RBMHeroFx.env(a, 0.0, 0.05, 0.25, 0.7)
	# 金環日食（覚醒後は深紅）: 頭の上に現れ、溜めの間に光冠が伸び、放つ瞬間に燃え上がる
	if on > 0.0:
		var corona := 7.0 + 7.0 * charge + (16.0 if not heal else 9.0) * flare
		show_eclipse(eclipse, c, 12.0 + 2.0 * on + 2.0 * flare, corona, {"flow": t * 1.2, "power": 0.55 + 0.45 * charge + 0.4 * flare, "fade": on, "sun_fill": 1.0,
			"moon_k": 0.76, "dread": 1.0 if awakened else 0.0, "rim": 1.0, "sun_col": Vector3(1.0, 0.42, 0.26) if awakened else Vector3(1.0, 0.86, 0.5)})
	else:
		eclipse.visible = false
	# 溜め: 周りの光が金環へ集まる
	if t >= T.gather and t < T.impact:
		inward(b_add, c, t, 44, 7, 6.0, 72.0, 1.2, Color(HOT if not awakened else Color("#ffb080"), 0.85), charge, 2.4)
		disc(b_add, c, 4.0 + 10.0 * charge, Color(HOT, 0.10 + 0.25 * charge))
	if heal:
		# 回復: 金環から光の柱がゆっくり降りて体を包み、光の粒が降り注ぐ
		var pillar := RBMHeroFx.env(a, -0.04, 0.10, 0.45, 0.85)
		if pillar > 0.0:
			# 空から金環を通って体へ降りる柔らかな光の柱（縁へ向かって消える帯を重ねる）
			var top := Vector2(c.x, c.y - 140.0)
			var reach := Vector2(c.x, lerpf(c.y, ground.y + 2.0, RBMHeroFx.ramp(a, -0.04, 0.14)))
			band(b_back, top, reach, 64.0, Color(light, 0.0), Color(light, 0.26 * pillar))
			band(b_back, top, reach, 34.0, Color(HOT, 0.10 * pillar), Color(HOT, 0.34 * pillar))
			band(b_add, top, reach, 12.0, Color(HOT, 0.12 * pillar), Color(HOT, 0.30 * pillar))
			disc(b_back, ground, 46.0 * pillar, Color(light, 0.18 * pillar), 0.3)
		embers(b_add, Rect2(c.x - 46, c.y - 40, 92, ground.y - c.y + 40), t, 56, 19, -70.0, Color(light, 1.0), RBMHeroFx.env(a, -0.1, 0.1, 0.6, 1.0), 2.5, 6.0)
		embers(b_add, Rect2(ground.x - 50, ground.y - 70, 100, 70), t, 30, 23, 60.0, Color(HOT, 0.8), RBMHeroFx.env(a, 0.05, 0.25, 0.6, 1.05), 1.5, 8.0)
		if a >= 0.0:
			ring_line(b_add, ground, 14.0 + 52.0 * RBMHeroFx.burst(a, 6.0), 1.5, Color(light, 0.7 * (1.0 - RBMHeroFx.ramp(a, 0.1, 0.6))), 0.3)
			ring_line(b_add, ground, 8.0 + 34.0 * RBMHeroFx.burst(a, 5.0), 1.0, Color(HOT, 0.6 * (1.0 - RBMHeroFx.ramp(a, 0.1, 0.5))), 0.3)
		view["hero"]["flash"] = 0.45 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.35)) if a >= 0.0 else 0.0
		view["hero"]["flash_col"] = light
		view["hero"]["lit"] = 0.55 * RBMHeroFx.env(a, 0.0, 0.1, 0.5, 0.9)
		view["hero"]["lit_col"] = light
	else:
		# 強化: 金環が燃え上がり、足元から光の筋と火の粉が立ち上る。体の縁が燃える色に
		var rise := RBMHeroFx.env(a, 0.0, 0.06, 0.45, 0.8)
		if rise > 0.0:
			for i in range(22):
				var x := ground.x - 44.0 + 88.0 * RBMHeroFx.r(i, 61)
				var q := fmod(a * (1.6 + 0.8 * RBMHeroFx.r(i, 62)) + RBMHeroFx.r(i, 63), 1.0)
				var y0 := ground.y - q * 90.0
				var ln := 10.0 + 18.0 * RBMHeroFx.r(i, 64)
				b_add.streak(Vector2(x, y0 - ln), Vector2(x, y0), 2.0, Color(HOT, 0.0), Color(light.lerp(HOT, 0.3), 0.95 * rise * sin(q * PI)))
		embers(b_add, Rect2(ground.x - 54, ground.y - 40, 108, 40), t, 54, 29, 110.0, Color(light, 0.95), RBMHeroFx.env(a, -0.05, 0.1, 0.55, 1.0), 2.0, 5.0)
		if a >= 0.0:
			disc(b_back, ground + Vector2(0, -2), 50.0 * RBMHeroFx.burst(a, 6.0), Color(col, 0.22 * (1.0 - RBMHeroFx.ramp(a, 0.05, 0.6))), 0.3)
			ring_line(b_add, ground, 16.0 + 60.0 * RBMHeroFx.burst(a, 7.0), 2.0, Color(light, 0.8 * (1.0 - RBMHeroFx.ramp(a, 0.1, 0.55))), 0.3)
			ring_line(b_add, chest, 6.0 + 26.0 * RBMHeroFx.burst(a, 9.0), 1.5, Color(HOT, 0.8 * (1.0 - RBMHeroFx.ramp(a, 0.05, 0.3))))
		show_ring(wave, chest, a, 0.6, 120.0, 4.0, 6.0, 0.02)
		view["shake"] += hit_shake(a, 6.0, 80.0, 0.3)
		view["hero"]["flash"] = 0.55 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.25)) if a >= 0.0 else 0.0
		view["hero"]["flash_col"] = HOT
		view["hero"]["lit"] = 0.7 * RBMHeroFx.env(a, 0.0, 0.08, 0.55, 0.85)
		view["hero"]["lit_col"] = light
		if awakened:
			view["hero"]["sun_aura"] = 1.0 + 1.1 * RBMHeroFx.env(a, 0.0, 0.1, 0.4, 0.8)
	# 世界: 光が映えるように少しだけ暗く
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.halo, 0.0], [T.gather, 0.22], [T.impact, 0.3], [T.back, 0.08], [T.end, 0.0]])
	view["dim_col"] = Color(0.04, 0.03, 0.02) if not awakened else Color(0.05, 0.01, 0.02)
	b_back.commit(); b_add.commit()
