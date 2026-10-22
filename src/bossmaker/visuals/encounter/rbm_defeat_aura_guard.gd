extends RefCounted
## A defeated awakened boss owns no ambient aura. Keep it hidden through result refreshes.
## Release only with the victory layer; cancel/retry restores presentation resources.
var _items: Array = []
var _nodes: Array = []
var _viewports: Array = []
var _musha_aura: Node2D
var _musha_allies := false
var _aura: Node2D
var _stage: Control

func attach(stage: Control, asset: String, owner: Node) -> void:
	if not asset.ends_with("_awakened"): return
	var base := asset.trim_suffix("_awakened")
	var aura: Node2D = stage.get("_"+base+"_aura")
	if not is_instance_valid(aura): return
	_aura = aura
	_stage = stage
	owner.tree_exiting.connect(release,CONNECT_ONE_SHOT)
	_suspend(aura)
	_hold(aura)
	if base == "astronaut" and is_instance_valid(aura._layer):
		_stop_viewport(aura._layer.viewport)
	elif base == "musha":
		_musha_aura = aura
		_musha_allies = aura._allies_on
		aura._apply_allies(false)
		# The current ink director draws into three viewports and stage siblings.
		# Hiding only the legacy aura leaves the pool and rising ink visible.
		var ink: Node = stage.get("_musha_ink")
		if is_instance_valid(ink):
			_suspend(ink)
			for canvas in [ink.back,ink.mid,ink.top]:
				_hold(canvas.disp)
				_stop_viewport(canvas.vp)
			for item in [ink.accent,ink.space_rect,ink._bbc]+ink.hud_over: _hold(item)
		var idle: Node2D = stage.get("_musha_idle")
		if is_instance_valid(idle):
			_suspend(idle)
			_hold(idle)

func _suspend(node: Node) -> void:
	_nodes.append({"node":node,"processing":node.is_processing()})
	node.set_process(false)

func _hold(item: CanvasItem) -> void:
	if not is_instance_valid(item): return
	var callback := _keep_hidden.bind(item)
	_items.append({"item":item,"visible":item.visible,"callback":callback})
	item.visibility_changed.connect(callback)
	_keep_hidden(item)

func _keep_hidden(item: CanvasItem) -> void:
	if is_instance_valid(item) and item.visible: item.hide()

func _stop_viewport(viewport: SubViewport) -> void:
	_viewports.append({"viewport":viewport,"mode":viewport.render_target_update_mode})
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func release() -> void:
	for saved in _items:
		if not is_instance_valid(saved.item): continue
		if saved.item.visibility_changed.is_connected(saved.callback): saved.item.visibility_changed.disconnect(saved.callback)
		saved.item.visible = saved.visible
	for saved in _nodes:
		if is_instance_valid(saved.node): saved.node.set_process(saved.processing)
	for saved in _viewports:
		if is_instance_valid(saved.viewport): saved.viewport.render_target_update_mode = saved.mode
	# Some refresh implementations discard their hidden viewport. Rebuild it on cancel,
	# while leaving a dying stage alone during teardown.
	if is_instance_valid(_aura) and is_instance_valid(_stage) and _stage.is_inside_tree() and not _stage.is_queued_for_deletion():
		_aura.refresh()
	if is_instance_valid(_musha_aura): _musha_aura._apply_allies(_musha_allies)
	_items.clear()
	_nodes.clear()
	_viewports.clear()
