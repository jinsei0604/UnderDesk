class_name UDSim
extends RefCounted
## Deterministic tick-based simulation (§7.2). All state is a pure function
## of (initial seed, player commands, tick count), so offline batch calculation
## and realtime progression share this exact code path (§7.1-4).

signal document_discovered(doc_id: String)
signal item_found(item_id: String)
signal companion_joined(companion_id: String)

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
## Treasure-chest collectibles owned: item id -> count. Items stack up
## to a per-rank cap (UD.ITEM_RANK_CAPS) so spares can feed the altar
## and the guild exchange. The candidate pool and rank map are injected
## like the strata DB and not serialized.
var items: Dictionary = {}
var item_pool: Array[String] = []
var item_ranks: Dictionary = {}  # item id -> "Z".."D"
## Coins offered at the altar so far, +1 dig power per level.
var altar_level: int = 0
## Story companions who have joined (§ plan change: the protagonist
## starts alone; companions join as documents are discovered).
## Definitions are injected like the strata DB, not serialized.
var companions: Array[String] = []
var companion_defs: Array = []  # [{ id, name_key, join_at_docs }]
## Unlock conditions per document id (data/documents "conditions" field).
## Injected like the strata DB and not serialized. A document whose
## conditions are unmet stays underground until they hold (§7.3).
var doc_conditions: Dictionary = {}  # doc id -> { min_docs, requires_* }
## Loot dug up but not yet tallied: resource id -> count. Filled on the
## spot when a dig completes (no hauling trips); converted to coins in
## one batch by collect_loot() when the player checks in.
var pending_loot: Dictionary = {}
## Shop purchases: id -> { "level": int, "effect": String }.
var upgrades: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func new_game(
	p_strata: UDStrataDB,
	rng_seed: int,
	p_item_pool: Array[String] = [],
	p_companion_defs: Array = [],
	p_doc_conditions: Dictionary = {},
	p_item_ranks: Dictionary = {},
) -> UDSim:
	var sim := UDSim.new()
	sim.strata = p_strata
	sim.item_pool = p_item_pool
	sim.companion_defs = p_companion_defs
	sim.doc_conditions = p_doc_conditions
	sim.item_ranks = p_item_ranks
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
	_check_companion_joins()


## Story progression: companions join when enough documents have been
## unearthed (thresholds live in data/companions/).
func _check_companion_joins() -> void:
	for def: Variant in companion_defs:
		var companion := def as Dictionary
		var id := str(companion["id"])
		if companions.has(id) or minions.size() >= UD.MINION_MAX:
			continue
		if discovered_documents.size() >= int(companion["join_at_docs"]):
			companions.append(id)
			minions.append(UDMinion.create(minions.size(), UD.DEPOT_POS))
			companion_joined.emit(id)


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
			# Serpentine tunnel: odd rows dig left-to-right, even rows dig
			# back right-to-left, dropping one row at each end. Progress
			# reads as horizontal tunnelling (per the reference image)
			# while depth still advances through the strata.
			for y in range(1, grid.height):
				var xs: Array[int] = []
				if y % 2 == 1:
					for x in grid.width:
						xs.append(x)
				else:
					for x in range(grid.width - 1, -1, -1):
						xs.append(x)
				for x in xs:
					var cell := Vector2i(x, y)
					if grid.terrain_at(cell) != UD.Terrain.AIR:
						candidates.append(cell)
						if candidates.size() >= UD.MINION_MAX:
							return candidates
				if not candidates.is_empty():
					return candidates
		UD.DigPolicy.WIDEN:
			for x in grid.width:
				var air := Vector2i(x, deepest)
				if not grid.is_walkable(air):
					continue
				for dx: int in [-1, 1]:
					var side := air + Vector2i(dx, 0)
					if grid.is_inside(side) and grid.terrain_at(side) != UD.Terrain.AIR:
						candidates.append(side)
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


## Base power plus one for each built room with a dig_power_add effect
## (e.g. the tavern). Effects are recorded on the room entry at build time.
func dig_power() -> int:
	var power := UD.MINION_DIG_POWER
	for room in rooms:
		if str(room.get("effect", "")) == "dig_power_add":
			power += 1
	if daily_effect == "dig_power_add":
		power += 1
	power += UDSim._effect_levels_in(upgrades, "dig_power_add")
	power += altar_level
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


func upgrade_level(id: String) -> int:
	if not upgrades.has(id):
		return 0
	return int((upgrades[id] as Dictionary).get("level", 0))


static func upgrade_cost(good: Dictionary, level: int) -> int:
	return int(round(float(good["base_cost"]) * pow(float(good["cost_mult"]), level)))


## Buys one level of a shop good. Returns false when maxed or unaffordable.
func buy_upgrade(good: Dictionary) -> bool:
	var id := str(good["id"])
	var level := upgrade_level(id)
	if level >= int(good["max_level"]):
		return false
	var cost := UDSim.upgrade_cost(good, level)
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	var effect := str(good.get("effect", ""))
	upgrades[id] = {"level": level + 1, "effect": effect}
	return true


static func _effect_levels_in(entries: Dictionary, effect: String) -> int:
	var total := 0
	for id: Variant in entries.keys():
		var entry := entries[id] as Dictionary
		if str(entry.get("effect", "")) == effect:
			total += int(entry.get("level", 0))
	return total


## Extra document drop chance from built altars and the daily anomaly.
func document_chance_bonus() -> float:
	var bonus := 0.0
	for room in rooms:
		if str(room.get("effect", "")) == "doc_chance_add":
			bonus += UD.DOC_CHANCE_PER_ALTAR
	if daily_effect == "doc_chance_add":
		bonus += UD.DAILY_DOC_CHANCE_BONUS
	bonus += UDSim._effect_levels_in(upgrades, "doc_chance_add") * UD.UPGRADE_DOC_CHANCE
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
		if not discovered_documents.has(doc_id) and _doc_unlocked(str(doc_id)):
			pool.append(doc_id)
	if roll >= chance or pool.is_empty():
		return
	var doc_id: String = pool[_rng.randi_range(0, pool.size() - 1)]
	discovered_documents.append(doc_id)
	document_discovered.emit(doc_id)


## True when every unlock condition on the document holds. Conditions are
## a pure function of sim state, so gating stays deterministic and
## offline-equivalent. Documents without conditions are always available.
func _doc_unlocked(doc_id: String) -> bool:
	if not doc_conditions.has(doc_id):
		return true
	var cond := doc_conditions[doc_id] as Dictionary
	if discovered_documents.size() < int(cond.get("min_docs", 0)):
		return false
	for companion_id: Variant in cond.get("requires_companions", []) as Array:
		if not companions.has(str(companion_id)):
			return false
	for item_id: Variant in cond.get("requires_items", []) as Array:
		if item_count(str(item_id)) <= 0:
			return false
	return true


func item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))


func item_rank(item_id: String) -> String:
	return str(item_ranks.get(item_id, UD.ITEM_DEFAULT_RANK))


func item_cap(item_id: String) -> int:
	return int(UD.ITEM_RANK_CAPS.get(item_rank(item_id), 0))


## Distinct collectibles owned at least once (collection progress).
func distinct_items() -> int:
	var total := 0
	for item_id: Variant in items.keys():
		if int(items[item_id]) > 0:
			total += 1
	return total


func _add_item(item_id: String, amount: int) -> void:
	items[item_id] = mini(item_count(item_id) + amount, item_cap(item_id))


## Rare finds on dig completion: a chest always pays coins and also
## holds a random collection item that is still under its rank cap;
## a nugget pays far more than any hauled resource.
func _roll_special_find() -> void:
	var roll := _rng.randf()
	if roll < UD.CHEST_CHANCE:
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + UD.CHEST_COINS
		var pool: Array[String] = []
		for item_id in item_pool:
			if item_count(item_id) < item_cap(item_id):
				pool.append(item_id)
		if not pool.is_empty():
			var item_id: String = pool[_rng.randi_range(0, pool.size() - 1)]
			_add_item(item_id, 1)
			item_found.emit(item_id)
	elif roll < UD.CHEST_CHANCE + UD.NUGGET_CHANCE:
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + UD.NUGGET_COINS


## --- Altar offerings -----------------------------------------------
## Coins (and, at higher levels, a collection item) buy permanent-for-
## this-run dig power. Player command: deterministic, no rng.

func altar_built() -> bool:
	for room in rooms:
		if str(room["id"]) == "altar":
			return true
	return false


func altar_offer_cost() -> int:
	return int(round(
		UD.ALTAR_OFFER_BASE_COST * pow(UD.ALTAR_OFFER_COST_MULT, altar_level)
	))


## Rank of the item the NEXT offering consumes ("" while coins suffice).
func altar_required_item_rank() -> String:
	var next_level := altar_level + 1
	var required := ""
	var best_tier := -1
	for tier: Variant in UD.ALTAR_ITEM_RANK_TIERS.keys():
		if next_level >= int(tier) and int(tier) > best_tier:
			best_tier = int(tier)
			required = str(UD.ALTAR_ITEM_RANK_TIERS[tier])
	return required


## Offers coins (plus item_id when a rank is required) for +1 dig power.
func offer_at_altar(item_id: String = "") -> bool:
	if not altar_built():
		return false
	var cost := altar_offer_cost()
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	var required_rank := altar_required_item_rank()
	if required_rank != "":
		if item_id == "" or item_count(item_id) <= 0:
			return false
		if item_rank(item_id) != required_rank:
			return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	if required_rank != "":
		items[item_id] = item_count(item_id) - 1
	altar_level += 1
	return true


## --- Guild exchange --------------------------------------------------
## Receiving one item of rank R consumes UD.ITEM_EXCHANGE_COSTS[R] items
## of the rank directly below (Z←S×3, S←A×5, A←B×7, B←C×10). C/D rank
## items cannot be exchanged for — they come out of chests. The consume
## map is chosen by the caller (UI/network layer); the sim only enforces
## the rules, so the same command serves local and future Steam trades.

func rank_below(rank: String) -> String:
	var index := UD.ITEM_RANKS.find(rank)
	if index < 0 or index + 1 >= UD.ITEM_RANKS.size():
		return ""
	return UD.ITEM_RANKS[index + 1]


func exchange_item(target_id: String, consume: Dictionary) -> bool:
	if not item_pool.has(target_id):
		return false
	var target_rank := item_rank(target_id)
	if not UD.ITEM_EXCHANGE_COSTS.has(target_rank):
		return false
	if item_count(target_id) >= item_cap(target_id):
		return false
	var required := int(UD.ITEM_EXCHANGE_COSTS[target_rank])
	var fodder_rank := rank_below(target_rank)
	var offered := 0
	for consume_id: Variant in consume.keys():
		var id := str(consume_id)
		var count := int(consume[consume_id])
		if count <= 0 or id == target_id:
			return false
		if item_rank(id) != fodder_rank:
			return false
		if item_count(id) < count:
			return false
		offered += count
	if offered != required:
		return false
	for consume_id: Variant in consume.keys():
		var id := str(consume_id)
		items[id] = item_count(id) - int(consume[consume_id])
	_add_item(target_id, 1)
	return true


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
		"altar_level": altar_level,
		"companions": companions.duplicate(),
		"pending_loot": pending_loot.duplicate(),
		"upgrades": upgrades.duplicate(true),
	}


static func from_dict(
	d: Dictionary,
	p_strata: UDStrataDB,
	p_item_pool: Array[String] = [],
	p_companion_defs: Array = [],
	p_doc_conditions: Dictionary = {},
	p_item_ranks: Dictionary = {},
) -> UDSim:
	var sim := UDSim.new()
	sim.strata = p_strata
	sim.item_pool = p_item_pool
	sim.companion_defs = p_companion_defs
	sim.doc_conditions = p_doc_conditions
	sim.item_ranks = p_item_ranks
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
	# v4 -> v5: the collection became stackable. Old saves hold a plain
	# id array (one of each); new saves hold id -> count.
	var saved_items: Variant = d.get("items", {})
	if saved_items is Array:
		for item_id: Variant in saved_items as Array:
			sim.items[str(item_id)] = 1
	else:
		for item_id: Variant in (saved_items as Dictionary).keys():
			sim.items[str(item_id)] = int((saved_items as Dictionary)[item_id])
	sim.altar_level = int(d.get("altar_level", 0))
	for companion_id: Variant in d.get("companions", []) as Array:
		sim.companions.append(str(companion_id))
	for res: Variant in (d.get("pending_loot", {}) as Dictionary).keys():
		sim.pending_loot[res] = int(d["pending_loot"][res])
	for id: Variant in (d.get("upgrades", {}) as Dictionary).keys():
		var entry := d["upgrades"][id] as Dictionary
		sim.upgrades[id] = {
			"level": int(entry.get("level", 0)),
			"effect": str(entry.get("effect", "")),
		}
	# v3 -> v4: the minion crew becomes protagonist + story companions.
	# Rebuild the party and release job claims held by removed workers;
	# companions re-join on the next ticks from the document count.
	if int(d.get("version", 1)) < 4:
		sim.minions.clear()
		sim.minions.append(UDMinion.create(0, UD.DEPOT_POS))
		sim.companions.clear()
		for job in sim.jobs:
			job.claimed_by = -1
			job.progress = 0
	# Companions whose definitions were removed (placeholder characters)
	# leave the party; the crew is rebuilt when the roster changed.
	if not p_companion_defs.is_empty():
		var known_ids: Array[String] = []
		for def: Variant in p_companion_defs:
			known_ids.append(str((def as Dictionary)["id"]))
		var kept: Array[String] = []
		for companion_id in sim.companions:
			if known_ids.has(companion_id):
				kept.append(companion_id)
		if kept.size() != sim.companions.size() \
				or sim.minions.size() != kept.size() + 1:
			sim.companions = kept
			sim.minions.clear()
			for i in kept.size() + 1:
				sim.minions.append(UDMinion.create(i, UD.DEPOT_POS))
			for job in sim.jobs:
				job.claimed_by = -1
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
