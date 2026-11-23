extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 異形紳士の登場「硝子の弾痕」（2026-11-23 作り直し。ユーザー「機械武者と同じように画面全体を使って、画面が真っ暗の中で
## 銃弾を撃って画面にひび割れが起きるような」）。機械武者と同じ長い登場（約6.5秒）。
## 闇: 画面は黒いガラスに覆われて真っ暗。遠くで鐘が鳴る。
## 三発: 闇の中から銃声だけが響き、弾が画面（ガラス）に当たって弾痕とひびが走る（2026-11-23 ユーザー「弾痕だけにして、
##       異形紳士は映さないように」→ 闇の中では紳士の姿・銃口の光・赤い目は描かない。ひびが一瞬光るだけ）。
## 間: 撃鉄を起こす音だけ。
## 最後の一発: 画面の真ん中に撃ち込まれ、ひびが画面じゅうに走って一瞬止まり → ガラスが真ん中から砕け散る。
## 登場: 破片の向こうに、銃を構えたままの紳士（銃口から煙）。銃を下ろして帽子に手をかけ、深く一礼 → 題字。
## ガラスの層は rbm_intro_gentleman_glass.gd。絵は本番の紳士のコマ（motion_frames）をそのまま使い、伸縮・回転はしない。
## 音は1本の専用の音（gent_intro_v2.wav、tools/gentleman/audio/build_intro.mjs が下の T の時刻で作る）。

const Glass = preload("res://src/bossmaker/visuals/encounter/rbm_intro_gentleman_glass.gd")
const GMotion = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:gent_intro_v2"]
## 本番の紳士のコマ（motion_frames）。
const FRAMES := ["hat_reach_00", "hat_reach_15", "normal_draw_fire_05", "normal_draw_fire_11", "normal_draw_fire_15",
	"bow_down_04", "bow_down_08", "bow_down_15", "bow_up_08"]
## 時刻（秒、登場の再生の時刻）。音の組み立て（build_intro.mjs）もこれを読む。
const T := {"track": 0.30, "bell": 0.50, "eyes": 0.95, "shot1": 1.40, "shot2": 1.88, "shot3": 2.28, "cock": 2.78, "final": 3.22, "break": 3.58, "lower": 4.30, "hat": 4.50, "bow": 4.90, "up": 5.55, "end": 6.50}
## 闇の中の三発 [時刻の名前, 立つ場所（元の場所からの横のずれ）, 弾痕の場所（画面）, ひびの半径, 放射のひびの数]
const SHOTS := [["shot1", 0.0, Vector2(500, 290), 230.0, 11], ["shot2", -300.0, Vector2(235, 455), 200.0, 10], ["shot3", 170.0, Vector2(905, 180), 210.0, 10]]
const CENTER := Vector2(640, 345)

const UNIT := 160.0 / 94.0
const RED := Color(1.0, 0.15, 0.15)
const FOG := Color(0.62, 0.64, 0.72)
const AIM := "normal_draw_fire_15"
const RECOIL := "normal_draw_fire_11"
## 目の位置（コマの画素、足元からの相対）
const EYES := {"hat_reach_00": [Vector2(-6, -80), Vector2(-2, -80)], "normal_draw_fire_15": [Vector2(-12, -73), Vector2(-8, -74)]}
## 撃鉄（構えた絵、足元からの相対）
const HAMMER := Vector2(-28, -67)

var glass: Glass
var gf := ""           # 砕けた後の本体のコマ（戦場に描く）
var fog := 0.0
var home := Vector2.ZERO
# 闇の中の紳士（ガラスの上に描く）
var fig_frame := ""
var fig_foot := Vector2.ZERO
var fig_k := 0.0
var dark_eyes := 0.0
var dark_eye_frame := "hat_reach_00"
var hammer_k := 0.0
var smoke: Array = []   # {p(戦場の座標), t0}

func prepare() -> void:
	super.prepare()
	eye_color = RED
	home = p.boss_foot()
	glass = Glass.new()
	glass.name = "IntroGentlemanGlassLayer"
	p.add_child(glass)
	glass.setup(p.view, p.camera)
	glass.figure_fn = _draw_figure
	glass.extra_glow_fn = _draw_dark_glow

func duration() -> float:
	return float(T.end)

# --- 描画 -------------------------------------------------------------------

func draw_body(ci: CanvasItem) -> void:
	if gf.is_empty():
		return
	ci.draw_set_transform(home.round(), 0.0, Vector2(UNIT, UNIT))
	ci.draw_texture(GMotion.texture(gf), Vector2(-72, -112), Color.WHITE)
	ci.draw_set_transform(Vector2.ZERO)

func draw_flat(_ci: CanvasItem) -> void:
	pass

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for e in EYES.get(gf, []):
		out.append((home + Vector2(e) * UNIT).round())
	return out

func extra_back(ci: CanvasItem) -> void:
	draw_fog(ci, fog, FOG)

func extra_top(ci: CanvasItem) -> void:
	draw_fog(ci, fog * 0.6, FOG, true)

## 戦場の座標 → 画面の座標（ガラスの層は画面の座標）。
func scr(v: Vector2) -> Vector2:
	return p.stage.get_global_transform_with_canvas() * v - Vector2(glass.glass_layer.offset)

func _muzzle(foot: Vector2, frame: String) -> Dictionary:
	var g := GMotion.gun(frame, "near")
	return {"p": foot + Vector2(g.p) * UNIT, "d": Vector2(g.d)}

## 闇の中で銃口の光に照らされた紳士（暖かい光で明るく、光が消えると闇に沈む）と、銃口の煙。
func _draw_figure(ci: CanvasItem) -> void:
	var xf: Transform2D = Transform2D(0.0, -Vector2(glass.glass_layer.offset)) * p.stage.get_global_transform_with_canvas()
	if fig_k > 0.0 and not fig_frame.is_empty():
		var k := fig_k
		ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(UNIT, UNIT), 0.0, fig_foot.round()))
		ci.draw_texture(GMotion.texture(fig_frame), Vector2(-72, -112), Color(0.35 + 1.25 * k, 0.3 + 0.95 * k, 0.28 + 0.7 * k, minf(1.0, k * 1.6)))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	for s in smoke:
		var u: float = (float(p.age) - float(s.t0)) / 1.3
		if u < 0.0 or u > 1.0:
			continue
		var at := scr(Vector2(s.p) + Vector2(sin(u * 5.0 + float(s.t0) * 9.0) * 6.0, -46.0 * u))
		var r := 3.0 + 11.0 * u
		ci.draw_circle(at.round(), r, Color(0.72, 0.72, 0.78, 0.30 * (1.0 - u)), true, -1.0, false)
		ci.draw_circle((at + Vector2(-r * 0.3, -r * 0.3)).round(), r * 0.55, Color(0.85, 0.85, 0.9, 0.18 * (1.0 - u)), true, -1.0, false)

## 加算の光: 照らされた床・闇の中の赤い目・撃鉄の閃き。
func _draw_dark_glow(ci: CanvasItem) -> void:
	if fig_k > 0.0:
		var f := scr(fig_foot)
		ci.draw_set_transform(f.round(), 0.0, Vector2(1.0, 0.22))
		for i in range(4):
			ci.draw_circle(Vector2.ZERO, 150.0 - i * 32.0, Color(1.0, 0.6, 0.3, 0.07 * fig_k), true, -1.0, false)
		ci.draw_set_transform(Vector2.ZERO)
	if dark_eyes > 0.0:
		var k := dark_eyes
		for e in EYES[dark_eye_frame]:
			var at := scr(home + Vector2(e) * UNIT).round()
			# 闇の中の目: 赤いにじみ・横に細く伸びる光・明るい芯
			for i in range(4):
				ci.draw_circle(at, 26.0 - i * 6.0, Color(RED, 0.05 * k), true, -1.0, false)
			ci.draw_rect(Rect2(at + Vector2(-38, -1), Vector2(76, 2)), Color(RED, 0.22 * k))
			ci.draw_rect(Rect2(at + Vector2(-16, -1), Vector2(32, 2)), Color(1.0, 0.35, 0.3, 0.45 * k))
			glow(ci, at, k, RED)
			ci.draw_rect(Rect2(at + Vector2(-2, -1), Vector2(4, 2)), Color(1.0, 0.75, 0.7, minf(1.0, k)))
	if hammer_k > 0.0:
		glint(ci, scr(home + HAMMER * UNIT), hammer_k)

# --- 振付 -------------------------------------------------------------------

func advance(t: float, dt: float) -> void:
	home = p.boss_foot()
	_step(t)
	glass.advance(dt)

func _step(t: float) -> void:
	open_from_list(t)
	fade_in(t, 0.36, 0.10)
	var brk: float = T["break"]
	bars(t, brk + 0.15)
	p.se(float(T.track), "enc:gent_intro_v2", 0.0, float(T.track))
	# 砕けるまで: 戦場の絵は描かない（ガラスの下）。砕けた後は暗がりから明るさが戻る
	var lift := smoothstep(brk, brk + 0.9, t)
	dark_bg = 0.85 * (1.0 - lift) + 0.18 * lift
	fog = 0.0 if t < brk else 0.55 - 0.3 * lift
	ally_tint(Color(0.5, 0.5, 0.58).lerp(Color.WHITE, lift))
	# 闇の中では紳士を映さない（目も光らない）
	dark_eyes = 0.0
	# --- 三発 ---
	fig_k = 0.0
	glass.lit = 0.0
	for s in SHOTS:
		var at: float = T[s[0]]
		var hole: Vector2 = s[2]
		p.at(at, str(s[0]), func():
			glass.crack(hole, float(s[3]), int(s[4]), 0.05)
			p.camera.shake(5, 0.22))
		_glass_lit(t, at)
	# --- 間: 撃鉄を起こす音だけ（音の中） ---
	hammer_k = 0.0
	# --- 最後の一発: 真ん中にひびが画面じゅうへ走り、止まり、砕ける ---
	var fin: float = T.final
	var fm := _muzzle(home, AIM)
	p.at(fin, "final", func():
		glass.crack(CENTER, 1000.0, 18, 0.12)
		p.camera.shake(8, 0.3))
	_glass_lit(t, fin)
	p.at(brk, "break", func():
		glass.shatter(CENTER, 0.22)
		glass.white = 0.16
		p.camera.shake(12, 0.55))
	glass.white = 0.16 * (1.0 - (t - brk) / 0.09) if t >= brk and t < brk + 0.09 else 0.0
	# --- 砕けた向こうの紳士: 構えたまま（銃口から煙）→ 銃を下ろす → 帽子に手 → 一礼 → 顔を上げる ---
	gf = ""
	if t >= brk:
		gf = _pose_after(t)
	eye = 0.0
	if t >= brk and t < float(T.lower):
		eye = 0.9
	if t >= brk and t < float(T.lower) and int((t - brk) / 0.09) > smoke.size() - 1:
		smoke.append({"p": fm.p, "t0": t})
	p.at(brk + 0.08, "brace", func(): allies_brace(true, 4.0))
	p.at(float(T.end) - 0.55, "relax", func(): allies_brace(false))
	title_card(t, brk + 0.45, Color(1.0, 0.35, 0.4))

## 弾が当たった瞬間から0.2秒、ひびが光る（闇の中では紳士の姿・銃口の光は描かない）。
func _glass_lit(t: float, at: float) -> void:
	if t < at or t >= at + 0.2:
		return
	glass.lit = maxf(glass.lit, pow(1.0 - (t - at) / 0.2, 1.4))

func _pose_after(t: float) -> String:
	var lower: float = T.lower
	var hat: float = T.hat
	var bow: float = T.bow
	var up: float = T.up
	if t < lower:
		return AIM
	if t < hat:
		return "normal_draw_fire_05" if t < lower + 0.1 else "hat_reach_00"
	if t < bow:
		return "hat_reach_00" if t < hat + 0.2 else "hat_reach_15"
	if t < bow + 0.45:
		return ["hat_reach_15", "bow_down_04", "bow_down_08", "bow_down_15"][clampi(int((t - bow) / 0.45 * 4.0), 0, 3)]
	if t < up:
		return "bow_down_15"
	if t < up + 0.45:
		return ["bow_down_08", "bow_up_08", "hat_reach_15", "hat_reach_00"][clampi(int((t - up) / 0.45 * 4.0), 0, 3)]
	return "hat_reach_00"
