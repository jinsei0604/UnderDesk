extends RBMLionFxBase
## 金環の聖獣の登場（2026-11-13 ユーザーの案）: 戦場が少し暗くなり、聖獣が現れる場所に金色のオーラをまとった剣が
## 空から次々と突き刺さっていく（刺さるたびに火花と金の輪、剣の円陣ができていく）→ 最後に巨大な剣が空からゆっくり現れ、
## 一気に突き刺さる（ヒットストップ）→ 金の大爆発（剣はすべて光になって砕ける）→ 爆発の中から聖獣が現れて咆哮 → 立ち姿。
## 時刻は登場の再生の秒（rbm_intro_player.gd の age。0.30秒から始まる）。本体の絵は pre_all（3＝咆哮）と立ち姿（0）。

const T := {"dim": 0.36, "swords": [0.78, 0.98, 1.15, 1.30, 1.43, 1.55, 1.65, 1.74], "giant_in": 1.98, "giant_fall": 2.40, "giant_hit": 2.56, "burst": 2.62,
	"reveal": 2.80, "roar": 3.05, "stance": 3.80, "end": 5.0}
## 剣が刺さる場所（足元からの論理ドット）と傾き（ラジアン）。円陣になるように前後左右へ散らす
const SPOTS := [[Vector2(-54, 6), -0.18], [Vector2(50, -8), 0.20], [Vector2(-22, 18), -0.08], [Vector2(70, 12), 0.26], [Vector2(-70, -10), -0.24], [Vector2(26, 20), 0.10], [Vector2(-40, -18), -0.14], [Vector2(36, -20), 0.16]]
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const AMBER := Color("#ff9f29")

var b_back: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var blast: ColorRect
var rings: Array = []

func duration() -> float:
	return T.end

## 巨大な剣が刺さった瞬間に止める
func stops() -> Array:
	return [[T.giant_hit, 0.10]]

func pose_keys() -> Array:
	return [[0.0, 3], [T.stance, 0]]

func _build() -> void:
	b_back = batch(back, false)
	b_glow = batch(back)
	blast = blast_quad(back, GOLDEN, GOLDEN, {"amp": 40., "k": .046, "seed": 3.9, "glow": .7, "glow_col": Vector3(1., .8, .4), "glow_r": 56.})
	for i in range(6):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .4, "seed": 1.5 + i * 2.7, "glow": .45, "glow_col": Vector3(1., .8, .4)}))
	b_front = batch(front, false)
	b_add = batch(front)

## 本体が見えるか（爆発の中から現れる）
func body_alpha(t: float) -> float:
	return RBMHeroFx.ramp(t, T.reveal - 0.1, T.reveal + 0.1)

## 剣（tip が地面に刺さった先端、向きは ang、長さ length、幅 wide）。金色のオーラを周りに（描き方は RBMLionFxBase.draw_sword）。
func sword(tip: Vector2, ang: float, length: float, wide: float, aura: float, alpha: float = 1.0) -> void:
	draw_sword(b_back, b_glow, tip, ang, length, wide, aura, alpha)

func _step(t: float) -> void:
	b_back.reset(); b_glow.reset(); b_front.reset(); b_add.reset()
	var a := t - T.giant_hit
	var ground := HOME + Vector2(0, 2)
	var circle := 0.0
	for at_t in T.swords:
		circle += RBMHeroFx.ramp(t, float(at_t), float(at_t) + 0.08) / float(T.swords.size())
	var gone := RBMHeroFx.ramp(a, 0.04, 0.2)
	# 戦場が少し暗くなる（剣の光が映えるように）。爆発で明るくなって戻る
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.dim, 0.0], [T.dim + 0.4, 0.42], [T.giant_hit, 0.55], [T.giant_hit + 0.3, 0.2], [T.stance, 0.0]])
	view["dim_col"] = Color(0.02, 0.02, 0.05)
	# 剣の円陣: 聖獣が現れる場所の足元に金の光の輪（剣が刺さるほど強くなる）
	if circle > 0.0 and gone < 1.0:
		var f := circle * (1.0 - gone)
		ring_line(b_glow, ground, 50.0 + 26.0 * circle, 2.0, Color(GOLD, 0.7 * f), 0.3)
		ring_line(b_glow, ground, 36.0 + 18.0 * circle, 1.0, Color(HOT, 0.5 * f), 0.3)
		disc(b_glow, ground, 40.0 + 30.0 * circle, Color(GOLD, 0.10 * f), 0.3)
		embers(b_add, Rect2(ground.x - 70, ground.y - 10, 140, 16), t, 40, 3, 80.0, GOLD, f, 2.0, 6.0)
	# 剣が次々と空から突き刺さる（刺さった後は残る。巨大な剣の一撃で光になって砕ける）
	for i in range(T.swords.size()):
		var at_t := float(T.swords[i])
		var spot: Vector2 = SPOTS[i][0]
		var ang := float(SPOTS[i][1])
		var tip := ground + spot
		var up := Vector2(sin(ang), -cos(ang))
		var fall := 0.16
		if t < at_t - fall:
			continue
		var u := RBMHeroFx.ramp(t, at_t - fall, at_t)
		var pos := tip + up * 260.0 * (1.0 - u * u)
		var alpha := 1.0 - gone
		sword(pos, ang, 46.0, 5.0, 1.0, alpha)
		if t < at_t:
			b_add.streak(pos + up * 90.0, pos + up * 10.0, 3.0, Color(GOLD, 0.0), Color(HOT, 0.7))
		var hit := t - at_t
		if hit >= 0.0:
			sparks(b_add, tip, hit, 0.35, 30, 11 + i, 260.0, HOT, GOLD, -PI * 0.5, PI * 0.9, 220.0, 1.6)
			ring_line(b_add, tip, 6.0 + 50.0 * RBMHeroFx.burst(hit, 9.0), 1.5, Color(GOLD, 0.7 * (1.0 - RBMHeroFx.ramp(hit, 0.05, 0.3))), 0.32)
			disc(b_add, tip + Vector2(0, -2), 6.0 * (1.0 - RBMHeroFx.ramp(hit, 0.0, 0.12)), Color(HOT, 0.8))
			view["shake"] += hit_shake(hit, 4.0 + i * 0.6, 90.0, 0.18)
	# 巨大な剣: 空からゆっくり現れ、溜めてから一気に突き刺さる
	if t >= T.giant_in and gone < 1.0:
		var appear := RBMHeroFx.ramp(t, T.giant_in, T.giant_in + 0.3)
		var hover := ground + Vector2(0, -150.0 - 30.0 * (1.0 - appear))
		var u2 := RBMHeroFx.ramp(t, T.giant_fall, T.giant_hit)
		var pos2 := hover.lerp(ground + Vector2(0, 2), u2 * u2 * u2) if t < T.giant_hit else ground + Vector2(0, 2)
		var charge := RBMHeroFx.ramp(t, T.giant_in, T.giant_fall)
		sword(pos2, 0.0, 150.0, 14.0, 0.6 + 0.8 * charge, appear * (1.0 - gone))
		if t < T.giant_fall:
			inward(b_add, pos2 + Vector2(0, -60), t, 80, 21, 8.0, 160.0, 1.6, GOLD, charge, 2.2)
			b_add.streak(pos2 + Vector2(0, -220), pos2 + Vector2(0, -150), 4.0 * appear, Color(GOLD, 0.0), Color(HOT, 0.6 * appear))
		elif t < T.giant_hit:
			b_add.streak(pos2 + Vector2(0, -260), pos2 + Vector2(0, -40), 8.0, Color(GOLD, 0.0), Color(HOT, 0.9))
	# 一撃: 刺さった瞬間の白金の閃き → 金の大爆発（剣はすべて光の破片になって砕ける）
	if a >= 0.0:
		disc(b_add, ground + Vector2(0, -30), 40.0 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.2)), Color(HOT, 0.8 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.2))), 0.6)
		view["shake"] += hit_shake(a, 20.0, 70.0, 0.6)
	var ab := t - T.burst
	var bf := 1.0 - RBMHeroFx.ramp(ab, 0.55, 1.0)
	blast.visible = ab >= 0.0 and bf > 0.0
	if blast.visible:
		var c := ground + Vector2(0, -40)
		show_blast(blast, blobs(c, ab, 40, 17, 430.0, 220.0, 100.0, 140.0, .6, 0.0, 6.2), ab, {"flow": ab * .22, "cool": .04 + RBMHeroFx.ramp(ab, .2, 1.0) * .22, "erode": RBMHeroFx.ramp(ab, .32, .98), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .55, "amp": 38.0, "radial_heat": .5, "heat_center": w(c), "heat_radius": 460.0 * RBMHeroFx.burst(ab, 6.2), "erode_radial": 210.0, "tone_cap": .97})
		refract_wave(c, ab, 0.8, 560.0, 5.0, 0.035)
	if ab >= 0.0:
		shards(b_add, ground + Vector2(0, -30), ab, 1.1, 70, 31, 760.0, 5.0, HOT, GOLD, 160.0)
		sparks(b_add, ground + Vector2(0, -40), ab, 1.0, 160, 33, 1050.0, HOT, GOLD, 0.0, TAU, 140.0, 2.2)
	for i in range(3):
		show_ring(rings[i], ground, ab - i * 0.08, 0.8, 560.0, 9.0 - i * 2.0, 5.0, 0.03)
	# 本体: 爆発の中から白金の光で現れ、光が引いて咆哮 → 立ち姿
	var reveal := RBMHeroFx.ramp(t, T.reveal - 0.1, T.reveal + 0.1)
	body["alpha"] = reveal
	body["hidden"] = reveal <= 0.0
	view["hero"]["flash"] = (1.0 - RBMHeroFx.ramp(t, T.reveal, T.reveal + 0.35)) * reveal
	view["hero"]["flash_col"] = HOT
	view["hero"]["lit"] = 0.5 * RBMHeroFx.env(t, T.reveal, T.reveal + 0.3, T.roar + 0.4, T.stance + 0.3)
	view["hero"]["lit_col"] = GOLD
	var mouth := at("front", 3, 6, -26)
	var ar := t - T.roar
	if ar < 0.0 or t >= T.stance:
		for k in range(3):
			rings[3 + k].visible = false
	if ar >= 0.0 and t < T.stance:
		for k in range(3):
			show_ring(rings[3 + k], mouth, ar - k * 0.18, 0.7, 260.0, 5.0 - k, 4.0, 0.025)
		view["shake"] += hit_shake(ar, 8.0, 70.0, 0.5)
	embers(b_add, Rect2(HOME.x - 160, HOME.y - 200, 320, 60), t, 60, 41, -200.0, GOLD, RBMHeroFx.env(ab, 0.3, 0.6, 1.8, 2.3), 2.0, 10.0)
	b_back.commit(); b_glow.commit(); b_front.commit(); b_add.commit()
