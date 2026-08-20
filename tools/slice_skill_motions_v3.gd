extends SceneTree
## Slices the skill-motion delivery (12 frames/skill, uniform 222x222 grid)
## into assets/art/, replacing the existing skill_minion_<variant>_<suffix>
## clips in place.
##
## History: v1 did a plain per-cell crop (shrunk characters — v3 cells have
## padding other 128x128-edge-to-edge sprites don't). v2 tried several
## "shared crop window across a clip" schemes (union of cast frames, then a
## core/outlier-filtered union) to keep frame-to-frame scale consistent —
## every version still left some skills shrunk. v3 (2026-07-22) abandoned
## shared windows for independent per-frame tight crops, verified clean via
## a crop-boundary review — but a *uniform* per-frame crop still means
## different frames of the same clip are different pixel sizes, and
## _draw_party_row was stretching each one into the same fixed icon_px box,
## so the character's apparent size still flickered frame to frame within
## a single cast (the "サイズが小さくなってる" complaint, still unresolved
## after v3's own re-verification round).
##
## v4 (2026-07-22, delivered pre-sliced by the user — this script mirrors
## their slice_skill_motions_fixed.gd so future re-slices from the source
## sheets stay reproducible): stop cropping entirely. Every frame is saved
## as the FULL, unmodified 222x222 source cell — no get_used_rect(), no
## resize, no per-frame variation of any kind. Character scale and
## cell-relative position are exactly what the source art authored, and
## are IDENTICAL across all 12 frames of a clip by construction (same
## canvas, untouched), so there is nothing left to flicker.
##
## This moves the actual fix to the draw site instead: main.gd's
## _draw_party_row no longer fits these textures into icon_px like the
## 128x128 sprites. It scales/anchors the whole 222x222 canvas by a
## per-character constant (SKILL_MOTION_REF_CONTENT_H / _BOTTOM, measured
## once from each character's calmest reference frame) so the character
## renders at the same apparent size as their idle/attack sprites, with
## feet landing on the formation's ground line regardless of how much
## transparent padding a given frame has below them. See that constant's
## doc comment in main.gd for the full reasoning.

const SRC := "C:/Users/jinch/OneDrive/デスクトップ/仲間全員_スキルモーション_v3_12frames_ClaudeCode用/final/"
const DST := "res://assets/art/"
const COLS := 12
const CELL := 222

## variant, source file, [suffix per row in skills_by_row order].
const SHEETS := [
	[0, "ソティリス_スキルモーション_v3_12frames.png",
		["rapidslash", "healing", "soulbreak", "eosburst"]],
	[1, "月夜円_スキルモーション_v3_12frames.png",
		["shuneizan", "gekkarambu", "tsukuyomi", "yomogun", "yomotsuhirasaka"]],
	[2, "ヴァルド・ストランド_スキルモーション_v3_12frames.png",
		["heil", "liv", "skjaldborg", "heitskjold"]],
	[3, "司馬燿_スキルモーション_v3_12frames.png",
		["genkafu", "jubaku", "jumon", "shiigyaku"]],
	[4, "サユ_スキルモーション_v3_12frames.png",
		["shoukon", "kagura", "hyoui", "chinkon"]],
]


func _init() -> void:
	var saved := 0
	for sheet_def: Array in SHEETS:
		var variant: int = sheet_def[0]
		var fname: String = sheet_def[1]
		var suffixes: Array = sheet_def[2]
		var sheet := Image.load_from_file(SRC + fname)
		if sheet == null:
			push_error("cannot load " + fname)
			quit(1)
			return
		sheet.convert(Image.FORMAT_RGBA8)
		var expected_w := COLS * CELL
		var expected_h := suffixes.size() * CELL
		if sheet.get_width() != expected_w or sheet.get_height() != expected_h:
			push_error("%s: size %dx%d != expected %dx%d (%d rows)" % [
				fname, sheet.get_width(), sheet.get_height(),
				expected_w, expected_h, suffixes.size()])
			quit(1)
			return
		for row in suffixes.size():
			var suffix: String = suffixes[row]
			for col in COLS:
				# Preserve the complete source cell and its transparent
				# padding — no crop, no resize.
				var out_frame := sheet.get_region(Rect2i(col * CELL, row * CELL, CELL, CELL))
				var out_name := "skill_minion_%d_%s" % [variant, suffix]
				if col > 0:
					out_name += "_f%d" % (col + 1)
				var err := out_frame.save_png(ProjectSettings.globalize_path(DST + out_name + ".png"))
				if err != OK:
					push_error("save failed: " + out_name)
					quit(1)
					return
				saved += 1
	print("DONE: %d fixed 222x222 frames saved" % saved)
	quit(0)
