extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 異形紳士の登場（案B・第2版）。霧のロンドン・礼儀正しい不気味さ・赤い目・拳銃。
## 寄り: 濃い霧の中、山高帽の影だけが立つ。遠くで鐘が鳴り、赤い目がふたつ灯る。
## 引き: 霧が晴れていき、紳士が帽子に手をかけて深く一礼する（本番のコマ: hat_reach → bow_down → bow_up）
## → 顔を上げて拳銃を抜き（legacy_draw）、撃鉄を起こす音 → 味方が身構える → 題字。
## 二丁拳銃・覚醒（legacy_reveal・dual_*）のコマは使わない。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:gent_bell", "enc:gent_eyes", "enc:gent_bow", "enc:gent_cock"]
## 本番の紳士のコマ（motion_frames）。
const FRAMES := ["hat_reach_00", "hat_reach_01", "hat_reach_02", "hat_reach_03", "hat_reach_04", "hat_reach_05", "hat_reach_06", "hat_reach_07", "hat_reach_08", "hat_reach_09", "hat_reach_10", "hat_reach_11", "hat_reach_12", "hat_reach_13", "hat_reach_14", "hat_reach_15", "bow_down_00", "bow_down_01", "bow_down_02", "bow_down_03", "bow_down_04", "bow_down_05", "bow_down_06", "bow_down_07", "bow_down_08", "bow_down_09", "bow_down_10", "bow_down_11", "bow_down_12", "bow_down_13", "bow_down_14", "bow_down_15", "bow_up_00", "bow_up_01", "bow_up_02", "bow_up_03", "bow_up_04", "bow_up_05", "bow_up_06", "bow_up_07", "bow_up_08", "bow_up_09", "bow_up_10", "bow_up_11", "bow_up_12", "bow_up_13", "bow_up_14", "bow_up_15", "legacy_draw", "legacy_aim"]

const GMotion = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const UNIT := 160.0 / 94.0
const RED := Color(1.0, 0.15, 0.15)
const FOG := Color(0.62, 0.64, 0.72)

var gf := ""          # 本番の紳士のコマ（motion_frames）。空なら12ポーズの絵
var fog := 1.0

func prepare() -> void:
	super.prepare()
	eye_color = RED

func duration() -> float:
	return 4.7

func draw_body(ci: CanvasItem) -> void:
	if bs.is_empty():
		return
	var foot: Vector2 = Vector2(bs.foot)
	var mod: Color = bs.get("mod", Color.WHITE)
	if gf.is_empty():
		Sprites.draw(ci, asset, int(bs.get("pose", 0)), foot, mod)
	else:
		ci.draw_set_transform(foot.round(), 0.0, Vector2(UNIT, UNIT))
		ci.draw_texture(GMotion.texture(gf), Vector2(-72, -112), mod)
		ci.draw_set_transform(Vector2.ZERO)

func draw_flat(_ci: CanvasItem) -> void:
	pass

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if bs.is_empty() or not gf.is_empty():
		return out
	var f: Vector2 = Vector2(bs.foot)
	out.append(px(Vector2(65.5, 32.5), f))
	out.append(px(Vector2(70.5, 32.5), f))
	return out

func extra_back(ci: CanvasItem) -> void:
	draw_fog(ci, fog, FOG)

func extra_top(ci: CanvasItem) -> void:
	draw_fog(ci, fog, FOG, true)

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.3)
	bars(t, 0.30)
	# --- ショット1: 寄り。霧の中の帽子の影と、灯る赤い目（0.36〜1.40） ---
	if t < 1.40:
		p.camera.cut(2, home + Vector2(-10, -110))
		dark_bg = 0.75
		ally_tint(Color(0.2, 0.2, 0.26))
		fog = 1.0
		gf = ""
		bs = {"pose": 0, "foot": home, "mod": Color(0.12, 0.12, 0.16)}
		eye = 0.0
		if t >= 0.95:
			eye = 0.6 if t < 1.0 else 1.0
		p.se(0.36, "enc:gent_bell", -3.0)
		p.se(0.95, "enc:gent_eyes", -4.0)
		return
	# --- ショット2: 引き（1.40〜） ---
	p.at(1.40, "cut2", func(): p.camera.cut(1, Vector2(640, 360)))
	var lift := smoothstep(1.40, 1.9, t)
	dark_bg = 0.75 * (1.0 - lift) + 0.2 * lift
	ally_tint(Color(0.2, 0.2, 0.26).lerp(Color(0.85, 0.85, 0.9), lift))
	fog = 1.0 - 0.6 * lift
	var mod := Color(0.12, 0.12, 0.16).lerp(Color.WHITE, lift)
	bs = {"pose": 0, "foot": home, "mod": mod}
	eye = 1.0 - smoothstep(1.6, 1.8, t)
	gf = ""
	# 帽子に手（hat_reach, 0.4秒）→ 一礼（bow_down, 0.45秒）→ 止め（0.2秒）→ 顔を上げる（bow_up, 0.45秒）
	var b0 := 1.65
	if t >= b0 and t < b0 + 0.4:
		gf = "hat_reach_%02d" % clampi(int((t - b0) / 0.4 * 16.0), 0, 15)
	elif t >= b0 + 0.4 and t < b0 + 0.85:
		gf = "bow_down_%02d" % clampi(int((t - b0 - 0.4) / 0.45 * 16.0), 0, 15)
	elif t >= b0 + 0.85 and t < b0 + 1.05:
		gf = "bow_down_15"
	elif t >= b0 + 1.05 and t < b0 + 1.5:
		gf = "bow_up_%02d" % clampi(int((t - b0 - 1.05) / 0.45 * 16.0), 0, 15)
	elif t >= b0 + 1.5:
		gf = "legacy_draw" if t < b0 + 1.62 else "legacy_aim"
	p.se(b0, "enc:gent_bow", -3.0)
	p.at(b0 + 1.62, "cock", func():
		p.sfx.play("enc:gent_cock", -1.0)
		p.fx.stars(home + Vector2(-88, -104), 4, Color(1, 0.95, 0.8), 4.0))
	p.at(b0 + 1.65, "brace", func(): allies_brace(true, 4.0))
	p.at(4.15, "relax", func(): allies_brace(false))
	title_card(t, 2.55, Color(1.0, 0.35, 0.4))
