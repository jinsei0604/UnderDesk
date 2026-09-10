extends Node2D

## 氷属性の老執事の必殺技(butler_grand_ice)着弾フィニッシュ。
## rbm_hero_fire_finish.gdと同じ手法(px/poly/stroke、外部からageを渡される
## だけのNode2D)を踏襲するが、シルエット・色・段階構成は氷専用
## (「凍結→静止→破砕」、炎の「収束→白熱→爆発」とは別の個性)。

var age := -1.0
var floor_point := Vector2.ZERO
var canvas_size := Vector2(1280, 720)

const INK = Color('#16233a')
const DEEP = Color('#28587f')
const ICE = Color('#4fa3d1')
const FROST = Color('#a9e3f2')
const SHINE = Color('#eafeff')
const WHITE = Color('#ffffff')

# Authored silhouettes (alternating x,y, relative to origin) — each shape is
# hand-designed and distinct, never a rotated/scaled clone of another. Scale
# matches fire's own finish (coordinates spanning roughly ±300px at extent 1)
# so the fully-grown ice mass reads as large on a 1280x720 canvas.
#
# Cracks: fissures that run ACROSS the forming ice mass's own surface, not
# free-floating lines in open air. Each is a trunk (one bend) plus a branch
# sprouting from partway along the trunk — an irregular branching split, not
# a straight ray and not a zigzag. Kept short enough to stay within the ice
# mass silhouette below. A tiny icicle buds where each trunk finishes.
const CRACKS := [
	{"trunk": [0, 0, 34, -66, 22, -148], "branch": [34, -66, 92, -104]},
	{"trunk": [0, 0, -40, -58, -28, -140], "branch": [-40, -58, -98, -88]},
	{"trunk": [0, 0, 78, 14, 162, 32], "branch": [78, 14, 122, -38]},
	{"trunk": [0, 0, -82, 18, -168, 14], "branch": [-82, 18, -128, -32]},
	{"trunk": [0, 0, 18, 60, 12, 122], "branch": []},
]
const ICICLE_TIP = [-8, 10, -3, -26, 6, -34, 9, -4, 4, 12]

# Angular ice spikes: long thin pointed shards jutting outward from the
# target at different lengths/angles — the "surrounds the boss" silhouette,
# never a repeated rotated copy (each has its own proportions). Lengths and
# angles are deliberately uneven and lean off-axis (not a symmetric dome):
# the tall centre spike leans slightly, low spikes dig outward at ground
# level, and small notch spikes break up the outer silhouette between them.
const SPIKE_TALL = [-18, 20, -38, -46, -18, -172, 14, -244, 40, -200, 30, -64, 44, 20]
const SPIKE_UPRIGHT = [-10, 16, 30, -20, 52, -118, 84, -176, 90, -102, 48, -8]
const SPIKE_LEFT = [10, -14, -50, -36, -160, -46, -226, -16, -170, 10, -58, 20]
const SPIKE_RIGHT = [-8, -18, 58, -52, 178, -88, 234, -30, 170, 18, 50, 24]
const SPIKE_LOW_LEFT = [16, -10, -24, 26, -108, 98, -136, 150, -94, 116, -22, 46]
const SPIKE_LOW_RIGHT = [-16, -10, 40, 24, 114, 68, 158, 128, 92, 96, 24, 40]
const SPIKE_SMALL_A = [-8, 10, -22, -18, -4, -70, 14, -84, 22, -32, 14, 12]
const SPIKE_SMALL_B = [8, 10, 26, -10, 46, -58, 32, -74, 4, -34, -6, 8]
const NOTCH_A = [-6, 8, -14, -20, 2, -30, 10, -6]
const NOTCH_B = [6, 8, 16, -16, 0, -26, -8, -4]

const FROST_HALO = [-84, 26, -132, -58, -66, -158, 22, -172, 118, -134, 150, -40, 108, 32, 4, 58]

# Body-wrap ice: hugs the target's own silhouette at the sides and feet, so
# the whole figure reads as frozen rather than an ice mass merely piled on
# top of it. Positioned from floor_point directly (the target's own base),
# not from the tall-spike centre above.
const SIDE_ICE_L = [10, 10, -34, -20, -56, -78, -30, -138, 12, -112, 20, -46]
const SIDE_ICE_R = [-10, 10, 30, -14, 50, -70, 34, -132, -6, -104, -16, -40]
const FOOT_ICE_L = [-8, 6, -30, -4, -46, -22, -24, -30, -2, -18]
const FOOT_ICE_R = [8, 6, 26, -6, 40, -24, 20, -30, 0, -16]

# Shatter fragments: irregular triangles, needles and off-kilter chunks --
# never a rectangle/board silhouette. Large, medium and fine tiers are each
# their own distinct shape, not a scaled copy of one another.
const SHARD_TRI_A = [-8, -96, 22, -18, -34, 30]
const SHARD_TRI_B = [10, -84, 30, 20, -26, 8]
const SHARD_NEEDLE_A = [-6, -78, 4, -70, 10, 24, -12, 16]
const SHARD_NEEDLE_B = [6, -66, -4, -58, -10, 20, 10, 12]
const SHARD_CHUNK_A = [-20, -40, 14, -48, 30, -6, 8, 24, -26, 10]
const SHARD_CHUNK_B = [18, -36, -12, -44, -28, -4, -4, 22, 24, 8]
const SHARD_SMALL = [-14, -30, 6, -34, 12, 6, -10, 16]
const ICE_DUST_A = [-4, -18, 3, -16, 6, 6, -3, 10]
const ICE_DUST_B = [4, -16, -3, -14, -6, 6, 3, 9]

# Ground shockwave: a HANDFUL of uneven, flat angular wedges digging outward
# along the ground right as the ice breaks -- not a ring, not a circle, not
# thin radiating lines. This is what carries "the ice shattered with real
# force", distinct from the flash and from the flying shards above it.
const SHOCK_WEDGE_A = [-12, 6, 66, -10, 78, 2, 16, 12]
const SHOCK_WEDGE_B = [10, 6, -58, -12, -70, 0, -14, 12]
const SHOCK_WEDGE_C = [-8, 4, 40, -18, 52, -4, 10, 10]

func px(p: Vector2, s: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.snapped(Vector2(4, 4)), s.max(Vector2(4, 4)).snapped(Vector2(4, 4))), c)

func poly(points: Array, c: Color) -> void:
	var lo := 4096.0
	var hi := -4096.0
	for p in points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	for y in range(mini(0, int(lo / 4) * 4), maxi(int(canvas_size.y), int(hi) + 4), 4):
		var xs: Array[float] = []
		for i in range(points.size()):
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % points.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for i in range(0, xs.size() - 1, 2):
			px(Vector2(xs[i], y), Vector2(xs[i + 1] - xs[i], 4), c)

func stroke(a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var n: Vector2 = (b - a).normalized().orthogonal() * w * .5
	poly([a + n, b + n, b - n, a - n], c)

## Grows a polyline (trunk or branch) from its start point out to `growth`
## segments (fractional), returning the current tip so a branch/icicle can
## anchor to it. Shared by every crack in CRACKS.
func grow_path(points: Array, growth: float, width: float, color: Color, origin: Vector2) -> Vector2:
	var count := points.size() / 2
	var reach := clampf(growth, 0, float(count - 1))
	var tip := origin + Vector2(points[0], points[1])
	for seg in range(count - 1):
		var seg_u := clampf(reach - float(seg), 0, 1)
		if seg_u <= 0:
			break
		var a := origin + Vector2(points[seg * 2], points[seg * 2 + 1])
		var full_b := origin + Vector2(points[(seg + 1) * 2], points[(seg + 1) * 2 + 1])
		var b := a.lerp(full_b, seg_u)
		stroke(a, b, width, color)
		tip = b
	return tip

## Soft, gently rounded silhouette — reserved for the low, ground-hugging
## frost halo and the body-wrap ice. Corner-smoothing technique shared with
## rbm_hero_fire_finish.gd's generic sheet() (a geometry utility, not
## fire-specific), but ice's own crystal spikes/shatter pieces never use it.
func mass(coords: Array, origin: Vector2, extent: float, color: Color) -> void:
	var points: Array = []
	for i in range(0, coords.size(), 2):
		points.append(origin + Vector2(coords[i], coords[i + 1]) * extent)
	var contour: Array = []
	for i in range(points.size()):
		var p: Vector2 = points[i]
		var back: Vector2 = points[(i - 1 + points.size()) % points.size()] - p
		var ahead: Vector2 = points[(i + 1) % points.size()] - p
		if back.normalized().dot(ahead.normalized()) > .5:
			contour.append(p)
		else:
			var a := p + back.normalized() * minf(8 * extent, back.length() * .18)
			var b := p + ahead.normalized() * minf(8 * extent, ahead.length() * .18)
			for k in range(4):
				var u := float(k) / 3
				contour.append(a * (1 - u) * (1 - u) + p * 2 * u * (1 - u) + b * u * u)
	poly(contour, color)

## Hard angular silhouette, no corner-rounding at all — every vertex stays a
## crisp point. This is ice's own visual signature versus fire's rounder
## sheet(): crystal spikes and shatter fragments must read as sharp, faceted,
## never melted/soft.
func shard(coords: Array, origin: Vector2, extent: float, color: Color, rot: float = 0.0) -> void:
	var points: Array = []
	for i in range(0, coords.size(), 2):
		var p := Vector2(coords[i], coords[i + 1])
		if rot != 0.0:
			p = p.rotated(rot)
		points.append(origin + p * extent)
	poly(points, color)

func _shake(strength: float) -> Vector2:
	if strength <= 0:
		return Vector2.ZERO
	return Vector2(sin(age * 311.0), cos(age * 257.0)) * strength

func _draw() -> void:
	if age < 0 or age > 2.4:
		return
	var base_center := floor_point + Vector2(0, -110)

	# --- Phase 0 (0.00-0.05): sharp contact instant. A short, small, plain
	# flash -- the hit is felt, but the moment must not upstage the freeze
	# and shatter that follow.
	if age < 0.05:
		var flash_fade := 1.0 - age / 0.05
		px(base_center, Vector2(46, 46) * flash_fade, SHINE * Color(1, 1, 1, 0.85))

	# --- Phase 1+2 (0.03-1.02): the target freezes solid. Body-wrap ice
	# closes in at the sides/feet, angular spikes grow around the centre,
	# and cracks race across that forming surface (not through empty air).
	# Never the same silhouette twice, never a rotated clone.
	if age >= 0.03 and age < 1.02:
		var strength := clampf((age - 0.03) / 0.30, 0, 1)
		var grown := 1 - pow(1 - strength, 2)
		mass(FROST_HALO, base_center + Vector2(8, 4), 0.5 + grown * 0.85, DEEP)
		mass(SIDE_ICE_L, floor_point, grown, ICE)
		mass(SIDE_ICE_R, floor_point, grown, ICE)
		mass(FOOT_ICE_L, floor_point, grown, DEEP)
		mass(FOOT_ICE_R, floor_point, grown, DEEP)
		shard(SPIKE_LEFT, base_center + Vector2(10, 30), grown, DEEP)
		shard(SPIKE_RIGHT, base_center + Vector2(-6, 24), grown, ICE, -0.06)
		shard(SPIKE_LOW_LEFT, base_center + Vector2(20, 10), grown, FROST)
		shard(SPIKE_LOW_RIGHT, base_center + Vector2(-14, 6), grown, DEEP)
		shard(SPIKE_UPRIGHT, base_center + Vector2(-64, 6), grown, ICE, 0.08)
		shard(SPIKE_SMALL_A, base_center + Vector2(78, -34), grown, FROST, 0.15)
		shard(SPIKE_SMALL_B, base_center + Vector2(-102, -18), grown, ICE, -0.12)
		shard(NOTCH_A, base_center + Vector2(-40, -96), grown, FROST)
		shard(NOTCH_B, base_center + Vector2(56, -70), grown, FROST)
		shard(NOTCH_A, base_center + Vector2(130, 30), grown, ICE, 0.6)
		shard(NOTCH_B, base_center + Vector2(-150, 44), grown, FROST, -0.5)
		shard(SPIKE_TALL, base_center, grown, SHINE, -0.05)

		# --- Cracks: drawn on top of the mass above, growing across its
		# surface. Each trunk bends once and sprouts one irregular branch --
		# never a straight ray, never a zigzag chain.
		if age >= 0.08:
			var crack_u := clampf((age - 0.08) / 0.30, 0, 1)
			var crack_grow := 1 - pow(1 - crack_u, 3)
			for crack in CRACKS:
				var trunk: Array = crack["trunk"]
				var branch: Array = crack["branch"]
				var tip := grow_path(trunk, crack_grow * float(trunk.size() / 2 - 1), 3.0, FROST, base_center)
				if not branch.is_empty():
					grow_path(branch, crack_grow * float(branch.size() / 2 - 1), 2.5, FROST, base_center)
				if crack_grow >= 0.999:
					var dir := (tip - base_center).normalized()
					shard(ICICLE_TIP, tip, 0.9, ICE, dir.angle() + PI / 2)

		# --- The "fully frozen" beat: the centre spike briefly brightens to
		# white right as growth completes and holds through the static
		# window -- the moment that reads as "completely frozen", distinct
		# from both the growth above and the shatter flash below. No extra
		# sparkle lines -- brightness alone carries the beat.
		if age >= 0.46 and age < 0.62:
			var glint := clampf(1.0 - absf(age - 0.52) / 0.12, 0, 1)
			shard(SPIKE_TALL, base_center, grown, WHITE.lerp(SHINE, 1.0 - glint), -0.05)

	# --- Phase 4 (0.72-0.80): the shatter instant. Full-canvas flash.
	if age >= 0.72 and age < 0.80:
		px(Vector2.ZERO, canvas_size, Color(0.88, 0.98, 1.0, 0.94))

	# --- Phase 4.5 (0.76-0.98): a short ground shockwave. A handful of
	# uneven flat wedges dig outward along the ground at a few unevenly
	# spaced angles -- deliberately NOT a ring/circle and NOT thin radiating
	# lines. This is what sells "shattered with real force" the instant
	# before the flying debris takes over.
	if age >= 0.76 and age < 0.98:
		var su := clampf((age - 0.76) / 0.14, 0, 1)
		var sgrow := 1 - pow(1 - su, 2)
		var sfade := clampf((0.98 - age) / 0.22, 0, 1)
		var stint := Color(1, 1, 1, sfade)
		shard(SHOCK_WEDGE_A, floor_point + Vector2(-10, 2), sgrow, FROST * stint, -0.10)
		shard(SHOCK_WEDGE_B, floor_point + Vector2(20, 4), sgrow * 0.85, ICE * stint, 0.16)
		shard(SHOCK_WEDGE_C, floor_point + Vector2(-46, 6), sgrow * 0.7, FROST * stint, -0.6)
		shard(SHOCK_WEDGE_A, floor_point + Vector2(38, 8), sgrow * 0.6, ICE * stint, 2.4)

	# --- Phase 5 (0.74-2.05): the ice explodes with real force. Large
	# pieces fly first, fast and far; a much bigger swarm of fine ice dust
	# trails a beat behind, chasing them out; everything follows the same
	# directions the cracks etched into the surface, so the break reads as
	# following those fissures. No round burst, no extra radiating lines,
	# no stars -- the sheer quantity and speed of angular ice IS the
	# "explosion". A small handful of pieces stay bright; most are the base
	# ICE/DEEP/FROST tones.
	if age >= 0.74 and age < 2.05:
		var shake := _shake(clampf((0.92 - age) / 0.20, 0, 1) * 16.0)
		var center := base_center + shake
		var t := age - 0.74
		var fade := clampf((2.05 - age) / 0.9, 0, 1)
		var tint := Color(1, 1, 1, fade)
		# Directions taken from each crack's own far endpoint -- the shatter
		# breaks along the same lines the cracks etched into the surface.
		var crack_dirs: Array = []
		for crack in CRACKS:
			var trunk: Array = crack["trunk"]
			var end := Vector2(trunk[trunk.size() - 2], trunk[trunk.size() - 1])
			crack_dirs.append(end.normalized())
		var launches = [
			[SHARD_TRI_A, crack_dirs[0] * 480, 1.7, ICE],
			[SHARD_TRI_B, crack_dirs[1] * 460, 1.6, DEEP],
			[SHARD_NEEDLE_A, crack_dirs[2] * 440, 1.5, FROST],
			[SHARD_NEEDLE_B, crack_dirs[3] * 440, 1.5, ICE],
			[SHARD_CHUNK_A, crack_dirs[4] * 400, 1.4, DEEP],
			[SHARD_CHUNK_B, Vector2(-340, -220), 1.4, FROST],
			[SHARD_TRI_A, Vector2(320, -260), 1.6, SHINE],
			[SHARD_TRI_B, Vector2(-300, 140), 1.5, ICE],
			[SHARD_NEEDLE_B, Vector2(300, 160), 1.5, DEEP],
			[SHARD_SMALL, Vector2(-380, 70), 1.3, FROST],
			[SHARD_SMALL, Vector2(380, 100), 1.3, ICE],
			[SHARD_NEEDLE_A, Vector2(-80, -400), 1.6, SHINE],
			[SHARD_CHUNK_A, Vector2(140, -360), 1.4, FROST],
			[SHARD_CHUNK_B, Vector2(-160, -340), 1.4, ICE],
		]
		for i in range(launches.size()):
			var shape: Array = launches[i][0]
			var dir: Vector2 = launches[i][1]
			var speed: float = launches[i][2]
			var color: Color = launches[i][3]
			var dt := maxf(0.0, t - float(i % 4) * 0.015)
			var travel := dir * dt * speed
			var p := center + travel + Vector2(0, 340 * dt * dt)
			if p.y > floor_point.y + 50:
				continue
			shard(shape, p, 1.3, color * tint, dt * (1.9 if i % 2 == 0 else -1.6))
		# Fine ice dust: a much larger swarm of small angular chips, never a
		# star/cross silhouette, launched a beat AFTER the big pieces above
		# so it visibly chases them outward rather than moving in lockstep.
		for i in range(32):
			var a := float(i) * 2.399
			var delay := 0.10 + float(i % 8) * 0.03
			var dt2 := maxf(0.0, t - delay)
			var v := Vector2(cos(a) * (260 + i % 7 * 50), sin(a) * (190 + i % 5 * 38) - 90)
			var p2 := center + v * dt2 + Vector2(0, 280 * dt2 * dt2)
			if p2.y > floor_point.y + 36:
				continue
			var s := 0.6 + float(i % 3) * 0.24
			var dust_color: Color = [ICE, FROST, DEEP, ICE][i % 4]
			var dust_shape := ICE_DUST_A if i % 2 == 0 else ICE_DUST_B
			shard(dust_shape, p2, s, dust_color * tint, dt2 * (2.2 if i % 2 == 0 else -1.8))

	# --- Phase 6 (1.9-2.4): no ice debris left behind on the ground -- only
	# cold mist and a few very fine particles linger briefly, then clear.
	if age >= 1.9:
		var fade2 := clampf((2.4 - age) / 0.5, 0, 1)
		var tint2 := Color(1, 1, 1, fade2)
		for i in range(10):
			px(floor_point + Vector2(-130 + i * 30, -8 - (i % 3) * 10), Vector2(4, 4), SHINE * tint2)
