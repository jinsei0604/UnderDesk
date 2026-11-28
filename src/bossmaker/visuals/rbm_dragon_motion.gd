extends RefCounted
## 竜の強化・回復（咆哮）の体の動き。2026-11-28: 前の攻撃（息吹・隕石）の動きと戦闘テンポの表は削除した
## （攻撃4種は dragon/rbm_dragon_attack_host.gd の各エフェクトが体の動きも持つ）。
const SUPPORT_HIT:=.90
const SUPPORT_RELEASE:=.26
const SUPPORT_DURATION:=2.35
var home:=Vector2.ZERO
func configure(origin: Vector2) -> void:
	home=origin
func sample(kind: String,t: float) -> Dictionary:
	var s={"pose":0,"foot":home,"scale":Vector2.ONE,"neck":0.0}
	if t<0: return s
	if kind in ["buff","heal"]:
		if t<.25: s.pose=1
		elif t<.57:
			s.pose=4
			s.scale=Vector2(1,1+.06*smoothstep(.25,.57,t))
		elif t<1.50:
			s.pose=9
			s.scale=Vector2(1.04,1.06)
		elif t<1.82:
			s.pose=4
			s.scale=Vector2(1,1+.06*(1-smoothstep(1.50,1.82,t)))
		elif t<2.12: s.pose=7
	return s
