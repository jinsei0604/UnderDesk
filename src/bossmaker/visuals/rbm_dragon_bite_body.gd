extends Node2D
## Approved v3 bite frames use the rear heel as the grounded animation pivot.
const ROOT="res://assets_bossmaker/battle/dragon/bite/"
var state: Dictionary={}
var _foot:=Vector2(384,460)
var _canvas:=Vector2(768,512)
var _pixel_scale:=.75
var _poses: Array=[]
static var _textures: Array[Texture2D]=[]

func configure(stage: Control) -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_scale=stage.Assets.display_height("dragon")/240.0
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"frames.json"))
	_foot=Vector2(data.foot[0],data.foot[1])
	_canvas=Vector2(data.canvas[0],data.canvas[1])
	_poses=data.poses
	if _textures.is_empty():
		for i in range(12): _textures.append(load(ROOT+"%02d.png" % i))

func anchor_offset() -> Vector2:
	# Matches the approved preview's rear heel at 915 against the actor home at 840.
	return Vector2(100,0)*_pixel_scale

func local_point(pose: int,kind: String) -> Vector2:
	var point: Array=_poses[pose][kind]
	return (Vector2(point[0],point[1])-_foot)*_pixel_scale

func mouth_point() -> Vector2:
	return Vector2(state.foot)+local_point(int(state.pose),"mouth")

func foot_point() -> Vector2: return state.foot

func advance(sample: Dictionary) -> void:
	state=sample.duplicate()
	queue_redraw()

func _draw() -> void:
	if state.is_empty(): return
	draw_texture_rect(_textures[int(state.pose)],Rect2((Vector2(state.foot)-_foot*_pixel_scale).round(),_canvas*_pixel_scale),false)
