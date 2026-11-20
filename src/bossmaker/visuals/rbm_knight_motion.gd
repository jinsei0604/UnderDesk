extends RefCounted
## 戦闘テンポ（2026-10-16）: 演出の時刻のうち詰める区間（rbm_tempo_map.gd、[から, まで, 実時間]）。一覧画像（0.1秒ごと）で確かめた区間だけ。
## 回復・強化: 剣を掲げたまま光が昇る所（効果音は1.1秒で終わる）を2倍の速さで。攻撃は変えない。
const TEMPO={"heal":[[1.30,2.10,0.40]],"buff":[[1.30,2.10,0.40]]}
static func tempo(kind: String) -> Array:
	return TEMPO.get(kind,[])
var home:=Vector2(840,500)
const SCALE=170.0/320
var contact:=Vector2(436,470)
const SWORD_TIP=(Vector2(84,449)-Vector2(256,460))*SCALE
var endpoint:=contact-SWORD_TIP
const SINGLE_HIT=.84
## 単体: 振り下ろす時刻と、踏み込む一歩（ステージの画素）
const SWING=.64
const STEP_DIST=18.0
const AOE_HIT=1.08
var wave_source:=Vector2(718,402)

func sample(kind: String,t: float) -> Dictionary:
	var state={"foot":home,"pose":0,"flip":false}
	if t<0: return state
	if kind=="single":
		# 2026-11-20 作り直し（ユーザー「本来の動きでない、動きがありすぎ」→ ゴーレム・狼と同じく画面を滑らない）:
		# その場で剣を立てて構える → 頭上に振りかぶって溜める → 一歩だけ重く踏み込んで振り下ろす（剣圧が飛んで相手を斬る）
		# → 振り下ろした姿のまま見届ける → 一歩下がって剣を立て、構えに戻る。
		var step:=home+Vector2(-STEP_DIST,0)
		if t<.12: state.pose=8
		elif t<SWING-.04: state.pose=9
		elif t<SWING+.06:
			var m:=clampf((t-SWING+.04)/.10,0,1)
			state.foot=(home.lerp(step,m*m*(3-2*m))+Vector2(0,-3*sin(m*PI))).round()
			state.pose=9 if m<.4 else 2
		elif t<1.20:
			state.foot=step+Vector2(0,roundf(2*(1-smoothstep(SWING+.06,SWING+.16,t))))
			state.pose=2
		elif t<1.36:
			var m:=(t-1.20)/.16
			state.foot=(step.lerp(home,m*m*(3-2*m))+Vector2(0,-3*sin(m*PI))).round()
			state.pose=8
		elif t<1.80:
			state.pose=8
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
