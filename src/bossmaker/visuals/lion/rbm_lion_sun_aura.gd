class_name RBMLionSunAura
extends Node2D
## 日蝕の獅皇の覚醒後の常時オーラ（太陽。2026-11-12 ユーザー採用）: 体の輪郭から立ち上る金色のグラデーションの炎・足元の金の光・昇る金の粒。
## 炎の形はヒーローの黒い炎（RBMHeroDarkAura）と同じ作り方で、色だけ体に近いほど白金→外へ金・橙・紅（shaders/sun_aura.gdshader）。
## 輪郭からの距離はポーズごとに事前に焼いた物（RBMLionMotion.field_path、tools/lion/bake_lion_assets.gd）。戦闘中に計算しない。
## 座標は絵の画素（320×180 のキーポーズの座標）。表示専用。

const PAL := ["#8a2a0c", "#d0581a", "#f29424", "#ffc63c", "#ffe88c", "#fff8e0"]
const POOL := ["#3a1a06", "#7a3a0c", "#c0701a", "#f0a830", "#ffe08a"]
const POOL_SIZE := Vector2(200, 60)
const EMBERS := 18
const SHADER_PATH := "res://src/bossmaker/visuals/lion/shaders/sun_aura.gdshader"

static var _fields := {}

var flames: Sprite2D
var pool: ColorRect
var motes: RBMHeroFxBatch

## そのポーズの焼いた距離（無いポーズは null）。
static func field(move: String, n: int) -> Texture2D:
	var key := "%s_%d" % [move, n]
	if not _fields.has(key):
		var path := RBMLionMotion.field_path(move, n)
		_fields[key] = load(path) as Texture2D if RBMLionMotion.has_field(move, n) and ResourceLoader.exists(path) else null
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
	var origin := sprite_top_left + RBMLionMotion.field_origin(move, n)
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
		var c := Color("#ffd27a" if i % 3 else "#fff1c8", sin(q * PI) * 0.8 * minf(power, 1.0))
		motes.dot_px(p, 1.0 + float(i % 3 == 0), c)
	motes.commit()
