class_name UDGrid
extends RefCounted
## 2D cross-section grid. y = 0 is the surface row; rows extend downward.
## Engine-node independent (§12-2).

var width: int
var height: int = 0
var _cells: PackedInt32Array = PackedInt32Array()


func _init(p_width: int = UD.GRID_WIDTH) -> void:
	width = p_width


## Appends one row at the bottom filled with the given terrain.
func append_row(terrain: UD.Terrain) -> void:
	var row := PackedInt32Array()
	row.resize(width)
	row.fill(terrain)
	_cells.append_array(row)
	height += 1


func is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func terrain_at(pos: Vector2i) -> UD.Terrain:
	assert(is_inside(pos))
	return _cells[pos.y * width + pos.x] as UD.Terrain


func set_terrain(pos: Vector2i, terrain: UD.Terrain) -> void:
	assert(is_inside(pos))
	_cells[pos.y * width + pos.x] = terrain


func is_walkable(pos: Vector2i) -> bool:
	return is_inside(pos) and terrain_at(pos) == UD.Terrain.AIR


func to_dict() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"cells": Array(_cells),
	}


static func from_dict(d: Dictionary) -> UDGrid:
	var grid := UDGrid.new(int(d["width"]))
	grid.height = int(d["height"])
	var cells := PackedInt32Array()
	for v: Variant in d["cells"] as Array:
		cells.append(int(v))
	grid._cells = cells
	return grid
