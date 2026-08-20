extends SceneTree
## Slices the 2026-07-20 UNDERDESK_sprite_asset_pack sheets straight into
## assets/art/ under their final key names. Unlike slice_grid.gd (which
## fights opaque backgrounds, divider lines and uneven grids), this pack
## is pre-transparent with exact uniform grids (verified: every sheet's
## pixel size divides evenly by its README grid), so slicing is: crop the
## exact cell -> crop again to the ROW's union content box (one shared
## box per row keeps all 8 frames aligned — per-frame trimming is the
## classic "膨張と収縮" pitfall, see CLAUDE.md) -> paste onto one shared
## canvas. Characters/enemies are bottom-aligned (feet stay planted);
## effects (impact/projectile) are centered. Projectiles keep their
## natural aspect (drawn aspect-fit in game); everything else is squared.

const SRC := "C:/Users/jinch/OneDrive/デスクトップ/UNDERDESK_sprite_asset_pack/"
const DST := "res://assets/art/"

## file -> [cols, cell_w, cell_h, [row names in order], mode]
## mode: "bottom" (characters/enemies, squared, bottom-aligned) or
## "center" (effects; squared for impacts), "aspect" (projectiles,
## natural aspect kept).
const SHEETS := [
	["01_enemies_hole_wanderer_lost_shadow.png", 8, 222, 222,
		["enemy_hole_wanderer", "enemy_hole_wanderer_hit",
		"enemy_lost_shadow", "enemy_lost_shadow_hit"], "bottom"],
	["02_enemies_guardian_pursuer_cave_troll.png", 8, 208, 237,
		["enemy_guardian_pursuer", "enemy_guardian_pursuer_hit",
		"enemy_cave_troll", "enemy_cave_troll_hit"], "bottom"],
	["03_impact_vfx_generic_fire_water_wind_light_dark.png", 8, 181, 181,
		["impact_generic", "impact_fire", "impact_water",
		"impact_wind", "impact_light", "impact_dark"], "center"],
	["04_projectiles_soul_break_yomotsu_hirasaka_dan.png", 8, 222, 444,
		["proj_soul_break", "proj_yomotsuhirasaka"], "aspect"],
	["10_enemies_attack.png", 8, 222, 222,
		["enemy_hole_wanderer_attack", "enemy_lost_shadow_attack",
		"enemy_guardian_pursuer_attack", "enemy_cave_troll_attack"], "bottom"],
	["11_enemies_defeat.png", 8, 222, 222,
		["enemy_hole_wanderer_defeat", "enemy_lost_shadow_defeat",
		"enemy_guardian_pursuer_defeat", "enemy_cave_troll_defeat"], "bottom"],
	["05_sotiris_hit_guard_victory.png", 8, 222, 296,
		["hit_minion_0", "guard_minion_0", "victory_minion_0"], "bottom"],
	["06_tsukuyo_madoka_hit_guard_victory.png", 8, 222, 296,
		["hit_minion_1", "guard_minion_1", "victory_minion_1"], "bottom"],
	["07_vard_strand_hit_guard_victory.png", 8, 222, 296,
		["hit_minion_2", "guard_minion_2", "victory_minion_2"], "bottom"],
	["08_shiba_yo_hit_guard_victory.png", 8, 222, 296,
		["hit_minion_3", "guard_minion_3", "victory_minion_3"], "bottom"],
	["09_sayu_hit_guard_victory.png", 8, 205, 321,
		["hit_minion_4", "guard_minion_4", "victory_minion_4"], "bottom"],
]


func _init() -> void:
	var saved := 0
	for sheet_def: Array in SHEETS:
		var fname: String = sheet_def[0]
		var cols: int = sheet_def[1]
		var cell_w: int = sheet_def[2]
		var cell_h: int = sheet_def[3]
		var row_names: Array = sheet_def[4]
		var mode: String = sheet_def[5]
		var sheet := Image.load_from_file(SRC + fname)
		if sheet == null:
			push_error("cannot load " + fname)
			quit(1)
			return
		sheet.convert(Image.FORMAT_RGBA8)
		if sheet.get_width() != cols * cell_w \
				or sheet.get_height() < row_names.size() * cell_h:
			push_error("%s: size %dx%d does not match grid %dx%d x %d rows" % [
				fname, sheet.get_width(), sheet.get_height(), cell_w, cell_h, row_names.size()])
			quit(1)
			return
		# Row bands measured from the sheet's own fully-transparent
		# horizontal runs, not the README's cell height: sheet 10's troll
		# row is drawn across the 666px grid line (figures at y610-808),
		# which put troll heads into the guardian row and left the troll
		# row itself with only legs and clubs. When the detected band
		# count matches, the real bands win; otherwise uniform fallback.
		var bands := _detect_sheet_bands(sheet, row_names.size(), cell_h)
		for r in row_names.size():
			var band: Vector2i = bands[r]
			# The README grid is authoritative only when the row actually
			# aligns to it. The troll rows are drawn on a ~220px pitch (7
			# figures, found via the contact-sheet audit: every "cell"
			# held halves of two neighboring figures), so each row's real
			# figure boundaries are measured from its fully-transparent
			# column runs; fewer-than-cols clean spans means slice by
			# those instead of the grid. Aligned rows (count == cols) and
			# scatter-effect rows (count > cols: one frame = several
			# disconnected fragments) keep the uniform grid.
			var spans := _detect_row_spans(sheet, band.x, band.y - band.x)
			# Misaligned means the README's grid boundaries land ON the
			# figures, not between them. A merely-touching pair of frames
			# on an otherwise aligned grid also yields < cols spans (one
			# merged span), but there most boundaries still fall in gaps —
			# only slice by spans when the majority of boundaries are
			# covered by content (the troll rows: all 7 boundaries are).
			var boundaries_on_content := 0
			for k in range(1, cols):
				var bx := k * cell_w
				for span: Vector2i in spans:
					if bx >= span.x and bx < span.y:
						boundaries_on_content += 1
						break
			var use_spans := spans.size() < cols and spans.size() >= cols - 2 \
				and boundaries_on_content * 2 > cols - 1
			match str(MODE_OVERRIDE.get("%s:%d" % [fname, r], "")):
				"spans":
					use_spans = true
				"uniform":
					use_spans = false
			var frame_rects: Array[Rect2i] = []
			if use_spans:
				print("  (%s row %d: %d detected spans, grid misaligned)" % [
					fname, r, spans.size()])
				for span: Vector2i in spans:
					frame_rects.append(Rect2i(span.x, band.x, span.y - span.x, band.y - band.x))
			else:
				for c in cols:
					frame_rects.append(Rect2i(c * cell_w, band.x, cell_w, band.y - band.x))
			var cells: Array[Image] = []
			var per_frame_center := use_spans
			if use_spans or mode != "bottom":
				for c in frame_rects.size():
					cells.append(sheet.get_region(frame_rects[c]))
			else:
				# Aligned figure rows still overflow their cells (lunging
				# arms/clubs reach 60+px into the neighbor cell — found on
				# the attack sheet's contact audit): split the whole row
				# band by connected-component OWNERSHIP instead. Each
				# component belongs to the cell its bbox center falls in,
				# so a neighbor's overflowing arm goes back to the
				# neighbor while this frame's own detached swipe/debris
				# stays — and overflowing content is kept WHOLE rather
				# than guillotined at the cell edge.
				cells = _split_row_by_ownership(sheet, band, cols, cell_w)
				per_frame_center = true
				# Two figures touching each other fuse into ONE component,
				# leaving the neighbor's frame empty — ownership can't
				# split a fused pair, so such rows keep the plain grid cut
				# (matching the pre-ownership behavior: minor mutual bleed
				# at the touch point instead of a missing frame).
				for c in cells.size():
					if cells[c].get_used_rect().size.x <= 0:
						print("  (%s row %d: fused figures, plain grid kept)" % [fname, r])
						cells.clear()
						for rect: Rect2i in frame_rects:
							cells.append(sheet.get_region(rect))
						per_frame_center = false
						break
			var used_rects: Array[Rect2i] = []
			var union := Rect2i()
			var union_set := false
			for c in cells.size():
				var used := cells[c].get_used_rect()
				used_rects.append(used)
				if used.size.x > 0 and used.size.y > 0:
					union = used if not union_set else union.merge(used)
					union_set = true
			if not union_set:
				push_error("%s row %d (%s): entirely empty" % [fname, r, row_names[r]])
				quit(1)
				return
			# Effect rows share ONE content box across all frames
			# (preserves inter-frame position shifts). Figure rows
			# (span-detected or ownership-split) have arbitrary per-frame
			# widths, so each frame keeps its own horizontal content
			# centered while everyone shares the same vertical band (feet
			# stay planted). Both paths give every frame of a clip an
			# identical canvas — per-frame trimming is the 膨張と収縮
			# pitfall.
			var canvas_w := union.size.x
			var canvas_h := union.size.y
			if per_frame_center:
				canvas_w = 0
				for used: Rect2i in used_rects:
					canvas_w = maxi(canvas_w, used.size.x)
			if mode != "aspect":
				canvas_w = maxi(canvas_w, canvas_h)
				canvas_h = canvas_w
			for c in cells.size():
				var content: Image
				var content_size: Vector2i
				if per_frame_center:
					var used := used_rects[c]
					if used.size.x <= 0:
						# Keep the frame numbering contiguous even if a
						# frame somehow owns nothing: save a blank canvas.
						content = null
						content_size = Vector2i.ZERO
					else:
						content = cells[c].get_region(Rect2i(
							used.position.x, union.position.y, used.size.x, union.size.y))
						content_size = Vector2i(used.size.x, union.size.y)
				else:
					content = cells[c].get_region(union)
					content_size = union.size
				var canvas := Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
				var x := (canvas_w - content_size.x) / 2
				var y := canvas_h - content_size.y if mode == "bottom" \
					else (canvas_h - content_size.y) / 2
				if content != null:
					canvas.blit_rect(
						content, Rect2i(Vector2i.ZERO, content_size), Vector2i(x, y))
				else:
					print("  WARNING: %s frame %d owned no content" % [row_names[r], c])
				var out_name := str(row_names[r]) if c == 0 else "%s_f%d" % [row_names[r], c + 1]
				var err := canvas.save_png(
					ProjectSettings.globalize_path(DST + out_name + ".png"))
				if err != OK:
					push_error("save failed: " + out_name)
					quit(1)
					return
				saved += 1
			print("%s row %d -> %s (%d frames, canvas %dx%d, content %s)" % [
				fname, r, row_names[r], cells.size(), canvas_w, canvas_h, union])
	print("DONE: %d files saved" % saved)
	quit(0)


## Figure spans (x_start, x_end_exclusive) of one row band, split on runs
## of >= MIN_GAP fully-transparent columns. Spans narrower than
## MIN_SPAN_W (stray dots that would inflate the count) are merged into
## whichever neighbor span sits closer.
const MIN_GAP := 3
const MIN_SPAN_W := 20

## "file:row" -> "spans" | "uniform". Visual rulings for the rows where
## the automatic misalignment test is wrong either way (checked frame by
## frame on green crops, 2026-07-20): sayu's victory row really is 7
## free-pitched figures but enough of them straddle grid boundaries to
## fool the majority test; the yomotsuhirasaka projectile row really is
## 8 aligned frames whose long trails touch each other into 6 merged
## spans.
const MODE_OVERRIDE := {
	"09_sayu_hit_guard_victory.png:2": "spans",
	"04_projectiles_soul_break_yomotsu_hirasaka_dan.png:1": "uniform",
}


## Content bands (y_start, y_end_exclusive) of the whole sheet, split on
## runs of >= 2 fully-transparent rows; sub-MIN_SPAN_W-tall stray bands
## merge into the nearer neighbor. Falls back to the uniform grid when
## the count disagrees with the expected row count.
func _detect_sheet_bands(sheet: Image, expected_rows: int, cell_h: int) -> Array[Vector2i]:
	var w := sheet.get_width()
	var h := sheet.get_height()
	var bands: Array[Vector2i] = []
	var start := -1
	var gap_run := 0
	for y in h + 1:
		var filled := false
		if y < h:
			for x in w:
				if sheet.get_pixel(x, y).a > 0.01:
					filled = true
					break
		if filled:
			if start == -1:
				start = y
			gap_run = 0
		else:
			gap_run += 1
			if start != -1 and (gap_run >= 2 or y >= h):
				bands.append(Vector2i(start, y - gap_run + 1))
				start = -1
	var i := 0
	while i < bands.size():
		if bands[i].y - bands[i].x >= MIN_SPAN_W or bands.size() == 1:
			i += 1
			continue
		var prev_gap := bands[i].x - bands[i - 1].y if i > 0 else 999999
		var next_gap := bands[i + 1].x - bands[i].y if i < bands.size() - 1 else 999999
		if prev_gap <= next_gap:
			bands[i - 1] = Vector2i(bands[i - 1].x, bands[i].y)
		else:
			bands[i + 1] = Vector2i(bands[i].x, bands[i + 1].y)
		bands.remove_at(i)
	if bands.size() == expected_rows:
		return bands
	var uniform: Array[Vector2i] = []
	for r in expected_rows:
		uniform.append(Vector2i(r * cell_h, (r + 1) * cell_h))
	return uniform


## Splits an aligned figure row into `cols` frame images by connected-
## component ownership: every component belongs to the cell its bbox
## center x falls in. Returned images are full-band-strip sized (caller
## crops each to its used rect); a component overflowing its cell stays
## whole in its owner's image instead of being cut at the cell edge or
## polluting the neighbor.
func _split_row_by_ownership(
		sheet: Image, band: Vector2i, cols: int, cell_w: int) -> Array[Image]:
	var w := sheet.get_width()
	var band_h := band.y - band.x
	var strip := sheet.get_region(Rect2i(0, band.x, w, band_h))
	var labels := PackedInt32Array()
	labels.resize(w * band_h)
	labels.fill(-1)
	var owners: Array[int] = []
	for y in band_h:
		for x in w:
			if labels[y * w + x] != -1 or strip.get_pixel(x, y).a <= 0.03:
				continue
			var label := owners.size()
			var min_x := x
			var max_x := x
			var members := PackedInt32Array()
			var stack := PackedInt32Array([y * w + x])
			labels[y * w + x] = label
			while stack.size() > 0:
				var idx := stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				members.append(idx)
				var px := idx % w
				@warning_ignore("integer_division")
				var py := idx / w
				min_x = mini(min_x, px)
				max_x = maxi(max_x, px)
				for offset: Vector2i in [
						Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := px + offset.x
					var ny := py + offset.y
					if nx < 0 or ny < 0 or nx >= w or ny >= band_h:
						continue
					var nidx := ny * w + nx
					if labels[nidx] == -1 and strip.get_pixel(nx, ny).a > 0.03:
						labels[nidx] = label
						stack.append(nidx)
			owners.append(clampi((min_x + max_x) / 2 / cell_w, 0, cols - 1))
	var cell_imgs: Array[Image] = []
	for c in cols:
		cell_imgs.append(Image.create(w, band_h, false, Image.FORMAT_RGBA8))
	for y in band_h:
		for x in w:
			var label := labels[y * w + x]
			if label != -1:
				cell_imgs[owners[label]].set_pixel(x, y, strip.get_pixel(x, y))
	return cell_imgs


func _detect_row_spans(sheet: Image, y0: int, band_h: int) -> Array[Vector2i]:
	var w := sheet.get_width()
	var occupied := PackedByteArray()
	occupied.resize(w)
	for x in w:
		occupied[x] = 0
		for y in range(y0, mini(y0 + band_h, sheet.get_height())):
			if sheet.get_pixel(x, y).a > 0.01:
				occupied[x] = 1
				break
	var spans: Array[Vector2i] = []
	var start := -1
	var gap_run := 0
	for x in w + 1:
		var filled: bool = x < w and occupied[x] == 1
		if filled:
			if start == -1:
				start = x
			# A sub-MIN_GAP hole never closed the span below, so an open
			# span just continues here.
			gap_run = 0
		else:
			gap_run += 1
			if start != -1 and (gap_run >= MIN_GAP or x >= w):
				spans.append(Vector2i(start, x - gap_run + 1))
				start = -1
	# Merge stray-dot spans into the nearer neighbor.
	var i := 0
	while i < spans.size():
		if spans[i].y - spans[i].x >= MIN_SPAN_W or spans.size() == 1:
			i += 1
			continue
		var prev_gap := spans[i].x - spans[i - 1].y if i > 0 else 999999
		var next_gap := spans[i + 1].x - spans[i].y if i < spans.size() - 1 else 999999
		if prev_gap <= next_gap:
			spans[i - 1] = Vector2i(spans[i - 1].x, spans[i].y)
		else:
			spans[i + 1] = Vector2i(spans[i].x, spans[i + 1].y)
		spans.remove_at(i)
	return spans
