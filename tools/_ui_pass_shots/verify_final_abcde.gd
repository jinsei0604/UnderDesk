extends SceneTree

## v2最終検証。前ラウンドと同じ検証（サイズ/足元/顔髪/フリンジ/欠落行）
## を、v2生成物（prototype/*_prime.png、原本ベース）に対して行う。

const PROTO := "res://tools/_ui_pass_shots/out/breath_2_0x/"
const ORIG_A := "res://tools/_ui_pass_shots/originals/creator_guide_idle_a.png"

func _init() -> void:
	var a := _load(ORIG_A)
	var b := _load(PROTO + "b_prime.png")
	var c := _load(PROTO + "c_prime.png")
	var d := _load(PROTO + "d_prime.png")
	var e := _load(PROTO + "e_prime.png")
	var frames := {"A": a, "B": b, "C": c, "D": d, "E": e}

	print("=== size/format ===")
	for k in frames:
		var img: Image = frames[k]
		print("%s: size=%s format=%d" % [k, img.get_size(), img.get_format()])

	print("\n=== feet (bottommost opaque row, full width scan) ===")
	for k in frames:
		var img: Image = frames[k]
		print("%s: bottom_opaque_row=%d" % [k, _bottom_row(img)])

	print("\n=== face/hair stability (rows 60-330, should be pixel-identical to A) ===")
	for k in ["B", "C", "D", "E"]:
		var img: Image = frames[k]
		var diff := _diff_count_region(a, img, 100, 60, 900, 270)
		print("%s vs A: diff pixels in head/hair band (y:60-330) = %d" % [k, diff])

	print("\n=== boundary whitish fraction (background-spill fringe check) ===")
	for k in frames:
		var img: Image = frames[k]
		var frac := _whitish_boundary_fraction(img)
		print("%s: whitish_boundary_fraction=%.4f" % [k, frac])

	print("\n=== full-canvas gap scan ===")
	for k in frames:
		var img: Image = frames[k]
		_scan_gaps(img, k)

	print("\ndone")
	quit()

func _load(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	return img

func _bottom_row(img: Image) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.05:
				return y
	return -1

func _diff_count_region(base: Image, alt: Image, x0: int, y0: int, x1: int, y1: int) -> int:
	var count := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			if base.get_pixel(x, y) != alt.get_pixel(x, y):
				count += 1
	return count

func _whitish_boundary_fraction(img: Image) -> float:
	var boundary_total := 0
	var boundary_whitish := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(1, h - 1, 2):
		for x in range(1, w - 1, 2):
			var col := img.get_pixel(x, y)
			if col.a < 0.5:
				continue
			var is_boundary := false
			for offs in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if img.get_pixel(x + offs.x, y + offs.y).a < 0.5:
					is_boundary = true
					break
			if not is_boundary:
				continue
			boundary_total += 1
			var mx: float = maxf(col.r, maxf(col.g, col.b))
			var mn: float = minf(col.r, minf(col.g, col.b))
			var sat: float = 0.0
			if mx > 0.001:
				sat = (mx - mn) / mx
			if mx > 0.75 and sat < 0.15:
				boundary_whitish += 1
	if boundary_total == 0:
		return 0.0
	return float(boundary_whitish) / boundary_total

func _scan_gaps(img: Image, label: String) -> void:
	var h := img.get_height()
	var counts := PackedInt32Array()
	counts.resize(h)
	for y in range(h):
		var cnt := 0
		for x in range(254, 847, 2):
			if img.get_pixel(x, y).a > 0.5:
				cnt += 1
		counts[y] = cnt
	var found := false
	for y in range(6, h - 6):
		if counts[y] < 3:
			continue
		var neighbor_avg := 0.0
		for dy in [-6, -5, -4, -3, 3, 4, 5, 6]:
			neighbor_avg += counts[y + dy]
		neighbor_avg /= 8.0
		if neighbor_avg > 20.0 and float(counts[y]) < neighbor_avg * 0.35:
			print("%s: GAP at row %d (count=%d, neighbor_avg=%.1f)" % [label, y, counts[y], neighbor_avg])
			found = true
	if not found:
		print("%s: no gaps found" % label)
