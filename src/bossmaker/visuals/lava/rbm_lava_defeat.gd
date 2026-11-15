extends "res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_canvas.gd"
## 熔鉱炉の番人／噴界炉の巨神の撃破（2026-11-14〜16 ユーザーが確認動画で採用。表示専用。戦闘の状態・乱数・保存データには触れない）。
## とどめのスロー（全ボス共通の入り）の後に続く。作りは金環の聖獣の撃破（rbm_lion_defeat.gd）と同じで、本体の絵はキーポーズ
## （覚醒前＝覚醒の2枚目、覚醒後＝覚醒後全体の4枚目）。エフェクトは rbm_lava_fx_fall.gd（覚醒前）・rbm_lava_fx_fall_awakened.gd（覚醒後）。
## 覚醒前: うずくまる姿（覚醒の2枚目）→ 炉の火が消えて灰色に冷える（湯気・小さな震え）→ ひびが入ってかけらがこぼれる
##   → 上から四角い粒でほどけ、ほどけた所から岩が転げ落ちて、立っていた所に冷えた岩の山が残る（割れ目の残り火がゆっくり消える）。
## 覚醒後（覚醒前より派手に）: 熱が暴れ出す（足元に火口・割れ目から溶岩・オーラが燃え上がる）→ 最後の大噴火（天への炎の柱・溶岩の大爆発）
##   → 柱の中で巨神がほどける → 柱が地面から離れて上へ抜け、冷えていく火口の上に岩の山が残る。
## 岩の山は結果の画面まで残る。
## 本体の色・震え・四角い粒の消え方はエフェクトの値（body・view["hero"]）を、共通の撃破の描き方（bs.mod・dissolve・rise・block・edge）へ移す。
## 音は assets_bossmaker/audio/lava/defeat.wav（覚醒前）・defeat_awakened.wav（覚醒後）。

const FallFx = preload("res://src/bossmaker/visuals/lava/rbm_lava_fx_fall.gd")
const FallAwakenedFx = preload("res://src/bossmaker/visuals/lava/rbm_lava_fx_fall_awakened.gd")
const Presentation = preload("res://src/bossmaker/visuals/lava/rbm_lava_presentation.gd")
const POSE := {"lava": ["awaken", 2], "lava_awakened": ["post_all", 4]}
const SOUND := "game:lava/defeat"
const SOUND_AWAKENED := "game:lava/defeat_awakened"
const SOUNDS := [SOUND, SOUND_AWAKENED]
const SOUND_GAIN := 1.0
## とどめのスローで体が後ろへずれる量（共通の final_advance と同じ。エフェクトの足元もここへそろえる）
const KNOCK := Vector2(18, 0)
## とどめの一撃の前に読み終えておく物（RBMVictoryPlayer.final_blow_paths()・warm_paths()）
const VFX_PATHS := [
	"res://assets_bossmaker/battle/lava/motion/awaken/02.png", "res://assets_bossmaker/battle/lava/motion/post_all/04.png",
	"res://assets_bossmaker/battle/lava/aura_fields/post_all_4.res", "res://src/bossmaker/visuals/lava/shaders/sun_aura.gdshader",
	"res://src/bossmaker/visuals/lava/shaders/eruption.gdshader", "res://src/bossmaker/visuals/lava/shaders/caldera.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/pool.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/post.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/blast.gdshader",
]
const POST_MARGIN := 32.0

var _tex: Texture2D
var _world: Node2D
var _fx: RBMLavaFxBase
var _aura: RBMLavaSunAura
var _post: ColorRect
var _awakened := false

func duration() -> float:
	return float(_fx.duration()) if _fx != null else 4.5

func setup() -> void:
	super.setup()
	_awakened = asset.ends_with("_awakened")
	var pose: Array = POSE.get(asset, POSE["lava"])
	_tex = load(RBMLavaMotion.pose_path(str(pose[0]), int(pose[1])))
	_world = Node2D.new()
	_world.name = "LavaDefeatWorld"
	_world.scale = Vector2(2, 2)
	_world.position = home() + KNOCK - Presentation.HOME_FOOT * 2.0
	_world.z_index = 1
	var back := Node2D.new()
	back.name = "LavaDefeatBack"
	_world.add_child(back)
	var front := Node2D.new()
	front.name = "LavaDefeatFront"
	front.z_index = 4
	_world.add_child(front)
	# 覚醒後の常時オーラ（本体の後ろ。撃破の間に燃え上がって散る）
	if _awakened:
		_aura = RBMLavaSunAura.new()
		back.add_child(_aura)
		_aura.setup()
	_fx = (FallAwakenedFx if _awakened else FallFx).new()
	_fx.seq = str(pose[0])
	_fx.mid = back
	_world.add_child(_fx)
	_fx.setup(back, front, [])
	# 本体（boss_body）より前に置き、後ろの効果を本体の後ろに描く（z は本体と同じ1）
	p.stage.add_child(_world)
	p.stage.move_child(_world, p.boss_body.get_index())
	_post = ColorRect.new()
	_post.name = "LavaDefeatPost"
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_post.size = p.stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_post.z_index = 6
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("post")
	_post.material = pm
	_post.visible = false
	p.stage.add_child(_post)

func cleanup() -> void:
	if _only_moved(p.top):
		# 戦闘画面の配置の移動でステージごと木から外れただけ（勝利の層は消されていない）。次に外れる時にもう一度確かめる。
		# 遅らせて繋ぐ間に top が消えていたら繋がない。top を直接つかむと、消えた後に「Lambda capture was freed」が出るので弱い参照で持つ。
		var top_ref: WeakRef = weakref(p.top)
		(func():
			var top: Node = top_ref.get_ref() as Node
			if is_instance_valid(top) and not top.tree_exiting.is_connected(cleanup):
				top.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)).call_deferred()
		return
	super.cleanup()
	for n in [_world, _post]:
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

## 暗幕だけを使う（共通の覚醒後の撃破の煙の部品 field は使わない）。
func dim(color: Color, amount: float) -> void:
	shade = Color(color, amount)
	veil.queue_redraw()

## とどめの一撃（全ボス共通の入りと同じ: 被弾の姿勢・0.3倍のスロー・寄り・揺れ・音・白く光る）。
## 胸の小さな光の円と火花は出さない（2026-11-14 ユーザー「ボスの中心に変なマークが出る」。聖獣と同じ）。
func final_blow() -> void:
	impact_pose()
	p.set_motion_speed(SLOW_SPEED)
	p.camera.cut(2, chest_point() + Vector2(-70, 14))
	p.camera.shake(4, 0.4)
	p.sfx.play("enc:final_hit", 0.0)
	white = 1.0

func begin() -> void:
	super.begin()
	p.sfx.play(SOUND_AWAKENED if _awakened else SOUND, SOUND_GAIN)

func advance(t: float, _dt: float) -> void:
	age = t
	bs["pose"] = 11
	_fx.advance_pose(t)
	var view: Dictionary = _fx.view
	var body: Dictionary = _fx.body
	var hero_info: Dictionary = view.get("hero", {})
	# 本体: 震え（論理ドット → 2倍）と色（褪せる・冷える・染まる・照り）
	bs["foot"] = home() + KNOCK + (Vector2(body.get("off", Vector2.ZERO)) * 2.0).round()
	bs["mod"] = _body_color(hero_info)
	dim(view.get("dim_col", Color(0.03, 0.02, 0.04)), float(view.get("dim", 0.0)))
	_apply_post(view, t)
	# 揺れ（戦場のカメラに足す。強さの設定を掛ける）
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	if shake != Vector2.ZERO:
		p.camera._offset += (shake * 2.0 * p.camera.shake_strength()).snapped(Vector2(2, 2))
		p.camera.apply()
	# 上から四角い粒でほどける（共通の消え方。縁の色・粒の大きさはエフェクトの値）
	dissolve = float(body.get("dissolve", 0.0))
	rise = float(body.get("rise", 0.95))
	block = float(body.get("block", 3.0))
	edge = body.get("edge", Color(1.0, 0.98, 0.9, 0.9))
	if dissolve >= 0.999:
		gone = true
	# 覚醒後のオーラ（エフェクトの sun_aura の強さ。本体の絵の輪郭＝覚醒後全体の4枚目）
	if is_instance_valid(_aura):
		var pose: Array = POSE[asset] if POSE.has(asset) else POSE["lava_awakened"]
		var off: Vector2 = body.get("off", Vector2.ZERO)
		_aura.show_pose(str(pose[0]), int(pose[1]), Presentation.HOME_FOOT + off - Presentation.ORIGIN, Presentation.HOME_FOOT + off,
			float(hero_info.get("sun_aura", 0.0)) * (1.0 - dissolve), t)
	# 残った物（溶岩）は消さない（_world は勝利の層が片付く時に一緒に消える）

## エフェクトの本体の色の指定（tint・desat・lit）を、共通の撃破の描き方の色（掛け算）へ近づけて移す。
static func _body_color(h: Dictionary) -> Color:
	var mod := Color.WHITE
	var tint := float(h.get("tint", 0.0))
	if tint > 0.0:
		mod = mod.lerp(Color(h.get("tint_col", Color.WHITE)), tint)
	var desat := float(h.get("desat", 0.0))
	if desat > 0.0:
		mod = mod.lerp(Color(0.6, 0.6, 0.62), desat * 0.55)
	var lit := float(h.get("lit", 0.0))
	if lit > 0.0:
		var lc: Color = h.get("lit_col", Color.WHITE)
		mod = mod.lerp(Color(lc.r * 1.5, lc.g * 1.5, lc.b * 1.5), lit * 0.3)
	mod.a = 1.0
	return mod

## 本体: キーポーズの絵を、戦闘と同じ2倍・足元で描く（伸縮・回転しない）。
func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	if _tex == null or mod.a <= 0.003:
		return
	var foot: Vector2 = Vector2(bs.foot) + Vector2(0, sink)
	ci.draw_texture_rect(_tex, Rect2(foot - RBMLavaMotion.ORIGIN * 2.0, _tex.get_size() * 2.0), false, mod)

func _apply_post(view: Dictionary, t: float) -> void:
	var post_values: Dictionary = view.get("post", {})
	_post.visible = float(post_values.get("vig", 0.0)) > 0.001 or float(post_values.get("flash", 0.0)) > 0.001 or not (view.get("rings", []) as Array).is_empty()
	if not _post.visible:
		return
	var pm := _post.material as ShaderMaterial
	pm.set_shader_parameter("time", t)
	for k in Presentation.POST_DEFAULTS:
		pm.set_shader_parameter(k, Presentation.POST_DEFAULTS[k])
	for k in post_values:
		if k != "focus_world":
			pm.set_shader_parameter(k, post_values[k])
	var rings := PackedVector4Array()
	var screen := _post.get_viewport_rect().size
	var scale_y: float = 2.0 * p.stage.get_global_transform_with_canvas().get_scale().y / maxf(screen.y, 1.0)
	for ring in view.get("rings", []):
		var c: Vector2 = p.stage.get_global_transform_with_canvas() * (Vector2(ring.x, ring.y) * 2.0 + _world.position)
		var ruv := c / screen
		rings.append(Vector4(ruv.x, ruv.y, ring.z * scale_y, ring.w))
		if rings.size() >= 6:
			break
	var count := rings.size()
	while rings.size() < 6:
		rings.append(Vector4.ZERO)
	pm.set_shader_parameter("rings", rings)
	pm.set_shader_parameter("ring_count", count)
