extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## The accepted cloth collapse uses the existing encounter/victory lifecycle.
const Render=preload("res://src/bossmaker/visuals/plush/rbm_plush_render.gd")
const VFX_PATHS=["res://assets_bossmaker/battle/plush/poses.png","res://assets_bossmaker/battle/plush/fx.png","res://assets_bossmaker/battle/plush/aura-v5.png"]
var body: Control
var clip:="normal_defeat"

func duration() -> float:return 5.0 if asset=="plush_awakened" else 3.6

func begin() -> void:
	super.begin()
	clip="awakened_defeat" if asset=="plush_awakened" else "normal_defeat"
	# Owned by the victory layer so cancel/exit frees every temporary node.
	body=Render.new();body.home=home()
	p.boss_body.add_child(body)
	p.boss_body.draw_fn=Callable();p.boss_flat.draw_fn=Callable()
	body.show_action(clip,0)
	white=0

func advance(t: float,_dt: float) -> void:
	age=t
	if is_instance_valid(body):body.show_action(clip,minf(t,duration()))
