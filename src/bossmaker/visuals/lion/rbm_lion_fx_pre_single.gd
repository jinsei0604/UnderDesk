extends RBMLionFxBase
## 金環の聖獣・覚醒前単体「飛びかかり」: 構え → 後脚を縮めて溜める（背に金の光輪）→ 一瞬で飛びかかる（残像）
## → 金の三本爪の聖なる斬撃（ヒットストップ）→ 振り抜き → 金の光になって元の位置へ戻る。

const T := {"windup": 0.22, "leap": 0.70, "contact": 0.80, "follow": 1.06, "vanish": 1.30, "back": 1.40, "end": 1.85}
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const AMBER := Color("#ff9f29")
const WHITE := Color("#ffffff")

var b_back: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var ring_hit: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.contact

func stops() -> Array:
	return [[T.contact, 0.09]]

## 相手の前（爪が胸に届く所）までのずれ
func _reach() -> Vector2:
	return Vector2(-50, 26) + focus_delta

func pose_keys() -> Array:
	return [[0.0, 1], [T.windup, 2], [T.leap, 3], [T.follow, 4], [T.back, 1]]

func move_keys() -> Array:
	var r := _reach()
	return [[0.0, Vector2.ZERO, "snap"], [T.leap, Vector2.ZERO, "snap"], [T.contact, r, "out"], [T.follow, r, "snap"], [T.follow + 0.08, r + Vector2(-8, 0), "out"], [T.back, r + Vector2(-8, 0), "snap"], [T.back + 0.001, Vector2.ZERO, "snap"]]

func _build() -> void:
	b_back = batch(back)
	ring_hit = ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .5, "breakup": .4, "seed": 2.0, "glow": .45, "glow_col": Vector3(1., .8, .4)})
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_front.reset(); b_add.reset()
	var hit := target_chest(3)
	var a := t - T.contact
	var gem := at("mark")
	# 溜め: 背の金の光輪が灯り、光が前脚へ集まる
	var charge := RBMHeroFx.ramp(t, T.windup, T.leap) * (1.0 - RBMHeroFx.ramp(t, T.leap, T.leap + 0.12))
	if t < T.leap + 0.15:
		# 背の金の光輪: 低く構えた体（頭と肩）の後ろに。光は頭の前へ集まる（2026-11-12 位置を体に合わせた）
		var halo_c := px(Vector2(152, 116))
		var hr := 30.0 + 6.0 * charge
		ring_line(b_back, halo_c, hr, 3.0, Color(GOLD, 0.8 * charge), 0.5)
		ring_line(b_back, halo_c, hr + 5.0, 1.0, Color(HOT, 0.5 * charge), 0.5)
		inward(b_add, px(Vector2(132, 134)), t, 60, 3, 4.0, 70.0, 1.4, GOLD, charge, 2.6)
		disc(b_add, gem, 3.0 + 5.0 * charge, Color(HOT, 0.8 * charge))
	if t >= T.windup and t < T.leap + 0.1:
		# 後脚の踏み込みの土ぼこり
		var dust := RBMHeroFx.env(t, T.leap - 0.05, T.leap, T.leap + 0.05, T.leap + 0.25)
		for i in range(6):
			disc(b_back, HOME + Vector2(30 + i * 7, -2 - RBMHeroFx.r(i, 9) * 6), 5.0 + i, Color(0.55, 0.5, 0.45, 0.35 * dust), 0.55)
	# 飛びかかり: 金の残像と光の筋
	if t >= T.leap and t < T.contact + 0.12:
		var u := RBMHeroFx.ramp(t, T.leap, T.contact)
		var gf := 1.0 - RBMHeroFx.ramp(t, T.contact, T.contact + 0.1)
		for k in range(3):
			var back_t := t - 0.04 * (k + 1)
			if back_t < T.leap:
				continue
			ghost(3, move_at(move_keys(), back_t), (0.34 - k * 0.1) * gf, GOLD, 0.6)
		for i in range(10):
			var y := lerpf(HOME.y - 60, hit.y + 10, RBMHeroFx.r(i, 4)) + (RBMHeroFx.r(i, 5) - 0.5) * 30.0
			var x0 := lerpf(HOME.x, hit.x + 40, u) + 20 + RBMHeroFx.r(i, 6) * 60
			b_add.streak(Vector2(x0 + 50, y), Vector2(x0, y), 1.4, Color(HOT, 0.7 * (1.0 - RBMHeroFx.ramp(t, T.contact, T.contact + 0.1))), Color(GOLD, 0.0))
	# 命中: 金の三本爪（斜めの三日月）、白金の閃き、火花、光の輪
	if a >= 0.0:
		var f := 1.0 - RBMHeroFx.ramp(a, 0.25, 0.55)
		var grow := RBMHeroFx.ramp(a, 0.0, 0.05)
		# 右上から左下へ払う三本の爪（白い芯・金の縁）。現れるのは一瞬、消える時は細くなる
		for i in range(3):
			var c := hit + Vector2(30 + i * 10, -34 + i * 4)
			crescent(b_front, c, 46.0, PI * 0.62, PI * 0.62 + 1.1 * grow, 9.0 * f, Color(AMBER, 0.85 * f), Color(GOLD, 0.0), 1.0)
			crescent(b_add, c, 46.0, PI * 0.62, PI * 0.62 + 1.1 * grow, 5.0 * f, Color(WHITE, f), Color(HOT, 0.9 * f), 1.0)
		disc(b_add, hit, 7.0 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.1)), Color(HOT, 0.8))
		sparks(b_add, hit, a, 0.45, 70, 11, 520.0, HOT, GOLD, PI, PI * 1.3, 180.0, 2.0)
		show_ring(ring_hit, hit, a, 0.4, 70.0, 5.0, 6.0, 0.03)
		view["shake"] += hit_shake(a, 14.0, 90.0, 0.32)
		ally_hits(t, [[T.contact, 3]], 1.0)
		embers(b_add, Rect2(hit.x - 30, hit.y - 30, 60, 40), t, 24, 21, 60.0, GOLD, RBMHeroFx.env(a, 0.05, 0.15, 0.6, 0.9), 2.0, 6.0)
	# 金の光になって戻る
	if t >= T.vanish and t < T.back + 0.25:
		var v := RBMHeroFx.ramp(t, T.vanish, T.back)
		var trail := 1.0 - RBMHeroFx.ramp(t, T.back, T.back + 0.2)
		var from := HOME + _reach() + Vector2(-8, -40)
		var to := HOME + Vector2(0, -40)
		b_add.streak(from.lerp(to, v), from, 4.0 * trail, Color(HOT, 0.85 * trail), Color(GOLD, 0.0))
		if t < T.back:
			body["alpha"] = 1.0 - v
			view["hero"]["flash"] = v
			view["hero"]["flash_col"] = HOT
		else:
			var appear := 1.0 - RBMHeroFx.ramp(t, T.back, T.back + 0.18)
			view["hero"]["flash"] = appear * 0.8
			view["hero"]["flash_col"] = HOT
			ring_line(b_add, HOME + Vector2(0, -2), 26.0 + 30.0 * (1.0 - appear), 2.0, Color(GOLD, appear), 0.3)
	b_back.commit(); b_front.commit(); b_add.commit()
