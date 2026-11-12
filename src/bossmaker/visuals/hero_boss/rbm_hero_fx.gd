class_name RBMHeroFx
extends RefCounted
## ヒーローのエフェクトの基礎部品（色の段階・時間の曲線・再現性のある乱数）。本体の絵には触れない。

const WORLD := Rect2(-100, -100, 840, 560)

const FIRE := ["#26222e", "#3a3440", "#4e3a44", "#c84a1c", "#ff8a24", "#ffc25e", "#fff0c4", "#ffffff"]
const PLASMA := ["#22263a", "#2c3a62", "#1f68e4", "#2f9cf5", "#5cc6fa", "#9fe6ff", "#dcf8ff", "#ffffff"]
const DARK := ["#05030a", "#12071a", "#2a0b2a", "#5a0e30", "#a0132f", "#ed274c", "#ff8a78", "#ffefe8"]
const VOID := ["#020105", "#07040c", "#100618", "#1c0a22", "#3a0f33", "#7a1030", "#d41f42", "#ff9a88"]

const R_BLUE := ["#123a96", "#1f68e4", "#4dbbf6", "#9fe6ff", "#e6fbff", "#ffffff"]
const R_AMBER := ["#e8581a", "#ff8f26", "#ffb347", "#ffd27a", "#fff1c8", "#ffffff"]
const R_DARK := ["#12071a", "#3a0f33", "#a0132f", "#ed274c", "#ff9a88", "#fff2ee"]
const R_VOID := ["#ed274c", "#7a1030", "#12071a", "#05030a", "#05030a", "#ffd8d0"]
const R_TEAR := ["#05030a", "#05030a", "#7a1030", "#ed274c", "#ffb0a0", "#ffffff"]

const A4_BLUE := ["#1f68e4", "#4dbbf6", "#c8f4ff", "#ffffff"]
const A4_AMBER := ["#e8581a", "#ff9f29", "#ffe0a0", "#ffffff"]
const A4_RED := ["#7a1030", "#ed274c", "#ff9a88", "#fff2ee"]
const A4_DARK := ["#05030a", "#3a0f33", "#ed274c", "#ffb0a0"]

const AURA_BLUE := ["#123a96", "#1f68e4", "#2f9cf5", "#5cc6fa", "#c8f4ff", "#ffffff"]
const AURA_DARK := ["#05030a", "#12071a", "#3a0f33", "#a0132f", "#ed274c", "#ffc0b0"]
const POOL_DARK := ["#05030a", "#1c0a22", "#5a0e30", "#ed274c", "#ffb0a0"]

const C_WHITE := Color("#ffffff")
const C_HOT := Color("#fff1c8")
const C_GOLD := Color("#ffd27a")
const C_AMBER := Color("#ff9f29")
const C_ORANGE := Color("#f0641e")
const C_PALE := Color("#c8f4ff")
const C_CYAN := Color("#4dbbf6")
const C_BLUE := Color("#1f68e4")
const C_DEEP := Color("#123a96")
const C_RED := Color("#ed274c")
const C_CRIM := Color("#a0132f")
const C_ROSE := Color("#ff9a88")
const C_VOID := Color("#05030a")
const C_PLUM := Color("#3a0f33")

static var _shaders := {}

static func shader(name_: String) -> Shader:
	if not _shaders.has(name_):
		_shaders[name_] = load("res://src/bossmaker/visuals/hero_boss/shaders/%s.gdshader" % name_)
	return _shaders[name_]

static func pal(hexes: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for h in hexes:
		var c := Color(str(h))
		out.append(Vector3(c.r, c.g, c.b))
	return out

static func v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

static func r(i: int, salt: int = 0) -> float:
	var x := sin(float(i) * 127.1 + float(salt) * 311.7 + 0.37) * 43758.5453
	return x - floor(x)

static func sat(x: float) -> float:
	return clampf(x, 0.0, 1.0)

static func ramp(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t) if b > a else (1.0 if t >= b else 0.0)

static func env(t: float, a: float, b: float, c: float, d: float) -> float:
	return ramp(t, a, b) * (1.0 - ramp(t, c, d))

static func key(t: float, pts: Array) -> float:
	if t <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(pts.size() - 1):
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if t <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), ramp(t, float(a[0]), float(b[0])))
	return float(pts[-1][1])

## 速く出て、ゆっくり止まる（爆発・衝撃波の広がり）。
static func burst(a: float, speed: float = 7.0) -> float:
	return 1.0 - exp(-maxf(a, 0.0) * speed)

## 本体のヒットストップに合わせて、命中直後の経過時間を遅くする。
static func stop_age(a: float) -> float:
	if a > 0.032 and a < 0.165:
		return 0.032 + (a - 0.032) * ramp(a, 0.091, 0.165)
	return a

## 2点を結ぶ弓なりの線（斬撃の道筋）。
static func bow(p0: Vector2, p1: Vector2, bulge: float, n: int = 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d := (p1 - p0)
	var nv := Vector2(-d.y, d.x).normalized()
	for i in range(n + 1):
		var u := float(i) / n
		out.append(p0 + d * u + nv * sin(u * PI) * bulge)
	return out
