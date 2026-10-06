extends RefCounted
const HIT := 1.50
const DURATION := 3.85
var home := Vector2(840, 500)
var endpoint := Vector2(635, 525)

var contact:=Vector2.ZERO
func configure(origin: Vector2,aim: Vector2,_targets: Array[Vector2]) -> void:
	home=origin
	contact=aim

func sample(_kind: String,t: float) -> Dictionary:
	var s := {"pose":0,"foot":home,"phase":"構え"}
	if t < 0: return s
	if t < .34:
		s.pose=1
		s.phase="低く構えて力を溜める"
	elif t < .73:
		var q := clampf((t-.34)/.39,0,1)
		s.pose=2 if q < .52 else 3
		s.foot=home.lerp(home.lerp(endpoint,.52),smoothstep(0,1,q))
		s.foot.y-=6*sin(q*PI)
		s.phase="前脚を踏み出す"
	elif t < 1.12:
		var q := clampf((t-.73)/.39,0,1)
		s.pose=2 if q < .52 else 3
		s.foot=home.lerp(endpoint,.52).lerp(endpoint,smoothstep(0,1,q))
		s.foot.y-=4*sin(q*PI)
		s.phase="体重を乗せて踏ん張る"
	elif t < 1.34:
		s.pose=4
		s.foot=endpoint
		s.phase="首を引いて口を開く"
	elif t < HIT:
		s.pose=5
		s.foot=endpoint
		s.phase="首と頭を一気に突き出す"
	elif t < 1.64:
		s.pose=6
		s.foot=endpoint
		s.phase="顎を閉じて噛み込む"
	elif t < 1.83:
		s.pose=7
		s.foot=endpoint
		s.phase="噛み込んだ重さを受け止める"
	elif t < 2.12:
		s.pose=8
		s.foot=endpoint
		s.phase="首を引き戻す"
	elif t < 2.72:
		var q := clampf((t-2.12)/.60,0,1)
		s.pose=9 if q < .55 else 10
		s.foot=endpoint.lerp(endpoint.lerp(home,.5),smoothstep(0,1,q))
		s.foot.y-=3*sin(q*PI)
		s.phase="体重を後ろへ移して戻る"
	elif t < 3.32:
		var q := clampf((t-2.72)/.60,0,1)
		s.pose=9 if q < .55 else 10
		s.foot=endpoint.lerp(home,.5).lerp(home,smoothstep(0,1,q))
		s.foot.y-=3*sin(q*PI)
		s.phase="脚を踏み替えて構えへ"
	elif t < 3.58:
		s.pose=10
		s.phase="姿勢を落ち着ける"
	return s
