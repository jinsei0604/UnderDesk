extends RBMGentlemanFxBase
## 異形紳士・覚醒前の全体「跳弾」（2026-11-23 作り直し。前の版は影が四人の横に並んで撃つ）。
## ユーザー「覚醒前の全体攻撃はこのアイデア自体が良くない。異形紳士はクールなキャラだから、それに合った技を考えて」
## → クールに: 動きは少なく、一発で全部が決まる。
## 2026-11-23 ユーザー「四方八方に、狼と同じすごい速さで」「軌道は五芒星に。弾は画面の外へ行かず、最後に当たった所で止まる」
## 意味: 銃を抜き、片腕をまっすぐ伸ばして一発だけ撃つ → 時間がほとんど止まる（色が抜け、空気の塵が止まる）。弾は四人を囲む
## 星の頂点で跳ね返りながら、狼の駆け抜けと同じ速さ（1本 STEP 秒）で五芒星を描く。五本の線は四人を貫き、深紅の星だけが
## 色の抜けた空中に残る。弾は最初の頂点へ戻ると、一番近いパーティの一人の胸へ跳ね返って食い込み、そこで赤く光り続ける
## （2026-11-23 ユーザー「最後の着弾地点はパーティー側の誰かに」。その間に紳士は銃を下ろし、腰に手を当てて見てもいない）
## → 紳士が帽子のつばに触れた瞬間に時間が戻る: 星が砕け、四人が同時に撃ち抜かれる（深紅の弾け）。
## 頂点で跳ね返る時刻は FIRST + STEP*k（音 all_v2.wav と同じ）。体を貫く時刻は、線が胸に一番近づく所（hits）。

const T := {"draw": 0.3, "aim": 0.5, "glint": 0.66, "fire": 0.85, "lower": 1.25, "rest": 1.5, "click": 2.2, "impact": 2.25, "stand": 2.85, "end": 3.6}
## 頂点: 最初の頂点に着く時刻・一本の時間・星の線の数（銃口 → 頂点 → 一つ飛ばしで五本 → 最初の頂点 → 一人の胸で止まる）
const FIRST := 0.93
const STEP := 0.07
const COUNT := 5
## 線が胸のそばを通ったら貫いたとする距離（論理ドット）
const PASS_NEAR := 16.0
## 一人に出す小さな数字の数の上限（狼と同じ）
const MAX_SMALL := 3
## 片腕を伸ばした絵（legacy_final_aim）の銃口（足元から、絵の画素）と、帽子のつば（hat_reach_15）
const MUZZLE := Vector2(-39, -74)
const BRIM := Vector2(-8, -92)

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
## 色を抜く画面全体の処理（z 19）より上に描く層: 止まった時間の中でも、弾と深紅の軌跡だけは色が残る
var b_top: RBMHeroFxBatch
var blasts: Array = []
var ring: ColorRect
var ring2: ColorRect
## 弾の通る点: 0=銃口、1〜COUNT+1=星の頂点（一つ飛ばし。COUNT+1 は最初の頂点）、最後=止まる所（一人の胸）
var last_target := -1
var path: Array = []
## 体を貫いた所: {"t": 時刻, "who": 相手の番号, "p": 位置, "seg": 区間}
var passes: Array = []
var final_share := 0.6

func duration() -> float:
	return T.end

func impact() -> float:
	return T.impact

func pose_keys() -> Array:
	return [[0.0, "hat_reach_00"], [T.draw, "normal_draw_fire_05"], [T.aim, "legacy_final_aim"], [T.lower, "normal_draw_fire_05"], [T.rest, "legacy_hand_rest"],
		[T.click - 0.08, "hat_reach_15"], [T.stand, "hat_reach_00"]]

## 途中の当たり（弾が体を貫いた時）: [[秒, 相手の番号], ...]（一人 MAX_SMALL まで）
func hits() -> Array:
	if path.is_empty():
		_make_path()
	var out := []
	var counts := {}
	for ps in passes:
		var who := int(ps.who)
		if int(counts.get(who, 0)) >= MAX_SMALL:
			continue
		counts[who] = int(counts.get(who, 0)) + 1
		out.append([float(ps.t), who])
	return out

## 区間 k（path[k] → path[k+1]）の始まりと終わり（頂点に着く）時刻
func _seg_start(k: int) -> float:
	return T.fire if k == 0 else FIRST + STEP * float(k - 1)

func _seg_end(k: int) -> float:
	return FIRST + STEP * float(k)

## 弾が止まる時刻（最初の頂点から一人の胸へ）
func _stop_time() -> float:
	return _seg_end(COUNT + 1)

func _build() -> void:
	b_back = batch(back, false)
	b_back_add = batch(back)
	b_mid = batch(mid, false)
	# 性能（2026-11-23）: 四人ぶんの深紅の弾けを1枚の矩形にまとめて描く（4枚を重ねると同じ所を何度も計算し、1920×1080 で重い）
	blasts.append(blast_quad(front, CRIMSON_INK, INK_SMOKE, {"amp": 16., "k": .08, "seed": 3.0, "glow": .7, "glow_col": Vector3(.95, .15, .25), "glow_r": 18.}))
	ring = ring_quad(front, RBMHeroFx.A4_RED, {"squash": .36, "breakup": .5, "seed": 2.0, "glow": .5, "glow_col": Vector3(.95, .15, .25)})
	ring2 = ring_quad(front, RBMHeroFx.A4_DARK, {"squash": .36, "breakup": .55, "seed": 3.7, "glow": .3, "glow_col": Vector3(.95, .15, .25)})
	b_add = batch(front)
	b_front = batch(front, false)
	var top := Node2D.new()
	top.name = "GentlemanRicochetTop"
	top.z_as_relative = false
	top.z_index = 20
	add_child(top)
	b_top = batch(top)
	_make_path()

## 星の中心（四人の胸の高さの中心）と半径（五本の線が四人の胸のそばを通る大きさ。線は中心から半径×cos72° を通る）
func _star() -> Dictionary:
	var pc := party_center() + Vector2(0, -18)
	var sum := 0.0
	var n := 0
	for i in range(mini(targets.size(), 4)):
		if present[i]:
			sum += target_chest(i).distance_to(pc)
			n += 1
	var r := clampf((sum / maxf(1.0, float(n))) / cos(deg_to_rad(72.0)), 90.0, 150.0) if n > 0 else 115.0
	return {"c": pc, "r": r}

## 弾の道: 銃口 → 星の右の頂点 → 一つ飛ばしに五本 → 最初の頂点 → 一番近い一人の胸（ここで止まる）。体を貫く所も決める。
func _make_path() -> void:
	path.clear()
	passes.clear()
	var st := _star()
	var c: Vector2 = st.c
	var r: float = st.r
	var verts: Array = []
	for j in range(5):
		var v := c + Vector2.from_angle(-PI * 0.5 + TAU * j / 5.0) * Vector2(r, r * 0.92)
		verts.append(Vector2(clampf(v.x, 12.0, 628.0), clampf(v.y, 14.0, 300.0)))
	# 紳士の側（右）の頂点から入る（道を作る時はまだ足元が決まっていないので、銃口ではなく右端で選ぶ）
	var start := 0
	for j in range(5):
		if Vector2(verts[j]).x > Vector2(verts[start]).x:
			start = j
	path.append(foot + MUZZLE * UNIT)
	for k in range(COUNT + 1):
		path.append(verts[(start + 2 * k) % 5])
	# 体を貫く所: 星の線が胸のそばを通る所（線ごと・相手ごとに一番近い点）。どの線も近くを通らない相手は、一番近い線で貫く
	var live: Array = []
	for i in range(mini(targets.size(), 4)):
		if present[i]:
			live.append(i)
	var best := {}
	for k in range(1, COUNT + 1):
		var a: Vector2 = path[k]
		var b: Vector2 = path[k + 1]
		for i in live:
			var ch := target_chest(i)
			var u := clampf((ch - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
			var p := a.lerp(b, u)
			var d := p.distance_to(ch)
			var ps := {"t": lerpf(_seg_start(k), _seg_end(k), u), "who": i, "p": p, "seg": k}
			if d <= PASS_NEAR:
				passes.append(ps)
			if not best.has(i) or d < float(best[i].d):
				ps["d"] = d
				best[i] = ps
	# 最後: 最初の頂点から一番近い一人の胸へ跳ね返り、食い込んで止まる
	var v0: Vector2 = path.back()
	last_target = -1
	for i in live:
		if last_target < 0 or target_chest(i).distance_to(v0) < target_chest(last_target).distance_to(v0):
			last_target = i
	if last_target >= 0:
		path.append(target_chest(last_target))
		passes.append({"t": _stop_time(), "who": last_target, "p": target_chest(last_target), "seg": COUNT + 1})
	else:
		path.append(v0)
	for i in live:
		var found := false
		for ps in passes:
			if int(ps.who) == i:
				found = true
		if not found and best.has(i):
			passes.append(best[i])
	passes.sort_custom(func(x, y): return float(x.t) < float(y.t))

## 時刻 t の弾の位置と区間（撃つ前は空。止まった後は食い込んだ胸）
func _bullet(t: float) -> Dictionary:
	if t < T.fire:
		return {}
	if t >= _stop_time():
		return {"p": path.back(), "seg": COUNT, "stopped": true}
	for k in range(COUNT + 2):
		var t0 := _seg_start(k)
		var t1 := _seg_end(k)
		if t >= t0 and t < t1:
			var u := (t - t0) / maxf(0.001, t1 - t0)
			return {"p": Vector2(path[k]).lerp(path[k + 1], u), "seg": k}
	return {}

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_mid.reset(); b_add.reset(); b_front.reset(); b_top.reset()
	if path.is_empty():
		_make_path()
	# 銃口は今の足元から（道を作った時はまだ足元が決まっていない）
	path[0] = foot + MUZZLE * UNIT
	var a := t - T.impact
	var pc := party_center()
	var slow := RBMHeroFx.env(t, T.fire + 0.04, T.fire + 0.14, T.click, T.impact)
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.aim, 0.18], [T.fire, 0.24], [T.fire + 0.14, 0.4], [T.click, 0.44], [T.impact + 0.04, 0.22], [T.end - 0.4, 0.04], [T.end, 0.0]])
	view["dim_col"] = Color(0.02, 0.0, 0.02)
	set_post({"vig": 0.15 + 0.35 * RBMHeroFx.env(t, T.aim, T.fire + 0.1, T.impact, T.end - 0.3), "vig_col": Vector3(.1, .0, .02), "vig_r": .3, "desat": 0.82 * slow})
	# 構え: 銃身に光が走る
	var gun := foot + MUZZLE * UNIT
	var gl := RBMHeroFx.env(t, T.glint, T.glint + 0.05, T.glint + 0.1, T.glint + 0.2)
	if gl > 0.0:
		star(b_add, gun + Vector2(10, 1), gl, 4, 7, 9.0, 0.8, [Color(PALE, 0.95), Color(ROSE, 0.5)])
	# 撃つ: 大きな銃火・本体の閃き
	muzzle(b_add, gun, Vector2.LEFT, t - T.fire, 2.2)
	if t >= T.fire and t < T.fire + 0.1:
		RBMHeroRooftop.glow(b_add, gun, 22.0 * (1.0 - (t - T.fire) / 0.1), Color(1.0, 0.75, 0.45, 0.4))
		set_post({"flash": 0.07 * (1.0 - (t - T.fire) / 0.1)})
	view["shake"] += hit_shake(t - T.fire, 6.0, 90.0, 0.2)
	view["hero"]["flash"] = 0.2 * (1.0 - RBMHeroFx.ramp(t - T.fire, 0.0, 0.08)) if t >= T.fire else 0.0
	view["hero"]["flash_col"] = Color(1.0, 0.85, 0.6)
	# 止まった時間の中で、空気の塵が浮いたまま
	if slow > 0.0:
		for i in range(46):
			var p := Vector2(20.0 + 600.0 * RBMHeroFx.r(i, 11), 30.0 + 230.0 * RBMHeroFx.r(i, 12)) + Vector2(sin(t * 0.6 + i) * 2.0, -t * 1.5)
			b_add.dot_px(p, 1.0, Color(PALE, 0.35 * slow * (0.5 + 0.5 * RBMHeroFx.r(i, 13))))
	# 弾と軌跡（五芒星）
	var bl := _bullet(t)
	var passed := int(bl.get("seg", -1))
	var stopped := bool(bl.get("stopped", false))
	var trail_on := 1.0 if t < T.impact else 0.0
	var white := RBMHeroFx.env(t, T.click, T.click + 0.02, T.impact - 0.01, T.impact)
	var tc := Color(RED, 0.8).lerp(Color(PALE, 1.0), white)
	for i in range(mini(passed + 1, path.size() - 1)):
		var p0: Vector2 = path[i]
		var p1: Vector2 = path[i + 1]
		if i == passed and not stopped:
			p1 = bl.p
		# 銃口から最初の頂点までは細く淡く（星の線を主役に）
		var main := 0.85 if i > 0 else 0.45
		b_top.line(p0, p1, 2.6, Color(tc, 0.14 * trail_on), Color(tc, 0.14 * trail_on))
		b_top.line(p0, p1, 0.8, Color(tc, main * trail_on), Color(tc, main * trail_on))
	if not bl.is_empty() and t < T.impact:
		var p: Vector2 = bl.p
		if stopped:
			# 一人の胸に食い込んで止まった弾: 赤く脈打つ
			var pulse := 0.7 + 0.3 * absf(sin(t * 14.0))
			RBMHeroRooftop.glow(b_top, p, 7.0 * pulse, Color(RED, 0.6))
			RBMHeroRooftop.glow(b_top, p, 2.5, Color(PALE, pulse))
		else:
			var seg: int = bl.seg
			var dir := (Vector2(path[seg + 1]) - Vector2(path[seg])).normalized()
			b_top.streak(p - dir * 42.0, p, 3.0, Color(PALE, 1.0), Color(RED, 0.0))
			RBMHeroRooftop.glow(b_top, p, 6.0, Color(ROSE, 0.55))
			RBMHeroRooftop.glow(b_top, p, 2.5, Color(PALE, 1.0))
	# 頂点で跳ね返る（火花・小さな輪・閃き）
	for k in range(COUNT + 1):
		var age := t - _seg_end(k)
		var p: Vector2 = path[k + 1]
		if age < 0.0 or age >= 0.45:
			continue
		var din := (p - Vector2(path[k])).normalized()
		var dout := (Vector2(path[k + 2]) - p).normalized() if k + 2 < path.size() else -din
		sparks(b_top, p, age, 0.45, 26, 200 + k * 7, 180.0, PALE, ROSE, (dout - din).angle(), 1.6, 100.0, 1.3)
		var rr := 2.0 + 12.0 * RBMHeroFx.ramp(age, 0.0, 0.22)
		var fa := 1.0 - RBMHeroFx.ramp(age, 0.05, 0.28)
		for sg in range(12):
			var q0 := p + Vector2.from_angle(TAU * sg / 12.0) * rr
			var q1 := p + Vector2.from_angle(TAU * (sg + 1) / 12.0) * rr
			b_top.line(q0, q1, 0.7, Color(PALE, 0.8 * fa), Color(PALE, 0.8 * fa))
		star(b_top, p, (1.0 - RBMHeroFx.ramp(age, 0.0, 0.16)), 4, 30 + k, 7.0, 0.8, [Color(PALE, 1.0), Color(ROSE, 0.6)])
	# 体を貫く（深紅の筋・飛沫）。筋は時間が戻るまで残る
	for ps in passes:
		var pa: float = t - float(ps.t)
		var k: int = ps.seg
		var dc := (Vector2(path[k + 1]) - Vector2(path[k])).normalized()
		var c: Vector2 = ps.p
		if pa >= 0.0 and pa < 0.55:
			sparks(b_top, c, pa, 0.55, 24, 300 + k * 7 + int(ps.who), 160.0, ROSE, RED, dc.angle(), 0.9, 150.0, 1.3)
		if pa >= 0.0 and t < T.impact + 0.1:
			var n := Vector2(-dc.y, dc.x)
			var f := 1.0 - RBMHeroFx.ramp(t, T.impact, T.impact + 0.1)
			b_top.line(c - dc * 5.0 - n * 2.0, c + dc * 5.0 + n * 2.0, 1.2, Color(ROSE, f), Color(RED, f))
	ally_hits(t, hits(), 0.45)
	# 帽子のつばに触れる: 小さな閃き
	var ck := t - T.click
	if ck >= 0.0 and ck < 0.18:
		star(b_add, foot + BRIM * UNIT, 1.0 - ck / 0.18, 4, 41, 10.0, 0.9, [Color(PALE, 1.0), Color(ROSE, 0.6)])
	# 時間が戻る: 星が砕け、四人が同時に撃ち抜かれる
	if a >= 0.0:
		for i in range(path.size() - 1):
			var p0: Vector2 = path[i]
			var p1: Vector2 = path[i + 1]
			for k in range(4):
				var q := p0.lerp(p1, (k + 0.5) / 4.0)
				shards(b_front, q, a, 0.7, 2, 500 + i * 13 + k, 90.0, 2.2, Color(PALE, 0.95), Color(RED, 0.9), 220.0)
		var q: ColorRect = blasts[0]
		var fin := 1.0 - RBMHeroFx.ramp(a, 0.25, 0.65)
		var data := PackedVector4Array()
		for i in range(4):
			if present[i]:
				data.append_array(blobs(target_chest(i), a, 12, 60 + i * 7, 20.0, 16.0, 9.0, 10.0, .5, .4, 8.5))
		q.visible = fin > 0.0 and not data.is_empty()
		if q.visible:
			show_blast(q, data, a, {"flow": a * .4, "cool": .05 + RBMHeroFx.ramp(a, .1, .6) * .2, "erode": RBMHeroFx.ramp(a, .1, .65), "fade": fin, "erode_noise": .5,
				"polar": 0.0, "detail": .7, "amp": 16.0, "tone_cap": 1.0})
		for i in range(4):
			if present[i]:
				sparks(b_add, target_chest(i), a, 0.6, 40, 70 + i * 9, 260.0, PALE, RED, 0.0, TAU, 160.0, 1.5)
		show_ring(ring, pc + Vector2(0, -6), a, 0.6, 200.0, 7.0, 6.0, 0.02)
		show_ring(ring2, pc + Vector2(0, -6), a - 0.06, 0.65, 160.0, 5.0, 5.5, 0.0)
		refract_wave(pc + Vector2(0, -16), a, 0.6, 260.0, 5.5, 0.03)
		ally_light(RBMHeroFx.env(a, 0.0, 0.03, 0.2, 0.6), RED, 0.0)
		set_post({"flash": 0.14 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.08)), "chroma": 0.005 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.25))})
		view["shake"] += hit_shake(a, 12.0, 80.0, 0.45)
		var finals: Array = []
		for i in range(4):
			if present[i]:
				finals.append([T.impact, i])
		ally_hits(t, finals, 1.1)
	else:
		(blasts[0] as ColorRect).visible = false
		ring.visible = false
		ring2.visible = false
	b_back.commit(); b_back_add.commit(); b_mid.commit(); b_add.commit(); b_front.commit(); b_top.commit()
