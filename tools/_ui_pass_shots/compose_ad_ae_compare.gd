extends SceneTree

## A→D、A→Eのジャンプが実際どう見えるかを実GPUスクリーンショット
## （frame_A.png/frame_D.png/frame_E.png、実背景・実0.50倍スケール）で
## 目視確認するための比較画像を作る。
## ①A/D/Eの胴体全体を並べた比較 ②A基準の差分をmagentaで可視化した
## オーバーレイ（どの範囲がどれだけズレて見えるかを直接視認する）。

const DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const OUT := "res://tools/_ui_pass_shots/out/hair_check/review/"

# 胴体全体を含む実画面crop（native y:300-1200 -> screen y:169-619、
# native x:150-850 -> screen x:151-501）。
const TORSO_CROP := Rect2i(150, 165, 360, 460)
const ZOOM := 3

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_side_by_side("A", "D")
	_side_by_side("A", "E")
	_diff_overlay("A", "D")
	_diff_overlay("A", "E")
	print("A/D/E compare images built")
	quit()

func _side_by_side(la: String, lb: String) -> void:
	var a := _load(DIR + "frame_%s.png" % la)
	var b := _load(DIR + "frame_%s.png" % lb)
	var w := TORSO_CROP.size.x * ZOOM
	var h := TORSO_CROP.size.y * ZOOM
	var gap := 6
	var strip := Image.create(w * 2 + gap, h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.6, 0.9, 1.0))
	var ca := a.get_region(TORSO_CROP)
	ca.resize(w, h, Image.INTERPOLATE_NEAREST)
	strip.blit_rect(ca, Rect2i(0, 0, w, h), Vector2i(0, 0))
	var cb := b.get_region(TORSO_CROP)
	cb.resize(w, h, Image.INTERPOLATE_NEAREST)
	strip.blit_rect(cb, Rect2i(0, 0, w, h), Vector2i(w + gap, 0))
	strip.save_png(ProjectSettings.globalize_path(OUT + "torso_%s_vs_%s.png" % [la, lb]))
	print("saved torso_%s_vs_%s.png (left=%s, right=%s)" % [la, lb, la, lb])

func _diff_overlay(la: String, lb: String) -> void:
	var a := _load(DIR + "frame_%s.png" % la)
	var b := _load(DIR + "frame_%s.png" % lb)
	var ca := a.get_region(TORSO_CROP)
	var cb := b.get_region(TORSO_CROP)
	var w := TORSO_CROP.size.x
	var h := TORSO_CROP.size.y
	var diff := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var pa := ca.get_pixel(x, y)
			var pb := cb.get_pixel(x, y)
			var d: float = absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			if d > 0.08:
				diff.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))
			else:
				# 背景として元画像(a)を薄く表示。
				diff.set_pixel(x, y, Color(pa.r * 0.4, pa.g * 0.4, pa.b * 0.4, 1.0))
	diff.resize(w * ZOOM, h * ZOOM, Image.INTERPOLATE_NEAREST)
	diff.save_png(ProjectSettings.globalize_path(OUT + "diff_%s_vs_%s.png" % [la, lb]))
	print("saved diff_%s_vs_%s.png (magenta = changed pixels, >0.08 color diff)" % [la, lb])

func _load(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
