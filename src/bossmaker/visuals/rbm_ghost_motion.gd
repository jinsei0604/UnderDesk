extends RefCounted
var home:=Vector2(910,505)
var target_foot:=Vector2(275,490)
const SINGLE_HIT=1.43
const ALL_HIT=1.62

func configure(origin: Vector2,feet: Array[Vector2]) -> void:
	home=origin
	if not feet.is_empty(): target_foot=feet[0]

func sample(kind: String,t: float) -> Dictionary:
	var s={"foot":home,"pose":0,"alpha":1.0,"flip":false,"scale":Vector2.ONE,"ripple":0.0}
	if t<0: return s
	if kind=="single":
		if t<.84:
			s.pose=1 if t>.18 else 0
			s.alpha=1-smoothstep(.18,.84,t)
			s.ripple=sin(clampf((t-.18)/.66,0,1)*PI)*2
		elif t<1.04: s.alpha=0.0
		elif t<1.32:
			s.foot=target_foot+Vector2(-132,0)
			s.pose=2
			s.flip=true
		elif t<1.58:
			s.foot=target_foot+Vector2(lerpf(-132,180,(t-1.32)/.26),0)
			s.pose=2
			s.flip=true
			s.scale=Vector2(1.16,.94)
			s.alpha=.83
		elif t<1.94:
			s.foot=target_foot+Vector2(180,0)
			s.pose=7
			s.flip=true
			s.alpha=1-smoothstep(1.62,1.94,t)
		elif t<2.25: s.alpha=0.0
		elif t<2.86: s.alpha=smoothstep(2.25,2.86,t)
	elif kind=="all":
		var lift=smoothstep(.15,.80,t)*(1-smoothstep(2.90,3.42,t))
		s.foot=home+Vector2(0,-29*lift)
		if t>=.20 and t<.48: s.pose=4
		elif t>=.48 and t<2.42: s.pose=5
		elif t>=2.42 and t<3.08: s.pose=7
	else:
		# Buff and heal share this entire body timeline; only VFX selects a color.
		var lift=smoothstep(.12,.65,t)*(1-smoothstep(2.98,3.50,t))
		s.foot=home+Vector2(0,-25*lift)
		if t>=.18 and t<.55: s.pose=4
		elif t>=.55 and t<2.42: s.pose=5
		elif t>=2.42 and t<2.97: s.pose=7
		elif t>=2.97 and t<3.28: s.pose=8
		var q=clampf((t-2.4)/.55,0,1)
		var wobble=sin(q*TAU*1.5)*(1-q)
		s.scale=Vector2(1+wobble*.14,1-wobble*.09)
		s.ripple=sin(q*PI)*4
	return s
