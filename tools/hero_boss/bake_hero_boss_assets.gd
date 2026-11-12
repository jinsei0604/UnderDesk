extends SceneTree
## ヒーロー（hero_boss）の素材を、正式モーション（assets_bossmaker/battle/hero_boss/motion/cels.png・exposures.json）から作る。
## 1. 立ち絵の12ポーズ（frames/00〜11.png・design.png・frames.json）: 覚醒前は normal、覚醒後は omega のコマを、足元をそろえて置く。
##    戦闘の汎用の本体表示（rbm_character_visual.gd）が使う。体の高さ90ドットを180px（2倍）で表示する。
## 3. 覚醒後の撃破のコマ（hero_boss_awakened/defeat/<コマ名>.png）: 撃破の本体を、共通の消え方（四角い粒）がそのまま効く1枚ずつの絵にする。
##    覚醒後の立ち姿（omega）の足元を立ち絵と同じ位置にそろえ、ほかのコマは正式モーションの中の位置関係のまま置く。
## 2. オーラの距離（aura_fields/<コマ名>.res）: 全部のコマについて、輪郭からの距離と一番近い体の点を焼く（RBMHeroDarkAura.compute_field）。
##    戦闘中に計算しないための事前の焼き込み。
## 使い方: godot --headless --path . --script res://tools/hero_boss/bake_hero_boss_assets.gd
## 絵そのもの（コマの画素）は変えない。モーションを差し替えたら、これを流し直してから --import する。

const ROOT := "res://assets_bossmaker/battle/"
const MOTION := ROOT + "hero_boss/motion/"
const CANVAS := Vector2i(96, 104)
const FOOT := Vector2i(48, 102)
const BODY_HEIGHT := 90
const FORMS := {"hero_boss": "normal", "hero_boss_awakened": "omega"}
## 覚醒後の撃破のコマ（rbm_hero_boss_defeat_awakened.gd の DEFEAT_CANVAS・DEFEAT_FOOT と同じ値）
const DEFEAT_CELS := ["omega", "release2", "release3", "release1"]
const DEFEAT_CANVAS := Vector2i(112, 100)
const DEFEAT_FOOT := Vector2i(56, 98)

func _init() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(MOTION + "cels.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOTION + "exposures.json"))
	var rects: Dictionary = data["rects"]
	var failures := 0
	for asset_id in FORMS:
		failures += _stance(sheet, rects, asset_id, str(FORMS[asset_id]))
	failures += _defeat_cels(sheet, data)
	var bytes := sheet.get_data()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "hero_boss/aura_fields"))
	for cel in rects:
		var r: Array = rects[cel]
		var image := RBMHeroDarkAura.compute_field(bytes, sheet.get_width(), int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var path := RBMHeroDarkAura.field_path(str(cel))
		var err := ResourceSaver.save(ImageTexture.create_from_image(image), path)
		var back := load(path) as Texture2D
		if err != OK or back == null or back.get_image().get_data() != image.get_data():
			push_error("aura field not saved exactly: " + path)
			failures += 1
	print("HERO_BOSS_ASSETS cels=%d failures=%d" % [rects.size(), failures])
	quit(1 if failures > 0 else 0)

func _defeat_cels(sheet: Image, data: Dictionary) -> int:
	var rects: Dictionary = data["rects"]
	var top_left := {}
	for seq: Dictionary in data["sequences"]:
		for e: Dictionary in seq["exposures"]:
			if not top_left.has(str(e["cel"])):
				top_left[str(e["cel"])] = Vector2i(int(e["world_top_left"][0]), int(e["world_top_left"][1]))
	var o: Array = rects["omega"]
	# 立ち絵と同じ足元（コマの下端の中央）を基準にする
	var anchor: Vector2i = top_left["omega"] + Vector2i(roundi(float(o[2]) * 0.5), int(o[3]))
	var dir := ROOT + "hero_boss_awakened/defeat/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var failures := 0
	for cel in DEFEAT_CELS:
		var r: Array = rects[cel]
		var size := Vector2i(int(r[2]), int(r[3]))
		var at: Vector2i = top_left[cel] - anchor + DEFEAT_FOOT
		if at.x < 0 or at.y < 0 or at.x + size.x > DEFEAT_CANVAS.x or at.y + size.y > DEFEAT_CANVAS.y:
			push_error("defeat cel out of canvas: " + cel)
			failures += 1
			continue
		var canvas := Image.create_empty(DEFEAT_CANVAS.x, DEFEAT_CANVAS.y, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(sheet.get_region(Rect2i(int(r[0]), int(r[1]), size.x, size.y)), Rect2i(Vector2i.ZERO, size), at)
		if canvas.save_png(ProjectSettings.globalize_path(dir + cel + ".png")) != OK:
			failures += 1
	return failures

func _stance(sheet: Image, rects: Dictionary, asset_id: String, cel: String) -> int:
	var r: Array = rects[cel]
	var size := Vector2i(int(r[2]), int(r[3]))
	var body := sheet.get_region(Rect2i(int(r[0]), int(r[1]), size.x, size.y))
	var top_left := FOOT - Vector2i(roundi(size.x * 0.5), size.y)
	var canvas := Image.create_empty(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(body, Rect2i(Vector2i.ZERO, size), top_left)
	var dir := ROOT + asset_id + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "frames"))
	var failures := 0
	for i in range(12):
		if canvas.save_png(ProjectSettings.globalize_path(dir + "frames/%02d.png" % i)) != OK:
			failures += 1
	if canvas.save_png(ProjectSettings.globalize_path(dir + "design.png")) != OK:
		failures += 1
	var poses := []
	for i in range(12):
		poses.append({"index": i, "bbox": [top_left.x, top_left.y, size.x, size.y]})
	var meta := {"source": "assets_bossmaker/battle/hero_boss/motion/cels.png#" + cel, "canvas": [CANVAS.x, CANVAS.y], "foot": [FOOT.x, FOOT.y], "body_height": BODY_HEIGHT, "poses": poses}
	var f := FileAccess.open(ProjectSettings.globalize_path(dir + "frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return failures
