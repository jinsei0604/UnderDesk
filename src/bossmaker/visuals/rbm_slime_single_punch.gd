extends "res://src/bossmaker/visuals/rbm_slime_presentation.gd"
func _init() -> void:
	kind="single"
	duration=2.65
	impact_time=.91

# The approved connected punch keeps the inherited hit, counter and cleanup contract.
const Connected=preload("res://src/bossmaker/visuals/rbm_slime_punch_vfx.gd")
const PunchTiming=preload("res://src/bossmaker/visuals/rbm_slime_punch_timing.gd")
var _punch_release_played:=false
func play(stage: Control) -> Tween:
	_punch_release_played=false
	# Own the launch cue; impact audio stays in the inherited strike.
	_released=true
	var tween:=super.play(stage)
	var old:=_vfx
	var next:=Connected.new()
	next.motion=old.motion
	next.kind=old.kind
	next.attack_attribute=old.attack_attribute
	next.slime=old.slime
	next.pixel_scale=old.pixel_scale
	next.feet=old.feet
	next.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	remove_child(old)
	old.free()
	_vfx=next
	add_child(next)
	next.advance(0)
	return tween

func _advance(t: float) -> void:
	if not _punch_release_played and active and is_instance_valid(_stage) and t>=PunchTiming.RELEASE:
		_punch_release_played=true
		_stage._play_se("release")
	super._advance(t)
