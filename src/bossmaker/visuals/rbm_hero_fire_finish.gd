extends Node2D
var age:=-1.0
var floor_point:=Vector2.ZERO
var flight:=-1.0
var launch_point:=Vector2.ZERO
var target_point:=Vector2.ZERO
var canvas_size:=Vector2(1280,720)
const INK=Color('#71192a')
const RED=Color('#cb3022')
const ORANGE=Color('#f96a20')
const GOLD=Color('#ffbc3d')
const HOT=Color('#fff0a0')
const WHITE=Color('#fffdf0')

# Authored silhouettes: each sheet has its own direction, not a repeated particle.
const PLUME=[-32,48,-52,-18,-14,-85,42,-142,48,-216,112,-274,84,-202,138,-221,97,-153,142,-168,113,-109,163,-120,118,-64,89,-25,40,38]
const PLUME_IN=[-15,34,-21,-23,28,-85,60,-109,69,-162,90,-193,80,-137,108,-145,83,-90,108,-98,61,-36,33,29]
const PLUME_HOT=[0,28,9,-34,44,-66,60,-109,57,-68,80,-86,44,-21,23,29]
const TEAR=[-20,48,-76,10,-116,-10,-194,-8,-170,-42,-248,-58,-302,-117,-224,-89,-251,-136,-176,-116,-206,-170,-148,-153,-103,-83,-54,-80,12,8]
const TEAR_IN=[-14,25,-78,-5,-125,-32,-182,-32,-164,-50,-227,-91,-179,-80,-178,-107,-128,-90,-91,-52,-55,-54,3,7]
const TEAR_HOT=[-7,14,-80,-21,-132,-43,-93,-38,-104,-61,-56,-28,12,14]
const FAN=[38,72,92,28,151,26,211,-16,315,-22,264,14,345,36,240,40,292,74,180,61,153,90,90,81]
const FAN_IN=[40,60,112,43,161,48,203,11,261,1,235,25,278,36,205,42,245,61,162,51,143,73,76,67]
const FAN_HOT=[37,49,121,49,164,29,195,28,169,44,207,51,145,56,99,60]
const SPLINTER=[-20,28,34,32,52,87,87,128,45,108,60,164,17,133,-24,142,-8,91,-41,74]
const SPLINTER_IN=[-12,34,20,39,30,78,56,114,23,91,38,123,5,105,-6,127,4,73,-23,61]
const CORE=[-44,-40,-8,-55,24,-30,57,-13,42,12,60,34,24,56,-3,40,-39,51,-46,19,-63,2]

func px(p: Vector2,s: Vector2,c: Color) -> void:
 draw_rect(Rect2(p.snapped(Vector2(4,4)),s.max(Vector2(4,4)).snapped(Vector2(4,4))),c)
func poly(points: Array,c: Color) -> void:
 var lo:=720.0
 var hi:=0.0
 for p in points:
  lo=minf(lo,p.y)
  hi=maxf(hi,p.y)
 for y in range(maxi(0,int(lo/4)*4),mini(int(canvas_size.y),int(hi)+4),4):
  var xs: Array[float]=[]
  for i in range(points.size()):
   var a: Vector2=points[i]
   var b: Vector2=points[(i+1)%points.size()]
   if (a.y<=y and b.y>y) or (b.y<=y and a.y>y):xs.append(a.x+(y-a.y)*(b.x-a.x)/(b.y-a.y))
  xs.sort()
  for i in range(0,xs.size()-1,2):px(Vector2(xs[i],y),Vector2(xs[i+1]-xs[i],4),c)
func stroke(a: Vector2,b: Vector2,w: float,c: Color) -> void:
 var n: Vector2=(b-a).normalized().orthogonal()*w*.5
 poly([a+n,b+n,b-n,a-n],c)
func sheet(coords: Array,origin: Vector2,extent: float,color: Color,bend: float=0) -> void:
 if age>=.62 and age<1.28:extent*=1.18
 var points: Array=[]
 for i in range(0,coords.size(),2):
  var p:=Vector2(coords[i],coords[i+1])
  p.x+=bend*pow(absf(p.y)/240,2)
  points.append(origin+p*extent)
 # Curve broad shoulders but preserve acute tearing tips. Rasterization stays 4 px.
 var contour: Array=[]
 for i in range(points.size()):
  var p: Vector2=points[i]
  var back: Vector2=points[(i-1+points.size())%points.size()]-p
  var ahead: Vector2=points[(i+1)%points.size()]-p
  if back.normalized().dot(ahead.normalized())>.45:
   contour.append(p)
  else:
   var a:=p+back.normalized()*minf(12*extent,back.length()*.22)
   var b:=p+ahead.normalized()*minf(12*extent,ahead.length()*.22)
   for k in range(4):
    var u:=float(k)/3
    contour.append(a*(1-u)*(1-u)+p*2*u*(1-u)+b*u*u)
 poly(contour,color)

func _draw() -> void:
 if age<0 and flight>=0:
  var p:=launch_point.lerp(target_point,flight)
  var direction:=(target_point-launch_point).normalized()
  var normal:=direction.orthogonal()
  # A forward-moving, upright flame blade, with its tail pointing back to the sword.
  var contour: Array=[]
  for v in [Vector2(-94,8),Vector2(-44,-12),Vector2(-37,-56),Vector2(-13,-95),Vector2(-19,-47),Vector2(15,-61),Vector2(5,-23),Vector2(38,0),Vector2(4,27),Vector2(-3,72),Vector2(-24,45),Vector2(-19,21),Vector2(-63,30)]:
   contour.append(p+direction*v.x+normal*v.y)
  poly(contour,RED)
  poly([p-direction*65,p-normal*57-direction*14,p-normal*20+direction*4,p+direction*30,p+normal*37-direction*9,p+normal*11-direction*23],GOLD)
  poly([p-direction*31,p-normal*28,p+direction*20,p+normal*23],WHITE)
  for i in range(8):
   var trail:=p-direction*(42+i*11)+normal*(sin(i*4.7)*18)
   px(trail,Vector2(8,4),ORANGE if i%2==0 else GOLD)
  return
 if age<0 or age>2.1:return
 var center:=floor_point+Vector2(0,-90)
 var focus:=clampf((age-.1)/.18,0,1)*clampf((1.5-age)/.55,0,1)
 px(Vector2.ZERO,canvas_size,Color(.055,.015,.025,.56*focus))
 if age<.11:
  # Frozen, angular contact. No fireball before the contraction.
  sheet([-52,-62,-3,-12,31,-32,15,2,60,66,1,21,-31,43,-14,4],center,1,HOT)
  stroke(center-Vector2(70,-18),center+Vector2(75,-18),3,WHITE)
 if age>=.11 and age<.48:
  var u:=(age-.11)/.37
  # Five separate flame filaments fold into a small, fixed destination.
  var sources: Array=[Vector2(-230,-65),Vector2(170,-180),Vector2(240,35),Vector2(-90,120),Vector2(25,-210)]
  for i in range(sources.size()):
   var offset: Vector2=sources[i]*(1-u*u)
   var p:=center+offset
   var tangent:=offset.normalized().orthogonal()*(18+10*sin(u*PI))
   poly([p+offset.normalized()*25,p+tangent,p*.6+center*.4,p-tangent*.3],RED)
   stroke(p,p.lerp(center,.25),4,GOLD)
  for i in range(27):
   var a:=i*2.399
   var start:=Vector2(cos(a)*(100+i%4*32),sin(a)*(80+i%3*30))
   var p:=center+start*(1-u*u*u)
   stroke(p,p-start.normalized()*8,2+(i%2)*2,HOT)
 if age>=.25 and age<.62:
  var strength:=clampf((age-.25)/.25,0,1)
  sheet(CORE,center,.16+strength*.25,ORANGE)
  sheet([-10,-22,5,-17,14,-3,8,16,-5,22,-16,5],center,1+strength*.1,WHITE)
  if age>.48:
   stroke(center-Vector2(90,0),center+Vector2(75,0),2,HOT)
   stroke(center-Vector2(0,38),center+Vector2(0,40),2,WHITE)
 if age>=.62 and age<1.28:
  var elapsed:=age-.62
  var burst:=1-pow(1-clampf(elapsed/.115,0,1),3)
  var fade:=clampf((1.28-age)/.30,0,1)
  var bend:=maxf(0,elapsed-.18)*120
  var tint:=Color(1,1,1,fade)
  # Four distinct silhouettes, separate onset speeds and separately drawn inner heat.
  sheet(TEAR,center,burst,RED*tint,-bend*.5)
  sheet(TEAR_IN,center,burst,ORANGE*tint,-bend*.5)
  sheet(TEAR_HOT,center,burst,HOT*tint,-bend*.5)
  var rise:=1-pow(1-clampf(elapsed/.16,0,1),3)
  sheet(PLUME,center,rise,RED*tint,bend)
  sheet(PLUME_IN,center,rise,GOLD*tint,bend)
  sheet(PLUME_HOT,center,rise,HOT*tint,bend)
  var spread:=1-pow(1-clampf(elapsed/.20,0,1),3)
  sheet(FAN,center,spread,ORANGE*tint)
  sheet(FAN_IN,center,spread,GOLD*tint)
  sheet(FAN_HOT,center,spread,HOT*tint)
  sheet(SPLINTER,center,burst,RED*tint,-bend)
  sheet(SPLINTER_IN,center,burst,ORANGE*tint,-bend)
  # Individual detached licking tips, pulled out of the major sheets.
  var tear_off:=clampf((elapsed-.15)/.38,0,1)
  if tear_off>0:
   sheet([-22,11,-12,-4,-27,-23,-5,-14,16,-30,5,-3,24,-7,10,12],center+Vector2(-260,-122)+Vector2(-78,-32)*tear_off,.7*tear_off,GOLD*tint,-12)
   sheet([-9,26,-5,0,17,-27,7,-4,21,-12,12,17],center+Vector2(128,-208)+Vector2(40,-78)*tear_off,tear_off,HOT*tint,8)
   sheet([-29,0,-8,-8,7,-27,8,-4,31,-10,9,10],center+Vector2(268,44)+Vector2(70,22)*tear_off,.8*tear_off,ORANGE*tint)
  sheet(CORE,center,burst,HOT*tint)
  # A white-hot split, aligned with the dominant up-right release.
  sheet([-29,34,-8,-30,51,-91,25,-30,48,-37,6,21,23,30,-3,48],center,burst,WHITE*tint)
  # Broken ground shock fronts: no expanding circle.
  var travel:=clampf(elapsed/.30,0,1)
  var edge:=floor_point+Vector2(-30,4)
  sheet([-10,0,-180,-12,-292,-4,-210,8,-336,24,-172,11,-98,20],edge,travel,GOLD*tint)
  sheet([15,0,185,-8,267,-25,225,0,370,18,239,10,207,28,112,10],edge,travel,HOT*tint)
 if age>=.74 and age<.775:
  px(Vector2.ZERO,canvas_size,Color(1,.99,.90,.88))
 if age>.76:
  var flight:=age-.76
  var fade:=clampf((2.1-age)/.55,0,1)
  for i in range(55):
   # Unequal speeds, sizes and launch times; fragments break from different sheets.
   var dt:=maxf(0,flight-float(i%5)*.025)
   var a:=float(i)*2.399
   var v:=Vector2(cos(a)*(145+i%7*43),sin(a)*(110+i%5*31)-80)
   var p:=center+v*dt+Vector2(0,150*dt*dt)
   if p.y>floor_point.y+28:continue
   var c: Color=[RED,ORANGE,GOLD,HOT][i%4]*Color(1,1,1,fade)
   var size:=Vector2(2+i%4*2,2+i%3*3)
   if i%4==0:
    var d:=v.normalized()
    poly([p-d*9,p+d.orthogonal()*4,p+d*5,p-d.orthogonal()*3],c)
   else:px(p,size,c)
 if age>1.25:
  var fade:=clampf((2.1-age)/.65,0,1)
  var tint:=Color(1,1,1,fade)
  # Three different residual tears, not a row of cloned flames.
  sheet([-20,0,-12,-10,-18,-30,0,-13,6,-43,13,-17,20,0],floor_point+Vector2(-58,0),.8,ORANGE*tint)
  sheet([-13,0,-19,-17,-2,-11,10,-31,6,-9,23,-14,16,0],floor_point+Vector2(55,4),1,GOLD*tint)
  sheet([-23,0,-4,-7,3,-26,8,-6,29,0],floor_point+Vector2(8,3),.7,RED*tint)
