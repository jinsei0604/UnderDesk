class_name UDPathfinder
extends RefCounted
## BFS pathfinding over walkable (AIR) cells. The cross-section is small,
## so BFS is sufficient (§7.2). Direction order is fixed for determinism.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## Returns the full cell sequence from `from` to `to` inclusive,
## or an empty array when unreachable. `to` must be walkable.
static func find_path(grid: UDGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not grid.is_walkable(from) or not grid.is_walkable(to):
		return empty
	if from == to:
		var trivial: Array[Vector2i] = [from]
		return trivial

	var came_from: Dictionary = {}
	var frontier: Array[Vector2i] = [from]
	came_from[from] = from
	var head: int = 0
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		if current == to:
			break
		for dir in DIRS:
			var next: Vector2i = current + dir
			if grid.is_walkable(next) and not came_from.has(next):
				came_from[next] = current
				frontier.append(next)

	if not came_from.has(to):
		return empty
	var path: Array[Vector2i] = [to]
	var cursor: Vector2i = to
	while cursor != from:
		cursor = came_from[cursor]
		path.push_front(cursor)
	return path
