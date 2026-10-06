extends RefCounted
var home:=Vector2(840,500)
const SCALE=170.0/320
var contact:=Vector2(436,470)
const SWORD_TIP=(Vector2(84,449)-Vector2(256,460))*SCALE
var endpoint:=contact-SWORD_TIP
const SINGLE_HIT=.84
const AOE_HIT=1.08
var wave_source:=Vector2(718,402)

func sample(kind: String,t: float) -> Dictionary:
	var state={"foot":home,"pose":0,"flip":false}
	if t<0: return state
	if kind=="single":
		if t<.12: state.pose=8
		elif t<.42: state.pose=9
		elif t<.78:
			var q:=clampf((t-.42)/.36,0,1)
			state.foot=home.lerp(endpoint+Vector2(18,0),smoothstep(0,1,q))
			state.pose=9 if q<.78 else 8
		elif t<SINGLE_HIT:
			state.foot=(endpoint+Vector2(18,0)).lerp(endpoint,(t-.78)/.06)
			state.pose=8
		elif t<1.18:
			state.foot=endpoint
			state.pose=2
		elif t<1.92:
			var q:=clampf((t-1.18)/.74,0,1)
			state.foot=endpoint.lerp(home,smoothstep(0,1,q))
			state.pose=8 if q<.55 else 0
	elif kind=="aoe":
		if t<.62: state.pose=4
		elif t<.76: state.pose=5
		elif t<1.26: state.pose=3
		elif t<1.46: state.pose=8
	elif kind in ["buff","heal"]:
		if t<.20: state.pose=0
		elif t<2.05: state.pose=8
	return state

func configure(boss_foot: Vector2,aim: Vector2,_party_feet: Array[Vector2]) -> void:
	home=boss_foot
	contact=aim
	endpoint=contact-SWORD_TIP
	wave_source=home+Vector2(-122,-98)
