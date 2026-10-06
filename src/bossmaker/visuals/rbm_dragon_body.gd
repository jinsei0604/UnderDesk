extends Node2D
## Dragon pose textures and anchors for breath, roar and awakening.
const Assets=preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
const NORMAL_MARKS=[
	[Vector2(75,204),Vector2(102,184),Vector2(343,229)],
	[Vector2(443,222),Vector2(461,185),Vector2(716,217)],
	[Vector2(810,259),Vector2(825,227),Vector2(1115,226)],
	[Vector2(1212,202),Vector2(1242,182),Vector2(1455,221)],
	[Vector2(114,440),Vector2(150,424),Vector2(325,528)],
	[Vector2(425,533),Vector2(449,507),Vector2(725,538)],
	[Vector2(843,578),Vector2(876,550),Vector2(1083,509)],
	[Vector2(1211,503),Vector2(1240,477),Vector2(1450,518)],
	[Vector2(114,727),Vector2(147,715),Vector2(328,823)],
	[Vector2(514,731),Vector2(548,709),Vector2(729,827)],
	[Vector2(812,869),Vector2(842,822),Vector2(1077,832)],
	[Vector2(1192,801),Vector2(1222,771),Vector2(1450,821)]]
var state: Dictionary={}
var _stage: Control
var asset_id:="dragon"
var _pixel_scale:=.75
var _foot:=Vector2(256,460)
var _canvas:=Vector2(512,512)
var _poses: Array=[]

func configure(stage: Control) -> void:
	_stage=stage
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	refresh_asset()

func refresh_asset() -> void:
	asset_id=str(_stage._asset_ids["boss"])
	var actor: Control=_stage._visuals["boss"]
	_pixel_scale=actor._pixel_scale
	_foot=actor._foot
	_canvas=actor._canvas_size
	var metadata=JSON.parse_string(FileAccess.get_file_as_string(Assets.ROOT+asset_id+"/frames.json"))
	_poses=metadata.get("poses",[]) if metadata is Dictionary else []
	queue_redraw()

func advance(sample: Dictionary) -> void:
	state=sample.duplicate()
	queue_redraw()

func raw_point(pose: int,kind: String) -> Vector2:
	var record: Dictionary=_poses[clampi(pose,0,_poses.size()-1)]
	if record.has("landmarks"):
		var point: Array=record.landmarks[kind]
		return Vector2(point[0],point[1])
	var point: Vector2=NORMAL_MARKS[pose][{"mouth":0,"eye":1,"tail":2}[kind]]
	var source: Array=record.source_bbox
	var bounds: Array=record.bbox
	return Vector2(bounds[0],bounds[1])+(point-Vector2(source[0],source[1]))*Vector2(float(bounds[2])/source[2],float(bounds[3])/source[3])

func local_point(pose: int,kind: String) -> Vector2:
	return (raw_point(pose,kind)-_foot)*_pixel_scale

func world_point(kind: String) -> Vector2:
	if state.is_empty(): return _stage._foot("boss")
	return Vector2(state.foot)+local_point(int(state.pose),kind)*Vector2(state.get("scale",Vector2.ONE))
func mouth_point() -> Vector2: return world_point("mouth")
func eye_point() -> Vector2: return world_point("eye")
func tail_point() -> Vector2: return world_point("tail")
func foot_point() -> Vector2: return state.get("foot",_stage._foot("boss"))

func _draw() -> void:
	if state.is_empty(): return
	var texture: Texture2D=Assets.texture(asset_id,int(state.pose))
	if texture==null: return
	var sc: Vector2=state.get("scale",Vector2.ONE)
	draw_set_transform(Vector2(state.foot).round(),0,sc)
	var origin:=(-_foot*_pixel_scale).round()
	draw_texture_rect(texture,Rect2(origin,_canvas*_pixel_scale),false)
	draw_set_transform(Vector2.ZERO)
