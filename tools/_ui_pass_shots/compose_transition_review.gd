extends SceneTree

## 実GPUで撮影したtransitions/*_before.png / *_after.pngペアを、
## キャラクター全身を含む領域でクロップし、①横並び②差分オーバーレイ
## （赤=beforeにあってafterに無い、青=afterにあってbeforeに無い、
## 明るさ閾値ベース）を1枚にまとめる。実表示スケール(0.5倍)そのままの
## ピクセルで比較するため、これが実際に画面で見える「ジャンプ」の
## 最終判定材料になる。

const DIR := "res://tools/_ui_pass_shots/out/transitions/"
const OUT := "res://tools/_ui_pass_shots/out/transitions/review/"

const PAIRS := ["a_to_next", "ab1_to_next", "b1_to_next", "bc1_to_next", "c_to_next", "bc2_to_next", "b2_to_next", "ab2_to_next", "d_a", "d_a_return", "e_a", "e_a_return"]
const CROP := Rect2i(20, 60, 500, 660)  # キャラクター全身を含む領域(実画面px)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for pair in PAIRS:
		_process_pair(pair)
	print("done")
	quit()

func _process_pair(pair: String) -> void:
	var before_name := ""
	var after_name := ""
	match pair:
		"d_a":
			before_name = "d_before_a"
			after_name = "d_after_d"
		"d_a_return":
			before_name = "d_before_a_return"
			after_name = "d_after_a_return"
		"e_a":
			before_name = "e_before_a"
			after_name = "e_after_e"
		"e_a_return":
			before_name = "e_before_a_return"
			after_name = "e_after_a_return"
		_:
			before_name = "%s_before" % pair
			after_name = "%s_after" % pair

	var before := _load(DIR + before_name + ".png")
	var after := _load(DIR + after_name + ".png")
	if before == null or after == null:
		print("MISSING for %s" % pair)
		return

	var b_crop := before.get_region(CROP)
	var a_crop := after.get_region(CROP)

	var zoom := 2
	var w := CROP.size.x * zoom
	var h := CROP.size.y * zoom
	var gap := 6

	var b_scaled := b_crop.duplicate()
	b_scaled.resize(w, h, Image.INTERPOLATE_NEAREST)
	var a_scaled := a_crop.duplicate()
	a_scaled.resize(w, h, Image.INTERPOLATE_NEAREST)

	# 差分オーバーレイ: before(グレースケール) + 変化した画素を強調色で。
	var diff := Image.create(CROP.size.x, CROP.size.y, false, Image.FORMAT_RGBA8)
	var changed := 0
	for y in range(CROP.size.y):
		for x in range(CROP.size.x):
			var pb := b_crop.get_pixel(x, y)
			var pa := a_crop.get_pixel(x, y)
			var delta: float = absf(pb.r - pa.r) + absf(pb.g - pa.g) + absf(pb.b - pa.b)
			if delta > 0.06:
				changed += 1
				diff.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))  # magenta = changed pixel
			else:
				var g: float = (pb.r + pb.g + pb.b) / 3.0
				diff.set_pixel(x, y, Color(g, g, g, 1.0))
	var diff_scaled := diff.duplicate()
	diff_scaled.resize(w, h, Image.INTERPOLATE_NEAREST)

	var strip := Image.create(w * 3 + gap * 2, h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.6, 0.9, 1.0))
	strip.blit_rect(b_scaled, Rect2i(0, 0, w, h), Vector2i(0, 0))
	strip.blit_rect(a_scaled, Rect2i(0, 0, w, h), Vector2i(w + gap, 0))
	strip.blit_rect(diff_scaled, Rect2i(0, 0, w, h), Vector2i((w + gap) * 2, 0))
	strip.save_png(ProjectSettings.globalize_path(OUT + pair + "_review.png"))
	print("%s: changed_px=%d / %d (%.2f%%) -> %s_review.png (order: before, after, diff[magenta=changed])" % [
		pair, changed, CROP.size.x * CROP.size.y, 100.0 * changed / (CROP.size.x * CROP.size.y), pair
	])

func _load(path: String) -> Image:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
