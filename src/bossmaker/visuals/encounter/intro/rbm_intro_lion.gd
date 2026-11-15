extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 金環の聖獣の登場（2026-11-13 ユーザーの案）。中身は rbm_lion_fx_intro.gd（剣の雨 → 巨大な剣 → 金の大爆発 → 聖獣が現れて咆哮）。
## 本体は Codex のキーポーズをそのまま使い（咆哮＝覚醒前全体の3枚目 → 立ち姿）、エフェクトは戦闘の演出と同じ部品で描く。
## カメラは寄らない（揺れだけ。ヒーローで「ズームが見づらい」と言われたため）。音は1本（assets_bossmaker/audio/lion/intro.wav）。

const FxIntro = preload("res://src/bossmaker/visuals/lion/rbm_lion_fx_intro.gd")
const SOUNDS := ["game:lion/intro"]
const EXTRA_PATHS := [
	"res://assets_bossmaker/battle/lion/motion/pre_all/03.png", "res://assets_bossmaker/battle/lion/motion/awaken/01.png",
	"res://src/bossmaker/visuals/hero_boss/shaders/actor.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/blast.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/post.gdshader",
]
const HOME_FOOT := Vector2(390, 237)
const ORIGIN := RBMLionMotion.ORIGIN
const POST_MARGIN := 32.0
const POST_DEFAULTS := {"chroma": 0.0, "radial": 0.0, "split_amt": 0.0, "split_head": 99.0, "split_soft": .18, "split_gap": 0.0, "corrupt": 0.0, "desat": 0.0, "tint": Color.WHITE, "vig": 0.0, "impact": 0.0, "flash": 0.0}

var _world: Node2D
var _dim: ColorRect
var _post: ColorRect
var _body: Sprite2D
var _body_mat: ShaderMaterial
var _fx: RBMLionFxBase
var _textures := {}
var _offset := Vector2.ZERO

func prepare() -> void:
	super.prepare()
	_textures[3] = load(RBMLionMotion.pose_path("pre_all", 3))
	_textures[0] = load(RBMLionMotion.stance_path("pre"))
	_offset = p.boss_foot() - HOME_FOOT * 2.0
	_dim = ColorRect.new()
	_dim.name = "LionIntroDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_dim.size = p.stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_dim.color = Color(0, 0, 0, 0)
	_dim.z_index = 1
	p.stage.add_child(_dim)
	p.stage.move_child(_dim, 1)
	_world = Node2D.new()
	_world.name = "LionIntroWorld"
	_world.scale = Vector2(2, 2)
	_world.position = _offset
	p.stage.add_child(_world)
	var back := _layer("LionIntroBack", 1)
	var actor := _layer("LionIntroBody", 3)
	var front := _layer("LionIntroFront", 5)
	_body = Sprite2D.new()
	_body.centered = false
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = RBMHeroFx.shader("actor")
	_body.material = _body_mat
	actor.add_child(_body)
	_fx = FxIntro.new()
	_fx.seq = "pre_all"
	_fx.mid = back
	_world.add_child(_fx)
	_fx.setup(back, front, [])
	_post = ColorRect.new()
	_post.name = "LionIntroPost"
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_post.size = p.stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_post.z_index = 6
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("post")
	_post.material = pm
	p.stage.add_child(_post)
	# 登場の再生が終わる・やめる時に、ここで作った物も消す
	p.tree_exiting.connect(_cleanup, CONNECT_ONE_SHOT)
	bs = {}

func _layer(layer_name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	n.z_index = z
	_world.add_child(n)
	return n

func _cleanup() -> void:
	if _only_moved(p):
		# 戦闘画面の配置の移動でステージごと木から外れただけ（登場は続いている）。次に外れる時にもう一度確かめる。
		var player: Node = p
		(func():
			if is_instance_valid(player) and not player.tree_exiting.is_connected(_cleanup):
				player.tree_exiting.connect(_cleanup, CONNECT_ONE_SHOT)).call_deferred()
		return
	for n in [_world, _dim, _post]:
		if is_instance_valid(n):
			n.queue_free()

## n が消されるのではなく、配置の移動で木から外れただけか（n か祖先のどれかが消される予定なら false）。
static func _only_moved(n: Node) -> bool:
	if not is_instance_valid(n):
		return false
	while n != null:
		if n.is_queued_for_deletion():
			return false
		n = n.get_parent()
	return true

func duration() -> float:
	return float(_fx.unwarp(float(FxIntro.T.end))) if _fx != null else 5.1

func advance(t: float, _dt: float) -> void:
	fade_in(t, 0.36, 0.25)
	bars(t, 0.30)
	p.se(0.34, "game:lion/intro", 1.0)
	var te: float = _fx.warp(t)
	_fx.advance_pose(te)
	var view: Dictionary = _fx.view
	var body: Dictionary = view.get("body", {})
	var hero_info: Dictionary = view.get("hero", {})
	var dc: Color = view.get("dim_col", Color(0.02, 0.02, 0.05))
	dc.a = float(view.get("dim", 0.0))
	_dim.color = dc
	var tex: Texture2D = _textures.get(int(body.get("pose", 0)), _textures[0])
	_body.texture = tex
	_body.position = HOME_FOOT + Vector2(body.get("off", Vector2.ZERO)) - ORIGIN
	_body.visible = not bool(body.get("hidden", false))
	_body.modulate.a = float(body.get("alpha", 1.0))
	_body_mat.set_shader_parameter("rim_amt", float(hero_info.get("lit", 0.0)))
	_body_mat.set_shader_parameter("rim_col", hero_info.get("lit_col", Color.WHITE))
	_body_mat.set_shader_parameter("rim_side", 0.0)
	_body_mat.set_shader_parameter("flash", float(hero_info.get("flash", 0.0)))
	_body_mat.set_shader_parameter("flash_col", hero_info.get("flash_col", Color.WHITE))
	# 揺れ（戦場のカメラ。強さの設定を掛ける）
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	p.camera._offset = (shake * 2.0 * p.camera.shake_strength()).snapped(Vector2(2, 2))
	p.camera.apply()
	_apply_post(view, te)
	var T: Dictionary = FxIntro.T
	p.at(float(T.giant_hit), "brace", func(): allies_brace(true, 4.0))
	p.at(float(T.stance) + 0.3, "relax", func(): allies_brace(false))
	ally_tint(Color.WHITE.lerp(Color(0.55, 0.55, 0.62), float(view.get("dim", 0.0))))
	title_card(t, 3.45, Color(1.0, 0.82, 0.4))

func _apply_post(view: Dictionary, t: float) -> void:
	# 屈折の輪が無い間は画面全体の処理を止める（何もしない時は画面を写すだけで、見た目は同じ）
	_post.visible = not (view.get("rings", []) as Array).is_empty()
	if not _post.visible:
		return
	var pm := _post.material as ShaderMaterial
	pm.set_shader_parameter("time", t)
	for k in POST_DEFAULTS:
		pm.set_shader_parameter(k, POST_DEFAULTS[k])
	var rings := PackedVector4Array()
	var screen := _post.get_viewport_rect().size
	var scale_y: float = 2.0 * p.stage.get_global_transform_with_canvas().get_scale().y / maxf(screen.y, 1.0)
	for ring in view.get("rings", []):
		var c: Vector2 = p.stage.get_global_transform_with_canvas() * (Vector2(ring.x, ring.y) * 2.0 + _offset)
		var ruv := c / screen
		rings.append(Vector4(ruv.x, ruv.y, ring.z * scale_y, ring.w))
		if rings.size() >= 6:
			break
	var count := rings.size()
	while rings.size() < 6:
		rings.append(Vector4.ZERO)
	pm.set_shader_parameter("rings", rings)
	pm.set_shader_parameter("ring_count", count)
