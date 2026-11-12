class_name RBMHeroDarkAura
extends Node2D
## 体の輪郭から立ち上る炎のオーラ。覚醒後は黒い炎（style="dark"）、覚醒前の①の溜めは同じ形の青い炎（style="blue"）。
## コマの輪郭は読むだけで、本体の絵は変えない。強さは view["hero"]["dark_aura"]（0で消える）。
## 待機中も出し続けるので、輪郭からの距離はコマごとに事前に焼いておき（tools/hero_boss/bake_hero_boss_assets.gd → aura_fields/<コマ名>.res）、
## 毎フレームの処理は軽くしている。戦闘中に距離を計算しない。

const M_SIDE := 34
const M_TOP := 64
const M_BOT := 8
const FAR := 1000.0
## 上へは伸びやすく、下へは伸びにくい（炎の形になる）
const C_UP := 0.55
const C_UP_D := 0.8
const C_SIDE := 1.0
const C_DOWN := 2.2
const C_DOWN_D := 1.7
const STYLES := {
	"dark": {"flame": ["#05030a", "#2a0b2a", "#5a0e30", "#a0132f", "#ed274c"], "pool": ["#05030a", "#12071a", "#2a0b2a", "#5a0e30", "#a0132f"], "glow": Vector3(.8, .05, .16), "glow_amt": .14, "ember": Color("#ed274c")},
	"blue": {"flame": ["#1a58d0", "#123a96", "#2f9cf5", "#5cc6fa", "#c8f4ff"], "pool": ["#0a1a52", "#0e2f86", "#123a96", "#1f68e4", "#5cc6fa"], "glow": Vector3(.25, .6, 1.), "glow_amt": .26, "ember": Color("#c8f4ff")},
	"blue_big": {"flame": ["#1a58d0", "#123a96", "#2f9cf5", "#5cc6fa", "#c8f4ff"], "pool": ["#0a1a52", "#0e2f86", "#123a96", "#1f68e4", "#5cc6fa"], "glow": Vector3(.25, .6, 1.), "glow_amt": .3, "ember": Color("#c8f4ff"), "reach": 36.0, "max_r": 31.0},
}
## 焼いた距離の置き場（コマ名.res、ImageTexture）。
const FIELD_ROOT := "res://assets_bossmaker/battle/hero_boss/aura_fields/"
const POOL_SIZE := Vector2(180, 64)
const EMBER_COUNT := 14

var flames: Sprite2D
var pool: ColorRect
var motes: RBMHeroFxBatch
var ember_col := Color.WHITE
static var _fields := {}

static func field_path(cel: String) -> String:
	return FIELD_ROOT + cel + ".res"

## そのコマの焼いた距離（無いコマは null）。
static func field(cel: String) -> Texture2D:
	if not _fields.has(cel):
		var path := field_path(cel)
		_fields[cel] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _fields[cel]

func setup(style_name: String = "dark") -> void:
	var style: Dictionary = STYLES[style_name]
	ember_col = style["ember"]
	pool = ColorRect.new()
	pool.size = POOL_SIZE
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("pool")
	pm.set_shader_parameter("size", POOL_SIZE)
	pm.set_shader_parameter("center", POOL_SIZE * 0.5)
	pm.set_shader_parameter("pal", RBMHeroFx.pal(style["pool"]))
	pm.set_shader_parameter("squash", 0.26)
	pm.set_shader_parameter("seed", 5.3)
	pm.set_shader_parameter("clip_y", -1.0)
	pool.material = pm
	add_child(pool)
	motes = RBMHeroFxBatch.new()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = add_mat
	add_child(motes)
	flames = Sprite2D.new()
	flames.centered = false
	flames.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m := ShaderMaterial.new()
	m.shader = RBMHeroFx.shader("dark_aura")
	m.set_shader_parameter("pal", RBMHeroFx.pal(style["flame"]))
	m.set_shader_parameter("glow_col", style["glow"])
	m.set_shader_parameter("glow", style["glow_amt"])
	m.set_shader_parameter("reach", style.get("reach", 26.0))
	m.set_shader_parameter("max_r", style.get("max_r", 24.0))
	m.set_shader_parameter("seed", 3.7)
	flames.material = m
	add_child(flames)
	visible = false

## 輪郭からの距離と「一番近い体の点」を計算して RGBA の画像にする（焼く道具だけが使う。戦闘中は呼ばない）。
static func compute_field(data: PackedByteArray, sheet_w: int, rx: int, ry: int, w: int, h: int) -> Image:
	var fw := w + M_SIDE * 2
	var fh := h + M_TOP + M_BOT
	var up := PackedFloat32Array()
	up.resize(fw * fh)
	up.fill(FAR)
	var iso := up.duplicate()
	var src := PackedInt32Array()
	src.resize(fw * fh)
	src.fill(-1)
	for y in range(h):
		for x in range(w):
			if data[((ry + y) * sheet_w + rx + x) * 4 + 3] > 127:
				var i := (y + M_TOP) * fw + x + M_SIDE
				up[i] = 0.0
				iso[i] = 0.0
				src[i] = i
	# [行のずれ, 列のずれ, 上へ伸びやすい距離の重み, 同じ距離の重み]
	var from_above := [[-1, 0, C_DOWN, 1.0], [-1, -1, C_DOWN_D, 1.414], [-1, 1, C_DOWN_D, 1.414], [0, -1, C_SIDE, 1.0]]
	var from_below := [[1, 0, C_UP, 1.0], [1, -1, C_UP_D, 1.414], [1, 1, C_UP_D, 1.414], [0, 1, C_SIDE, 1.0]]
	for pass_i in range(3):
		var forward := pass_i % 2 == 0
		var steps: Array = from_above if forward else from_below
		var ys: Array = range(fh) if forward else range(fh - 1, -1, -1)
		var xs: Array = range(fw) if forward else range(fw - 1, -1, -1)
		for y: int in ys:
			for x: int in xs:
				var i := y * fw + x
				var u := up[i]
				var v := iso[i]
				var s_ := src[i]
				for st: Array in steps:
					var ny: int = y + st[0]
					var nx: int = x + st[1]
					if ny < 0 or ny >= fh or nx < 0 or nx >= fw:
						continue
					var j := ny * fw + nx
					var cand: float = up[j] + st[2]
					if cand < u:
						u = cand
						s_ = src[j]
					v = minf(v, iso[j] + st[3])
				up[i] = u
				iso[i] = v
				src[i] = s_
	var bytes := PackedByteArray()
	bytes.resize(fw * fh * 4)
	for i in range(fw * fh):
		bytes[i * 4] = clampi(int(up[i] / 64.0 * 255.0), 0, 255)
		bytes[i * 4 + 1] = clampi(int(iso[i] / 64.0 * 255.0), 0, 255)
		if src[i] >= 0:
			bytes[i * 4 + 2] = int(float(src[i] % fw) / (fw - 1) * 255.0)
			bytes[i * 4 + 3] = int(float(src[i] / fw) / (fh - 1) * 255.0)
	return Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8, bytes)

## cel: 今のコマ / top_left: コマの左上 / ground: 足元の地面 / lift: 地面からの高さ / power: 強さ / t: 経過秒
func show_on(cel: String, top_left: Vector2, ground: Vector2, lift: float, power: float, t: float, rise: float = 1.0) -> void:
	var tex := field(cel)
	visible = power > 0.001 and tex != null
	if not visible:
		return
	flames.texture = tex
	var origin := top_left - Vector2(M_SIDE, M_TOP)
	flames.position = origin
	var m := flames.material as ShaderMaterial
	m.set_shader_parameter("flow", t)
	m.set_shader_parameter("power", power)
	m.set_shader_parameter("rise", rise)
	m.set_shader_parameter("world_origin", origin)
	# 足元の闇（跳んでいる間は薄く小さく）
	var low := 1.0 - minf(1.0, lift / 70.0)
	pool.visible = low > 0.02
	if pool.visible:
		pool.position = (ground - POOL_SIZE * 0.5).round()
		var pm := pool.material as ShaderMaterial
		pm.set_shader_parameter("radius", (34.0 + 8.0 * minf(power, 1.5)) * lerpf(0.4, 1.0, low) * minf(power * 2.0, 1.0))
		pm.set_shader_parameter("flow", t * 0.6)
		pm.set_shader_parameter("fade", low)
	# 紅い火の粉（少なく、ゆっくり）
	motes.reset()
	var center := top_left.x + flames.texture.get_width() * 0.5 - M_SIDE
	for i in range(EMBER_COUNT):
		var q := fmod(t * (0.22 + 0.2 * RBMHeroFx.r(i, 7)) + RBMHeroFx.r(i, 9), 1.0)
		var p := Vector2(center + (RBMHeroFx.r(i, 11) - 0.5) * 92.0 + sin(t * 1.3 + float(i)) * 5.0, ground.y - lift - q * (70.0 + 70.0 * RBMHeroFx.r(i, 13)))
		var c := Color(ember_col, sin(q * PI) * 0.85 * minf(power, 1.0))
		motes.dot_px(p, 1.0 + float(i % 3 == 0), c)
	motes.commit()
