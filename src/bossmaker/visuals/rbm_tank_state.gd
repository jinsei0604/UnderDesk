extends Node2D
const FX=preload("res://src/bossmaker/visuals/rbm_tank_fx.gd")
var stage: Control
var enabled:=true
var cover_id:=""
var boost:=false
var wall:=false
func _ready() -> void:
	z_index=6;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
func _process(_delta: float) -> void:refresh()
func refresh() -> void:
	cover_id="";boost=false;wall=false
	if not enabled or not is_instance_valid(stage):queue_redraw();return
	var present:=false
	for key in stage._party_keys:
		if stage._asset_ids.get(key,"")=="tank":present=true;break
	set_process(present)
	if not present:queue_redraw();return
	var effects: Dictionary=stage._state.get("party_timed_effects",{})
	var turn:=int(stage._state.get("turn",0))
	boost=RBMConstants.timed_effect_active(effects,"guard_boost",turn)
	wall=RBMConstants.timed_effect_active(effects,"iron_wall",turn)
	for key in stage._party_keys:
		var state: Dictionary=stage._unit_state(key)
		if stage._asset_ids.get(key,"")=="tank" and not state.get("is_downed",false) and int(state.get("protecting_ally_id",-1))>=0:
			cover_id=str(state.protecting_ally_id)
	queue_redraw()
func release() -> void:
	enabled=false;set_process(false);cover_id="";boost=false;wall=false;queue_redraw()
func _draw() -> void:
	if not enabled or not is_instance_valid(stage):return
	for key in stage._party_keys:
		var state: Dictionary=stage._unit_state(key)
		if state.get("is_downed",false):continue
		var foot: Vector2=stage._foot(key)
		if wall:FX.plate(self,foot+Vector2(37,-26),11,0.62)
		if boost and state.get("is_defending",false):FX.chevron(self,foot+Vector2(37,-43),8,0.72)
		if key==cover_id:FX.shield(self,foot+Vector2(38,-48),12,0.65)

func resume() -> void:
	enabled=true
	refresh()
