extends RBMGentlemanFxLayer
## 異形紳士・強化と回復「身だしなみ」のエフェクト（2026-11-23 強化。動き・時刻は rbm_gentleman_vfx.gd のまま）。
## 手袋を直すと、まわりから光の筋が手元へ集まる → クラバットを直すと襟元が閃き、目が赤く光る → 体に力が満ちる瞬間、
## 足元に衝撃の輪と火の粉（強化は深紅と薔薇の花びら、回復は翠の光の粒）→ 光の粒が上り続けて薄れる。
## 2026-11-23 ユーザー「支援と回復のとき光の柱があるのはださい」→ 光の柱は使わない。

const GLOVE := [0.55, 0.9, 1.7, 1.95]
const CRAVAT := [1.95, 2.3, 2.85, 3.1]
const HAND := Vector2(-2, -57)
const NECK := Vector2(-3, -70)
const HEAL := Color("#5fe08a")
const HEAL_PALE := Color("#e2ffe9")

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var rings: Array = []

func _heal() -> bool:
	return action_kind == "heal"

func _col() -> Color:
	return HEAL if _heal() else RED

func _pale() -> Color:
	return HEAL_PALE if _heal() else ROSE

func _build() -> void:
	b_back = batch(back, false)
	b_back_add = batch(back)
	b_mid = batch(mid, false)
	for i in range(2):
		var dark_pal: Array = ["#031a0c", "#0c3a1e", "#1fa050", "#a0f0c0"] if _heal() else RBMHeroFx.A4_DARK
		rings.append(ring_quad(front, (["#0c5a2a", "#1fa050", "#c8ffd8", "#ffffff"] if _heal() else RBMHeroFx.A4_RED) if i == 0 else dark_pal, {"squash": .3, "breakup": .5, "seed": 1.7 + i * 2.1, "glow": .5, "glow_col": Vector3(.3, 1., .5) if _heal() else Vector3(.95, .15, .25)}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_mid.reset(); b_add.reset(); b_front.reset()
	var hv: Vector2 = vfx.call("host_foot")
	var f := vp(hv)
	var hand := vp(hv + HAND)
	var neck := vp(hv + NECK)
	var ch := f + Vector2(0, -26)
	var col := _col()
	var pale := _pale()
	var imp := impact()
	var a := t - imp
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [0.5, 0.2], [imp - 0.2, 0.32], [imp + 0.1, 0.22], [duration() - 0.6, 0.0]])
	view["dim_col"] = Color(0.0, 0.03, 0.015) if _heal() else Color(0.05, 0.0, 0.02)
	set_post({"vig": 0.12 + 0.3 * RBMHeroFx.env(t, 0.4, 1.2, imp + 0.6, duration() - 0.3), "vig_col": Vector3(.0, .1, .04) if _heal() else Vector3(.15, .0, .03), "vig_r": .34})
	# 手袋を直す: 光の筋が手元へ集まり、手元が脈打つ
	var glove := RBMHeroFx.env(t, GLOVE[0], GLOVE[1], GLOVE[2], GLOVE[3])
	inward(b_add, hand, t, 22, 11, 3.0, 46.0, 1.0, Color(pale, 1.0), glove, 1.6)
	if glove > 0.0:
		RBMHeroRooftop.glow(b_add, hand, 5.0 + 2.0 * sin(t * 9.0), Color(pale, 0.7 * glove))
		star(b_add, hand, glove * (0.6 + 0.4 * absf(sin(t * 7.0))), 4, 19, 8.0, 0.8, [Color(pale, 0.9), Color(col, 0.6)])
	# クラバットを直す: 襟元の閃き・目が赤く光る
	var cravat := RBMHeroFx.env(t, CRAVAT[0], CRAVAT[1], CRAVAT[2], CRAVAT[3])
	if cravat > 0.0:
		RBMHeroRooftop.glow(b_add, neck, 4.0 + 1.5 * sin(t * 11.0), Color(pale, 0.8 * cravat))
		star(b_add, neck, cravat, 4, 23, 10.0, 0.8, [Color(1, 1, 1, 0.9), Color(pale, 0.6)])
	var pose_now: String = Motion.frame(action_kind, t)
	eyes(b_add, eye_of(pose_now, f), 0.5 + 0.5 * RBMHeroFx.env(t, CRAVAT[0], CRAVAT[1], imp + 0.4, duration() - 0.3), 0.9)
	# 力が満ちる直前: 胸へ光の筋が集まる
	inward(b_add, ch, t, 30, 31, 6.0, 80.0, 1.2, Color(col, 1.0), RBMHeroFx.env(t, imp - 0.45, imp - 0.25, imp - 0.03, imp), 2.6)
	# 力が満ちる: 足元の衝撃の輪・火の粉・花びら（回復は翠の光の粒）
	show_ring(rings[0], f + Vector2(0, -2), a, 0.6, 120.0, 5.0, 6.0, 0.02)
	show_ring(rings[1], f + Vector2(0, -2), a - 0.06, 0.65, 90.0, 4.0, 5.5, 0.0)
	if a >= 0.0:
		refract_wave(ch, a, 0.5, 160.0, 6.0, 0.025)
		sparks(b_add, ch, a, 0.9, 80, 37, 300.0, Color(pale, 1.0), Color(col, 1.0), -PI * 0.5, PI * 1.3, 140.0, 1.8)
		view["hero"]["flash"] = 0.45 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.18))
		view["hero"]["flash_col"] = pale
		set_post({"flash": 0.07 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.1))})
		view["shake"] += hit_shake(a, 4.0, 80.0, 0.25)
	view["hero"]["lit"] = 0.5 * RBMHeroFx.env(t, imp - 0.4, imp, imp + 0.5, duration() - 0.3)
	view["hero"]["lit_col"] = col
	if _heal():
		embers(b_add, Rect2(f.x - 26, f.y - 40, 52, 40), t, 36, 41, 70.0, Color(HEAL, 1.0), RBMHeroFx.env(t, imp - 0.1, imp + 0.1, duration() - 1.0, duration() - 0.2), 2.0, 6.0)
		embers(b_add, Rect2(f.x - 18, f.y - 30, 36, 30), t, 18, 43, 90.0, Color(HEAL_PALE, 1.0), RBMHeroFx.env(t, imp, imp + 0.2, duration() - 1.0, duration() - 0.2), 1.0, 4.0)
	else:
		petals(b_front, ch, a, 1.8, 40, 45, 140.0, 1.0, 0.7)
		embers(b_add, Rect2(f.x - 26, f.y - 40, 52, 40), t, 30, 41, 70.0, Color(RED, 1.0), RBMHeroFx.env(t, imp - 0.1, imp + 0.1, duration() - 1.0, duration() - 0.2), 1.6, 6.0)
	RBMHeroRooftop.glow(b_back_add, f, 22.0, Color(col, 0.18 * RBMHeroFx.env(t, imp - 0.3, imp, imp + 0.6, duration() - 0.3)))
	b_back.commit(); b_back_add.commit(); b_mid.commit(); b_add.commit(); b_front.commit()
