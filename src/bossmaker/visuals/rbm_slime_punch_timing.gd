extends RefCounted
# Compress the travel, preserving the resolved hit and recovery.
const RELEASE := 0.78
const HIT := 0.91
const ORIGINAL_RELEASE := 0.57

static func pose_time(t: float) -> float:
	if t < ORIGINAL_RELEASE or t >= HIT:
		return t
	var progress := clampf((t - RELEASE) / (HIT - RELEASE), 0.0, 1.0)
	return lerpf(ORIGINAL_RELEASE, HIT, progress)
