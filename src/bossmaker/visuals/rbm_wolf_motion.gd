extends RefCounted
var home:=Vector2(840,500)
const SCALE=155.0/300
var contact:=Vector2(436,470)
const MOUTH=(Vector2(95,380)-Vector2(256,460))*SCALE
var endpoint:=contact-MOUTH
const BITE_HIT=.58
const AOE_HIT=.92
const AOE_START=.20
const AOE_RUN=.85
var path: Array[Vector2]=[Vector2(840,500),Vector2(620,501),Vector2(394,520),Vector2(221,477),Vector2(260,404),Vector2(431,382),Vector2(530,427),Vector2(674,482),Vector2(840,500)]

static func run_pose(t: float) -> int:
	return [1,2,3,2][int(t*22)%4]

func path_point(q: float) -> Vector2:
	var f:=clampf(q,0,.999999)*(path.size()-1)
	var i:=int(f)
	var t:=f-i
	var a: Vector2=path[maxi(i-1,0)]
	var b: Vector2=path[i]
	var c: Vector2=path[mini(i+1,path.size()-1)]
	var d: Vector2=path[mini(i+2,path.size()-1)]
	return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)

func sample(kind: String,t: float) -> Dictionary:
	var state={"foot":home,"pose":0,"flip":false}
	if t<0: return state
	if kind=="single":
		if t<.25: state.pose=1
		elif t<BITE_HIT:
			var q:=clampf((t-.25)/.33,0,1)
			state.foot=home.lerp(endpoint,q)+Vector2(0,-4*absf(sin(q*PI*2)))
			state.pose=run_pose(t-.25) if t<.50 else 2
		elif t<.67:
			state.foot=endpoint
			state.pose=2
		elif t<.78:
			state.foot=endpoint
			state.pose=1
		elif t<.96:
			state.foot=endpoint+Vector2(14*smoothstep(.78,.96,t),0)
			state.pose=3
		elif t<1.52:
			var q:=clampf((t-.96)/.56,0,1)
			state.foot=(endpoint+Vector2(14,0)).lerp(home,q)+Vector2(0,-3*absf(sin(q*PI*3)))
			state.pose=run_pose(t-.96)
			state.flip=true
	elif kind=="aoe":
		if t<AOE_START: state.pose=4
		elif t<AOE_START+AOE_RUN:
			var q:=clampf((t-AOE_START)/AOE_RUN,0,1)
			state.foot=path_point(q)+Vector2(0,-3*absf(sin(t*31)))
			state.pose=run_pose(t*1.30)
			state.flip=path_point(minf(q+.006,.99999)).x>path_point(maxf(q-.006,0)).x
		elif t<1.22: state.pose=3
	elif kind in ["buff","heal"]:
		if t<.28: state.pose=1
		elif t<.43: state.pose=7
		elif t<1.65: state.pose=5
		elif t<1.88: state.pose=7
	return state

func configure(boss_foot: Vector2,aim: Vector2,party_feet: Array[Vector2]) -> void:
	home=boss_foot
	contact=aim
	endpoint=contact-MOUTH
	var sum:=Vector2.ZERO
	for foot in party_feet: sum+=foot
	var center:=sum/maxi(party_feet.size(),1)
	var party_delta:=center-Vector2(352.5,447.5)
	var boss_delta:=home-Vector2(840,500)
	for i in range(path.size()):
		var weight:=clampf((path[i].x-500)/340,0,1)
		path[i]+=party_delta.lerp(boss_delta,weight)
