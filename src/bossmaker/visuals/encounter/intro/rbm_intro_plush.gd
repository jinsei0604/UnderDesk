extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## つぎはぎのぬいぐるみ（plush）の登場「縫い直し」（2026-11-17 初版、2026-11-19 ユーザーの指摘で部位ごとの糸に作り直し、
## 同日「糸を縫い付ける演出（初版の針）もいれて」で針が縫い目を縫って回る形を足した。表示専用。戦闘の状態・乱数・保存データには触れない）。
## 意味: 裁縫部屋の床に、頭・胴・両腕・両足がバラバラに散らばっている → 胴の縫い目から部位ごとに赤い糸が飛び、それぞれの部位を刺す
## → 糸が張って、足・腕・頭の順に引き寄せられる（足が付くと胴が立ち上がる）→ 付いた所を、赤い糸を通した1本の針が縫い目に沿って
## 3針ずつ縫い付けて回る（1針ごとに体がびくっと動き、縫い跡が1つずつ増える）→ 頭を縫い終えると針が上へ抜け、糸がぷつっと切れる
## → 全身がそろい、色が戻り、ボタンの目が一瞬だけ赤く光る（覚醒後の不気味さの予告）→ かわいく手を振る → 立ち姿・題字。
## 部位の絵は立ち姿（poses.png のコマ 0）を輪郭で切り分けた物（assets_bossmaker/battle/plush/intro_parts/、
## tools/plush/bake_intro_parts.gd が作る。6つを重ねるとコマ 0 と画素が一致する）。部位は動かすだけで、伸縮・回転しない。
## 全部そろった所で立ち姿のコマ 0 に替える（同じ絵なので見た目は変わらない）。手を振るのは全体攻撃のコマ（57/53）。
## 最後の立ち姿は戦闘中の立ち姿と同じ絵・同じ足元。カメラは寄らない（揺れだけ）。
## 音は1本（assets_bossmaker/audio/plush/intro.wav、tools/plush/audio/build.mjs。演出の0秒＝音の0秒）。

const Data = preload("res://src/bossmaker/visuals/plush/rbm_plush_data.gd")
const ATLAS_PATH := "res://assets_bossmaker/battle/plush/poses.png"
const PARTS_ROOT := "res://assets_bossmaker/battle/plush/intro_parts/"
## 糸で引き寄せる順（足 → 腕 → 頭）。胴は最初から真ん中にあり、足が付くと立ち上がる。
const ORDER := ["leg_l", "leg_r", "arm_l", "arm_r", "head"]
const SOUNDS := ["game:plush/intro"]
const EXTRA_PATHS := [ATLAS_PATH, PARTS_ROOT + "torso.png", PARTS_ROOT + "head.png", PARTS_ROOT + "arm_l.png", PARTS_ROOT + "arm_r.png", PARTS_ROOT + "leg_l.png", PARTS_ROOT + "leg_r.png"]
## 演出の0秒（画面が黒から出る所。fade_in と同じ）
const LEAD := 0.36
## 構えた後、題字を読めるだけ待つ
const HOLD := 0.3
## 時刻（演出の秒）。音（tools/plush/audio/build.mjs）もここを読む。shoot・pull・travel・sew は ORDER の順。
## sew は針がその縫い目の1針目を刺す時刻。1針ごとに stitch 秒（3針）。needle_in は針が飛んでくる時刻、needle_out は抜けて上へ飛ぶ時刻、snap は糸が切れる時刻。
const T := {
	"shoot": [0.5, 0.57, 0.64, 0.71, 0.78], "shot": 0.22, "tighten": 0.95,
	"pull": [1.05, 1.42, 1.79, 2.16, 2.53], "travel": [0.24, 0.24, 0.24, 0.24, 0.32],
	"needle_in": 1.0, "sew": [1.3, 1.67, 2.04, 2.41, 2.86], "stitch": 0.1, "needle_out": 3.16, "snap": 3.4,
	"whole": 3.2, "alive": 3.25, "eye": 3.55, "wave": [3.95, 4.15, 4.35], "settle": 4.55, "title": 4.05, "end": 5.1
}
## 1つの縫い目の針の数
const STITCHES := 3
## 針が飛んでくる所（画面の右上）
const NEEDLE_FROM := Vector2(1180, 110)
## バラバラの時の置き場所（組み上がった位置からのずれ。ステージの画素）。床に寝かせるように、部位の下端を床の高さへ。
const SCATTER := {
	"torso": Vector2(0, 19), "head": Vector2(-160, 104), "arm_l": Vector2(-57, 41), "arm_r": Vector2(90, 30),
	"leg_l": Vector2(-62, 20), "leg_r": Vector2(54, 18),
}
## 縫い目の点（コマ 0 の中の画素。胴と部位の両方に入る輪郭の中心。bake_intro_parts.gd が出す値）
const SEAM := {"head": Vector2(50, 73), "arm_l": Vector2(17, 100), "arm_r": Vector2(77, 107), "leg_l": Vector2(39, 147), "leg_r": Vector2(69, 146)}
## 縫い目の向き（縫い跡の並ぶ向き）
const SEAM_DIR := {"head": Vector2(1, 0), "arm_l": Vector2(0, 1), "arm_r": Vector2(0, 1), "leg_l": Vector2(1, 0.3), "leg_r": Vector2(1, -0.3)}
## 引き寄せる時に浮く高さ（頭は高く持ち上げてから下ろす）
const HOP := {"head": 46.0, "arm_l": 18.0, "arm_r": 18.0, "leg_l": 12.0, "leg_r": 12.0}
const STAND := 0
const WAVE_POSES := [57, 53, 57]
## 足元からの相対（立ち姿のコマ。右の赤茶のボタンの目）
const EYE_RIGHT := Vector2(13, -128)
## 立ち姿のコマの左上（足元からの相対。ANIMATION.frames[0].offset と同じ）
const FRAME_OFFSET := Vector2(-55, -170)
const THREAD := Color("#b8323f")
const NEEDLE := Color("#d8dde6")
const NEEDLE_DARK := Color("#7d8796")
const FLUFF := Color("#eee0bb")

var _atlas: Texture2D
var _parts := {}
var _foot := Vector2.ZERO
var _te := 0.0
var _shake := Vector2.ZERO

func prepare() -> void:
	super.prepare()
	_atlas = load(ATLAS_PATH) as Texture2D
	for part in ["torso"] + ORDER:
		_parts[part] = load(PARTS_ROOT + part + ".png") as Texture2D
	_foot = p.boss_foot()
	bs = {"pose": 0, "foot": _foot}

func duration() -> float:
	return LEAD + float(T.end) + HOLD

## 部位の i 番目（ORDER の順）の引き寄せの進み具合（0＝置き場所、1＝付いた）
static func pull_k(i: int, t: float) -> float:
	var a := float(T.pull[i])
	var u := clampf((t - a) / float(T.travel[i]), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

## 部位の組み上がった位置からのずれ（t 秒）
static func part_offset(part: String, t: float) -> Vector2:
	if part == "torso":
		# 両足が付く間に立ち上がる
		var u := clampf((t - float(T.pull[0])) / (float(T.pull[1]) + float(T.travel[1]) - float(T.pull[0])), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		return Vector2(SCATTER["torso"]) * (1.0 - u)
	var i := ORDER.find(part)
	var k := pull_k(i, t)
	var off: Vector2 = Vector2(SCATTER[part]).lerp(Vector2.ZERO, k)
	off.y -= sin(k * PI) * float(HOP[part])
	return off.round()

## 部位が付く時刻（ORDER の順）
static func arrival_times() -> Array:
	var out: Array = []
	for i in range(ORDER.size()):
		out.append(float(T.pull[i]) + float(T.travel[i]))
	return out

## 針が刺す時刻（全部の縫い目の全部の針。ORDER の順）
static func stitch_times() -> Array:
	var out: Array = []
	for i in range(ORDER.size()):
		for k in range(STITCHES):
			out.append(float(T.sew[i]) + float(T.stitch) * k)
	return out

## t 秒（演出の秒）の本体のコマ。全部そろうまでは -1（部位を別々に描く）
static func frame_at(t: float) -> int:
	var wa: Array = T.wave
	if t < float(T.whole):
		return -1
	if t < float(wa[0]):
		return STAND
	if t < float(wa[1]):
		return WAVE_POSES[0]
	if t < float(wa[2]):
		return WAVE_POSES[1]
	if t < float(T.settle):
		return WAVE_POSES[2]
	return STAND

func _rect(id: int) -> Rect2:
	var r: Array = Data.ANIMATION.frames[id].rect
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))

func _top_left(id: int) -> Vector2:
	var o: Array = Data.ANIMATION.frames[id].offset
	return (_foot + _shake + Vector2(float(o[0]), float(o[1]))).round()

## 部位の左上（ステージの画素）
func _part_top_left(part: String, t: float) -> Vector2:
	var off := part_offset(part, t)
	if t >= float(T.pull[0]) or part == "torso":
		off += _shake
	return (_foot + FRAME_OFFSET + off).round()

## 縫い目の点（部位の側・胴の側）
func _seam_on(part: String, owner: String, t: float) -> Vector2:
	return _part_top_left(owner, t) + Vector2(SEAM[part]) + Vector2(0.5, 0.5)

## 縫い目の k 番目の針の点（組み上がった体の上。縫い目の向きに 7 画素ずつ）
func _stitch_point(i: int, k: int) -> Vector2:
	var part: String = ORDER[i]
	var d: Vector2 = Vector2(SEAM_DIR[part]).normalized()
	return (_foot + _shake + FRAME_OFFSET + Vector2(SEAM[part]) + d * 7.0 * float(k - 1)).round() + Vector2(0.5, 0.5)

## 針の位置と向き（t 秒）。出ていなければ空。初版の針の縫い方: 刺した所で一瞬止まり、浮き上がって次の点へ移る。
func _needle(te: float) -> Array:
	var sew: Array = T.sew
	var st := float(T.stitch)
	var first := _stitch_point(0, 0)
	if te < float(T.needle_in):
		return []
	if te < float(sew[0]):
		# 右上から弧を描いて最初の縫い目へ飛んでくる
		var u := RBMHeroFx.ramp(te, float(T.needle_in), float(sew[0]))
		u = u * u * (3.0 - 2.0 * u)
		var mid := NEEDLE_FROM.lerp(first, 0.5) + Vector2(0, -80)
		var a := NEEDLE_FROM.lerp(mid, u)
		var b := mid.lerp(first, u)
		var dir := (b - a).normalized() if a.distance_to(b) > 0.5 else (first - NEEDLE_FROM).normalized()
		return [a.lerp(b, u), dir]
	for i in range(ORDER.size()):
		var s0 := float(sew[i])
		var e0 := s0 + st * STITCHES
		var next_start := float(sew[i + 1]) if i + 1 < ORDER.size() else float(T.needle_out)
		if te < s0 or te >= next_start:
			continue
		if te < e0:
			# k 針目: 刺す（一瞬止まる）→ 浮き上がって次の点へ
			var k := mini(int((te - s0) / st), STITCHES - 1)
			var a := te - s0 - st * k
			var here := _stitch_point(i, k)
			var there := _stitch_point(i, k + 1) if k + 1 < STITCHES else here + Vector2(6, -10)
			if a < st * 0.3:
				return [here, Vector2(0.45, 1.0).normalized()]
			var u := RBMHeroFx.ramp(a, st * 0.3, st)
			var lift := sin(u * PI) * 10.0
			var pos := here.lerp(there, u) + Vector2(0, -lift)
			return [pos, (there - here + Vector2(0, -lift)).normalized() if here.distance_to(there) > 0.5 else Vector2(0, -1)]
		# 次の縫い目へ跳ぶ（弧）。最後の後は上へ抜ける所へ
		var from := _stitch_point(i, STITCHES - 1) + Vector2(6, -10)
		var to := _stitch_point(i + 1, 0) if i + 1 < ORDER.size() else from
		var u2 := RBMHeroFx.ramp(te, e0, next_start)
		var lift2 := sin(u2 * PI) * 26.0
		return [from.lerp(to, u2) + Vector2(0, -lift2), (to - from).normalized() if from.distance_to(to) > 0.5 else Vector2(0, -1)]
	# 頭を縫い終えたら真上へ抜ける
	var last := _stitch_point(ORDER.size() - 1, STITCHES - 1) + Vector2(6, -10)
	var u3 := RBMHeroFx.ramp(te, float(T.needle_out), float(T.snap))
	if u3 >= 1.0:
		return []
	return [last.lerp(Vector2(last.x + 20.0, -40.0), u3 * u3), Vector2(0.1, -1.0).normalized()]

func advance(t: float, _dt: float) -> void:
	fade_in(t, LEAD, 0.25)
	bars(t, 0.30)
	p.se(LEAD, "game:plush/intro", 1.0)
	var te := maxf(0.0, t - LEAD)
	_te = te
	# 部位が付くたび・縫う1針ごとに、付いた体が小さく揺れる（びくっと引かれる）
	_shake = Vector2.ZERO
	for at in stitch_times() + arrival_times():
		var a := te - float(at)
		if a >= 0.0 and a < 0.07:
			_shake = Vector2(2.0 if int(a * 60.0) % 2 == 0 else -2.0, 0.0)
	# 部屋が少し暗い → そろうと明るさが戻る
	dark_bg = 0.32 * (1.0 - RBMHeroFx.ramp(te, float(T.alive), float(T.settle)))
	dark_bg_color = Color(0.03, 0.02, 0.04)
	# 体の色: 命の無い間は色が褪せている → そろうと戻る
	var life := RBMHeroFx.ramp(te, float(T.alive), float(T.alive) + 0.35)
	bs = {"pose": 0, "foot": _foot, "mod": Color(0.6, 0.58, 0.62).lerp(Color.WHITE, life)}
	white = 0.0
	eye = 0.0
	# 頭が付いた時の小さな揺れ（カメラ）
	var la := te - (float(T.pull[4]) + float(T.travel[4]))
	if la >= 0.0 and la < 0.25:
		var k := 1.0 - la / 0.25
		p.camera._offset = (Vector2(sin(la * 70.0), cos(la * 55.0) * 0.5) * 6.0 * k * k * p.camera.shake_strength()).snapped(Vector2(2, 2))
	else:
		p.camera._offset = Vector2.ZERO
	p.camera.apply()
	p.at(LEAD + float(T.whole), "plush_whole", func(): allies_brace(true, 2.0))
	p.at(LEAD + float(T.settle), "plush_relax", func(): allies_brace(false))
	title_card(t, LEAD + float(T.title), Color(0.9, 0.55, 0.5))
	p.body.queue_redraw()
	p.top.queue_redraw()

## 描く順: バラバラの間は奥（下端が上）から手前へ。動いている部位はいちばん前。
func _draw_order(te: float) -> Array:
	var order: Array = ["arm_l", "arm_r", "torso", "head", "leg_r", "leg_l"]
	for i in range(ORDER.size()):
		var k := pull_k(i, te)
		if k > 0.0 and k < 1.0:
			order.erase(ORDER[i])
			order.append(ORDER[i])
	return order

## 本体: バラバラの部位、またはそろった後の承認済みのコマを、等倍・足元で描く（伸縮・回転しない）
func draw_body(ci: CanvasItem) -> void:
	var mod: Color = bs.get("mod", Color.WHITE)
	var id := frame_at(_te)
	if id >= 0:
		if _atlas != null:
			ci.draw_texture_rect_region(_atlas, Rect2(_top_left(id), _rect(id).size), _rect(id), mod)
		return
	for part in _draw_order(_te):
		var tex: Texture2D = _parts.get(part)
		if tex != null:
			ci.draw_texture(tex, _part_top_left(part, _te), mod)

func draw_flat(_ci: CanvasItem) -> void:
	pass

func extra_top(ci: CanvasItem) -> void:
	var te := _te
	var whole := te >= float(T.whole)
	# 糸: 胴の縫い目から部位ごとに飛ぶ（先に小さな針）→ たるんだ糸が張る → 引き寄せる間は縮む → 付いたら縫い跡になる
	for i in range(ORDER.size()):
		var part: String = ORDER[i]
		var s := float(T.shoot[i])
		if te < s or whole:
			continue
		var arrive := float(T.pull[i]) + float(T.travel[i])
		if te >= arrive:
			continue
		var from := _seam_on(part, "torso", te)
		var to := _seam_on(part, part, te)
		var grow := RBMHeroFx.ramp(te, s, s + float(T.shot))
		var tip := from.lerp(to, grow)
		# たるみ（張る前は下へ垂れる）
		var slack := 1.0 - RBMHeroFx.ramp(te, float(T.tighten) + 0.03 * i, float(T.pull[i]))
		var sag := 10.0 * slack * grow
		var pts := PackedVector2Array()
		for k in range(9):
			var u := float(k) / 8.0
			var q := from.lerp(tip, u) + Vector2(0, sin(u * PI) * sag)
			pts.append(q.round())
		ci.draw_polyline(pts, THREAD, 2.0)
		# 飛んでいる間は先に小さな針
		if grow < 1.0:
			var dir := (to - from).normalized()
			ci.draw_line(tip - dir * 12.0, tip, NEEDLE_DARK, 2.0)
			ci.draw_line(tip - dir * 12.0, tip - dir * 2.0, NEEDLE, 1.0)
		# 刺した瞬間の小さな光
		var pa := te - (s + float(T.shot))
		if pa >= 0.0 and pa < 0.12:
			glow(ci, to, 1.0 - pa / 0.12, Color(1, 0.95, 0.9))
	# 縫い跡（赤い糸の短い縫い目。針が刺すたびに1つずつ増え、色が戻った後に消える）
	var mark_fade := 1.0 - RBMHeroFx.ramp(te, float(T.alive) + 0.2, float(T.alive) + 0.8)
	if mark_fade > 0.0:
		for i in range(ORDER.size()):
			for k in range(STITCHES):
				var at := float(T.sew[i]) + float(T.stitch) * k
				if te < at:
					continue
				var m := _stitch_point(i, k).round()
				ci.draw_line(m + Vector2(-3, -2), m + Vector2(3, 2), Color(THREAD, mark_fade), 2.0)
				ci.draw_line(m + Vector2(-3, 2), m + Vector2(3, -2), Color(THREAD, mark_fade), 2.0)
				var ga := te - at
				if ga < 0.1:
					glow(ci, m, 1.0 - ga / 0.1, Color(1, 0.95, 0.9))
	# 縫う糸: 針の糸穴から、最後に刺した点まで（飛んでくる間は後ろにたなびく）。針が上へ抜けると張って、切れて縮む
	var needle := _needle(te)
	var last_stitch := Vector2.INF
	for at_i in range(ORDER.size()):
		for k in range(STITCHES):
			if te >= float(T.sew[at_i]) + float(T.stitch) * k:
				last_stitch = _stitch_point(at_i, k)
	if not needle.is_empty():
		var npos: Vector2 = needle[0]
		var ndir: Vector2 = needle[1]
		var eye_pt := npos - ndir * 24.0
		if last_stitch == Vector2.INF:
			ci.draw_line(eye_pt - ndir * 34.0 + Vector2(0, 8), eye_pt, THREAD, 2.0)
		elif te < float(T.snap):
			ci.draw_line(last_stitch, eye_pt, THREAD, 2.0)
		# 針（細い銀の線と、糸を通す小さな輪）
		ci.draw_line(npos - ndir * 26.0, npos, NEEDLE_DARK, 3.0)
		ci.draw_line(npos - ndir * 26.0, npos - ndir * 2.0, NEEDLE, 1.0)
		ci.draw_arc(npos - ndir * 28.0, 2.5, 0.0, TAU, 10, NEEDLE_DARK, 1.0)
	# 糸が切れる所の小さな光と、上へ縮む切れ端
	var sa := te - float(T.snap)
	if sa >= 0.0 and sa < 0.25 and last_stitch != Vector2.INF:
		var end := last_stitch.lerp(last_stitch + Vector2(4, -30), RBMHeroFx.ramp(sa, 0.0, 0.2))
		ci.draw_line(last_stitch, end, Color(THREAD, 1.0 - sa / 0.25), 2.0)
		if sa < 0.12:
			glow(ci, end, 1.0 - sa / 0.12, Color(1, 0.9, 0.85))
	# 部位が付くたびに舞う綿のくず（ゆっくり落ちる）
	for i in range(ORDER.size()):
		var part: String = ORDER[i]
		var aa := te - (float(T.pull[i]) + float(T.travel[i]))
		if aa < 0.0 or aa > 1.0:
			continue
		var c := _foot + FRAME_OFFSET + Vector2(SEAM[part])
		for j in range(6):
			var r1 := RBMHeroFx.r(j + i * 7, 301)
			var r2 := RBMHeroFx.r(j + i * 7, 302)
			var vel := Vector2((r1 - 0.5) * 80.0, -40.0 - 40.0 * r2)
			var pos := c + vel * minf(aa, 0.3) + Vector2(sin(aa * 4.0 + j) * 5.0, maxf(0.0, aa - 0.3) * 20.0)
			var fa := 1.0 - RBMHeroFx.ramp(aa, 0.5 + 0.4 * r2, 1.0)
			ci.draw_rect(Rect2(pos.round(), Vector2(2, 2) * (1.0 + float(j % 2))), Color(FLUFF, 0.9 * fa))
	# ボタンの目が一瞬だけ赤く光る（覚醒後の予告。小さな光で、画面の20%よりずっと小さい）
	var ea := te - float(T.eye)
	if ea >= 0.0 and ea < 0.4:
		var k := RBMHeroFx.env(ea, 0.0, 0.04, 0.16, 0.4)
		glow(ci, _foot + EYE_RIGHT, k, Color(1.0, 0.18, 0.2))

## 目の位置（共通の目の光で使う。ここでは使わない）
func eye_points() -> Array:
	return [_foot + EYE_RIGHT]
