extends RefCounted
## Esc（ui_cancel）で「戻る・閉じる・キャンセル」をする時の共通の入口（プレイ体験監査 PX-13、2026-10-18。品質の決まり UI_UX §14）。
## 各画面の _unhandled_input から使う。Godot は手前（後に足した・深い）ノードから順に _unhandled_input を呼ぶので、
## 一番手前の画面（開いている窓・確認）が先に受け取る。受け取ったら consume() で、ほかの画面へ届かないようにする。
## 押した時の音は、戻るボタンを押した時と同じ「ui_cancel」。

## この入力が、表示中の node に届いた Esc か（押し続けの繰り返しは除く）。
static func pressed(node: Node, event: InputEvent) -> bool:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return false
	return node.is_inside_tree() and node is CanvasItem and (node as CanvasItem).is_visible_in_tree()

## Esc を受け取ったことにする（音を鳴らし、ほかの画面へ届かないようにする）。
static func consume(node: Node, sound := true) -> void:
	if sound:
		preload("res://src/bossmaker/rbm_audio.gd").cue(node, "ui_cancel")
	if node.is_inside_tree():
		node.get_viewport().set_input_as_handled()
