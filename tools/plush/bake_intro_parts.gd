extends SceneTree
## ぬいぐるみの登場「縫い直し」（rbm_intro_plush.gd）で使う、立ち姿（poses.png のコマ 0）を部位ごとに切り分けた絵を作る（2026-11-19）。
## 起動: godot --headless --path . --script res://tools/plush/bake_intro_parts.gd → --import
## 作る物: assets_bossmaker/battle/plush/intro_parts/<部位>.png（どれもコマ 0 と同じ 106×170。その部位の画素だけを残す）。
## 切り方: 黒い輪郭（#211e29）を壁にして、輪郭以外の画素を4方向でつながった塊に分け、塊を部位へ割り当てる
## （種の点の塊はその部位、種の無い塊（目・鼻・お腹・つぎ当て・肉球など）は、輪郭をはさんで接している部位の多数決）。
## 輪郭の画素は、隣り合う部位のすべてに入れる（どの部位にも輪郭が付き、組み上がった時は元の絵と同じになる）。
## 最後に、全部の部位を重ねるとコマ 0 と画素が一致することを確かめ、部位ごとの縫い目の点（胴と接する輪郭の中心）を出す。

const SOURCE := "res://assets_bossmaker/battle/plush/poses.png"
const OUT := "res://assets_bossmaker/battle/plush/intro_parts/"
const FRAME := Rect2i(0, 0, 106, 170)
const INK := Color8(0x21, 0x1e, 0x29)
## 種の点（コマ 0 の中の画素）。部位ごとに1つ以上。
const SEEDS := {
	"head": [Vector2i(50, 30)],
	"torso": [Vector2i(22, 100), Vector2i(76, 100), Vector2i(50, 145), Vector2i(45, 78), Vector2i(30, 73)],
	"arm_l": [Vector2i(10, 100)],
	"arm_r": [Vector2i(90, 100)],
	"leg_l": [Vector2i(25, 150), Vector2i(35, 160)],
	"leg_r": [Vector2i(75, 150), Vector2i(75, 160)],
}
const PARTS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]
## 輪郭が途切れていて、隣の部位の塗りとつながってしまう所（股の右側）。ここは輪郭と同じに扱う（色は元のまま、両方の部位に入る）。
const WALLS := [Vector2i(60, 149), Vector2i(61, 149), Vector2i(62, 149)]

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if img == null:
		push_error("cannot read " + SOURCE)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var f := img.get_region(FRAME)
	var w := f.get_width()
	var h := f.get_height()
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var comps: Array = []
	# 輪郭以外の画素の塊（4方向）
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			if comp[i] != -1 or not _fill(f, x, y):
				continue
			var id := comps.size()
			var pixels: Array = []
			var stack: Array = [Vector2i(x, y)]
			comp[i] = id
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				pixels.append(p)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
						continue
					var j := q.y * w + q.x
					if comp[j] == -1 and _fill(f, q.x, q.y):
						comp[j] = id
						stack.append(q)
			comps.append(pixels)
	var part_of := {}
	for part in SEEDS:
		for s in SEEDS[part]:
			var id := comp[s.y * w + s.x]
			if id < 0:
				push_error("seed on ink or empty: %s %s" % [part, s])
				quit(1)
				return
			if part_of.has(id) and part_of[id] != part:
				push_error("seed conflict: %s and %s share a region" % [part, part_of[id]])
				quit(1)
				return
			part_of[id] = part
	# 種の無い塊: 輪郭をはさんだ向こう側（2画素先まで）の部位の多数決。決まるまで繰り返す
	for round in range(20):
		var changed := false
		for id in range(comps.size()):
			if part_of.has(id):
				continue
			var votes := {}
			for p in comps[id]:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var q: Vector2i = p + Vector2i(dx, dy)
						if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
							continue
						var other := comp[q.y * w + q.x]
						if other >= 0 and other != id and part_of.has(other):
							votes[part_of[other]] = int(votes.get(part_of[other], 0)) + 1
			if votes.is_empty():
				continue
			var best := ""
			for k in votes:
				if best == "" or int(votes[k]) > int(votes[best]):
					best = k
			part_of[id] = best
			changed = true
		if not changed:
			break
	# 部位ごとの絵
	var images := {}
	for part in PARTS:
		var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		images[part] = im
	var seams := {}
	for y in range(h):
		for x in range(w):
			var c := f.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var id := comp[y * w + x]
			if id >= 0:
				if not part_of.has(id):
					push_error("unassigned pixel %d,%d" % [x, y])
					continue
				images[part_of[id]].set_pixel(x, y, c)
				continue
			# 輪郭: 8方向の隣の部位すべてに入れる
			var owners := {}
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var qx := x + dx
					var qy := y + dy
					if qx < 0 or qy < 0 or qx >= w or qy >= h:
						continue
					var other := comp[qy * w + qx]
					if other >= 0 and part_of.has(other):
						owners[part_of[other]] = true
			if owners.is_empty():
				# 輪郭だけが続く所（太い輪郭の内側）は、近い輪郭の持ち主に合わせる（2画素先まで）
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var qx := x + dx
						var qy := y + dy
						if qx < 0 or qy < 0 or qx >= w or qy >= h:
							continue
						var other := comp[qy * w + qx]
						if other >= 0 and part_of.has(other):
							owners[part_of[other]] = true
			for part in owners:
				images[part].set_pixel(x, y, c)
			# 縫い目: 胴と他の部位の両方に入った輪郭
			if owners.has("torso"):
				for part in owners:
					if part != "torso":
						if not seams.has(part):
							seams[part] = []
						seams[part].append(Vector2(x, y))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for part in PARTS:
		images[part].save_png(ProjectSettings.globalize_path(OUT + part + ".png"))
	# 重ねるとコマ 0 と同じか
	var mismatch := 0
	for y in range(h):
		for x in range(w):
			var c := f.get_pixel(x, y)
			var got := Color(0, 0, 0, 0)
			for part in PARTS:
				var pc: Color = images[part].get_pixel(x, y)
				if pc.a > 0.5:
					got = pc
			if (c.a > 0.5) != (got.a > 0.5) or (c.a > 0.5 and not c.is_equal_approx(got)):
				mismatch += 1
	print("PLUSH_PARTS mismatch_pixels=", mismatch)
	for part in PARTS:
		var used := (images[part] as Image).get_used_rect()
		var seam := Vector2.ZERO
		if seams.has(part):
			for p in seams[part]:
				seam += p
			seam = (seam / float(seams[part].size())).round()
		print("PLUSH_PART ", part, " used=", used, " seam=", seam, " seam_pixels=", seams.get(part, []).size())
	quit(0 if mismatch == 0 else 1)

## 輪郭以外の、色のある画素か
func _fill(f: Image, x: int, y: int) -> bool:
	var c := f.get_pixel(x, y)
	return c.a >= 0.5 and not c.is_equal_approx(INK) and not WALLS.has(Vector2i(x, y))
