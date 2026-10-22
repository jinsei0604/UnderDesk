extends RefCounted
const SHEET="res://assets_bossmaker/battle/tank/actions/tank_intermediates_v1.png"
# Regions/pivots measured from the untouched transparent authoring sheet.
const CELLS=[Rect2(78,20,155,212),Rect2(443,30,165,202),Rect2(796,31,194,201),Rect2(1165,31,202,201),
	Rect2(73,245,176,213),Rect2(425,264,197,194),Rect2(773,267,306,191),Rect2(1173,267,202,191),
	Rect2(86,491,154,226),Rect2(434,464,177,253),Rect2(801,473,164,244),Rect2(1135,554,247,163),
	Rect2(61,769,244,156),Rect2(464,750,214,170),Rect2(796,734,197,186),Rect2(1181,734,193,186),
	Rect2(79,931,166,175),Rect2(450,950,197,156),Rect2(820,929,202,179),Rect2(1180,927,154,181)]
const FEET=[Vector2(172,223),Vector2(530,223),Vector2(872,223),Vector2(1251,223),
	Vector2(159,449),Vector2(535,449),Vector2(868,449),Vector2(1256,449),
	Vector2(166,708),Vector2(529,708),Vector2(882,708),Vector2(1230,708),
	Vector2(146,913),Vector2(546,911),Vector2(880,911),Vector2(1262,911),
	Vector2(161,1098),Vector2(530,1098),Vector2(914,1098),Vector2(1258,1098)]
# Per-cell constant calibration accounts for the sheet's row sizing, never animated stretching.
const SCALES=[0.56,0.59,0.59,0.59,0.59,0.59,0.59,0.59,0.59,0.59,0.59,0.59,0.64,0.64,0.64,0.64,0.68,0.68,0.67,0.67]
const HEADS=[Vector2(105,211),Vector2(463,153),Vector2(965,153),Vector2(1347,157),
	Vector2(102,275),Vector2(451,368),Vector2(1055,339),Vector2(1349,420),
	Vector2(107,519),Vector2(460,495),Vector2(839,507),Vector2(1357,683),
	Vector2(279,893),Vector2(652,850),Vector2(971,830),Vector2(1349,839),
	Vector2(108,969),Vector2(624,1021),Vector2(849,1085),Vector2(1257,1084)]
static func draw_frame(c: CanvasItem,texture: Texture2D,frame: int,foot: Vector2) -> void:
	var rect: Rect2=CELLS[frame]
	c.draw_texture_rect_region(texture,Rect2((foot+(rect.position-FEET[frame])*SCALES[frame]).round(),rect.size*SCALES[frame]),rect)
static func head(frame: int,foot: Vector2) -> Vector2:
	return foot+(HEADS[frame]-FEET[frame])*SCALES[frame]
