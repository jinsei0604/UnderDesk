extends "res://ally_awakening/core/ink.gd"
## Presentation only. Signals never resolve a battle action.
signal released
signal finished
signal cancelled
signal pose_requested(frame: String)
signal shake_requested(amplitude: float,duration: float)
signal screen_requested(darkness: float,flash: float)
@export_range(0.25,2.0) var playback_speed:=1.0
@export_range(0,1) var flash_strength:=1.0
@export_range(0,1) var shake_strength:=1.0
@export_range(0,1) var vfx_strength:=1.0
@export var sound_gain_db:=-9.0
var character_id:="hero"
var duration:=5.6
var release_time:=3.0
var quiet_time:=2.82
var active:=false
var did_release:=false
var foot_provider: Callable
var voice: AudioStreamPlayer
var release_voice: AudioStreamPlayer
var _pose:=""
var cue_log: Array=[]
func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	z_index=2
	voice=AudioStreamPlayer.new()
	add_child(voice)
	release_voice=AudioStreamPlayer.new()
	add_child(release_voice)
	visible=false
	visibility_changed.connect(_visibility_changed)
func prepare() -> bool:
	voice.stream=load("res://ally_awakening/audio/"+character_id+"_charge.wav")
	release_voice.stream=load("res://ally_awakening/audio/"+character_id+"_release.wav")
	return voice.stream!=null and release_voice.stream!=null
func warm_paths() -> Array[String]:
	return ["res://ally_awakening/audio/"+character_id+"_charge.wav","res://ally_awakening/audio/"+character_id+"_release.wav"]
func play() -> bool:
	if voice.stream==null or release_voice.stream==null:return false
	if active:cancel()
	age=0
	did_release=false
	_pose=""
	cue_log.clear()
	visible=true
	active=true
	voice.volume_db=sound_gain_db
	release_voice.volume_db=sound_gain_db
	voice.pitch_scale=playback_speed
	release_voice.pitch_scale=playback_speed
	voice.play()
	advance(0.0)
	return true
func _process(dt: float) -> void:
	if active:advance(age+dt*playback_speed)
func advance(t: float) -> void:
	if not active:return
	age=minf(t,duration)
	strength=vfx_strength
	if foot_provider.is_valid():position=Vector2(foot_provider.call()).round()
	if age>=quiet_time and age<release_time:voice.stop()
	if age>=release_time and not did_release:
		did_release=true
		voice.stop()
		release_voice.play(maxf(0,age-release_time))
		cue_log.append({"cue":"release","scheduled":release_time,"actual":age})
		released.emit()
		shake_requested.emit(shake_amplitude()*shake_strength,.42)
	var frame:=pose_at(age)
	if frame!=_pose:
		_pose=frame
		pose_requested.emit(frame)
	var dark:=smoothstep(.12,.9,age)*.43*(1-smoothstep(release_time+.25,duration-.25,age))
	var flash:=maxf(0,1-(age-release_time)/.10) if age>=release_time else 0.0
	screen_requested.emit(dark,flash*.16*flash_strength)
	queue_redraw()
	if age>=duration:
		active=false
		visible=false
		screen_requested.emit(0,0)
		pose_requested.emit("b:0")
		finished.emit()
func cancel() -> void:
	var was_active:=active
	active=false
	voice.stop()
	release_voice.stop()
	visible=false
	age=0
	screen_requested.emit(0,0)
	pose_requested.emit("b:0")
	if was_active:cancelled.emit()
func _visibility_changed() -> void:
	if active and not is_visible_in_tree():cancel()
func _exit_tree() -> void:
	if is_instance_valid(voice):voice.stop()
	if is_instance_valid(release_voice):release_voice.stop()
func shake_amplitude() -> float:return 6.0
func pose_at(_t: float) -> String:return "b:0"
func gather() -> float:return smoothstep(.2,quiet_time,age)*(1-smoothstep(quiet_time,release_time,age))
func tail(seconds: float=1.6) -> float:return 1-clampf((age-release_time)/seconds,0,1)
