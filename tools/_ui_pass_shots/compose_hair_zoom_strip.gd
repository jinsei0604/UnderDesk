extends SceneTree

## 実GPUスクリーンショット(frame_A.png等、実背景・実0.50倍スケール)から
## 髪・帽子周辺を拡大したコンタクトシートを作る。

const DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const OUT := "res://tools/_ui_pass_shots/out/hair_check/review/"
const LABELS := ["A", "AB", "B", "BC", "C", "D", "E"]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# 実測head bbox（native: top_y=72, 左境界x:341-511, 右境界x:512-613
	# @y=72-372）から逆算した実画面px crop（screen = (76,19) + native*0.5）。
	# 境界線は斜めに動くため、全yで境界を確実に含む広めの帯にする。
	_build_strip(Rect2i(220, 40, 190, 195), "head_overview", 5)
	# 頭頂部・帽子の縁。
	_build_strip(Rect2i(270, 45, 95, 55), "top_of_head", 8)
	# 左髪外周（画面向かって左側、窓側）。native x:300-560を含む帯。
	_build_strip(Rect2i(226, 49, 130, 160), "left_hair_outline", 6)
	# 右髪外周（画面向かって右側、顔の反対）。native x:490-650を含む帯。
	_build_strip(Rect2i(321, 49, 80, 160), "right_hair_outline", 6)
	# 顔横の髪。
	_build_strip(Rect2i(240, 90, 140, 85), "face_side_hair", 7)
	# 肩に重なる毛先。
	_build_strip(Rect2i(230, 165, 160, 70), "shoulder_hair_tips", 7)
	# 差分診断（_scratch_diff_screenshots.gd）で実際に画素値が変化していた
	# 実画面座標(321-335,193-201)を中心に、背景の明るい暖色照明が見え
	# 隠れる疑いのある領域を高倍率で直接確認。
	_build_strip(Rect2i(290, 170, 90, 70), "arm_collar_boundary_bright_bg", 14)

	print("hair zoom strips built")
	quit()

func _build_strip(crop: Rect2i, name: String, zoom: int) -> void:
	var w := crop.size.x * zoom
	var h := crop.size.y * zoom
	var gap := 4
	var strip := Image.create(w * LABELS.size() + gap * (LABELS.size() - 1), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.6, 0.9, 1.0))
	for i in range(LABELS.size()):
		var img := _load(DIR + "frame_%s.png" % LABELS[i])
		if img == null:
			print("MISSING frame_%s.png" % LABELS[i])
			continue
		var cropped := img.get_region(crop)
		cropped.resize(w, h, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(cropped, Rect2i(0, 0, w, h), Vector2i(i * (w + gap), 0))
	strip.save_png(ProjectSettings.globalize_path(OUT + name + "_strip.png"))
	print("saved %s_strip.png (order: %s)" % [name, LABELS])

func _load(path: String) -> Image:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	return img
