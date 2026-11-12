extends "res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_canvas.gd"
## ヒーローの覚醒後の撃破（2026-11-11。表示専用。戦闘の状態・乱数・保存データには触れない）。
## とどめのスロー（全ボス共通）→ 膝をつく → 闇が暴れ、内から青い光が漏れる（鼓動3回）→ 闇が爆ぜて黒紅の炎と青い光の柱
## → 元の青い姿で膝をつき → 青い光の粒になって昇る（共通の四角い粒の消え方）。
## 本体の絵は正式モーションのコマ（tools/hero_boss/bake_hero_boss_assets.gd が1枚ずつに切り出した物）をそのまま使い、伸縮・回転しない。
## エフェクトは rbm_hero_fx_fall.gd、時刻は RBMHeroFxTiming.FALL、音は assets_bossmaker/audio/hero_boss/awakened_defeat.wav（1本）。

const FallFx = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_fall.gd")
const Presentation = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_presentation.gd")
const T := RBMHeroFxTiming.FALL
const ROOT := "res://assets_bossmaker/battle/hero_boss_awakened/defeat/"
const FIELDS := "res://assets_bossmaker/battle/hero_boss/aura_fields/"
const SHADER_ROOT := "res://src/bossmaker/visuals/hero_boss/shaders/"
## 撃破のコマの絵の大きさと足元（tools/hero_boss/bake_hero_boss_assets.gd の DEFEAT_CANVAS・DEFEAT_FOOT と同じ）
const DEFEAT_CANVAS := Vector2(112, 100)
const DEFEAT_FOOT := Vector2(56, 98)
## コマの左上と大きさ（立ち姿 omega の足元＝立ち絵の足元からの相対、論理ドット）
const CEL_TOP_LEFT := {"omega": Vector2(-25, -90), "release2": Vector2(-28, -66), "release3": Vector2(-34, -92), "release1": Vector2(-47, -63)}
const CEL_SIZE := {"omega": Vector2(49, 90), "release2": Vector2(74, 66), "release3": Vector2(78, 92), "release1": Vector2(66, 63)}
const SOUND := "game:hero_boss/awakened_defeat"
const SOUNDS := [SOUND]
## 音の大きさ（技の音と同じ -8dB。RBMEncounterAudio の基準 -9dB からの差）
const SOUND_GAIN := 1.0
## とどめの一撃の前に読み終えておく物（RBMVictoryPlayer.final_blow_paths()・warm_paths()）
const VFX_PATHS := [
	ROOT + "omega.png", ROOT + "release2.png", ROOT + "release3.png", ROOT + "release1.png",
	FIELDS + "omega.res", FIELDS + "release2.res", FIELDS + "release3.res", FIELDS + "release1.res",
	SHADER_ROOT + "blast.gdshader", SHADER_ROOT + "cracks.gdshader", SHADER_ROOT + "pillar.gdshader", SHADER_ROOT + "pool.gdshader",
	SHADER_ROOT + "ring.gdshader", SHADER_ROOT + "post.gdshader", SHADER_ROOT + "dark_aura.gdshader",
]
## 体の色（内から漏れる光・爆発の閃光・戻った後の光）
const GLOW := Color("#5cc6fa")
const FLASH := Color("#e6fbff")
const POST_MARGIN := 32.0

var _tex := {}
var _world: Node2D
var _back: Node2D
var _front: Node2D
var _fx: RBMHeroFxBase
var _aura_dark: RBMHeroDarkAura
var _aura_blue: RBMHeroDarkAura
var _post: ColorRect
var _aura_t := 0.0
var _flat_col := Color.WHITE

func duration() -> float:
	return float(T.end)

func setup() -> void:
	super.setup()
	for cel in CEL_TOP_LEFT:
		_tex[cel] = load(ROOT + cel + ".png")
	_world = Node2D.new()
	_world.name = "HeroDefeatWorld"
	_world.scale = Vector2(2, 2)
	_world.position = home() - Presentation.HOME_FOOT * 2.0
	_world.z_index = 1
	_back = Node2D.new()
	_back.name = "HeroDefeatBack"
	_world.add_child(_back)
	_front = Node2D.new()
	_front.name = "HeroDefeatFront"
	_front.z_index = 4
	_world.add_child(_front)
	_aura_dark = RBMHeroDarkAura.new()
	_back.add_child(_aura_dark)
	_aura_dark.setup("dark")
	_aura_blue = RBMHeroDarkAura.new()
	_back.add_child(_aura_blue)
	_aura_blue.setup("blue")
	_aura_blue.visible = false
	_fx = FallFx.new()
	_world.add_child(_fx)
	_fx.setup(_back, _front, [])
	# 本体（boss_body）より前に置き、オーラ・爆炎・光の柱を本体の後ろに描く（z は本体と同じ1）
	p.stage.add_child(_world)
	p.stage.move_child(_world, p.boss_body.get_index())
	_post = ColorRect.new()
	_post.name = "HeroDefeatPost"
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_post.size = p.stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_post.z_index = 6
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("post")
	_post.material = pm
	_post.visible = false
	p.stage.add_child(_post)
	_show_aura(0.0)

func cleanup() -> void:
	if is_instance_valid(p.top) and not p.top.is_queued_for_deletion():
		# 戦闘画面の配置の移動でステージごと木から外れただけ（勝利の層は消されていない）。次に外れる時にもう一度確かめる。
		p.top.tree_exiting.connect.call_deferred(cleanup, CONNECT_ONE_SHOT)
		return
	super.cleanup()
	for n in [_world, _post]:
		if is_instance_valid(n):
			n.queue_free()

func final_blow() -> void:
	super.final_blow()
	bs["cel"] = "omega"

func final_advance(t: float, dt: float) -> void:
	super.final_advance(t, dt)
	_aura_t += dt * float(p.motion_speed)
	_show_aura(0.0)

func begin() -> void:
	super.begin()
	p.sfx.play(SOUND, SOUND_GAIN)

func advance(t: float, dt: float) -> void:
	age = t
	_aura_t += dt
	var cel := _cel_at(t)
	var shake := Vector2.ZERO
	var ten := FallFx.tension(t)
	if t >= float(T.kneel) and t < float(T.burst):
		# 闇が暴れる間、体が小さく震える（2px の格子）
		shake = Vector2(sin(t * 47.0), 0.0).snapped(Vector2.ONE) * roundf(ten * 2.0) * 2.0
	var recoil := 18.0 - 6.0 * RBMHeroFx.ramp(t, 0.0, float(T.kneel))
	bs["cel"] = cel
	bs["pose"] = 11
	bs["foot"] = home() + Vector2(recoil, 0) + shake
	var anchor := Presentation.HOME_FOOT + (Vector2(bs["foot"]) - home()) * 0.5
	var body_foot := anchor + Vector2(CEL_TOP_LEFT[cel].x + roundf(CEL_SIZE[cel].x * 0.5), 0)
	_fx.advance(t, cel, anchor, body_foot)
	_show_aura(t)
	_body_light(t)
	dim(Color(0.02, 0.01, 0.05), RBMHeroFx.key(t, [[0.0, 0.3], [float(T.kneel), 0.42], [float(T.burst) - 0.04, 0.72], [float(T.burst) + 0.12, 0.5], [float(T.restore), 0.45], [float(T.fade), 0.32], [float(T.gone), 0.0]]))
	_apply_post(t)
	# 体が光の粒になって昇る（共通の四角い粒の消え方。上から先にほどける）
	dissolve = smoothstep(float(T.fade), float(T.gone) - 0.08, t)
	rise = 0.9
	block = 3.0
	edge = Color(GLOW, 0.95)
	p.at(float(T.kneel), "hero_fall_kneel", func(): p.camera.shake(3, 0.2))
	for i in range(T.beats.size()):
		p.at(float(T.beats[i]), "hero_fall_beat_%d" % i, func(): p.camera.shake(2 + i, 0.14))
	p.at(float(T.burst), "hero_fall_burst", func(): p.camera.shake(10, 0.55))
	if t >= float(T.gone):
		gone = true
	if t > float(T.end) + 0.2:
		_world.visible = false
		_post.visible = false

## 暗幕だけを使う（共通の覚醒後の撃破の煙の部品 field は使わない）。
func dim(color: Color, amount: float) -> void:
	shade = Color(color, amount)
	veil.queue_redraw()

func _cel_at(t: float) -> String:
	if t < float(T.kneel):
		return "omega"
	if t < float(T.burst):
		return "release2"
	if t < float(T.restore):
		return "release3"
	return "release1"

## 覚醒後の常時オーラ（とどめから爆発まで、鼓動のたびに強くなる。途中で弱めない）→ 爆発で吹き飛ぶ → 元の姿の青い炎。
func _show_aura(t: float) -> void:
	var cel: String = bs.get("cel", "omega")
	var anchor := Presentation.HOME_FOOT + (Vector2(bs.get("foot", home())) - home()) * 0.5
	var top_left := anchor + Vector2(CEL_TOP_LEFT[cel])
	var dark := 0.0
	if t < float(T.burst):
		dark = 1.0 + 1.6 * FallFx.tension(t)
	_aura_dark.show_on(cel, top_left, anchor, 0.0, dark, _aura_t)
	var blue := 0.7 * RBMHeroFx.ramp(t, float(T.restore), float(T.restore) + 0.35) * (1.0 - RBMHeroFx.ramp(t, float(T.fade) + 0.2, float(T.gone) - 0.15))
	_aura_blue.show_on(cel, top_left, anchor, 0.0, blue, _aura_t)

## 体に重ねる単色（内から漏れる青い光・爆発の閃光・元の姿に戻った時の光）。とどめの白い点滅は共通のまま。
func _body_light(t: float) -> void:
	var a := t - float(T.burst)
	var leak := 0.0
	for at in T.beats:
		leak = maxf(leak, 0.32 * RBMHeroFx.env(t, float(at), float(at) + 0.04, float(at) + 0.08, float(at) + 0.3))
	leak = maxf(leak, 0.18 * FallFx.tension(t)) * (1.0 - RBMHeroFx.ramp(a, -0.01, 0.0))
	var burst := (1.0 - RBMHeroFx.ramp(a, 0.06, 0.2)) * RBMHeroFx.ramp(a, -0.001, 0.0)
	var restore := 0.55 * (1.0 - RBMHeroFx.ramp(t, float(T.restore), float(T.restore) + 0.3)) * RBMHeroFx.ramp(t, float(T.restore) - 0.001, float(T.restore))
	if burst > 0.0:
		_flat_col = FLASH
		white = burst
	elif restore > 0.0:
		_flat_col = FLASH
		white = restore
	else:
		_flat_col = GLOW
		white = leak

func _draw_flat(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or dissolve > 0.0 or white <= 0.0:
		return
	draw_sprite(ci, Color(_flat_col, white))

## 本体: 撃破のコマの絵を、立ち絵と同じ倍率・足元で描く（伸縮・回転しない）。
func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	var tex: Texture2D = _tex.get(str(bs.get("cel", "omega")))
	if tex == null or mod.a <= 0.003:
		return
	var foot: Vector2 = Vector2(bs.foot) + Vector2(0, sink)
	ci.draw_texture_rect(tex, Rect2(foot - DEFEAT_FOOT * 2.0, DEFEAT_CANVAS * 2.0), false, mod)

func _apply_post(t: float) -> void:
	var view: Dictionary = _fx.view
	var post_values: Dictionary = view.get("post", {})
	var rings_in: Array = view.get("rings", [])
	var active_post := not rings_in.is_empty() or float(post_values.get("desat", 0.0)) > 0.001 or float(post_values.get("vig", 0.0)) > 0.001
	_post.visible = active_post and t <= float(T.end)
	if not _post.visible:
		return
	var pm := _post.material as ShaderMaterial
	pm.set_shader_parameter("time", t)
	for k in Presentation.POST_DEFAULTS:
		pm.set_shader_parameter(k, Presentation.POST_DEFAULTS[k])
	pm.set_shader_parameter("focus", Vector2(0.5, 0.5))
	for k in post_values:
		if k == "focus_world":
			pm.set_shader_parameter("focus", _uv(post_values[k]))
		else:
			pm.set_shader_parameter(k, post_values[k])
	var rings := PackedVector4Array()
	var screen := _post.get_viewport_rect().size
	var scale_y: float = 2.0 * p.stage.get_global_transform_with_canvas().get_scale().y / maxf(screen.y, 1.0)
	for ring in rings_in:
		var ruv := _uv(Vector2(ring.x, ring.y))
		rings.append(Vector4(ruv.x, ruv.y, ring.z * scale_y, ring.w))
		if rings.size() >= 6:
			break
	var count := rings.size()
	while rings.size() < 6:
		rings.append(Vector4.ZERO)
	pm.set_shader_parameter("rings", rings)
	pm.set_shader_parameter("ring_count", count)

func _uv(world_point: Vector2) -> Vector2:
	var canvas: Vector2 = p.stage.get_global_transform_with_canvas() * (world_point * 2.0 + _world.position)
	return canvas / _post.get_viewport_rect().size
