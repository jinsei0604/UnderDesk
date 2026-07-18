extends SceneTree
## One-shot art tool: crops character poses out of a reference sheet,
## clears the background by flood fill from the borders (so dark hair
## in the interior survives), trims, pads to a bottom-centered square,
## and saves game-ready PNGs.
##
## Run:
##   godot --headless --path . -s res://tools/extract_sprites.gd -- <config>
## where <config> selects a preset below.

const BG_TOLERANCE := 0.075
## Per-preset override: some source art (e.g. a dark-clothed character on
## a near-black sheet, no clean color gap between subject and background —
## see madoka_idle) needs a much tighter tolerance than the sheets this
## tool was originally built for, plus a pass that removes small leftover
## noise islands the tighter tolerance doesn't fully flood-fill away.
const TOLERANCE_OVERRIDE := {
	"madoka_idle": 0.03,
}
const MIN_ISLAND_OVERRIDE := {
	"madoka_idle": 20,
}
## In-game sprites are resampled to this size (matches the expanded
## view's cell) so nearest-neighbor drawing stays crisp.
const GAME_SPRITE_SIZE := 128

## Outputs flipped horizontally so every frame of a character faces the
## same way (the game mirrors at draw time for the other direction).
## Every minion_0 frame must agree with the base idle pose's orientation
## or the dig loop visibly snaps to face the wrong way mid-swing.
const FLIP_X_OUTPUTS: Array[String] = []

## preset -> { src, crops: { out_name: [x, y, w, h] } }
## or { src, grid: {...}, cell_crops: { out_name: cell_index } } for a
## uniform-grid reference sheet (see the "grid"/"cell_crops" handling
## below; ERASE_TOP_LEFT strips a numbered badge stamped in each cell).
##
## NOTE (2026-07-13): the "miner"/"miner_v2" presets that used to
## generate minion_0[.._f6].png are gone — the protagonist's dig frames
## are now the user's hand-drawn art (Pixelorama). Re-running an old
## preset targeting those output names would silently overwrite that
## hand-drawn work, so don't recreate one without confirming first.
const PRESETS := {
	"riko": {
		"src": "res://assets/reference/riko_sheet.png",
		"crops": {
			"minion_2": [40, 720, 155, 152],
			"minion_2_f2": [220, 720, 165, 152],
			"riko_notice": [395, 662, 160, 210],
			"riko_read": [565, 720, 180, 152],
			"riko_think": [735, 652, 170, 220],
			"riko_surprise": [900, 688, 165, 184],
			"riko_cheer": [1055, 700, 180, 172],
		},
	},
	## Madoka (円, companion_1) idle row only (§待機モーション, y49-146,
	## measured with tools/analyze_madoka_sheet.gd). Only the idle loop is
	## extracted for now — party art only needs a static/animated icon
	## (UDArtLibrary._draw_party_row uses icon_or_placeholder, one frame is
	## enough; _fN frames are a free bonus since the sheet already has 8).
	## The rest of the sheet (walk/dash/attack/skill/hit/...) is for the
	## unbuilt manual battle system — extract those once that work starts.
	"madoka_idle": {
		"src": "C:/Users/jinch/OneDrive/デスクトップ/UNDERDESK設定/4b681009-7eb4-4f1a-aa02-4d690601424d.png",
		"crops": {
			"minion_1": [492, 35, 94, 125],
			"minion_1_f2": [621, 35, 94, 125],
			"minion_1_f3": [737, 35, 81, 125],
			"minion_1_f4": [837, 35, 78, 125],
			"minion_1_f5": [935, 35, 79, 125],
			"minion_1_f6": [1033, 35, 81, 125],
			"minion_1_f7": [1140, 35, 87, 125],
			"minion_1_f8": [1236, 35, 96, 125],
		},
	},
}

## Cell-local rect to blank out before background clearing (kills the
## reference sheet's numbered badge so it never survives into trim()).
## Measured against the actual sheet: the badge spans roughly
## x:12-46, y:38-64, so this rect covers it with margin.
const ERASE_TOP_LEFT := Rect2i(0, 0, 52, 68)
## Horizontal inset per cell + fixed crop width: keeps each character
## clear of its neighbors regardless of how wide a pose's cell margin is.
const CELL_INSET_X := 6
const CELL_CROP_W := 88


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_name := "riko" if args.is_empty() else String(args[0])
	if not PRESETS.has(preset_name):
		push_error("unknown preset: %s" % preset_name)
		quit(1)
		return
	var preset: Dictionary = PRESETS[preset_name]
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(preset["src"]))
	if sheet == null:
		push_error("cannot load %s" % preset["src"])
		quit(1)
		return
	sheet.convert(Image.FORMAT_RGBA8)
	# Two crop styles: hand-picked rects ("crops"), or a uniform grid
	# where each cell is picked by index and auto-inset ("cell_crops").
	var crops: Dictionary = {}
	if preset.has("cell_crops"):
		var grid: Dictionary = preset["grid"]
		var cell_w: float = float(grid["sheet_w"]) / float(grid["cols"])
		var cell_h: float = float(grid["sheet_h"]) / float(grid["rows"])
		var cell_crops: Dictionary = preset["cell_crops"]
		for out_name: String in cell_crops.keys():
			var index: int = int(cell_crops[out_name])
			var col: int = index % int(grid["cols"])
			var row: int = index / int(grid["cols"])
			var x0 := int(round(col * cell_w)) + CELL_INSET_X
			crops[out_name] = [x0, int(row * cell_h), CELL_CROP_W, int(cell_h)]
	else:
		crops = preset["crops"]
	var erase_badge: bool = preset.has("cell_crops")
	var tolerance: float = TOLERANCE_OVERRIDE.get(preset_name, BG_TOLERANCE)
	var min_island: int = MIN_ISLAND_OVERRIDE.get(preset_name, 0)
	for out_name: String in crops.keys():
		var r: Array = crops[out_name]
		var img := sheet.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
		if erase_badge:
			img.fill_rect(ERASE_TOP_LEFT, img.get_pixel(0, 0))
		_clear_background(img, tolerance)
		if min_island > 0:
			_remove_small_islands(img, min_island)
		var trimmed := _trim(img)
		if trimmed == null:
			print("EMPTY after trim: ", out_name)
			continue
		var squared := _square(trimmed)
		if out_name.begins_with("minion_"):
			squared.resize(GAME_SPRITE_SIZE, GAME_SPRITE_SIZE, Image.INTERPOLATE_LANCZOS)
		if FLIP_X_OUTPUTS.has(out_name):
			squared.flip_x()
		var out_path := ProjectSettings.globalize_path("res://assets/art/%s.png" % out_name)
		squared.save_png(out_path)
		print("saved %s (%dx%d)" % [out_name, squared.get_width(), squared.get_height()])
	quit(0)


## Flood-fills transparency inward from every border pixel that matches
## the background color within tolerance.
func _clear_background(img: Image, tolerance: float = BG_TOLERANCE) -> void:
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


## Clears any opaque connected component smaller than min_size pixels —
## kills leftover noise specks a tight tolerance doesn't fully flood-fill
## away, without touching the character's main (much larger) silhouette.
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


## Pads to a square canvas, bottom-centered, so the game can stretch it
## into its square cell without distortion.
func _square(img: Image) -> Image:
	var s: int = maxi(img.get_width(), img.get_height())
	var canvas := Image.create(s, s, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var dst := Vector2i((s - img.get_width()) / 2, s - img.get_height())
	canvas.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), dst)
	return canvas
