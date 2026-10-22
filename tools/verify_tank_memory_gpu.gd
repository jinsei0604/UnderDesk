extends RefCounted
var _gpu_verification_completed:=false
func run_gpu_verification(tree: SceneTree,directory: String,_all: bool) -> int:
	DirAccess.make_dir_recursive_absolute(directory)
	for i in 5:await tree.process_frame
	var before:=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var sprites:Array=[]
	for path in ["res://assets_bossmaker/battle/tank/actions/tank_intermediates_v1.png"]:
		var sprite:=Sprite2D.new()
		sprite.texture=load(path)
		sprite.scale=Vector2.ONE*0.1
		sprite.position=Vector2(160+sprites.size()*200,160)
		tree.root.add_child(sprite)
		sprites.append(sprite)
	for i in 10:await tree.process_frame
	var loaded:=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	for sprite in sprites:sprite.queue_free()
	sprites.clear()
	for i in 10:await tree.process_frame
	var after:=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var report:Dictionary={"purpose":"New tank texture only; memory measurement, not frame-time evidence","adapter":RenderingServer.get_video_adapter_name(),"before_bytes":before,"loaded_bytes":loaded,"released_bytes":after,"increment_bytes":loaded-before,"residual_bytes":after-before}
	# Confirm lifetime in the actual sandbox battle too, and capture render counts.
	var review=preload("res://tools/verify_tank_actions_gpu.gd").new()
	review._tree_override=tree
	review.performance_mode=true
	var objects: Array=[]
	var primitives: Array=[]
	var sample:=func():
		objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	await review._new_view("knight","night")
	review.label=Label.new()
	review.sublabel=Label.new()
	tree.root.add_child(review.label)
	tree.root.add_child(review.sublabel)
	report["battle_before_actions_bytes"]=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	tree.process_frame.connect(sample)
	for key in ["attack","tank_smash","tank_guard_swap","tank_guard_boost","tank_iron_wall"]:
		await review._case(key,"memory_and_render_counts",false)
	tree.process_frame.disconnect(sample)
	report["battle_after_actions_bytes"]=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	report["objects_max"]=objects.max()
	report["primitives_max"]=primitives.max()
	report["battle_frames_sampled"]=objects.size()
	report["battle_asset_held"]=ResourceLoader.has_cached("res://assets_bossmaker/battle/tank/actions/tank_intermediates_v1.png")
	await review._close_view()
	review.label.queue_free()
	review.sublabel.queue_free()
	review=null
	for i in 10:await tree.process_frame
	report["battle_exit_bytes"]=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	report["battle_exit_asset_held"]=ResourceLoader.has_cached("res://assets_bossmaker/battle/tank/actions/tank_intermediates_v1.png")
	FileAccess.open(directory+"/memory.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TANK_TEXTURE_MEMORY ",report)
	_gpu_verification_completed=true
	return 0
