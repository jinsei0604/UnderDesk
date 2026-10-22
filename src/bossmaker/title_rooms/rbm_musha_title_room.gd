extends Node2D
const ROOM=preload("res://assets_bossmaker/title_rooms/musha/room.png")
const COMPLETE=preload("res://assets_bossmaker/title_rooms/musha/seated_cleaning.png")
const BATTLE=preload("res://assets_bossmaker/battle/backgrounds/musha/background.png")
const ORIGIN=Vector2(208,100)
var t: float=0.0
var actor: Sprite2D
var environment: QuietRoom
var decor_view: SubViewport

class QuietRoom:
	extends Node2D
	var time: float=0.0
	func _draw() -> void:
		for i in range(3):
			var f: float=fposmod(time*.10+i/3.0,1.0)
			var p: Vector2=Vector2(120+sin(f*5.0+i)*1.5,107-f*12)
			draw_line(p.round(),(p+Vector2(1,-3)).round(),Color(.68,.65,.58,sin(f*PI)*.17),1,false)
		draw_rect(Rect2(17,101,14,23),Color(1,.7,.3,.018+.009*sin(time*TAU/5.0)))

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	# Preserve the approved 320x180 room pixels; character uses the astronaut's
	# 640x360 presentation grid, with matching thin outline and flat shading.
	decor_view=SubViewport.new();decor_view.size=Vector2i(320,180);decor_view.disable_3d=true
	decor_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	decor_view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(decor_view)
	var decor:=Node2D.new();decor_view.add_child(decor)
	var backdrop:=Sprite2D.new();backdrop.centered=false;backdrop.texture=decor_view.get_texture()
	backdrop.scale=Vector2(2,2);add_child(backdrop)
	var forest:=Sprite2D.new();forest.centered=false
	var bamboo:=AtlasTexture.new();bamboo.atlas=BATTLE;bamboo.region=Rect2(0,0,128,128)
	forest.texture=bamboo
	forest.position=Vector2(194,11);decor.add_child(forest)
	var interior:=Sprite2D.new();interior.centered=false;interior.texture=ROOM;decor.add_child(interior)
	environment=QuietRoom.new();decor.add_child(environment)
	actor=Sprite2D.new();actor.name="CompleteCharacterAndSword";actor.centered=false
	actor.texture=COMPLETE;actor.hframes=8;actor.vframes=3;actor.position=ORIGIN;add_child(actor)
	# Each cel includes the naturally connected head, neck, shoulders, arms,
	# hands and complete sword. Seat/floor registration preserves the original
	# small head follow-through: no fixed eye anchor or copied head layer.
	advance(0)

func cleaning_frame(local: float) -> int:
	# 24 intact cels at 15 drawings/sec: each gets exactly two 30fps frames.
	# Wipe back through the same complete cels to preserve the approved motion.
	var tick: int=roundi(local*30.0)
	if tick<48:return mini(23,tick/2)
	if tick<52:return 23
	if tick<100:return maxi(0,23-(tick-52)/2)
	return 0

func advance(seconds: float) -> void:
	t=fposmod(seconds,40.0)
	var cel: int=0
	for onset in [4.0,14.0,24.0,34.0]:
		if t>=onset and t<onset+3.4:cel=cleaning_frame(t-onset)
	actor.frame=cel
	environment.time=t;environment.queue_redraw()

func set_presentation_active(active: bool) -> void:
	decor_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
