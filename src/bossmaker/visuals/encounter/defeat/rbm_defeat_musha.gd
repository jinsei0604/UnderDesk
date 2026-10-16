extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 朽ちた機械武者が倒れる: 居合の構えのまま止まる → 胴を一筋の光が走る → 単眼が消える → 墨になってはじけ、散る。
## 絵は本番のコマ描画（rbm_musha_frames.gd）の覚醒前のコマ（p0=居合の構え）。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:musha_slash", "enc:musha_ink_burst"]
## 本番の武者のコマ（rbm_musha_frames.gd）。
const FRAMES := ["p0"]
const Frames = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const INK := Color(0.05, 0.045, 0.06, 0.95)
var slash := 0.0
var eye_on := 1.0

func duration() -> float:
	return 1.45

func impact_pose() -> void:
	(p.stage.get("_visuals")["boss"] as Control).visible = false
	bs = {"fr": "p0", "foot": home() + Vector2(8, 0)}

func chest_point() -> Vector2:
	return home() + Vector2(-6, -100)

func final_advance(t: float, dt: float) -> void:
	white = maxf(0.0, 1.0 - t / 0.25)
	bs.foot = home() + Vector2(8, 0)
	if t >= SLOW_SECONDS and p.motion_speed < 1.0:
		p.set_motion_speed(1.0)
		p.camera.cut(1, Vector2(640, 360))

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	bs.fr = "p0"
	bs.foot = h + Vector2(8, 0)
	slash = smoothstep(0.22, 0.40, t) * (1.0 - smoothstep(0.70, 0.90, t))
	eye_on = 1.0 - smoothstep(0.5, 0.7, t)
	p.at(0.22, "slash_se", func(): p.sfx.play("enc:musha_slash", 0.0))
	if t >= 0.75:
		dissolve = smoothstep(0.75, 1.40, t)
		edge = Color(0.02, 0.02, 0.03, 1.0)
		block = 3.0
		p.at(0.75, "ink", func():
			p.sfx.play("enc:musha_ink_burst", 0.0)
			p.camera.shake(3, 0.35)
			p.fx.ink(h + Vector2(0, -110), 26, -1.0, INK, 1.2)
			p.fx.ink(h + Vector2(0, -70), 22, 1.0, INK, 1.0)
			p.fx.ink(h + Vector2(0, -30), 16, -1.0, INK, 0.8))
	if t >= 1.42:
		gone = true

func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	var s := Frames.state(str(bs.get("fr", "p0")), Vector2(bs.foot))
	s["eye"] = eye_on > 0.5
	Frames.draw(ci, s, mod)

func draw_top(ci: CanvasItem) -> void:
	if gone or slash <= 0.0:
		return
	var h := home()
	var y := h.y - 100
	var w := 130.0 * slash
	ci.draw_rect(Rect2(Vector2(h.x - w * 0.5, y - 1), Vector2(w, 2)).abs(), Color(1, 1, 1, 0.95))
	ci.draw_rect(Rect2(Vector2(h.x - w * 0.6, y - 3), Vector2(w * 1.2, 6)), Color(1, 1, 1, 0.22))
