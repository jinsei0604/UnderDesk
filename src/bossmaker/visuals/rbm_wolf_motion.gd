extends RefCounted
## 狼の技の動き（表示専用。戦闘の状態・乱数には触れない）。時刻だけから足元・絵・向きを決める。
## 2026-11-20 第3版（ユーザー「動きがありすぎ。本来の狼はこんな動きをしない」）: 本物の狼のように、低く身構えてじっと止まり、
## 一瞬で飛び込み、すぐ下がる。跳ね回らない・相手のまわりを回らない。止まっている時間を長く、動く時間は短く速く。
##   単体: 低く構えて止まる → 一瞬で低く飛び込む → 噛みつく（当たった瞬間は口が相手に重なる）→ うなって離す
##         → 振り向いて一瞬で元の場所へ駆け戻る → 振り向いて身構える
##   全体: 低くうなって構える → 見えない速さで四方八方から四人を突っ切る（7か所の間を8回駆け抜け、駆け抜けるたびに切り裂く）
##         → 元の場所へ戻って振り向き、うなった所で爪の跡が一斉に裂ける（2026-11-20 ユーザー「全体は一回だけでなく、四方八方に何度も
##         見えない速さで攻撃。今の1回の演出を高速で何回も」）
## 絵は要所の絵だけ（身構え 4・駆ける 8・噛む 2・うなる 10/9・立つ 1）。
var home:=Vector2(840,500)
const SCALE=155.0/300
var contact:=Vector2(436,470)
const MOUTH=(Vector2(95,380)-Vector2(256,460))*SCALE
var endpoint:=contact-MOUTH
const BITE_HIT=.58
## 単体の飛び込み（低く構えて止まる → 飛び込み → 最後に噛む）と駆け戻り
const BITE_DASH:=Vector2(.44,.54)
const BITE_BACK:=Vector2(.86,1.0)
## 全体: 構え（〜AOE_START）→ 駆け抜け AOE_LEGS 回（1回 AOE_DASH 秒、その間に止まって向きを変える AOE_STOP 秒）
## → AOE_START+AOE_RUN で元の場所 → 振り向いてうなる → AOE_HIT で爪の跡が一斉に裂ける
const AOE_START=.35
const AOE_DASH=.06
const AOE_STOP=.07
const AOE_LEGS=8
const AOE_RUN=AOE_LEGS*(AOE_DASH+AOE_STOP)-AOE_STOP
const AOE_HIT=1.46
## 駆け抜ける7か所（四人の中心からの向き、度。画面は下向きが正）。続けて結ぶと毎回四人の中を突っ切る
const AOE_ANGLES:=[180.0,-25.0,150.0,-70.0,110.0,-130.0,25.0]
const AOE_RADIUS:=Vector2(230,100)
## 駆け抜けるうち、1人に当たる（小さな数字が出る）回数の上限
const MAX_HITS:=3
## 駆ける間のわずかな浮き（低く走る）
const DASH_H=3.0
## 相手の足元・全体で駆け抜けた先（四人の向こう側、二列の間の高さ）
var party_feet: Array[Vector2]=[]
var far:=Vector2(160,450)
var party_center:=Vector2(352,447)

func sample(kind: String,t: float) -> Dictionary:
	var state={"foot":home,"pose":0,"flip":false,"lift":0.0,"air":false,"hidden":false}
	if t<0: return state
	if kind=="single":
		var crouch:=home+Vector2(6,2)
		var lunge_from:=endpoint+Vector2(36,0)
		if t<BITE_DASH.x:
			# 低く構えて止まる（少し後ろへ沈む）
			state.foot=home.lerp(crouch,smoothstep(0,.3,t))
			state.pose=4
		elif t<BITE_DASH.y:
			# 一瞬で低く飛び込む
			var u:=(t-BITE_DASH.x)/(BITE_DASH.y-BITE_DASH.x)
			state.lift=DASH_H*sin(u*PI)
			state.air=true
			state.foot=crouch.lerp(lunge_from,u)-Vector2(0,state.lift)
			state.pose=8
		elif t<BITE_HIT:
			# 最後のひと伸びで噛みつく
			var u:=(t-BITE_DASH.y)/(BITE_HIT-BITE_DASH.y)
			state.foot=lunge_from.lerp(endpoint,u)
			state.pose=2
		elif t<.72:
			# 噛みつき: 当たった瞬間は口が相手に重なる所で止め、それから少し押し込む
			var u:=clampf((t-BITE_HIT-.03)/(.72-BITE_HIT-.03),0,1)
			state.foot=endpoint+Vector2(-4*sin(u*PI),0)
			state.pose=2
		elif t<.80:
			# うなって離す
			state.foot=endpoint+Vector2(3*smoothstep(.72,.80,t),0)
			state.pose=10
		elif t<BITE_BACK.x:
			# 振り向く
			state.foot=endpoint+Vector2(3,0)
			state.pose=4
			state.flip=true
		elif t<BITE_BACK.y:
			# 一瞬で駆け戻る
			var u:=(t-BITE_BACK.x)/(BITE_BACK.y-BITE_BACK.x)
			state.lift=DASH_H*sin(u*PI)
			state.air=true
			state.foot=(endpoint+Vector2(3,0)).lerp(home,u)-Vector2(0,state.lift)
			state.pose=8
			state.flip=true
		elif t<1.25:
			state.pose=4
			state.flip=true
		elif t<1.45:
			# 振り向いて身構える
			state.pose=1
	elif kind=="aoe":
		var legs:=aoe_legs()
		var run_end:=AOE_START+AOE_RUN
		if t<AOE_START:
			# 低くうなって構える
			state.foot=home+Vector2(6*smoothstep(0,.25,t),2*smoothstep(0,.25,t))
			state.pose=10 if t<.2 else 4
		elif t<run_end+AOE_STOP:
			# 切り刻んでいる間は姿を見せない（2026-11-20 ユーザー指定）。元の場所に戻った所で現れる
			state.hidden=t<run_end
			var period:=AOE_DASH+AOE_STOP
			var i:=mini(int((t-AOE_START)/period),legs.size()-1)
			var ph:=t-AOE_START-i*period
			var from: Vector2=legs[i][0]
			var to: Vector2=legs[i][1]
			if ph<AOE_DASH:
				# 見えない速さで突っ切る
				var u:=ph/AOE_DASH
				state.lift=DASH_H*sin(u*PI)
				state.air=true
				state.foot=from.lerp(to,u)-Vector2(0,state.lift)
				state.pose=8
				state.flip=to.x>from.x
			else:
				# 一瞬止まって、次に飛び込む向きへ身構える
				state.foot=to
				state.pose=4
				if i+1<legs.size():
					state.flip=Vector2(legs[i+1][1]).x>to.x
				else:
					state.flip=to.x>from.x
		elif t<AOE_HIT+.40:
			# 元の場所で振り向いてうなる（ここで爪の跡が一斉に裂ける）
			state.pose=9
		elif t<AOE_HIT+.60:
			state.pose=1
	elif kind in ["buff","heal"]:
		if t<.28: state.pose=1
		elif t<.43: state.pose=7
		elif t<1.65: state.pose=5
		elif t<1.88: state.pose=7
	return state

## 全体の駆け抜けの道: [[から, まで], ...]（元の場所 → 7か所 → 元の場所）
func aoe_legs() -> Array:
	var pts: Array=[home+Vector2(6,2)]
	for a in AOE_ANGLES:
		var p:=party_center+Vector2(cos(deg_to_rad(a))*AOE_RADIUS.x,sin(deg_to_rad(a))*AOE_RADIUS.y)
		pts.append(Vector2(clampf(p.x,70,1210),clampf(p.y,340,545)))
	pts.append(home)
	var out: Array=[]
	for i in range(pts.size()-1):out.append([pts[i],pts[i+1]])
	return out

## 全体で、駆け抜けるたびに相手を切り裂く時刻: 相手の足元が駆け抜ける線から near 以内なら、いちばん近づく時刻
## limit: 返す回数の上限（小さな数字は MAX_HITS 回まで。切り傷の光は全部）
func aoe_hit_times(target_foot: Vector2,near: float=90.0,limit: int=MAX_HITS) -> Array:
	var out: Array=[]
	var legs:=aoe_legs()
	for i in range(legs.size()):
		var a: Vector2=legs[i][0]
		var b: Vector2=legs[i][1]
		var d:=b-a
		var u:=clampf((target_foot-a).dot(d)/maxf(d.length_squared(),1.0),0,1)
		if (a+d*u).distance_to(target_foot)<=near and u>0.02 and u<0.98:
			out.append(AOE_START+i*(AOE_DASH+AOE_STOP)+AOE_DASH*u)
	# 小さな数字が積み重なって読めなくならないよう、1人3回まで（最初・真ん中・最後）
	if out.size()>limit and limit==MAX_HITS:
		out=[out[0],out[out.size()/2],out[out.size()-1]]
	return out

## 駆け終わって足が地面に着いた時刻と足元（エフェクトの土煙に使う）。空中 → 地面に変わる所。
func landings(kind: String,until: float) -> Array:
	var out: Array=[]
	var was:=false
	var t:=0.0
	while t<until:
		var s:=sample(kind,t)
		if was and not bool(s.air):out.append([t,Vector2(s.foot)])
		was=bool(s.air)
		t+=1.0/120.0
	return out

func configure(boss_foot: Vector2,aim: Vector2,feet_in: Array[Vector2]) -> void:
	party_feet=feet_in
	home=boss_foot
	contact=aim
	endpoint=contact-MOUTH
	# 駆け抜けた先: 四人のいちばん左より少し先、四人の真ん中の高さ（前の列と後ろの列の間を通る）
	if not feet_in.is_empty():
		var min_x:=INF
		var sum:=Vector2.ZERO
		for foot in feet_in:
			min_x=minf(min_x,foot.x)
			sum+=foot
		far=Vector2(maxf(min_x-110,60),sum.y/feet_in.size())
		party_center=sum/feet_in.size()

## 前の版のエフェクト（rbm_wolf_vfx.gd。今は描かない）が読む道: 駆け抜ける一直線
func path_point(q: float) -> Vector2:
	return home.lerp(far,clampf(q,0,1))
