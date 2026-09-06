extends SceneTree

## §2追加修正: 輪郭スピル除去後もなお残っていた「髪などに閉じ込められた
## 市松模様の破片」を除去する。whitish/低彩度の連結成分のうち、サイズが
## 閾値以上のものだけを対象にする——1〜数画素の正当な小さなハイライト
## （目のキャッチライト等）は誤って消さないよう、十分保守的な閾値を使う。
## 除去対象と判断した成分は、視覚的なオーバーレイ（visualize_whitish_
## components.gd）で襟/カフス等の正当なデザインと重ならないことを目視
## 確認済み（最終報告参照）。

const SRC := "res://assets_bossmaker/art/creator_guide_character.png"
const OUT_MASTER := "res://assets_bossmaker/art/creator_guide_character.png"
const OUT_BODY := "res://assets_bossmaker/art/creator_guide_character_body.png"
const OUT_HAND := "res://assets_bossmaker/art/creator_guide_character_hand.png"
const HAND_RECT := Rect2i(695, 350, 200, 140)

const SIZE_THRESHOLD := 10

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	var w := img.get_width()
	var h := img.get_height()

	var visited := {}
	var removed_total := 0
	var removed_components := 0

	for y in range(h):
		for x in range(w):
			var key := Vector2i(x, y)
			if visited.has(key):
				continue
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or not _is_whitish(c):
				visited[key] = true
				continue
			var comp: Array[Vector2i] = []
			var queue: Array[Vector2i] = [key]
			visited[key] = true
			while not queue.is_empty():
				var p: Vector2i = queue.pop_back()
				comp.append(p)
				var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
				for d in dirs:
					var np: Vector2i = p + d
					if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
						continue
					if visited.has(np):
						continue
					var nc := img.get_pixel(np.x, np.y)
					if nc.a < 0.5 or not _is_whitish(nc):
						visited[np] = true
						continue
					visited[np] = true
					queue.append(np)
			if comp.size() >= SIZE_THRESHOLD:
				for p in comp:
					var pc := img.get_pixel(p.x, p.y)
					img.set_pixel(p.x, p.y, Color(pc.r, pc.g, pc.b, 0.0))
				removed_total += comp.size()
				removed_components += 1

	print("removed %d components, %d pixels total" % [removed_components, removed_total])
	img.save_png(ProjectSettings.globalize_path(OUT_MASTER))
	print("saved master")

	var body: Image = img.duplicate()
	for y2 in range(HAND_RECT.position.y, HAND_RECT.position.y + HAND_RECT.size.y):
		for x2 in range(HAND_RECT.position.x, HAND_RECT.position.x + HAND_RECT.size.x):
			var c2 := body.get_pixel(x2, y2)
			body.set_pixel(x2, y2, Color(c2.r, c2.g, c2.b, 0.0))
	body.save_png(ProjectSettings.globalize_path(OUT_BODY))
	print("saved body")

	var hand := img.get_region(HAND_RECT)
	hand.save_png(ProjectSettings.globalize_path(OUT_HAND))
	print("saved hand")

	print("done")
	quit()

func _is_whitish(c: Color) -> bool:
	var maxc: float = max(c.r, max(c.g, c.b))
	var minc: float = min(c.r, min(c.g, c.b))
	var sat: float = 0.0 if maxc <= 0.0001 else (maxc - minc) / maxc
	return maxc > 0.75 and sat < 0.15
