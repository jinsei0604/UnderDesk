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
## In-game sprites are resampled to this size (matches the expanded
## view's cell) so nearest-neighbor drawing stays crisp.
const GAME_SPRITE_SIZE := 128

## Outputs flipped horizontally so every frame of a character faces the
## same way (the game mirrors at draw time for the other direction).
## Every minion_0 frame must agree with the base idle pose's orientation
## or the dig loop visibly snaps to face the wrong way mid-swing (bug
## found 2026-07-12: the miner_v2 preset's raw poses face the opposite
## way from the kept idle frame).
const FLIP_X_OUTPUTS: Array[String] = [
	"minion_0", "minion_0_f2", "minion_0_f3", "minion_0_f4", "minion_0_f5",
	"minion_0_f6",
]

## preset -> { src, crops: { out_name: [x, y, w, h] } }
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
	"miner": {
		"src": "res://assets/reference/miner_sheet.png",
		"crops": {
			"minion_0": [50, 665, 135, 210],
			"minion_0_f2": [245, 940, 185, 235],
			"minion_0_f3": [650, 940, 150, 235],
			"miner_walk2": [240, 665, 145, 210],
			"miner_walk3": [440, 665, 140, 210],
			"miner_walk4": [635, 665, 145, 210],
			"miner_walk5": [840, 665, 160, 210],
			"miner_dig1": [40, 915, 170, 260],
			"miner_dig3_dust": [445, 940, 160, 235],
			"miner_dig5": [835, 940, 165, 235],
			"miner_find": [1030, 940, 205, 235],
		},
	},
	## Second reference sheet (2026-07-12): a uniform 10x4 grid of poses,
	## each cell stamped with a small numbered badge in the top-left that
	## must be erased before flood-fill (see ERASE_TOP_LEFT below). Picks
	## a full raise -> strike -> dust -> recover arc for a richer, more
	## natural dig loop (was a 3-frame loop that read as jittery).
	"miner_v2": {
		"src": "res://assets/reference/miner_sheet_v2.png",
		"grid": {"cols": 10, "rows": 4, "sheet_w": 1536, "sheet_h": 1024},
		"cell_crops": {
			# out_name: cell_index (0-based, row-major). minion_0 itself
			# (the idle/base frame) is intentionally NOT regenerated here:
			# every clean crop near its cell (20, 27, ...) bled a sliver
			# of the neighboring pose in this sheet, so the original,
			# already-shipped idle frame is kept and only the swing
			# frames below are sourced from this sheet.
			"minion_0_f2": 21,  # wind-up lifting (fixes the idle->apex snap)
			"minion_0_f3": 7,   # wind-up at apex
			"minion_0_f4": 8,   # strike begins, light dust
			"minion_0_f5": 25,  # strike peak, dust bursts
			"minion_0_f6": 9,   # dust settling, eases back toward idle
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
	for out_name: String in crops.keys():
		var r: Array = crops[out_name]
		var img := sheet.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
		if erase_badge:
			img.fill_rect(ERASE_TOP_LEFT, img.get_pixel(0, 0))
		_clear_background(img)
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
func _clear_background(img: Image) -> void:
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
		if dist > BG_TOLERANCE:
			continue
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		queue.append(p + Vector2i(1, 0))
		queue.append(p + Vector2i(-1, 0))
		queue.append(p + Vector2i(0, 1))
		queue.append(p + Vector2i(0, -1))


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
