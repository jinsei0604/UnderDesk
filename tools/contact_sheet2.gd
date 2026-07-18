extends SceneTree
const DIR := "C:/Users/jinch/AppData/Local/Temp/claude/C--src-underdesk/6fface6a-af13-4854-9b42-ba0bf7c0b720/scratchpad/sprite_staging2/"
const OUT := "C:/Users/jinch/AppData/Local/Temp/claude/C--src-underdesk/6fface6a-af13-4854-9b42-ba0bf7c0b720/scratchpad/"
const CELL := 96
const COLS := 16

func _init() -> void:
	var d := DirAccess.open(DIR)
	var names: Array[String] = []
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname.ends_with(".png"):
			names.append(fname)
		fname = d.get_next()
	d.list_dir_end()
	names.sort()
	print("total files: ", names.size())
	var rows := int(ceil(float(names.size()) / COLS))
	var sheet := Image.create(COLS * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.8, 0.2, 1.0))
	for i in names.size():
		var img := Image.load_from_file(DIR + names[i])
		img.resize(CELL, CELL, Image.INTERPOLATE_NEAREST)
		var col := i % COLS
		var row := i / COLS
		sheet.blend_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(col * CELL, row * CELL))
	sheet.save_png(OUT + "contact_sheet3.png")
	print("saved: ", COLS * CELL, "x", rows * CELL)
	quit(0)
