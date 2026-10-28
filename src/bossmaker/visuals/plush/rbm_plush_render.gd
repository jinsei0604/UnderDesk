extends Control
## Approved native v6 artwork. Receives resolved feet from the production presentation.
const Data=preload("res://src/bossmaker/visuals/plush/rbm_plush_data.gd")
const Front=preload("res://src/bossmaker/visuals/plush/rbm_plush_front.gd")
const Single=preload("res://src/bossmaker/visuals/plush/rbm_plush_claw.gd")
const Rift=preload("res://src/bossmaker/visuals/plush/rbm_plush_lightning.gd")
const Revision=preload("res://src/bossmaker/visuals/plush/rbm_plush_fx.gd")
const ScreenFX=preload("res://src/bossmaker/visuals/plush/rbm_plush_screen.gd")
const Support=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")
const Audio=preload("res://src/bossmaker/rbm_audio.gd")
const ROOT="res://assets_bossmaker/battle/plush/"
const IMPACT={"normal_single":.933333,"normal_all":1.5,"normal_heal":1.8,"normal_buff":1.8,"awakened_single":1.5,"awakened_all":2.35,"awakened_heal":2.2,"awakened_buff":2.2,"awakening":4.9}
var data: Dictionary=Data.ANIMATION
var fxdata: Dictionary=Data.FX
var aura_data: Dictionary=Data.AURA
var atlas: Texture2D
var fxatlas: Texture2D
var aura_atlas: Texture2D
var support: Node2D
var support_view: SubViewport
var support_display: Sprite2D
var screen_fx: Node2D
var space: ColorRect
var space_material: ShaderMaterial
var front: Node2D
var camera: RefCounted
var production_stage: Control
var home:=Vector2(780,474)
var HOMES: Dictionary={}
var age:=0.0
var old_age:=0.0
var kind:="normal_idle"
var boss:=Vector2(780,474)
var anim:="normal_idle"
var at:=0.0
var aura:=0.0
var compare:=false
var frame_record: Dictionary={}
var sound_marks: Dictionary={}
var audio: Node

func target_foot() -> Vector2:
	return HOMES.values()[0] if not HOMES.is_empty() else home+Vector2(-200,50)

func _ready() -> void:
	size=Vector2(1280,720);mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	audio=Audio.for_owner(self)
	atlas=load(ROOT+"poses.png");fxatlas=load(ROOT+"fx.png");aura_atlas=load(ROOT+"aura-v5.png")
	front=Front.new();front.stage=self;front.z_index=4;add_child(front)
	support_view=SubViewport.new();support_view.size=Vector2i(320,180);support_view.transparent_bg=true
	support_view.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(support_view)
	support=Support.new();support_view.add_child(support)
	support_display=Sprite2D.new();support_display.texture=support_view.get_texture();support_display.centered=false
	support_display.scale=Vector2(4,4);support_display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	support_display.z_index=5;support_display.visible=false;add_child(support_display)
	# Keep both screen effects below stage DamageNumbers (z=120) and outside the HUD.
	screen_fx=ScreenFX.new();screen_fx.stage=self;screen_fx.z_as_relative=false;screen_fx.z_index=90;add_child(screen_fx)
	space=ColorRect.new();space.size=size;space.mouse_filter=Control.MOUSE_FILTER_IGNORE
	space.z_as_relative=false;space.z_index=89;space.visible=false
	space_material=ShaderMaterial.new();space_material.shader=preload("res://src/bossmaker/visuals/plush/rbm_plush_space.gdshader")
	space.material=space_material;add_child(space)

func sound(key: String,pitch: float=1.0,mark: String="") -> void:
	var token:=key if mark.is_empty() else mark
	if sound_marks.has(token) or not is_instance_valid(production_stage):return
	sound_marks[token]=true
	# A boss-local instance of the existing audio owner retains the approved pitches.
	# Its voice pool cannot leave a changed pitch in another actor's sound player.
	audio.muted=production_stage._sound.muted
	if not audio._players.is_empty():audio._players[audio._next].pitch_scale=pitch
	audio.play_sound(key)

func ease_range(a: float,b: float,t: float) -> float:return smoothstep(a,b,t)
func current_frame(key: String, time: float) -> Dictionary:
	var a: Dictionary=data.animations[key]
	var ix:=clampi(int(time*float(a.fps)+.00001),0,a.frames.size()-1)
	return a.frames[ix]

func draw_pose(ci: CanvasItem,key: String,time: float,foot: Vector2) -> void:
	var f:=current_frame(key,time);var r: Dictionary=data.frames[int(f.id)]
	var rect:=Rect2(r.rect[0],r.rect[1],r.rect[2],r.rect[3])
	ci.draw_texture_rect_region(atlas,Rect2((foot+Vector2(r.offset[0],r.offset[1])).round(),rect.size),rect)

func fx(ci: CanvasItem,clip: String,index: int,pos: Vector2,alpha: float=1.0,floor_y: float=10000) -> void:
	var list: Array=fxdata.clips[clip]
	var f: Dictionary=fxdata.frames[int(list[posmod(index,list.size())])]
	var rect:=Rect2(f.rect[0],f.rect[1],f.rect[2],f.rect[3])
	var top: Vector2=(pos-Vector2(f.anchor[0],f.anchor[1])).round()
	rect.size.y=minf(rect.size.y,maxf(0,floor_y-top.y))
	if rect.size.y>0:ci.draw_texture_rect_region(fxatlas,Rect2(top,rect.size),rect,Color(1,1,1,clampf(alpha,0,1)))

func show_action(key: String,time: float) -> void:
	kind=key;age=time;boss=home;at=time
	compare=key=="comparison"
	var aw:=key.begins_with("awakened")
	aura=.62 if aw else 0.0
	anim=key.replace("_heal","_support").replace("_buff","_support").replace("awakening_wide","awakening")
	if compare:anim="normal_idle";at=0
	elif key.ends_with("idle"):at=0
	elif key.begins_with("awakening"):
		aura=smoothstep(1.6,3.4,time)*(1.0-.38*smoothstep(4.9,6.5,time))
		if camera!=null and key=="awakening" and time>=1.0 and time<4.9:camera.cut(2,home+Vector2(0,-79))
		elif camera!=null:camera.cut(1,Vector2(640,360))
		if time>=1.3:sound("boss_move_heavy",.86)
		if time>=2.9:sound("wind_cast",.72)
		if time>=4.9:sound("wind_burst",.72)
	elif key=="awakened_single":
		if time>=1.04:sound("neutral_sword_swing",.68,"rift_cut")
		if time>=Single.LAUNCH:sound("wind_burst",.84,"claw_launch")
	elif key=="normal_single":
		var impact:=.933333
		var move:=pow(clampf((time-.53)/(impact-.53),0,1),2)
		var back:=smoothstep(1.55,2.3,time)
		boss=home.lerp(target_foot()+Vector2(90,27),move*(1-back))
		boss.y-=sin(move*PI)*18*(1-back)
		if time>impact-.22:sound("neutral_blunt_swing")
	elif key=="awakened_all":
		if time>=1.15:sound("boss_move_heavy",.65)
		var n:=0
		for id in HOMES:
			if time>=2.35+n*.12:sound("neutral_impact_light",.7+n*.08,"dark_"+id)
			n+=1
	elif key=="awakened_defeat":aura=.62*(1-smoothstep(.7,2.8,time))
	var supporting:=key.ends_with("heal") or key.ends_with("buff")
	support_display.visible=supporting
	support_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if supporting else SubViewport.UPDATE_DISABLED
	support.origin=boss-Vector2(0,10)
	support.age=time-(.7 if aw else .3) if supporting else -1.0
	support.mode="heal" if key.ends_with("heal") else "buff"
	support.queue_redraw()
	frame_record=current_frame(anim,at)
	if key.ends_with("hit") and time>=.06:sound("neutral_impact_light",.85 if aw else 1.0)
	if camera!=null:camera.advance(maxf(0,time-old_age))
	old_age=time
	var active:=key=="awakened_single"
	var opening:=Single.opening(time) if active else 0.0
	# Keep shader warm at zero displacement; hidden for every other accepted action.
	space.visible=active
	space_material.set_shader_parameter("amount",opening)
	space_material.set_shader_parameter("center",target_foot()+Vector2(0,-48))
	queue_redraw();front.queue_redraw();screen_fx.queue_redraw()

func on_impact(key: String) -> void:
	if key.begins_with("awakening"):camera.shake(8,.5);sound("boss_impact_mass",.8)
	elif key.ends_with("single"):
		camera.shake(4 if key.begins_with("awakened") else 2,.24 if key.begins_with("awakened") else .13)
		sound("neutral_impact_heavy",.78 if key.begins_with("awakened") else 1.0)
	elif key.ends_with("all"):camera.shake(5 if key.begins_with("awakened") else 3,.33);sound("boss_impact_mass" if key.begins_with("awakened") else "neutral_impact_heavy")
	elif key.ends_with("heal"):sound("heal_hp")
	elif key.ends_with("buff"):sound("buff_atk")

func draw_aura(foot: Vector2,time: float,power: float) -> void:
	var index:=posmod(int(time*12),48)
	var r: Array=aura_data.frames[index]
	draw_texture_rect_region(aura_atlas,Rect2((foot-Vector2(160,286)).round(),Vector2(320,320)),Rect2(r[0],r[1],320,320),Color(1,1,1,power))

func _draw() -> void:
	if data==null or data.is_empty():return
	if kind.begins_with("awakening"):Revision.awakening_back(self,age,boss)
	if aura>0:draw_aura(boss,0 if kind.ends_with("idle") else age,minf(1,aura*1.3))
	if kind.begins_with("awakening"):Rift.lightning(self,age,boss)
	draw_pose(self,anim,at,boss.round())

func draw_foreground(ci: CanvasItem) -> void:
	if compare or frame_record.is_empty():return
	if kind=="normal_all":
		var n:=0
		for id in HOMES:
			var start:=.86+float(n)*.045
			var progress:=clampf((age-start)/(1.5-start),0,1)
			var target: Vector2=HOMES[id]+Vector2(10,-45)
			if age>=start and age<1.5:
				var pos:=boss+Vector2(-10,-88)
				pos=pos.lerp(target,progress);pos.y-=sin(progress*PI)*(74+n*12)
				fx(ci,"cotton",int(age*15)+n,pos)
			if age>=1.5 and age<2.3:fx(ci,"burst",clampi(int((age-1.5)*15),0,11),target)
			n+=1
	elif kind=="normal_single":
		var dt:=age-float(IMPACT[kind])
		if dt>=0 and dt<.45:
			var hand:=boss+Vector2(frame_record.far_hand[0],frame_record.far_hand[1])
			fx(ci,"impact",clampi(int(dt*20),0,8),hand)
			if kind.begins_with("awakened"):fx(ci,"burst",clampi(int(dt*24),0,11),hand+Vector2(-7,5),.85)
	elif kind=="awakened_single":Single.draw(ci,age,target_foot(),home+Vector2(-134,-104))
	elif kind=="awakened_all":Revision.unknown_front(ci,age,boss)
	elif kind.ends_with("heal") or kind.ends_with("buff"):
		var aw:=kind.begins_with("awakened")
		if age>.55 and age<(2.2 if aw else 1.9):
			var hand:=boss+Vector2(frame_record.hand[0],frame_record.hand[1])
			fx(ci,"needle",0,hand)
			# Only a short sewing stitch, never an attack made from travelling lines.
			for j in range(3):ci.draw_rect(Rect2((hand+Vector2(-8+j*5,8)).round(),Vector2(3,2)),Color("d4c7a6"))
	elif kind.ends_with("hit") and age<.35:fx(ci,"impact",int(age*20),boss+Vector2(-36,-100))
	if kind.begins_with("awakening"):Revision.awakening_front(ci,age,boss,self)
	if kind.ends_with("defeat"):
		for j in range(4):
			var t:=clampf((age-.7-float(j)*.15)/2,0,1)
			if t>0 and t<1:fx(ci,"cotton",j,boss+Vector2(-30+j*22,-60*(1-t)),1-t)
