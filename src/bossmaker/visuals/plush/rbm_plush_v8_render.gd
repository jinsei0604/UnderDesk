extends "res://src/bossmaker/visuals/plush/rbm_plush_v7_render.gd"
## V8 isolated review: a single bear, a brief looming face and translucent mist.
const Previous=preload("res://src/bossmaker/visuals/plush/rbm_plush_v7_render.gd")
const Art8=preload("res://src/bossmaker/visuals/plush/rbm_plush_v8_data.gd")
const Mist=preload("res://src/bossmaker/visuals/plush/rbm_plush_mist.gd")
const LOCAL_SOUNDS=["loom_jolt","cloth_hit_0","cloth_hit_1","cloth_hit_2","cloth_finish"]
var new_sheets: Array[Texture2D]=[]
var sound_streams: Dictionary={}

static func clip_duration(key: String) -> float:
	return float(Art8.ART.duration[key]) if Art8.ART.duration.has(key) else Previous.clip_duration(key)
static func clip_impact(key: String) -> float:
	return float(Art8.ART.impact[key]) if Art8.ART.impact.has(key) else Previous.clip_impact(key)
static func extra_paths() -> Array[String]:
	var paths:=Mist.paths()
	for key in LOCAL_SOUNDS:paths.append(Mist.ROOT+"audio/"+key+".wav")
	return paths
func _ready() -> void:
	super._ready()
	for path in Mist.paths():new_sheets.append(load(path))
	for key in LOCAL_SOUNDS:sound_streams[key]=load(Mist.ROOT+"audio/"+key+".wav")
func local_sound(key: String,mark: String,gain: float=0.0,pitch: float=1.0) -> void:
	if sound_marks.has(mark) or not is_instance_valid(production_stage):return
	sound_marks[mark]=true
	audio.muted=production_stage._sound.muted
	if audio.muted or audio._players.is_empty():return
	# The existing capped voice pool supplies cancellation and visibility cleanup.
	var player: AudioStreamPlayer=audio._players[audio._next]
	audio._next=(audio._next+1)%audio._players.size()
	player.stop();player.stream=sound_streams[key];player.volume_db=-9.0+gain;player.pitch_scale=pitch;player.play()
func stamp8(ci: CanvasItem,key: String,t: float,pos: Vector2,tint: Color=Color.WHITE,integer_scale: int=1) -> void:
	var clip: Dictionary=Art8.ART.animations[key]
	var ref: Dictionary=clip.frames[clampi(int(t*float(clip.fps)+.0001),0,clip.frames.size()-1)]
	var m: Dictionary=Art8.ART.frames[int(ref.id)]
	var r:=Rect2(m.rect[0],m.rect[1],m.rect[2],m.rect[3])
	var offset:=Vector2(m.offset[0],m.offset[1])*integer_scale
	ci.draw_texture_rect_region(new_sheets[int(m.page)],Rect2((pos+offset).round(),r.size*integer_scale),r,tint)
func stamp(ci: CanvasItem,key: String,t: float,pos: Vector2,tint: Color=Color.WHITE,flip: bool=false) -> void:
	if key=="aura":Mist.paint(ci,new_sheets,age,pos,tint.a);return
	super.stamp(ci,key,t,pos,tint,flip)
func draw_aura(foot: Vector2,time: float,power: float) -> void:
	Mist.paint(self,new_sheets,time,foot,power)

func show_action(key: String,t: float) -> void:
	if not key in ["awakening","awakened_all"]:
		super.show_action(key,t)
		return
	is_new=true;kind=key;age=t;at=t;boss=home;anim=key;frame_record={"v8":true}
	screen_fx.visible=false;space.visible=false;support_display.visible=false
	support_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	veil.visible=true;dark_front.visible=true
	if key=="awakening":
		if t>=float(Art8.ART.loom_time):
			if not sound_marks.has("loom"):camera.shake(5,.16)
			local_sound("loom_jolt","loom",-1)
	else:
		var hits: Array=Art8.ART.rush_times
		for i in hits.size():
			if t>=float(hits[i]):
				var mark:="rush_"+str(i)
				if not sound_marks.has(mark):camera.shake(1.6,.055)
				local_sound("cloth_hit_"+str(i%3),mark,-3 if i<4 else -1,.97+float(i%3)*.03)
	camera.advance(maxf(0,t-old_age));old_age=t
	queue_redraw();front.queue_redraw();veil.queue_redraw();dark_front.queue_redraw()
func on_impact(key: String) -> void:
	if key=="awakening":return
	if key=="awakened_all":
		camera.shake(6,.23);local_sound("cloth_finish","finish",0)
		return
	super.on_impact(key)

func blackout() -> float:
	if kind=="awakening":return smoothstep(.90,1.02,age)*(1-smoothstep(2.28,2.75,age))
	return smoothstep(.40,.72,age)*(1-smoothstep(3.82,4.23,age))
func rush_index() -> int:
	var index:=-1
	for i in Art8.ART.rush_times.size():
		if age>=float(Art8.ART.rush_times[i])-.085:index=i
	return index
func _draw() -> void:
	if kind=="awakening":
		if age<1.08:stamp8(self,"omen",age,home)
		elif age>=2.38:
			Mist.paint(self,new_sheets,age,home,smoothstep(2.38,3.15,age))
			stamp8(self,"reveal",maxf(0,age-2.75),home)
			Mist.paint(self,new_sheets,age,home,smoothstep(2.38,3.15,age),true)
		return
	if kind=="awakened_all":
		if age<.72 or age>3.82:
			Mist.paint(self,new_sheets,age,home,1.0)
			if age<.72:super.stamp(self,"awakened_single",age*.65,home)
			else:stamp8(self,"rush_finish",age-3.12,home)
			Mist.paint(self,new_sheets,age,home,1.0,true)
		return
	super._draw()
	if kind.begins_with("awakened"):Mist.paint(self,new_sheets,age,boss,.8,true)
func draw_foreground(ci: CanvasItem) -> void:
	if kind in ["awakening","awakened_all"]:return
	super.draw_foreground(ci)
func draw_darkness(ci: CanvasItem,foreground: bool=false) -> void:
	if not kind in ["awakening","awakened_all"]:return
	var dark:=blackout()
	if not foreground:
		if dark>0:ci.draw_rect(Rect2(Vector2.ZERO,size),Color(.005,.003,.011,dark))
		if kind=="awakened_all" and age>=.72 and age<=3.82:
			# Exactly one body. No shadow copies or afterimages.
			Mist.paint(ci,new_sheets,age,home,.5)
			var tint:=Color(.66,.55,.77)
			if age<1.0:super.stamp(ci,"awakened_single",.8,home,tint)
			elif age<2.95:stamp8(ci,"rush_body",fmod(maxf(0,age-1.0),.5),home,tint)
			else:stamp8(ci,"rush_finish",maxf(0,age-3.12),home,tint)
			Mist.paint(ci,new_sheets,age,home,.5,true)
		return
	if kind=="awakening":
		if age>=1.72 and age<2.58:
			var t:=age-1.72
			var lunge:=1-pow(1-clampf(t/.09,0,1),3)
			var retreat:=smoothstep(.44,.86,t)
			var pos:=Vector2(640+24*(1-lunge),300+115*(1-lunge)+55*retreat)
			stamp8(ci,"loom",minf(t,.46),pos,Color(1,1,1,1-retreat),4)
		return
	_draw_rush(ci)

func _draw_rush(ci: CanvasItem) -> void:
	var index:=rush_index()
	if index>=0:
		var q:=age-float(Art8.ART.rush_times[index])
		if q<.14:
			var id: String=HOMES.keys()[index%HOMES.size()]
			var target: Vector2=HOMES[id]+Vector2(0,-37)
			var origin:=home+Vector2(-3,-86)
			var outward:=pow(smoothstep(-.085,0,q),2)
			var back:=smoothstep(.035,.14,q)
			var hand:=origin.lerp(target,outward*(1-back))
			var elbow:=origin.lerp(hand,.48)+Vector2(0,(-52 if index%2==0 else 36)*outward*(1-back))
			var opacity:=smoothstep(-.085,-.065,q)*(1-smoothstep(.10,.14,q))
			sleeve(ci,origin,elbow,25,opacity);sleeve(ci,elbow,hand+Vector2(0,37),32,opacity)
			super.stamp(ci,"hand",.7+.3*smoothstep(-.05,0,q),hand,Color(.91,.82,1,opacity))
			if q>=0:super.stamp(ci,"impact",q*2.4,target,Color(1,1,1,.86*(1-smoothstep(.06,.14,q))))
	if age>=3.12 and age<4.15:
		var out:=pow(smoothstep(3.24,3.46,age),2)
		var back:=smoothstep(3.62,4.15,age)
		var origin:=home+Vector2(-3,-86)
		var hand:=Vector2(910,220).lerp(Vector2(280,425),out).lerp(origin,back)
		var elbow:=origin.lerp(hand,.5)+Vector2(0,-70*(1-back))
		var opacity:=smoothstep(3.12,3.22,age)*(1-smoothstep(4.0,4.15,age))
		sleeve(ci,origin,elbow,42,opacity);sleeve(ci,elbow,hand+Vector2(0,60),53,opacity)
		super.stamp(ci,"giant_claw",.5,hand,Color(1,1,1,opacity))
	if age>=3.46 and age<4.0:
		for foot in HOMES.values():super.stamp(ci,"impact",age-3.46,foot+Vector2(0,-25),Color(1,1,1,1-smoothstep(3.75,4.0,age)))

func update_actors() -> void:
	if kind!="awakened_all":super.update_actors();return
	if not is_instance_valid(production_stage):return
	var index:=rush_index()
	for id in HOMES:
		var actor: Control=production_stage._visuals[id]
		if not originals.has(id):originals[id]={"modulate":actor.modulate,"z":actor.z_index,"relative":actor.z_as_relative}
		var dark:=blackout()
		actor.z_as_relative=false;actor.z_index=91 if dark>.15 else int(originals[id].z)
		actor.modulate=Color.WHITE.lerp(Color(.42,.32,.53,1),dark)
		if index>=0 and id==HOMES.keys()[index%HOMES.size()]:
			var q:=age-float(Art8.ART.rush_times[index])
			if q>=0 and q<.13:
				production_stage._pose(id,11);actor.modulate=Color(.82,.71,.93)
				actor.position=production_stage._homes[id]+Vector2(-sin(q/.13*PI)*9,0).round()
