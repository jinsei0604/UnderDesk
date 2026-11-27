extends Node2D
## 竜の覚醒に重ねる「黒い雷」（2026-11-25 試作 → 2026-11-26 ユーザー承認。表示専用。戦闘の状態・乱数には触れない）。
## 今の覚醒（rbm_dragon_awakening.gd: 黒い炎の殻 → 咆哮 → 暗転して目だけ → 解放）の流れはそのまま、上に重ねる:
## 殻が育つ間、空から黒い稲妻が殻と戦場のあちこちへ落ち始め、だんだん速く・多くなる → 暗転の直前に巨大な黒い雷が殻を貫く
## → 暗転の中で目の周りに紅い放電 → 解放の瞬間に黒い雷が竜から画面の端まで放射状に走る → 覚醒した体に残る放電。
## 黒い芯に紅い光（RBMDragonFxBase.black_bolt）。雷が落ちるたびに画面が一瞬暗く紅く沈む。

const REVEAL := 3.04
## 落ちる雷: [時刻, 落ちる先（"cocoon"=殻 / "ground"=地面）, 太さ, 大きさ（0=普通 1=大 2=巨大）]
const STRIKES := [
	[0.62, "cocoon", 1.8, 0], [0.86, "ground", 1.6, 0], [1.08, "cocoon", 2.0, 0], [1.30, "cocoon", 2.6, 1], [1.31, "ground", 1.8, 1],
	[1.50, "ground", 1.6, 0], [1.62, "ground", 1.6, 0], [1.74, "cocoon", 2.0, 0], [1.84, "ground", 1.6, 0], [1.93, "ground", 1.7, 0],
	[2.01, "cocoon", 2.0, 0], [2.07, "ground", 1.6, 0], [2.13, "ground", 1.8, 0], [2.20, "cocoon", 4.2, 2],
]

var fx: RBMDragonFxBase
var _world: Node2D
var _post: ColorRect
var _stage: Control
var b_glow: RBMHeroFxBatch
var b_core: RBMHeroFxBatch
var b_add: RBMHeroFxBatch

func setup(stage: Control) -> void:
	_stage = stage
	_world = Node2D.new()
	_world.scale = Vector2(2, 2)
	add_child(_world)
	fx = RBMDragonFxBase.new()
	_world.add_child(fx)
	fx.setup(_world, _world, [])
	b_glow = fx.batch(_world)
	b_core = fx.batch(_world, false)
	b_add = fx.batch(_world)
	_post = ColorRect.new()
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.position = Vector2(-32, -32)
	_post.size = stage.size + Vector2(64, 64)
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("post")
	_post.material = pm
	add_child(_post)

func _target(kind: String, i: int, home: Vector2) -> Vector2:
	if kind == "cocoon":
		return home + Vector2((RBMHeroFx.r(i, 3) - 0.5) * 50.0, -70.0 - 30.0 * RBMHeroFx.r(i, 4))
	# 地面: 戦場のあちこち（画面全体へ広げる）
	return Vector2(30.0 + 520.0 * RBMHeroFx.r(i, 5), 250.0 + 50.0 * RBMHeroFx.r(i, 6))

func advance(age: float, home_stage: Vector2, eye_stage: Vector2) -> void:
	if not is_instance_valid(_stage):
		return
	var home := home_stage * 0.5
	var eye := eye_stage * 0.5
	b_glow.reset()
	b_core.reset()
	b_add.reset()
	var post := {"flash": 0.0, "impact": 0.0, "vig": 0.0, "desat": 0.0, "chroma": 0.0}
	var flash_col := Color(0.3, 0.0, 0.05)
	# 空気が重くなる（周辺が紅黒く沈む）
	var mood := RBMHeroFx.ramp(age, 0.5, 2.1) * (1.0 - RBMHeroFx.ramp(age, REVEAL + 0.4, 4.6))
	post.vig = 0.55 * mood
	post.desat = 0.22 * mood
	for k in range(STRIKES.size()):
		var s: Array = STRIKES[k]
		var a: float = age - float(s[0])
		var life := 0.26 if int(s[3]) == 2 else 0.17
		if a < 0.0 or a > life:
			continue
		# 落ちた瞬間は太く明るく、その後は瞬きながら消える
		var power := 1.0 if a < 0.05 else (0.55 + 0.45 * float(int(age * 20.0) % 2)) * (1.0 - (a - 0.05) / (life - 0.05))
		var to := _target(str(s[1]), k, home)
		var from := Vector2(to.x + (RBMHeroFx.r(k, 7) - 0.5) * 160.0, -30.0)
		var big := int(s[3])
		fx.black_bolt(b_glow, b_core, from, to, k * 13 + 1, float(s[2]), power, Color("#ed274c"), 12 if big == 0 else 16, 0.2, true)
		if big >= 1:
			# 太い雷には何本か寄り添う
			for j in range(2 + big):
				var off := Vector2((RBMHeroFx.r(k * 5 + j, 8) - 0.5) * 120.0, 0)
				fx.black_bolt(b_glow, b_core, from + off, to + off * 0.25, k * 31 + j * 7, float(s[2]) * 0.45, power * 0.8, Color("#ed274c"), 10, 0.24, true)
		# 落ちた所: 紅い火花と光の輪
		fx.sparks(b_add, to, a, 0.3, 18 + 14 * big, k * 11 + 3, 140.0 + 80.0 * big, Color("#ff9a88"), Color("#ed274c"), -PI * 0.5, PI * 1.6, 200.0, 1.6)
		fx.circle_line(b_add, to + Vector2(0, 6), 6.0 + (40.0 + 40.0 * big) * RBMHeroFx.burst(a, 8.0), 1.6, Color("#ed274c", 0.8 * (1.0 - a / life)), 24, 0.32)
		if a < 0.04:
			post.flash = maxf(float(post.flash), 0.28 + 0.15 * big)
		if big >= 1 and a < 0.034:
			post.impact = 0.8
		post.chroma = maxf(float(post.chroma), 0.003 * power * (1 + big))
	# 暗転の中: 目の周りの紅い放電
	if age >= 2.32 and age < 2.68:
		var phase := int(floor(age * 12.0))
		for j in range(3):
			var th := RBMHeroFx.r(phase * 3 + j, 12) * TAU
			var a := eye + Vector2.from_angle(th) * 8.0
			var c := eye + Vector2.from_angle(th + 0.6) * (26.0 + 22.0 * RBMHeroFx.r(phase * 3 + j, 13))
			fx.black_bolt(b_glow, b_core, a, c, phase * 7 + j, 0.9, 0.9, Color("#ff2244"), 6, 0.35, false)
	# 解放: 竜から画面の端まで放射状に走る黒い雷（2回）
	for wave in range(2):
		var ra := age - (REVEAL + 0.16 * wave)
		if ra < 0.0 or ra > 0.34:
			continue
		var power := 1.0 if ra < 0.06 else (0.5 + 0.5 * float(int(age * 20.0) % 2)) * (1.0 - (ra - 0.06) / 0.28)
		var center := home + Vector2(0, -60)
		var n := 14 if wave == 0 else 9
		for j in range(n):
			var th := float(j) / n * TAU + (RBMHeroFx.r(j + wave * 20, 14) - 0.5) * 0.35 + wave * 0.2
			var reach := 520.0 * minf(1.0, ra / 0.05)
			fx.black_bolt(b_glow, b_core, center + Vector2.from_angle(th) * 24.0, center + Vector2.from_angle(th) * Vector2(reach, reach * 0.7), j * 17 + wave * 101, 2.6 - wave, power, Color("#ed274c"), 14, 0.16, true)
		if ra < 0.034:
			post.impact = 0.8
		if ra < 0.06:
			post.flash = maxf(float(post.flash), 0.4)
	# 覚醒した体に残る放電
	if age >= REVEAL + 0.34 and age < 4.5:
		var fade := 1.0 - RBMHeroFx.ramp(age, 4.0, 4.5)
		var phase := int(floor(age * 7.0))
		for j in range(2):
			var p := home + Vector2((RBMHeroFx.r(phase * 2 + j, 15) - 0.5) * 120.0, -10.0 - 100.0 * RBMHeroFx.r(phase * 2 + j, 16))
			var q := p + Vector2((RBMHeroFx.r(phase * 2 + j, 17) - 0.5) * 50.0, (RBMHeroFx.r(phase * 2 + j, 18) - 0.5) * 40.0)
			fx.black_bolt(b_glow, b_core, p, q, phase * 9 + j, 0.9, fade * (1.0 - fmod(age * 7.0, 1.0)), Color("#ed274c"), 6, 0.35, false)
	b_glow.commit()
	b_core.commit()
	b_add.commit()
	# 効果が無い間は画面全体の処理を消す（絵は同じ。rbm_dragon_attack_host.gd の post_active と同じ考え方）
	_post.visible = float(post.flash) > 0.0 or float(post.impact) > 0.0 or float(post.vig) > 0.0 or float(post.desat) > 0.0 or float(post.chroma) > 0.0
	if not _post.visible:
		return
	var pm := _post.material as ShaderMaterial
	pm.set_shader_parameter("time", age)
	pm.set_shader_parameter("flash", float(post.flash))
	pm.set_shader_parameter("flash_col", flash_col)
	pm.set_shader_parameter("impact", float(post.impact))
	pm.set_shader_parameter("impact_hi", Vector3(1.0, 0.6, 0.55))
	pm.set_shader_parameter("impact_lo", Vector3(0.02, 0.01, 0.03))
	pm.set_shader_parameter("impact_cut", 0.4)
	pm.set_shader_parameter("vig", float(post.vig))
	pm.set_shader_parameter("vig_col", Vector3(0.08, 0.0, 0.02))
	pm.set_shader_parameter("desat", float(post.desat))
	pm.set_shader_parameter("chroma", float(post.chroma))
	pm.set_shader_parameter("ring_count", 0)
