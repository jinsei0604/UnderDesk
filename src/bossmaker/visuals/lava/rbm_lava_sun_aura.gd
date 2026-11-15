class_name RBMLavaSunAura
extends Node2D
## 噴界炉の巨神の覚醒後の常時オーラ（2026-11-14 ユーザー「覚醒後はオーラ。それぞれのボスに合った色で」→ 溶岩の色）:
## 体の輪郭から立ち上る溶岩色のグラデーションの炎・足元の赤熱の光・昇る火の粉。
## 炎の形は日蝕の獅皇の太陽のオーラ（RBMLionSunAura）・ヒーローの黒い炎と同じ作り方で、色だけ変える（shaders/sun_aura.gdshader）。
## 輪郭からの距離はポーズごとに事前に焼いた物（RBMLavaMotion.field_path、tools/lava/bake_lava_assets.gd）。戦闘中に計算しない。
## 座標は絵の画素（320×180 のキーポーズの座標）。表示専用。

const PAL := ["#4a0c04", "#9a2008", "#d84a14", "#f68a1e", "#ffc440", "#fff2b8"]
const POOL := ["#2a0a04", "#6a1a08", "#c0400c", "#f08020", "#ffd060"]
const POOL_SIZE := Vector2(200, 60)
const EMBERS := 18
const MOTES := ["#ffb040", "#ff6a1e"]
const GLOW := Vector3(1., .42, .1)
const SHADER_PATH := "res://src/bossmaker/visuals/lava/shaders/sun_aura.gdshader"

static var _fields := {}

var flames: Sprite2D
var pool: ColorRect
var motes: RBMHeroFxBatch

## そのポーズの焼いた距離（無いポーズは null）。
static func field(move: String, n: int) -> Texture2D:
	var key := "%s_%d" % [move, n]
	if not _fields.has(key):
		var path := RBMLavaMotion.field_path(move, n)
		_fields[key] = load(path) as Texture2D if RBMLavaMotion.has_field(move, n) and ResourceLoader.exists(path) else null
	return _fields[key]

func setup() -> void:
	pool = ColorRect.new()
	pool.size = POOL_SIZE
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("pool")
	pm.set_shader_parameter("size", POOL_SIZE)
	pm.set_shader_parameter("center", POOL_SIZE * 0.5)
	pm.set_shader_parameter("pal", RBMHeroFx.pal(POOL))
	pm.set_shader_parameter("squash", 0.24)
	pm.set_shader_parameter("seed", 2.1)
	pm.set_shader_parameter("clip_y", -1.0)
	pool.material = pm
	add_child(pool)
	flames = Sprite2D.new()
	flames.centered = false
	flames.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	m.set_shader_parameter("pal", RBMHeroFx.pal(PAL))
	m.set_shader_parameter("glow_col", GLOW)
	m.set_shader_parameter("seed", 1.9)
	flames.material = m
	add_child(flames)
	motes = RBMHeroFxBatch.new()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = add_mat
	add_child(motes)
	visible = false

## move・n: 今のポーズ / sprite_top_left: キーポーズの絵の左上 / ground: 足元 / power: 強さ（0で消える） / t: 経過秒
func show_pose(move: String, n: int, sprite_top_left: Vector2, ground: Vector2, power: float, t: float) -> void:
	var tex := field(move, n)
	visible = power > 0.001 and tex != null
	if not visible:
		return
	var origin := sprite_top_left + RBMLavaMotion.field_origin(move, n)
	flames.texture = tex
	flames.position = origin
	var m := flames.material as ShaderMaterial
	m.set_shader_parameter("flow", t)
	m.set_shader_parameter("power", power)
	m.set_shader_parameter("world_origin", origin)
	pool.position = (ground - POOL_SIZE * 0.5).round()
	var pm := pool.material as ShaderMaterial
	pm.set_shader_parameter("radius", 44.0 * minf(power, 1.2))
	pm.set_shader_parameter("flow", t * 0.5)
	pm.set_shader_parameter("fade", 0.75 * minf(power, 1.0))
	motes.reset()
	var cx := origin.x + tex.get_width() * 0.5
	for i in range(EMBERS):
		var q := fmod(t * (0.25 + 0.2 * RBMHeroFx.r(i, 7)) + RBMHeroFx.r(i, 9), 1.0)
		var p := Vector2(cx + (RBMHeroFx.r(i, 11) - 0.5) * 120.0 + sin(t * 1.3 + float(i)) * 5.0, ground.y - q * (80.0 + 80.0 * RBMHeroFx.r(i, 13)))
		var c := Color(MOTES[0] if i % 3 else MOTES[1], sin(q * PI) * 0.8 * minf(power, 1.0))
		motes.dot_px(p, 1.0 + float(i % 3 == 0), c)
	motes.commit()
