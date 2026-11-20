class_name RBMGentlemanFxBase
extends RBMHeroFxBase
## 異形紳士の大技（覚醒・覚醒後の全体。2026-11-20 作り直し）のエフェクトの土台（表示専用。戦闘の状態・乱数には触れない）。
## 2026-11-20 ユーザー「覚醒モーションの派手さがまったくない。他のボスと同じくらい派手に豪華に」「覚醒後の全体攻撃は作り直したい。
## 聖獣やヒーローくらいのクオリティで」→ ヒーロー・聖獣と同じ部品（RBMHeroFxBase の爆炎・衝撃の輪・柱・帯・粒・後処理）で描く。
## 紳士の部品: 深紅の幕（ribbon）・空間の裂け目（rift）・闇に開く赤い目（eyes）・薔薇の花びら（petals）・銃火（muzzle）。
## 本体は今ある絵（motion_frames の要所の絵）を切り替えるだけ（pose_keys）。描くのは rbm_gentleman_vfx.gd（view["body"] を読む）。
## 座標は 640×360 の論理ドット（ステージの半分）。紳士の絵の画素（ステージの 1.7 倍）は UNIT で直す。

const Motion := preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
## 紳士の絵の1画素 → 論理ドット（ステージの 160/94 px ÷ 2）
const UNIT := 160.0 / 94.0 * 0.5
## 深紅の墨（爆炎の8色: 闇 → 深紅 → 薔薇色 → 白）
const CRIMSON_INK := ["#020105", "#09030c", "#1a0612", "#3c0a1c", "#7a1026", "#c22a44", "#ff8a96", "#fff0f2"]
## 爆炎の外側（冷えた墨）
const INK_SMOKE := ["#010103", "#040308", "#0a0610", "#140a18", "#24101e", "#3a1422", "#5a1c2a", "#8a3040"]
## 幕（天鵞絨の深紅。帯の6色: 縁 → 中）
const VELVET := ["#060105", "#16030a", "#2e0612", "#4a0a1a", "#661022", "#86162c"]
## 闇の柱（下から上へ）
const DARK_PILLAR := ["#2a0612", "#5a0c1c", "#a01830", "#e0304a", "#ffa0ac", "#fff0f2"]
const RED := Color("#d8243e")
const ROSE := Color("#ff8a96")
const PALE := Color("#fff0f2")
const INK := Color("#07040c")

## 本体の今の状態（つなぎが読む）: pose=絵の名前、off=足元からのずれ（論理ドット）、alpha、flash、flash_col
var body := {}

func duration() -> float:
	return 3.0

func impact() -> float:
	return 1.0

## 途中の当たり: [[秒, 相手の番号], ...]（最後の一撃より前）
func hits() -> Array:
	return []

## [[秒, "絵の名前"], ...]
func pose_keys() -> Array:
	return [[0.0, "hat_reach_00"]]

func pose_name(t: float) -> String:
	var keys := pose_keys()
	var p := str(keys[0][1])
	for k in keys:
		if t >= float(k[0]):
			p = str(k[1])
	return p

func advance_all(t: float, boss_foot: Vector2) -> void:
	var name := pose_name(t)
	advance(t, name, boss_foot, boss_foot)
	if not view.has("body"):
		view["body"] = {}
	view["body"]["pose"] = name

## 絵の銃口と銃身の向き（論理ドット）。銃の無い絵なら空。
func gun_at(pose_: String, hand: String) -> Dictionary:
	var g := Motion.gun(pose_, hand)
	if g.is_empty():
		return {}
	return {"p": foot + Vector2(g.p) * UNIT, "d": Vector2(g.d)}

## 本体の胸（論理ドット）
func chest() -> Vector2:
	return foot + Vector2(0, -50) * UNIT

func n_targets() -> int:
	var n := 0
	for i in range(mini(targets.size(), 4)):
		if present[i]:
			n += 1
	return n

func party_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for i in range(mini(targets.size(), 4)):
		if present[i]:
			c += Vector2(targets[i])
			n += 1
	return c / maxf(1.0, float(n)) if n > 0 else Vector2(175, 225)

# --- 紳士の部品 -------------------------------------------------------------

## 空間の裂け目: 縦長の暗い裂け目、縁に深紅の光、まわりのやわらかい光。open 0〜1。
func rift(b: RBMHeroFxBatch, b_add: RBMHeroFxBatch, p: Vector2, open: float, h: float, t: float, seed_: int) -> void:
	if open <= 0.02:
		return
	var hh := h * open
	var ww := (2.2 + 1.6 * open) * open
	var pts := PackedVector2Array()
	for k in range(14):
		var a := TAU * float(k) / 14.0
		var j := 1.0 + (RBMHeroFx.r(k + int(t * 14.0), seed_) - 0.5) * 0.3
		pts.append(p + Vector2(sin(a) * ww * j, -cos(a) * hh))
	var dark := Color(0.01, 0.0, 0.02, 0.97)
	for k in range(14):
		b.tri(p, pts[k], pts[(k + 1) % 14], dark, dark, dark)
	for k in range(14):
		var c := Color(RED, open * (0.6 + 0.35 * sin(t * 13.0 + k)))
		b_add.line(pts[k], pts[(k + 1) % 14], 0.9, c, c)
	RBMHeroRooftop.glow(b_add, p, ww * 3.0 + 5.0, Color(RED, 0.28 * open))

## 闇に開く赤い目（2つの小さな光。まばたきで開く）
func eyes(b_add: RBMHeroFxBatch, p: Vector2, open: float, size_: float = 1.0) -> void:
	if open <= 0.02:
		return
	for s in [-1.0, 1.0]:
		var e := p + Vector2(s * 2.2 * size_, 0)
		b_add.line(e - Vector2(1.3 * size_, 0), e + Vector2(1.3 * size_, 0), 0.9 * open * size_, Color(ROSE, open), Color(RED, open))
		RBMHeroRooftop.glow(b_add, e, 2.5 * size_, Color(RED, 0.45 * open))

## 薔薇の花びら（小さな2色の粒。ひらひら回りながら落ちる）。origin から広がる。
func petals(b: RBMHeroFxBatch, origin: Vector2, age: float, life: float, n: int, seed_: int, speed: float, power: float = 1.0, rise: float = 0.0) -> void:
	if age < 0.0 or age > life or power <= 0.0:
		return
	for i in range(n):
		var li := life * (0.55 + 0.45 * RBMHeroFx.r(i, seed_ + 1))
		if age > li:
			continue
		var th := RBMHeroFx.r(i, seed_) * TAU
		var sp_ := speed * (0.3 + 0.7 * RBMHeroFx.r(i, seed_ + 2))
		var dir := Vector2(cos(th), sin(th) * 0.7 - rise)
		var k := 3.0
		var p := origin + dir * sp_ * (1.0 - exp(-k * age)) / k + Vector2(sin(age * 5.0 + i) * 4.0, 22.0 * age * age)
		var f := (1.0 - RBMHeroFx.ramp(age, li * 0.6, li)) * RBMHeroFx.ramp(age, 0.0, 0.05) * power
		var flip := absf(sin(age * (6.0 + 5.0 * RBMHeroFx.r(i, seed_ + 3)) + i))
		var col := RED.lerp(Color("#7a1026"), RBMHeroFx.r(i, seed_ + 4) * 0.6)
		b.dot_px(p, 2.0, Color(col, f))
		if flip > 0.4:
			b.dot_px(p + Vector2(2, 0), 1.0, Color(col.darkened(0.35), f))
		if flip > 0.75:
			b.dot_px(p + Vector2(0, -1), 1.0, Color(ROSE, f * 0.9))

## 銃火（銃身の向きに伸びる光。尖らせない）と流れる硝煙
func muzzle(b_add: RBMHeroFxBatch, p: Vector2, d: Vector2, a: float, big: float = 1.0) -> void:
	if a < 0.0 or a > 0.12:
		return
	var k := 1.0 - a / 0.12
	RBMHeroRooftop.glow(b_add, p + d * 2.0, (4.0 + 2.0 * big) * (0.6 + 0.4 * k), Color(1.0, 0.85, 0.6, 0.9 * k))
	b_add.line(p, p + d * (7.0 + 3.0 * big) * (0.6 + 0.4 * k), 2.2 * k, Color(1.0, 0.95, 0.85, k), Color(1.0, 0.55, 0.3, 0.0))

## 弾の光の筋
func tracer(b_add: RBMHeroFxBatch, a: Vector2, c: Vector2, age: float, dur: float, col: Color) -> void:
	if age < 0.0 or age > dur + 0.05:
		return
	var p := clampf(age / dur, 0.0, 1.0)
	var fade := 1.0 - clampf((age - dur) / 0.05, 0.0, 1.0)
	b_add.streak(a.lerp(c, maxf(0.0, p - 0.35)), a.lerp(c, p), 1.6, Color(col, fade), Color(col, 0.0))
	b_add.line(a.lerp(c, maxf(0.0, p - 0.12)), a.lerp(c, p), 0.6, Color(PALE, fade), Color(PALE, fade))

## 命中（白い芯・深紅の飛沫・墨）
func bullet_hit(b_add: RBMHeroFxBatch, b: RBMHeroFxBatch, p: Vector2, d: Vector2, age: float, seed_: int, power: float = 1.0) -> void:
	if age < 0.0 or age > 0.9:
		return
	if age < 0.08:
		var k := 1.0 - age / 0.08
		RBMHeroRooftop.glow(b_add, p, (4.0 + 3.0 * power) * (0.7 + 0.3 * k), Color(PALE, k))
		RBMHeroRooftop.glow(b_add, p, (8.0 + 5.0 * power) * (0.7 + 0.3 * k), Color(RED, 0.5 * k))
	sparks(b_add, p, age, 0.45, int(16 * power), seed_, 120.0 * power, ROSE, RED, d.angle(), 1.6, 160.0, 1.4)
	for k in range(int(4 + 3 * power)):
		var v := d.rotated((RBMHeroFx.r(k, seed_ + 9) - 0.5) * 1.2) * (16.0 + 22.0 * RBMHeroFx.r(k, seed_ + 10)) * power
		var q := p + d * 3.0 + v * minf(age, 0.3) + Vector2(0, 14.0 * age * age)
		RBMHeroRooftop.glow(b, q, (1.5 + 1.5 * RBMHeroFx.r(k, seed_ + 11)) * (1.0 + 1.5 * RBMHeroFx.ramp(age, 0.0, 0.4)), Color(INK, 0.8 * (1.0 - RBMHeroFx.ramp(age, 0.15, 0.7))))
