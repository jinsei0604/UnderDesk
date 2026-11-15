extends "res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_canvas.gd"
## 金環の聖獣／日蝕の獅皇の撃破（2026-11-13 ユーザーの案。表示専用。戦闘の状態・乱数・保存データには触れない）。
## とどめのスロー（全ボス共通）→ 背に金環日食が現れる → 金の輪が上から両側へ欠けていき、欠けた所から金の破片がこぼれる
## → 輪が欠けるのに合わせて聖獣も上から光の粒になってほどける（共通の四角い粒の消え方）→ 最後のひとかけらが消えて闇が晴れる
## → 聖獣のいた床に剣が刺さって残る（結果の画面まで。2026-11-13 ユーザー指定）。
## 覚醒前は金の輪と金の剣。覚醒後（ユーザー「もっと派手に」）は大きな深紅の日蝕・光冠の燃え上がり・脈打つ閃光・深紅の大爆発・空から落ちる深紅の大剣。
## 本体の絵はキーポーズ（覚醒前＝覚醒の2枚目のうなだれ、覚醒後＝覚醒後全体の構え）。
## エフェクトは rbm_lion_fx_fall.gd、音は assets_bossmaker/audio/lion/defeat.wav（覚醒前）・defeat_awakened.wav（覚醒後）。

const FallFx = preload("res://src/bossmaker/visuals/lion/rbm_lion_fx_fall.gd")
const Presentation = preload("res://src/bossmaker/visuals/lion/rbm_lion_presentation.gd")
const POSE := {"lion": ["awaken", 2], "lion_awakened": ["post_all", 1]}
const SOUND := "game:lion/defeat"
const SOUND_AWAKENED := "game:lion/defeat_awakened"
const SOUNDS := [SOUND, SOUND_AWAKENED]
const SOUND_GAIN := 1.0
## とどめの一撃の前に読み終えておく物（RBMVictoryPlayer.final_blow_paths()・warm_paths()）
const VFX_PATHS := [
	"res://assets_bossmaker/battle/lion/motion/awaken/02.png", "res://assets_bossmaker/battle/lion/motion/post_all/01.png",
	"res://src/bossmaker/visuals/lion/shaders/eclipse.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/post.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/blast.gdshader",
]
const POST_MARGIN := 32.0

var _tex: Texture2D
var _world: Node2D
var _fx: RBMLionFxBase
var _post: ColorRect
## 時刻（覚醒前 FallFx.T・覚醒後 FallFx.TA）
var _tt: Dictionary = FallFx.T

func duration() -> float:
	return float(_tt.end)

func setup() -> void:
	super.setup()
	var pose: Array = POSE.get(asset, POSE["lion"])
	_tex = load(RBMLionMotion.pose_path(str(pose[0]), int(pose[1])))
	_world = Node2D.new()
	_world.name = "LionDefeatWorld"
	_world.scale = Vector2(2, 2)
	_world.position = home() - Presentation.HOME_FOOT * 2.0
	_world.z_index = 1
	var back := Node2D.new()
	back.name = "LionDefeatBack"
	_world.add_child(back)
	var front := Node2D.new()
	front.name = "LionDefeatFront"
	front.z_index = 4
	_world.add_child(front)
	_fx = FallFx.new()
	_fx.awakened = asset.ends_with("_awakened")
	_tt = _fx.tm()
	_fx.seq = str(pose[0])
	_world.add_child(_fx)
	_fx.setup(back, front, [])
	# 本体（boss_body）より前に置き、金環日食を本体の後ろに描く（z は本体と同じ1）
	p.stage.add_child(_world)
	p.stage.move_child(_world, p.boss_body.get_index())
	_post = ColorRect.new()
	_post.name = "LionDefeatPost"
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
		# 遅らせて繋ぐ間に top が消えていたら繋がない（戦闘画面ごと消える時に null へ繋ぐエラーを出さない）。
		# top を直接つかむと、消えた後に「Lambda capture was freed」が出るので弱い参照で持つ。
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
## 胸の小さな光の円と火花は出さない（2026-11-14 ユーザー「ボスの中心に変なマークが出る」→ 白く光る体の真ん中に印のように見えた）。
func final_blow() -> void:
	impact_pose()
	p.set_motion_speed(SLOW_SPEED)
	p.camera.cut(2, chest_point() + Vector2(-70, 14))
	p.camera.shake(4, 0.4)
	p.sfx.play("enc:final_hit", 0.0)
	white = 1.0

func begin() -> void:
	super.begin()
	p.sfx.play(SOUND_AWAKENED if asset.ends_with("_awakened") else SOUND, SOUND_GAIN)

func advance(t: float, _dt: float) -> void:
	age = t
	bs["pose"] = 11
	# 輪が現れる間、体が小さく震える（2px の格子）
	var T: Dictionary = _tt
	var tremble := 1.0 - RBMHeroFx.ramp(t, T.melt, T.melt + 0.3)
	bs["foot"] = home() + Vector2(18, 0) + Vector2(sin(t * 41.0), 0.0).snapped(Vector2.ONE) * 2.0 * roundf(tremble)
	_fx.advance_pose(t)
	var view: Dictionary = _fx.view
	dim(view.get("dim_col", Color(0.03, 0.02, 0.04)), float(view.get("dim", 0.0)))
	_apply_post(view, t)
	# 揺れ（戦場のカメラに足す。強さの設定を掛ける）
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	if shake != Vector2.ZERO:
		p.camera._offset += (shake * 2.0 * p.camera.shake_strength()).snapped(Vector2(2, 2))
		p.camera.apply()
	# 輪が欠けるのに合わせて、体も上から光の粒になってほどける
	dissolve = smoothstep(float(T.melt), float(T.gone) - 0.05, t)
	rise = 0.95
	block = 3.0
	edge = Color(Color("#e0402a") if asset.ends_with("_awakened") else Color("#ffd27a"), 0.95)
	p.at(float(T.wane), "lion_fall_wane", func(): p.camera.shake(3, 0.3))
	p.at(float(T.last), "lion_fall_last", func(): p.camera.shake(2, 0.2))
	if t >= float(T.gone):
		gone = true
	# 剣は床に残す（_world は消さない。勝利の層が片付く時に一緒に消える）

## 本体: キーポーズの絵を、戦闘と同じ2倍・足元で描く（伸縮・回転しない）。
func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	if _tex == null or mod.a <= 0.003:
		return
	var foot: Vector2 = Vector2(bs.foot) + Vector2(0, sink)
	ci.draw_texture_rect(_tex, Rect2(foot - RBMLionMotion.ORIGIN * 2.0, _tex.get_size() * 2.0), false, mod)

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
