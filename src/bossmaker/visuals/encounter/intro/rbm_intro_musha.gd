extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 朽ちた機械武者の登場（案B・第2版）。本番のコマ描画（rbm_musha_frames.gd）の覚醒前のコマだけを使う
## （idle=静止姿・p2k=柄に手・p0=居合の構え・p0k=鯉口を切る）。覚醒後のコマ（a*・s*）は使わない。絵は変形させない。
## 寄り: 月から竹林へゆっくり下りると、竹の葉が舞う中に静かに立つ影。単眼が瞬いて赤く灯る。
## 寄り: 柄に手がかかり、鯉口が鳴る（鍔の閃き）。
## 引き: 居合の構えへ沈み、足元から墨の筆跡が走る → 味方が身構える → 題字。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["game:musha_aoe", "enc:musha_wind", "enc:musha_eye", "game:wind_swing", "enc:musha_stance"]
## 本番の武者のコマ（rbm_musha_frames.gd）。
const FRAMES := ["idle", "p2k", "p0", "p0k"]

const Frames = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const EYE := Color(1.0, 0.16, 0.12)
const INK := Color(0.045, 0.04, 0.06, 0.92)
const LEAF := Color(0.45, 0.62, 0.32)

var fr := "idle"
var foot := Vector2.ZERO
var mod := Color.WHITE
var stroke := {}
var glint_at := Vector2.ZERO
var glint_k := 0.0

func prepare() -> void:
	super.prepare()
	eye_color = EYE
	foot = p.boss_foot()

func duration() -> float:
	return 4.6

func _state() -> Dictionary:
	return Frames.state(fr, foot)

func draw_body(ci: CanvasItem) -> void:
	if fr.is_empty():
		return
	var s := _state()
	Frames.draw(ci, s, mod)
	if eye_cover.a > 0.0 and Frames.has_point(s, "eye"):
		var e := Frames.point(s, "eye")
		ci.draw_rect(Rect2((e - Vector2(2, 2)).round(), Vector2(4, 4)), eye_cover)

func draw_flat(_ci: CanvasItem) -> void:
	pass

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var s := _state()
	if Frames.has_point(s, "eye"):
		out.append(Frames.point(s, "eye"))
	return out

func extra_top(ci: CanvasItem) -> void:
	if glint_k > 0.0:
		glint(ci, glint_at, glint_k)

func extra_back(ci: CanvasItem) -> void:
	if stroke.is_empty():
		return
	# 墨の筆跡: 足元から左へ走る、端がかすれた帯（4pxの格子）。
	var a: float = stroke.a
	var from: Vector2 = stroke.from
	var to: Vector2 = stroke.to
	var end := from.lerp(to, float(stroke.k))
	var x := minf(from.x, end.x)
	var x1 := maxf(from.x, end.x)
	var i := 0
	while x < x1:
		var u := (x - to.x) / maxf(1.0, from.x - to.x)
		var h := roundf(lerpf(4.0, 16.0, sin(clampf(u, 0.0, 1.0) * PI) * 0.8 + 0.2) / 2.0) * 2.0
		var wobble := float([0, 2, -2, 0, 2, 0, -2][i % 7])
		var gap := (i % 11 == 3 and u < 0.35) or (i % 7 == 5 and u < 0.15)
		if not gap:
			ci.draw_rect(Rect2(Vector2(x, from.y - h * 0.5 + wobble).round(), Vector2(4, h)), Color(INK, INK.a * a))
		x += 4.0
		i += 1

## 鍔が鳴る音は、本番のボス戦の機械武者の納刀の鍔鳴りそのもの（覚醒前の全体攻撃の音 musha_aoe.wav の 5.37秒から0.14秒。
## 覚醒後の全体攻撃 rbm_musha_awakened_frame_presentation.gd が「覚醒前の納刀の音」として流用している所と同じ）。
## 音量も本番の武者の攻撃の音と同じ（RBMMushaMotion.track_gain = +3dB）。
const NOTO_FROM := 5.37
const NOTO_LENGTH := 0.14

func _koiguchi(at_t: float, key: String) -> void:
	p.at(at_t, key, func():
		p.sfx.play("game:musha_aoe", 3.0, NOTO_FROM, NOTO_LENGTH)
		var s := _state()
		p.fx.stars(Frames.point(s, "tsuba") if Frames.has_point(s, "tsuba") else foot + Vector2(0, -80), 4, Color(1, 0.97, 0.88), 4.0))

func advance(t: float, _dt: float) -> void:
	foot = p.boss_foot()
	glint_k = 0.0
	open_from_list(t)
	fade_in(t, 0.36, 0.3)
	bars(t, 1.40)
	# --- ショット1: 寄り。月から竹林へ下りて、静かに立つ影（0.36〜1.40） ---
	if t < 1.40:
		pan(t, 0.36, 1.25, 2, Vector2(900, 170), Vector2(830, 250))
		dark_bg = 0.30
		ally_tint(Color(0.4, 0.4, 0.5))
		mod = Color(0.42, 0.40, 0.48)
		fr = "idle"
		var on := t >= 1.02 and (t < 1.06 or t >= 1.12)
		eye_cover = Color(0, 0, 0, 0) if on else Color(0.05, 0.04, 0.05, 1.0)
		eye = (0.6 if t < 1.06 else 1.0) if on else 0.0
		p.at(0.36, "leaves", func(): p.fx_back.motes(Rect2(700, 60, 360, 320), 18, LEAF, Vector2(-14, 22), 2.4))
		p.se(0.36, "enc:musha_wind", -4.0)
		p.se(1.02, "enc:musha_eye", -2.0)
		return
	# --- ショット2: 寄り。柄に手、鯉口が鳴る（1.40〜2.05） ---
	if t < 2.05:
		p.at(1.40, "cut2", func(): p.camera.cut(2, Frames.point(Frames.state("p2k", foot), "tsuba") + Vector2(-40, -10)))
		dark_bg = 0.30
		mod = Color(0.62, 0.60, 0.66)
		eye_cover = Color(0, 0, 0, 0)
		eye = 0.8
		fr = "idle" if t < 1.55 else "p2k"
		p.se(1.55, "game:wind_swing", -12.0)
		if t >= 1.80:
			glint_at = Frames.point(Frames.state("p2k", foot), "tsuba")
			glint_k = maxf(0.0, 1.0 - (t - 1.80) / 0.22)
		_koiguchi(1.80, "koiguchi1")
		return
	# --- ショット3: 引き。居合の構え・墨の筆跡 → 題字（2.05〜） ---
	p.at(2.05, "cut3", func(): p.camera.cut(1, Vector2(640, 360)))
	var lift := smoothstep(2.05, 2.25, t)
	dark_bg = 0.30 * (1.0 - lift)
	ally_tint(Color(0.4, 0.4, 0.5).lerp(Color.WHITE, lift))
	mod = Color(0.62, 0.60, 0.66).lerp(Color.WHITE, lift)
	eye = 1.0 if t < 3.3 else 0.6
	fr = "p0"
	if t >= 2.62 and t < 3.70:
		fr = "p0k"
	elif t >= 3.70 and t < 3.92:
		fr = "p2k"
	elif t >= 3.92:
		fr = "idle"
	p.at(2.10, "stance", func():
		p.camera.shake(2, 0.2)
		p.sfx.play("enc:musha_stance", -2.0)
		p.fx.ink(foot + Vector2(-20, -2), 18, -1.0, INK, 1.2))
	p.at(2.16, "brace", func(): allies_brace(true, 0.0))
	if t >= 2.10:
		stroke = {"from": foot + Vector2(10, 2), "to": foot + Vector2(-560, 2), "k": ease_out((t - 2.10) / 0.28), "a": 1.0 - smoothstep(3.3, 3.9, t)}
	if t >= 2.62 and t < 2.86:
		glint_at = Frames.point(Frames.state("p0k", foot), "tsuba")
		glint_k = 1.0 - (t - 2.62) / 0.24
	_koiguchi(2.62, "koiguchi2")
	p.at(3.92, "relax", func(): allies_brace(false))
	title_card(t, 2.40, Color(1.0, 0.42, 0.38))
