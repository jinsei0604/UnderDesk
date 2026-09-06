extends SceneTree

const DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const OUT := "res://tools/_ui_pass_shots/out/hair_check/review/"
const LABELS := ["A", "AD", "D", "AD", "A"]
const TORSO_CROP := Rect2i(150, 165, 360, 460)
const ZOOM := 3

func _init() -> void:
	var w := TORSO_CROP.size.x * ZOOM
	var h := TORSO_CROP.size.y * ZOOM
	var gap := 6
	var strip := Image.create(w * LABELS.size() + gap * (LABELS.size() - 1), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.6, 0.9, 1.0))
	for i in range(LABELS.size()):
		var img := _load(DIR + "frame_%s.png" % LABELS[i])
		var cropped := img.get_region(TORSO_CROP)
		cropped.resize(w, h, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(cropped, Rect2i(0, 0, w, h), Vector2i(i * (w + gap), 0))
	strip.save_png(ProjectSettings.globalize_path(OUT + "torso_A_AD_D_AD_A.png"))
	print("saved torso_A_AD_D_AD_A.png (order: %s)" % [LABELS])
	quit()

func _load(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
