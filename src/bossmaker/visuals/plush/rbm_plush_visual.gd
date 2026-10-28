extends "res://src/bossmaker/visuals/rbm_character_visual.gd"
## Static approved rest pose; a native hit clip starts only on a real impact flash.
const NormalHit=preload("res://src/bossmaker/visuals/plush/rbm_plush_normal_hit.gd")
const AwakenedHit=preload("res://src/bossmaker/visuals/plush/rbm_plush_awakened_hit.gd")
const Mist=preload("res://src/bossmaker/visuals/plush/rbm_plush_mist.gd")
var _mist_sheets: Array[Texture2D]=[]
var _mist_age:=0.0
var _hit_sheet: Texture2D
var _aura_rest: Texture2D
var _hit_age:=-1.0
var _hit_rects: Array=[]

func setup(id: String,height: float) -> void:
	super.setup(id,height)
	_hit_age=-1.0
	_hit_sheet=load(Assets.ROOT+id+"/hit.png")
	_hit_rects=AwakenedHit.RECTS if id=="plush_awakened" else NormalHit.RECTS
	_aura_rest=null
	_mist_sheets.clear()
	if id=="plush_awakened":
		for path in Mist.paths():_mist_sheets.append(load(path))

func impact_flash() -> void:
	super.impact_flash()
	_hit_age=0.0

func _process(delta: float) -> void:
	super._process(delta)
	if not _mist_sheets.is_empty() and is_visible_in_tree():
		_mist_age=fmod(_mist_age+delta,4.0)
		queue_redraw()
	if _hit_age>=0:
		_hit_age+=delta
		if _hit_age>=float(_hit_rects.size())/15.0:_hit_age=-1.0
		queue_redraw()

func _draw() -> void:
	if not _mist_sheets.is_empty():Mist.paint(self,_mist_sheets,_mist_age,foot_position())
	if _hit_age>=0 and _hit_sheet!=null:
		var r: Array=_hit_rects[clampi(int(_hit_age*15),0,_hit_rects.size()-1)]
		draw_texture_rect_region(_hit_sheet,Rect2(foot_position()-Vector2(128,232),Vector2(256,256)),Rect2(r[0],r[1],256,256),Color(1.5,1.25,1.15) if _flash>0 else Color.WHITE)
	else:super._draw()
	if not _mist_sheets.is_empty():Mist.paint(self,_mist_sheets,_mist_age,foot_position(),1.0,true)
