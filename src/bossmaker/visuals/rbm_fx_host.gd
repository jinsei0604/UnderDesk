class_name RBMFxHost
extends Node2D
## 初期のボス（ゴーレム・狼など）の技に、ヒーロー・聖獣と同じ部品のエフェクト（RBMHeroFxBase を継いだ物）を重ねる入れ物
## （2026-11-20。表示専用。戦闘の状態・乱数には触れない）。動き（本体のポーズ・移動・時刻）は各ボスのつなぎのまま。
## 座標: エフェクトは 640×360 の論理ドット（ステージの半分）。ここで2倍してステージに重ねる。
## 層（z はステージの中の絶対値）: 後ろ1 ＜ 味方2 ＜ 本体3 ＜ 前18。

var fx: RBMHeroFxBase
var _world: Node2D

## fx を作って置く。targets は相手の足元（ステージの座標）。
func setup(stage: Control, fx_node: RBMHeroFxBase, target_feet: Array) -> void:
	fx = fx_node
	_world = Node2D.new()
	_world.scale = Vector2(2, 2)
	add_child(_world)
	var back := _layer("FxBack", 1)
	var front := _layer("FxFront", 18)
	fx.mid = back
	var targets: Array = []
	for p in target_feet:
		if targets.size() < 4:
			targets.append(Vector2(p) * 0.5)
	for i in range(4):
		fx.present[i] = i < targets.size()
		if i >= targets.size():
			targets.append(Vector2(175, 225))
	_world.add_child(fx)
	fx.setup(back, front, targets)
	position = Vector2.ZERO
	if is_instance_valid(stage):
		size_from(stage)

func size_from(_stage: Control) -> void:
	pass

func _layer(layer_name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	n.z_as_relative = false
	n.z_index = z
	_world.add_child(n)
	return n

## t 秒の見た目にする。foot はボスの足元（ステージの座標）。
func advance(t: float, foot: Vector2) -> void:
	if fx == null:
		return
	fx.advance(t, "", foot * 0.5, foot * 0.5)

func clear() -> void:
	visible = false
