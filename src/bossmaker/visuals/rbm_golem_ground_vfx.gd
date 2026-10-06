extends Node2D
## Rendered at 320x180 and displayed at exact 4x nearest.
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
var center:=Vector2(352,460)
const ROCK_SCALE=1.4
var slam_center:=Vector2(816,500)
var ground_contacts: Array[Vector2]=[Vector2(770,495),Vector2(867,495)]
var age:=-1.0
var attribute:="NEUTRAL"
var routes: Array[PackedVector2Array]=[
	PackedVector2Array([Vector2(770,495),Vector2(793,510),Vector2(738,507),Vector2(713,491),Vector2(660,500),Vector2(636,483),Vector2(583,486),Vector2(550,465),Vector2(501,479),Vector2(460,456),Vector2(418,466),Vector2(386,450),center]),
	PackedVector2Array([Vector2(867,495),Vector2(848,520),Vector2(813,507),Vector2(793,510)]),
	PackedVector2Array([Vector2(637,483),Vector2(627,461),Vector2(588,454)]),
	PackedVector2Array([Vector2(501,479),Vector2(491,507),Vector2(460,518)]),
	PackedVector2Array([center,Vector2(314,474),Vector2(294,463),Vector2(275,490)]),
	PackedVector2Array([center,Vector2(391,480),Vector2(401,503),Vector2(430,525)]),
	PackedVector2Array([center,Vector2(331,415),Vector2(297,413),Vector2(275,370)]),
	PackedVector2Array([center,Vector2(395,433),Vector2(420,441),Vector2(430,405)])]

func polygon(points: Array,color: Color) -> void:
	var vertices:=PackedVector2Array()
	for p in points: vertices.append((Vector2(p)/4.0).floor())
	draw_colored_polygon(vertices,color)

func segment(a: Vector2,b: Vector2,width: float,color: Color) -> void:
	draw_line((a/4).floor(),(b/4).floor(),color,width,false)

func crack(path: PackedVector2Array,progress: float,alpha: float) -> void:
	var length:=0.0
	for i in range(path.size()-1): length+=path[i].distance_to(path[i+1])
	var remaining:=length*clampf(progress,0,1)
	for i in range(path.size()-1):
		var a:=path[i]
		var b:=path[i+1]
		var distance:=a.distance_to(b)
		var tip:=a.lerp(b,minf(1,remaining/maxf(distance,.01)))
		segment(a,tip,3,Color(.12,.105,.12,alpha))
		segment(a+Vector2(0,-4),tip+Vector2(0,-4),1,Color(.60,.56,.49,alpha*.65))
		segment(a,tip,1,Color(.045,.04,.05,alpha))
		remaining-=distance
		if remaining<=0: break

func _draw() -> void:
	if age<.72: return
	var fade:=1.0-smoothstep(3.4,4.1,age)
	var travel:=clampf((age-.82)/.68,0,1)
	crack(routes[0],travel,fade)
	crack(routes[1],clampf((age-.72)/.13,0,1),fade)
	crack(routes[2],clampf((travel-.40)*5,0,1),fade)
	crack(routes[3],clampf((travel-.69)*6,0,1),fade)
	for i in range(4,routes.size()): crack(routes[i],clampf((age-1.45)/.32,0,1),fade)
	if age>=1.52:
		rock(age-1.52)
		shock(age-1.52)
		debris(age-1.52)
	# The first ring marks the two-hand ground contact, before the travelling fissure.
	slam_shock(age-.72)
	var dust_age:=age-.72
	if dust_age<.35:
		for contact in ground_contacts:
			for i in range(8):
				var p: Vector2=contact+Vector2((i-4)*5,dust_age*12-absf(i-4)*2)
				draw_rect(Rect2((p/4).floor(),Vector2(2,1)),Color(.6,.57,.52,(1-dust_age/.35)*.35))

func rock(t: float) -> void:
	var rise:=smoothstep(0,.22,t)*(1.0-smoothstep(1.20,1.60,t))
	var alpha:=1.0-smoothstep(1.40,1.62,t)
	var facets: Array=[
		[[Vector2(-88,0),Vector2(-86,-60),Vector2(-61,-142),Vector2(-31,-216),Vector2(10,-207),Vector2(48,-164),Vector2(65,-92),Vector2(92,-41),Vector2(86,0)],Color("38343c")],
		[[Vector2(-78,0),Vector2(-76,-64),Vector2(-55,-141),Vector2(-28,-204),Vector2(4,-194),Vector2(-9,-126),Vector2(-27,-66),Vector2(-18,0)],Color("817b77")],
		[[Vector2(-28,-204),Vector2(4,-194),Vector2(40,-157),Vector2(21,-92),Vector2(-9,-126)],Color("a39a86")],
		[[Vector2(4,-194),Vector2(40,-157),Vector2(59,-86),Vector2(35,-57),Vector2(21,-92)],Color("68636a")],
		[[Vector2(-9,-126),Vector2(21,-92),Vector2(35,-57),Vector2(12,0),Vector2(-18,0),Vector2(-27,-66)],Color("59545b")],
		[[Vector2(59,-86),Vector2(84,-38),Vector2(78,0),Vector2(12,0),Vector2(35,-57)],Color("49444d")]]
	polygon([center+Vector2(-94,0)*ROCK_SCALE,center+Vector2(-54,-16)*ROCK_SCALE,center+Vector2(70,-12)*ROCK_SCALE,center+Vector2(103,8)*ROCK_SCALE,center+Vector2(48,20)*ROCK_SCALE,center+Vector2(-70,16)*ROCK_SCALE],Color(.045,.04,.045,.8*alpha))
	# Clip rising rock against the ground plane; never scale the entire rock.
	var clip:=PackedVector2Array([center+Vector2(-220,-360),center+Vector2(220,-360),center+Vector2(220,0),center+Vector2(-220,0)])
	for facet in facets:
		var world:=PackedVector2Array()
		for p in facet[0]: world.append(center+Vector2(p)*ROCK_SCALE+Vector2(0,216*ROCK_SCALE*(1-rise)))
		for part in Geometry2D.intersect_polygons(world,clip):
			var points: Array=[]
			for p in part: points.append(p)
			var c: Color=facet[1]
			c.a=alpha
			polygon(points,c)
	# Broad broken strata: a few deliberate stone edges, no noisy texture.
	for seam in [[Vector2(-55,-136),Vector2(-34,-128),Vector2(-19,-133)],
		[Vector2(-68,-73),Vector2(-39,-81),Vector2(-31,-69)],
		[Vector2(30,-93),Vector2(44,-100),Vector2(54,-84)],
		[Vector2(-9,-51),Vector2(12,-60),Vector2(29,-54)]]:
		for i in range(2):
			var a: Vector2=center+seam[i]*ROCK_SCALE+Vector2(0,216*ROCK_SCALE*(1-rise))
			var b: Vector2=center+seam[i+1]*ROCK_SCALE+Vector2(0,216*ROCK_SCALE*(1-rise))
			if a.y<center.y-3 and b.y<center.y-3:
				segment(a,b,1,Color(.20,.18,.21,alpha*.85))
				segment(a+Vector2(0,-4),b+Vector2(0,-4),1,Color(.62,.58,.51,alpha*.55))

func slam_shock(t: float) -> void:
	if t<0 or t>.30: return
	var q:=clampf(t/.24,0,1)
	var radius:=32+112*(1-pow(1-q,2))
	var alpha:=smoothstep(0,.025,t)*(1-smoothstep(.16,.30,t))
	pressure_ring(slam_center,radius,.44,13,alpha,156)

func shock(t: float) -> void:
	if t<.03 or t>.47: return
	var q:=clampf((t-.03)/.30,0,1)
	var radius:=52+268*(1-pow(1-q,2))
	var alpha:=smoothstep(.03,.07,t)*(1-smoothstep(.27,.47,t))
	pressure_ring(center,radius,.62,24,alpha,332)

func pressure_ring(center: Vector2,radius: float,ratio: float,thickness: float,alpha: float,bound: int) -> void:
	var base: Color=Palette.color_for(attribute)
	var vertical:=int(ceil(bound*ratio/4))*4
	for y in range(-vertical,vertical+1,4):
		for x in range(-bound,bound+1,4):
			var p:=Vector2(x,float(y)/ratio)
			var a:=p.angle()
			var edge:=radius+sin(a*9+.4)*5+sin(a*15)*3
			var width:=thickness+6*sin(a*3+.7)
			var d:=p.length()
			if sin(a*13)>.96 or d>edge or d<edge-width: continue
			var color:=base.lightened(.38) if d<edge-width+5 else base
			color.a=alpha
			draw_rect(Rect2(((center+Vector2(x,y))/4).floor(),Vector2.ONE),color)

func debris(t: float) -> void:
	if t>.8: return
	for i in range(12):
		var direction:=Vector2(sin(i*2.13)*135,-70-fmod(i*19,95))
		var p: Vector2=center+direction*t+Vector2(0,230*t*t)
		var side:=2 if i%4==0 else 1
		draw_rect(Rect2((p/4).floor(),Vector2(side,side)),Color(.53,.49,.46,1-smoothstep(.4,.7,t)))
	for i in range(15):
		var p:=center+Vector2((i-7)*12*(.7+t),8+sin(i*2.1)*9-t*15)
		draw_rect(Rect2((p/4).floor(),Vector2(3 if i%3 else 5,2)),Color(.68,.64,.57,smoothstep(0,.1,t)*(1-smoothstep(.22,.65,t))*.36))

func configure(boss_foot: Vector2,target_feet: Array[Vector2]) -> void:
	var sum:=Vector2.ZERO
	for foot in target_feet: sum+=foot
	center=(sum/maxi(target_feet.size(),1)+Vector2(0,12)).round()
	var boss_delta:=boss_foot-Vector2(840,500)
	var party_delta:=center-Vector2(352,460)
	ground_contacts=[Vector2(770,495)+boss_delta,Vector2(867,495)+boss_delta]
	slam_center=Vector2(816,500)+boss_delta
	for path in routes:
		for i in range(path.size()):
			var weight:=clampf((path[i].x-352)/488,0,1)
			path[i]+=party_delta.lerp(boss_delta,weight)
	routes.resize(4)
	for foot in target_feet:
		var middle:=center.lerp(foot,.5)
		routes.append(PackedVector2Array([center,middle+Vector2(-12,0),middle+Vector2(8,8),foot]))
