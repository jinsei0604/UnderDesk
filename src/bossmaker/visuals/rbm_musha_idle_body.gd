extends Node2D
## 朽ちた機械武者の待機中の本体(承認済み 2026-09-27)。原画の静止姿をコマ描画(rbm_musha_frames.gd)でそのまま描く(揺らさない)。
## 覚醒後は抜刀待機(a3)を描き、墨の層(rbm_musha_ink_director.gd)へ本体の状態(刀の位置)を渡す(刀から立ち昇る墨の出どころ)。
##
## 描くのは「行動の再生中でなく、ボスが普段の姿勢(0番)で見えている」ときだけ。そのときだけステージのボスの見た目を
## 透明にして代わりに描く。それ以外(武者の行動中は演出が本体を描き、味方の行動中・防御などの姿勢ではボスの見た目の
## 被弾の姿勢・光をそのまま見せる)は描かず、ボスの見た目を元へ戻す。表示専用で、戦闘の状態には触れない。
const Frames = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")

var stage: Control
var director
var state: Dictionary = {}
var _boss: Control

func setup(st: Control, dir) -> void:
	stage = st
	director = dir
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1
	_boss = st._visuals["boss"]
	st.add_child(self)
	st.move_child(self, _boss.get_index() + 1)
	_sync()

func _process(_delta: float) -> void:
	_sync()

func _sync() -> void:
	if not is_instance_valid(stage) or not is_instance_valid(_boss):
		visible = false
		return
	var shown: bool = not stage.is_playing() and _boss.visible and int(stage._poses.get("boss", 0)) == 0
	_boss.self_modulate.a = 0.0 if shown else 1.0
	visible = shown
	if not shown:
		return
	var awk := str(stage._asset_ids.get("boss", "")) == "musha_awakened"
	state = Frames.state("a3" if awk else "idle", stage._foot("boss"))
	if is_instance_valid(director):
		director.set_body(state)
	queue_redraw()

func _draw() -> void:
	if not state.is_empty():
		Frames.draw(self, state)

## ステージから外す(別のボスへの切り替え・ステージの破棄)。ボスの見た目を元へ戻す。
func dispose() -> void:
	if is_instance_valid(_boss):
		_boss.self_modulate.a = 1.0
	stage = null
	queue_free()
