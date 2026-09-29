extends RefCounted
## 朽ちた機械武者のコマ描画(覚醒前・覚醒後の全行動と待機で共通)。
## 本番の原画のコマ(静止姿 design.png・ポーズ poses.png・覚醒後 awakened.png・振り下ろし swing.png)と、
## 原画から作った追加コマ(assets_bossmaker/battle/musha_frames/)を、承認済みの倍率・足元のまま Nearest で1枚ずつ描く。
## 絵を毎フレーム変形・揺らすことはしない(動きはコマの切り替えで表す)。表示専用で、戦闘の状態には触れない。
## 状態: {"fr": コマ名, "foot": 足元(ステージ座標), "flip": 左右反転, "alpha": 不透明度, "eye": 眼を灯すか}

const ROOT := "res://assets_bossmaker/battle/"

static var FR := {
	"idle": {"tex": "musha/design.png", "rect": Rect2(0, 0, 748, 1410), "anchor": Vector2(374, 1410), "scale": 180.0 / 1410.0, "eye": Vector2(265, 243)},
	"p0": {"tex": "musha/poses.png", "rect": Rect2(95, 50, 345, 438), "anchor": Vector2(270, 475), "scale": 0.445, "eye": Vector2(215, 158), "hilt": Vector2(284, 262), "tsuba": Vector2(292, 274)},
	"p1": {"tex": "musha/poses.png", "rect": Rect2(447, 50, 590, 438), "anchor": Vector2(856, 475), "scale": 0.445, "eye": Vector2(800, 152), "hilt": Vector2(646, 203), "tip": Vector2(463, 206)},
	"p2": {"tex": "musha/poses.png", "rect": Rect2(1190, 50, 332, 438), "anchor": Vector2(1360, 475), "scale": 0.445, "eye": Vector2(1305, 152), "hilt": Vector2(1318, 272), "tsuba": Vector2(1366, 268)},
	"p3": {"tex": "musha/poses.png", "rect": Rect2(20, 502, 435, 508), "anchor": Vector2(280, 988), "scale": 0.445, "eye": Vector2(258, 657), "hilt": Vector2(245, 555), "tip": Vector2(50, 517)},
	"p4": {"tex": "musha/poses.png", "rect": Rect2(535, 547, 454, 462), "anchor": Vector2(823, 988), "scale": 0.445, "eye": Vector2(780, 653), "hilt": Vector2(725, 839), "tip": Vector2(562, 944)},
	"p5": {"tex": "musha/poses.png", "rect": Rect2(1190, 543, 322, 465), "anchor": Vector2(1355, 988), "scale": 0.445, "eye": Vector2(1306, 649), "core": Vector2(1330, 760), "tsuba": Vector2(1353, 775), "chest": Vector2(1332, 712)},
	"a0": {"tex": "musha_awakened/awakened.png", "rect": Rect2(177, 17, 328, 581), "anchor": Vector2(351, 596), "scale": 0.335, "eye": Vector2(294, 126), "patch": true, "tsuba": Vector2(352, 318)},
	"a1": {"tex": "musha_awakened/awakened.png", "rect": Rect2(777, 24, 365, 578), "anchor": Vector2(959, 600), "scale": 0.335, "eye": Vector2(897, 129), "patch": true},
	"a2": {"tex": "musha_awakened/awakened.png", "rect": Rect2(110, 639, 513, 579), "anchor": Vector2(370, 1215), "scale": 0.335, "eye": Vector2(324, 741), "patch": true},
	"a3": {"tex": "musha_awakened/awakened.png", "rect": Rect2(672, 640, 456, 579), "anchor": Vector2(971, 1215), "scale": 0.335, "eye": Vector2(925, 742), "patch": true, "hilt": Vector2(849, 1001), "tip": Vector2(706, 1172)},
	"s0": {"tex": "musha_awakened/swing.png", "rect": Rect2(40, 20, 390, 710), "anchor": Vector2(232, 708), "scale": 0.415, "eye": Vector2(181, 311), "hilt": Vector2(189, 173), "tip": Vector2(338, 48)},
	"s1": {"tex": "musha_awakened/swing.png", "rect": Rect2(451, 140, 502, 589), "anchor": Vector2(786, 708), "scale": 0.415, "eye": Vector2(729, 334), "hilt": Vector2(605, 313), "tip": Vector2(478, 182)},
	"s2": {"tex": "musha_awakened/swing.png", "rect": Rect2(956, 240, 586, 490), "anchor": Vector2(1380, 708), "scale": 0.415, "eye": Vector2(1308, 335), "hilt": Vector2(1186, 436), "tip": Vector2(985, 429)},
	"s3": {"tex": "musha_awakened/swing.png", "rect": Rect2(1560, 266, 505, 468), "anchor": Vector2(1890, 708), "scale": 0.415, "eye": Vector2(1784, 366), "hilt": Vector2(1756, 576), "tip": Vector2(1624, 704)},
}

## 原画から作った追加コマ(1コマ1枚。倍率1.0 = 表示の大きさのドット絵。pscale は元にした原画の倍率)。
## 鯉口を切る・抜き始め・納刀の途中・溜め・振り抜き後の沈み・反動・調律の沈み/伸び(覚醒前)、
## 振り下ろしの溜め・振り抜き(覚醒後単体)、納刀・居合の構え・鯉口を切る・抜く瞬間・納め直し(覚醒後全体)。
const GENERATED := {
	"a0f": {"file": "musha_frames/a0f.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(79.9, 76.6), "tsuba": Vector2(98.8, 141.2), "mouth": Vector2(101.1, 143.9)},
	"a1c": {"file": "musha_frames/a1c.png", "size": Vector2(203, 274), "anchor": Vector2(101.0, 233.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.6, 92.7), "tsuba": Vector2(73.7, 147.7), "mouth": Vector2(111.3, 162.9)},
	"an1": {"file": "musha_frames/an1.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(79.9, 76.6), "tsuba": Vector2(76.4, 115.6), "mouth": Vector2(101.1, 143.9)},
	"an2": {"file": "musha_frames/an2.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(79.9, 76.6), "tsuba": Vector2(85.6, 126.2), "mouth": Vector2(101.1, 143.9)},
	"an3": {"file": "musha_frames/an3.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(79.9, 76.6), "tsuba": Vector2(93.5, 135.2), "mouth": Vector2(101.1, 143.9)},
	"kc": {"file": "musha_frames/kc.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(96.6, 158.8), "mouth": Vector2(100.0, 159.6)},
	"kc1": {"file": "musha_frames/kc1.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(75.5, 86.3), "tsuba": Vector2(97.5, 150.6), "mouth": Vector2(100.4, 152.4)},
	"kcd": {"file": "musha_frames/kcd.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(93.7, 158.0), "mouth": Vector2(100.0, 159.6)},
	"kcn1": {"file": "musha_frames/kcn1.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(67.5, 151.5), "mouth": Vector2(100.0, 159.6)},
	"kcn2": {"file": "musha_frames/kcn2.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(85.9, 156.1), "mouth": Vector2(100.0, 159.6)},
	"kcs14": {"file": "musha_frames/kcs14.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(83.0, 155.4), "mouth": Vector2(100.0, 159.6)},
	"kcs18": {"file": "musha_frames/kcs18.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(79.2, 154.4), "mouth": Vector2(100.0, 159.6)},
	"kcs22": {"file": "musha_frames/kcs22.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(75.3, 153.4), "mouth": Vector2(100.0, 159.6)},
	"kcs26": {"file": "musha_frames/kcs26.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(71.4, 152.5), "mouth": Vector2(100.0, 159.6)},
	"kcs3": {"file": "musha_frames/kcs3.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(93.2, 157.9), "mouth": Vector2(100.0, 159.6)},
	"kcs7": {"file": "musha_frames/kcs7.png", "size": Vector2(191, 275), "anchor": Vector2(99.0, 234.0), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(72.5, 94.4), "tsuba": Vector2(89.8, 157.1), "mouth": Vector2(100.0, 159.6)},
	"p0d": {"file": "musha_frames/p0d.png", "size": Vector2(393, 486), "anchor": Vector2(199.0, 449.0), "scale": 0.445, "patch": false, "eye": Vector2(134.8, 137.7), "hilt": Vector2(183.8, 232.3), "tsuba": Vector2(192.6, 243.7), "mouth": Vector2(225.2, 251.0)},
	"p0k": {"file": "musha_frames/p0k.png", "size": Vector2(393, 486), "anchor": Vector2(199.0, 449.0), "scale": 0.445, "patch": false, "eye": Vector2(144.0, 132.0), "hilt": Vector2(202.0, 233.0), "tsuba": Vector2(210.0, 245.0), "mouth": Vector2(228.0, 250.0)},
	"p2k": {"file": "musha_frames/p2k.png", "size": Vector2(229, 276), "anchor": Vector2(116.0, 230.0), "scale": 1.0, "patch": false, "pscale": 0.445, "eye": Vector2(91.5, 86.3), "tsuba": Vector2(119.5, 133.2), "mouth": Vector2(122.3, 135.2)},
	"p2n1": {"file": "musha_frames/p2n1.png", "size": Vector2(229, 276), "anchor": Vector2(116.0, 230.0), "scale": 1.0, "patch": false, "pscale": 0.445, "eye": Vector2(91.5, 86.3), "tsuba": Vector2(101.8, 120.0), "mouth": Vector2(122.3, 135.2)},
	"p2n2": {"file": "musha_frames/p2n2.png", "size": Vector2(229, 276), "anchor": Vector2(116.0, 230.0), "scale": 1.0, "patch": false, "pscale": 0.445, "eye": Vector2(91.5, 86.3), "tsuba": Vector2(109.1, 125.4), "mouth": Vector2(122.3, 135.2)},
	"p2n3": {"file": "musha_frames/p2n3.png", "size": Vector2(229, 276), "anchor": Vector2(116.0, 230.0), "scale": 1.0, "patch": false, "pscale": 0.445, "eye": Vector2(91.5, 86.3), "tsuba": Vector2(115.5, 130.2), "mouth": Vector2(122.3, 135.2)},
	"p3c": {"file": "musha_frames/p3c.png", "size": Vector2(483, 556), "anchor": Vector2(284.0, 510.0), "scale": 0.445, "patch": false, "eye": Vector2(272.8, 180.4), "hilt": Vector2(267.0, 77.7), "tip": Vector2(75.1, 26.2)},
	"p4i": {"file": "musha_frames/p4i.png", "size": Vector2(502, 510), "anchor": Vector2(312.0, 465.0), "scale": 0.445, "patch": false, "eye": Vector2(260.2, 136.3), "hilt": Vector2(214.1, 316.7), "tip": Vector2(51.0, 421.0)},
	"p4r": {"file": "musha_frames/p4r.png", "size": Vector2(502, 510), "anchor": Vector2(312.0, 465.0), "scale": 0.445, "patch": false, "eye": Vector2(276.4, 127.3), "hilt": Vector2(213.9, 315.6), "tip": Vector2(51.0, 421.0)},
	"p5d": {"file": "musha_frames/p5d.png", "size": Vector2(370, 513), "anchor": Vector2(189.0, 469.0), "scale": 0.445, "patch": false, "eye": Vector2(137.3, 136.7), "core": Vector2(163.3, 246.7), "tsuba": Vector2(186.6, 260.3)},
	"p5u": {"file": "musha_frames/p5u.png", "size": Vector2(370, 513), "anchor": Vector2(189.0, 469.0), "scale": 0.445, "patch": false, "eye": Vector2(145.5, 120.7), "core": Vector2(165.4, 233.3), "tsuba": Vector2(187.8, 250.3)},
	"s0c": {"file": "musha_frames/s0c.png", "size": Vector2(438, 758), "anchor": Vector2(216.0, 712.0), "scale": 0.415, "patch": false, "eye": Vector2(176.9, 315.2), "hilt": Vector2(193.3, 178.0), "tip": Vector2(349.7, 62.3)},
	"s3i": {"file": "musha_frames/s3i.png", "size": Vector2(553, 516), "anchor": Vector2(354.0, 466.0), "scale": 0.415, "patch": false, "eye": Vector2(239.8, 133.2), "hilt": Vector2(220.0, 334.0), "tip": Vector2(88.0, 462.0)},
}

static var _tex := {}
static var _prepared := false

static func _ensure() -> void:
	if _prepared:
		return
	_prepared = true
	for name in GENERATED:
		var e: Dictionary = GENERATED[name]
		var entry := e.duplicate()
		entry["tex"] = e.file
		entry["rect"] = Rect2(Vector2.ZERO, e.size)
		FR[name] = entry

static func has_frame(fr: String) -> bool:
	_ensure()
	return FR.has(fr)

static func texture(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(ROOT + path) as Texture2D
	return _tex[path]

static func state(fr: String, foot: Vector2) -> Dictionary:
	_ensure()
	return {"fr": fr, "foot": foot, "flip": false, "alpha": 1.0, "eye": true}

## 足元からの高さ h・横 x の点(左向き基準の局所座標)。変形はしない。
static func local(x: float, h: float, _s: Dictionary) -> Vector2:
	return Vector2(x, -h)

## 素材上の点 → ステージ座標。
static func map_point(s: Dictionary, src: Vector2) -> Vector2:
	_ensure()
	var f: Dictionary = FR[s.fr]
	var l: Vector2 = (src - (f.anchor as Vector2)) * float(f.scale)
	if bool(s.get("flip", false)):
		l.x = -l.x
	return (s.foot as Vector2).round() + l

static func has_point(s: Dictionary, key: String) -> bool:
	_ensure()
	return (FR[s.fr] as Dictionary).has(key)

static func point(s: Dictionary, key: String) -> Vector2:
	_ensure()
	return map_point(s, (FR[s.fr] as Dictionary)[key])

## 刀身(鍔元・切っ先)。無いコマは空。
static func blade(s: Dictionary) -> Array:
	_ensure()
	var f: Dictionary = FR[s.fr]
	if not f.has("hilt") or not f.has("tip"):
		return []
	return [map_point(s, f.hilt), map_point(s, f.tip)]

## 1コマを描く。mod で色・不透明度を掛ける。
static func draw(ci: CanvasItem, s: Dictionary, mod: Color = Color.WHITE) -> void:
	_ensure()
	var f: Dictionary = FR[s.fr]
	var tx := texture(f.tex)
	if tx == null:
		return
	var m := Color(mod.r, mod.g, mod.b, mod.a * float(s.get("alpha", 1.0)))
	if m.a <= 0.01:
		return
	var r: Rect2 = f.rect
	var sc: float = f.scale
	var an: Vector2 = f.anchor
	var flip := bool(s.get("flip", false))
	ci.draw_set_transform((s.foot as Vector2).round(), 0.0, Vector2(-sc if flip else sc, sc))
	ci.draw_texture_rect_region(tx, Rect2(r.position - an, r.size), r, m)
	# 覚醒後の素材: 原画の眼を暗色で覆い、点灯時だけ細い赤線を描く(本番の覚醒後の本体と同じ扱い)。
	# 大きさは原画の画素で決まっているので、表示の大きさで作ったコマ(倍率1)では原画の倍率を掛ける。
	if bool(f.get("patch", false)) and f.has("eye"):
		var e: Vector2 = (f.eye as Vector2) - an
		var ps := float(f.get("pscale", sc)) / sc
		ci.draw_rect(Rect2(e - Vector2(7, 10) * ps, Vector2(15, 21) * ps), Color(.035, .027, .032, m.a))
		if bool(s.get("eye", true)):
			ci.draw_rect(Rect2(e - Vector2(10, 2) * ps, Vector2(20, 4) * ps), Color(1, .04, .05, m.a))
			ci.draw_rect(Rect2(e - Vector2(4, 1) * ps, Vector2(8, 2) * ps), Color(1, .6, .52, m.a))
	ci.draw_set_transform(Vector2.ZERO)