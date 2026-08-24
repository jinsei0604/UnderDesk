extends Node

## UNDERDESK / Eos Burst v28 reference implementation.
##
## This revision removes the cut-in completely and keeps the approved slash,
## impact and outer art byte-identical. Frames 6..10 preserve the reference
## video's loaded apex and body mechanics, then carry the blade over the head
## so the true downslash remains in front of Sotiris.
## Adapt node paths, but keep these contracts:
## - character, sword aura, slash, impact and burst are process-frame driven;
## - no phase waits for the preceding visual to disappear before it may begin;
## - no cut-in texture, node, signal, timer or call exists in the v28 path;
## - the aura is attached to the authored blade segment for every pose and has
##   no ground ring or body-sized pillar;
## - Sotiris uses complementary ordered-dither transitions at full opacity;
##   translucent whole-character crossfades are forbidden;
## - one fixed scale is calibrated from the visible idle-frame height and one
##   foot anchor is reused for all seventeen motion cells;
## - MotionA and MotionB are dedicated Sprite2D nodes, rendered twenty Z units
##   above the ordinary sprite; visibility and frame are reasserted each draw;
## - the approved horizontal slash remains level and stops at enemy centre;
## - the one-second legacy prelude wait is removed;
## - slash->impact, contact flash and impact->burst share one clock, with no
##   blank frame or delayed flash;
## - imported textures stay Nearest/Lossless; runtime filtering/resampling is forbidden.

const SOTIRIS_MOTION_TEXTURE := preload("res://assets/vfx/eos_burst/v28/assets/sotiris_eos_downslash_17f_frontside_v28.png")
const DITHER_SHADER := preload("res://assets/vfx/eos_burst/v28/godot/sprite_dither_v28.gdshader")

const SWORD_AURA_TEXTURES: Array[Texture2D] = [
	preload("res://assets/vfx/eos_burst/v28/frames/sword_blade_aura_v21/aura_00.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/sword_blade_aura_v21/aura_01.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/sword_blade_aura_v21/aura_02.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/sword_blade_aura_v21/aura_03.png"),
]

const MAIN_TEXTURES: Array[Texture2D] = [
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_00.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_01.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_02.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_03.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_04.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_05.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_07.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/grand_crescent_v12_tip_locked/grand_08.png"),
]

const IMPACT_TEXTURES: Array[Texture2D] = [
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_00.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_01.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_02.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_03.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_04.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_05.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_06.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_07.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_08.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_09.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_10.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/enemy_crossflash_v8/crossflash_11.png"),
]

## outer_08 is intentionally absent: it is the unwanted pale circular tail.
const OUTER_TEXTURES: Array[Texture2D] = [
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_00.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_01.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_02.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_03.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_04.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_05.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_06.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_07.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_09.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_10.png"),
	preload("res://assets/vfx/eos_burst/v28/frames/burst_outer_v15_no_white_disc/outer_11.png"),
]

## v28 preserves v26's readable charge and accepted finish, removes the cut-in,
## and replaces only the five swing poses with a front-side weapon path.
## Together with the inherited low follow-through, the visible swing occupies
## 0.740s. Short intervals
## dither for at most 45 percent of their duration; longer holds retain the
## existing 0.080s cap.
const CHARACTER_FRAME_TIMES := [
	0.380, 0.360, 0.360, 0.380, 0.460, 0.600,
	0.180, 0.180, 0.100, 0.080, 0.080, 0.120,
	0.180, 0.160, 0.160, 0.200, 0.240,
]
const CHARACTER_DITHER_MAX := 0.080
const CHARACTER_DITHER_INTERVAL_RATIO := 0.45
const RELEASE_FRAME_INDEX := 12
const CHARACTER_RELEASE_TIME := 3.280
const MOTION_CELL_SIZE := Vector2(222.0, 222.0)
const MOTION_GROUND_SOURCE := Vector2(111.0, 214.0)
const MOTION_REFERENCE_BOUNDS := Rect2(54.0, 122.0, 113.0, 92.0)
const MOTION_SCALE_RATIO_MIN := 0.45
const MOTION_SCALE_RATIO_MAX := 1.15
const MOTION_Z_LOCK_OFFSET := 20

const SWORD_SEGMENTS: Array[Vector4] = [
	Vector4(106,165,54,191), Vector4(106,157,72,120),
	Vector4(108,154,69,103), Vector4(110,154,67,78),
	Vector4(110,154,74,64), Vector4(111,154,101,58),
	Vector4(110,128,110,69), Vector4(101,135,45,128),
	Vector4(119,124,157,78), Vector4(114,166,124,213),
	Vector4(112,177,154,211),
	Vector4(118,164,165,208), Vector4(119,165,177,205),
	Vector4(119,165,175,204), Vector4(120,169,177,206),
	Vector4(120,173,177,210), Vector4(119,162,159,191),
]
const SWORD_AURA_STAGE_TIMES := [0.450, 0.550, 0.700, 1.510]
const SWORD_AURA_BLEND_DURATION := 0.140
const SWORD_AURA_FADE_DURATION := 0.070
const SWORD_AURA_SOURCE_LENGTH := 126.0
const SWORD_AURA_CHILD_OFFSET := Vector2(-24.0, -140.0)
const SWORD_AURA_MAX_ALPHA := 0.86

## Start character/aura almost immediately after dimming. The latest build held
## a static battlefield for about one second; that legacy wait must be removed.
const BURST_LEAD_IN := 0.120

## Approved v18 slash timing and contact geometry are retained.
const MAIN_BUILD_TIMES := [0.055, 0.055, 0.060, 0.065, 0.070, 0.075, 0.080]
const MAIN_BUILD_DURATION := 0.460
const MAIN_TRAVEL_SPEED_PX_PER_SEC := 700.0
const MAIN_MIN_CONTACT_HOLD := 0.120
const MAIN_MIN_DURATION := 0.580
const MAIN_MAX_DURATION := 0.700
const MAIN_FRAME08_TIP_OFFSET_SOURCE_X := 198.735
const MAIN_EDGE_EASE_RATIO := 0.100
const MAIN_SCALE_MIN := 0.001

## Impact is process-frame crossfaded. It is slightly longer than v18's hard
## 0.24 s sequence so all twelve sources receive readable interpolation.
const IMPACT_FRAME_TIMES := [
	0.030, 0.030, 0.033, 0.033, 0.035, 0.038,
	0.040, 0.040, 0.038, 0.033, 0.027, 0.023,
]
const SLASH_TO_IMPACT_OVERLAP := 0.080
const IMPACT_ENTRY_MIN_ALPHA := 0.080
const OUTER_START_AFTER_CONTACT := 0.140
const IMPACT_TO_OUTER_OVERLAP := 0.260
const OUTER_ENTRY_FADE := 0.160

## The old global flash peaked late and almost washed the whole screen white.
## v28 preserves v21's accepted contact draw and flash exactly.
const CONTACT_FLASH_RISE := 0.050
const CONTACT_FLASH_FALL := 0.150
const CONTACT_FLASH_PEAK_ALPHA := 0.42

## Luminous VFX use a gamma-compensated crossfade so the midpoint does not
## look like a dim/bright flicker. Character art keeps ordinary alpha blending.
const VFX_CROSSFADE_GAMMA := 0.70

const OUTER_TIMES := [0.075, 0.0875, 0.100, 0.1125, 0.1375, 0.150, 0.175, 0.225, 0.175, 0.1375, 0.125]
const OUTER_ALPHA := [0.70, 0.82, 0.92, 1.00, 1.00, 1.00, 1.00, 0.98, 0.72, 0.42, 0.18]

## Alpha-weighted centroids of the unchanged approved slash PNGs.
const MAIN_PIVOTS: Array[Vector2] = [
	Vector2(604.836, 223.654),
	Vector2(616.036, 223.957),
	Vector2(639.637, 223.840),
	Vector2(629.025, 223.731),
	Vector2(609.844, 223.618),
	Vector2(592.873, 224.175),
	Vector2(554.140, 224.066),
	Vector2(537.265, 223.995),
]

signal release_frame_fully_visible
signal character_pose_finished
signal contact_flash_finished
signal outer_finished
signal finish_chain_completed

var _burst_running := false
var _release_draw_frame := -1
var _slash_first_visible_draw_frame := -1
var _slash_contact_draw_frame := -1
var _impact_first_visible_draw_frame := -1
var _outer_first_visible_draw_frame := -1
var _damage_apply_count := 0
var _original_sotiris_state: Dictionary = {}
var _calibrated_motion_scale := Vector2.ONE
var _motion_foot_anchor_parent := Vector2.ZERO
var _character_pose_complete := false


func _sum_times(times: Array) -> float:
	var result := 0.0
	for value in times:
		result += float(value)
	return result


func _smootherstep(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func _luminous_weights(mix_value: float) -> Vector2:
	## Gamma-compensated A/B weights retain perceived light energy without the
	## strong midpoint overexposure of a square-root crossfade.
	var mix := clampf(mix_value, 0.0, 1.0)
	return Vector2(
		pow(1.0 - mix, VFX_CROSSFADE_GAMMA),
		pow(mix, VFX_CROSSFADE_GAMMA)
	)


func _edge_smoothed_linear(value: float) -> float:
	## C1-continuous at t=0, edge, 1-edge and 1. The middle 80 percent
	## remains scalar Linear, so the horizontal slash does not become sluggish.
	var t := clampf(value, 0.0, 1.0)
	var edge := MAIN_EDGE_EASE_RATIO
	if t < edge:
		var u := t / edge
		return edge * (2.0 * u * u - u * u * u)
	if t > 1.0 - edge:
		var u := (1.0 - t) / edge
		return 1.0 - edge * (2.0 * u * u - u * u * u)
	return t


func _set_alpha(item: CanvasItem, alpha: float) -> void:
	item.self_modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))


func _clear_sprite(sprite: Sprite2D) -> void:
	sprite.texture = null
	sprite.visible = false
	_set_alpha(sprite, 0.0)


func _configure_plain_sprite(sprite: Sprite2D) -> void:
	sprite.centered = true
	sprite.region_enabled = false
	sprite.hframes = 1
	sprite.vframes = 1
	sprite.offset = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = true
	_set_alpha(sprite, 0.0)


func _snapshot_sprite(sprite: Sprite2D) -> Dictionary:
	return {
		"texture": sprite.texture,
		"hframes": sprite.hframes,
		"vframes": sprite.vframes,
		"frame": sprite.frame,
		"position": sprite.position,
		"scale": sprite.scale,
		"rotation": sprite.rotation,
		"skew": sprite.skew,
		"centered": sprite.centered,
		"offset": sprite.offset,
		"flip_h": sprite.flip_h,
		"flip_v": sprite.flip_v,
		"z_index": sprite.z_index,
		"material": sprite.material,
		"texture_filter": sprite.texture_filter,
		"visible": sprite.visible,
		"self_modulate": sprite.self_modulate,
	}


func _restore_sprite(sprite: Sprite2D, state: Dictionary) -> void:
	sprite.texture = state["texture"]
	sprite.hframes = state["hframes"]
	sprite.vframes = state["vframes"]
	sprite.frame = state["frame"]
	sprite.position = state["position"]
	sprite.scale = state["scale"]
	sprite.rotation = state["rotation"]
	sprite.skew = state["skew"]
	sprite.centered = state["centered"]
	sprite.offset = state["offset"]
	sprite.flip_h = state["flip_h"]
	sprite.flip_v = state["flip_v"]
	sprite.z_index = state["z_index"]
	sprite.material = state["material"]
	sprite.texture_filter = state["texture_filter"]
	sprite.visible = state["visible"]
	sprite.self_modulate = state["self_modulate"]


func _texture_frame_bounds(
	texture: Texture2D,
	hframes: int,
	vframes: int,
	frame_index: int
) -> Rect2:
	assert(texture != null)
	var image := texture.get_image()
	var columns := maxi(1, hframes)
	var rows := maxi(1, vframes)
	var cell_width := int(image.get_width() / columns)
	var cell_height := int(image.get_height() / rows)
	var frame_x := frame_index % columns
	var frame_y := int(frame_index / columns)
	assert(frame_y < rows)
	var cell := image.get_region(Rect2i(
		frame_x * cell_width, frame_y * cell_height, cell_width, cell_height
	))
	var used := cell.get_used_rect()
	assert(used.size.x > 0 and used.size.y > 0)
	return Rect2(Vector2(used.position), Vector2(used.size))


func _configure_motion_sprite(
	sprite: Sprite2D,
	original: Dictionary,
	motion_transform: Transform2D,
	reveal_next: bool
) -> void:
	sprite.texture = SOTIRIS_MOTION_TEXTURE
	sprite.hframes = 17
	sprite.vframes = 1
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	sprite.flip_h = bool(original["flip_h"])
	sprite.flip_v = bool(original["flip_v"])
	## Dedicated motion sprites must always render above the ordinary battle
	## sprite, even if another battle system makes that sprite visible again.
	sprite.z_index = int(original["z_index"]) + MOTION_Z_LOCK_OFFSET
	sprite.transform = motion_transform
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var dither_material := ShaderMaterial.new()
	dither_material.shader = DITHER_SHADER
	dither_material.set_shader_parameter("reveal_next", reveal_next)
	dither_material.set_shader_parameter("progress", 0.0)
	sprite.material = dither_material
	sprite.visible = true
	_set_alpha(sprite, 1.0)


func _enforce_motion_display_lock(
	original_sotiris: Sprite2D,
	motion_a: Sprite2D,
	motion_b: Sprite2D,
	frame_index: int,
	next_frame: int
) -> void:
	## The v27 in-game capture showed the ordinary idle sprite covering the
	## animated Eos sprite. Re-assert ownership every process frame and keep the
	## two dedicated motion sprites on a higher Z layer.
	var original_z := int(_original_sotiris_state["z_index"])
	original_sotiris.visible = false
	original_sotiris.z_index = original_z - MOTION_Z_LOCK_OFFSET
	_set_alpha(original_sotiris, 0.0)

	for sprite in [motion_a, motion_b]:
		sprite.texture = SOTIRIS_MOTION_TEXTURE
		sprite.hframes = 17
		sprite.vframes = 1
		sprite.z_index = original_z + MOTION_Z_LOCK_OFFSET
		sprite.visible = true
		_set_alpha(sprite, 1.0)
	motion_a.frame = frame_index
	motion_b.frame = next_frame


func _set_dither_progress(sprite: Sprite2D, progress: float) -> void:
	var dither_material := sprite.material as ShaderMaterial
	assert(dither_material != null)
	dither_material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))


func _configure_sword_aura(
	aura_root: Node2D,
	aura_a: Sprite2D,
	aura_b: Sprite2D,
	motion_z: int
) -> void:
	aura_root.visible = true
	aura_root.z_index = motion_z + 1
	for aura in [aura_a, aura_b]:
		aura.centered = false
		aura.region_enabled = false
		aura.hframes = 1
		aura.vframes = 1
		aura.offset = Vector2.ZERO
		aura.position = SWORD_AURA_CHILD_OFFSET
		aura.scale = Vector2.ONE
		aura.rotation = 0.0
		aura.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		aura.visible = true
		_set_alpha(aura, 0.0)


func _sword_aura_state(elapsed: float) -> Dictionary:
	var cursor := 0.0
	for stage in range(SWORD_AURA_STAGE_TIMES.size()):
		var interval := float(SWORD_AURA_STAGE_TIMES[stage])
		if elapsed < cursor + interval:
			if stage < SWORD_AURA_TEXTURES.size() - 1:
				var blend_start := cursor + interval - SWORD_AURA_BLEND_DURATION
				if elapsed >= blend_start:
					return {
						"from": stage,
						"to": stage + 1,
						"mix": _smootherstep((elapsed - blend_start) / SWORD_AURA_BLEND_DURATION),
						"alpha": SWORD_AURA_MAX_ALPHA,
					}
			return {"from": stage, "to": stage, "mix": 0.0, "alpha": SWORD_AURA_MAX_ALPHA}
		cursor += interval
	if elapsed < cursor + SWORD_AURA_FADE_DURATION:
		var fade := 1.0 - _smootherstep((elapsed - cursor) / SWORD_AURA_FADE_DURATION)
		return {"from": 3, "to": 3, "mix": 0.0, "alpha": SWORD_AURA_MAX_ALPHA * fade}
	return {}


func _update_sword_aura(
	motion_a: Sprite2D,
	aura_root: Node2D,
	aura_a: Sprite2D,
	aura_b: Sprite2D,
	frame_index: int,
	next_frame: int,
	frame_mix: float,
	elapsed: float
) -> void:
	var state := _sword_aura_state(elapsed)
	if state.is_empty():
		_clear_sprite(aura_a)
		_clear_sprite(aura_b)
		aura_root.visible = false
		return
	aura_root.visible = true
	var current_segment := SWORD_SEGMENTS[frame_index]
	var following_segment := SWORD_SEGMENTS[next_frame]
	var base := Vector2(current_segment.x, current_segment.y).lerp(
		Vector2(following_segment.x, following_segment.y), frame_mix
	)
	var tip := Vector2(current_segment.z, current_segment.w).lerp(
		Vector2(following_segment.z, following_segment.w), frame_mix
	)
	var cell_centre := MOTION_CELL_SIZE * 0.5
	## Sprite2D.flip_* changes the sampled picture but not Node2D.transform.
	## Mirror the authored blade points too, or the aura detaches in formations
	## that flip Sotiris.
	if motion_a.flip_h:
		base.x = MOTION_CELL_SIZE.x - base.x
		tip.x = MOTION_CELL_SIZE.x - tip.x
	if motion_a.flip_v:
		base.y = MOTION_CELL_SIZE.y - base.y
		tip.y = MOTION_CELL_SIZE.y - tip.y
	var base_parent := motion_a.transform * (base - cell_centre)
	var tip_parent := motion_a.transform * (tip - cell_centre)
	var blade_vector := tip_parent - base_parent
	aura_root.position = base_parent
	aura_root.rotation = blade_vector.angle() + PI * 0.5
	var aura_scale := blade_vector.length() / SWORD_AURA_SOURCE_LENGTH
	aura_root.scale = Vector2.ONE * aura_scale

	var from_index := int(state["from"])
	var to_index := int(state["to"])
	var aura_mix := float(state["mix"])
	var alpha := float(state["alpha"])
	aura_a.texture = SWORD_AURA_TEXTURES[from_index]
	aura_b.texture = SWORD_AURA_TEXTURES[to_index]
	if from_index == to_index:
		_set_alpha(aura_a, alpha)
		_set_alpha(aura_b, 0.0)
	else:
		var weights := _luminous_weights(aura_mix)
		_set_alpha(aura_a, alpha * weights.x)
		_set_alpha(aura_b, alpha * weights.y)


func play_crisp_character_with_sword_aura(
	original_sotiris: Sprite2D,
	motion_a: Sprite2D,
	motion_b: Sprite2D,
	aura_root: Node2D,
	aura_a: Sprite2D,
	aura_b: Sprite2D
) -> void:
	assert(CHARACTER_FRAME_TIMES.size() == 17)
	assert(SWORD_SEGMENTS.size() == 17)
	## These must be three different Sprite2D nodes. Reusing the ordinary battle
	## sprite as MotionA or MotionB lets its idle animator pin the visible frame.
	assert(original_sotiris != motion_a)
	assert(original_sotiris != motion_b)
	assert(motion_a != motion_b)
	## Frame 7 is the only rear-side pose and is preparation, not the downslash.
	## Frames 8..10 have already crossed overhead: every blade tip remains to
	## the right/front of its hilt through upper-right, vertical and down-right.
	assert(SWORD_SEGMENTS[7].z < SWORD_SEGMENTS[7].x)
	for swing_index in range(8, 11):
		assert(SWORD_SEGMENTS[swing_index].z > SWORD_SEGMENTS[swing_index].x)
	assert(SWORD_SEGMENTS[8].w < SWORD_SEGMENTS[8].y)
	assert(SWORD_SEGMENTS[9].w - SWORD_SEGMENTS[9].y >= 40.0)
	assert(SWORD_SEGMENTS[10].w - SWORD_SEGMENTS[10].y >= 30.0)
	assert(is_equal_approx(_sum_times(CHARACTER_FRAME_TIMES), 4.220))
	var release_sum := 0.0
	for release_index in range(RELEASE_FRAME_INDEX):
		release_sum += float(CHARACTER_FRAME_TIMES[release_index])
	assert(is_equal_approx(release_sum, CHARACTER_RELEASE_TIME))
	assert(is_equal_approx(
		_sum_times(SWORD_AURA_STAGE_TIMES) + SWORD_AURA_FADE_DURATION,
		CHARACTER_RELEASE_TIME
	))
	assert(motion_a.get_parent() == original_sotiris.get_parent())
	assert(motion_b.get_parent() == original_sotiris.get_parent())
	assert(aura_root.get_parent() == original_sotiris.get_parent())
	assert(aura_a.get_parent() == aura_root and aura_b.get_parent() == aura_root)

	_original_sotiris_state = _snapshot_sprite(original_sotiris)
	var idle_bounds := _texture_frame_bounds(
		original_sotiris.texture,
		original_sotiris.hframes,
		original_sotiris.vframes,
		original_sotiris.frame
	)
	var idle_image := original_sotiris.texture.get_image()
	var idle_cell_size := Vector2(
		float(idle_image.get_width()) / maxi(1, original_sotiris.hframes),
		float(idle_image.get_height()) / maxi(1, original_sotiris.vframes)
	)
	var idle_foot_source := Vector2(idle_bounds.get_center().x, idle_bounds.end.y)
	if original_sotiris.flip_h:
		idle_foot_source.x = idle_cell_size.x - idle_foot_source.x
	if original_sotiris.flip_v:
		idle_foot_source.y = idle_cell_size.y - idle_foot_source.y
	if original_sotiris.centered:
		idle_foot_source -= idle_cell_size * 0.5
	idle_foot_source += original_sotiris.offset
	_motion_foot_anchor_parent = original_sotiris.transform * idle_foot_source

	var scale_ratio := clampf(
		idle_bounds.size.y / MOTION_REFERENCE_BOUNDS.size.y,
		MOTION_SCALE_RATIO_MIN,
		MOTION_SCALE_RATIO_MAX
	)
	var original_scale: Vector2 = _original_sotiris_state["scale"]
	var original_rotation: float = _original_sotiris_state["rotation"]
	var original_skew: float = _original_sotiris_state["skew"]
	_calibrated_motion_scale = original_scale * scale_ratio
	var motion_basis := Transform2D(
		original_rotation,
		_calibrated_motion_scale,
		original_skew,
		Vector2.ZERO
	)
	var motion_ground_local := MOTION_GROUND_SOURCE - MOTION_CELL_SIZE * 0.5
	var motion_position := _motion_foot_anchor_parent - (motion_basis * motion_ground_local)
	var motion_transform := Transform2D(
		original_rotation,
		_calibrated_motion_scale,
		original_skew,
		motion_position
	)
	_configure_motion_sprite(motion_a, _original_sotiris_state, motion_transform, false)
	_configure_motion_sprite(motion_b, _original_sotiris_state, motion_transform, true)
	_configure_sword_aura(aura_root, aura_a, aura_b, motion_a.z_index)
	original_sotiris.visible = false

	var cursor := 0.0
	var start_usec := Time.get_ticks_usec()
	for frame_index in range(17):
		var interval := float(CHARACTER_FRAME_TIMES[frame_index])
		var next_frame := mini(frame_index + 1, 16)
		_enforce_motion_display_lock(
			original_sotiris, motion_a, motion_b, frame_index, next_frame
		)
		if frame_index == RELEASE_FRAME_INDEX:
			_release_draw_frame = Engine.get_frames_drawn()
			release_frame_fully_visible.emit()
		while true:
			var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
			if elapsed >= cursor + interval:
				break
			var local_time := elapsed - cursor
			var frame_mix := 0.0
			_enforce_motion_display_lock(
				original_sotiris, motion_a, motion_b, frame_index, next_frame
			)
			var dither_duration := minf(
				CHARACTER_DITHER_MAX,
				interval * CHARACTER_DITHER_INTERVAL_RATIO
			)
			if frame_index < 16 and local_time >= interval - dither_duration:
				frame_mix = _smootherstep(
					(local_time - (interval - dither_duration)) / dither_duration
				)
			_set_dither_progress(motion_a, frame_mix)
			_set_dither_progress(motion_b, frame_mix)
			_update_sword_aura(
				motion_a, aura_root, aura_a, aura_b,
				frame_index, next_frame, frame_mix, elapsed
			)
			await get_tree().process_frame
		cursor += interval

	motion_a.frame = 16
	_set_dither_progress(motion_a, 0.0)
	_clear_sprite(motion_b)
	_clear_sprite(aura_a)
	_clear_sprite(aura_b)
	aura_root.visible = false
	_character_pose_complete = true
	character_pose_finished.emit()


func cleanup_crisp_character_motion(
	original_sotiris: Sprite2D,
	motion_a: Sprite2D,
	motion_b: Sprite2D,
	aura_root: Node2D,
	aura_a: Sprite2D,
	aura_b: Sprite2D
) -> void:
	assert(not _original_sotiris_state.is_empty())
	_restore_sprite(original_sotiris, _original_sotiris_state)
	_clear_sprite(motion_a)
	_clear_sprite(motion_b)
	_clear_sprite(aura_a)
	_clear_sprite(aura_b)
	aura_root.visible = false
	_original_sotiris_state.clear()


func _configure_main_sprite(sprite: Sprite2D, fixed_scale: float) -> void:
	assert(fixed_scale >= MAIN_SCALE_MIN)
	sprite.centered = false
	sprite.region_enabled = false
	sprite.hframes = 1
	sprite.vframes = 1
	sprite.offset = Vector2.ZERO
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE * fixed_scale
	sprite.rotation = 0.0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = true
	_set_alpha(sprite, 0.0)


func _apply_main_time(
	main_a: Sprite2D,
	main_b: Sprite2D,
	local_time: float,
	fixed_scale: float,
	travel_duration: float
) -> void:
	var cursor := 0.0
	for index in range(MAIN_BUILD_TIMES.size()):
		var interval := float(MAIN_BUILD_TIMES[index])
		if local_time < cursor + interval:
			var mix := _smootherstep((local_time - cursor) / interval)
			var weights := _luminous_weights(mix)
			main_a.visible = true
			main_b.visible = true
			main_a.texture = MAIN_TEXTURES[index]
			main_b.texture = MAIN_TEXTURES[index + 1]
			main_a.position = -MAIN_PIVOTS[index] * fixed_scale
			main_b.position = -MAIN_PIVOTS[index + 1] * fixed_scale
			_set_alpha(main_a, weights.x)
			_set_alpha(main_b, weights.y)
			return
		cursor += interval
	main_a.visible = true
	main_a.texture = MAIN_TEXTURES[-1]
	main_a.position = -MAIN_PIVOTS[-1] * fixed_scale
	_set_alpha(main_a, 1.0)
	_clear_sprite(main_b)


func calculate_contact_anchor_target_x(
	start_center_x: float,
	enemy_group_bounds: Rect2,
	fixed_scale: float
) -> float:
	var tip_offset := MAIN_FRAME08_TIP_OFFSET_SOURCE_X * fixed_scale
	var result := roundf(enemy_group_bounds.get_center().x - tip_offset)
	assert(result > start_center_x)
	return result


func calculate_contact_travel_duration(start_center_x: float, target_center_x: float) -> float:
	var distance := target_center_x - start_center_x
	assert(distance > 0.0)
	return clampf(distance / MAIN_TRAVEL_SPEED_PX_PER_SEC, MAIN_MIN_DURATION, MAIN_MAX_DURATION)


func play_level_slash_until_contact(
	motion_anchor: Node2D,
	main_a: Sprite2D,
	main_b: Sprite2D,
	start_center_x: float,
	target_center_x: float,
	lane_y: float,
	fixed_scale: float,
	travel_duration: float
) -> void:
	for sprite in [main_a, main_b]:
		_configure_main_sprite(sprite, fixed_scale)
	var frozen_start_x := start_center_x
	var frozen_target_x := target_center_x
	var frozen_lane_y := roundf(lane_y)
	motion_anchor.global_position = Vector2(frozen_start_x, frozen_lane_y)
	_apply_main_time(main_a, main_b, 0.0, fixed_scale, travel_duration)
	_slash_first_visible_draw_frame = Engine.get_frames_drawn()
	assert(_slash_first_visible_draw_frame == _release_draw_frame)

	var start_usec := Time.get_ticks_usec()
	while true:
		var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
		if elapsed >= travel_duration:
			break
		var linear_progress := elapsed / travel_duration
		var position_progress := _edge_smoothed_linear(linear_progress)
		## X is a float updated every process frame; Y is the same frozen integer.
		## Do not round X per frame and do not Tween the child sprites separately.
		motion_anchor.global_position = Vector2(
			lerpf(frozen_start_x, frozen_target_x, position_progress),
			frozen_lane_y
		)
		_apply_main_time(main_a, main_b, elapsed, fixed_scale, travel_duration)
		await get_tree().process_frame

	motion_anchor.global_position = Vector2(frozen_target_x, frozen_lane_y)
	_apply_main_time(main_a, main_b, travel_duration - 0.000001, fixed_scale, travel_duration)
	_slash_contact_draw_frame = Engine.get_frames_drawn()
	## Return in the same process tick. The caller primes Impact at alpha0.08 and
	## the flash at alpha0 before this draw, while grand08 stays fully visible.
	## This makes contact, damage, flash clock and impact share one draw number.


func _apply_impact_time(
	impact_a: Sprite2D,
	impact_b: Sprite2D,
	local_time: float,
	opacity: float = 1.0
) -> void:
	var cursor := 0.0
	for index in range(IMPACT_TEXTURES.size()):
		var interval := float(IMPACT_FRAME_TIMES[index])
		if local_time < cursor + interval:
			if index < IMPACT_TEXTURES.size() - 1:
				var mix := _smootherstep((local_time - cursor) / interval)
				var weights := _luminous_weights(mix)
				impact_a.texture = IMPACT_TEXTURES[index]
				impact_b.texture = IMPACT_TEXTURES[index + 1]
				impact_a.visible = true
				impact_b.visible = true
				_set_alpha(impact_a, opacity * weights.x)
				_set_alpha(impact_b, opacity * weights.y)
			else:
				var tail := _smootherstep((local_time - cursor) / interval)
				impact_a.texture = IMPACT_TEXTURES[-1]
				impact_a.visible = true
				_set_alpha(impact_a, opacity * (1.0 - tail))
				_clear_sprite(impact_b)
			return
		cursor += interval
	_clear_sprite(impact_a)
	_clear_sprite(impact_b)


func _configure_outer(
	outer_a: Sprite2D,
	outer_b: Sprite2D,
	enemy_group_bounds: Rect2
) -> void:
	var outer_scale := clampf((enemy_group_bounds.size.x + 144.0) / 340.0, 1.05, 1.45)
	var position := enemy_group_bounds.get_center() + Vector2(0.0, -192.0 * outer_scale)
	for sprite in [outer_a, outer_b]:
		_configure_plain_sprite(sprite)
		sprite.global_position = position
		sprite.scale = Vector2.ONE * outer_scale


func play_contact_flash(flash_overlay: ColorRect) -> void:
	## Use a screen-space ColorRect under a CanvasLayer. This replaces every
	## delayed legacy flash callback; it starts on the exact contact pass.
	var original_color := flash_overlay.color
	var original_modulate := flash_overlay.self_modulate
	var original_visible := flash_overlay.visible
	flash_overlay.color = Color.WHITE
	flash_overlay.visible = true
	_set_alpha(flash_overlay, 0.0)
	var total_duration := CONTACT_FLASH_RISE + CONTACT_FLASH_FALL
	var start_usec := Time.get_ticks_usec()
	while true:
		var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
		if elapsed >= total_duration:
			break
		var alpha := 0.0
		if elapsed < CONTACT_FLASH_RISE:
			alpha = CONTACT_FLASH_PEAK_ALPHA * _smootherstep(elapsed / CONTACT_FLASH_RISE)
		else:
			alpha = CONTACT_FLASH_PEAK_ALPHA * (
				1.0 - _smootherstep((elapsed - CONTACT_FLASH_RISE) / CONTACT_FLASH_FALL)
			)
		_set_alpha(flash_overlay, alpha)
		await get_tree().process_frame
	flash_overlay.color = original_color
	flash_overlay.self_modulate = original_modulate
	flash_overlay.visible = original_visible
	contact_flash_finished.emit()


func _apply_outer_time(
	outer_a: Sprite2D,
	outer_b: Sprite2D,
	local_time: float,
	opacity: float = 1.0
) -> void:
	var cursor := 0.0
	for index in range(OUTER_TEXTURES.size() - 1):
		var interval := float(OUTER_TIMES[index])
		if local_time < cursor + interval:
			var mix := _smootherstep((local_time - cursor) / interval)
			var weights := _luminous_weights(mix)
			outer_a.texture = OUTER_TEXTURES[index]
			outer_b.texture = OUTER_TEXTURES[index + 1]
			outer_a.visible = true
			outer_b.visible = true
			_set_alpha(outer_a, opacity * float(OUTER_ALPHA[index]) * weights.x)
			_set_alpha(outer_b, opacity * float(OUTER_ALPHA[index + 1]) * weights.y)
			return
		cursor += interval
	var tail_duration := float(OUTER_TIMES[-1])
	if local_time < cursor + tail_duration:
		var tail := _smootherstep((local_time - cursor) / tail_duration)
		outer_a.texture = OUTER_TEXTURES[-1]
		outer_a.visible = true
		_set_alpha(outer_a, opacity * float(OUTER_ALPHA[-1]) * (1.0 - tail))
		_clear_sprite(outer_b)
		return
	_clear_sprite(outer_a)
	_clear_sprite(outer_b)


func play_smooth_outer(
	outer_a: Sprite2D,
	outer_b: Sprite2D,
	enemy_group_bounds: Rect2
) -> void:
	_configure_outer(outer_a, outer_b, enemy_group_bounds)
	var duration := _sum_times(OUTER_TIMES)
	var start_usec := Time.get_ticks_usec()
	while true:
		var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
		if elapsed >= duration:
			break
		var entry_alpha := _smootherstep(elapsed / OUTER_ENTRY_FADE)
		_apply_outer_time(outer_a, outer_b, elapsed, entry_alpha)
		await get_tree().process_frame
	_clear_sprite(outer_a)
	_clear_sprite(outer_b)
	outer_finished.emit()


func play_impact_with_overlaps(
	main_a: Sprite2D,
	main_b: Sprite2D,
	impact_a: Sprite2D,
	impact_b: Sprite2D,
	outer_a: Sprite2D,
	outer_b: Sprite2D,
	impact_position: Vector2,
	enemy_group_bounds: Rect2
) -> void:
	for sprite in [impact_a, impact_b]:
		_configure_plain_sprite(sprite)
		sprite.global_position = impact_position.round()
		sprite.scale = Vector2.ONE
	_apply_impact_time(impact_a, impact_b, 0.0, IMPACT_ENTRY_MIN_ALPHA)
	_impact_first_visible_draw_frame = Engine.get_frames_drawn()
	var blank_draw_delta := _impact_first_visible_draw_frame - _slash_contact_draw_frame
	assert(blank_draw_delta == 0)

	var impact_duration := _sum_times(IMPACT_FRAME_TIMES)
	var outer_start_time := OUTER_START_AFTER_CONTACT
	assert(is_equal_approx(impact_duration - outer_start_time, IMPACT_TO_OUTER_OVERLAP))
	var outer_started := false
	var start_usec := Time.get_ticks_usec()
	while true:
		var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
		if elapsed >= impact_duration:
			break
		var impact_entry_alpha := lerpf(
			IMPACT_ENTRY_MIN_ALPHA,
			1.0,
			_smootherstep(elapsed / SLASH_TO_IMPACT_OVERLAP)
		)
		_apply_impact_time(impact_a, impact_b, elapsed, impact_entry_alpha)
		var slash_alpha := 1.0 - _smootherstep(elapsed / SLASH_TO_IMPACT_OVERLAP)
		_set_alpha(main_a, slash_alpha)
		_set_alpha(main_b, 0.0)
		if elapsed >= SLASH_TO_IMPACT_OVERLAP:
			_clear_sprite(main_a)
			_clear_sprite(main_b)
		if not outer_started and elapsed >= outer_start_time:
			outer_started = true
			_outer_first_visible_draw_frame = Engine.get_frames_drawn() + 1
			play_smooth_outer(outer_a, outer_b, enemy_group_bounds)
		await get_tree().process_frame

	_clear_sprite(main_a)
	_clear_sprite(main_b)
	_clear_sprite(impact_a)
	_clear_sprite(impact_b)
	if not outer_started:
		outer_started = true
		play_smooth_outer(outer_a, outer_b, enemy_group_bounds)
	await outer_finished


func play_continuous_finish_chain(
	motion_anchor: Node2D,
	main_a: Sprite2D,
	main_b: Sprite2D,
	impact_a: Sprite2D,
	impact_b: Sprite2D,
	outer_a: Sprite2D,
	outer_b: Sprite2D,
	flash_overlay: ColorRect,
	start_center_x: float,
	enemy_group_bounds: Rect2,
	lane_y: float,
	fixed_scale: float,
	damage_callback: Callable
) -> void:
	var target_x := calculate_contact_anchor_target_x(start_center_x, enemy_group_bounds, fixed_scale)
	var travel_duration := calculate_contact_travel_duration(start_center_x, target_x)
	var impact_position := enemy_group_bounds.get_center().round()
	var contact_tip_x := target_x + MAIN_FRAME08_TIP_OFFSET_SOURCE_X * fixed_scale
	assert(absf(contact_tip_x - impact_position.x) <= 1.0)
	await play_level_slash_until_contact(
		motion_anchor, main_a, main_b,
		start_center_x, target_x, lane_y, fixed_scale, travel_duration
	)
	_damage_apply_count = 0
	if damage_callback.is_valid():
		damage_callback.call()
		_damage_apply_count += 1
	assert(_damage_apply_count <= 1)
	## Deliberately no await: flash starts on contact while impact is primed.
	play_contact_flash(flash_overlay)
	await play_impact_with_overlaps(
		main_a, main_b, impact_a, impact_b, outer_a, outer_b,
		impact_position, enemy_group_bounds
	)
	print(
		"EOS_V28_CONTINUITY release_draw=", _release_draw_frame,
		" slash_draw=", _slash_first_visible_draw_frame,
		" contact_draw=", _slash_contact_draw_frame,
		" impact_draw=", _impact_first_visible_draw_frame,
		" outer_first_draw=", _outer_first_visible_draw_frame,
		" contact_tip_x=", contact_tip_x,
		" enemy_center_x=", impact_position.x,
		" travel_duration=", travel_duration,
		" calibrated_motion_scale=", _calibrated_motion_scale,
		" motion_foot_anchor=", _motion_foot_anchor_parent,
		" damage_count=", _damage_apply_count
	)
	finish_chain_completed.emit()


func play_v28_eos_burst(
	original_sotiris: Sprite2D,
	motion_a: Sprite2D,
	motion_b: Sprite2D,
	sword_aura_root: Node2D,
	aura_a: Sprite2D,
	aura_b: Sprite2D,
	motion_anchor: Node2D,
	main_a: Sprite2D,
	main_b: Sprite2D,
	impact_a: Sprite2D,
	impact_b: Sprite2D,
	outer_a: Sprite2D,
	outer_b: Sprite2D,
	flash_overlay: ColorRect,
	start_center_x: float,
	enemy_group_bounds: Rect2,
	lane_y: float,
	fixed_scale: float,
	damage_callback: Callable
) -> void:
	assert(not _burst_running)
	_burst_running = true
	_release_draw_frame = -1
	_slash_first_visible_draw_frame = -1
	_slash_contact_draw_frame = -1
	_impact_first_visible_draw_frame = -1
	_outer_first_visible_draw_frame = -1
	_character_pose_complete = false

	## Delete the legacy ~1.0 s prelude wait. Dimming/input lock may start at
	## t=0, but character and blade aura begin after only this0.12s lead-in.
	await get_tree().create_timer(BURST_LEAD_IN).timeout
	## Deliberately no await: the pose clock and blade aura run continuously.
	play_crisp_character_with_sword_aura(
		original_sotiris, motion_a, motion_b,
		sword_aura_root, aura_a, aura_b
	)
	## No cut-in timer or call exists. The viewer sees the entire charge, the
	## overhead crossing and all front-side swing poses before the slash.
	await release_frame_fully_visible
	assert(_release_draw_frame >= 0)
	play_continuous_finish_chain(
		motion_anchor, main_a, main_b, impact_a, impact_b, outer_a, outer_b, flash_overlay,
		start_center_x, enemy_group_bounds, lane_y, fixed_scale, damage_callback
	)
	await finish_chain_completed
	assert(_character_pose_complete)
	cleanup_crisp_character_motion(
		original_sotiris, motion_a, motion_b,
		sword_aura_root, aura_a, aura_b
	)
	_burst_running = false
