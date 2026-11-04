extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 朽ちた機械武者の登場「落墨・三連斬」（2026-11-04 ユーザー採用。試作 prototypes/musha_entrance_ink_2026-11-04 の案2第3版、
## 目が光る溜めだけ約0.5秒短縮）。武者だけ特別に長い登場（約6.5秒。ほかのボスは約4.6秒）。
## 墨: 戦場の真ん中に一滴の墨が落ち、弾けた瞬間に冠のような飛沫ごと画面を呑む（0.3秒）。濃く艶のある墨。
## 溜め: 脈打っていた墨が静まり、単眼がまたたいてから灯り続けて強まる。武者が居合の構えに沈むと墨が武者の方へ
##     引き込まれて震える。鯉口を切る音 → 音も墨の動きもほぼ止まる無音の間。
## 斬撃: 「／」「＼」「―」の三連斬を見えないほどの速さで（1本1コマ・0.04秒ごと）。3本の裂け目のまま一瞬止まる。
## 開き: 3本の切れ目すべてから墨が一気に弾け、大きな塊と無数の滴が四方へ飛び散り、画面にも墨が付く。
## 登場: 覚醒後の全体攻撃の納刀と同じく、居合の構えのまま刀身の最後をゆっくり鞘へ納めている途中の武者が現れる
##     （kcn1 → kcs26 … kcs3 → kc。覚醒後の眼の上書きはせず原画のまま描く＝覚醒前の姿）。納めきった鍔鳴りで、
##     残った墨がもう一度弾ける → 立ち上がって通常の姿へ。
## 墨の層は rbm_intro_musha_ink.gd。絵は本番のコマ（rbm_musha_frames.gd）をそのまま使い、伸縮・回転はしない。

const Frames = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const InkLayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_musha_ink.gd")
## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["game:musha_aoe", "game:musha_single", "enc:musha_eye", "enc:musha_slash", "enc:musha_ink_burst",
	"enc:musha_break", "enc:musha_stance", "enc:musha_drop_fall", "enc:musha_drop_hit", "enc:musha_drone", "enc:musha_splatter"]
## 本番の武者のコマ（rbm_musha_frames.gd）。p0・p0k は眼・鍔の位置だけに使う。
const FRAMES := ["idle", "p0", "p0k", "p2k", "kc1", "kc", "kcn1", "kcs26", "kcs22", "kcs18", "kcs14", "kcn2", "kcs7", "kcs3"]
## 音・コマのほかに先に読む素材（墨のシェーダー）。
const EXTRA_PATHS := ["res://src/bossmaker/visuals/encounter/shaders/rbm_intro_musha_ink.gdshader"]

const EYE := Color(1.0, 0.16, 0.12)
const INK := Color(0.035, 0.032, 0.045, 1.0)
const STAIN := Color(0.02, 0.02, 0.035, 0.92)
const GLOW := Color(1.0, 0.55, 0.45)
const DROP_AT := 0.50
const HIT_AT := 0.72
const KOIGUCHI_AT := 2.45
const HUSH_AT := 2.55
## 三連斬 [時刻, 線が通る点, 向き]
const SLASHES := [[2.90, Vector2(640, 380), Vector2(0.92, -0.40)], [2.94, Vector2(600, 330), Vector2(0.88, 0.48)], [2.98, Vector2(640, 300), Vector2(-1.0, 0.10)]]
const OPEN_AT := 3.22
## 墨が晴れてからのコマ（覚醒後の全体攻撃 rbm_musha_awakened_frame_presentation.gd の ALL_KEYS の kcn1 以降と同じ順。
## kcn1 の溜めだけ 1.06秒 → 0.70秒）。CLICK で納めきって鍔鳴り。
const NOTO := [[0.00, "kcn1"], [0.70, "kcs26"], [0.86, "kcs22"], [1.00, "kcs18"], [1.13, "kcs14"], [1.25, "kcn2"],
	[1.37, "kcs7"], [1.48, "kcs3"], [1.59, "kc"], [2.15, "kc1"], [2.35, "p2k"], [2.70, "idle"]]
const CLICK := 1.59
## 鍔が鳴る音は、本番のボス戦の機械武者の納刀の鍔鳴りそのもの（覚醒前の全体攻撃の音 musha_aoe.wav の 5.37秒から0.14秒。
## 覚醒後の全体攻撃が「覚醒前の納刀の音」として流用している所と同じ）。音量も本番の武者の攻撃の音と同じ（+3dB）。
const NOTO_FROM := 5.37
const NOTO_LENGTH := 0.14

var ink: InkLayer
var fr := ""
var foot := Vector2.ZERO
var lines: Array = []
var covered := true
var top_eye := 0.0
var top_glint_at := Vector2.ZERO
var top_glint_k := 0.0
var glint_at := Vector2.ZERO
var glint_k := 0.0

func prepare() -> void:
	super.prepare()
	eye_color = EYE
	foot = p.boss_foot()
	ink = InkLayer.new()
	ink.name = "IntroMushaInkLayer"
	p.add_child(ink)
	ink.setup(p.view, p.camera)
	ink.extra_glow_fn = _draw_top_glow
	for s in SLASHES:
		lines.append(through(s[1], s[2]))
	ink.param("hole_line1", Vector4(lines[0][0].x, lines[0][0].y, lines[0][1].x, lines[0][1].y))
	ink.param("hole_line2", Vector4(lines[1][0].x, lines[1][0].y, lines[1][1].x, lines[1][1].y))
	ink.param("hole_line3", Vector4(lines[2][0].x, lines[2][0].y, lines[2][1].x, lines[2][1].y))

func duration() -> float:
	return 6.5

# --- 描画 -------------------------------------------------------------------

func draw_body(ci: CanvasItem) -> void:
	if fr.is_empty():
		return
	draw_frame(ci, fr, foot, Color.WHITE)

func draw_flat(_ci: CanvasItem) -> void:
	pass

## コマを描く。覚醒後の演出用のコマ（kc* など "patch" 付き）は、覚醒後の眼の上書きをせず原画のまま描く
## （衣装・笠は覚醒前と同じ絵なので、覚醒前の姿のまま使える）。
static func draw_frame(ci: CanvasItem, f: String, at: Vector2, m: Color) -> void:
	var e: Dictionary = Frames.FR[f]
	if not bool(e.get("patch", false)):
		Frames.draw(ci, Frames.state(f, at), m)
		return
	var tx := Frames.texture(e.tex)
	if tx == null:
		return
	var r: Rect2 = e.rect
	var sc: float = e.scale
	ci.draw_set_transform(at.round(), 0.0, Vector2(sc, sc))
	ci.draw_texture_rect_region(tx, Rect2(r.position - (e.anchor as Vector2), r.size), r, m)
	ci.draw_set_transform(Vector2.ZERO)

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not fr.is_empty():
		out.append(point_of(fr, "eye", Vector2(-20, -150)))
	return out

func extra_top(ci: CanvasItem) -> void:
	if glint_k > 0.0:
		glint(ci, glint_at, glint_k)

## 墨の上（画面の座標）に灯る眼と鍔の閃き。
func _draw_top_glow(ci: CanvasItem) -> void:
	if top_glint_k > 0.0:
		glint(ci, scr(top_glint_at), top_glint_k)
	if top_eye <= 0.0:
		return
	var e := scr(point_of("p0", "eye", Vector2(-20, -150)))
	glow(ci, e, top_eye, EYE)
	# 墨の中に灯る眼は、周りの墨をわずかに赤く照らす
	ci.draw_circle(e.round(), 16.0, Color(EYE, 0.05 * top_eye), true, -1.0, false)
	ci.draw_circle(e.round(), 7.0, Color(EYE, 0.10 * top_eye), true, -1.0, false)

# --- 道具 -------------------------------------------------------------------

func point_of(f: String, key: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var s := Frames.state(f, foot)
	return Frames.point(s, key) if Frames.has_point(s, key) else (foot + fallback)

## 戦場の座標 → 画面の座標（墨・光の層は画面の座標）。
func scr(v: Vector2) -> Vector2:
	return p.stage.get_global_transform_with_canvas() * v - Vector2(ink.top_layer.offset)

## 点 c を通る向き dir の線の、画面の中の部分（両端は画面の縁。斬撃の光は縁で細くなる）。
static func through(c: Vector2, dir: Vector2) -> Array:
	dir = dir.normalized()
	var t0 := -INF
	var t1 := INF
	for ax in range(2):
		var dc: float = dir[ax]
		var cc: float = c[ax]
		if absf(dc) < 0.0001:
			continue
		var hi := 1292.0 if ax == 0 else 732.0
		var a := (-12.0 - cc) / dc
		var b := (hi - cc) / dc
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	return [c + dir * t0, c + dir * t1]

## 時刻表 [[時刻, コマ], ...] から今のコマ（最初の時刻より前は空＝描かない）。
static func key_at(t: float, keys: Array) -> String:
	var out := ""
	for k in keys:
		if t >= float(k[0]):
			out = str(k[1])
	return out

## 鯉口・納刀の鍔鳴り（本番の音そのもの）と、鍔の小さな閃き（墨の中なら墨の上に描く）。
func koiguchi(t: float, at_t: float, key: String, f: String) -> void:
	p.at(at_t, key, func(): p.sfx.play("game:musha_aoe", 3.0, NOTO_FROM, NOTO_LENGTH))
	if t >= at_t and t < at_t + 0.22:
		var k := 1.0 - (t - at_t) / 0.22
		if covered:
			top_glint_at = point_of(f, "tsuba", Vector2(-10, -90))
			top_glint_k = k
		else:
			glint_at = point_of(f, "tsuba", Vector2(-10, -90))
			glint_k = k

## 3本の切れ目に沿って、両側へ墨の滴を飛ばす（n: 1本あたりの数）。
func burst(n: int, speed: float, r1: float) -> void:
	for ends in lines:
		var a: Vector2 = ends[0]
		var b: Vector2 = ends[1]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		for i in range(n):
			var side := -1.0 if ink.rng.randf() < 0.5 else 1.0
			var v := nrm * side * speed * ink.rng.randf_range(0.4, 1.0) + d * ink.rng.randf_range(-340.0, 340.0)
			ink.drop(a.lerp(b, ink.rng.randf()) + nrm * side * 4.0, v, ink.rng.randf_range(2.0, r1), 1.1 * ink.rng.randf_range(0.7, 1.1), INK, 1300.0)

## 画面に付いた墨（いびつな本体・飛んできた向きの尾・周りの細かい飛沫）。
func stains(count: int, rect: Rect2, r0: float, r1: float, life: float) -> void:
	for i in range(count):
		var at := rect.position + Vector2(ink.rng.randf() * rect.size.x, ink.rng.randf() * rect.size.y)
		var r := ink.rng.randf_range(r0, r1)
		var l := life * ink.rng.randf_range(0.6, 1.0)
		for k in range(3):
			ink.drop(at + Vector2.from_angle(ink.rng.randf() * TAU) * r * 0.45, Vector2.ZERO, r * ink.rng.randf_range(0.55, 0.85), l, STAIN, 0.0, true)
		var dir := Vector2.from_angle(ink.rng.randf() * TAU)
		for k in range(4):
			ink.drop(at + dir * r * (1.0 + k * 0.9), Vector2.ZERO, maxf(1.0, r * (0.55 - k * 0.12)), l, STAIN, 0.0, true)
		for k in range(ink.rng.randi_range(3, 7)):
			var o := Vector2.from_angle(ink.rng.randf() * TAU) * ink.rng.randf_range(r * 1.4, r * 3.5)
			ink.drop(at + o, Vector2.ZERO, ink.rng.randf_range(1.0, 2.0), l * 0.8, STAIN, 0.0, true)

# --- 振付 -------------------------------------------------------------------

func advance(t: float, dt: float) -> void:
	foot = p.boss_foot()
	glint_k = 0.0
	top_glint_k = 0.0
	var slow := _step(t)
	ink.advance(dt, slow)

## 1コマ分を進め、墨と滴の時間の進み（1=普通・0=止める）を返す。
func _step(t: float) -> float:
	open_from_list(t)
	fade_in(t, 0.36, 0.14)
	bars(t, OPEN_AT + 0.25)
	dark_bg = 0.18 * (1.0 - smoothstep(OPEN_AT, OPEN_AT + 0.25, t))
	# --- 一滴が落ちて弾け、画面を呑む ---
	p.at(DROP_AT, "drop", func():
		ink.drop(Vector2(640, -30), Vector2(0, 1300), 7.0, HIT_AT - DROP_AT, INK, 3000.0)
		p.sfx.play("enc:musha_drop_fall", -4.0))
	ink.param("cover", ease_out((t - HIT_AT) / 0.30) if t >= HIT_AT else 0.0)
	# 晴れきった後は描かない（透明でも全画面のシェーダーは重い）。落ちる前は黒い幕の下で描いておき、シェーダーの準備を済ませる
	ink.show_ink(t < OPEN_AT + 0.45)
	p.at(HIT_AT, "hit", func():
		var c := Vector2(640, 330)
		for i in range(56):
			var a := ink.rng.randf() * TAU
			ink.drop(c, Vector2.from_angle(a) * ink.rng.randf_range(500, 1150) + Vector2(0, -200), ink.rng.randf_range(2.0, 8.0), ink.rng.randf_range(0.5, 0.8), INK, 1400.0)
		stains(14, Rect2(40, 30, 1200, 650), 4.0, 11.0, 2.4)
		p.camera.shake(3, 0.25)
		p.sfx.play("enc:musha_drop_hit", 0.0)
		p.sfx.play("enc:musha_ink_burst", -5.0))
	# --- 溜め ---
	# 墨の脈打ちは静まっていく
	ink.param("sheen", 1.5 + 0.6 * sin(t * 9.0) * (1.0 - smoothstep(1.3, 2.1, t)))
	# 居合の構えに沈むと、墨が武者の方へ引き込まれて震える
	ink.param("churn", 0.30 * smoothstep(1.70, 2.45, t))
	p.se(1.50, "enc:musha_drone", -9.0)
	p.se(1.70, "enc:musha_stance", -4.0)
	p.at(1.70, "sink", func(): p.camera.shake(1, 0.3))
	top_eye = 0.0
	if t < OPEN_AT:
		if (t >= 1.20 and t < 1.25) or (t >= 1.31 and t < 1.38):
			top_eye = 0.9
		elif t >= 1.50:
			top_eye = 0.5 + 0.8 * smoothstep(1.50, 2.80, t)
		if t >= float(SLASHES[0][0]):
			top_eye = 1.7
	p.se(1.20, "enc:musha_eye", -3.0)
	covered = t < OPEN_AT
	koiguchi(t, KOIGUCHI_AT, "koiguchi", "p0k")
	# --- 三連斬（見えないほどの速さ） ---
	for i in range(SLASHES.size()):
		var s: Array = SLASHES[i]
		var ends: Array = lines[i]
		p.at(float(s[0]), "slash%d" % i, func():
			ink.slash(ends[0], ends[1], 0.02, OPEN_AT - float(s[0]) - 0.02, 0.10, GLOW, 3.0)
			if i == 0:
				p.sfx.play("game:musha_single", 0.0, 2.70, 0.9)
				p.sfx.play("enc:musha_slash", -4.0, 0.0, 0.6, 1.15)
			elif i == 1:
				p.sfx.play("enc:musha_slash", -5.0, 0.0, 0.6, 1.0)
			else:
				p.sfx.play("enc:musha_slash", -5.0, 0.0, -1.0, 0.86))
	# --- 3本の切れ目から一気に弾け飛ぶ ---
	ink.param("hole", ease_out((t - OPEN_AT) / 0.42) if t >= OPEN_AT else 0.0)
	p.at(OPEN_AT, "open", func():
		burst(170, 1300.0, 12.0)
		var c := Vector2(630, 340)
		for i in range(40):
			var a := ink.rng.randf() * TAU
			ink.drop(c + Vector2.from_angle(a) * ink.rng.randf_range(0, 160), Vector2.from_angle(a) * ink.rng.randf_range(500, 1050) + Vector2(0, -260),
				ink.rng.randf_range(6.0, 12.0), ink.rng.randf_range(0.8, 1.3), INK, 1500.0)
		stains(34, Rect2(20, 20, 1240, 680), 5.0, 15.0, 2.6)
		p.camera.shake(9, 0.5)
		p.sfx.play("enc:musha_splatter", 0.0)
		p.sfx.play("enc:musha_drop_hit", -3.0)
		p.sfx.play("enc:musha_ink_burst", -6.0)
		p.sfx.play("enc:musha_break", -6.0))
	# --- 納刀の途中で現れ、納めきった鍔鳴りで残りの墨がもう一度弾ける ---
	var keys: Array = []
	for k in NOTO:
		keys.append([OPEN_AT + float(k[0]), k[1]])
	fr = key_at(t, keys)
	eye = 1.0 if t < OPEN_AT + CLICK + 0.4 else 0.6
	koiguchi(t, OPEN_AT + CLICK, "noto", "kc")
	p.at(OPEN_AT + CLICK, "noto_burst", func():
		burst(60, 900.0, 8.0)
		stains(12, Rect2(40, 40, 1200, 640), 4.0, 10.0, 1.6)
		p.camera.shake(3, 0.25)
		p.sfx.play("enc:musha_splatter", -5.0))
	p.at(OPEN_AT + 0.12, "brace", func(): allies_brace(true, 0.0))
	p.at(OPEN_AT + 2.60, "relax", func(): allies_brace(false))
	title_card(t, OPEN_AT + 0.50, Color(1.0, 0.42, 0.38))
	# 鯉口を切ってから斬るまでは墨の動きもほぼ止まる無音の間、斬ってから弾けるまでは止める
	if t >= float(SLASHES[0][0]) and t < OPEN_AT:
		return 0.0
	if t >= HUSH_AT and t < float(SLASHES[0][0]):
		return 0.12
	return 1.0
