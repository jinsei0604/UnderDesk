extends RBMClockFxBase
## 本番（2026-11-16 ユーザー「これが終わったら実装していいよ」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/pre_all.gd でユーザーが採用した内容をそのまま移した。
## 振り子の給仕長・覚醒前全体「時刻の指揮」（2026-11-16 v3。ユーザー「迫力がない・技の一つ一つに意味があるように」）:
## 意味: 「この戦場は私の時計。お前たちの時刻を私が打つ」。
## 構え → 両手を頭の時計へ（四人の後ろに大時計がせり上がる。歯車が針を動かす仕組みとして両脇でかみ合う）
## → 両腕を開く（指揮の構え）: 大時計の両針がその腕と同じ角度へ振れる＝彼の腕が針
## → 4拍の指揮: 拍ごとに歯車が一歯回り、分針が次の一人の上へ跳ぶ。針が重なった人を、分針から抜け出した針が貫く（一人ずつ順に当たる）
## → 最後の拍で両針が12時で重なる: 大時計が鐘を打ち、光が満ちて一気に砕ける（最後の一撃。ガラスと真鍮・歯車が弾け飛ぶ）→ 余韻。

const T := {"charge": 0.34, "rise": 0.45, "conduct": 1.05, "beats": [1.42, 1.66, 1.90, 2.14], "chime": 2.52, "settle": 3.0, "end": 3.95}
const BRASS := Color("#d8b468")
const BRASS_D := Color("#7a6030")
const CREAM := Color("#f0e8d0")
const TEAL := Color("#4ab8c0")
const TEAL_L := Color("#a8f0f0")
const INK := Color("#141418")
const STEEL := [Color("#1a2440"), Color("#8aa2e0"), Color("#0a0a12")]
## 歯車: [大時計の中心からの位置, 半径, 歯の数, 回る向き]（左右の歯車がかみ合い、針の軸を回す）
const GEARS := [[Vector2(-128, -6), 30.0, 14.0, 1.0], [Vector2(-102, 42), 19.0, 10.0, -1.47], [Vector2(130, -18), 25.0, 12.0, -1.2], [Vector2(114, 34), 15.0, 9.0, 1.67]]

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_line: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var big: ColorRect
var gears: Array = []
var blast: ColorRect
var final_share := 0.45

func duration() -> float:
	return T.end

func impact() -> float:
	return T.chime

## 4拍で打つ順（大時計の12時から時計回りに、針が重なる順）
func _order() -> Array:
	var out: Array = [0, 1, 2, 3]
	if targets.size() < 4:
		return out
	var dc := _dial_center()
	out.sort_custom(func(i, j): return _clock_angle(dc, Vector2(targets[i]) + Vector2(0, -16)) < _clock_angle(dc, Vector2(targets[j]) + Vector2(0, -16)))
	return out

static func _clock_angle(c: Vector2, p: Vector2) -> float:
	return fposmod(atan2(p.x - c.x, -(p.y - c.y)), TAU)

func hits() -> Array:
	var out := []
	var order := _order()
	var beats: Array = T.beats
	for j in range(4):
		out.append([float(beats[j]) + 0.04, int(order[j])])
	return out

func stops() -> Array:
	return [[T.chime, 0.12]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.charge, 2], [T.conduct, 3], [T.settle, 4]]

func _dial_center() -> Vector2:
	var c := Vector2.ZERO
	for i in range(4):
		c += Vector2(targets[i]) if i < targets.size() else Vector2(170, 220)
	return c * 0.25 + Vector2(0, -40)

func _build() -> void:
	b_back = batch(back, false)
	blast = blast_quad(back, BRASS_PAL, ["#06121e", "#0c2a40", "#145a78", "#2aa0c0", "#7ee0ec", "#c8f6fa", "#eafcff", "#ffffff"], {"amp": 28., "k": .055, "seed": 3.6, "glow": .7, "glow_col": Vector3(.9, .9, .7), "glow_r": 44.})
	for g in GEARS:
		gears.append(gear_quad(back, {"teeth": g[2], "spokes": 5.0 if float(g[1]) > 20.0 else 4.0}))
	big = dial_quad(back, {"seed": 7.0, "thick": 6.0})
	b_line = batch(front, false)
	b_front = batch(front, false)
	b_add = batch(front)

## 拍の数（0〜4。拍の瞬間に 0.06秒で次へ）
func _beat_k(t: float) -> float:
	var k := 0.0
	for b in T.beats:
		k += smoothstep(float(b) - 0.06, float(b), t)
	return k

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_line.reset(); b_front.reset()
	var dc := _dial_center()
	var a := t - T.chime
	var rise := RBMHeroFx.ramp(t, T.rise, T.rise + 0.4)
	var bk := _beat_k(t)
	var order := _order()
	var beats: Array = T.beats
	view["dim"] = 0.34 * rise * (1.0 - RBMHeroFx.ramp(a, 0.3, 1.0))
	view["dim_col"] = Color(0.01, 0.03, 0.05)
	# 大時計: せり上がる。指揮の構えで両針が腕と同じ角度（10時10分）へ → 拍ごとに分針が次の人の上へ → 最後に両針が12時
	var dpos := dc + Vector2(0, 40.0 * (1.0 - rise * rise))
	var hour := 3.0
	var minute := 0.0
	if t >= T.conduct:
		var snap := RBMHeroFx.ramp(t, T.conduct, T.conduct + 0.06)
		hour = lerp_angle(3.0, 5.24, snap)
		minute = lerp_angle(0.0, 1.05, snap)
		if bk > 0.0:
			var j: int = mini(int(floorf(bk)), 3)
			var f: float = bk - floorf(bk)
			var cur: float = _clock_angle(dc, Vector2(targets[order[j]]) + Vector2(0, -16)) if j < 4 and bk < 4.0 else TAU
			var prev: float = 1.05 if j == 0 else _clock_angle(dc, Vector2(targets[order[j - 1]]) + Vector2(0, -16))
			minute = lerp_angle(prev, cur, f) if bk < 4.0 else _clock_angle(dc, Vector2(targets[order[3]]) + Vector2(0, -16))
	var fin := RBMHeroFx.ramp(t, T.chime - 0.12, T.chime)
	if fin > 0.0:
		minute = lerp_angle(minute, 0.0, fin)
		hour = lerp_angle(hour, 0.0, fin)
	var glow := 0.2 + 0.25 * RBMHeroFx.ramp(t, T.conduct, T.beats[0]) + 0.9 * fin
	var shat := RBMHeroFx.ramp(a, 0.0, 0.4)
	if rise > 0.0 and shat < 1.0:
		show_dial(big, dpos, 92.0, {"squash": 0.86, "hour": hour, "minute": minute, "second": t * 5.0, "glow": glow, "hot_mark": 0.0 if fin > 0.0 else -1.0, "hot": fin,
			"crack": RBMHeroFx.ramp(a, -0.04, 0.04), "shatter": shat, "fade": rise, "dark": 0.12 - 0.12 * fin})
	else:
		big.visible = false
	# 歯車: 拍ごとに一歯ずつ回る（針を動かす仕組み）。砕ける時に弾け飛ぶ
	for i in range(GEARS.size()):
		var g: Array = GEARS[i]
		var fly := RBMHeroFx.ramp(a, 0.0, 0.7)
		var out := Vector2(g[0]).normalized() * 170.0 * fly + Vector2(0, 260.0 * fly * fly)
		var gr := (bk + 0.4 * RBMHeroFx.ramp(t, T.rise, T.conduct)) * TAU / float(g[2]) * float(g[3]) + fly * 9.0 * float(g[3])
		show_gear(gears[i], dpos + Vector2(g[0]) + out, float(g[1]), {"rot": gr, "fade": rise * (1.0 - RBMHeroFx.ramp(a, 0.35, 0.7)), "dark": 0.15, "glow": 0.5 * fin})
	view["hero"]["lit"] = 0.4 * RBMHeroFx.ramp(t, T.charge, T.conduct) * (1.0 - RBMHeroFx.ramp(t, T.conduct, T.conduct + 0.3)) + 0.3 * fin
	view["hero"]["lit_col"] = BRASS
	# 4拍: 分針が重なった人を、分針から抜け出した針が貫く
	for j in range(4):
		var i := int(order[j])
		if not present[i]:
			continue
		var bt := float(beats[j])
		var chest := target_chest(i)
		var u := t - bt
		if u >= -0.02 and u < 0.32:
			var dir := (chest - dpos).normalized()
			var start := chest - dir * 46.0
			var tip := start.lerp(chest + dir * 6.0, RBMHeroFx.ramp(u, -0.02, 0.04))
			var fade := 1.0 - RBMHeroFx.ramp(u, 0.16, 0.32)
			breguet_hand(b_line, b_front, tip - dir * 40.0, tip, 2.2, STEEL, fade)
			b_add.line(dpos + dir * 20.0, tip - dir * 40.0, 2.0, Color(TEAL_L, 0.0), Color(TEAL_L, 0.35 * fade))
		if u >= 0.04:
			glass_shards(b_add, chest, u - 0.04, 0.45, 12, 21 + i * 7, 260.0, 2.6, Color(TEAL_L, 0.9), Color(TEAL, 0.7), 140.0)
			sparks(b_add, chest, u - 0.04, 0.38, 30, 23 + i, 360.0, Color("#eafcff"), BRASS, 0.0, TAU, 100.0, 1.5)
			view["shake"] += hit_shake(u - 0.04, 7.0, 90.0, 0.2)
	var evs := []
	for j in range(4):
		evs.append([float(beats[j]) + 0.04, int(order[j])])
	ally_hits(t, evs, 1.0)
	# 鐘: 両針が12時で重なり、光が満ちて一気に砕ける（最後の一撃）
	if a >= 0.0:
		set_post({"flash": 0.34 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.14)), "flash_col": Vector3(1.0, 0.97, 0.88), "chroma": 0.004 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.25))})
		glass_shards(b_front, dpos, a, 1.3, 52, 31, 680.0, 7.0, Color(CREAM, 1.0), Color("#9ab8c0", 1.0), 260.0)
		glass_shards(b_front, dpos, a, 1.2, 28, 37, 600.0, 6.0, BRASS, BRASS_D, 300.0)
		glass_shards(b_add, dpos, a, 0.9, 26, 33, 560.0, 4.0, Color(TEAL_L, 0.9), Color(TEAL, 0.6), 220.0)
		sparks(b_add, dpos, a, 0.8, 130, 35, 820.0, CREAM, BRASS, 0.0, TAU, 160.0, 2.0)
		view["shake"] += hit_shake(a, 18.0, 70.0, 0.55)
		ally_light(RBMHeroFx.env(a, 0.0, 0.05, 0.3, 0.7), CREAM, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), 1.2 * RBMHeroFx.env(a, 0.0, 0.05, 0.14, 0.5))
	var ba := a + 0.08
	var bf := 1.0 - RBMHeroFx.ramp(a, 0.3, 0.6)
	blast.visible = a >= 0.0 and bf > 0.0
	if blast.visible:
		show_blast(blast, blobs(dpos, ba, 32, 19, 240.0, 110.0, 60.0, 50.0, .6, 0.3, 8.0), ba, {"flow": ba * .3, "cool": .04, "erode": RBMHeroFx.ramp(ba, .15, .6), "fade": bf, "erode_noise": .4, "polar": 0.6, "detail": .5, "radial_heat": .5, "heat_center": w(dpos), "heat_radius": 220.0 * RBMHeroFx.burst(ba, 8.0), "erode_radial": 150.0, "tone_cap": .98})
	b_back.commit(); b_add.commit(); b_line.commit(); b_front.commit()
