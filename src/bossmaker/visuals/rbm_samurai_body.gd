extends RefCounted
const SHEET="res://assets_bossmaker/battle/samurai/actions/samurai_intermediates_v1.png"
const SCALE=104.777778/238.0
# Source regions and grounded pivots are measurements of the untouched authored PNG.
# Two long-blade cells use separate regions to exclude a neighbouring sprite's feet.
const CELLS=[Rect2(55,26,190,254),Rect2(315,57,228,223),Rect2(572,60,247,220),Rect2(870,54,242,226),
	Rect2(22,298,220,269),Rect2(312,293,201,274),Rect2(568,341,309,226),Rect2(887,331,225,236),
	Rect2(10,588,248,242),Rect2(296,593,215,237),Rect2(603,595,177,235),Rect2(880,593,231,237),
	Rect2(54,858,213,245),Rect2(331,838,207,242),Rect2(590,881,237,222),Rect2(903,849,192,254),
	Rect2(50,1108,176,268),Rect2(343,1108,162,268),Rect2(602,1108,170,268),Rect2(868,1108,216,268)]
const FEET=[Vector2(127,271),Vector2(407,271),Vector2(710,271),Vector2(1009,271),
	Vector2(132,558),Vector2(410,558),Vector2(680,558),Vector2(987,558),
	Vector2(151,819),Vector2(407,819),Vector2(678,819),Vector2(983,819),
	Vector2(139,1090),Vector2(424,1060),Vector2(689,1090),Vector2(978,1090),
	Vector2(138,1363),Vector2(416,1363),Vector2(673,1363),Vector2(968,1363)]
const TIPS=[Vector2(233,256),Vector2(533,252),Vector2(582,205),Vector2(879,205),
	Vector2(199,322),Vector2(503,400),Vector2(865,374),Vector2(1102,540),
	Vector2(20,647),Vector2(592,686),Vector2(893,688),Vector2(1095,801),
	Vector2(255,1052),Vector2(525,1005),Vector2(813,1070),Vector2(1082,1068),
	Vector2(160,1260),Vector2(430,1253),Vector2(688,1252),Vector2(1068,1121)]
const HANDS=[Vector2(105,186),Vector2(396,195),Vector2(684,185),Vector2(999,182),
	Vector2(69,368),Vector2(397,326),Vector2(732,421),Vector2(981,480),
	Vector2(123,687),Vector2(430,698),Vector2(720,698),Vector2(971,749),
	Vector2(116,993),Vector2(412,971),Vector2(680,1031),Vector2(956,1000),
	Vector2(102,1237),Vector2(404,1248),Vector2(680,1252),Vector2(967,1235)]

static func draw_frame(canvas: CanvasItem,texture: Texture2D,frame: int,foot: Vector2) -> void:
	var regions: Array=[CELLS[frame]]
	if frame==9:regions.append(Rect2(511,661,93,66))
	if frame==10:regions.append(Rect2(780,659,123,68))
	for region: Rect2 in regions:
		canvas.draw_texture_rect_region(texture,Rect2((foot+(region.position-FEET[frame])*SCALE).round(),region.size*SCALE),region)

static func tip(frame: int,foot: Vector2) -> Vector2:
	return foot+(TIPS[frame]-FEET[frame])*SCALE

static func hand(frame: int,foot: Vector2) -> Vector2:
	return foot+(HANDS[frame]-FEET[frame])*SCALE
