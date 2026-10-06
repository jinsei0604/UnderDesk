extends RefCounted
## Approved review timings, in seconds. Pure presentation; no combat RNG/state.
const DURATIONS := {"single":7.2, "all":7.4, "awakening":11.0, "planet":9.0, "blackhole":7.2, "buff":3.0, "heal":3.0}
const IMPACTS := {"single":3.27, "all":3.25, "awakening":6.45, "planet":4.15, "blackhole":5.12, "buff":1.7, "heal":1.7}
const SUCTION_START := 2.65
const SUCTION_END := 4.75
const RIFT_CONCEPT := "A"

static func pose(kind: String, t: float, awakened: bool) -> int:
	if kind == "blackhole":
		if t < .44: return 1 # wrist console
		if t < 1.15: return 2 # two palms aim
		if t < 1.95: return 3 # separate both hands / open seam
		if t < 2.27: return 4 # fold the space inward
		if t < 3.65: return 5 # hold the new gravity well
		if t < 4.86: return 4
		if t < 5.64: return 6 # both palms close; never a punch
		return 5 if t < 6.5 else 0
	if kind == "awakening": return 0 if t < 1.15 or t >= 6.45 else 2
	if kind in ["buff", "heal"]: return 1 if .35 < t and t < 2.5 else 0
	if awakened: return 0
	return 1 if .45 < t and t < 4.0 else 0

static func pull(t: float) -> float:
	if t < SUCTION_START: return 0.0
	if t < SUCTION_END: return .065 + .865 * pow((t-SUCTION_START)/(SUCTION_END-SUCTION_START), 2.7)
	if t < 4.86: return .93
	if t < 5.12: return lerpf(.93, 1.0, smoothstep(4.86, 5.12, t))
	return 1.0 - smoothstep(5.12, 5.77, t)

static func radius(t: float) -> float:
	if t < 2.20: return 0.0
	if t < 2.38: return lerpf(.65, 4.2, smoothstep(2.20, 2.38, t))
	if t < 2.65: return lerpf(4.2, 21.3, smoothstep(2.38, 2.65, t))
	if t < 3.30: return lerpf(21.3, 39.0, smoothstep(2.65, 3.30, t))
	if t < 4.12: return 39.0
	if t < 4.75: return lerpf(39.0, 31.0, smoothstep(4.12, 4.75, t))
	if t < 4.86: return 31.0
	if t < 5.12: return lerpf(31.0, .4, smoothstep(4.86, 5.12, t))
	return 0.0

static func shake(kind: String, t: float) -> Vector2:
	var amplitude := 0.0
	var dt := t - float(IMPACTS[kind])
	if kind == "blackhole":
		if 2.65 < t and t < 4.75: amplitude = 2.0 * pow((t-2.65)/2.1, 3)
		if 4.86 < t and t < 5.12: amplitude = 4.0 * smoothstep(4.86, 5.12, t)
		if 0 <= dt and dt < .98: amplitude = 9.0 * exp(-dt*3.4)
	elif kind == "awakening":
		amplitude = 6.0 * smoothstep(3.5, 6.25, t) if dt < 0 else 18.0 * exp(-dt*2.5)
	elif kind == "planet":
		amplitude = 6.0 * smoothstep(.75, 3.2, t) if dt < 0 else 18.0 * exp(-dt*2.9)
	elif kind in ["single", "all"] and dt >= 0:
		amplitude = (7.0 if kind == "single" else 13.0) * exp(-dt*3.5)
	return Vector2(sin(t*145), cos(t*173)*.67) * amplitude
