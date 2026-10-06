extends RefCounted
# Approved slime prototype v1; support body motion is identical for buff/heal.
const SINGLE_HIT=0.91
const BURST=0.88
func ramp(a: float,b: float,t: float) -> float:
	return smoothstep(a,b,t)
func sample(kind: String,t: float) -> Dictionary:
	var s={"scale":Vector2.ONE,"offset":Vector2.ZERO,"arm":0.0,"crush":0.0,"ripple":0.0}
	if t<0: return s
	if kind=="single":
		if t<.57:
			var q=ramp(0,.48,t)
			s.scale=Vector2(1+.15*q,1-.37*q)
		elif t<.91:
			var q=pow(clampf((t-.57)/.34,0,1),2.6)
			s.scale=Vector2(1.15-.30*q,.63+.30*q)
			s.arm=q
		elif t<1.10:
			s.scale=Vector2(.85,.93)
			s.arm=1.0
			s.crush=sin(clampf((t-.91)/.09,0,1)*PI/2)
		elif t<1.90:
			var q=ramp(1.10,1.90,t)
			s.arm=1-q
			s.crush=1-ramp(1.10,1.25,t)
			s.ripple=sin(q*PI)*12
			s.scale=Vector2(.85+.15*q,.93+.07*q)
		elif t<2.52:
			var q=(t-1.90)/.62
			var wob=sin(q*PI*4)*(1-q)*.16
			s.scale=Vector2(1+wob,1-wob)
	elif kind=="aoe":
		if t<.52:
			var q=ramp(0,.15,t)
			s.offset=Vector2(sin(t*100)*6,cos(t*87)*3)*q
			s.scale=Vector2(1+sin(t*82)*.05,1+cos(t*72)*.05)
		elif t<.88:
			var q=ramp(.52,.85,t)
			s.scale=Vector2(1+.38*q,1-.62*q)
			s.offset.x=sin(t*110)*3
		elif t<1.03:
			var q=ramp(.88,1.03,t)
			s.scale=Vector2(1.38-.55*q,.38+.82*q)
		elif t<1.50:
			var q=(t-1.03)/.47
			var wob=sin(q*PI*3)*(1-q)*.15
			s.scale=Vector2(lerpf(.83,1,q)+wob,lerpf(1.20,1,q)-wob)
	else:
		if t<.38:
			var q=ramp(0,.38,t)
			s.scale=Vector2(1+.18*q,1-.37*q)
		elif t<1.12:
			s.scale=Vector2(1.18,.63)
		elif t<1.63:
			var q=ramp(1.12,1.63,t)
			s.scale=Vector2(lerpf(1.18,1.30,q),lerpf(.63,1.40,q))
		elif t<1.90:
			s.scale=Vector2(1.30,1.40)
		elif t<2.95:
			var q=(t-1.90)/1.05
			var wob=sin(q*PI*6)*.18*(1-q)
			s.scale=Vector2(lerpf(1.30,1,ramp(0,.55,q))+wob,lerpf(1.40,1,ramp(0,.55,q))-wob)
	return s


var home:=Vector2.ZERO
var contact:=Vector2.ZERO
var feet: Array[Vector2]=[]
func configure(origin: Vector2,aim: Vector2,targets: Array[Vector2]) -> void:
	home=origin
	contact=aim
	feet=targets.duplicate()
