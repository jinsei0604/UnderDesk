class_name UDJob
extends RefCounted
## A dig designation. Progress accumulates until the cell's hardness is met.

var target: Vector2i
var progress: int = 0
var claimed_by: int = -1  # minion id, -1 = unclaimed


static func create(p_target: Vector2i) -> UDJob:
	var job := UDJob.new()
	job.target = p_target
	return job


func to_dict() -> Dictionary:
	return {
		"target": [target.x, target.y],
		"progress": progress,
		"claimed_by": claimed_by,
	}


static func from_dict(d: Dictionary) -> UDJob:
	var job := UDJob.new()
	var t: Array = d["target"]
	job.target = Vector2i(int(t[0]), int(t[1]))
	job.progress = int(d["progress"])
	job.claimed_by = int(d["claimed_by"])
	return job
