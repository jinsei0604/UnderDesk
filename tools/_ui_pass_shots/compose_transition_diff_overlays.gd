extends SceneTree

## 追加修正パス（2026-09-03、10回目）②対応: 実スクリーンショット
## (frame_A.png等、実背景・実0.50倍スケール)を使い、通常呼吸・D・Eの
## 全遷移について「前フレーム→後フレーム」の半透明重ね比較画像と、
## 差分magenta可視化を作る。頭・首・胸・腰・骨盤を含む全身縦帯を対象。

const DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const OUT := "res://tools/_ui_pass_shots/out/hair_check/review/transitions_10th/"

# 全身縦帯（頭〜膝上）を含む実画面crop。native y:50-1250 -> screen
# y:44-644、native x:100-950 -> screen x:126-551。
const BODY_CROP := Rect2i(120, 40, 440, 610)
const ZOOM := 2

# 一意な遷移ペア一覧（通常呼吸は往復とも同じテクスチャ対を使うため、
# 片方向のみで十分）。
const PAIRS := [
	["A", "AB"], ["AB", "B"], ["B", "BC"], ["BC", "C"],
	["A", "AD"], ["AD", "D"],
	["A", "E"],
	["A", "B"], ["A", "C"], ["A", "D"],
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for pair in PAIRS:
		_build_overlay(pair[0], pair[1])
		_build_diff(pair[0], pair[1])
	print("all transition diff overlays built")
	quit()

func _build_overlay(la: String, lb: String) -> void:
	var a := _load(DIR + "frame_%s.png" % la)
	var b := _load(DIR + "frame_%s.png" % lb)
	var ca := a.get_region(BODY_CROP)
	var cb := b.get_region(BODY_CROP)
	var w := BODY_CROP.size.x * ZOOM
	var h := BODY_CROP.size.y * ZOOM
	ca.resize(w, h, Image.INTERPOLATE_NEAREST)
	cb.resize(w, h, Image.INTERPOLATE_NEAREST)

	# 前フレームを赤チャンネル、後フレームを緑チャンネルへ割り当てた
	# 半透明重ね（重なっている部分は黄色、前だけ赤、後だけ緑）。
	var overlay := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var pa := ca.get_pixel(x, y)
			var pb := cb.get_pixel(x, y)
			var ba: float = (pa.r + pa.g + pa.b) / 3.0 if pa.a > 0.3 else 0.0
			var bb: float = (pb.r + pb.g + pb.b) / 3.0 if pb.a > 0.3 else 0.0
			overlay.set_pixel(x, y, Color(ba, bb, 0.0, 1.0))
	overlay.save_png(ProjectSettings.globalize_path(OUT + "overlay_%s_to_%s.png" % [la, lb]))
	print("saved overlay_%s_to_%s.png (red=%s only, green=%s only, yellow=both)" % [la, lb, la, lb])

func _build_diff(la: String, lb: String) -> void:
	var a := _load(DIR + "frame_%s.png" % la)
	var b := _load(DIR + "frame_%s.png" % lb)
	var ca := a.get_region(BODY_CROP)
	var cb := b.get_region(BODY_CROP)
	var w := BODY_CROP.size.x
	var h := BODY_CROP.size.y
	var diff := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var pa := ca.get_pixel(x, y)
			var pb := cb.get_pixel(x, y)
			var d: float = absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			if d > 0.12:
				diff.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))
			else:
				diff.set_pixel(x, y, Color(pa.r * 0.35, pa.g * 0.35, pa.b * 0.35, 1.0))
	diff.resize(w * ZOOM, h * ZOOM, Image.INTERPOLATE_NEAREST)
	diff.save_png(ProjectSettings.globalize_path(OUT + "diff_%s_to_%s.png" % [la, lb]))
	print("saved diff_%s_to_%s.png" % [la, lb])

func _load(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
