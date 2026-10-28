extends RefCounted
## Expression overlay for the existing s:18 frame only. Source sheet is untouched.
## Coordinates are in the original sheet, using the exact existing body calibration.
const Body=preload("res://src/bossmaker/visuals/rbm_samurai_body.gd")
static func patch(canvas: CanvasItem,rect: Rect2,c: Color) -> void:
	var cell: Rect2=Body.CELLS[18]
	var origin: Vector2=((cell.position-Body.FEET[18])*Body.SCALE).round()
	var pos: Vector2=origin+((rect.position-cell.position)*Body.SCALE).round()
	var size: Vector2=(rect.size*Body.SCALE).round().max(Vector2.ONE)
	canvas.draw_rect(Rect2(pos,size),c)
static func draw(canvas: CanvasItem) -> void:
	# Restore skin only inside the two open-eye columns, then a short lowered lid.
	patch(canvas,Rect2(684,1167,5,11),Color("f7b96c"))
	patch(canvas,Rect2(700,1168,4,10),Color("ffc578"))
	patch(canvas,Rect2(682,1173,8,3),Color("63432b"))
	patch(canvas,Rect2(698,1173,6,3),Color("63432b"))
