extends "res://src/bossmaker/visuals/plush/rbm_plush_v11_render.gd"
## Only the dark rush drawing changes. V11 preparation, timing, sound and return
## remain inherited. The awakening layer owns the approved voice and face cue.
const RUSH_TINT=Color(.24,.20,.30)
const BODY_TINT=Color(.22,.22,.24,.65)

func show_action(key: String,t: float) -> void:
	super.show_action(key,t)
	if key=="awakened_all":dark_front.self_modulate=RUSH_TINT

func combo_state() -> Dictionary:
	var heavy:=age>=LAST_HIT-.17 and age<LAST_HIT+.24
	var index:=rush_index()
	# A full reach / hit / return fits inside the shortest 120 ms hit interval.
	# V11 selected the next arm 90 ms early, cutting the previous recovery short.
	if not heavy:
		index=-1
		for i in HITS.size():
			if age>=float(HITS[i])-.055:index=i
	if not heavy and index<0:return {}
	var q:=age-(LAST_HIT if heavy else float(HITS[index]))
	var anticipation:=.17 if heavy else .055
	var recovery:=.24 if heavy else .060
	if q < -anticipation or q>=recovery:return {}
	var target: Vector2=home+Vector2(-320,0)
	if not HOMES.is_empty():
		target=HOMES.values()[index%HOMES.size()]
		if heavy:
			target=Vector2.ZERO
			for p in HOMES.values():target+=p
			target/=HOMES.size()
	# The shoulder never leaves the stationary body. Reach first, then a fast
	# downward arc, a brief contact and a visibly folding return to the shoulder.
	var origin:=home+Vector2(1,-86)
	var contact:=target+Vector2(0,-32)
	var rest:=origin+Vector2(-42,7)
	var raised:=contact+Vector2(30 if index%2 else -22,-108 if heavy else -70)
	var extend:=smoothstep(-anticipation,-anticipation*.46,q)
	var strike:=pow(smoothstep(-anticipation*.46,0,q),1.45)
	var withdraw:=smoothstep(.06 if heavy else .012,recovery,q)
	var hand:=rest.lerp(raised,extend).lerp(contact,strike).lerp(rest,withdraw)
	var elbow:=origin.lerp(hand,.48)+Vector2(0,-40 if index%2 else -24)
	var fade:=smoothstep(-anticipation,-anticipation*.62,q)*(1-withdraw)
	return {"body":home,"origin":origin,"elbow":elbow,"hand":hand,
		"pose":5.8,"curl":strike*(1-withdraw)*.48,
		"alpha":fade*(.82 if heavy else .76),"heavy":heavy,"index":index}

func _draw_bear_rush(ci: CanvasItem) -> void:
	# A single, nearly invisible stationary body, never an attacking whole-body
	# sprite or an afterimage. Its exact pose and screen location stay constant.
	stamp(ci,"awakened_all",5.8,home,BODY_TINT)
	var state:=combo_state()
	if state.is_empty():return
	var opacity: float=state.alpha
	var origin: Vector2=state.origin;var elbow: Vector2=state.elbow;var hand: Vector2=state.hand
	var heavy: bool=state.heavy
	# Reuse the approved single attack's cloth sleeve and native giant claw.
	sleeve(ci,origin,elbow,34 if heavy else 28,opacity)
	sleeve(ci,elbow,hand+Vector2(0,60),42 if heavy else 36,opacity)
	stamp(ci,"giant_claw",float(state.curl),hand,Color(1,1,1,opacity))
