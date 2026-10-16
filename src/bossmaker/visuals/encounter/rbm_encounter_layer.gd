extends Node2D
## 登場・勝利の演出の描画の層（表示専用）。draw_fn に渡した関数で、この層に描く。
var draw_fn: Callable

func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
