extends SceneTree
## Bulk-slices the 8x4 battle/skill sheets into individual 128x128 game
## sprites, background-cleared and trimmed, saved with positional names
## (row/col) to a staging folder outside the project. The row->skill-name
## mapping (walk/dash/attack/skill_<name>) is applied afterward by hand
## when copying the confirmed cells into assets/art/ - see CLAUDE.md's
## content recipe for the current naming.

const DIR := "C:/Users/jinch/OneDrive/デスクトップ/UNDERDESK設定/"
## Outside res:// on purpose - Godot auto-imports anything under the
## project tree, and 200 throwaway staging PNGs previously bloated the
## import cache with .import files that had to be cleaned up by hand.
const OUT_DIR := "C:/Users/jinch/AppData/Local/Temp/claude/C--src-underdesk/6fface6a-af13-4854-9b42-ba0bf7c0b720/scratchpad/sprite_staging2/"
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
## Cells are NOT reliably square across deliveries. Most sheets use
## square cells (row height = column width = w/8) with blank canvas
## margin below the last row; but sayu_basic stretches its 4 rows over
## the full 1110px canvas instead (row height 277.5 vs column width
## 221.75). Slicing that with the square assumption cuts across the real
## row boundaries - divider lines appear inside crops, sprites lose
## their feet, the row above bleeds in. Full-height sheets get
## row_h = h / rows. CAUTION when classifying a sheet: a bottom-of-canvas
## divider line makes a naive "where does content end" scan report ~5.0
## square-rows-worth even on a square-cell sheet (that false positive
## put shiba_yo_skills in this list at first, which turned its slicing
## into garbage - all of row 3 came out empty). Verify against the
## actual image, not just the scan: does the LAST ROW OF CHARACTERS sit
## near the canvas bottom (full-height) or is there a blank band below
## them (square)?
const FULL_HEIGHT_SHEETS := [
	"sayu_basic_1774x1110.png",
]
const SPRITE_SIZE := 128
const BG_TOLERANCE := 0.09
const MIN_ISLAND := 20
## 2026-07-18: the first extraction pass (committed, then found broken by
## the user - "ドット絵に背景が入ってしまっている") left real gray
## background behind most frames. Two compounding bugs, both fixed here:
## 1. Cell boundaries computed by simple division land ON the sheet's
##    grid divider lines (~4-5px, darker than the flat background), not
##    cleanly between cells. Sampling the flood-fill's background
##    reference color from a crop's own (0,0) corner then picks up the
##    grid-line color instead of true background, and the fill barely
##    propagates. Fixed by CELL_INSET (crop a few px past the divider).
## 2. Even past the divider, a single reference pixel is fragile - the
##    sheets have visible grain/noise (adjacent background pixels can
##    differ by ~0.05-0.1), and any content that happens to graze a
##    crop's exact corner throws it off completely. Fixed by sampling a
##    small patch at each of the 4 corners and using whichever patch has
##    the lowest internal variance (least likely to contain content).
## Do NOT validate this kind of fix by checking alpha at a handful of
## border pixels (tried that, got misleading 100+/200 "failures" - trim()
## guarantees content touches its own bounding edges, especially the
## bottom since _square() bottom-aligns, so "opaque pixel at the border"
## is often correct, not a bug). What actually caught the real bug: a
## single composite "contact sheet" of every frame tiled on a bright
## green backdrop (impossible to miss a leftover gray square at a
## glance) - the fastest reliable way to audit background-removal
## quality on a batch this size.
## far from that sample point (only dropped the failure rate to
## 180/200). The fix that actually worked: inset each crop, then sample
## the background reference **per cell** (still from that cell's own
## corner, just past the divider now instead of on top of it).
const CELL_INSET := 8

const FILES := [
	"sotiris_basic_1774x1110.png", "sotiris_skills_1774x1110.png",
	"madoka_basic_1774x1110.png", "madoka_skills_1774x1110.png",
	"vard_basic_1774x1110.png", "vard_skills_1774x1110.png",
	"shiba_yo_basic_1774x1110.png", "shiba_yo_skills_1774x1110.png",
	"sayu_basic_1774x1110.png", "sayu_skills_1774x1110.png",
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for fname: String in FILES:
		var sheet := Image.load_from_file(DIR + fname)
		sheet.convert(Image.FORMAT_RGBA8)
		var w := sheet.get_width()
		var h := sheet.get_height()
		# e.g. "shiba_yo_basic_1774x1110.png" -> "shiba_yo_basic". Naively
		# taking split("_")[0]+"_"+split("_")[1] breaks for character names
		# that themselves contain an underscore (shiba_yo) - it silently
		# collapsed shiba_yo_basic and shiba_yo_skills to the same
		# "shiba_yo" base name and one overwrote the other's output files
		# (128 cells sliced, only 96 landed on disk - caught by the
		# contact-sheet file count not matching the slice log's count).
		# Fixed: the last token is always the WxH.png dimensions, the one
		# before that is always basic/skills - everything else is the name.
		var parts := fname.get_basename().split("_")
		var base_name := "_".join(parts.slice(0, parts.size() - 1))
		# Cells are square (cell size = sheet width / COLS); the sheet
		# canvas is taller than the 4 rows of content need, leaving blank
		# margin at the bottom - dividing by ROWS directly over the full
		# height stretches row 4 into that empty margin and drifts rows
		# out of alignment with each other. Found by inspecting output.
		var cell_size := float(w) / COLS
		var rows: int = ROW_OVERRIDE.get(fname, DEFAULT_ROWS)
		var row_h := float(h) / rows if FULL_HEIGHT_SHEETS.has(fname) else cell_size
		# Column edges: detected from the sheet's actual vertical divider
		# lines when possible, uniform division otherwise (see
		# _detect_column_edges - madoka_skills' grid is genuinely
		# non-uniform, columns range 250px down to 162px).
		var col_edges := _detect_column_edges(sheet)
		if col_edges.size() != COLS + 1:
			col_edges.clear()
			for c in COLS + 1:
				col_edges.append(int(round(float(c) * cell_size)))
		else:
			print("  (", fname, ": using detected column edges ", col_edges, ")")
		var saved := 0
		for row in rows:
			for col in COLS:
				var x0: int = col_edges[col] + CELL_INSET
				var x1: int = col_edges[col + 1] - CELL_INSET
				var y0 := int(round(float(row) * row_h)) + CELL_INSET
				var y1 := int(round(float(row + 1) * row_h)) - CELL_INSET
				var cell := sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
				var bg_ref := _median_bg(cell)
				_clear_background(cell, BG_TOLERANCE, bg_ref)
				_remove_small_islands(cell, MIN_ISLAND)
				_remove_top_bleed(cell)
				_remove_divider_lines(cell)
				_remove_enclosed_background(cell, bg_ref)
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


## Detects the sheet's actual vertical divider-line positions instead of
## trusting uniform division. Needed because madoka_skills' grid is
## genuinely NON-uniform (measured divider centers: 250, 488, 727, 961,
## 1193, 1412, 1612 - columns shrink from 250px to 162px left to right,
## drifting up to ~60px from the uniform-division positions; this
## re-confirms CLAUDE.md's old "AI生成シートは列幅が均一グリッド計算
## どおりにならないことがある" pitfall). A divider column is one whose
## pixels are consistently darker than the background over nearly the
## full canvas height. Returns COLS+1 edges (canvas edges + 7 internal
## divider centers) or an empty array when detection doesn't find
## exactly 7 internal dividers (caller falls back to uniform division -
## e.g. when bright effects crossing a divider break its dark run).
func _detect_column_edges(sheet: Image) -> Array[int]:
	var w := sheet.get_width()
	var h := sheet.get_height()
	var bg := sheet.get_pixel(2, 2)
	var divider_cols: Array[int] = []
	for x in range(4, w - 4):
		var dark := 0
		for y in range(0, h, 2):
			var c := sheet.get_pixel(x, y)
			var d := Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length()
			if d > 0.04 and c.r < bg.r:
				dark += 1
		if float(dark) / (h / 2.0) > 0.85:
			divider_cols.append(x)
	# Group consecutive columns into divider centers.
	var centers: Array[int] = []
	var run_start := -10
	var prev := -10
	for x in divider_cols:
		if x != prev + 1:
			if run_start >= 0:
				centers.append((run_start + prev) / 2)
			run_start = x
		prev = x
	if run_start >= 0:
		centers.append((run_start + prev) / 2)
	if centers.size() != COLS - 1:
		return []
	var edges: Array[int] = [0]
	edges.append_array(centers)
	edges.append(w)
	return edges


## Median color over a small patch at each corner, picking whichever
## corner patch has the lowest internal variance (most likely to be
## clean background rather than grazing a character/effect). Far more
## robust than a single pixel, which regularly landed on grain noise or
## a sliver of content and made the whole flood-fill reference wrong.
func _median_bg(img: Image) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	var patch := 10
	var corners := [
		Vector2i(0, 0), Vector2i(w - patch, 0),
		Vector2i(0, h - patch), Vector2i(w - patch, h - patch),
	]
	var best_color := Color.MAGENTA
	var best_variance := INF
	for c: Vector2i in corners:
		var sum := Vector3.ZERO
		var count := 0
		for y in range(c.y, c.y + patch):
			for x in range(c.x, c.x + patch):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var px := img.get_pixel(x, y)
				sum += Vector3(px.r, px.g, px.b)
				count += 1
		if count == 0:
			continue
		var mean := sum / count
		var variance := 0.0
		for y in range(c.y, c.y + patch):
			for x in range(c.x, c.x + patch):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var px := img.get_pixel(x, y)
				variance += Vector3(px.r, px.g, px.b).distance_squared_to(mean)
		variance /= count
		if variance < best_variance:
			best_variance = variance
			best_color = Color(mean.x, mean.y, mean.z)
	return best_color


func _clear_background(img: Image, tolerance: float, bg: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
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


## Kills connected components confined entirely to the crop's top band.
## These are bleed-over from the row above: some characters (e.g. Sayu's
## ponytail) are drawn taller than their grid cell and dip past the
## divider into the cell below, leaving a floating hair fragment near
## the top of the crop. A legitimate subject never looks like that here
## - characters are bottom-anchored and even full-height effects extend
## well below the top band - so "fits entirely in the top third" is a
## safe bleed signature. Note it must NOT require touching the top edge:
## clearing the divider as background often leaves the fragment floating
## a few px down, detached from y=0 (the first edge-seeded version of
## this check missed everything for exactly that reason). CELL_INSET
## alone can't fix this either: the overflow reaches ~15-20px past the
## divider, and insetting that far would eat neighboring real content.
func _remove_top_bleed(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var band := h / 3
	var visited: Dictionary = {}
	for y in band:
		for x in w:
			var p := Vector2i(x, y)
			if visited.has(p) or img.get_pixel(x, y).a <= 0.01:
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [p]
			var max_y := 0
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
				max_y = maxi(max_y, q.y)
				stack.append(q + Vector2i(1, 0))
				stack.append(q + Vector2i(-1, 0))
				stack.append(q + Vector2i(0, 1))
				stack.append(q + Vector2i(0, -1))
			if max_y < band:
				for q2: Vector2i in comp:
					img.set_pixel(q2.x, q2.y, Color(0, 0, 0, 0))


## Kills surviving grid-divider fragments: components that are very wide
## but only a few px tall (a shape no character or effect in these
## sheets ever has - the flattest real effects, like wind streams and
## flame jets, are 25px+ tall). Found the hard way: sayu_basic's row
## dividers carry a soft shadow that extends past CELL_INSET into the
## crop, the flood fill stops at the divider's own color boundary, and
## the leftover reads as a gray bar under the character's feet in-game.
## These bars also slipped through the contact-sheet review because a
## bar at a sprite's bottom edge looks exactly like the contact sheet's
## own cell boundary - which is why the contact sheet tools now draw
## gaps between cells.
func _remove_divider_lines(img: Image) -> void:
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
			var min_x := w
			var max_x := 0
			var min_y := h
			var max_y := 0
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
				min_x = mini(min_x, q.x)
				max_x = maxi(max_x, q.x)
				min_y = mini(min_y, q.y)
				max_y = maxi(max_y, q.y)
				stack.append(q + Vector2i(1, 0))
				stack.append(q + Vector2i(-1, 0))
				stack.append(q + Vector2i(0, 1))
				stack.append(q + Vector2i(0, -1))
			var comp_w := max_x - min_x + 1
			var comp_h := max_y - min_y + 1
			if comp_h <= 10 and comp_w >= w / 3:
				for q2: Vector2i in comp:
					img.set_pixel(q2.x, q2.y, Color(0, 0, 0, 0))


## Clears background trapped inside closed content loops, which the
## border-seeded flood fill can never reach (e.g. the flat gray patches
## inside Shiba Yao's 呪縛 chain coil). A region qualifies only if ALL
## of: every pixel matches the cell's background reference within a
## strict tolerance (much tighter than the flood fill's), the region is
## flat (near-zero color variance - real art like Sayu's silver-gray
## hair, whose hue drifts near the warm-gray background, always carries
## shading), and it is at least a few dozen px (never punch pinholes in
## antialiased interiors). All three guards matter: Sayu's hair is the
## reason a simple global "erase anything bg-colored" pass was rejected.
func _remove_enclosed_background(img: Image, bg: Color) -> void:
	const STRICT_TOL := 0.045
	const FLATNESS := 0.0012
	const MIN_REGION := 40
	var w := img.get_width()
	var h := img.get_height()
	var visited: Dictionary = {}
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if visited.has(p):
				continue
			var c0 := img.get_pixel(x, y)
			if c0.a <= 0.01 or Vector3(c0.r - bg.r, c0.g - bg.g, c0.b - bg.b).length() > STRICT_TOL:
				visited[p] = true
				continue
			# Grow the region of strictly-bg-like pixels.
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [p]
			var sum := Vector3.ZERO
			while not stack.is_empty():
				var q: Vector2i = stack.pop_back()
				if visited.has(q):
					continue
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
					continue
				var c := img.get_pixel(q.x, q.y)
				if c.a <= 0.01 or Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length() > STRICT_TOL:
					continue
				visited[q] = true
				comp.append(q)
				sum += Vector3(c.r, c.g, c.b)
				stack.append(q + Vector2i(1, 0))
				stack.append(q + Vector2i(-1, 0))
				stack.append(q + Vector2i(0, 1))
				stack.append(q + Vector2i(0, -1))
			if comp.size() < MIN_REGION:
				continue
			var mean := sum / comp.size()
			var variance := 0.0
			for q2: Vector2i in comp:
				var c2 := img.get_pixel(q2.x, q2.y)
				variance += Vector3(c2.r, c2.g, c2.b).distance_squared_to(mean)
			variance /= comp.size()
			if variance < FLATNESS:
				for q3: Vector2i in comp:
					img.set_pixel(q3.x, q3.y, Color(0, 0, 0, 0))


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
