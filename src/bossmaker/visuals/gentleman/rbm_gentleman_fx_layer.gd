class_name RBMGentlemanFxLayer
extends RBMGentlemanFxBase
## 異形紳士の技（単体・全体・覚醒後の単体・強化・回復）のエフェクトの層の土台（2026-11-23、表示専用。戦闘の状態・乱数には触れない）。
## 2026-11-23 ユーザー「全体的にエフェクトが弱くてクオリティが低い。覚醒後の全体攻撃だけはすごくいいから、そこは変えないで基準に」
## → 動き（要所の絵・霧の移動・影の並び・水平の弾）は承認済みの rbm_gentleman_vfx.gd のまま（fx_layer=true で本体・影・霧だけを描く）。
##   エフェクトは覚醒後の全体と同じ部品（RBMHeroFxBase の爆炎・衝撃の輪・屈折・火花・裂け目・花びら・後処理）で、技ごとの
##   スクリプト（rbm_gentleman_fx_single.gd など）が描く。弾の時刻・銃口・当たる所は vfx.shot_events() を読む（同じ計算）。
## 時刻は動きのデータ（motion.json の clip）のまま。座標: vfx の1画素（ステージの 160/94 px）→ 論理ドット（ステージの半分）は UNIT 倍。

var vfx: Node2D
var data: Dictionary = {}
var action_kind := ""
## 白い芯・火の粉の色（深紅の紳士の色。属性の色は火の粉の尾に混ぜる）
var accent := RED

func duration() -> float:
	return float(data.get("duration", 3.0))

func impact() -> float:
	return float(data.get("impact", 1.0))

## vfx の座標 → 論理ドット
func vp(v: Vector2) -> Vector2:
	return v * UNIT

## 弾ごとの出来事（論理ドット）。vfx.shot_events() と同じ時刻・位置。
func shots() -> Array:
	var out: Array = []
	for e in vfx.call("shot_events"):
		var c: Dictionary = e.duplicate()
		c.mouth = vp(e.mouth)
		c.dest = vp(e.dest)
		if e.has("intake"):
			c.intake = vp(e.intake)
			var exits: Array = []
			for x in e.exits:
				var y: Dictionary = x.duplicate()
				y.exit = vp(x.exit)
				y.dest = vp(x.dest)
				exits.append(y)
			c.exits = exits
		out.append(c)
	return out

## 本体の足元（論理ドット。単体の霧の移動も含む）
func host() -> Vector2:
	return vp(vfx.call("host_foot"))

## 相手 i の足元・胸（論理ドット）
func foot_of(i: int) -> Vector2:
	return vp(vfx.call("foot", i))

func chest_of(i: int) -> Vector2:
	return vp(vfx.call("point", i))

## 絵の目の位置（足元からの相対、絵の画素）。影は左右反転する。
const EYE_AT := {"hat_reach_00": Vector2(-4, -80), "normal_draw_fire_05": Vector2(-5, -79), "normal_draw_fire_15": Vector2(-10, -73), "normal_draw_fire_11": Vector2(-3, -77)}

func eye_of(pose_: String, foot_: Vector2, flip: bool = false) -> Vector2:
	var e: Vector2 = EYE_AT.get(pose_, Vector2(-6, -78))
	if flip:
		e.x = -e.x
	return foot_ + e * UNIT

## 墨の煙（加算しない層。柔らかい黒い塊が広がって薄れる）
func ink_puff(b: RBMHeroFxBatch, p: Vector2, age: float, life: float, n: int, seed_: int, reach: float, size_: float = 5.0, rise: float = 18.0) -> void:
	if age < 0.0 or age > life:
		return
	for k in range(n):
		var ang := RBMHeroFx.r(k, seed_) * TAU
		var d := Vector2(cos(ang), sin(ang) * 0.55)
		var sp_ := reach * (0.35 + 0.65 * RBMHeroFx.r(k, seed_ + 1))
		var q := p + d * sp_ * (1.0 - exp(-4.0 * age)) / 4.0 * 4.0 + Vector2(0, -rise * age * (0.5 + RBMHeroFx.r(k, seed_ + 2)))
		var f := 1.0 - RBMHeroFx.ramp(age, life * 0.35, life)
		RBMHeroRooftop.glow(b, q, size_ * (0.7 + 0.6 * RBMHeroFx.r(k, seed_ + 3)) * (1.0 + 1.4 * RBMHeroFx.ramp(age, 0.0, life)), Color(INK, 0.75 * f))

## 撃った弾ひとつ: 銃火・弾の光の筋・命中（白い芯・深紅の飛沫・墨）・揺れ。覚醒後は銃身の先の裂け目と相手のそばの裂け目。
## 返り値: 味方ののけぞり [[時刻, 相手の番号], ...]
func draw_shot(e: Dictionary, t: float, b_add: RBMHeroFxBatch, b_front: RBMHeroFxBatch, b_mid: RBMHeroFxBatch, scale_: float = 1.0) -> Array:
	var hits_out: Array = []
	var dt := t - float(e.time)
	var d: Vector2 = e.d
	muzzle(b_add, e.mouth, d, dt, float(e.big) * 1.5 * scale_)
	# 撃った瞬間の銃口の光のにじみ（暗い所で目立つ）
	if dt >= 0.0 and dt < 0.1:
		RBMHeroRooftop.glow(b_add, e.mouth, 16.0 * scale_ * (1.0 - dt / 0.1), Color(1.0, 0.7, 0.4, 0.35))
	var power: float = float(e.power) * scale_
	if e.has("intake"):
		rift(b_mid, b_add, e.intake, RBMHeroFx.env(t, float(e.time) - 0.25, float(e.time) - 0.05, float(e.time) + 0.18, float(e.time) + 0.45), 10.0, t, 11 + int(e.index) * 5)
		tracer(b_add, e.mouth, e.intake, dt, 0.07, PALE)
		for x in e.exits:
			rift(b_mid, b_add, x.exit, RBMHeroFx.env(t, float(x.open), float(x.open) + 0.28, float(e.hit) + 0.04, float(e.hit) + 0.25), 11.0, t, int(x.seed))
			RBMHeroRooftop.glow(b_add, x.exit, 7.0 * RBMHeroFx.env(t - float(x.from), 0.0, 0.02, 0.06, 0.14), Color(ROSE, 0.9))
			tracer(b_add, x.exit, x.dest, t - float(x.from), float(e.hit) - float(x.from), ROSE)
			bullet_hit(b_add, b_front, x.dest, (Vector2(x.dest) - Vector2(x.exit)).normalized(), t - float(e.hit), int(x.hit_seed), power)
			hits_out.append([float(e.hit), int(x.target)])
	else:
		tracer(b_add, e.mouth, e.dest, dt, maxf(0.02, float(e.hit) - float(e.time)), PALE)
		bullet_hit(b_add, b_front, e.dest, d, t - float(e.hit), int(e.seed), power)
		if int(e.target) >= 0:
			hits_out.append([float(e.hit), int(e.target)])
		else:
			for i in range(n_targets()):
				hits_out.append([float(e.hit), i])
	view["shake"] += hit_shake(t - float(e.hit), 2.0 + 3.0 * power, 90.0, 0.2)
	return hits_out
