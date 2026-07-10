class_name UDMinion
extends RefCounted
## A worker unit. Moves one cell per tick; digs, then hauls yield to the depot.

enum State { IDLE = 0, MOVING = 1, DIGGING = 2, HAULING = 3 }

const NO_TARGET := Vector2i(-1, -1)

var id: int
var display_name: String
var pos: Vector2i
var state: State = State.IDLE
var path: Array[Vector2i] = []
var job_target: Vector2i = NO_TARGET
var carrying: String = ""


static func create(p_id: int, p_pos: Vector2i) -> UDMinion:
	var minion := UDMinion.new()
	minion.id = p_id
	minion.display_name = UD.MINION_NAMES[p_id % UD.MINION_NAMES.size()]
	minion.pos = p_pos
	return minion


func to_dict() -> Dictionary:
	var path_arrays: Array = []
	for cell in path:
		path_arrays.append([cell.x, cell.y])
	return {
		"id": id,
		"display_name": display_name,
		"pos": [pos.x, pos.y],
		"state": int(state),
		"path": path_arrays,
		"job_target": [job_target.x, job_target.y],
		"carrying": carrying,
	}


static func from_dict(d: Dictionary) -> UDMinion:
	var minion := UDMinion.new()
	minion.id = int(d["id"])
	minion.display_name = d["display_name"]
	var p: Array = d["pos"]
	minion.pos = Vector2i(int(p[0]), int(p[1]))
	minion.state = int(d["state"]) as State
	var restored: Array[Vector2i] = []
	for cell: Variant in d["path"] as Array:
		var c: Array = cell
		restored.append(Vector2i(int(c[0]), int(c[1])))
	minion.path = restored
	var jt: Array = d["job_target"]
	minion.job_target = Vector2i(int(jt[0]), int(jt[1]))
	minion.carrying = d["carrying"]
	return minion
