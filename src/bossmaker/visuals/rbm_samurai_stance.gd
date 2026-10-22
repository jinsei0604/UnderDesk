extends Node2D
const Body=preload("res://src/bossmaker/visuals/rbm_samurai_body.gd")
const Wind=preload("res://src/bossmaker/visuals/rbm_samurai_iai_wind.gd")
var stage: Control
var key:=""
var frame:=-1
var texture: Texture2D
var owned: Control
var enabled:=true
var wind_clock:=0.0
var wind_active:=false
var counter_wind:=false

func _ready() -> void:
	z_index=3;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	wind_clock+=delta
	refresh()

func refresh() -> void:
	if not is_instance_valid(stage):return
	var next:=-1
	wind_active=false
	if not stage._samurai_finish or not stage.is_playing():counter_wind=false
	key=""
	for actor in stage._asset_ids:
		if stage._asset_ids[actor]=="samurai":key=str(actor);break
	if enabled and stage._visuals.has(key) and not stage._samurai_finish:
		var state: Dictionary=stage._unit_state(key)
		var busy: bool=is_instance_valid(stage._skill_presentation) and stage._actor==key
		if not busy and not state.get("is_downed",false):
			if state.get("counter_pending",false) and int(stage._poses.get(key,0))==8:next=19
			elif float(state.get("next_attack_bonus_multiplier",1))>1 and int(stage._poses.get(key,0))==7:next=18
	if enabled and stage._visuals.has(key):
		var busy: bool=is_instance_valid(stage._skill_presentation) and stage._actor==key
		var state: Dictionary=stage._unit_state(key)
		wind_active=not busy and not state.get("is_downed",false) and (Wind.is_active(state) or counter_wind)
	if next>=0 and texture==null and ResourceLoader.has_cached(Body.SHEET):texture=load(Body.SHEET)
	if texture==null:next=-1
	if next<0 and is_instance_valid(owned):owned.visible=true;owned=null
	if next>=0:
		owned=stage._visuals[key];owned.visible=false
	if key.is_empty():texture=null
	frame=next
	set_process(enabled and not key.is_empty())
	queue_redraw()

func release() -> void:
	enabled=false
	set_process(false)
	if is_instance_valid(owned):owned.visible=true
	owned=null;texture=null;frame=-1;wind_active=false;counter_wind=false
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(stage) or not stage._visuals.has(key):return
	var foot: Vector2=stage._foot(key)
	var hand:=Body.hand(frame,foot) if frame>=0 else foot+Vector2(0,-45)
	var tip:=Body.tip(frame,foot) if frame>=0 else hand
	var alpha:=1.0 if wind_active else 0.0
	if counter_wind and not Wind.is_active(stage._unit_state(key)):
		alpha*=1-smoothstep(1.5,2.5,stage._samurai_elapsed)
	Wind.mantle(self,foot,hand,tip,wind_clock,alpha,true)
	if frame>=0 and is_instance_valid(owned):Body.draw_frame(self,texture,frame,foot)
	Wind.mantle(self,foot,hand,tip,wind_clock,alpha)

func resume() -> void:
	enabled=true
	refresh()

func begin_counter(counter_key: String) -> void:
	# Keep the existing response's IAI wind through its consuming impact.
	counter_wind=Wind.is_active(stage._unit_state(counter_key))
