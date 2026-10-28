extends "res://src/bossmaker/visuals/plush/rbm_plush_v8_render.gd"
## Review-only correction. V8 mist, artwork and every other action stay inherited.
const V8=preload("res://src/bossmaker/visuals/plush/rbm_plush_v8_render.gd")
const STING="res://assets_bossmaker/battle/plush/v12/audio/awakening_scream.wav"
const BLACK_START:=2.60
const BLACK_FULL:=2.70
const JUMP:=3.40
const FACE_END:=3.68
const REVEAL:=3.68
const FINISH:=3.48
const CLEAR_START:=4.45
const CLEAR_END:=5.30
const RUSH=[1.35,1.57,1.76,1.93,2.09,2.24,2.38,2.51,2.63,2.75,2.87,2.99]

static func clip_duration(key: String) -> float:
	if key=="awakening":return 6.5
	if key=="awakened_all":return 5.6
	return V8.clip_duration(key)
static func clip_impact(key: String) -> float:
	if key=="awakening":return REVEAL
	if key=="awakened_all":return FINISH
	return V8.clip_impact(key)
static func extra_paths() -> Array[String]:
	var paths:=V8.extra_paths();paths.append(STING);return paths
func _ready() -> void:
	super._ready()
	sound_streams["loom_jolt_v9"]=load(STING)
	# Darkness is screen-locked; the attacking fragments retain camera shake.
	veil.top_level=true
	veil.global_position=Vector2.ZERO

func face_visible() -> bool:
	return kind=="awakening" and age>=JUMP and age<FACE_END
func blackout() -> float:
	if kind=="awakening":
		# One boundary controls BOTH the end of black and the beginning of the face.
		return smoothstep(BLACK_START,BLACK_FULL,age) if age<JUMP else 0.0
	return smoothstep(.72,1.08,age)*(1-smoothstep(CLEAR_START,CLEAR_END,age))
func rush_index() -> int:
	var index:=-1
	for i in RUSH.size():
		if age>=float(RUSH[i])-.050:index=i
	return index
func show_action(key: String,t: float) -> void:
	if not key in ["awakening","awakened_all"]:
		super.show_action(key,t);return
	is_new=true;kind=key;age=t;at=t;boss=home;anim=key;frame_record={"v9":true}
	screen_fx.visible=false;space.visible=false;support_display.visible=false
	support_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	veil.visible=true;dark_front.visible=true
	if key=="awakening":
		if t> .55 and t<BLACK_FULL:camera.cut(2,home+Vector2(0,-86))
		elif t>=REVEAL and t<3.90:camera.cut(2,home+Vector2(0,-86))
		else:camera.cut(1,Vector2(640,360))
		if t<BLACK_FULL:
			if t>=1.2:sound("neutral_blunt_swing",.52,"seam0")
			if t>=1.9:sound("neutral_impact_light",.53,"seam1")
		if t>=BLACK_FULL and not sound_marks.has("silence"):
			audio.stop_all();sound_marks["silence"]=true
		if t>=JUMP:
			local_sound("loom_jolt_v9","loom",-1)
	else:
		if t>=.85:sound("boss_move_heavy",.47,"door")
		if t>=1.08 and not sound_marks.has("dark_silence"):
			audio.stop_all();sound_marks["dark_silence"]=true
		for i in RUSH.size():
			if t>=float(RUSH[i]):
				var mark:="rush_"+str(i)
				if not sound_marks.has(mark):camera.shake(2.5,.075)
				local_sound("cloth_hit_"+str(i%3),mark,-2 if i<4 else -1,.94+float(i%3)*.035)
		if t>=4.15 and not sound_marks.has("end_silence"):
			audio.stop_all();sound_marks["end_silence"]=true
	camera.advance(maxf(0,t-old_age));old_age=t
	queue_redraw();front.queue_redraw();veil.queue_redraw();dark_front.queue_redraw()
func on_impact(key: String) -> void:
	if key=="awakening":return
	if key=="awakened_all":
		camera.shake(5,.22);local_sound("cloth_finish","finish",0);return
	super.on_impact(key)

func _draw() -> void:
	if kind=="awakening":
		if age<BLACK_FULL:
			# Exact V7 native anticipation poses and its integer 2x camera cut.
			super.stamp(self,"awakening",minf(age,BLACK_START),home)
		elif age>=REVEAL:
			Mist.paint(self,new_sheets,age,home,1)
			super.stamp(self,"awakening",minf(7.2,4.25+age-REVEAL),home)
			Mist.paint(self,new_sheets,age,home,1,true)
		return
	if kind=="awakened_all":
		if age<1.08:
			Mist.paint(self,new_sheets,age,home,1)
			super.stamp(self,"awakened_all",age,home)
			Mist.paint(self,new_sheets,age,home,1,true)
		elif age>=CLEAR_START:
			Mist.paint(self,new_sheets,age,home,1)
			super.stamp(self,"awakened_all",5.8,home)
			Mist.paint(self,new_sheets,age,home,1,true)
		return
	super._draw()

func draw_darkness(ci: CanvasItem,foreground: bool=false) -> void:
	if not kind in ["awakening","awakened_all"]:return
	if not foreground:
		var dark:=blackout()
		# Overscan prevents a camera shake exposing bright strips at screen edges.
		if dark>0:ci.draw_rect(Rect2(-32,-32,1344,784),Color(0,0,0,dark))
		return
	if kind=="awakening":
		if face_visible():
			# The real battlefield is already visible, not a portrait on a black card.
			ci.draw_rect(Rect2(-32,-32,1344,784),Color(.62,.57,.63,.16))
			_draw_face(ci,age-JUMP)
		return
	_draw_rush(ci)

func _draw_face(ci: CanvasItem,t: float) -> void:
	var clip: Dictionary=Art8.ART.animations.loom
	var ref: Dictionary=clip.frames[clampi(int(t*float(clip.fps)),0,clip.frames.size()-1)]
	var m: Dictionary=Art8.ART.frames[int(ref.id)]
	var offset:=Vector2(m.offset[0],m.offset[1])
	var bounds:=Rect2(offset,Vector2(m.rect[2],m.rect[3]))
	# Crop at native pixel boundaries. A fixed integer close-up, never a zoom tween.
	var crop:=bounds
	var source:=Rect2(Vector2(m.rect[0],m.rect[1])+crop.position-offset,crop.size)
	ci.draw_texture_rect_region(new_sheets[int(m.page)],Rect2(Vector2(640,354)+crop.position*10,crop.size*10),source)

func _hand_fragment(ci: CanvasItem,key: String,curl: float,point: Vector2,opacity: float,flip: bool=false) -> void:
	var ref:=new_frame(key,curl);var m: Dictionary=NewArt.ART.frames[int(ref.id)]
	var whole:=Rect2(m.rect[0],m.rect[1],m.rect[2],m.rect[3])
	var offset:=Vector2(m.offset[0],m.offset[1])
	# Only knuckles, fingertips and a fraction of the torn palm are visible. The
	# sleeve, wrist, body and source location remain completely absent in darkness.
	var fragment:=Rect2(whole.position,Vector2(whole.size.x,ceilf(whole.size.y*.64)))
	ci.draw_set_transform(point.round(),0,Vector2(-1 if flip else 1,1))
	var solid_height:=fragment.size.y-16
	ci.draw_texture_rect_region(sheets[int(m.page)],Rect2(offset.round(),Vector2(fragment.size.x,solid_height)),Rect2(fragment.position,Vector2(fragment.size.x,solid_height)),Color(.47,.36,.60,opacity))
	# Four native pixel bands dissolve the partial palm into black, no blur/filter.
	for strip in range(4):
		var shift:=Vector2(0,solid_height+strip*4)
		var dimensions:=Vector2(fragment.size.x,4)
		ci.draw_texture_rect_region(sheets[int(m.page)],Rect2(offset.round()+shift,dimensions),Rect2(fragment.position+shift,dimensions),Color(.47,.36,.60,opacity*float(4-strip)/5))
	ci.draw_set_transform(Vector2.ZERO)
func _draw_rush(ci: CanvasItem) -> void:
	var index:=rush_index()
	if index>=0 and not HOMES.is_empty():
		var q:=age-float(RUSH[index])
		if q>=-.050 and q<.065:
			var target: Vector2=HOMES.values()[index%HOMES.size()]+Vector2(0,-34)
			var travel:=smoothstep(-.050,.012,q)
			var start:=target+Vector2(78 if index%2==0 else -70,-51 if index%3 else 38)
			var opacity:=smoothstep(-.050,-.025,q)*(1-smoothstep(.012,.065,q))*.80
			_hand_fragment(ci,"hand",.65+.35*travel,start.lerp(target,travel),opacity,index%2==1)
	if age>=FINISH-.085 and age<FINISH+.13:
		var travel:=pow(smoothstep(FINISH-.085,FINISH,age),2)
		var target:=Vector2(340,431)
		if not HOMES.is_empty():
			target=Vector2.ZERO
			for foot in HOMES.values():target+=foot
			target=target/HOMES.size()+Vector2(0,-25)
		var opacity:=smoothstep(FINISH-.085,FINISH-.050,age)*(1-smoothstep(FINISH+.025,FINISH+.13,age))*.85
		_hand_fragment(ci,"giant_claw",.50,target+Vector2(95,-90)*(1-travel),opacity)

func update_actors() -> void:
	if kind!="awakened_all":super.update_actors();return
	if not is_instance_valid(production_stage):return
	var index:=rush_index()
	for id in HOMES:
		var actor: Control=production_stage._visuals[id]
		if not originals.has(id):originals[id]={"modulate":actor.modulate,"z":actor.z_index,"relative":actor.z_as_relative}
		# The real victims stay behind the opaque veil. No persistent silhouettes.
		actor.z_as_relative=bool(originals[id].relative);actor.z_index=int(originals[id].z)
		actor.modulate=originals[id].modulate
		if index>=0 and id==HOMES.keys()[index%HOMES.size()]:
			var q:=age-float(RUSH[index])
			if q>=0 and q<.11:
				production_stage._pose(id,11)
				actor.position=production_stage._homes[id]+Vector2(-sin(q/.11*PI)*9,0).round()
