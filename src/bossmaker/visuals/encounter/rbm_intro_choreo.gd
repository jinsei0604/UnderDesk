extends RefCounted
## 登場演出（案B シネマ型）の振付の共通部分（表示専用）。
## ボスごとの振付（intro/rbm_intro_<ボス>.gd）がこれを継承し、ショットの時間割とボスの動き・粒・音を持つ。
## 共通の流れ: 前の画面が電源を切るように閉じる（rbm_screen_close.gd、0〜0.30秒）→ 帯が入る → 寄りのカット → 引きで大きな動き
## → 題字 → 帯が抜けて通常の戦闘へ。
## 絵は既存のポーズ（またはコマ）をそのまま使い、伸縮・回転はしない。動きは「ポーズの切り替え」と「整数の画素の移動」だけ。
## 使う音は各振付の SOUNDS、ボス専用のコマ絵は FRAMES で宣言する（事前読み込み。再生中に初めて読まない）。
const Sprites = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_sprites.gd")
const S = preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")

var p   # intro_player.gd
var asset := ""
var bs := {}            # ボス本体 {pose, foot, mod(Color), alpha, ground(地面より下は描かない), rim(Color), rim_off}
var white := 0.0        # 本体を白く光らせる（flat 層）
var shadow := 0.0       # 本体を黒い影にする（flat 層。0〜1）
var dark_bg := 0.0      # 背景だけを暗くする（キャラより後ろ）
var dark_bg_color := Color(0.01, 0.015, 0.04)
var dark := 0.0         # 味方も含めて前を暗くする
var dark_color := Color(0.01, 0.015, 0.04)
var eye := 0.0          # 目の光の強さ
var eye_color := Color(1.0, 0.86, 0.32)
var eye_cover := Color(0, 0, 0, 0)  # 目を消す時の色（a>0 で目を塗りつぶす）
var light_shaft := 0.0  # 上から差す光の筋（背景の上・キャラの後ろ）
var light_shaft_color := Color(0.75, 0.85, 1.0)
var light_shaft_x := 780.0
var ground_glow := 0.0  # ボスの足元の床の光
var ground_glow_color := Color(1, 1, 1)
const END_FADE := 0.55  # 終わりの帯が抜ける長さ

## 味方の身構えのポーズ（本番の12ポーズから。戦闘の状態は変えない）
const READY_POSE := {"hero": 1, "butler": 1, "healer": 1, "samurai": 6, "tank": 10}
## 全ボス共通の音（題字の一打）。前の画面が閉じる音（enc:crt_off）は rbm_screen_close.gd が鳴らす。
const COMMON_SOUNDS := ["enc:crt_off", "enc:title_hit"]
## ボスごとの音は各振付の const SOUNDS、ボス専用のコマ絵（武者・紳士）は const FRAMES（コマの名前）で宣言する
## （rbm_intro_player.gd の warm_paths() が読む）。

func prepare() -> void:
	p.body.draw_fn = draw_body
	p.flat.draw_fn = draw_flat
	p.top.draw_fn = draw_top
	p.back.draw_fn = draw_back
	asset = str(p.stage.get("_asset_ids")["boss"])

func duration() -> float:
	return 4.5

func advance(_t: float, _dt: float) -> void:
	pass

# --- 共通の流れ -------------------------------------------------------------

## 前の画面が閉じる（0〜0.30秒）。本番では戦闘を始める前に rbm_screen_close.gd が見せるので、ここでは何もしない
## （再生は 0.30秒から始まり、その時は黒）。
func open_from_list(_t: float) -> void:
	pass

## 黒から絵が出る（at〜at+len）。
func fade_in(t: float, at: float, length: float = 0.25) -> void:
	if t < at:
		p.overlay.fade = 1.0
	else:
		p.overlay.fade = 1.0 - smoothstep(at, at + length, t)

## シネマの帯。in_at に入り、終わりの END_FADE で抜ける。
func bars(t: float, in_at: float) -> void:
	var out_at := duration() - END_FADE
	if t < in_at:
		p.overlay.letterbox = 0.0
	elif t < out_at:
		p.overlay.letterbox = ease_out((t - in_at) / 0.28)
	else:
		p.overlay.letterbox = 1.0 - ease_in_out((t - out_at) / 0.4)
	p.overlay.vignette = 0.55 * p.overlay.letterbox

## 題字（左下）。start に出て、終わりの少し前に左へ抜ける。
func title_card(t: float, start: float, accent: Color = S.ACCENT) -> void:
	var out_at := duration() - END_FADE - 0.05
	if t < start:
		p.overlay.title = {}
		return
	p.overlay.title = {"name": p.boss_name, "author": p.author, "label": "BOSS BATTLE", "t": t - start,
		"out": clampf((t - out_at) / 0.3, 0.0, 1.0), "accent": accent}
	p.se(start, "enc:title_hit", -2.0)

## 寄りのカット（整数倍。focus は寄りの中心のステージ座標）。
func cut(key: String, at: float, zoom: int, focus: Vector2) -> void:
	p.at(at, "cut:" + key, func(): p.camera.cut(zoom, focus))

## 寄りのままゆっくり動かす。
func pan(t: float, t0: float, t1: float, zoom: int, from: Vector2, to: Vector2) -> void:
	if t < t0 or t > t1 + 0.001:
		return
	var k := ease_in_out((t - t0) / maxf(0.01, t1 - t0))
	p.camera.cut(zoom, from.lerp(to, k).snapped(Vector2(1, 1)))

## 味方の見た目の色（暗がりのショット）。Color.WHITE で戻す。
func ally_tint(c: Color) -> void:
	for key in p.ally_keys():
		var v: Control = p.stage.get("_visuals")[key]
		v.modulate = Color(c.r, c.g, c.b, v.modulate.a)

## 味方が身構える（back: 少し後ずさる量）。on=false で元へ戻す。
func allies_brace(on: bool, back: float = 0.0) -> void:
	for key in p.ally_keys():
		var a: String = p.ally_asset(key)
		if on:
			p.ally_pose(key, int(READY_POSE.get(a, 1)), Vector2(-back, 0))
		else:
			p.ally_pose(key, 0)

# --- 描画 -------------------------------------------------------------------

func draw_back(ci: CanvasItem) -> void:
	if dark_bg > 0.0:
		ci.draw_rect(Rect2(-16, -16, 1312, 752), Color(dark_bg_color, dark_bg))
	if light_shaft > 0.0:
		_draw_shaft(ci)
	if ground_glow > 0.0:
		var f: Vector2 = Vector2(bs.get("foot", p.boss_foot()))
		for i in range(4):
			var w := 150.0 - i * 30.0
			ci.draw_set_transform(f.round(), 0.0, Vector2(1.0, 0.22))
			ci.draw_circle(Vector2.ZERO, w, Color(ground_glow_color, 0.08 * ground_glow), true, -1.0, false)
			ci.draw_set_transform(Vector2.ZERO)
	extra_back(ci)

func _draw_shaft(ci: CanvasItem) -> void:
	var x := light_shaft_x
	var a := light_shaft
	for i in range(3):
		var w := 70.0 + i * 40.0
		var pts := PackedVector2Array([Vector2(x - w * 0.35, -20), Vector2(x + w * 0.35, -20), Vector2(x + w * 0.75, 520), Vector2(x - w * 0.75, 520)])
		ci.draw_colored_polygon(pts, Color(light_shaft_color, 0.06 * a))

func draw_body(ci: CanvasItem) -> void:
	if bs.is_empty():
		return
	var ground := float(bs.get("ground", INF))
	var foot: Vector2 = Vector2(bs.foot)
	if bs.has("rim"):
		# 縁の光: 本体を少しずらして明るく描き、その上に本体を重ねる（縁の1〜2pxだけが光って見える）
		Sprites.draw(ci, asset, int(bs.pose), foot + Vector2(bs.get("rim_off", Vector2(-2, -2))), bs.rim, ground)
	var mod: Color = bs.get("mod", Color.WHITE)
	Sprites.draw(ci, asset, int(bs.pose), foot, Color(mod, mod.a * float(bs.get("alpha", 1.0))), ground)
	if eye_cover.a > 0.0:
		for e in eye_points():
			ci.draw_rect(Rect2((e - Vector2(2, 1)).round(), Vector2(5, 3)), eye_cover)

func draw_flat(ci: CanvasItem) -> void:
	if bs.is_empty():
		return
	if shadow > 0.0:
		Sprites.draw(ci, asset, int(bs.pose), bs.foot, Color(0.02, 0.02, 0.05, shadow), float(bs.get("ground", INF)))
	if white > 0.0:
		Sprites.draw(ci, asset, int(bs.pose), bs.foot, Color(1, 1, 1, white), float(bs.get("ground", INF)))

func draw_top(ci: CanvasItem) -> void:
	if dark > 0.0:
		ci.draw_rect(Rect2(-16, -16, 1312, 752), Color(dark_color, dark))
	if eye > 0.0:
		for e in eye_points():
			glow(ci, e, eye, eye_color)
	extra_top(ci)

func extra_top(_ci: CanvasItem) -> void:
	pass

func extra_back(_ci: CanvasItem) -> void:
	pass

## 床を流れる霧の帯（横に長い楕円をいくつも重ね、ゆっくり横へ流す）。front=true は手前用（少なく・薄く）。
func draw_fog(ci: CanvasItem, amount: float, color: Color, front: bool = false) -> void:
	if amount <= 0.0:
		return
	var tt: float = p.age
	var n := 5 if front else 9
	for i in range(n):
		var speed := (20.0 + i * 4.0) * (-1.0 if front else 1.0)
		var x := fmod(200.0 + i * (260.0 if front else 140.0) + tt * speed + 3000.0, 1500.0) - 100.0
		var y := (470.0 + (i % 2) * 40.0) if front else (360.0 + (i % 3) * 50.0)
		var w := (320.0 if front else 220.0 + (i % 4) * 40.0)
		ci.draw_set_transform(Vector2(x, y).round(), 0.0, Vector2(1.0, 0.30))
		ci.draw_circle(Vector2.ZERO, w * 0.5, Color(color, (0.06 if front else 0.10) * amount), true, -1.0, false)
		ci.draw_circle(Vector2.ZERO, w * 0.3, Color(color.lightened(0.15), (0.05 if front else 0.08) * amount), true, -1.0, false)
		ci.draw_set_transform(Vector2.ZERO)

## 目の位置（ステージ座標）。ボスごとに上書きする。
func eye_points() -> Array[Vector2]:
	return []

## ポーズ画像（512×512）の上の画素の点 → ステージ座標。
func px(pose_point: Vector2, foot: Vector2) -> Vector2:
	var m := Sprites.meta(asset)
	return (foot + (pose_point - Vector2(m.foot)) * float(m.scale)).round()

## ドット絵の光: 芯（2px）と、十字のにじみ・外側の淡い四角。
static func glow(ci: CanvasItem, at: Vector2, k: float, color: Color) -> void:
	var c := at.round()
	ci.draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), Color(color, 0.08 * k))
	ci.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), Color(color, 0.22 * k))
	for d in [Vector2(-5, -1), Vector2(3, -1), Vector2(-1, -4), Vector2(-1, 2)]:
		ci.draw_rect(Rect2(c + d, Vector2(2, 2)), Color(color, 0.45 * k))
	ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(color.lightened(0.6), minf(1.0, 1.2 * k)))

## 小さな閃き（刃・鍔・目）: 十字の光が短く伸びて消える。
static func glint(ci: CanvasItem, at: Vector2, k: float, color: Color = Color(1, 0.98, 0.9)) -> void:
	if k <= 0.0:
		return
	var c := at.round()
	var ln := roundf(4.0 + 16.0 * k)
	ci.draw_rect(Rect2(c + Vector2(-ln, -1), Vector2(ln * 2, 2)), Color(color, 0.75 * k))
	ci.draw_rect(Rect2(c + Vector2(-1, -ln * 0.7), Vector2(2, roundf(ln * 1.4))), Color(color, 0.75 * k))
	ci.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(color, k))

# --- 緩急 -------------------------------------------------------------------

static func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

static func ease_in(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x

static func ease_in_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## 0〜length で、高さ h だけ跳ねて戻る。
static func hop(x: float, length: float, h: float) -> float:
	if x < 0.0 or x > length:
		return 0.0
	return h * sin(PI * x / length)

## 着地の沈み込み（px）: 着地の瞬間に depth 沈み、0.18秒で戻る。
static func land_dip(x: float, depth: float) -> float:
	if x < 0.0 or x > 0.18:
		return 0.0
	return roundf(depth * sin(PI * x / 0.18))
