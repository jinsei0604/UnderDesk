extends RefCounted
## 爆炎（blast.gdshader）を、元の層へ直接描いた時と、半分の解像度で描いて2倍に拡大した時（RBMHeroFxHalfRes、2026-11-19 の性能の修正）の
## 画素が同じかを、実際の描画で確かめる。爆炎の値は採用済みの技（全体技 array・覚醒後全体 press・覚醒 breach）の組み合わせ。
## 起動: godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_blast_half_res_gpu.gd --output=<dir> [--1080]
## 揺れで戦場がずれた時（奇数の画素）も確かめる。違う画素があれば、両方の画像を保存する。
var _gpu_verification_completed := false
var report: Dictionary = {"cases": [], "errors": []}

const CASES := [
	{"name": "array", "pa": "FIRE", "pb": "PLASMA", "quad": {"amp": 34., "k": .05, "seed": 4.4, "glow": .55, "glow_col": Vector3(1., .55, .18), "glow_r": 50.},
		"blobs": [Vector2(436, 178), 48, 8, 460.0, 200.0, 104.0, 150.0, .62, 0.0, 6.2], "show": {"lump_scale": .62, "tone_cap": .74, "erode_noise": .4, "polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .36, "erode_radial": 220.0}},
	{"name": "press_rim", "pa": "DARK", "pb": "VOID", "quad": {"amp": 36., "k": .05, "seed": 7.3, "glow": .55, "glow_col": Vector3(.95, .08, .18), "glow_r": 40., "rim_mode": 1., "rim_w": 18.},
		"blobs": [Vector2(300, 250), 30, 31, 300.0, 120.0, 80.0, 60.0, .72, .3, 8.0], "show": {"lump_scale": .62, "tone_cap": .86, "erode_noise": .4}},
	{"name": "breach", "pa": "DARK", "pb": "VOID", "quad": {"amp": 40., "k": .045, "seed": 3.3, "glow": 1.0, "glow_col": Vector3(.95, .08, .18), "glow_r": 64., "rim_mode": 1., "rim_w": 22.},
		"blobs": [Vector2(390, 200), 24, 17, 120.0, 90.0, 60.0, 80.0, .6, 0.0, 7.0], "show": {"erode_noise": .4, "tone_cap": .9}},
]
const AGES := [0.06, 0.25, 0.6, 0.95]
const SHAKES := [Vector2.ZERO, Vector2(2, 0), Vector2(-4, 2)]

func run_gpu_verification(tree: SceneTree, directory: String) -> int:
	DirAccess.make_dir_recursive_absolute(directory)
	tree.root.mode = Window.MODE_WINDOWED
	tree.root.size = Vector2i(1280, 720)
	if "--1080" in OS.get_cmdline_user_args():
		tree.root.mode = Window.MODE_FULLSCREEN
		tree.root.size = Vector2i(1920, 1080)
	tree.root.content_scale_size = Vector2i(1280, 720)
	for i in range(4):
		await tree.process_frame
	report.window = [tree.root.size.x, tree.root.size.y]
	# 戦場と同じ形: 1280×720 の座標の中に、2倍の論理ドットの世界を置く（本番の presentation と同じ）
	var stage := Node2D.new()
	tree.root.add_child(stage)
	var world := Node2D.new()
	world.scale = Vector2(2, 2)
	world.position = Vector2(-0, -2)
	stage.add_child(world)
	var back := Node2D.new()
	world.add_child(back)
	var fx := RBMHeroFxBase.new()
	world.add_child(fx)
	fx.view = {"rings": []}
	var total := 0
	var worst := 0
	var worst_strong := 0
	for c in CASES:
		var consts: Dictionary = (RBMHeroFx as Script).get_script_constant_map()
		RBMHeroFxHalfRes.enabled = false
		var direct := fx.blast_quad(back, consts[c.pa], consts[c.pb], c.quad)
		RBMHeroFxHalfRes.enabled = true
		var half := fx.blast_quad(back, consts[c.pa], consts[c.pb], c.quad)
		if direct.get_parent() != back or half.get_parent() == back:
			report.errors.append("%s: the half-resolution path was not taken" % c.name)
		for age in AGES:
			for shake in SHAKES:
				stage.position = shake
				var b: Array = c.blobs
				var data := fx.blobs(b[0], float(age), int(b[1]), int(b[2]), float(b[3]), float(b[4]), float(b[5]), float(b[6]), float(b[7]), float(b[8]), float(b[9]))
				var params := {"flow": float(age) * .22, "cool": RBMHeroFx.ramp(float(age), .2, 1.1) * .34, "erode": RBMHeroFx.ramp(float(age), .36, 1.02), "fade": 1.0 - RBMHeroFx.ramp(float(age), .7, 1.0), "heat_center": fx.w(b[0]), "heat_radius": 300.0 * RBMHeroFx.burst(float(age), 6.2)}
				params.merge(c.show, true)
				fx.show_blast(direct, data, float(age), params)
				fx.show_blast(half, data, float(age), params)
				half.visible = false
				var a := await _grab(tree)
				direct.visible = false
				half.visible = true
				var h := await _grab(tree)
				half.visible = false
				var d := _diff(a, h)
				total += int(d.pixels)
				worst = maxi(worst, int(d.max))
				worst_strong = maxi(worst_strong, int(d.strong))
				report.cases.append({"case": c.name, "age": age, "shake": [shake.x, shake.y], "differing_pixels": d.pixels, "max_channel_diff": d.max, "strong_pixels": d.strong})
				print("BLAST_HALF ", c.name, " age=", age, " shake=", shake, " diff_pixels=", d.pixels, " max=", d.max, " strong=", d.strong)
				if int(d.max) > 2:
					a.save_png(directory.path_join("%s_%.2f_%d_%d_direct.png" % [c.name, age, shake.x, shake.y]))
					h.save_png(directory.path_join("%s_%.2f_%d_%d_half.png" % [c.name, age, shake.x, shake.y]))
	report.total_differing_pixels = total
	report.worst_channel_diff = worst
	# 合格: ほとんどの画素の差は 1/255（8bit の中間の描画先の丸め）。色の段の境目で浮動小数の丸めにより1ドット（2×2画素、1080 では 3×3 まで）が
	# 隣の色に変わることがある。1コマにつき 3×3×4 画素（4ドット）以下なら合格（2026-11-19 実測は 4画素＝1ドット）
	report.worst_strong_pixels = worst_strong
	report.passed = report.errors.is_empty() and worst_strong <= 36
	FileAccess.open(directory.path_join("blast-half-res-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	stage.queue_free()
	_gpu_verification_completed = true
	print("BLAST_HALF_DONE ", report.passed, " total_diff_pixels=", total, " worst=", worst, " worst_strong_pixels=", worst_strong, " window=", report.window)
	return 0 if report.passed else 1

func _grab(tree: SceneTree) -> Image:
	for i in range(2):
		await tree.process_frame
	await RenderingServer.frame_post_draw
	return tree.root.get_texture().get_image()

func _diff(a: Image, b: Image) -> Dictionary:
	var da := a.get_data()
	var db := b.get_data()
	var pixels := 0
	var worst := 0
	var strong := 0
	var stride := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	for i in range(0, mini(da.size(), db.size()), stride):
		var d := 0
		for k in range(3):
			d = maxi(d, absi(int(da[i + k]) - int(db[i + k])))
		if d > 0:
			pixels += 1
			worst = maxi(worst, d)
		if d > 2:
			strong += 1
	return {"pixels": pixels, "max": worst, "strong": strong}
