extends RefCounted
const BREATH_HIT:=1.02
const FOCUSED_HIT:=1.04
const METEOR_HIT:=1.65
const SUPPORT_HIT:=.90
## 戦闘テンポ（2026-10-16）: 演出の時刻のうち詰める区間（rbm_tempo_map.gd、[から, まで, 実時間]）。一覧画像（0.1秒ごと）と完成トラックの
## 無音で、画面も音も止まっていることを確かめた区間だけ（最後の0.5秒は残す）。噛みつき・回復・強化・覚醒は変えない。
const TEMPO:={"breath":[[3.05,3.55,0.0]],"focused_breath":[[3.35,3.95,0.0]],"meteors":[[5.80,6.15,0.0]]}
static func tempo(kind: String) -> Array:
	return TEMPO.get(kind,[])
var home:=Vector2.ZERO
var contact:=Vector2.ZERO
var feet: Array[Vector2]=[]
func configure(origin: Vector2,aim: Vector2,targets: Array[Vector2]) -> void:
	home=origin
	contact=aim
	feet=targets.duplicate()
func sample(kind: String,t: float) -> Dictionary:
	var s={"pose":0,"foot":home,"scale":Vector2.ONE,"neck":0.0}
	if t<0: return s
	if kind in ["breath","focused_breath"]:
		if t<.24: s.pose=1
		elif t<.65:
			s.pose=4
			s.scale=Vector2(1.0,1.0+.05*sin((t-.24)/.41*PI))
		elif t<(2.64 if kind=="breath" else 2.90):
			s.pose=2 if kind=="breath" else 5
			s.foot=home+Vector2(5,0)
		elif t<(2.89 if kind=="breath" else 3.15): s.pose=1
		if kind=="focused_breath":
			s.foot=home
			s.scale=Vector2.ONE
	elif kind=="meteors":
		if t<.26: s.pose=10
		elif t<.54: s.pose=4
		elif t<1.64:
			s.pose=9
			s.scale=Vector2(1,1+.04*sin((t-.54)*6))
		elif t<2.55: s.pose=4
		elif t<2.88: s.pose=3
	elif kind in ["buff","heal"]:
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
