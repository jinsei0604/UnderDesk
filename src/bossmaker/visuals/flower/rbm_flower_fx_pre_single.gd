extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/pre_single.gd でユーザーが採用した内容をそのまま移した。
## 白磁のカラー・覚醒前単体「棘指の突き」: 優雅な構え → 茎をひねる（白い花びらが周りを舞い、指先に淡い光）
## → 一瞬だけ鋭く指先を突き出し、蔦が一直線に伸びて相手を突く（白い閃き・花びらが散る・ヒットストップ）
## → 蔦が戻り、振り抜き → 元の姿勢へ。柔らかい動きから一瞬だけ鋭い。

const T := {"windup": 0.30, "thrust": 0.80, "contact": 0.86, "follow": 1.10, "back": 1.55, "end": 2.00}
const WHITE := Color("#fbf8ee")
const IVORY := Color("#e8e2d0")
const GREEN := Color("#6f8a52")
const LEAF := Color("#9db07a")
const GLOW := Color("#f2f6c8")

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var ring_hit: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.contact

func stops() -> Array:
	return [[T.contact, 0.08]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.windup, 2], [T.thrust, 3], [T.follow, 4], [T.back, 1]]

func move_keys() -> Array:
	return [[0.0, Vector2.ZERO, "snap"], [T.thrust, Vector2.ZERO, "snap"], [T.thrust + 0.04, Vector2(-14, 0), "out"], [T.follow, Vector2(-14, 0), "snap"], [T.back, Vector2(-6, 0), "inout"], [T.back + 0.25, Vector2.ZERO, "out"]]

func _build() -> void:
	b_back = batch(back, false)
	ring_hit = ring_quad(front, ["#9db07a", "#e8e2d0", "#fbf8ee", "#ffffff"], {"squash": .5, "breakup": .3, "seed": 3.0, "glow": .3, "glow_col": Vector3(.95, 1., .8)})
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var hit := target_chest(3)
	var a := t - T.contact
	# 舞う白い花びら（構えから溜めの間）
	var sway := RBMHeroFx.env(t, 0.0, T.windup, T.thrust, T.thrust + 0.2)
	petal_cloud(b_front, at("center", 1, 0, -10), t, 10, 3, 36.0, 4.0, WHITE, IVORY, 0.9 * sway, "orbit", 0.5)
	var ch := RBMHeroFx.ramp(t, T.windup, T.thrust)
	# 指先の光は突きの瞬間に消す（2026-11-13 指摘: 攻撃の後も白い丸が残っていた）
	var gk := ch * (1.0 - RBMHeroFx.ramp(t, T.thrust - 0.02, T.thrust + 0.04))
	var tip := at("front", 2)
	disc(b_add, tip, 2.0 + 3.0 * ch, Color(GLOW, 0.8 * gk))
	inward(b_add, tip, t, 30, 5, 3.0, 40.0, 1.0, GLOW, gk, 2.0)
	# 突き: 指先から相手へ蔦が一直線に伸び、戻る
	if t >= T.thrust:
		var finger := at("front", 3)
		var grow := RBMHeroFx.ramp(t, T.thrust, T.contact) * (1.0 - RBMHeroFx.ramp(t, T.contact + 0.18, T.follow + 0.12))
		var reach := finger.lerp(hit + Vector2(10, 0), 1.0)
		vine(b_front, finger, reach, -6.0, grow, 2.2, Color(GREEN, 1.0), Color(LEAF, 1.0), 7, true, true)
		if t < T.contact + 0.08:
			b_add.streak(reach, finger, 1.6, Color(WHITE, 0.9 * grow), Color(GLOW, 0.0))
	# 命中: 白い閃き、細い一閃、花びらが散る、淡い輪
	if a >= 0.0:
		var f := 1.0 - RBMHeroFx.ramp(a, 0.1, 0.35)
		b_add.line(hit + Vector2(26, -18), hit + Vector2(-26, 18), 3.0 * f, Color(WHITE, f), Color(GLOW, f))
		disc(b_add, hit, 6.0 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.1)), Color(WHITE, 0.9))
		petal_cloud(b_front, hit, a, 22, 11, 90.0, 4.0, WHITE, IVORY, 1.0, "burst")
		show_ring(ring_hit, hit, a, 0.4, 60.0, 4.0, 6.0, 0.02)
		sparks(b_add, hit, a, 0.4, 40, 13, 380.0, WHITE, GLOW, PI, PI * 1.4, 120.0, 1.6)
		view["shake"] += hit_shake(a, 8.0, 90.0, 0.25)
	ally_hits(t, [[T.contact, 3]], 1.0)
	# 余韻: 花びらがゆっくり落ちる
	petal_cloud(b_front, hit + Vector2(0, -20), t, 8, 17, 40.0, 3.5, WHITE, IVORY, RBMHeroFx.env(t, T.contact + 0.2, T.follow, T.end - 0.3, T.end), "fall")
	b_back.commit(); b_add.commit(); b_front.commit()
