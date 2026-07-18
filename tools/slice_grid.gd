extends SceneTree
## Bulk-slices the 8x4 battle/skill sheets into individual 128x128 game
## sprites, background-cleared and trimmed, saved with positional names
## to a staging folder (NOT assets/art/ yet - these need a skill-name
## mapping proposed and confirmed before they're wired into the game's
## real naming convention).

const DIR := "C:/Users/jinch/OneDrive/デスクトップ/UNDERDESK設定/"
const OUT_DIR := "res://tools/_staging/"
const COLS := 8
const DEFAULT_ROWS := 4
## Madoka's skill sheet has 5 rows, not 4 - the design doc gives her 5
## skills (瞬影斬/月華乱舞/月詠/黄泉軍/必殺) vs. 4 for everyone else
## (3 regular + 1 ultimate), confirmed by "円のみ特別枠あり" in
## RPG_SYSTEM_DESIGN_v5.md §4, and by the sheet having no empty margin
## at the bottom (visually verified) where the other 5 sheets do.
const ROW_OVERRIDE := {
	"madoka_skills_1774x1110.png": 5,
}
const SPRITE_SIZE := 128
const BG_TOLERANCE := 0.075
const MIN_ISLAND := 20

const FILES := [
	"madoka_basic_1774x1110.png", "madoka_skills_1774x1110.png",
	"sotiris_basic_1774x1110.png", "sotiris_skills_1774x1110.png",
	"vard_basic_1774x1110.png", "vard_skills_1774x1110.png",
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for fname: String in FILES:
		var sheet := Image.load_from_file(DIR + fname)
		sheet.convert(Image.FORMAT_RGBA8)
		var w := sheet.get_width()
		var h := sheet.get_height()
		var base_name := fname.split("_")[0] + "_" + fname.split("_")[1]  # e.g. madoka_basic
		# Cells are square (cell size = sheet width / COLS); the sheet
		# canvas is taller than the 4 rows of content need, leaving blank
		# margin at the bottom - dividing by ROWS directly over the full
		# height stretches row 4 into that empty margin and drifts rows
		# out of alignment with each other. Found by inspecting output.
		var cell_size := float(w) / COLS
		var rows: int = ROW_OVERRIDE.get(fname, DEFAULT_ROWS)
		var saved := 0
		for row in rows:
			for col in COLS:
				var x0 := int(round(float(col) * cell_size))
				var x1 := int(round(float(col + 1) * cell_size))
				var y0 := int(round(float(row) * cell_size))
				var y1 := int(round(float(row + 1) * cell_size))
				var cell := sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
				_clear_background(cell, BG_TOLERANCE)
				_remove_small_islands(cell, MIN_ISLAND)
				var trimmed := _trim(cell)
				if trimmed == null:
					print("EMPTY: ", base_name, " r", row, "c", col)
					continue
				var squared := _square(trimmed)
				squared.resize(SPRITE_SIZE, SPRITE_SIZE, Image.INTERPOLATE_LANCZOS)
				var out_name := "%s_r%dc%d" % [base_name, row, col]
				squared.save_png(ProjectSettings.globalize_path("%s%s.png" % [OUT_DIR, out_name]))
				saved += 1
		print("sliced ", fname, ": ", saved, " cells")
	quit(0)


func _clear_background(img: Image, tolerance: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bg := img.get_pixel(0, 0)
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	for x in w:
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in h:
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		if visited.has(p):
			continue
		visited[p] = true
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var c := img.get_pixel(p.x, p.y)
		var dist := Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length()
		if dist > tolerance:
			continue
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		queue.append(p + Vector2i(1, 0))
		queue.append(p + Vector2i(-1, 0))
		queue.append(p + Vector2i(0, 1))
		queue.append(p + Vector2i(0, -1))


func _remove_small_islands(img: Image, min_size: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var visited: Dictionary = {}
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if visited.has(p):
				continue
			if img.get_pixel(x, y).a <= 0.01:
				visited[p] = true
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [p]
			while not stack.is_empty():
				var q: Vector2i = stack.pop_back()
				if visited.has(q):
					continue
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
					continue
				if img.get_pixel(q.x, q.y).a <= 0.01:
					continue
				visited[q] = true
				comp.append(q)
				stack.append(q + Vector2i(1, 0))
				stack.append(q + Vector2i(-1, 0))
				stack.append(q + Vector2i(0, 1))
				stack.append(q + Vector2i(0, -1))
			if comp.size() < min_size:
				for q2: Vector2i in comp:
					img.set_pixel(q2.x, q2.y, Color(0, 0, 0, 0))


func _trim(img: Image) -> Image:
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	return img.get_region(used)


func _square(img: Image) -> Image:
	var s: int = maxi(img.get_width(), img.get_height())
	var canvas := Image.create(s, s, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var dst := Vector2i((s - img.get_width()) / 2, s - img.get_height())
	canvas.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), dst)
	return canvas
