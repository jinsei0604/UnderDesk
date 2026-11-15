extends SceneTree
## 熔鉱炉の番人／噴界炉の巨神（lava）の素材を、Codex のキーポーズ（assets_bossmaker/battle/lava/motion/<技>/<番号>.png）から作る。
## 1. 立ち絵の12ポーズ（lava・lava_awakened の frames/00〜11.png・design.png・frames.json）: 覚醒前＝awaken の1枚目、
##    覚醒後＝awaken の5枚目（RBMLavaMotion.STANCE）を、RBMLavaMotion.STANCE_CROP の範囲で切り出して12枚同じに置く。
##    戦闘の汎用の本体表示（rbm_character_visual.gd）が使う。体の高さ（絵の画素）を2倍で表示する（RBMVisualAssets.HEIGHTS）。
## 2. 覚醒後の常時オーラの距離（aura_fields/<技>_<番号>.res）: RBMLavaMotion.AURA_POSES の各ポーズ（RBMHeroDarkAura.compute_field）。
## 3. エフェクトを付ける場所（motion/anchors.json）: 技・ポーズごとに front（いちばん左の点）・top（いちばん上の点）・
##    center（重心）・mark（炉心の明るい黄色〜白の画素の重心）を絵の画素で測る。
## 使い方: godot --headless --path . --script res://tools/lava/bake_lava_assets.gd → --import
## 絵そのもの（キーポーズの画素）は変えない。

const BATTLE := "res://assets_bossmaker/battle/"

func _init() -> void:
	var failures := 0
	failures += _stance("lava", "pre")
	failures += _stance("lava_awakened", "post")
	failures += _fields()
	failures += _anchors()
	print("LAVA_ASSETS failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func _image(move: String, n: int) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(RBMLavaMotion.pose_path(move, n)))
	img.convert(Image.FORMAT_RGBA8)
	return img

func _stance(asset_id: String, form: String) -> int:
	var s: Array = RBMLavaMotion.STANCE[form]
	var move := str(s[0])
	var n := int(s[1])
	var crop := RBMLavaMotion.STANCE_CROP
	var canvas := _image(move, n).get_region(crop)
	var dir := BATTLE + asset_id + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "frames"))
	var failures := 0
	for i in range(12):
		if canvas.save_png(ProjectSettings.globalize_path(dir + "frames/%02d.png" % i)) != OK:
			failures += 1
	if canvas.save_png(ProjectSettings.globalize_path(dir + "design.png")) != OK:
		failures += 1
	var b := RBMLavaMotion.bbox(move, n)
	var box := [int(b[0]) - crop.position.x, int(b[1]) - crop.position.y, int(b[2]) - int(b[0]), int(b[3]) - int(b[1])]
	var poses := []
	for i in range(12):
		poses.append({"index": i, "bbox": box})
	var foot := Vector2i(RBMLavaMotion.ORIGIN) - crop.position
	var meta := {"source": RBMLavaMotion.pose_path(move, n), "canvas": [crop.size.x, crop.size.y], "foot": [foot.x, foot.y], "body_height": box[3], "poses": poses}
	var f := FileAccess.open(ProjectSettings.globalize_path(dir + "frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return failures

func _fields() -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RBMLavaMotion.FIELD_ROOT))
	var failures := 0
	for move in RBMLavaMotion.AURA_POSES:
		for n in RBMLavaMotion.AURA_POSES[move]:
			var img := _image(move, n)
			var b := RBMLavaMotion.bbox(move, n)
			var field := RBMHeroDarkAura.compute_field(img.get_data(), img.get_width(), int(b[0]), int(b[1]), int(b[2]) - int(b[0]), int(b[3]) - int(b[1]))
			var path := RBMLavaMotion.field_path(move, n)
			var err := ResourceSaver.save(ImageTexture.create_from_image(field), path)
			var back := load(path) as Texture2D
			if err != OK or back == null or back.get_image().get_data() != field.get_data():
				push_error("aura field not saved exactly: " + path)
				failures += 1
	return failures

func _anchors() -> int:
	var out := {}
	for move in RBMLavaMotion.MOVES:
		out[move] = []
		for n in range(1, RBMLavaMotion.pose_count(move) + 1):
			var img := _image(move, n)
			var front := Vector2(9999, 0)
			var top := Vector2(0, 9999)
			var sum := Vector2.ZERO
			var count := 0
			var mark_sum := Vector2.ZERO
			var mark_n := 0
			for y in range(img.get_height()):
				for x in range(img.get_width()):
					var c := img.get_pixel(x, y)
					if c.a < 0.5:
						continue
					sum += Vector2(x, y)
					count += 1
					if x < front.x:
						front = Vector2(x, y)
					if y < top.y:
						top = Vector2(x, y)
					# 炉心（明るい黄色〜白。試作 analyze_poses.gd と同じ）
					if c.r > 0.95 and c.g > 0.75 and c.b > 0.35:
						mark_sum += Vector2(x, y)
						mark_n += 1
			out[move].append({"pose": n, "front": [front.x, front.y], "top": [top.x, top.y], "center": [roundf(sum.x / count), roundf(sum.y / count)],
				"mark": [roundf(mark_sum.x / maxf(mark_n, 1)), roundf(mark_sum.y / maxf(mark_n, 1))]})
	var f := FileAccess.open(ProjectSettings.globalize_path(RBMLavaMotion.ANCHORS_PATH), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return 0
