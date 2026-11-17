extends "res://src/bossmaker/visuals/clock/rbm_clock_fx_fall.gd"
## 本番（2026-11-17 ユーザー「これでいいね」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/post_defeat.gd でユーザーが採用した内容をそのまま移した。
## 終刻の給仕長・撃破（2026-11-16）:
## 意味: 「自分が告げてきた“終わりの時刻”が、自分に来る」。
## 構えが崩れた姿（覚醒後全体の4枚目）→ オーラが乱れて燃え上がり、空に大時計がせり上がる。針がすべて逆回転し、だんだん速く巻き戻りながら12時へ向かう
##   （2026-11-16 ユーザー「覚醒後の撃破は時計の針が逆回転になるように」: 彼の時間が巻き戻って消える）
## → 12時で両針が重なる: 鐘の一打・時が止まる（ヒットストップ）→ 大時計と給仕長が同時に砕ける（ガラスの雨・青緑と深紅の閃光）
## → 体はガラスの粒になってほどけ、オーラが散る → 立っていた床に、ひびの入った黒い懐中時計が一つ立って残り（竜頭・吊り輪・鎖）、照らされたまま。

const TP := {"surge": 0.30, "sky": 0.55, "twelve": 1.90, "gone": 2.95, "remain": 3.10, "end": 5.20}
const CYAN := Color("#7ee0ec")
const CRIMSON := Color("#e03848")
const BURST := ["#145a78", "#1e78a0", "#2aa0c0", "#5ac8dc", "#9ae8f0", "#d8fafc", "#f0feff", "#ffffff"]
const DARK_BRASS := {"brass_l": Vector3(.86, .72, .45), "brass": Vector3(.55, .40, .20), "brass_d": Vector3(.22, .14, .07), "face_l": Vector3(.86, .84, .80), "face_d": Vector3(.5, .48, .46),
	"steel": Vector3(.12, .3, .36), "sec_col": Vector3(.95, .2, .25)}

var sky: ColorRect
var blast: ColorRect

func duration() -> float:
	return TP.end

func impact() -> float:
	return TP.twelve

func stops() -> Array:
	return [[TP.twelve, 0.14]]

func extra_poses() -> Dictionary:
	return {POSE: ["post_all", 4]}

func _build() -> void:
	sky = dial_quad(back, DARK_BRASS.merged({"seed": 23.0, "thick": 10.0}))
	blast = blast_quad(front, BURST, BURST, {"amp": 30., "k": .05, "seed": 5.6, "glow": .7, "glow_col": Vector3(.5, .9, 1.), "glow_r": 50.})
	super._build()
	face_dial.visible = false
	left.material.set_shader_parameter("brass_l", Vector3(.7, .6, .45))
	left.material.set_shader_parameter("brass", Vector3(.4, .3, .18))
	left.material.set_shader_parameter("brass_d", Vector3(.16, .1, .06))
	left.material.set_shader_parameter("face_l", Vector3(.6, .6, .6))
	left.material.set_shader_parameter("face_d", Vector3(.32, .32, .34))

func _step(t: float) -> void:
	b_shaft.reset(); b_glow.reset(); b_front.reset(); b_chain.reset()
	face_dial.visible = false
	var ab := t - TP.twelve
	var su := RBMHeroFx.ramp(t, TP.surge, TP.twelve)
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.15], [TP.twelve - 0.05, 0.62], [TP.twelve + 0.05, 0.18], [TP.gone, 0.4], [TP.end, 0.26]])
	view["dim_col"] = Color(0.0, 0.02, 0.05)
	# オーラが乱れて燃え上がる → 砕けて散る
	view["hero"]["sun_aura"] = (1.0 + 1.6 * su * (0.75 + 0.25 * sin(t * 17.0))) * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.6))
	view["hero"]["lit"] = 0.4 * su * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.2))
	view["hero"]["lit_col"] = CYAN
	var tremble := su * float(ab < 0.0)
	body["off"] = Vector2(roundf(sin(t * 53.0) * (1.0 + tremble)) * float(tremble > 0.05), 0.0)
	# 空の大時計: 針がすべて逆回転（時計と反対回り）でだんだん速く巻き戻り、12時でぴたりと重なる → 砕ける
	var on := RBMHeroFx.ramp(t, TP.sky, TP.sky + 0.6)
	var k12 := RBMHeroFx.ramp(t, TP.sky, TP.twelve)
	var shat := RBMHeroFx.ramp(ab, 0.0, 0.55)
	var sc := Vector2(390, 70) + Vector2(0, 50.0 * (1.0 - on))
	if on > 0.0 and shat < 1.0:
		# 角度が減っていく＝反時計回り。k12² で加速し、k12=1 でちょうど12時（一周の整数倍）に着く
		var rew := k12 * k12
		show_dial(sky, sc, 140.0, DARK_BRASS.merged({"squash": 0.82, "hour": 4.4 * (1.0 - rew) - TAU * rew, "minute": -TAU * 5.0 * rew, "second": -TAU * 14.0 * rew, "hot_mark": 0.0, "hot_col": Vector3(1., .3, .38), "hot": k12 * k12,
			"glow": 0.25 + 0.6 * k12, "glow_col": Vector3(.5, .92, 1.), "crack": RBMHeroFx.ramp(t, TP.twelve - 0.6, TP.twelve), "crack_at": Vector2(0.0, 0.1), "shatter": shat, "fade": 0.85 * on, "dark": 0.45}))
	else:
		sky.visible = false
	if ab < 0.0:
		inward(b_glow, HOME + Vector2(0, -60), t, 40, 15, 10.0, 160.0, 1.6, Color(CYAN, 0.9), RBMHeroFx.ramp(t, TP.twelve - 0.7, TP.twelve), 2.2)
		view["shake"] += Vector2(sin(t * 37.0), 0.0) * 2.0 * su * su
	# 12時: 鐘・大時計と給仕長が同時に砕ける
	if ab >= 0.0:
		set_post({"flash": 0.3 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.16)), "flash_col": Vector3(.85, .97, 1.0), "chroma": 0.005 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.3))})
		view["hero"]["flash"] = 0.8 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.25))
		view["hero"]["flash_col"] = Color("#e6fcff")
		glass_shards(b_front, sc, ab, 1.9, 56, 61, 520.0, 8.0, Color(CREAM, 0.9), Color("#7a8a90", 0.9), 300.0, PI * 0.5, PI * 1.3)
		glass_shards(b_front, sc, ab, 1.8, 26, 63, 460.0, 6.0, BRASS, BRASS_D, 320.0, PI * 0.5, PI * 1.3)
		glass_shards(b_glow, HOME + Vector2(0, -60), ab, 1.2, 30, 65, 420.0, 4.0, Color(CYAN, 0.9), Color(TEAL, 0.6), 200.0)
		glass_shards(b_glow, HOME + Vector2(0, -60), ab, 1.2, 20, 67, 380.0, 4.0, Color("#ffb0b8", 0.9), Color(CRIMSON, 0.6), 200.0)
		view["shake"] += hit_shake(ab, 18.0, 65.0, 0.7)
	var ba := ab + 0.08
	var bf := 1.0 - RBMHeroFx.ramp(ab, 0.3, 0.75)
	blast.visible = ab >= 0.0 and bf > 0.0
	if blast.visible:
		var bc := HOME + Vector2(0, -60)
		show_blast(blast, blobs(bc, ba, 26, 27, 200.0, 130.0, 60.0, 80.0, .5, 0.0, 7.5), ba, {"flow": ba * .25, "cool": .05 + RBMHeroFx.ramp(ba, .2, .9) * .2, "erode": RBMHeroFx.ramp(ba, .25, .8), "fade": bf, "erode_noise": .4,
			"polar": 0.6, "detail": .5, "radial_heat": .45, "heat_center": w(bc), "heat_radius": 220.0 * RBMHeroFx.burst(ba, 7.5), "erode_radial": 140.0, "tone_cap": .98})
	# 体はガラスの粒になってほどける
	body["dissolve"] = smoothstep(TP.twelve, TP.gone - 0.05, t)
	body["rise"] = 0.95
	body["block"] = 3.0
	body["edge"] = Color(CYAN, 0.95)
	body["shadow"] = 1.0 - body["dissolve"]
	embers(b_glow, Rect2(-20, 0, 680, 300), t, 50, 69, -50.0, Color(CREAM, 0.7), RBMHeroFx.env(ab, 0.4, 0.9, 1.8, 2.4), 2.0, 14.0)
	# ひびの入った黒い懐中時計が残る
	remain_watch_upright(t, TP.remain, 0.4)
	b_shaft.commit(); b_glow.commit(); b_front.commit(); b_chain.commit()
