extends "res://src/bossmaker/visuals/plush/rbm_plush_v9_render.gd"
## AoE-only review revision. Every other action delegates to the approved V10.
const Approved=preload("res://src/bossmaker/visuals/plush/rbm_plush_v9_render.gd")
const Preparation=preload("res://src/bossmaker/visuals/plush/rbm_plush_v11_data.gd")
const PREPARE_PATH="res://assets_bossmaker/battle/plush/v11/prepare.png"
const DARK_BEGIN:=1.18
const DARK_FULL:=2.10
const LAST_HIT:=4.48
const RETURN_BEGIN:=5.45
const RETURN_END:=6.30
const HITS=[2.35,2.57,2.76,2.93,3.09,3.24,3.38,3.51,3.63,3.75,3.87,3.99]
var prepare_sheet: Texture2D

static func clip_duration(key: String) -> float:
	return 6.60 if key=="awakened_all" else Approved.clip_duration(key)
static func clip_impact(key: String) -> float:
	return LAST_HIT if key=="awakened_all" else Approved.clip_impact(key)
static func extra_paths() -> Array[String]:
	var paths:=Approved.extra_paths();paths.append(PREPARE_PATH);return paths
func _ready() -> void:
	super._ready()
	prepare_sheet=load(PREPARE_PATH)
func prep_frame() -> Dictionary:
	return Preparation.ART.frames[clampi(int(age*20),0,Preparation.ART.frames.size()-1)]
func belly_origin() -> Vector2:
	var f:=prep_frame()
	return home+Vector2(f.belly[0],f.belly[1])
func blackout() -> float:
	if kind!="awakened_all":return super.blackout()
	return smoothstep(DARK_BEGIN,DARK_FULL,age)*(1-smoothstep(RETURN_BEGIN,RETURN_END,age))
func rush_index() -> int:
	if kind!="awakened_all":return super.rush_index()
	var index:=-1
	for i in HITS.size():
		if age>=float(HITS[i])-.09:index=i
	return index
func show_action(key: String,t: float) -> void:
	if key!="awakened_all":
		dark_front.self_modulate=Color.WHITE
		super.show_action(key,t);return
	is_new=true;kind=key;age=t;at=t;boss=home;anim=key;frame_record={"v11_aoe":true}
	screen_fx.visible=false;space.visible=false;support_display.visible=false
	support_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	veil.visible=true;dark_front.visible=true
	# One shared tint keeps body, sleeve and hand equally restrained in darkness.
	dark_front.self_modulate=Color(.50,.40,.62)
	camera.cut(1,Vector2(640,360))
	if t>=.51:sound("boss_move_heavy",.47,"belly_first")
	if t>=.95:sound("boss_move_heavy",.43,"belly_second")
	if t>=DARK_FULL and not sound_marks.has("dark_silence"):
		audio.stop_all();sound_marks["dark_silence"]=true
	for i in HITS.size():
		if t>=float(HITS[i]):
			var mark:="rush_"+str(i)
			if not sound_marks.has(mark):camera.shake(2.5,.075)
			local_sound("cloth_hit_"+str(i%3),mark,-2 if i<4 else -1,.94+float(i%3)*.035)
	if t>=5.15 and not sound_marks.has("end_silence"):
		audio.stop_all();sound_marks["end_silence"]=true
	camera.advance(maxf(0,t-old_age));old_age=t
	queue_redraw();front.queue_redraw();veil.queue_redraw();dark_front.queue_redraw()
func on_impact(key: String) -> void:
	if key!="awakened_all":super.on_impact(key);return
	camera.shake(5,.22);local_sound("cloth_finish","finish",0)

func _draw() -> void:
	if kind!="awakened_all":super._draw();return
	if age<DARK_FULL:
		Mist.paint(self,new_sheets,age,home,1)
		var f:=prep_frame();var im: Dictionary=Preparation.ART.images[int(f.id)]
		var rect:=Rect2(im.rect[0],im.rect[1],im.rect[2],im.rect[3])
		draw_texture_rect_region(prepare_sheet,Rect2((home+Vector2(im.offset[0],im.offset[1])).round(),rect.size),rect)
		Mist.paint(self,new_sheets,age,home,1,true)
	elif age>=RETURN_BEGIN:
		Mist.paint(self,new_sheets,age,home,1)
		super.stamp(self,"awakened_all",5.8,home)
		Mist.paint(self,new_sheets,age,home,1,true)

func draw_darkness(ci: CanvasItem,foreground: bool=false) -> void:
	if kind!="awakened_all":super.draw_darkness(ci,foreground);return
	if foreground:
		if age>=DARK_FULL and age<LAST_HIT+.24:_draw_bear_rush(ci)
		return
	if age<DARK_BEGIN:return
	if age>=DARK_FULL:
		ci.draw_rect(Rect2(-32,-32,1344,784),Color(0,0,0,1-smoothstep(RETURN_BEGIN,RETURN_END,age)))
		return
	# Filled, pixel-snapped shadow fronts grow out of the actual belly landmark.
	# No screen fade precedes this expansion and no bright slash/flash is drawn.
	var k:=smoothstep(DARK_BEGIN,DARK_FULL,age)
	var radius:=12+pow(k,1.7)*1180
	var origin:=belly_origin()
	for layer in range(3):
		var points: Array=[]
		var extent:=radius*(1.10-float(layer)*.05)+float(2-layer)*6
		for i in range(96):
			var angle:=float(i)*TAU/96
			var irregular:=1+.045*sin(angle*7+.3)+.025*cos(angle*11-.4)
			var p:=origin+Vector2(cos(angle),sin(angle))*extent*irregular
			points.append(p.snapped(Vector2(2,2)))
		polygon(ci,points,[Color(.045,.027,.065,.28),Color(.012,.006,.022,.66),Color.BLACK][layer])

func combo_state() -> Dictionary:
	# Exactly ONE body and its connected arm are returned per rendered frame.
	if age>=LAST_HIT-.17 and age<LAST_HIT+.24:
		var q:=age-LAST_HIT
		var target:=Vector2(350,430)
		if not HOMES.is_empty():
			target=Vector2.ZERO
			for p in HOMES.values():target+=p
			target=target/HOMES.size()
		var reach:=pow(smoothstep(-.17,0,q),1.35)
		var withdraw:=smoothstep(.06,.24,q)
		var body_at:=home.lerp(target+Vector2(170,-10),reach).lerp(home,withdraw)
		var origin:=body_at+Vector2(1,-86)
		var hand:=origin.lerp(target+Vector2(0,-20),reach*(1-withdraw))
		return {"body":body_at,"origin":origin,"hand":hand,"pose":lerpf(.8,2.3,reach),"curl":.50,"alpha":smoothstep(-.17,-.11,q)*(1-withdraw)*.90,"heavy":true,"index":-1}
	var index:=rush_index()
	if index<0:return {}
	var q:=age-float(HITS[index])
	if q<-.09 or q>=.115:return {}
	var target: Vector2=HOMES.values()[index%HOMES.size()] if not HOMES.is_empty() else home+Vector2(-320,0)
	var reach:=pow(smoothstep(-.09,0,q),1.45)
	var withdraw:=smoothstep(.025,.115,q)
	var start:=home+Vector2(-28 if index%2 else 12,-12 if index%3 else 10)
	var contact:=target+Vector2(145+float(index%3)*12,10 if index%2 else -8)
	var body_at:=start.lerp(contact,reach).lerp(start,withdraw)
	body_at.y-=sin(reach*PI)*(14 if index%2 else 8)*(1-withdraw)
	var origin:=body_at+Vector2(1,-86)
	var hand:=origin.lerp(target+Vector2(0,-35),reach*(1-withdraw))
	var contact_pose:=1.95 if index%2 else 2.22
	var pose:=lerpf(.80,contact_pose,reach)
	if q>0:pose=lerpf(contact_pose,3.2,withdraw)
	return {"body":body_at,"origin":origin,"hand":hand,"pose":pose,"curl":smoothstep(-.03,.025,q)*(1-withdraw),"alpha":smoothstep(-.09,-.055,q)*(1-withdraw)*.85,"heavy":false,"index":index}
func _draw_bear_rush(ci: CanvasItem) -> void:
	var state:=combo_state()
	if state.is_empty():return
	var opacity: float=state.alpha
	var body_at: Vector2=state.body
	super.stamp(ci,"awakened_single",float(state.pose),body_at,Color(1,1,1,opacity))
	var origin: Vector2=state.origin;var hand: Vector2=state.hand
	var elbow:=origin.lerp(hand,.48)+Vector2(0,-30 if int(state.index)%2==0 else 18)
	var heavy: bool=state.heavy
	sleeve(ci,origin,elbow,34 if heavy else 23,opacity)
	sleeve(ci,elbow,hand+Vector2(0,60 if heavy else 37),42 if heavy else 29,opacity)
	super.stamp(ci,"giant_claw" if heavy else "hand",float(state.curl),hand,Color(1,1,1,opacity))

func update_actors() -> void:
	if kind!="awakened_all":super.update_actors();return
	if not is_instance_valid(production_stage):return
	var index:=rush_index()
	for id in HOMES:
		var actor: Control=production_stage._visuals[id]
		if not originals.has(id):originals[id]={"modulate":actor.modulate,"z":actor.z_index,"relative":actor.z_as_relative}
		actor.z_as_relative=bool(originals[id].relative);actor.z_index=int(originals[id].z);actor.modulate=originals[id].modulate
		if index>=0 and id==HOMES.keys()[index%HOMES.size()]:
			var q:=age-float(HITS[index])
			if q>=0 and q<.11:
				production_stage._pose(id,11)
				actor.position=production_stage._homes[id]+Vector2(-sin(q/.11*PI)*9,0).round()
