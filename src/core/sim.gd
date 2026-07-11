class_name UDSim
extends RefCounted
## Deterministic tick-based simulation (§7.2). All state is a pure function
## of (initial seed, player commands, tick count), so offline batch calculation
## and realtime progression share this exact code path (§7.1-4).

signal document_discovered(doc_id: String)

var tick_count: int = 0
var grid: UDGrid
var strata: UDStrataDB
var inventory: Dictionary = {}  # resource id -> int
var minions: Array[UDMinion] = []
var jobs: Array[UDJob] = []
var rooms: Array[Dictionary] = []  # { "id": String, "pos": Vector2i }
var discovered_documents: Array[String] = []
var dig_policy: UD.DigPolicy = UD.DigPolicy.NONE
var _rng := RandomNumberGenerator.new()


static func new_game(p_strata: UDStrataDB, rng_seed: int) -> UDSim:
	var sim := UDSim.new()
	sim.strata = p_strata
	sim._rng.seed = rng_seed
	sim.grid = UDGrid.new(UD.GRID_WIDTH)
	for y in UD.GRID_INITIAL_HEIGHT:
		sim.grid.append_row(p_strata.terrain_for_depth(y))
	for res in UD.ALL_RESOURCES:
		sim.inventory[res] = 0
	for i in UD.INITIAL_MINION_COUNT:
		sim.minions.append(UDMinion.create(i, UD.DEPOT_POS))
	# Idle games should idle from minute one: new dungeons dig on their own.
	sim.dig_policy = UD.DigPolicy.DOWN
	return sim


func advance(ticks: int) -> void:
	for i in ticks:
		tick()


func tick() -> void:
	tick_count += 1
	_auto_designate()
	for minion in minions:
		_step_minion(minion)


## Generates dig jobs from the current policy so play continues unattended.
## Pure function of grid state -> deterministic across offline/realtime.
## Only workable jobs count toward the limit: stale designations on buried
## cells must not starve the policy.
func _auto_designate() -> void:
	if dig_policy == UD.DigPolicy.NONE:
		return
	var limit := minions.size()
	var active := 0
	for job in jobs:
		if _has_walkable_neighbor(job.target):
			active += 1
	if active >= limit:
		return
	for cell in _policy_candidates():
		if active >= limit:
			break
		if add_dig_job(cell):
			active += 1


func _has_walkable_neighbor(cell: Vector2i) -> bool:
	for dir in UDPathfinder.DIRS:
		if grid.is_walkable(cell + dir):
			return true
	return false


func _policy_candidates() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var deepest := deepest_air_row()
	if deepest < 0:
		return candidates
	_ensure_rows(deepest + UD.GRID_EXPAND_ROWS)
	match dig_policy:
		UD.DigPolicy.DOWN:
			# Layer order: fully clear the shallowest unfinished row before
			# descending, so no soil columns are left hanging beside the shaft.
			for y in range(1, grid.height):
				for x in grid.width:
					var cell := Vector2i(x, y)
					if grid.terrain_at(cell) != UD.Terrain.AIR:
						candidates.append(cell)
				if not candidates.is_empty():
					break
		UD.DigPolicy.WIDEN:
			for x in grid.width:
				var air := Vector2i(x, deepest)
				if not grid.is_walkable(air):
					continue
				for dx: int in [-1, 1]:
					var side := air + Vector2i(dx, 0)
					if grid.is_inside(side) and grid.terrain_at(side) != UD.Terrain.AIR:
						candidates.append(side)
	# Closest to the depot column first; ties resolve left-to-right.
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var da := absi(a.x - UD.DEPOT_POS.x)
			var db := absi(b.x - UD.DEPOT_POS.x)
			if da != db:
				return da < db
			return a.x < b.x
	)
	return candidates


## The digging front: deepest row with any open cell. Also used by the
## strip camera to follow the action.
func deepest_air_row() -> int:
	for y in range(grid.height - 1, -1, -1):
		for x in grid.width:
			if grid.is_walkable(Vector2i(x, y)):
				return y
	return -1


## Designates a cell for digging. Returns false when the cell is not diggable
## or already designated. Unreachable cells stay queued without penalty (§5.1).
func add_dig_job(target: Vector2i) -> bool:
	if not grid.is_inside(target):
		return false
	if grid.terrain_at(target) == UD.Terrain.AIR:
		return false
	for job in jobs:
		if job.target == target:
			return false
	jobs.append(UDJob.create(target))
	return true


## Cancels an unstarted designation. Jobs a minion is already walking to
## or digging stay (avoids stranding the minion mid-errand).
func remove_dig_job(target: Vector2i) -> bool:
	for job in jobs:
		if job.target == target and job.claimed_by == -1:
			jobs.erase(job)
			return true
	return false


## Builds a room whose footprint cells are all dug-out AIR. Deducts cost and
## applies its effect. Returns false when placement or cost is invalid.
func build_room(room_def: Dictionary, pos: Vector2i) -> bool:
	var footprint_w := int(room_def["width"])
	var footprint_h := int(room_def["height"])
	for dy in footprint_h:
		for dx in footprint_w:
			var cell := pos + Vector2i(dx, dy)
			if not grid.is_walkable(cell) or cell == UD.DEPOT_POS:
				return false
			if _room_at(cell) >= 0:
				return false
	var cost: Dictionary = room_def["cost"]
	for res: Variant in cost.keys():
		if int(inventory.get(res, 0)) < int(cost[res]):
			return false
	for res: Variant in cost.keys():
		inventory[res] = int(inventory[res]) - int(cost[res])
	rooms.append({
		"id": room_def["id"],
		"pos": pos,
		"effect": str(room_def.get("effect", "")),
	})
	_apply_room_effect(room_def)
	return true


func room_footprint(index: int, room_db: UDRoomDB) -> Rect2i:
	var room: Dictionary = rooms[index]
	var def := room_db.get_room(room["id"])
	return Rect2i(room["pos"], Vector2i(int(def["width"]), int(def["height"])))


func _room_at(cell: Vector2i) -> int:
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		# MVP rooms are small; compare against stored origin plus max footprint 2x1.
		var origin: Vector2i = room["pos"]
		if cell == origin or cell == origin + Vector2i(1, 0):
			return i
	return -1


func _apply_room_effect(room_def: Dictionary) -> void:
	var effect: String = room_def.get("effect", "")
	if effect == "minion_add" and minions.size() < UD.MINION_MAX:
		minions.append(UDMinion.create(minions.size(), UD.DEPOT_POS))


## Base power plus one for each built room with a dig_power_add effect
## (e.g. the tavern). Effects are recorded on the room entry at build time.
func dig_power() -> int:
	var power := UD.MINION_DIG_POWER
	for room in rooms:
		if str(room.get("effect", "")) == "dig_power_add":
			power += 1
	return power


func _step_minion(minion: UDMinion) -> void:
	match minion.state:
		UDMinion.State.IDLE:
			_try_claim_job(minion)
		UDMinion.State.MOVING:
			if not minion.path.is_empty():
				minion.pos = minion.path.pop_front()
			if minion.path.is_empty():
				minion.state = UDMinion.State.DIGGING
		UDMinion.State.DIGGING:
			_dig(minion)
		UDMinion.State.HAULING:
			if not minion.path.is_empty():
				minion.pos = minion.path.pop_front()
			if minion.path.is_empty():
				_deposit(minion)


func _try_claim_job(minion: UDMinion) -> void:
	for job in jobs:
		if job.claimed_by != -1:
			continue
		var best_path: Array[Vector2i] = []
		for dir in UDPathfinder.DIRS:
			var stand_cell: Vector2i = job.target + dir
			if not grid.is_walkable(stand_cell):
				continue
			var candidate := UDPathfinder.find_path(grid, minion.pos, stand_cell)
			if candidate.is_empty():
				continue
			if best_path.is_empty() or candidate.size() < best_path.size():
				best_path = candidate
		if best_path.is_empty():
			continue
		job.claimed_by = minion.id
		minion.job_target = job.target
		minion.path = best_path.slice(1)
		minion.state = UDMinion.State.MOVING
		return


func _dig(minion: UDMinion) -> void:
	var job := _job_for_target(minion.job_target)
	if job == null:
		minion.job_target = UDMinion.NO_TARGET
		minion.state = UDMinion.State.IDLE
		return
	job.progress += dig_power()
	if job.progress < strata.hardness_for_depth(job.target.y):
		return
	# Dig complete: open the cell, collect yield, roll for a document.
	grid.set_terrain(job.target, UD.Terrain.AIR)
	var stratum := strata.stratum_for_depth(job.target.y)
	minion.carrying = stratum["yield"]
	_roll_document(stratum)
	jobs.erase(job)
	minion.job_target = UDMinion.NO_TARGET
	_ensure_rows(job.target.y + UD.GRID_EXPAND_ROWS)
	minion.path.clear()
	var home := UDPathfinder.find_path(grid, minion.pos, UD.DEPOT_POS)
	if home.size() > 1:
		minion.path = home.slice(1)
	minion.state = UDMinion.State.HAULING


func _deposit(minion: UDMinion) -> void:
	if minion.carrying != "":
		inventory[minion.carrying] = int(inventory.get(minion.carrying, 0)) + 1
		minion.carrying = ""
	minion.state = UDMinion.State.IDLE


## Extra document drop chance from built altars.
func document_chance_bonus() -> float:
	var bonus := 0.0
	for room in rooms:
		if str(room.get("effect", "")) == "doc_chance_add":
			bonus += UD.DOC_CHANCE_PER_ALTAR
	return bonus


func _roll_document(stratum: Dictionary) -> void:
	var chance := float(stratum.get("document_chance", 0.0))
	if chance > 0.0:
		chance += document_chance_bonus()
	if chance <= 0.0:
		return
	var roll := _rng.randf()
	var pool: Array = []
	for doc_id: Variant in stratum.get("documents", []) as Array:
		if not discovered_documents.has(doc_id):
			pool.append(doc_id)
	if roll >= chance or pool.is_empty():
		return
	var doc_id: String = pool[_rng.randi_range(0, pool.size() - 1)]
	discovered_documents.append(doc_id)
	document_discovered.emit(doc_id)


func _job_for_target(target: Vector2i) -> UDJob:
	for job in jobs:
		if job.target == target:
			return job
	return null


func _ensure_rows(depth: int) -> void:
	while grid.height <= depth:
		grid.append_row(strata.terrain_for_depth(grid.height))


func to_dict() -> Dictionary:
	var minion_dicts: Array = []
	for minion in minions:
		minion_dicts.append(minion.to_dict())
	var job_dicts: Array = []
	for job in jobs:
		job_dicts.append(job.to_dict())
	var room_dicts: Array = []
	for room in rooms:
		var origin: Vector2i = room["pos"]
		room_dicts.append({
			"id": room["id"],
			"pos": [origin.x, origin.y],
			"effect": str(room.get("effect", "")),
		})
	return {
		"version": UD.SAVE_VERSION,
		"tick_count": tick_count,
		# RNG seed/state are 64-bit; store as strings to survive JSON floats.
		"rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state),
		"grid": grid.to_dict(),
		"inventory": inventory.duplicate(),
		"minions": minion_dicts,
		"jobs": job_dicts,
		"rooms": room_dicts,
		"discovered_documents": discovered_documents.duplicate(),
		"dig_policy": int(dig_policy),
	}


static func from_dict(d: Dictionary, p_strata: UDStrataDB) -> UDSim:
	var sim := UDSim.new()
	sim.strata = p_strata
	sim.tick_count = int(d["tick_count"])
	sim._rng.seed = (d["rng_seed"] as String).to_int()
	sim._rng.state = (d["rng_state"] as String).to_int()
	sim.grid = UDGrid.from_dict(d["grid"])
	for res: Variant in (d["inventory"] as Dictionary).keys():
		sim.inventory[res] = int(d["inventory"][res])
	for minion_dict: Variant in d["minions"] as Array:
		sim.minions.append(UDMinion.from_dict(minion_dict))
	for job_dict: Variant in d["jobs"] as Array:
		sim.jobs.append(UDJob.from_dict(job_dict))
	for room_dict: Variant in d["rooms"] as Array:
		var rd := room_dict as Dictionary
		var p: Array = rd["pos"]
		sim.rooms.append({
			"id": rd["id"],
			"pos": Vector2i(int(p[0]), int(p[1])),
			"effect": str(rd.get("effect", "")),
		})
	for doc_id: Variant in d["discovered_documents"] as Array:
		sim.discovered_documents.append(doc_id)
	# Missing in pre-policy saves: default to NONE.
	sim.dig_policy = int(d.get("dig_policy", 0)) as UD.DigPolicy
	return sim
