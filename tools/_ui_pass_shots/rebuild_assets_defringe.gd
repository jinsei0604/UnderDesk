extends SceneTree

## §2/§3 白フリンジ修正。creator_guide_character.png（既に正しいアルファを
## 持つマスター画像）に対し、輪郭（不透明かつ隣接画素の少なくとも1つが
## 透明）でかつ「明るく・低彩度」（=既知の背景色に近い）画素だけをalpha=0
## にする——内部画素は一切対象にしない（診断で内部のwhitish比率が0.5%と
## 極めて低いことを確認済み、輪郭のみ51.5%との差が背景スピルの証拠）。
## 白い襟・金装飾のハイライト等、デザイン上の正当な明るい画素は輪郭に
## 直接隣接していない限り一切変更しない。

const SRC := "res://assets_bossmaker/art/creator_guide_character.png"
const OUT_MASTER := "res://assets_bossmaker/art/creator_guide_character.png"
const OUT_BODY := "res://assets_bossmaker/art/creator_guide_character_body.png"
const OUT_HAND := "res://assets_bossmaker/art/creator_guide_character_hand.png"
const HAND_RECT := Rect2i(695, 350, 200, 140)

const WHITISH_MAX_THRESHOLD := 0.75
const WHITISH_SAT_THRESHOLD := 0.15
const EROSION_PASSES := 2

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	print("loaded master: ", img.get_size())

	for pass_i in range(EROSION_PASSES):
		var removed := _erode_whitish_boundary(img)
		print("pass %d: removed %d fringe pixels" % [pass_i + 1, removed])

	img.save_png(ProjectSettings.globalize_path(OUT_MASTER))
	print("saved defringed master")

	# body/hand分割を、修正済みマスターから同じ手順で再生成する。
	var body: Image = img.duplicate()
	for y in range(HAND_RECT.position.y, HAND_RECT.position.y + HAND_RECT.size.y):
		for x in range(HAND_RECT.position.x, HAND_RECT.position.x + HAND_RECT.size.x):
			var c := body.get_pixel(x, y)
			body.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
	body.save_png(ProjectSettings.globalize_path(OUT_BODY))
	print("saved defringed body")

	var hand := img.get_region(HAND_RECT)
	hand.save_png(ProjectSettings.globalize_path(OUT_HAND))
	print("saved defringed hand")

	print("done")
	quit()

## 1回のerosionパス: 輪郭かつwhitishな画素をalpha=0にする。同時に複数の
## 画素を判定してから一括で書き換える（判定中に自分自身の変更を次の画素の
## 判定へ影響させないため、判定と適用を分離する）。
func _erode_whitish_boundary(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var to_remove: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var neighbors_transparent := (
				img.get_pixel(x - 1, y).a < 0.5 or img.get_pixel(x + 1, y).a < 0.5 or
				img.get_pixel(x, y - 1).a < 0.5 or img.get_pixel(x, y + 1).a < 0.5
			)
			if not neighbors_transparent:
				continue
			var maxc: float = max(c.r, max(c.g, c.b))
			var minc: float = min(c.r, min(c.g, c.b))
			var sat: float = 0.0 if maxc <= 0.0001 else (maxc - minc) / maxc
			if maxc > WHITISH_MAX_THRESHOLD and sat < WHITISH_SAT_THRESHOLD:
				to_remove.append(Vector2i(x, y))
	for p in to_remove:
		var c := img.get_pixel(p.x, p.y)
		img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
	return to_remove.size()
