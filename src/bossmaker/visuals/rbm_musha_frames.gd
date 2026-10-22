extends RefCounted
## Same approved frame sequence; all action sprites are redrawn from the original standing design.
## One complete native-grid image is drawn at a time. Timing, movement and combat contracts are unchanged.
const ROOT := "res://assets_bossmaker/battle/"
static var FR := {
	"idle": {"tex": "musha/design.png", "rect": Rect2(0,0,748,1410), "anchor": Vector2(374,1410), "scale": 180.0/1410.0, "eye": Vector2(265,243)},
	"p0": {"tex": "musha_frames/p0.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(219.00, 130.32), "hilt": Vector2(231.81, 183.15), "tsuba": Vector2(236.63, 189.89), "mouth": Vector2(238.23, 192.68)},
	"p1": {"tex": "musha_frames/p1.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(207.69, 131.30), "hilt": Vector2(107.02, 168.77), "tip": Vector2(24.17, 162.14)},
	"p2": {"tex": "musha_frames/p2.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(219.00, 130.36), "hilt": Vector2(228.46, 184.12), "tsuba": Vector2(233.16, 189.57), "mouth": Vector2(235.83, 192.46)},
	"p3": {"tex": "musha_frames/p3.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(222.98, 131.19), "hilt": Vector2(232.58, 81.20), "tip": Vector2(168.77, 64.99)},
	"p4": {"tex": "musha_frames/p4.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(219.45, 130.07), "hilt": Vector2(213.34, 206.75), "tip": Vector2(177.29, 274.80)},
	"p5": {"tex": "musha_frames/p5.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(219.05, 130.27), "core": Vector2(229.56, 170.89), "chest": Vector2(229.78, 167.90), "tsuba": Vector2(236.40, 190.21)},
	"p0k": {"tex": "musha_frames/p0k.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(217.53, 129.75), "hilt": Vector2(225.73, 181.47), "tsuba": Vector2(232.34, 188.07), "mouth": Vector2(236.38, 191.38)},
	"p0d": {"tex": "musha_frames/p0d.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(207.27, 134.71), "hilt": Vector2(218.12, 179.08), "tsuba": Vector2(222.71, 184.22), "mouth": Vector2(236.47, 193.03)},
	"p2n1": {"tex": "musha_frames/p2n1.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(218.75, 131.63), "tsuba": Vector2(214.29, 170.84), "mouth": Vector2(233.70, 186.72)},
	"p2n2": {"tex": "musha_frames/p2n2.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(218.07, 131.54), "tsuba": Vector2(227.90, 183.19), "mouth": Vector2(234.20, 186.72)},
	"p2n3": {"tex": "musha_frames/p2n3.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(217.70, 131.60), "tsuba": Vector2(229.66, 186.97), "mouth": Vector2(235.21, 186.72)},
	"a0": {"tex": "musha_frames/a0.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(221.32, 129.65), "tsuba": Vector2(237.52, 185.43), "mouth": Vector2(240.13, 188.82)},
	"a1": {"tex": "musha_frames/a1.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(217.63, 129.78), "tsuba": Vector2(221.96, 173.21), "mouth": Vector2(237.18, 186.06)},
	"a2": {"tex": "musha_frames/a2.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(220.07, 129.36), "hilt": Vector2(200.20, 183.16), "tip": Vector2(260.99, 183.68)},
	"a3": {"tex": "musha_frames/a3.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(218.56, 129.43), "hilt": Vector2(199.29, 207.42), "tip": Vector2(159.44, 274.19)},
	"s0": {"tex": "musha_frames/s0.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(214.16, 134.35), "hilt": Vector2(195.66, 101.65), "tip": Vector2(287.81, 66.97)},
	"s1": {"tex": "musha_frames/s1.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(202.31, 136.07), "hilt": Vector2(152.51, 149.94), "tip": Vector2(106.93, 76.20)},
	"s2": {"tex": "musha_frames/s2.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(197.90, 136.20), "hilt": Vector2(149.23, 172.07), "tip": Vector2(65.89, 172.41)},
	"s3": {"tex": "musha_frames/s3.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(203.36, 136.86), "hilt": Vector2(201.85, 222.14), "tip": Vector2(116.25, 272.22)},
	"an1": {"tex": "musha_frames/an1.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(220.29, 130.48), "tsuba": Vector2(215.12, 168.79), "mouth": Vector2(239.66, 188.97)},
	"an2": {"tex": "musha_frames/an2.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(220.71, 130.44), "tsuba": Vector2(231.80, 179.80), "mouth": Vector2(247.85, 188.97)},
	"an3": {"tex": "musha_frames/an3.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(220.79, 130.48), "tsuba": Vector2(243.61, 185.53), "mouth": Vector2(256.68, 188.97)},
	"kcn1": {"tex": "musha_frames/kcn1.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(217.51, 145.05), "tsuba": Vector2(203.15, 187.92), "mouth": Vector2(243.70, 195.94)},
	"kcs26": {"tex": "musha_frames/kcs26.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(217.27, 145.00), "tsuba": Vector2(206.53, 187.92), "mouth": Vector2(236.94, 195.94)},
	"kcs22": {"tex": "musha_frames/kcs22.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(217.20, 145.00), "tsuba": Vector2(206.42, 187.92), "mouth": Vector2(230.92, 195.94)},
	"kcs18": {"tex": "musha_frames/kcs18.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(217.17, 143.23), "tsuba": Vector2(211.62, 188.68), "mouth": Vector2(243.63, 196.79)},
	"kcs14": {"tex": "musha_frames/kcs14.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(216.89, 143.19), "tsuba": Vector2(221.54, 188.68), "mouth": Vector2(236.91, 196.79)},
	"kcn2": {"tex": "musha_frames/kcn2.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(216.85, 143.23), "tsuba": Vector2(228.16, 188.68), "mouth": Vector2(230.72, 196.79)},
	"kcs7": {"tex": "musha_frames/kcs7.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(217.21, 142.17), "tsuba": Vector2(234.84, 189.26), "mouth": Vector2(243.87, 197.43)},
	"kcs3": {"tex": "musha_frames/kcs3.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(216.78, 142.17), "tsuba": Vector2(237.85, 189.26), "mouth": Vector2(236.99, 197.43)},
	"kc": {"tex": "musha_frames/kc.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(216.78, 142.17), "tsuba": Vector2(232.47, 189.26), "mouth": Vector2(230.75, 197.43)},
	"p2k": {"tex": "musha_frames/p2k.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(219.00, 130.36), "hilt": Vector2(228.46, 184.12), "tsuba": Vector2(233.16, 189.57), "mouth": Vector2(235.83, 192.46)},
	"a0f": {"tex": "musha_frames/a0f.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(221.32, 129.65), "tsuba": Vector2(237.52, 185.43), "mouth": Vector2(240.13, 188.82)},
	"p3c": {"tex": "musha_frames/p3c.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(227.98, 132.19), "hilt": Vector2(240.58, 77.20), "tip": Vector2(176.77, 60.99)},
	"p4i": {"tex": "musha_frames/p4i.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(215.45, 133.07), "hilt": Vector2(213.12, 206.92), "tip": Vector2(177.29, 274.80)},
	"p4r": {"tex": "musha_frames/p4r.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(222.45, 129.07), "hilt": Vector2(213.51, 206.70), "tip": Vector2(177.29, 274.80)},
	"p5d": {"tex": "musha_frames/p5d.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(218.05, 133.27), "core": Vector2(228.91, 172.85), "chest": Vector2(229.07, 170.02), "tsuba": Vector2(236.11, 191.08)},
	"p5u": {"tex": "musha_frames/p5u.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(221.05, 126.27), "core": Vector2(230.87, 168.27), "chest": Vector2(231.19, 165.07), "tsuba": Vector2(236.98, 189.05)},
	"s0c": {"tex": "musha_frames/s0c.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(219.16, 134.35), "hilt": Vector2(204.19, 104.30), "tip": Vector2(296.81, 69.97)},
	"s3i": {"tex": "musha_frames/s3i.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "eye": Vector2(200.36, 140.86), "hilt": Vector2(201.85, 222.14), "tip": Vector2(116.25, 272.22)},
	"kc1": {"tex": "musha_frames/kc1.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(219.77, 134.19), "tsuba": Vector2(233.40, 186.80), "mouth": Vector2(231.27, 196.05)},
	"kcd": {"tex": "musha_frames/kcd.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(216.78, 142.17), "tsuba": Vector2(237.85, 189.26), "mouth": Vector2(236.99, 197.43)},
	"a1c": {"tex": "musha_frames/a1c.png", "rect": Rect2(0,0,360,300), "anchor": Vector2(240,280), "scale": 1.0, "patch": true, "pscale": 0.335, "eye": Vector2(215.53, 144.06), "tsuba": Vector2(202.48, 187.59), "mouth": Vector2(243.31, 195.75)},
}
const GENERATED := {}

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

## コマの画像のパス(演出の素材の事前読み込みの宣言用。rbm_presentation_warmup.gd)。無いコマは空文字。
static func texture_path(fr: String) -> String:
	_ensure()
	return ROOT + str(FR[fr].tex) if FR.has(fr) else ""

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