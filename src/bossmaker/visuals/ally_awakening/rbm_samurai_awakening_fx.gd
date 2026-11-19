extends RBMHeroFxBase
## 侍の覚醒「墨風・一閃」（2026-11-19 第2版。表示専用）。時刻は T（音の build もここを読む）。座標は論理ドット（足元からの相対）。
## 前の版（rbm_samurai_awakening.gd）の「張りつめる → 止まる → 一閃」の流れは残し（ユーザー「侍は少しまし」）、描き方を作り直した。
## 本体は目を閉じて立ったまま（s:18。ユーザー「前の目をつむって立った状態に」）。抜刀は見えない速さで、一閃・墨・納刀の光と音だけで見せる。
## 2026-11-19 ユーザー「全部ボスとのつながりが分かるように」「侍は機械武者」→ 機械武者の墨（黒い墨・濡れた艶・飛び散る墨の滴・白い刃の芯）を入れた。
## 意味: 目を閉じて立つ → 墨の筆の風が体を巻き、木の葉が舞う → 風が止まり、葉が宙で止まる。柄に添えた手元（鯉口）に光
## → 見えない抜刀: 画面を横切る墨の筆の一閃（白い刃の芯）、墨の滴が飛び散り、止まっていた葉が真っ二つに割れて飛ぶ → 墨が乾いて消える
## → 鯉口に小さな光（納刀の音と同時。目を閉じたまま刀が鞘に戻ったことを示す）。
## 三角のトゲ・星形・平たい円は使わない（筆の帯は ribbon シェーダー、墨の滴と葉は小さな画素）。

const T := {"crouch": 0.3, "still": 1.4, "release": 1.85, "sheathe": 2.9, "end": 3.5}
## 鯉口（s:18＝目を閉じて立つ姿の、柄に添えた両手の間）・一閃の高さ（柄の高さ。足元からの相対、論理ドット）
const KOIGUCHI := Vector2(4, -24)
const BLADE_Y := -24.0
const GREEN := Color("#a4f255")
const LEAF := Color("#5f9a3a")
const INK := Color("#060609")
const INK_GREY := Color("#3a3c42")
## 墨の筆の色（縁＝薄い墨 → 中＝黒 → 芯＝白い刃の光）
const INK_PAL := ["#2c2e34", "#141519", "#08080b", "#050507", "#050507", "#f6f4ec"]
## 風の墨（灰色だと弱く濁って見えたので、黒い墨を半透明で）
const WASH_PAL := ["#3a3c40", "#1c1e22", "#0c0d10", "#08080b", "#08080b", "#c8d0c4"]

var cut: RBMHeroFxRibbon
var swirls: Array = []
var b_ink: RBMHeroFxBatch
var b_leaf: RBMHeroFxBatch
var b_add: RBMHeroFxBatch

func _build() -> void:
	for i in range(3):
		swirls.append(ribbon(back, WASH_PAL, {"body": .8, "taper": .5, "skew": .8, "rough": .6, "rough_freq": 18., "streak": .5, "gain": 1.0, "glow": 0.0, "seed": 2.0 + i * 3.0}))
	cut = ribbon(back, INK_PAL, {"body": .8, "taper": .45, "skew": .55, "rough": .75, "rough_freq": 30., "streak": .45, "gain": 1.04, "glow": .35, "glow_col": Vector3(.32, .4, .3), "seed": 4.0})
	b_leaf = batch(front, false)
	b_ink = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_ink.reset(); b_leaf.reset(); b_add.reset()
	var ra := t - T.release
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.crouch + 0.4, 0.36], [T.still, 0.46], [T.release - 0.02, 0.56], [T.release + 0.25, 0.34], [T.end, 0.0]])
	view["dim_col"] = Color(0.03, 0.035, 0.03)
	_swirl(t)
	_leaves(t, ra)
	# 鯉口の光（止まった後。尖った星形ではなく、短い横の光の筋）
	var gl := RBMHeroFx.ramp(t, T.still + 0.15, T.release - 0.05) * (1.0 - RBMHeroFx.ramp(ra, -0.04, 0.0))
	if gl > 0.0 and ra < 0.0:
		var k := foot + KOIGUCHI
		b_add.streak(k - Vector2(6.0 * gl, 0), k + Vector2(6.0 * gl, 0), 1.2, Color(1, 1, 1, 0.9 * gl), Color(1, 1, 1, 0.0))
		b_add.streak(k + Vector2(6.0 * gl, 0), k - Vector2(6.0 * gl, 0), 1.2, Color(1, 1, 1, 0.9 * gl), Color(1, 1, 1, 0.0))
		RBMHeroRooftop.glow(b_add, k, 2.0 + 1.5 * gl, Color(1, 1, 1, 0.5 * gl))
	# 納刀: 鯉口に短い光（音の「チン」と同時。一瞬だけ）
	var sh := RBMHeroFx.burst(t - T.sheathe, 10.0) * (1.0 - RBMHeroFx.ramp(t, T.sheathe + 0.05, T.sheathe + 0.22)) if t >= T.sheathe else 0.0
	if sh > 0.0:
		var k2 := foot + KOIGUCHI
		b_add.streak(k2 - Vector2(4.0 * sh, 0), k2 + Vector2(4.0 * sh, 0), 1.0, Color(1, 1, 1, 0.8 * sh), Color(1, 1, 1, 0.0))
		b_add.streak(k2 + Vector2(4.0 * sh, 0), k2 - Vector2(4.0 * sh, 0), 1.0, Color(1, 1, 1, 0.8 * sh), Color(1, 1, 1, 0.0))
		RBMHeroRooftop.glow(b_add, k2, 1.5 + 1.0 * sh, Color(1, 1, 1, 0.4 * sh))
	# 抜刀: 墨の筆の一閃（頭が一瞬で右端へ走り、尾が追って乾くように消える）
	cut.visible = ra >= 0.0 and ra < 0.85
	if cut.visible:
		var a := foot + Vector2(-70, BLADE_Y + 2.0)
		var c := foot + Vector2(400, BLADE_Y - 8.0)
		cut.set_path(RBMHeroFx.bow(a, c, -5.0, 32), 9.0)
		sp(cut, {"head": RBMHeroFx.ramp(ra, 0.0, 0.05), "tail": RBMHeroFx.ramp(ra, 0.15, 0.75), "body": .8 * (1.0 - 0.45 * RBMHeroFx.ramp(ra, 0.05, 0.6)), "flow": ra * 2.0, "fade": 1.0 - RBMHeroFx.ramp(ra, 0.55, 0.85)})
	if ra >= 0.0:
		_splatter(ra)
		view["hero"]["flash"] = 0.55 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.18))
		view["hero"]["flash_col"] = Color(1, 1, 0.96)
		view["hero"]["lit"] = 0.3 * (1.0 - RBMHeroFx.ramp(ra, 0.15, 0.9))
		view["hero"]["lit_col"] = GREEN
		set_post({"flash": 0.12 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.08))})
	b_ink.commit(); b_leaf.commit(); b_add.commit()

## 墨の筆の風: 薄い墨の筆の帯が3本、体のまわりを巻きながら回る（だんだん遅く、止まると消える）
func _swirl(t: float) -> void:
	var on := RBMHeroFx.ramp(t, T.crouch, T.crouch + 0.3) * (1.0 - RBMHeroFx.ramp(t, T.still - 0.1, T.still + 0.15))
	for i in range(swirls.size()):
		var r: RBMHeroFxRibbon = swirls[i]
		r.visible = on > 0.01
		if not r.visible:
			continue
		# 回る速さは止まる直前に落ちる（回った角度は速さの積分）
		var st := minf(t, T.still) - T.crouch
		var spin := st * 4.2 - st * st * 0.9
		var a0 := spin + float(i) * TAU / 3.0
		var rad := Vector2(26.0 - 3.0 * float(i), 7.0 + 1.5 * float(i))
		var cy := -6.0 - 13.0 * float(i)
		var pts := PackedVector2Array()
		for k in range(25):
			var ang := a0 + 2.4 * float(k) / 24.0
			pts.append(foot + Vector2(cos(ang) * rad.x, cy + sin(ang) * rad.y))
		r.set_path(pts, 3.6)
		sp(r, {"head": 1.0, "tail": 0.0, "flow": t * 1.5, "fade": 0.75 * on})

## 木の葉: 風に乗って回る → 止まると宙で止まる → 一閃で真っ二つに割れて飛ぶ
func _leaf_pos(i: int, t: float) -> Vector2:
	var st := minf(t, T.still) - T.crouch
	var spin := st * (3.0 + RBMHeroFx.r(i, 12)) - st * st * 0.7
	var a := RBMHeroFx.r(i, 11) * TAU + spin
	var rad := 18.0 + 30.0 * RBMHeroFx.r(i, 13)
	return foot + Vector2(cos(a) * rad, -8.0 - 34.0 * RBMHeroFx.r(i, 14) + sin(a) * rad * 0.3)

func _leaves(t: float, ra: float) -> void:
	var on := RBMHeroFx.ramp(t, T.crouch, T.crouch + 0.4)
	if on <= 0.0:
		return
	for i in range(11):
		var col := LEAF.lerp(GREEN, 0.35 * RBMHeroFx.r(i, 15))
		var p := _leaf_pos(i, t)
		var ang := RBMHeroFx.r(i, 16) * TAU + minf(t, T.still) * 5.0
		var d := Vector2.from_angle(ang) * 1.1
		if ra < 0.06:
			_leaf(p, d, col, on)
			continue
		# 割れて飛ぶ（上下の半分が別々に。落ちながら消える）
		var u := ra - 0.06
		var f := 1.0 - RBMHeroFx.ramp(u, 0.4, 1.1)
		if f <= 0.0:
			continue
		var away := Vector2(1.0 + RBMHeroFx.r(i, 17), 0.0) * (30.0 + 40.0 * RBMHeroFx.r(i, 18)) * RBMHeroFx.burst(u, 5.0)
		for half in [-1.0, 1.0]:
			var hf := float(half)
			var q := p + away + Vector2(0, hf * (2.0 + 14.0 * RBMHeroFx.burst(u, 4.0)) + 40.0 * u * u)
			_leaf(q, d.rotated(hf * u * 6.0) * 0.7, col, f, true)

## 墨の滴: 一閃の線から上下へ飛び散り、落ちながら小さくなって消える（武者の墨と同じ黒と艶）
func _splatter(ra: float) -> void:
	var u := ra - 0.03
	if u < 0.0:
		return
	for i in range(34):
		var x := -10.0 + 220.0 * RBMHeroFx.r(i, 21)
		var born := 0.04 * x / 220.0
		var a := u - born
		if a < 0.0:
			continue
		var life := 0.5 + 0.5 * RBMHeroFx.r(i, 22)
		var f := 1.0 - RBMHeroFx.ramp(a, life * 0.6, life)
		if f <= 0.0:
			continue
		var up := -1.0 if RBMHeroFx.r(i, 23) > 0.45 else 1.0
		var v := Vector2(40.0 + 90.0 * RBMHeroFx.r(i, 24), up * (30.0 + 70.0 * RBMHeroFx.r(i, 25)))
		var p := foot + Vector2(x, BLADE_Y - x * 0.017) + v * a + Vector2(0, 140.0 * a * a)
		var s := (1.0 + 1.8 * RBMHeroFx.r(i, 26)) * (1.0 - 0.4 * RBMHeroFx.ramp(a, 0.0, life))
		b_ink.dot_px(p, s, Color(INK, f))
		if s > 1.6:
			b_ink.dot_px(p + Vector2(-0.5, -0.5), 0.8, Color(INK_GREY, f))

## 小さな葉（濃い緑の葉に明るい葉脈の点。half は割れた半分）
func _leaf(p: Vector2, d: Vector2, col: Color, a: float, half: bool = false) -> void:
	b_leaf.line(p - d, p + d, 1.3 if half else 1.7, Color(col.darkened(0.25), a), Color(col, a))
	if not half:
		b_leaf.dot_px(p + d * 0.3, 0.8, Color(GREEN.lightened(0.35), a))
