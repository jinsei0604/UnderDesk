extends SceneTree

## 使い捨て: 発見した白ブロック（screen x~370-395, y~200-232）を
## 高倍率(16x)で全7フレーム比較する。周辺の背景美術がどんな要素かも
## 分かるよう少し広めにcropする。

const DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const OUT := "res://tools/_ui_pass_shots/out/hair_check/review/"
const LABELS := ["A", "AB", "B", "BC", "C", "D", "E"]
const CROP := Rect2i(360, 190, 60, 60)
const ZOOM := 16

func _init() -> void:
	var w := CROP.size.x * ZOOM
	var h := CROP.size.y * ZOOM
	var gap := 4
	var strip := Image.create(w * LABELS.size() + gap * (LABELS.size() - 1), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.6, 0.9, 1.0))
	for i in range(LABELS.size()):
		var img := _load(DIR + "frame_%s.png" % LABELS[i])
		var cropped := img.get_region(CROP)
		cropped.resize(w, h, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(cropped, Rect2i(0, 0, w, h), Vector2i(i * (w + gap), 0))
	strip.save_png(ProjectSettings.globalize_path(OUT + "gap_bright_patch_strip.png"))
	print("saved gap_bright_patch_strip.png (order: %s)" % [LABELS])
	quit()

func _load(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
