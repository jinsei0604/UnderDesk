class_name UDGrid
extends RefCounted
## Horizontal tunnel grid (2026-07-14 redesign). Fixed height (the tunnel's
## thin vertical span); x extends rightward as the dig advances. y = 0 is the
## tunnel ceiling. Engine-node independent (§12-2). Stored row-major, so
## appending a column rebuilds the backing array — cheap at the idle dig
## cadence and the corridor's small height.

var width: int = 0
var height: int


func _init(p_height: int = UD.CORRIDOR_HEIGHT) -> void:
	height = p_height


var _cells: PackedInt32Array = PackedInt32Array()


## Appends one column at the right filled with the given terrain.
func append_column(terrain: UD.Terrain) -> void:
	var new_cells := PackedInt32Array()
	new_cells.resize((width + 1) * height)
	for y in height:
		for x in width:
			new_cells[y * (width + 1) + x] = _cells[y * width + x]
		new_cells[y * (width + 1) + width] = terrain
	_cells = new_cells
	width += 1


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
	var grid := UDGrid.new(int(d["height"]))
	grid.width = int(d["width"])
	var cells := PackedInt32Array()
	for v: Variant in d["cells"] as Array:
		cells.append(int(v))
	grid._cells = cells
	return grid
