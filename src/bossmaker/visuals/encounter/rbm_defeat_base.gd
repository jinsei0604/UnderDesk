extends RefCounted
## ボスが倒れる演出（案C。表示専用）の共通部分。ボスごとの倒れ方（defeat/rbm_defeat_<ボス>.gd）がこれを継承する。
## 本番のボスの見た目を隠し、同じ絵を同じ大きさ・足元で描く。絵は伸縮・回転しない（ポーズの切り替え・位置・色・粒で消える）。
## 流れ: とどめの命中（スロー・寄り・局所の閃光） → begin() から倒れ方（ボスごと） → gone。
const Sprites = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_sprites.gd")

var p   # victory_player.gd
var asset := ""
var bs := {}            # {pose, foot, mod, alpha, ground}
var white := 0.0
var dissolve := 0.0     # 0=見える 1=消えた（四角い粒でほどける）
var rise := 0.7         # 上の方から先に消える度合い
var block := 6.0        # ほどける粒の大きさ（画像の画素）
var edge := Color(1.0, 0.98, 0.9, 0.9)
var sink := 0.0         # 地面に沈んだ量（px）
var gone := false
var age := 0.0

func setup() -> void:
	asset = str(p.stage.get("_asset_ids")["boss"])
	p.boss_body.draw_fn = _draw_body
	p.boss_flat.draw_fn = _draw_flat
	p.boss_dissolve.draw_fn = _draw_dissolve

func home() -> Vector2:
	return p.boss_foot()

## 倒れ方の長さ（begin から gone まで）。
func duration() -> float:
	return 1.4

## 命中の瞬間: 本番のボスの見た目（半透明になる）を隠し、被弾の姿勢で描く。
func impact_pose() -> void:
	(p.stage.get("_visuals")["boss"] as Control).visible = false
	bs = {"pose": 11, "foot": home() + Vector2(8, 0)}

## とどめのスローの長さ（実時間）と速さ。スローは戦場の今の行動の動きだけに掛ける（ゲーム全体の時間は変えない）。
const SLOW_SECONDS := 1.0
const SLOW_SPEED := 0.3

## とどめのスロー（全ボス共通の入り。0.3倍・2倍の寄り・局所の閃光・光の線）。
func final_blow() -> void:
	impact_pose()
	p.set_motion_speed(SLOW_SPEED)
	var chest := chest_point()
	p.camera.cut(2, chest + Vector2(-70, 14))
	p.fx.flash(chest, 44, 0.5, Color(1.0, 0.97, 0.9, 0.95))
	p.fx.ray_burst(chest, 14, 170.0, 0.9, Color(1.0, 0.95, 0.85, 0.85))
	p.fx.sparks(chest, 14, Color(1, 0.98, 0.9), Color(1.0, 0.7, 0.4), PI, PI * 1.2, 1.0)
	p.camera.shake(4, 0.4)
	p.sfx.play("enc:final_hit", 0.0)
	white = 1.0

func final_advance(t: float, _dt: float) -> void:
	white = maxf(0.0, 1.0 - t / 0.25)
	bs.foot = home() + Vector2(8 + roundf(10.0 * minf(1.0, t / 0.3)), 0)
	if t >= SLOW_SECONDS and p.motion_speed < 1.0:
		p.set_motion_speed(1.0)
		p.camera.cut(1, Vector2(640, 360))

func chest_point() -> Vector2:
	var r := Sprites.pose_rect(asset, 0, home())
	return Vector2(r.get_center().x, r.position.y + r.size.y * 0.42).round()

func begin() -> void:
	if bs.is_empty():
		impact_pose()

func finish_now() -> void:
	gone = true

func advance(t: float, _dt: float) -> void:
	age = t

# --- 描画 ------------------------------------------------------------------
## ボスの絵を1枚描く（武者・紳士はコマ絵なので上書きする）。
func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	var foot: Vector2 = Vector2(bs.foot) + Vector2(0, sink)
	Sprites.draw(ci, asset, int(bs.get("pose", 11)), foot, mod, float(bs.get("ground", INF)))

func _draw_body(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or dissolve > 0.0:
		return
	var mod: Color = bs.get("mod", Color.WHITE)
	draw_sprite(ci, Color(mod, mod.a * float(bs.get("alpha", 1.0))))

func _draw_flat(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or dissolve > 0.0 or white <= 0.0:
		return
	draw_sprite(ci, Color(1, 1, 1, white))

func _draw_dissolve(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or dissolve <= 0.0:
		return
	p.shader(p.boss_dissolve, "threshold", dissolve)
	p.shader(p.boss_dissolve, "block_px", block)
	p.shader(p.boss_dissolve, "rise", rise)
	p.shader(p.boss_dissolve, "edge_color", edge)
	p.shader(p.boss_dissolve, "edge_width", 0.10)
	var mod: Color = bs.get("mod", Color.WHITE)
	draw_sprite(ci, mod)

## 上に重ねる線・光（ひび・一閃など）。
func draw_top(_ci: CanvasItem) -> void:
	pass
