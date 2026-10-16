extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 異形紳士が倒れる: 帽子に手をかけ、敗北を認めるように深く一礼する（本番の紳士のコマ: hat_reach → bow_down）
## → 一礼したまま、赤い火の粉を含んだ煙になってほどける。二丁拳銃・覚醒のコマは使わない。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:gent_bow", "enc:gent_vanish"]
## 本番の紳士のコマ（motion_frames）。
const FRAMES := ["hat_reach_00", "hat_reach_01", "hat_reach_02", "hat_reach_03", "hat_reach_04", "hat_reach_05", "hat_reach_06", "hat_reach_07", "hat_reach_08", "hat_reach_09", "hat_reach_10", "hat_reach_11", "hat_reach_12", "hat_reach_13", "hat_reach_14", "hat_reach_15", "bow_down_00", "bow_down_01", "bow_down_02", "bow_down_03", "bow_down_04", "bow_down_05", "bow_down_06", "bow_down_07", "bow_down_08", "bow_down_09", "bow_down_10", "bow_down_11", "bow_down_12", "bow_down_13", "bow_down_14", "bow_down_15"]
const GMotion = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const UNIT := 160.0 / 94.0
const SMOKE := Color(0.32, 0.32, 0.38, 0.75)
var frame := "hat_reach_00"

func duration() -> float:
	return 1.7

func impact_pose() -> void:
	(p.stage.get("_visuals")["boss"] as Control).visible = false
	bs = {"pose": 11, "foot": home() + Vector2(8, 0)}
	frame = ""

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	bs.foot = h + Vector2(8, 0)
	# 0.0〜0.5 帽子に手 / 0.5〜1.0 一礼（各16コマ）
	if t < 0.5:
		frame = "hat_reach_%02d" % clampi(int(t / 0.5 * 16.0), 0, 15)
	elif t < 1.0:
		frame = "bow_down_%02d" % clampi(int((t - 0.5) / 0.5 * 16.0), 0, 15)
	else:
		frame = "bow_down_15"
	p.at(0.05, "cloth", func(): p.sfx.play("enc:gent_bow", -3.0))
	if t >= 0.95:
		dissolve = smoothstep(0.95, 1.62, t)
		edge = Color(0.85, 0.2, 0.25, 1.0)
		rise = 0.5
		block = 3.0
		p.at(0.95, "smoke", func():
			p.sfx.play("enc:gent_vanish", -1.0)
			p.fx.smoke(h + Vector2(0, -60), 18, SMOKE, 30.0, 40.0)
			p.fx.embers(h + Vector2(0, -60), 12, Color(0.95, 0.25, 0.3), 30.0, 50.0, 1.2))
		p.at(1.2, "smoke2", func(): p.fx.smoke(h + Vector2(0, -30), 12, SMOKE, 40.0, 35.0))
	if t >= 1.65:
		gone = true

func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	var foot: Vector2 = Vector2(bs.foot)
	if frame.is_empty():
		Sprites.draw(ci, asset, int(bs.get("pose", 11)), foot, mod)
		return
	ci.draw_set_transform(foot.round(), 0.0, Vector2(UNIT, UNIT))
	ci.draw_texture(GMotion.texture(frame), Vector2(-72, -112), mod)
	ci.draw_set_transform(Vector2.ZERO)
