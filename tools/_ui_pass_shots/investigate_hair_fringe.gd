extends SceneTree

## 髪周辺の白フリンジ調査（緊急修正パス）。全7素材（A/AB/B/BC/C/D/E）を
## 対象に、①境界画素（不透明かつ隣接に透明画素を持つ）のうち明るく低彩度
## なもの、②それらの座標クラスタ、③RGB/alpha実値を出力する。
## 「フリンジ率0%だから正常」という誤判定を避けるため、閾値を緩め
## （maxc>0.55かつsat<0.25）、かつ座標を明示的に出力して目視確認できる
## ようにする。

const DIR := "res://assets_bossmaker/art/"
const NAMES := ["a", "ab", "b", "bc", "c", "d_posture", "e_hand"]
const LABELS := ["A", "AB", "B", "BC", "C", "D", "E"]

## 髪・帽子がありそうな上半身の範囲だけに限定して走査する（native座標）。
## 目のbboxがy:255-290付近なので、髪はそれより広い範囲に及ぶ想定。
const SCAN_REGION := Rect2i(150, 0, 750, 400)

func _init() -> void:
	for i in range(NAMES.size()):
		var img := _load(DIR + "creator_guide_idle_%s.png" % NAMES[i])
		_scan(img, LABELS[i])
	quit()

func _load(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

func _scan(img: Image, label: String) -> void:
	var suspects: Array = []
	for y in range(SCAN_REGION.position.y, SCAN_REGION.position.y + SCAN_REGION.size.y):
		for x in range(SCAN_REGION.position.x, SCAN_REGION.position.x + SCAN_REGION.size.x):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var neighbors_transparent := false
			for offs in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var nx: int = x + offs.x
				var ny: int = y + offs.y
				if nx < 0 or ny < 0 or nx >= img.get_width() or ny >= img.get_height():
					continue
				if img.get_pixel(nx, ny).a < 0.5:
					neighbors_transparent = true
					break
			if not neighbors_transparent:
				continue
			var maxc: float = max(c.r, max(c.g, c.b))
			var minc: float = min(c.r, min(c.g, c.b))
			var sat: float = 0.0 if maxc <= 0.0001 else (maxc - minc) / maxc
			# 緩めの閾値: 明るめ(0.55超)かつ低彩度(0.25未満)を「白/灰色寄り」
			# として拾う——0.75/0.15という旧テストの厳しい閾値では見逃す
			# 中間的な灰白色も検出対象にする。
			if maxc > 0.55 and sat < 0.25:
				suspects.append([x, y, c.r, c.g, c.b, c.a])

	print("=== %s: %d suspect boundary pixels (maxc>0.55, sat<0.25) in scan region ===" % [label, suspects.size()])
	# クラスタの傾向を掴むため、y座標でソートして先頭・末尾を少し出す。
	suspects.sort_custom(func(p1, p2): return p1[1] < p2[1])
	var show := mini(20, suspects.size())
	for i in range(show):
		var s = suspects[i]
		print("  (%d,%d) rgb=(%.2f,%.2f,%.2f) a=%.2f" % [s[0], s[1], s[2], s[3], s[4], s[5]])
	if suspects.size() > 40:
		print("  ... (%d more) ..." % (suspects.size() - show - 20))
		for i in range(maxi(show, suspects.size() - 20), suspects.size()):
			var s = suspects[i]
			print("  (%d,%d) rgb=(%.2f,%.2f,%.2f) a=%.2f" % [s[0], s[1], s[2], s[3], s[4], s[5]])
