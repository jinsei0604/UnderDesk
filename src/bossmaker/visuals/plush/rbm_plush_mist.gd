extends RefCounted
## Shared by the plush's stationary form and presentation-only renderer.
const Data=preload("res://src/bossmaker/visuals/plush/rbm_plush_v8_data.gd")
const ROOT="res://assets_bossmaker/battle/plush/v8/"
static func paths() -> Array[String]:
	var out: Array[String]=[]
	for i in int(Data.ART.pages):out.append(ROOT+"native-"+str(i)+".png")
	return out
static func paint(ci: CanvasItem,textures: Array,t: float,foot: Vector2,power: float=1.0,foreground: bool=false) -> void:
	var clip: Dictionary=Data.ART.animations["mist_front" if foreground else "mist"]
	var ref: Dictionary=clip.frames[posmod(int(t*8),clip.frames.size())]
	var frame: Dictionary=Data.ART.frames[int(ref.id)]
	var rect:=Rect2(frame.rect[0],frame.rect[1],frame.rect[2],frame.rect[3])
	var offset:=Vector2(frame.offset[0],frame.offset[1])
	ci.draw_texture_rect_region(textures[int(frame.page)],Rect2((foot+offset).round(),rect.size),rect,Color(1,1,1,power))
