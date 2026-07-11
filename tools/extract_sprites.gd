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
			"minion_0": [40, 660, 190, 230],
			"minion_0_f2": [230, 660, 200, 230],
			"minion_0_f3": [430, 660, 200, 230],
			"miner_dig1": [30, 920, 220, 260],
			"miner_dig2": [250, 920, 230, 260],
			"miner_dig3": [480, 920, 230, 260],
			"miner_find": [1010, 920, 240, 260],
		},
	},
}


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
	var crops: Dictionary = preset["crops"]
	for out_name: String in crops.keys():
		var r: Array = crops[out_name]
		var img := sheet.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
		_clear_background(img)
		var trimmed := _trim(img)
		if trimmed == null:
			print("EMPTY after trim: ", out_name)
			continue
		var squared := _square(trimmed)
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
