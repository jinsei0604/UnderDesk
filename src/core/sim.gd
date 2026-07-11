class_name UDSim
extends RefCounted
## Deterministic tick-based simulation (§7.2). All state is a pure function
## of (initial seed, player commands, tick count), so offline batch calculation
## and realtime progression share this exact code path (§7.1-4).

signal document_discovered(doc_id: String)
signal item_found(item_id: String)

var tick_count: int = 0
var grid: UDGrid
var strata: UDStrataDB
var inventory: Dictionary = {}  # resource id -> int
var minions: Array[UDMinion] = []
var jobs: Array[UDJob] = []
var rooms: Array[Dictionary] = []  # { "id": String, "pos": Vector2i }
var discovered_documents: Array[String] = []
var dig_policy: UD.DigPolicy = UD.DigPolicy.NONE
## Daily anomaly (§5.4). Applied as an explicit state change so offline
## and realtime progression stay equivalent.
var daily_date_key: String = ""
var daily_anomaly_id: String = ""
var daily_effect: String = ""
## Treasure-chest collectibles owned. The candidate pool is injected
## like the strata DB and not serialized.
var items: Array[String] = []
var item_pool: Array[String] = []
## Loot dug up but not yet tallied: resource id -> count. Filled on the
## spot when a dig completes (no hauling trips); converted to coins in
## one batch by collect_loot() when the player checks in.
var pending_loot: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func new_game(
	p_strata: UDStrataDB, rng_seed: int, p_item_pool: Array[String] = []
) -> UDSim:
	var sim := UDSim.new()
	sim.strata = p_strata
	sim.item_pool = p_item_pool
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


## Switches to the given day's anomaly. Returns false when that day is
## already active.
func apply_daily(date_key: String, anomaly: Dictionary) -> bool:
	if daily_date_key == date_key:
		return false
	daily_date_key = date_key
	daily_anomaly_id = str(anomaly.get("id", ""))
	daily_effect = str(anomaly.get("effect", ""))
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
	if daily_effect == "dig_power_add":
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
			# Legacy state from pre-v3 saves; normalized away on load.
			minion.state = UDMinion.State.IDLE


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
	# Dig complete: open the cell, bag the yield on the spot, roll for
	# a document. The minion moves straight on to its next job.
	grid.set_terrain(job.target, UD.Terrain.AIR)
	var stratum := strata.stratum_for_depth(job.target.y)
	var yield_res: String = stratum["yield"]
	pending_loot[yield_res] = int(pending_loot.get(yield_res, 0)) + 1
	if daily_effect == "gold_per_dig":
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + 1
	_roll_document(stratum)
	_roll_special_find()
	jobs.erase(job)
	minion.job_target = UDMinion.NO_TARGET
	_ensure_rows(job.target.y + UD.GRID_EXPAND_ROWS)
	minion.path.clear()
	minion.state = UDMinion.State.IDLE


## Tallies all pending loot into coins in one batch (player check-in).
## Returns { "coins": int, "counts": Dictionary } for the UI report.
func collect_loot() -> Dictionary:
	var coins := 0
	var counts: Dictionary = {}
	for res: Variant in pending_loot.keys():
		var count := int(pending_loot[res])
		if count <= 0:
			continue
		counts[res] = count
		coins += count * int(UD.COIN_VALUES.get(res, 1))
	pending_loot.clear()
	if coins > 0:
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + coins
	return {"coins": coins, "counts": counts}


func pending_loot_total() -> int:
	var total := 0
	for res: Variant in pending_loot.keys():
		total += int(pending_loot[res])
	return total


## Extra document drop chance from built altars and the daily anomaly.
func document_chance_bonus() -> float:
	var bonus := 0.0
	for room in rooms:
		if str(room.get("effect", "")) == "doc_chance_add":
			bonus += UD.DOC_CHANCE_PER_ALTAR
	if daily_effect == "doc_chance_add":
		bonus += UD.DAILY_DOC_CHANCE_BONUS
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


## Rare finds on dig completion: a chest always pays coins and also
## holds a random unowned collection item while any remain; a nugget
## pays far more than any hauled resource.
func _roll_special_find() -> void:
	var roll := _rng.randf()
	if roll < UD.CHEST_CHANCE:
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + UD.CHEST_COINS
		var pool: Array[String] = []
		for item_id in item_pool:
			if not items.has(item_id):
				pool.append(item_id)
		if not pool.is_empty():
			var item_id: String = pool[_rng.randi_range(0, pool.size() - 1)]
			items.append(item_id)
			item_found.emit(item_id)
	elif roll < UD.CHEST_CHANCE + UD.NUGGET_CHANCE:
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + UD.NUGGET_COINS


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
		"daily_date_key": daily_date_key,
		"daily_anomaly_id": daily_anomaly_id,
		"daily_effect": daily_effect,
		"items": items.duplicate(),
		"pending_loot": pending_loot.duplicate(),
	}


static func from_dict(
	d: Dictionary, p_strata: UDStrataDB, p_item_pool: Array[String] = []
) -> UDSim:
	var sim := UDSim.new()
	sim.strata = p_strata
	sim.item_pool = p_item_pool
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
	sim.daily_date_key = str(d.get("daily_date_key", ""))
	sim.daily_anomaly_id = str(d.get("daily_anomaly_id", ""))
	sim.daily_effect = str(d.get("daily_effect", ""))
	for item_id: Variant in d.get("items", []) as Array:
		sim.items.append(str(item_id))
	for res: Variant in (d.get("pending_loot", {}) as Dictionary).keys():
		sim.pending_loot[res] = int(d["pending_loot"][res])
	# Pre-v3 saves may hold minions mid-haul: bag their load and free them.
	for minion in sim.minions:
		if minion.state == UDMinion.State.HAULING or minion.carrying != "":
			if minion.carrying != "":
				sim.pending_loot[minion.carrying] = \
					int(sim.pending_loot.get(minion.carrying, 0)) + 1
				minion.carrying = ""
			minion.path.clear()
			minion.state = UDMinion.State.IDLE
	# v1 -> v2 migration (§12-7): stockpiled raw resources become coins.
	if int(d.get("version", 1)) < 2:
		for res: String in UD.ALL_RESOURCES:
			if res == UD.RES_GOLD:
				continue
			var count := int(sim.inventory.get(res, 0))
			if count > 0:
				sim.inventory[UD.RES_GOLD] = int(sim.inventory.get(UD.RES_GOLD, 0)) \
					+ count * int(UD.COIN_VALUES.get(res, 1))
				sim.inventory[res] = 0
	return sim
