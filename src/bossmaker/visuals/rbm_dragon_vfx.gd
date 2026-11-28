extends Node2D
## 竜の強化・回復の咆哮の絵（集まる線・声の輪・足元の輪と光の粒）。2026-11-28: 前の攻撃（息吹・隕石）の絵は削除した。
const Support=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")
const SUPPORT=Support.COLORS
var kind:="buff"
var age:=-1.0
var body: Node2D

func prepare() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

func advance(t: float) -> void:
	age=t
	queue_redraw()

func line(a: Vector2,b: Vector2,c: Color,width: float=4) -> void:
	draw_line((a/4).round()*4,(b/4).round()*4,c,width,false)
func ring(p: Vector2,r: Vector2,c: Color,width: float=4) -> void:
	for i in range(20):
		var a=i*TAU/20
		var b=(i+1)*TAU/20
		line(p+Vector2(cos(a)*r.x,sin(a)*r.y),p+Vector2(cos(b)*r.x,sin(b)*r.y),c,width)


func _draw() -> void:
	if age<0 or not is_instance_valid(body): return
	if kind in SUPPORT: roar(SUPPORT[kind])

func roar(c: Color) -> void:
	var mouth: Vector2=body.mouth_point()
	var home: Vector2=body.foot_point()
	if age>=.22 and age<.9:
		var q=(age-.22)/.68
		for i in range(15):
			var a=i*2.399
			var p=home+Vector2(0,-82)+Vector2(cos(a),sin(a))*(90*(1-q)+10)
			line(p,p+(home+Vector2(0,-82)-p).normalized()*8,c,4)
	if age>=.65 and age<1.83:
		for i in range(4):
			var q=(age-.65-i*.18)/.62
			if q<0 or q>1: continue
			var col=c
			col.a=1-smoothstep(.5,1,q)
			ring(mouth+Vector2(0,-q*90),Vector2(18+q*54,6+q*12),col,4)
	if age>=.9 and age<2.15:
		var q=(age-.9)/1.25
		var col=c
		col.a=1-smoothstep(.6,1,q)
		ring(home+Vector2(0,-3),Vector2(72+q*42,15+q*8),col,4)
		for i in range(14):
			var p=home+Vector2(sin(i*5.3)*(40+q*50),-q*155-(i%4)*12)
			line(p-Vector2(0,4),p+Vector2(0,4),col,4)
			if i%3==0: line(p-Vector2(4,0),p+Vector2(4,0),col,4)
