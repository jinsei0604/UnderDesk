class_name RBMHeroFxRibbon
extends Node2D
## 道筋に沿った帯のメッシュ。見た目は ribbon シェーダーの uniform で動かす。

var _pts := PackedVector2Array()
var _uv := PackedVector2Array()
var _idx := PackedInt32Array()
var _col := PackedColorArray()

func set_path(path: PackedVector2Array, half_width: float) -> void:
	_pts.clear()
	_uv.clear()
	_idx.clear()
	_col.clear()
	var n := path.size()
	if n < 2:
		queue_redraw()
		return
	var total := 0.0
	for i in range(n - 1):
		total += path[i].distance_to(path[i + 1])
	var run := 0.0
	for i in range(n):
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, n - 1)]
		var d := (b - a).normalized()
		var nv := Vector2(-d.y, d.x)
		if i > 0:
			run += path[i - 1].distance_to(path[i])
		var u := run / maxf(total, 0.001)
		_pts.append(path[i] + nv * half_width)
		_uv.append(Vector2(u, -1.0))
		_pts.append(path[i] - nv * half_width)
		_uv.append(Vector2(u, 1.0))
		_col.append(Color.WHITE)
		_col.append(Color.WHITE)
	for i in range(n - 1):
		var k := i * 2
		_idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	queue_redraw()

func _draw() -> void:
	if _idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _col, _uv)
