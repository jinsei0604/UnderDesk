extends RefCounted
## Approved black lightning, shared integer-pixel contours.
const FX=preload("res://src/bossmaker/visuals/plush/rbm_plush_fx.gd")
static func poly(ci: CanvasItem,p: Array,c: Color) -> void:FX.poly(ci,p,c)

static func lightning(ci: CanvasItem,t: float,home: Vector2) -> void:
	# Three sustained discharges, no full-screen flash; thick black branching cores.
	for pulse in range(3):
		var start: float=[2.32,3.38,4.55][pulse]
		var u:=t-start
		if u<0 or u>.48:continue
		var power:=smoothstep(0,.035,u)*(1-smoothstep(.19,.48,u))
		for side in [-1,1]:
			var center:=home+Vector2(side*64,-98)
			var pts: Array=[center,center+Vector2(side*23,-29),center+Vector2(side*18,-59),center+Vector2(side*48,-73),center+Vector2(side*43,-108),center+Vector2(side*76,-139),center+Vector2(side*69,-162)]
			if pulse==1:
				pts=[center,center+Vector2(side*31,10),center+Vector2(side*53,-5),center+Vector2(side*72,24),center+Vector2(side*101,19),center+Vector2(side*124,52)]
			if side==1:
				for j in range(1,pts.size()):pts[j]+=Vector2(5*sin(j*2.1+pulse),11*sin(j*1.7+pulse))
			bolt(ci,pts,7+float(pulse),power)
			var branch: Vector2=pts[3]
			bolt(ci,[branch,branch+Vector2(side*29,9),branch+Vector2(side*39,-8),branch+Vector2(side*62,-1)],3.5,power*.85)

static func bolt(ci: CanvasItem,pts: Array,w: float,alpha: float) -> void:
	# Joined miter contour: each discharge is a single solid silhouette, no bars/gaps.
	for layer in range(2):
		var left: Array=[];var right: Array=[]
		for i in range(pts.size()):
			var incoming: Vector2=(pts[i]-pts[maxi(0,i-1)]).normalized()
			var outgoing: Vector2=(pts[mini(pts.size()-1,i+1)]-pts[i]).normalized()
			if i==0:incoming=outgoing
			if i==pts.size()-1:outgoing=incoming
			var n: Vector2=(incoming.orthogonal()+outgoing.orthogonal()).normalized()
			var thickness: float=(w+1.3 if layer==0 else w)*pow(1-float(i)/float(pts.size()-1),.72)
			thickness/=maxf(.55,absf(n.dot(outgoing.orthogonal())))
			left.append(pts[i]-n*thickness);right.push_front(pts[i]+n*thickness)
		poly(ci,left+right,Color(.23,.13,.31,alpha) if layer==0 else Color(.008,.004,.018,alpha))
