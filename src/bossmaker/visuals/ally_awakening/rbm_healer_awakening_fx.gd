extends RBMFlowerFxBase
## 少女の覚醒「天雷の祈り」（2026-11-19 第2版。表示専用）。時刻は T（音の build もここを読む）。座標は論理ドット（足元からの相対）。
## 意味: 目を閉じて杖を胸に抱いて祈る → 足元を静電気が這い、杖の宝石に小さな火花が集まる → 杖を天へ掲げると、まわりから稲妻が宝石へ
## 吸い込まれ、空から細い前触れの放電が降りてくる → 解放: 天から雷が杖に落ち（数回瞬く）、杖から足元へ、足元から床へ稲妻が走り、雷の輪が広がる
## → 両腕を広げた体のまわりに放電が残る。
## 色は単体攻撃の雷（rbm_healer_lightning_finish.gd）と同じ、金の雷に杖の宝石の紫を混ぜる。三角のトゲ・星形・平たい円は使わない。
## 稲妻は中点をずらして細かくギザギザにし、根元から先へ細らせ、紫のにじみ・金・白い芯の3重で描く（太い一定幅の線にしない）。
## 床の衝撃の輪は平たい帯に見えたので使わない（床は這う稲妻で見せる）。
## 2026-11-19 ユーザー「ヒーラーも花の要素を残して。ボスとのつながりで」→ 対応するボス「白磁のカラー」の花（立体の花 bloom・カラーの一輪・花びら）を入れた:
## 祈ると足元に白磁の花が咲き、花びらが体のまわりを回る → 雷が落ちると花は花びらへ弾け、両脇に白いカラーが立ち上がり、花びらがゆっくり降る。
## 花の部品は白磁のカラーと同じもの（RBMFlowerFxBase の bloom・calla・petal_cloud）。

const T := {"pray": 0.25, "raise": 1.0, "release": 1.9, "cast": 2.2, "settle": 3.1, "end": 3.6}
## 杖の宝石（frames/04＝胸に抱く、09＝天へ掲げる、05＝両腕を広げる。足元からの相対、論理ドット）
const GEM_PRAY := Vector2(6, -19)
const GEM_RAISE := Vector2(-12, -35)
const GEM_CAST := Vector2(-19, -26)
## 体の中心（放電がまとわりつく楕円の中心）
const BODY := Vector2(0, -20)
const GOLD := Color("#ffe37a")
const CORE := Color("#fffbe6")
const EDGE := Color("#e4c76b")
const VIOLET := Color("#c9a6ff")
## 白磁のカラーの色（rbm_flower_fx_support.gd と同じ）
const PORCELAIN := ["#2e3a32", "#4a5a4c", "#728470", "#9eae98", "#c4d0bc", "#e0e8d8", "#f4f6ee", "#ffffff"]
const WHITE := Color("#fbf8ee")
const IVORY := Color("#e8e2d0")
const LINE := Color("#4c5c4a")
## 放電の形が変わる間隔（秒）
const FLICK := 0.06
## 雷が落ちてくる高さ（足元から。画面の上の外）
const SKY := 175.0

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_flora: RBMHeroFxBatch
var b_petal: RBMHeroFxBatch
var flower: ColorRect

func _build() -> void:
	flower = bloom_quad(back, PORCELAIN, [], {"outline_col": Vector3(.16, .2, .16), "petals": 10.0, "seed": 4.0})
	b_flora = batch(back, false)
	b_back = batch(back)
	b_petal = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_flora.reset(); b_petal.reset()
	var ra := t - T.release
	var fl := int(t / FLICK)
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.raise, 0.38], [T.release, 0.52], [T.release + 0.3, 0.3], [T.end, 0.0]])
	view["dim_col"] = Color(0.03, 0.02, 0.07)
	_flowers(t, ra)
	# 祈り: 足元を静電気が這う・紫の粒が立ちのぼる
	var pray := RBMHeroFx.ramp(t, T.pray, T.raise) * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.1))
	if pray > 0.0:
		_creep(fl, pray)
		embers(b_add, Rect2(foot.x - 16, foot.y - 12, 32, 10), t, 12, 41, 30.0, Color(VIOLET, 0.9), pray, 1.3, 5.0)
	var gem := foot + (GEM_PRAY if t < T.raise else (GEM_RAISE if t < T.cast else GEM_CAST))
	# 宝石: ためるほど光が育ち、まわりで小さな放電が跳ねる
	var charge := RBMHeroFx.ramp(t, T.pray, T.release)
	if t >= T.pray and ra < 0.12:
		var pulse := 0.8 + 0.2 * sin(t * 30.0)
		RBMHeroRooftop.glow(b_add, gem, (3.0 + 6.0 * charge) * pulse, Color(VIOLET, 0.2 + 0.55 * charge))
		RBMHeroRooftop.glow(b_add, gem, 1.5 + 1.5 * charge, Color(CORE, 0.9))
		for i in range(2):
			var a0 := RBMHeroFx.r(fl * 3 + i, 51) * TAU
			_bolt(b_add, gem, gem + Vector2.from_angle(a0) * (4.0 + 5.0 * charge), fl * 5 + i, 0.35, 0.8, 0.5, 3, 0)
	# 掲げる: まわりから稲妻が宝石へ吸い込まれる（だんだん多く）・空から前触れの放電が降りてくる
	if t >= T.raise and t < T.release:
		var g := RBMHeroFx.ramp(t, T.raise, T.release)
		for i in range(1 + int(g * 3.0)):
			var k := fl * 7 + i
			if RBMHeroFx.r(k, 61) > 0.35 + 0.5 * g:
				continue
			var a1 := RBMHeroFx.r(k, 62) * TAU
			var from := gem + Vector2(cos(a1) * (16.0 + 8.0 * RBMHeroFx.r(k, 63)), sin(a1) * (12.0 + 6.0 * RBMHeroFx.r(k, 64)))
			_bolt(b_add, from, gem, k, 0.45, 0.45 + 0.5 * g, 0.45, 4, 1)
		var lead := RBMHeroFx.ramp(t, T.release - 0.4, T.release)
		if lead > 0.0:
			var sky := Vector2(gem.x + 6.0, foot.y - SKY)
			_bolt(b_add, sky, sky.lerp(gem, 0.25 + 0.6 * lead), 300 + fl, 0.45, 0.7 * lead, 0.4, 5, 2)
	# 解放: 天から雷が杖に落ちる（数回瞬いて消える）・杖から足元へ・床へ稲妻が走る・雷の輪・火花
	if ra >= 0.0:
		var strike := RBMHeroFx.key(ra, [[0.0, 1.0], [0.05, 0.35], [0.08, 1.0], [0.14, 0.4], [0.18, 0.85], [0.34, 0.0]])
		var hit := foot + GEM_RAISE
		if strike > 0.0:
			var sky := Vector2(hit.x + 6.0, foot.y - SKY)
			var sd := 400 + int(ra / 0.08)
			_bolt(b_add, sky, hit, sd, 2.2, strike, 0.42, 6, 4)
			_bolt(b_add, hit, foot + Vector2(0, -1), sd + 9, 0.8, strike, 0.35, 4, 0)
		var sg := 1.0 - RBMHeroFx.ramp(ra, 0.0, 0.25)
		if sg > 0.0:
			RBMHeroRooftop.glow(b_add, hit, 10.0 * sg, Color(CORE, 0.5 * sg))
		_floor_bolts(ra, fl)
		sparks(b_add, hit, ra, 0.5, 20, 71, 150.0, CORE, GOLD, -PI * 0.5, PI * 1.6, 120.0, 1.2)
		sparks(b_add, foot + Vector2(0, -2), ra, 0.6, 24, 73, 130.0, CORE, VIOLET, -PI * 0.5, PI * 1.2, 160.0, 1.2)
		view["hero"]["flash"] = 0.8 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.2))
		view["hero"]["flash_col"] = CORE
		view["hero"]["lit"] = 0.5 * (1.0 - RBMHeroFx.ramp(ra, 0.2, 1.2))
		view["hero"]["lit_col"] = GOLD
		set_post({"flash": 0.16 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.1))})
	# 両腕を広げる: 体のまわりに放電が残る・紫の粒
	if t >= T.cast:
		var aura := RBMHeroFx.ramp(t, T.cast, T.cast + 0.1) * (1.0 - RBMHeroFx.ramp(t, T.settle - 0.3, T.settle + 0.1))
		if aura > 0.0:
			_aura(fl, aura)
			embers(b_add, Rect2(foot.x - 18, foot.y - 40, 36, 36), t, 10, 45, 24.0, Color(VIOLET, 0.8), aura, 1.2, 4.0)
	b_back.commit(); b_add.commit(); b_flora.commit(); b_petal.commit()

## 足元の床を這う静電気（短い放電が床の楕円の上で場所を変えながら瞬く）
func _creep(fl: int, power: float) -> void:
	for i in range(3):
		var k := fl * 3 + i
		if RBMHeroFx.r(k, 31) > 0.4 + 0.5 * power:
			continue
		var a0 := RBMHeroFx.r(k, 32) * TAU
		var rad := 10.0 + 14.0 * RBMHeroFx.r(k, 33)
		var a1 := a0 + (0.5 + 0.4 * RBMHeroFx.r(k, 34)) * (1.0 if RBMHeroFx.r(k, 35) > 0.5 else -1.0)
		_bolt(b_back, foot + Vector2(cos(a0), sin(a0) * 0.3) * rad, foot + Vector2(cos(a1), sin(a1) * 0.3) * rad, k, 0.35, 0.85 * power, 0.5, 4, 0)

## 雷が落ちた後、足元から床を外へ稲妻が走る（形を変えながら瞬いて消える）
func _floor_bolts(ra: float, fl: int) -> void:
	var power := 1.0 - RBMHeroFx.ramp(ra, 0.15, 0.7)
	if power <= 0.0:
		return
	var reach := RBMHeroFx.burst(ra, 9.0)
	for i in range(6):
		var a0 := (float(i) + 0.3 * RBMHeroFx.r(i, 81)) * TAU / 6.0
		var length := (30.0 + 22.0 * RBMHeroFx.r(i, 82)) * reach
		var k := fl * 11 + i
		_bolt(b_back, foot + Vector2(0, -1), foot + Vector2(0, -1) + Vector2(cos(a0), sin(a0)) * length, k, 0.6, power, 0.4, 5, 1, 0.3)

## 体のまわりにまとわりつく放電（体の輪郭の楕円の上の近い2点を結ぶ短い放電）
func _aura(fl: int, power: float) -> void:
	for i in range(2):
		var k := fl * 5 + i
		if RBMHeroFx.r(k, 91) > 0.35 + 0.4 * power:
			continue
		var a0 := RBMHeroFx.r(k, 92) * TAU
		var a1 := a0 + 0.25 + 0.2 * RBMHeroFx.r(k, 93)
		var c := foot + BODY
		_bolt(b_add, c + Vector2(cos(a0) * 12.0, sin(a0) * 20.0), c + Vector2(cos(a1) * 13.0, sin(a1) * 21.0), k, 0.3, 0.75 * power, 0.5, 3, 0)

## 稲妻: a から c へ、中点をずらして細かくギザギザにする（seed で形が変わる）。根元から先へ細る。紫のにじみ・金・白い芯の3重。
## forks は枝の数（枝は細く短く、先へ消える）。sq < 1 は床の上（縦をつぶす）。
func _bolt(b: RBMHeroFxBatch, a: Vector2, c: Vector2, sd: int, wide: float, alpha: float, rough: float = 0.4, levels: int = 5, forks: int = 2, sq: float = 1.0) -> void:
	if alpha <= 0.01:
		return
	var pts: Array[Vector2] = [Vector2.ZERO, c - a]
	if sq < 1.0:
		pts[1] = Vector2(pts[1].x, pts[1].y / sq)
	for lv in range(levels):
		var nxt: Array[Vector2] = []
		for i in range(pts.size() - 1):
			var p := pts[i]
			var q := pts[i + 1]
			var d := q - p
			nxt.append(p)
			nxt.append((p + q) * 0.5 + Vector2(-d.y, d.x) * (RBMHeroFx.r(i + lv * 97, sd) - 0.5) * rough)
		nxt.append(pts[pts.size() - 1])
		pts = nxt
	var n := pts.size() - 1
	for i in range(n + 1):
		pts[i] = a + Vector2(pts[i].x, pts[i].y * sq)
	for i in range(n):
		var wv := wide * (1.0 - 0.6 * float(i) / float(n))
		b.line(pts[i], pts[i + 1], wv * 3.4, Color(VIOLET, 0.22 * alpha), Color(VIOLET, 0.22 * alpha))
		b.line(pts[i], pts[i + 1], wv * 1.7, Color(GOLD, 0.55 * alpha), Color(GOLD, 0.55 * alpha))
		b.line(pts[i], pts[i + 1], wv * 0.75, Color(1, 1, 1, alpha), Color(CORE, alpha))
	for k in range(forks):
		var at := int((0.15 + 0.6 * RBMHeroFx.r(k, sd + 3)) * float(n))
		var dir := (pts[at + 1] - pts[at]).normalized().rotated((0.45 + 0.4 * RBMHeroFx.r(k, sd + 4)) * (1.0 if RBMHeroFx.r(k, sd + 5) > 0.5 else -1.0))
		var length := (c - a).length() * (0.15 + 0.15 * RBMHeroFx.r(k, sd + 6))
		_bolt(b, pts[at], pts[at] + dir * length, sd * 3 + k + 1, wide * 0.5, alpha * 0.7, rough, maxi(levels - 2, 2), 0, sq)

## 白磁のカラーの花: 祈ると足元に花が咲き（雷が這う）、掲げる間は花びらが体のまわりを回る → 雷で花が花びらへ弾ける →
## 両腕を広げると両脇に白いカラーが立ち上がり、花びらがゆっくり降る → 消える
func _flowers(t: float, ra: float) -> void:
	var charge := RBMHeroFx.ramp(t, T.pray, T.release)
	var on := RBMHeroFx.ramp(t, T.pray, T.pray + 0.3) * (1.0 - RBMHeroFx.ramp(ra, 0.35, 0.6))
	if on > 0.0:
		var flash := 1.0 - RBMHeroFx.ramp(ra, 0.0, 0.3) if ra >= 0.0 else 0.0
		show_bloom(flower, foot + Vector2(0, 1), 24.0, {"open": RBMHeroFx.ramp(t, T.pray, T.raise + 0.25), "rot": t * 0.25, "squash": 0.4,
			"glow": 0.15 + 0.35 * charge + 0.6 * flash, "crumble": RBMHeroFx.ramp(ra, 0.05, 0.5), "fade": on})
	else:
		flower.visible = false
	var outline := Color(LINE, 0.85)
	# 掲げる間: 花びらが体のまわりを回る（少なめ）
	var orbit := RBMHeroFx.ramp(t, T.raise - 0.1, T.raise + 0.3) * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.04))
	if orbit > 0.0:
		petal_cloud(b_petal, foot + Vector2(0, -16), t, 8, 7, 24.0, 3.0, IVORY, WHITE, orbit, "orbit", 0.45, outline)
	if ra >= 0.0:
		# 雷で花びらが弾ける → ゆっくり降る
		petal_cloud(b_petal, foot + Vector2(0, -4), ra, 18, 13, 60.0, 3.2, IVORY, WHITE, 1.0, "burst", 0.45, outline)
		var fall := RBMHeroFx.ramp(ra, 0.3, 0.6) * (1.0 - RBMHeroFx.ramp(t, T.settle, T.end))
		petal_cloud(b_petal, foot + Vector2(0, -30), t, 8, 17, 34.0, 2.8, IVORY, WHITE, fall, "fall", 0.45, outline)
	# 両腕を広げる: 両脇に白いカラーが立ち上がる（芯に小さな放電が残る）
	var grow := RBMHeroFx.ramp(t, T.cast - 0.1, T.cast + 0.35)
	var keep := 1.0 - RBMHeroFx.ramp(t, T.settle, T.end - 0.05)
	if grow > 0.0 and keep > 0.0:
		for side in [-1.0, 1.0]:
			var sd := float(side)
			var base := foot + Vector2(22.0 * sd, 2.0)
			var o := grow * (1.0 - 0.15 * (1.0 - keep))
			calla(b_flora, base, 20.0, o, 0.22 * sd, [Color("#c4d0bc", keep), Color("#f4f6ee", keep), Color(1, 1, 1, keep)], Color(LINE, 0.95 * keep), [Color("#4a5a3c", keep), Color("#7a9a5c", keep)], Color(GOLD, keep))
