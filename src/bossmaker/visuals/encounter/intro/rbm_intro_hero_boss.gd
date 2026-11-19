extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## ヒーローの登場「救難信号」（2026-11-17）。中身は rbm_hero_fx_intro.gd（時刻 RBMHeroFxTiming.INTRO）。作りは金環の聖獣・白磁のカラーの登場と同じ。
## 屋上の2つの照射器が最初から着地点の床を照らしている（動かさない）→ 流れ星が光の中へ落ちてヒーロー着地 → 立ち上がり、照射器に照らされて腕を組む
## → 腕を組んだまま背後で大爆発 → 構え・題字（2026-11-19 ユーザーの指摘で照射器を動かさない・手を突き出すコマを使わない形に）。本体は正式モーションのコマ（motion/cels.png）をそのまま切り替えるだけ（中割り・変形なし）。
## カメラは寄らない（揺れだけ）。音は1本（assets_bossmaker/audio/hero_boss/intro.wav。演出の0秒＝音の0秒）。
## 演出は画面が黒から出た所（LEAD）から始める。
const FxIntro = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_intro.gd")
const Motion = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_motion.gd")
const SOUNDS := ["game:hero_boss/intro"]
const EXTRA_PATHS := [
	"res://assets_bossmaker/battle/hero_boss/motion/cels.png",
	"res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/pool.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/actor.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/blast.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/post.gdshader",
]
const HOME_FOOT := Vector2(390, 238)
## 演出の0秒（画面が黒から出る所。fade_in と同じ）
const LEAD := 0.36
## 構えた後、題字を読めるだけ待つ
const HOLD := 0.35
## 題字を出す時刻（演出の秒）
const TITLE_AT := 3.2
const POST_MARGIN := 32.0
const POST_DEFAULTS := {"chroma": 0.0, "radial": 0.0, "split_amt": 0.0, "split_head": 99.0, "split_soft": .18, "split_gap": 0.0, "corrupt": 0.0, "desat": 0.0, "tint": Color.WHITE, "vig": 0.0, "impact": 0.0, "flash": 0.0}

var _world: Node2D
var _dim: ColorRect
var _post: ColorRect
var _body: Sprite2D
var _body_mat: ShaderMaterial
var _fx: RBMHeroFxBase
var _sheet: Texture2D
var _offset := Vector2.ZERO

func prepare() -> void:
	super.prepare()
	_fx = FxIntro.new()
	_sheet = load(Motion.SHEET_PATH) as Texture2D
	_offset = p.boss_foot() - HOME_FOOT * 2.0
	_dim = ColorRect.new()
	_dim.name = "HeroIntroDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_dim.size = p.stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_dim.color = Color(0, 0, 0, 0)
	_dim.z_index = 1
	p.stage.add_child(_dim)
	p.stage.move_child(_dim, 1)
	_world = Node2D.new()
	_world.name = "HeroIntroWorld"
	_world.scale = Vector2(2, 2)
	_world.position = _offset
	p.stage.add_child(_world)
	var back := _layer("HeroIntroBack", 1)
	var actor := _layer("HeroIntroBody", 3)
	var front := _layer("HeroIntroFront", 5)
	_body = Sprite2D.new()
	_body.texture = _sheet
	_body.region_enabled = true
	_body.centered = false
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = RBMHeroFx.shader("actor")
	_body.material = _body_mat
	actor.add_child(_body)
	_fx.mid = back
	_world.add_child(_fx)
	_fx.setup(back, front, [])
	_post = ColorRect.new()
	_post.name = "HeroIntroPost"
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_post.size = p.stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_post.z_index = 6
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("post")
	_post.material = pm
	_post.visible = false
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
	return LEAD + float(FxIntro.T.end) + HOLD

func advance(t: float, _dt: float) -> void:
	fade_in(t, LEAD, 0.25)
	bars(t, 0.30)
	p.se(LEAD, "game:hero_boss/intro", 1.0)
	var te: float = maxf(0.0, t - LEAD)
	_fx.advance(te, _fx.cel_at(te), HOME_FOOT, HOME_FOOT)
	var view: Dictionary = _fx.view
	var body: Dictionary = view.get("body", {})
	var hero_info: Dictionary = view.get("hero", {})
	var dc: Color = view.get("dim_col", Color(0.02, 0.02, 0.05))
	dc.a = float(view.get("dim", 0.0))
	_dim.color = dc
	var r := Motion.rect(str(body.get("cel", "normal")))
	_body.region_rect = r
	_body.position = (HOME_FOOT - Vector2(round(r.size.x * 0.5), r.size.y)).round()
	_body.visible = not bool(body.get("hidden", false))
	_body.modulate.a = float(body.get("alpha", 1.0))
	_body_mat.set_shader_parameter("rim_amt", float(hero_info.get("lit", 0.0)))
	_body_mat.set_shader_parameter("rim_col", hero_info.get("lit_col", Color.WHITE))
	_body_mat.set_shader_parameter("rim_side", 1.0)
	_body_mat.set_shader_parameter("flash", float(hero_info.get("flash", 0.0)))
	_body_mat.set_shader_parameter("flash_col", hero_info.get("flash_col", Color.WHITE))
	# 揺れ（戦場のカメラ。強さの設定を掛ける）
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	p.camera._offset = (shake * 2.0 * p.camera.shake_strength()).snapped(Vector2(2, 2))
	p.camera.apply()
	_apply_post(view, te)
	ally_tint(Color.WHITE.lerp(Color(0.55, 0.55, 0.62), float(view.get("dim", 0.0))))
	var T: Dictionary = FxIntro.T
	p.at(LEAD + float(T.land), "brace", func(): allies_brace(true, 3.0))
	p.at(LEAD + float(T.settle), "relax", func(): allies_brace(false))
	title_card(t, LEAD + TITLE_AT, Color(0.36, 0.78, 0.98))

func _apply_post(view: Dictionary, t: float) -> void:
	# 閃光・周辺減光・屈折の輪が無い間は画面全体の処理を止める（何もしない時は画面を写すだけで、見た目は同じ）
	var post_values: Dictionary = view.get("post", {})
	_post.visible = float(post_values.get("vig", 0.0)) > 0.001 or float(post_values.get("flash", 0.0)) > 0.001 or not (view.get("rings", []) as Array).is_empty()
	if not _post.visible:
		return
	var pm := _post.material as ShaderMaterial
	pm.set_shader_parameter("time", t)
	for k in POST_DEFAULTS:
		pm.set_shader_parameter(k, POST_DEFAULTS[k])
	for k in post_values:
		if k != "focus_world":
			pm.set_shader_parameter(k, post_values[k])
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
