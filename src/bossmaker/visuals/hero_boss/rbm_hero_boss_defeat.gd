extends "res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_canvas.gd"
## ヒーローの覚醒前の撃破「力尽きる」（2026-11-17。表示専用。戦闘の状態・乱数・保存データには触れない）。
## とどめのスロー（全ボス共通の入り）の後に続く。覚醒後の撃破は rbm_hero_boss_defeat_awakened.gd（別の物）。
## よろめく（bridge0）→ 頭を押さえて立つ（release0）・鎧から火花・胸の灯が赤く点滅して速くなる → 片膝（release1）
## → 胸の灯が消える → 青い光の粒になって昇って消える（2026-11-19 ユーザーの指摘で、最後に照射器で照らす所を外した）。
## 本体の絵は正式モーションのコマをそのまま切り替えるだけ（伸縮・回転・中割りなし）。片膝のコマは四角い粒で消えるので、
## 1枚に切り出した絵（覚醒後の撃破と同じ assets_bossmaker/battle/hero_boss_awakened/defeat/release1.png）を使う。
## エフェクトは rbm_hero_fx_down.gd、時刻は RBMHeroFxTiming.DOWN、音は assets_bossmaker/audio/hero_boss/defeat.wav（1本）。
const DownFx = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_down.gd")
const Presentation = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_presentation.gd")
const Motion = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_motion.gd")
const T := RBMHeroFxTiming.DOWN
const KNEEL_PATH := "res://assets_bossmaker/battle/hero_boss_awakened/defeat/release1.png"
## 切り出した片膝の絵の大きさと、コマの下辺中央（tools/hero_boss/bake_hero_boss_assets.gd の DEFEAT_CANVAS・DEFEAT_FOOT と
## rbm_hero_boss_defeat_awakened.gd の CEL_TOP_LEFT から。立ち絵と同じく、コマの下辺中央を足元に置く）
const KNEEL_CANVAS := Vector2(112, 100)
const KNEEL_CENTER := Vector2(42, 98)
const SOUND := "game:hero_boss/defeat"
const SOUNDS := [SOUND]
const SOUND_GAIN := 1.0
## とどめの一撃の前に読み終えておく物（RBMVictoryPlayer.final_blow_paths()・warm_paths()）
const VFX_PATHS := ["res://assets_bossmaker/battle/hero_boss/motion/cels.png", KNEEL_PATH]
const PALE := Color("#c8f4ff")

var _sheet: Texture2D
var _kneel: Texture2D
var _world: Node2D
var _fx: RBMHeroFxBase
var _flat_col := Color.WHITE

func duration() -> float:
	return float(T.end)

func setup() -> void:
	super.setup()
	_sheet = load(Motion.SHEET_PATH) as Texture2D
	_kneel = load(KNEEL_PATH) as Texture2D
	_world = Node2D.new()
	_world.name = "HeroDownWorld"
	_world.scale = Vector2(2, 2)
	_world.position = home() - Presentation.HOME_FOOT * 2.0
	_world.z_index = 1
	var back := Node2D.new()
	back.name = "HeroDownBack"
	_world.add_child(back)
	var front := Node2D.new()
	front.name = "HeroDownFront"
	front.z_index = 4
	_world.add_child(front)
	_fx = DownFx.new()
	_world.add_child(_fx)
	_fx.setup(back, front, [])
	# 本体（boss_body）より前に置く（z は本体と同じ1）
	p.stage.add_child(_world)
	p.stage.move_child(_world, p.boss_body.get_index())

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
	if is_instance_valid(_world):
		_world.queue_free()

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
## 胸の小さな光の円と火花は出さない（2026-11-14 ユーザー「ボスの中心に変なマークが出る」。聖獣・時計と同じ）。
func final_blow() -> void:
	impact_pose()
	bs["cel"] = "bridge0"
	p.set_motion_speed(SLOW_SPEED)
	p.camera.cut(2, chest_point() + Vector2(-70, 14))
	p.camera.shake(4, 0.4)
	p.sfx.play("enc:final_hit", 0.0)
	white = 1.0

func begin() -> void:
	super.begin()
	p.sfx.play(SOUND, SOUND_GAIN)

func _cel_at(t: float) -> String:
	if t < float(T.stand):
		return "bridge0"
	if t < float(T.kneel):
		return "release0"
	return "release1"

func advance(t: float, _dt: float) -> void:
	age = t
	var cel := _cel_at(t)
	bs["cel"] = cel
	bs["pose"] = 11
	# とどめで後ろへずれた分（共通の final_advance の18px）を、立ち直る間に少し戻す
	var recoil := 18.0 - 6.0 * RBMHeroFx.ramp(t, 0.0, float(T.stand))
	bs["foot"] = home() + Vector2(roundf(recoil / 2.0) * 2.0, 0)
	var anchor := Presentation.HOME_FOOT + (Vector2(bs["foot"]) - home()) * 0.5
	_fx.advance(t, cel, anchor, anchor)
	var view: Dictionary = _fx.view
	var hero_info: Dictionary = view.get("hero", {})
	dim(view.get("dim_col", Color(0.02, 0.03, 0.08)), float(view.get("dim", 0.0)))
	# 体に重ねる白い光（火花・胸の灯が消える瞬間）
	_flat_col = PALE
	white = float(hero_info.get("flash", 0.0))
	# 力が抜けて色が褪せる
	var desat := float(hero_info.get("desat", 0.0))
	bs["mod"] = Color.WHITE.lerp(Color(0.62, 0.64, 0.7), desat)
	# 揺れ（戦場のカメラに足す。強さの設定を掛ける）
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	if shake != Vector2.ZERO:
		p.camera._offset += (shake * 2.0 * p.camera.shake_strength()).snapped(Vector2(2, 2))
		p.camera.apply()
	# 上から四角い粒でほどけ、青い光の粒になって昇る（共通の消え方）
	dissolve = smoothstep(float(T.melt), float(T.gone) - 0.08, t)
	rise = 0.9
	block = 3.0
	edge = Color(PALE, 0.95)
	if t >= float(T.gone):
		gone = true
	# _world は勝利の層が片付く時に一緒に消える

func _draw_flat(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or dissolve > 0.0 or white <= 0.0:
		return
	draw_sprite(ci, Color(_flat_col, white))

## 本体: 正式モーションのコマを、立ち絵と同じ2倍・足元（コマの下辺中央）で描く（伸縮・回転しない）。
func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	if mod.a <= 0.003:
		return
	var foot: Vector2 = Vector2(bs.get("foot", home())) + Vector2(0, sink)
	var cel := str(bs.get("cel", "bridge0"))
	if cel == "release1" and _kneel != null:
		ci.draw_texture_rect(_kneel, Rect2(foot - KNEEL_CENTER * 2.0, KNEEL_CANVAS * 2.0), false, mod)
		return
	if _sheet == null:
		return
	var r := Motion.rect(cel)
	ci.draw_texture_rect_region(_sheet, Rect2(foot - Vector2(roundf(r.size.x * 0.5), r.size.y) * 2.0, r.size * 2.0), r, mod)
