extends RefCounted
var _gpu_verification_completed:=false

func run_gpu_verification(tree: SceneTree,directory: String,_all: bool) -> int:
	tree.root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(directory)
	var view:=RBMCreatorTestBattleView.new()
	tree.root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.setup(null)
	view.set_boss_appearance("appearance_knight")
	var definition:=preload("res://tools/verify_tank_actions_gpu.gd").definition_for()
	view.start(definition,20260906)
	# No warmup wait/timer here: issue the earliest valid tank action immediately.
	while view.session.pending_ally_id()!=3:view.session.resolve_ally_action({"type":"defend"})
	var battle: RBMBattle=view.session.battle
	var stage: Control=view._battlefield_ally_row.get_meta("visual_stage")
	var baseline:=false
	var before:=battle.presentation_state().duplicate(true)
	stage.set_state(before)
	var entries:=battle.resolve_pending_ally_action({"type":"attack"})
	var snapshot:=battle.snapshot().duplicate(true)
	var sheet_cached:=ResourceLoader.has_cached("res://assets_bossmaker/battle/tank/actions/tank_intermediates_v1.png")
	var hits: Array=[];var finished: Array=[]
	stage.impact.connect(func(e):hits.append(e))
	stage.finished.connect(func():finished.append(true))
	var started:=Time.get_ticks_usec()
	view._present_batch(entries,before)
	var begin_ms:=(Time.get_ticks_usec()-started)/1000.0
	var saw_waiting:=false
	var held_state:=true
	var start_us:=0
	var frame_ms: Array=[]
	var last:=started
	var missing_at_start: Array=[]
	for i in 300:
		if stage._waiting_script!=null:
			saw_waiting=true
			held_state=held_state and hits.is_empty() and view._presenter.display_state()==before
		if stage.is_playing() and stage._waiting_script==null and start_us==0:
			start_us=Time.get_ticks_usec()
			if not baseline:
				for path in preload("res://src/bossmaker/visuals/rbm_tank_action.gd").warm_paths("tank",""):
					if not ResourceLoader.has_cached(path):missing_at_start.append(path)
		await tree.process_frame
		var now:=Time.get_ticks_usec()
		frame_ms.append((now-last)/1000.0);last=now
		if not view._presenter.is_playing():break
	var okay: bool=held_state and missing_at_start.is_empty() and hits.size()==1 and finished.size()==1 and battle.snapshot()==snapshot and not stage.is_playing()
	var report: Dictionary={"purpose":"Fresh-process full-HUD earliest valid tank action, no warmup sleep; turn selection is a fixture, not human UI navigation","adapter":RenderingServer.get_video_adapter_name(),"passed":okay,"sheet_cached_before_action":sheet_cached,"saw_waiting":saw_waiting,"state_held_during_wait":held_state,"missing_at_start":missing_at_start,"begin_call_ms":begin_ms,"start_delay_ms":(start_us-started)/1000.0,"frame_ms":frame_ms,"impacts":hits.size(),"finished":finished.size(),"snapshot_unchanged":battle.snapshot()==snapshot}
	report["baseline"]=baseline
	FileAccess.open(directory+"/cold-start.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TANK_COLD_START ",okay)
	view.queue_free()
	await tree.process_frame
	_gpu_verification_completed=true
	return 0 if okay else 1
