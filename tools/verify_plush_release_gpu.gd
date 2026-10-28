extends "res://tools/verify_plush_gpu.gd"
var audio_peak_db:=-120.0
var scream_observations: Array=[]
var scream_seen:=false
func _run() -> void:
	var original_locale:=RBMLocale.current_locale()
	report.verifier_instance_id=get_instance_id()
	report.master_volume_db=AudioServer.get_bus_volume_db(0)
	report.master_effects=[]
	for i in AudioServer.get_bus_effect_count(0):
		var effect=AudioServer.get_bus_effect(0,i)
		if effect is AudioEffectHardLimiter:report.master_effects.append({"type":"limiter","pre_gain_db":effect.pre_gain_db,"ceiling_db":effect.ceiling_db})
	_tree().process_frame.connect(_observe_audio)
	if "--cue-only" in OS.get_cmdline_user_args():await _awakening()
	elif "--perf" in OS.get_cmdline_user_args():
		for repetition in 2:
			await _case("challenge","aoe",true)
			scream_seen=false
			await _awakening()
	else:await super._run()
	_tree().process_frame.disconnect(_observe_audio)
	if RBMLocale.current_locale()!=original_locale:RBMLocale.set_locale(original_locale)
	report.audio_peak_db=audio_peak_db
	report.approved_scream=scream_observations
	if audio_peak_db>-.1:_fail("Plush audio approaches clipping")
	if not "--selection-only" in OS.get_cmdline_user_args() and not "--defeat-only" in OS.get_cmdline_user_args():
		if scream_observations.is_empty():_fail("Approved awakening scream was not observed")
func _observe_audio() -> void:
	audio_peak_db=maxf(audio_peak_db,maxf(AudioServer.get_bus_peak_volume_left_db(0,0),AudioServer.get_bus_peak_volume_right_db(0,0)))
	if not is_instance_valid(stage):return
	var driver=stage._skill_presentation
	if not is_instance_valid(driver) or not driver is Driver or driver.kind!="awakening":return
	if scream_seen or not driver._body.sound_marks.has("loom"):return
	for player in driver._body.audio._players:
		if player.playing and player.stream.resource_path.ends_with("v12/audio/awakening_scream.wav"):
			scream_seen=true
			var item:={"age":driver.age,"face_visible":driver._body.face_visible(),"blackout":driver._body.blackout(),"path":player.stream.resource_path,"gain_db":player.volume_db}
			scream_observations.append(item)
			if not item.face_visible or item.blackout!=0.0:_fail("New scream is not synchronized with bright face reveal")

func _expected_case_count() -> int:
	var args := OS.get_cmdline_user_args()
	if "--cue-only" in args: return 1
	if "--perf" in args: return 4
	return super._expected_case_count()
