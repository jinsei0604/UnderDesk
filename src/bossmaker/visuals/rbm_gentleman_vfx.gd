extends Node2D
## 異形紳士の戦闘演出の絵（表示専用。戦闘の状態・乱数は使わない）: 本体と影の要所の絵・銃火・弾・命中・霧・裂け目・足元のひび。
## 2026-11-20 作り直し（ユーザー「動きを繋げるようにしてて違和感がすごい。要所の絵を切り替える方式に」「銃弾の角度がおかしい」
## 「演出も改善したいから、その絵にあった角度にしていい」）:
##  - 本体・影は要所の絵（Motion.frame・_clone_pose）を切り替えるだけ。中割り・変形はしない。
##  - 弾は絵の銃口から銃身の向きに飛ぶ（Motion.GUNS）。単体は本体が霧になって相手と同じ高さへ移ってから撃ち、
##    全体は影が各相手の横に同じ高さで並んで撃つ。覚醒後は銃身の先の裂け目に撃ち込み、相手のそばの裂け目から当てる。
##    全体の締めは本体が四人へ撃つ一発（合図）と、影の一斉射撃。
##  - 命中は弾の向きに飛び散る墨と火の粉と煙。白い星形・平たい輪の衝撃の絵と、杭（尖った黒い三角）は使わない。
const Motion=preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
## 衝撃の絵（rbm_gentleman_impact_sheets.gd が読む 8x7 コマの絵）。2026-11-20 から使わない（命中は hit() で描く）。
const IMPACT_STYLES := {}
## 構えた姿（片手撃ち）の銃口の高さと、足元から銃口までの横の長さ（絵の画素＝この層の1画素）
const GUN_H := 64.5
const GUN_X := 49.0
## 撃つ者の足元の下の限り（パーティの札に足が隠れない所。札の上端は画面の約567px＝この層の約333）
const FOOT_MAX := 330.0
## 影と相手の間（銃口から相手の体まで）・影が縦に並ぶ間隔
const CLONE_GAP := 30.0
const CLONE_STEP := 15.0
## 同じ列の上の段の相手を撃つ影を外へずらす量（影の体の幅より広く。2026-11-20 ユーザー「全体攻撃で影が重なると変」）
const UPPER_OUT := 38.0
## 弾の傾きの限り（tan 3度）
const SLOPE := 0.0524
## 同じ相手を撃つ2人目・3人目の影の濃さ（奥の闇に溶けて見えるように）
const RANK_ALPHA := [1.0, .72, .55]
## 単体: 霧になって消える・相手の高さに現れる・戻る（音の無い区間。テンポで詰める 1.5〜1.9・4.5〜5.5 より前に終える）
const STEP_OUT := [0.95, 1.18]
const STEP_IN := [1.22, 1.45]
const BACK_OUT := [3.98, 4.18]
const BACK_IN := [4.22, 4.42]
const INK := Color(.045,.035,.075)
const SMOKE := Color(.11,.10,.15)
const CRIMSON := Color("c22a44")
const SHADOW_TINT := Color(.25,.29,.38)
var kind := "single"
var age := 0.0
var boss := Vector2.ZERO
var target := Vector2.ZERO
var feet: Array[Vector2]=[]
var points: Array[Vector2]=[]
var heights: Array[float]=[]
var party_feet: Array[Vector2]=[]
var party_heights: Array[float]=[]
var canvas_size := Vector2(752,424)
var attribute := "NEUTRAL"
var awakened := false
var data: Dictionary
## The stage's rbm_gentleman_impact_sheets.gd（2026-11-20 から何も読まない。IMPACT_STYLES が空）
var impact_sheets: Node
var _impact_textures: Dictionary={}
var _soft: GradientTexture2D
## 2026-11-20 作り直した大技（覚醒・覚醒後の全体）: エフェクトは rbm_gentleman_fx_*.gd（RBMHeroFxBase）が描き、ここは本体だけ。
## 絵の名前（pose_override）と本体に重ねる単色の光（閃光・縁の光）はつなぎから受け取る。
var v2 := false
var pose_override := ""
var body_flash := 0.0
var body_flash_col := Color.WHITE
var body_lit := 0.0
var body_lit_col := Color.WHITE
## 2026-11-23 強めたエフェクト（ユーザー「全体的にエフェクトが弱くてクオリティが低い」）: 単体・全体・覚醒後の単体・支援は、
## エフェクトを rbm_gentleman_fx_*.gd（RBMHeroFxBase。覚醒後の全体と同じ部品）が描く。ここは本体・影・霧（動き）だけを描き、
## 銃火・弾・命中・裂け目・足元のひび・支援の光は描かない。弾の出来事（shot_events）は fx が読む。
var fx_layer := false
var _flat: Node2D

static func impact_path(attribute: String, style: String) -> String:
	var attr:=attribute.to_lower()
	if not Palette.COLORS.has(attribute):attr="neutral"
	return Motion.ROOT+"impacts/"+attr+"_"+style+".png"

func _ready() -> void:
	_soft=GradientTexture2D.new()
	_soft.width=32;_soft.height=32
	_soft.fill=GradientTexture2D.FILL_RADIAL
	_soft.fill_from=Vector2(.5,.5);_soft.fill_to=Vector2(1,.5)
	var gradient:=Gradient.new()
	gradient.offsets=PackedFloat32Array([0,.35,.65,1])
	gradient.colors=PackedColorArray([Color(1,1,1,.95),Color(1,1,1,.6),Color(1,1,1,.25),Color(1,1,1,0)])
	_soft.gradient=gradient
	_flat=Node2D.new()
	var fm:=ShaderMaterial.new()
	fm.shader=load("res://src/bossmaker/visuals/encounter/rbm_encounter_sprite.gdshader")
	fm.set_shader_parameter("mode",1)
	_flat.material=fm
	_flat.draw.connect(_draw_flat)
	add_child(_flat)

# ---- 基本の道具 ----
func q(seed: int, channel: int=0) -> float:
	return fposmod(sin(seed*127.1+channel*311.7+91.3)*43758.5453,1.0)
func c(color: Color, alpha: float) -> Color:
	return Color(color,clampf(alpha,0,1))
func envelope(a: float,b: float,d: float,e: float,t: float) -> float:
	return smoothstep(a,b,t)*(1-smoothstep(d,e,t))
func ray(a: Vector2,b: Vector2,color: Color,width: float=1) -> void:
	draw_line(a.round(),b.round(),color,width,false)
func glow(p: Vector2, r: float, color: Color) -> void:
	if r<=.5 or color.a<=.004 or not is_instance_valid(_soft):return
	draw_texture_rect(_soft,Rect2((p-Vector2.ONE*r).round(),Vector2.ONE*round(r*2)),false,color)
func sprite(name: String, p: Vector2, flip: bool=false, tint: Color=Color.WHITE) -> void:
	if tint.a<=.004:return
	draw_set_transform(p.round(),0,Vector2(-1 if flip else 1,1))
	draw_texture(Motion.texture(name),Vector2(-72,-112),tint)
	draw_set_transform(Vector2.ZERO)
func mist(p: Vector2,t: float,power: float,width: float=55,rise: float=38,seed: int=0,ink: Color=Color(.09,.08,.14)) -> void:
	if power<=0:return
	for i in 20:
		var f:=fposmod(t*.36+q(seed+i),1.0)
		var pos:=p+Vector2((q(seed+i,1)-.5)*width+sin(t+i)*5,-f*rise)
		var radius: float=4+q(seed+i,2)*12+f*7
		glow(pos,radius,c(ink,sin(f*PI)*power*.6))
func fill_polygon(vertices: PackedVector2Array,color: Color) -> void:
	var clean:=PackedVector2Array()
	for p in vertices:
		var rounded:=p.round()
		if clean.is_empty() or clean[-1]!=rounded:clean.append(rounded)
	if clean.size()>1 and clean[0]==clean[-1]:clean.remove_at(clean.size()-1)
	if clean.size()<3:return
	if Geometry2D.triangulate_polygon(clean).size()<3:return
	draw_colored_polygon(clean,color)

# ---- 相手と位置 ----
func point(index: int) -> Vector2:
	return points[posmod(index,points.size())] if not points.is_empty() else target-Vector2(0,32)
func foot(index: int) -> Vector2:
	return feet[posmod(index,feet.size())] if not feet.is_empty() else target
func height(index: int) -> float:
	return heights[posmod(index,heights.size())] if not heights.is_empty() else 55.0
func center() -> Vector2:
	var p:=Vector2.ZERO
	for v in party_feet:p+=v
	return p/maxi(1,party_feet.size())

## 弾の通る高さ: 相手の胸（足元から体の高さの 0.6）。撃つ所から相手までの間に他の味方の体があれば、それを避ける高さを選ぶ。
func line_y(index: int, from_x: float) -> float:
	var f:=foot(index);var h:=height(index)
	for r in [.6,.66,.54,.72,.48,.78,.84]:
		var y: float=f.y-h*r
		var clear:=true
		for j in party_feet.size():
			var pf: Vector2=party_feet[j]
			if pf.distance_to(f)<1.0 or (pf.x-from_x)*(pf.x-f.x)>=0.0:continue
			var ph: float=party_heights[j] if j<party_heights.size() else 55.0
			if y>pf.y-ph-2.0 and y<pf.y+2.0:clear=false;break
		if clear:return y
	return f.y-h*.6

## 当たる所: 狙う高さ（相手の胸）を、銃口から水平に対して SLOPE（約3度）以内に収める。撃つ者の足が札に隠れない
## 下の限りで銃口が胸まで下がらない時（下の段の相手）も、弾が銃の絵の向きとほぼ同じに見えるように。
func aim(mouth: Vector2, want: Vector2) -> Vector2:
	var reach:=absf(want.x-mouth.x)*SLOPE
	return Vector2(want.x,clampf(want.y,mouth.y-reach,mouth.y+reach))

## 撃つ者の足元: 構えた銃口がその高さに来る所（パーティの札に足が隠れない所まで）。
func shooter_foot(x: float, y_line: float) -> Vector2:
	return Vector2(clampf(x,20,canvas_size.x-20),minf(y_line+GUN_H,FOOT_MAX))

## 単体: 本体が霧になって移る、相手と同じ高さの所（少し前へ出る）
func duel_foot() -> Vector2:
	var x:=boss.x-26.0
	return shooter_foot(x,line_y(0,x-GUN_X))
func host_foot() -> Vector2:
	if kind=="single" and age>=STEP_IN[0] and age<BACK_IN[0]:return duel_foot()
	return boss
func host_alpha() -> float:
	if kind!="single":return 1.0
	return clampf(1.0-envelope(STEP_OUT[0],STEP_OUT[1],STEP_IN[0],STEP_IN[1],age)-envelope(BACK_OUT[0],BACK_OUT[1],BACK_IN[0],BACK_IN[1],age),0,1)

## 影 i の立つ所・向き・相手（相手の横に、相手と同じ高さで、相手に近い順に並ぶ。左の列の相手には左から、右の列には右から）
func clone_spot(i: int) -> Dictionary:
	var n:=maxi(1,feet.size())
	var t:=posmod(i,n);var rank:=floori(float(i)/float(n))
	var f:=foot(t);var mid:=center().x
	var left:=f.x<mid-1.0 or (absf(f.x-mid)<=1.0 and t%2==0)
	var s:=-1.0 if left else 1.0
	# 同じ列の上の段の相手を撃つ影は少し外へ（下の段の影と重なって塔のように見えないように）
	var upper:=false
	for j in feet.size():
		var g:=foot(j)
		if j!=t and absf(g.x-f.x)<8.0 and g.y>f.y:upper=true
	# 同じ相手を撃つ2人目・3人目は少し外へずらし、高さも変える（体の上の方・下の方に当たる）
	var x:=f.x+s*(GUN_X+CLONE_GAP+(UPPER_OUT if upper else 0.0)+rank*CLONE_STEP)
	var y_line: float=line_y(t,x-s*GUN_X)+float([0.0,-9.0,8.0][rank%3])
	var cf:=shooter_foot(x,y_line)
	return {"foot":cf,"flip":left,"target":t,"rank":rank,"dest":aim(cf+Vector2(-s*GUN_X,-GUN_H),Vector2(f.x-s*4.0,y_line))}
func clone_count() -> int:
	return (data.shadow_positions as Array).size() if data.has("shadow_positions") else 0
## 影の撃つ時刻（全体は最後に一斉射撃も）
func clone_shots(i: int) -> Array:
	var out: Array=[]
	for e in data.get("shadows",[]):
		if int(e.shooter)==i:out.append({"time":float(e.time),"hit":float(e.hit)})
	if kind=="all":out.append({"time":volley_time(),"hit":float(data.impact),"volley":true})
	return out
func volley_time() -> float:
	return float(data.host[0].time)+.02 if kind=="all" and not (data.host as Array).is_empty() else -10.0
## 影の要所の絵: 立つ → 銃を抜く → 構える（撃つたびに一瞬反動）→（全体）構えを解いて合図を待つ → 一斉に構える
func clone_pose(i: int) -> String:
	var shots:=clone_shots(i)
	if shots.is_empty():return "hat_reach_00"
	var first: float=shots[0].time
	var last_round: float=first
	for s in shots:
		if not s.get("volley",false):last_round=maxf(last_round,float(s.time))
		if age>=float(s.time) and age<float(s.time)+.07:return Motion.RECOIL_POSE
	if age<first-.42:return "hat_reach_00"
	if age<first-.22:return "normal_draw_fire_05"
	if kind=="all":
		var v:=volley_time()
		if age>last_round+.35 and age<v-.30:return "normal_draw_fire_05"
	return Motion.AIM_POSE
func clone_alpha(i: int) -> float:
	if not data.has("shadow_frames"):return 0.0
	var row: Array=data.shadow_frames[Motion.frame_index(data,age)]
	return float(row[i].alpha) if i<row.size() else 0.0

# ---- 銃火・弾・命中 ----
## 銃口の炎（銃身の向きに伸びる短い光。尖った三角ではなく線と柔らかい光を重ねる）と、流れる硝煙
func flash(p: Vector2, d: Vector2, t: float, big: float=1.0) -> void:
	if t<0 or t>=.7:return
	if t<.09:
		var a:=1-t/.09
		glow(p+d*2,(4+2*big)*(.55+.45*a),c(Color(1,.88,.55),a*.9))
		ray(p,p+d*(8+3*big)*(.6+.4*a),c(Color(1,.70,.30),a),3)
		ray(p,p+d*(12+4*big),c(Color(1,.98,.88),a),1)
	for k in 3:
		var lt:=t-.02*k
		if lt<0:continue
		var pos:=p+d*(4+18*lt+k*3)+Vector2(0,-9*lt-k*2)
		glow(pos,2+7*lt+k,c(Color(.42,.40,.46),.30*(1-smoothstep(.1,.7,lt))))
## 弾の光の筋（頭が速く進み、尾が追う）
func tracer(a: Vector2, b: Vector2, t: float, duration: float, color: Color) -> void:
	if t<0 or t>duration+.04:return
	var p:=clampf(t/duration,0,1)
	var fade:=1.0-clampf((t-duration)/.04,0,1)
	ray(a.lerp(b,maxf(0,p-.32)),a.lerp(b,p),c(color,.75*fade),2)
	ray(a.lerp(b,maxf(0,p-.14)),a.lerp(b,p),c(Color(1,.98,.92),fade),1)
## 命中: 一瞬の白い芯、弾の向きへ飛び散る墨と属性の色の火の粉、流れる煙。強い一撃は赤い火の粉が上り、体に墨が残る。
func hit(p: Vector2, d: Vector2, t: float, color: Color, power: float, seed: int=0) -> void:
	if t<0 or t>1.5:return
	var dir:=d.normalized() if d.length()>.01 else Vector2.LEFT
	# 当たった瞬間: 白い芯と、弾の向きに体を突き抜ける光
	if t<.1:
		var a:=1-t/.1
		glow(p,(5+4*power)*(.7+.3*a),c(Color(1,.95,.85),a))
		glow(p,(9+7*power)*(.7+.3*a),c(color,.45*a))
		ray(p-dir*(4+2*power),p+dir*(9+7*power)*(.5+.5*a),c(Color(1,1,.96),a),2)
	# 弾の向きへ噴き出す墨（柔らかい塊が広がって薄れる）
	for k in int(4+3*power):
		var ang:=(q(seed+120+k)-.5)*1.1
		var v:=dir.rotated(ang)*(30+50*q(seed+130+k))*(.7+.3*power)
		var pos:=p+dir*6+v*minf(t,.35)*(1-.6*smoothstep(0,.35,t))+Vector2(0,24*t*t)
		glow(pos,(2+2.5*q(seed+140+k))*(1+1.2*smoothstep(0,.4,t)),c(INK,.75*(1-smoothstep(.12,.6,t))))
	var n:=int(10+8*power)
	for i in n:
		var ang:=(q(seed+i)-.5)*1.3
		var v:=dir.rotated(ang)*(45+95*q(seed+i,1))*(.6+.4*power)+Vector2(0,-25*q(seed+i,2))
		var life:=.22+.28*q(seed+i,3)
		if t>life:continue
		var pos:=p+v*t+Vector2(0,110*t*t)
		var f:=1-t/life
		var spark:=i%3==0
		ray(pos-v*(.05 if spark else .03),pos,c(color.lerp(Color(1,.95,.85),.35) if spark else INK,f*(.95 if spark else .8)),1 if spark else 2)
	for k in int(3+power):
		var lt:=t-.03*k
		if lt<0:continue
		var pos:=p+dir*(6+16*lt)*(.5+.5*q(seed+40+k))+Vector2((q(seed+50+k)-.5)*8,-10*lt-3*k)
		glow(pos,(3+7*lt)*(.8+.3*power),c(SMOKE,(.55-.08*k)*(1-smoothstep(.25,1.2,lt))))
	if power>=1.5:
		var ember:=1-smoothstep(.2,1.1,t)
		for i in 10:
			var pos:=p+Vector2((q(seed+70+i)-.5)*22,-t*(30+40*q(seed+80+i)))+dir*t*14
			draw_rect(Rect2(pos.round(),Vector2.ONE*(1+int(q(seed+90+i)*2))),c(CRIMSON.lightened(.25),ember*(.5+.5*sin(t*20+i))))
		glow(p+dir*3,6+10*smoothstep(0,.2,t),c(INK,.6*(1-smoothstep(.3,1.3,t))))
## 空間の裂け目（覚醒後）: 暗い縦長の裂け目、縁に赤い光、まわりに薄い霧
func rift(p: Vector2,t: float,opening: float,seed: int=0) -> void:
	if opening<.04:return
	var h:=22*opening;var w:=6*opening
	var polygon:=PackedVector2Array()
	for k in 16:
		var a:=k*TAU/16
		var j:=1.0+(q(seed+k+int(t*12))-.5)*.25
		polygon.append(p+Vector2(sin(a)*w*j,-cos(a)*h))
	fill_polygon(polygon,Color(.012,.006,.03,.96))
	for k in 16:
		ray(polygon[k],polygon[(k+1)%16],c(CRIMSON,opening*(.55+.35*sin(t*14+k))),1)
	glow(p,w+6,c(CRIMSON.darkened(.4),opening*.35))
	mist(p+Vector2(0,10),t,opening*.8,26,34,seed+93)
## 足元のひび（全体の締め）: 石畳が割れ、割れ目の奥が赤く光り、煙と石のかけらが上がる
func ground_crack(p: Vector2,t: float,power: float,seed: int) -> void:
	if t<0 or t>=2.4:return
	var grow:=smoothstep(0,.12,t);var fade:=1-smoothstep(1.2,2.4,t)
	for i in 7:
		var a:=q(seed+i)*TAU
		var dir:=Vector2(cos(a),sin(a)*.32)
		var path:=PackedVector2Array([p])
		var length: float=(12+22*q(seed+i,1))*power*grow
		for k in range(1,5):
			path.append((p+dir*length*k/4.0+Vector2((q(seed+i*7+k,2)-.5)*3,(q(seed+i*7+k,3)-.5)*1.5)).round())
		draw_polyline(path,c(INK,fade*.9),2)
		draw_polyline(path,c(CRIMSON,fade*.8*(1-smoothstep(.35,1.6,t))),1)
	glow(p+Vector2(0,-2),(7+5*power)*grow,c(CRIMSON,.35*(1-smoothstep(.2,1.4,t))))
	mist(p+Vector2(0,-4),t,1.4*fade*power,40*power,34,seed)
	for i in 8:
		var v:=Vector2((q(seed+30+i)-.5)*70,-(35+60*q(seed+40+i)))*power
		var pos:=p+v*t+Vector2(0,150*t*t)
		if t>.03 and pos.y<p.y+2:draw_rect(Rect2(pos.round(),Vector2(2,2) if i%2 else Vector2(3,2)),c(Color(.33,.31,.37),fade))

# ---- 技ごとの絵 ----
func awakening_effects() -> void:
	var dim:=envelope(2.8,4.8,9.3,11.5,age)
	draw_rect(Rect2(Vector2.ZERO,canvas_size),Color(0,0,.012,dim*.48))
	var h:=host_foot()
	# 帽子を取って正体が現れる間: 足元から黒い煙が立ち上り、赤い火の粉が舞い上がる（尖った黒い三角は使わない）
	var reveal:=envelope(5.4,6.6,7.9,8.4,age)
	if reveal>0:
		mist(h,age,reveal*3,80,130,212,INK)
		for i in 18:
			var f:=fposmod(age*.5+q(i+500),1.0)
			var pos:=h+Vector2((q(i+510)-.5)*70+sin(age*2+i)*4,-f*120)
			draw_rect(Rect2(pos.round(),Vector2.ONE*(1+int(q(i+520)*2))),c(CRIMSON.lightened(.2),reveal*sin(f*PI)))
	var dt:=age-8.08
	if dt>=0 and dt<2.8:
		var grow:=smoothstep(0,.4,dt);var fade:=1-smoothstep(.4,2.4,dt)
		var core:=h-Vector2(0,48)
		# 覚醒の瞬間: 黒い煙が体から外へ吹き出し、赤い筋が外へ走る
		for i in 40:
			var dir:=Vector2.from_angle(q(i+270)*TAU)
			var pos:=core+dir*Vector2(1,.62)*(18+125*q(i,1))*(.25+.75*grow)
			glow(pos,(5+11*q(i,2))*(.5+.5*grow),c(INK,fade*.7))
		for i in 20:
			var dir:=Vector2.from_angle(q(i+330)*TAU)*Vector2(1,.62)
			var a:=core+dir*(26+100*grow*(.5+.5*q(i,1)))
			ray(a,a+dir*(6+6*q(i,2)),c(CRIMSON.lightened(.15),fade),1)
		mist(h-Vector2(60,0),dt+1,3*fade,320,120,212)
		if dt<.10:draw_rect(Rect2(Vector2.ZERO,canvas_size),Color(.87,.76,.83,(1-dt/.10)*.5))

func support_effects() -> void:
	var color:=Color("71da87") if kind=="heal" else Color("ef4847")
	var h:=host_foot()
	# 手袋を直す（0.5〜1.9）: 手元に光の粒が集まる
	var glove:=envelope(.55,.9,1.7,1.95,age)
	if glove>0:
		var hand:=h+Vector2(-2,-57)
		glow(hand,3+1.5*sin(age*9),c(color.lightened(.35),glove*.85))
		for i in 10:
			var f:=fposmod(age*.9+q(i+600),1.0)
			var from:=hand+Vector2.from_angle(q(i+610)*TAU)*Vector2(26,18)
			var pos:=from.lerp(hand,f)
			draw_rect(Rect2(pos.round(),Vector2(1,1)),c(color.lightened(.3),glove*sin(f*PI)))
	# クラバットを直す（1.9〜3.05）: 襟元に小さな光
	var cravat:=envelope(1.95,2.3,2.85,3.1,age)
	if cravat>0:
		var neck:=h+Vector2(-3,-70)
		glow(neck,2.5+1.5*sin(age*11),c(color.lightened(.4),cravat))
		ray(neck-Vector2(4,0),neck+Vector2(4,0),c(Color(1,1,1),cravat*.7),1)
	# 力が体を巡る（3.05〜）: 色のついた煙が足元から立ち上り、光の粒が上る
	var strength:=envelope(2.85,3.3,4.0,4.8,age)
	mist(h,age,strength*2.2,60,90,50,color.darkened(.6))
	for i in 28:
		var p:=fposmod(age*.6+q(i),1)
		draw_rect(Rect2((h+Vector2((q(i,1)-.5)*55,-p*110)).round(),Vector2(2,3)),c(color,sin(p*PI)*strength))
	if age>=3.05 and age<3.35:
		glow(h-Vector2(0,48),26*smoothstep(3.05,3.2,age),c(color,.35*(1-smoothstep(3.1,3.35,age))))

## 本体に重ねる単色（閃光が強い方を優先。縁の光は薄く）
func _draw_flat() -> void:
	var a:=maxf(body_flash,body_lit*.35)
	var pose:=pose_override if v2 else (Motion.frame(kind,age) if fx_layer else "")
	if not (v2 or fx_layer) or a<=.003 or pose.is_empty():return
	a*=host_alpha()
	(_flat.material as ShaderMaterial).set_shader_parameter("flat_color",body_flash_col if body_flash>=body_lit*.35 else body_lit_col)
	_flat.draw_set_transform(host_foot().round())
	_flat.draw_texture(Motion.texture(pose),Vector2(-72,-112),Color(1,1,1,a))
	_flat.draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if data.is_empty():return
	if v2:
		sprite(pose_override if not pose_override.is_empty() else "hat_reach_00",host_foot())
		if is_instance_valid(_flat):_flat.queue_redraw()
		return
	var accent:=Palette.color_for(attribute)
	if kind=="awakening":awakening_effects()
	var impact_t:=age-float(data.impact)
	# 全体の締め: 相手の足元のひび（影と本体より奥に描く）
	if kind in ["all","awakened_all"] and not fx_layer:
		for j in feet.size():ground_crack(foot(j),impact_t,1.15 if awakened else 1.0,j*37+5)
	# 影: 相手の横に並び、要所の絵で撃つ（奥から順に）
	var order: Array=[]
	for i in clone_count():order.append(i)
	order.sort_custom(func(a,b):return clone_spot(a).foot.y<clone_spot(b).foot.y)
	for i in order:
		var alpha:=clone_alpha(i)
		if alpha<=0:continue
		var spot:=clone_spot(i)
		mist(spot.foot,age,alpha*.6,42,28,130+i*7)
		sprite(clone_pose(i),spot.foot,spot.flip,Color(SHADOW_TINT,alpha*float(RANK_ALPHA[int(spot.rank)%3])))
	# 本体（単体は霧になって相手の高さへ移り、撃った後に戻る）
	var host:=host_foot()
	if kind=="single":
		mist(boss,age,2.4*envelope(STEP_OUT[0]-.05,STEP_OUT[1],STEP_IN[0],STEP_IN[1]+.15,age),46,60,61,INK)
		mist(duel_foot(),age,2.4*envelope(STEP_OUT[1],STEP_IN[0]+.05,STEP_IN[1],STEP_IN[1]+.35,age),46,60,67,INK)
		mist(duel_foot(),age,2.4*envelope(BACK_OUT[0]-.05,BACK_OUT[1],BACK_IN[0],BACK_IN[1]+.15,age),46,60,71,INK)
		mist(boss,age,2.4*envelope(BACK_OUT[1],BACK_IN[0]+.05,BACK_IN[1],BACK_IN[1]+.35,age),46,60,73,INK)
	sprite(Motion.frame(kind,age),host,false,Color(1,1,1,host_alpha()))
	if is_instance_valid(_flat) and fx_layer:_flat.queue_redraw()
	if fx_layer:return
	if kind in ["buff","heal"]:support_effects()
	for e in shot_events():
		var dt:=age-float(e.time)
		match str(e.src):
			"clone":
				if dt<-.01 or dt>1.6:continue
				if clone_alpha(int(e.shooter))>.05 or dt>0:flash(e.mouth,e.d,dt,float(e.big))
				tracer(e.mouth,e.dest,dt,float(e.hit)-float(e.time),Color(.9,.83,.65))
				hit(e.dest,e.d,age-float(e.hit),accent,float(e.power),int(e.seed))
			"host":
				if dt<-.4 or dt>3.0:continue
				flash(e.mouth,e.d,dt,float(e.big))
				if e.has("intake"):
					# 銃身の先の裂け目へ撃ち込み、相手のそばの裂け目から当てる（覚醒後）
					rift(e.intake,age,envelope(float(e.time)-.25,float(e.time)-.05,float(e.time)+.18,float(e.time)+.45,age),11+int(e.index)*5)
					tracer(e.mouth,e.intake,dt,.07,Color(.92,.8,.68) if int(e.index)==0 else Color(.92,.39,.45))
					for x in e.exits:
						rift(x.exit,age,envelope(float(x.open),float(x.open)+.28,float(e.hit)+.04,float(e.hit)+.25,age),int(x.seed))
						tracer(x.exit,x.dest,age-float(x.from),float(e.hit)-float(x.from),Color(.95,.18,.3))
						hit(x.dest,x.dest-x.exit,age-float(e.hit),accent,float(e.power),int(x.hit_seed))
				else:
					tracer(e.mouth,e.dest,dt,float(e.hit)-float(e.time),Color(.95,.85,.7) if kind=="all" else Color(.92,.8,.68))
					hit(e.dest,e.d,age-float(e.hit),accent,float(e.power),int(e.seed))

## 弾ごとの出来事（この層の座標。今の時刻の本体・影の位置から）。_draw と、強めたエフェクト（rbm_gentleman_fx_*.gd）が読む。
## src: "clone"（影）/"host"（本体）、mouth・d: 銃口と銃身の向き、time: 撃つ時刻、hit: 当たる時刻、dest: 当たる所、target: 相手の番号
## （-1 は四人の中心）、power: 命中の強さ、big: 銃火の大きさ。覚醒後は intake（銃身の先の裂け目）と exits（相手のそばの裂け目）。
func shot_events() -> Array:
	var out: Array=[]
	for i in clone_count():
		var spot:=clone_spot(i)
		var g:=Motion.gun(Motion.AIM_POSE,"near",spot.flip)
		var mouth: Vector2=spot.foot+g.p
		for s in clone_shots(i):
			var volley:=bool(s.get("volley",false))
			out.append({"src":"clone","shooter":i,"mouth":mouth,"d":g.d,"time":float(s.time),"hit":float(s.hit),"dest":spot.dest,
				"target":int(spot.target),"volley":volley,"power":1.3 if volley else .6,"big":1.2 if volley else 1.0,"seed":i*40+int(float(s.time)*10)})
	var host:=host_foot()
	for i in data.host.size():
		var e: Dictionary=data.host[i]
		var pose:=Motion.frame(kind,float(e.time)-1.0/60.0)
		if kind=="single":pose=Motion.AIM_POSE
		var g:=Motion.gun(pose,str(e.hand))
		if g.is_empty():g={"p":Motion.muzzle(kind,float(e.time),str(e.hand)),"d":Vector2.LEFT}
		var mouth: Vector2=host+g.p
		var d: Vector2=g.d
		var ev:={"src":"host","index":i,"mouth":mouth,"d":d,"time":float(e.time),"hit":float(e.hit),"big":1.4 if awakened else 1.2}
		if kind=="single":
			ev.dest=aim(mouth,Vector2(foot(0).x+4,line_y(0,mouth.x)));ev.target=0;ev.power=1.4;ev.seed=12
		elif kind=="all":
			# 最後の一発（影が一斉に撃つ合図）: 構えた銃の向きのまま四人の中心へ（水平から3度以内）
			var mid:=center()
			ev.dest=aim(mouth,Vector2(mid.x+4,mid.y-GUN_H*.55));ev.target=-1;ev.power=1.6;ev.seed=21
		elif kind=="awakened_single":
			# 出口の裂け目は相手の右（紳士の側の空いている所）: 1発目は斜め上から、2発目は真横から
			var exit:=point(0)+(Vector2(36,-34) if i==0 else Vector2(44,0))
			ev.intake=mouth+d*44;ev.target=0;ev.power=1.55 if i==0 else 2.85;ev.dest=point(0)
			ev.exits=[{"exit":exit,"dest":point(0),"open":float(e.reentry)-.36,"from":float(e.reentry),"seed":31+i*5,"hit_seed":100+i*30,"target":0}]
		elif kind=="awakened_all":
			# 二丁の弾を銃身の先の裂け目へ。1発目は全員の頭上から、2発目は全員の横から当てる
			ev.intake=mouth+d*40;ev.target=-1;ev.power=1.6 if i==0 else 2.2;ev.dest=center()
			var exits: Array=[]
			for j in points.size():
				var body:=point(j)
				exits.append({"exit":body+(Vector2(34,-32) if i==0 else Vector2(40,2)),"dest":body,"open":float(e.time)-.05,"from":float(e.time)+.02,"seed":51+j*7+i*3,"hit_seed":80+j*40+i*7,"target":j})
			ev.exits=exits
		else:
			continue
		out.append(ev)
	return out

# ---- タイトルの紳士の部屋（rbm_gentleman_title_room.gd の PracticeEffects）が使う、前の版の銃火・弾・命中（見た目は前のまま）----
func tri(a: Vector2,b: Vector2,d: Vector2,color: Color) -> void:
	var aa:=a.round();var bb:=b.round();var dd:=d.round()
	if absf((bb-aa).cross(dd-aa))<.5:return
	draw_colored_polygon(PackedVector2Array([aa,bb,dd]),color)
func bullet(a: Vector2,b: Vector2,t: float,duration: float,color: Color) -> void:
	if t<0 or t>=duration:return
	var p:=clampf(t/duration,0,1)
	var tip:=a.lerp(b,p)
	ray(a.lerp(b,maxf(0,p-.28)),tip,c(color,.9),2)
	ray(a.lerp(b,maxf(0,p-.12)),tip,Color(.98,.96,.91),1)
func muzzle(p: Vector2,direction: Vector2,t: float) -> void:
	if t<0 or t>=.12:return
	var a:=1-t/.12
	var d:=direction.normalized();var side:=d.orthogonal()
	tri(p-side*4*a,p+d*22*a,p+side*4*a,c(Color(.99,.95,.85),a))
	ray(p-side*7*a,p+side*7*a,c(Color(.99,.98,.96),a),1)
func impact(p: Vector2,t: float,color: Color,power: float,seed: int=0) -> void:
	if t<0 or t>1.65:return
	var fade:=1-smoothstep(.12,.55,t)
	var growth:=.3+.7*smoothstep(0,.10,t)
	if fade>0:
		for i in (8 if power<1.0 else 27):
			var theta:=q(seed+i)*TAU
			var dir:=Vector2.from_angle(theta)
			var radius: float=(9+q(seed+i,1)*28)*power*growth
			tri(p+dir.orthogonal()*2*fade,p+dir*radius,p-dir.orthogonal()*2*fade,c(color,fade*.86))
		var shape:=PackedVector2Array()
		for i in 16:shape.append((p+Vector2.from_angle(i*TAU/16)*(15 if i%2==0 else 5)*power*growth).round())
		fill_polygon(shape,c(Color(.02,.015,.04),fade))
		if t<.13:
			ray(p-Vector2(8,0)*power,p+Vector2(8,0)*power,c(Color(.99,.98,.93),1-t/.13),3)
			ray(p-Vector2(0,12)*power,p+Vector2(0,12)*power,c(Color(.99,.98,.93),1-t/.13),2)
	if power>1:
		mist(p+Vector2(0,12),t,1.5*(1-smoothstep(.65,1.6,t)),55*power,35*power,seed)
		for i in 32:
			var theta:=q(seed+i+45)*TAU
			var velocity:=Vector2(cos(theta)*45,-35-65*q(seed+i,2))*power
			var pos:=p+velocity*t+Vector2(0,70*t*t)
			if t>.04:ray(pos-velocity*.018,pos,c(color,(1-smoothstep(.35,1.3,t))*.8),1)
