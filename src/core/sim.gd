class_name UDSim
extends RefCounted
## Deterministic tick-based simulation (§7.2). All state is a pure function
## of (initial seed, player commands, tick count), so offline batch calculation
## and realtime progression share this exact code path (§7.1-4).
##
## 2026-07-15 redesign: dig -> cave exploration + turn-based combat. Idle
## auto-battle clears trash mobs stage by stage (tick()); a stage flagged
## as a boss gate halts advancement (trash still farms for exp/coins) until
## the player manually wins a turn-based boss fight (player commands
## start_boss_fight/resolve_boss_round/flee_boss_fight).

signal document_discovered(doc_id: String)
signal item_found(item_id: String)
signal companion_joined(companion_id: String)

var tick_count: int = 0
var inventory: Dictionary = {}  # resource id -> int ("gold" only, in practice)
var minions: Array[UDMinion] = []
var discovered_documents: Array[String] = []
## Daily anomaly (§5.4). Applied as an explicit state change so offline
## and realtime progression stay equivalent.
var daily_date_key: String = ""
var daily_anomaly_id: String = ""
var daily_effect: String = ""
## Treasure-chest collectibles owned: item id -> count. Items stack up
## to a per-rank cap (UD.ITEM_RANK_CAPS) so spares can feed the altar
## and the guild exchange. The candidate pool and rank map are injected
## like the enemy/stage DBs and not serialized.
var items: Dictionary = {}
var item_pool: Array[String] = []
var item_ranks: Dictionary = {}  # item id -> "Z".."D"
## Coins offered at the altar so far, +1 party attack (party_atk_bonus())
## per level.
var altar_level: int = 0
## Story companions who have joined (§ plan change: the protagonist
## starts alone; companions join as documents are discovered).
## Definitions are injected like the enemy/stage DBs, not serialized.
var companions: Array[String] = []
var companion_defs: Array = []  # [{ id, name_key, join_at_docs, base_hp, hp_per_level, ... }]
## Unlock conditions per document id (data/documents "conditions" field).
## Injected like the enemy/stage DBs and not serialized. A document whose
## conditions are unmet stays hidden until they hold (§7.3).
var doc_conditions: Dictionary = {}  # doc id -> { min_docs, requires_* }
## Shop purchases: id -> { "level": int, "effect": String }.
var upgrades: Dictionary = {}
var _rng := RandomNumberGenerator.new()

## --- Cave exploration + combat state ---------------------------------
var stage_index: int = 1
var enemy_id: String = ""
var enemy_hp: int = 0
## Shared party EXP bank, filled automatically by idle combat. Spent
## explicitly by the player (level_up_companion()) on whichever party
## member they choose — sidesteps "who fought"/kill-credit entirely.
var exp_pool: int = 0
var boss_active: bool = false
var boss_hp: int = 0
## Every trash + boss kill, ever. Monotonic (unlike exp_pool, which drains
## on level-ups) — UI uses it to scroll the cave backdrop as a sense of
## forward progress each time an enemy falls.
var total_kills: int = 0
## The shop's weapon shelf: a single equipped slot, not an inventory —
## buying a new weapon replaces whichever one you had (a classic "next
## tier" weapon shop, no separate equip step).
var equipped_weapon_id: String = ""
var weapon_level: int = 0
var stages: UDStageDB
var enemies: UDEnemyDB
var skills: UDSkillDB
var weapons: UDShopDB


static func new_game(
	p_enemies: UDEnemyDB,
	p_stages: UDStageDB,
	rng_seed: int,
	p_item_pool: Array[String] = [],
	p_companion_defs: Array = [],
	p_doc_conditions: Dictionary = {},
	p_item_ranks: Dictionary = {},
	p_skills: UDSkillDB = null,
	p_weapons: UDShopDB = null,
) -> UDSim:
	var sim := UDSim.new()
	sim.enemies = p_enemies
	sim.stages = p_stages
	sim.skills = p_skills if p_skills != null else UDSkillDB.from_dicts([])
	sim.weapons = p_weapons if p_weapons != null else UDShopDB.from_dicts([])
	sim.item_pool = p_item_pool
	sim.companion_defs = p_companion_defs
	sim.doc_conditions = p_doc_conditions
	sim.item_ranks = p_item_ranks
	sim._rng.seed = rng_seed
	sim.inventory[UD.RES_GOLD] = 0
	for i in UD.INITIAL_MINION_COUNT:
		sim.minions.append(sim._new_unit_at_level(i, 1))
	return sim


func advance(ticks: int) -> void:
	for i in ticks:
		tick()


func tick() -> void:
	tick_count += 1
	if not boss_active:
		_auto_battle()
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
			minions.append(_new_unit_at_level(minions.size(), 1))
			companion_joined.emit(id)


## --- Growth: per-unit stats computed from level, not stored ----------

## Which growth curve a party slot uses: the protagonist (slot 0) has a
## fixed curve in UD.*; companions (slot >= 1) use their own data file.
## Falls back to UD.FALLBACK_GROWTH if the slot has no matching def yet
## (should not normally happen).
func _growth_def_for_unit(unit: UDMinion) -> Dictionary:
	if unit.id == 0:
		return {
			"base_hp": UD.PROTAGONIST_BASE_HP, "hp_per_level": UD.PROTAGONIST_HP_PER_LEVEL,
			"base_mp": UD.PROTAGONIST_BASE_MP, "mp_per_level": UD.PROTAGONIST_MP_PER_LEVEL,
			"base_atk": UD.PROTAGONIST_BASE_ATK, "atk_per_level": UD.PROTAGONIST_ATK_PER_LEVEL,
			"base_def": UD.PROTAGONIST_BASE_DEF, "def_per_level": UD.PROTAGONIST_DEF_PER_LEVEL,
		}
	var companion_index := unit.id - 1
	if companion_index >= 0 and companion_index < companions.size():
		var companion_id := companions[companion_index]
		for def: Variant in companion_defs:
			if str((def as Dictionary)["id"]) == companion_id:
				return def as Dictionary
	return UD.FALLBACK_GROWTH


func unit_max_hp(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_hp"]) + (unit.level - 1) * int(g["hp_per_level"])


func unit_max_mp(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_mp"]) + (unit.level - 1) * int(g["mp_per_level"])


func unit_atk(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_atk"]) + (unit.level - 1) * int(g["atk_per_level"])


func unit_def(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_def"]) + (unit.level - 1) * int(g["def_per_level"])


func unit_skills(unit: UDMinion) -> Array[String]:
	var g := _growth_def_for_unit(unit)
	var known: Array[String] = []
	for id: Variant in g.get("skills", []) as Array:
		known.append(str(id))
	return known


func _new_unit_at_level(id: int, level: int) -> UDMinion:
	var unit := UDMinion.create(id, level, 1, 1)
	unit.hp = unit_max_hp(unit)
	unit.mp = unit_max_mp(unit)
	return unit


func _unit_by_id(unit_id: int) -> UDMinion:
	for unit in minions:
		if unit.id == unit_id:
			return unit
	return null


## Shared ledger bonuses (shop upgrades, altar, daily anomaly) added on
## top of every living unit's own level-derived ATK/DEF — same "base +
## upgrades + altar + daily" shape dig_power() used to have.
func party_atk_bonus() -> int:
	var bonus := 0
	if daily_effect == "atk_add":
		bonus += 1
	bonus += UDSim._effect_levels_in(upgrades, "atk_add")
	bonus += altar_level
	bonus += weapon_atk_bonus()
	return bonus


func weapon_atk_bonus() -> int:
	if equipped_weapon_id == "" or not weapons.has_good(equipped_weapon_id):
		return 0
	var def := weapons.get_good(equipped_weapon_id)
	return int(def["base_atk"]) + int(def["atk_per_level"]) * (weapon_level - 1)


func party_def_bonus() -> int:
	var bonus := 0
	if daily_effect == "def_add":
		bonus += 1
	bonus += UDSim._effect_levels_in(upgrades, "def_add")
	return bonus


func effective_atk(unit: UDMinion) -> int:
	return unit_atk(unit) + party_atk_bonus()


func effective_def(unit: UDMinion) -> int:
	return unit_def(unit) + party_def_bonus()


## Sum of every living party member's effective attack — the idle trash
## loop's damage-per-tick (deterministic, no rng).
func party_atk_total() -> int:
	var total := 0
	for unit in minions:
		if unit.hp > 0:
			total += effective_atk(unit)
	return total


## --- Idle auto-battle (tick-driven, risk-free trash combat) ----------

func _auto_battle() -> void:
	var stage := stages.stage_for_index(stage_index)
	if enemy_id == "":
		# Spawn only this tick: a freshly spawned enemy takes its first hit
		# next tick, so the idle view always has at least one tick to show
		# it at full HP instead of it dying invisibly the instant it appears
		# (which would otherwise happen for every enemy once party attack
		# outgrows its HP — an increasingly common case as the party levels).
		_spawn_trash(stage)
		return
	var def := enemies.get_enemy(enemy_id)
	enemy_hp -= maxi(1, party_atk_total() - int(def["def"]))
	if enemy_hp > 0:
		return  # Trash combat is risk-free by design: no party HP loss.
	_grant_kill_rewards(def, stage)
	enemy_id = ""
	if stages.is_boss_stage(stage_index):
		return  # Gate: halt here. Trash keeps farming exp/coins until the
		# player wins the manual boss fight (start_boss_fight/resolve_boss_round).
	stage_index += 1


func _spawn_trash(stage: Dictionary) -> void:
	var pool: Array = stage.get("trash_pool", [])
	if pool.is_empty():
		enemy_id = ""
		enemy_hp = 0
		return
	enemy_id = str(pool[_rng.randi_range(0, pool.size() - 1)])
	enemy_hp = int(enemies.get_enemy(enemy_id)["hp"])


func _grant_kill_rewards(def: Dictionary, stage: Dictionary) -> void:
	total_kills += 1
	exp_pool += int(def.get("exp", 0))
	inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + int(def.get("coins", 0))
	if daily_effect == "gold_per_kill":
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + 1
	_roll_document(stage)
	_roll_special_find()


## --- Manual boss fight (turn-based, player commands) -----------------

## Opens the boss encounter at the current gate. Only callable when the
## party is standing at an undefeated boss stage.
func start_boss_fight() -> bool:
	if boss_active:
		return false
	var stage := stages.stage_for_index(stage_index)
	var boss_id := str(stage.get("boss_id", ""))
	if boss_id == "":
		return false
	boss_active = true
	boss_hp = int(enemies.get_enemy(boss_id)["hp"])
	return true


## Leaves the boss encounter without resolving it (no penalty): the
## party returns to idle-farming trash at the gate.
func flee_boss_fight() -> bool:
	if not boss_active:
		return false
	boss_active = false
	boss_hp = 0
	return true


func _boss_def() -> Dictionary:
	var stage := stages.stage_for_index(stage_index)
	return enemies.get_enemy(str(stage["boss_id"]))


## Resolves exactly one round: every living unit's action (in order),
## then the boss's counter-attack on one target. `actions` is
## [{ "unit_id": int, "action": "attack"|"skill", "skill_id": String }],
## one entry per living unit (units without an entry simply do nothing
## this round). Always resolves atomically — no mid-round state to save.
func resolve_boss_round(actions: Array) -> Dictionary:
	if not boss_active:
		return {}
	var boss := _boss_def()
	for entry: Variant in actions:
		var action := entry as Dictionary
		var unit := _unit_by_id(int(action["unit_id"]))
		if unit == null or unit.hp <= 0:
			continue
		match str(action.get("action", "attack")):
			"attack":
				boss_hp -= maxi(1, effective_atk(unit) - int(boss["def"]))
			"skill":
				_apply_skill(unit, str(action.get("skill_id", "")))
	if boss_hp <= 0:
		_grant_kill_rewards(boss, stages.stage_for_index(stage_index))
		boss_active = false
		boss_hp = 0
		stage_index += 1
		return {"won": true, "lost": false}
	var target := _boss_target()
	if target != null:
		target.hp = maxi(0, target.hp - maxi(1, int(boss["atk"]) - effective_def(target)))
	if _party_wiped():
		boss_active = false
		boss_hp = 0
		_heal_party_full()
		return {"won": false, "lost": true}
	return {"won": false, "lost": false}


func _apply_skill(unit: UDMinion, skill_id: String) -> void:
	if not skills.has_skill(skill_id) or not unit_skills(unit).has(skill_id):
		return
	var skill := skills.get_skill(skill_id)
	var cost := int(skill.get("mp_cost", 0))
	if unit.mp < cost:
		return
	unit.mp -= cost
	var power := int(skill.get("power", 0))
	match str(skill.get("effect", "damage")):
		"damage":
			boss_hp -= maxi(1, power - int(_boss_def()["def"]))
		"heal":
			unit.hp = mini(unit_max_hp(unit), unit.hp + power)
		# buff_atk / buff_def intentionally left as a future extension —
		# no lasting per-encounter modifier state exists yet.


## Target for the boss's counter-attack: the lowest-HP living unit (reads
## as the boss "finishing off" whoever is most hurt).
func _boss_target() -> UDMinion:
	var target: UDMinion = null
	for unit in minions:
		if unit.hp <= 0:
			continue
		if target == null or unit.hp < target.hp:
			target = unit
	return target


func _party_wiped() -> bool:
	for unit in minions:
		if unit.hp > 0:
			return false
	return true


func _heal_party_full() -> void:
	for unit in minions:
		unit.hp = unit_max_hp(unit)
		unit.mp = unit_max_mp(unit)


## --- Leveling (player command: spends the shared exp_pool) -----------

static func exp_cost_for_level(level: int) -> int:
	return int(round(UD.EXP_BASE * pow(UD.EXP_MULT, level - 1)))


## Spends the banked exp_pool to raise one party member a level, fully
## healing them. Returns false when unaffordable or the unit is unknown.
func level_up_companion(unit_id: int) -> bool:
	var unit := _unit_by_id(unit_id)
	if unit == null:
		return false
	var cost := UDSim.exp_cost_for_level(unit.level)
	if exp_pool < cost:
		return false
	exp_pool -= cost
	unit.level += 1
	unit.hp = unit_max_hp(unit)
	unit.mp = unit_max_mp(unit)
	return true


## --- Daily anomaly -----------------------------------------------------

## Switches to the given day's anomaly. Returns false when that day is
## already active.
func apply_daily(date_key: String, anomaly: Dictionary) -> bool:
	if daily_date_key == date_key:
		return false
	daily_date_key = date_key
	daily_anomaly_id = str(anomaly.get("id", ""))
	daily_effect = str(anomaly.get("effect", ""))
	return true


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


## --- Weapon shop (buy replaces the equipped weapon; upgrade levels it) -

static func weapon_upgrade_cost(weapon: Dictionary, level: int) -> int:
	return int(round(
		float(weapon["upgrade_base_cost"]) * pow(float(weapon["upgrade_cost_mult"]), level)
	))


## Buying a weapon you don't already have equipped replaces the current
## one outright (fresh at level 1) — a shop shelf, not an inventory.
func buy_weapon(weapon_id: String) -> bool:
	if not weapons.has_good(weapon_id) or weapon_id == equipped_weapon_id:
		return false
	var def := weapons.get_good(weapon_id)
	var cost := int(def["buy_cost"])
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	equipped_weapon_id = weapon_id
	weapon_level = 1
	return true


## Levels up whichever weapon is currently equipped. False with nothing
## equipped, already maxed, or unaffordable.
func upgrade_weapon() -> bool:
	if equipped_weapon_id == "" or not weapons.has_good(equipped_weapon_id):
		return false
	var def := weapons.get_good(equipped_weapon_id)
	if weapon_level >= int(def["max_level"]):
		return false
	var cost := UDSim.weapon_upgrade_cost(def, weapon_level)
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	weapon_level += 1
	return true


## --- Item shop (coins <-> collection items, priced by rank) -----------

## False on an unknown item, a full rank cap, or unaffordable.
func buy_item(item_id: String) -> bool:
	if not item_ranks.has(item_id):
		return false
	if item_count(item_id) >= item_cap(item_id):
		return false
	var cost := int(UD.ITEM_BUY_COST_BY_RANK.get(item_rank(item_id), 0))
	if cost <= 0 or int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) - cost
	_add_item(item_id, 1)
	return true


## False when fewer than `count` are owned.
func sell_item(item_id: String, count: int = 1) -> bool:
	if count <= 0 or item_count(item_id) < count:
		return false
	var value := int(UD.ITEM_SELL_VALUE_BY_RANK.get(item_rank(item_id), 0))
	items[item_id] = item_count(item_id) - count
	inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + value * count
	return true


static func _effect_levels_in(entries: Dictionary, effect: String) -> int:
	var total := 0
	for id: Variant in entries.keys():
		var entry := entries[id] as Dictionary
		if str(entry.get("effect", "")) == effect:
			total += int(entry.get("level", 0))
	return total


## Extra document drop chance from the altar facility and the daily
## anomaly. The "survey" shop upgrade that used to grant this is retired
## (2026-07-15, shop redesign: pickaxe/survey folded into the weapon
## system and the altar) — its per-level bonus now rides altar_level
## instead, alongside altar's existing +1 atk/level (party_atk_bonus()).
## _effect_levels_in() still reads any doc_chance_add already banked in
## upgrades so a save with survey levels bought before the retirement
## keeps that bonus frozen rather than losing it outright.
func document_chance_bonus() -> float:
	var bonus := 0.0
	if daily_effect == "doc_chance_add":
		bonus += UD.DAILY_DOC_CHANCE_BONUS
	bonus += UDSim._effect_levels_in(upgrades, "doc_chance_add") * UD.UPGRADE_DOC_CHANCE
	bonus += float(altar_level) * UD.UPGRADE_DOC_CHANCE
	return bonus


func _roll_document(stage: Dictionary) -> void:
	var chance := float(stage.get("document_chance", 0.0))
	if chance > 0.0:
		chance += document_chance_bonus()
	if chance <= 0.0:
		return
	var roll := _rng.randf()
	var pool: Array = []
	for doc_id: Variant in stage.get("documents", []) as Array:
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


## Rare finds on enemy defeat: a chest always pays coins and also holds a
## random collection item still under its rank cap; a nugget pays far
## more than a normal kill.
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
## this-run attack (party_atk_bonus()). Player command: deterministic, no rng.

func altar_built() -> bool:
	return upgrade_level("altar") > 0


func guild_built() -> bool:
	return upgrade_level("tavern") > 0


func dorm_built() -> bool:
	return upgrade_level("dorm") > 0


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


## Offers coins (plus item_id when a rank is required) for +1 attack.
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


func to_dict() -> Dictionary:
	var minion_dicts: Array = []
	for minion in minions:
		minion_dicts.append(minion.to_dict())
	return {
		"version": UD.SAVE_VERSION,
		"tick_count": tick_count,
		# RNG seed/state are 64-bit; store as strings to survive JSON floats.
		"rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state),
		"inventory": inventory.duplicate(),
		"minions": minion_dicts,
		"discovered_documents": discovered_documents.duplicate(),
		"daily_date_key": daily_date_key,
		"daily_anomaly_id": daily_anomaly_id,
		"daily_effect": daily_effect,
		"items": items.duplicate(),
		"altar_level": altar_level,
		"companions": companions.duplicate(),
		"upgrades": upgrades.duplicate(true),
		"stage_index": stage_index,
		"enemy_id": enemy_id,
		"enemy_hp": enemy_hp,
		"exp_pool": exp_pool,
		"boss_active": boss_active,
		"boss_hp": boss_hp,
		"total_kills": total_kills,
		"equipped_weapon_id": equipped_weapon_id,
		"weapon_level": weapon_level,
	}


static func from_dict(
	d: Dictionary,
	p_enemies: UDEnemyDB,
	p_stages: UDStageDB,
	p_item_pool: Array[String] = [],
	p_companion_defs: Array = [],
	p_doc_conditions: Dictionary = {},
	p_item_ranks: Dictionary = {},
	p_skills: UDSkillDB = null,
	p_weapons: UDShopDB = null,
) -> UDSim:
	var sim := UDSim.new()
	sim.enemies = p_enemies
	sim.stages = p_stages
	sim.skills = p_skills if p_skills != null else UDSkillDB.from_dicts([])
	sim.weapons = p_weapons if p_weapons != null else UDShopDB.from_dicts([])
	sim.item_pool = p_item_pool
	sim.companion_defs = p_companion_defs
	sim.doc_conditions = p_doc_conditions
	sim.item_ranks = p_item_ranks
	sim.tick_count = int(d["tick_count"])
	sim._rng.seed = (d["rng_seed"] as String).to_int()
	sim._rng.state = (d["rng_state"] as String).to_int()
	for res: Variant in (d["inventory"] as Dictionary).keys():
		sim.inventory[res] = int(d["inventory"][res])
	for minion_dict: Variant in d["minions"] as Array:
		sim.minions.append(UDMinion.from_dict(minion_dict))
	for doc_id: Variant in d["discovered_documents"] as Array:
		sim.discovered_documents.append(doc_id)
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
	for id: Variant in (d.get("upgrades", {}) as Dictionary).keys():
		var entry := d["upgrades"][id] as Dictionary
		sim.upgrades[id] = {
			"level": int(entry.get("level", 0)),
			"effect": str(entry.get("effect", "")),
		}
	# v5 -> v6: altar/tavern/dorm stopped being placeable rooms and
	# became one-time facility unlocks that live in the same "upgrades"
	# ledger as shop purchases. A room built in the old save carries
	# its unlock straight over (same effect, level 1).
	for room_dict: Variant in d.get("rooms", []) as Array:
		var rd := room_dict as Dictionary
		var facility_id := str(rd.get("id", ""))
		if facility_id in ["altar", "tavern", "dorm"] and not sim.upgrades.has(facility_id):
			sim.upgrades[facility_id] = {"level": 1, "effect": str(rd.get("effect", ""))}
	# v3 -> v4: the minion crew becomes protagonist + story companions.
	# Rebuild the party; companions re-join on the next ticks from the
	# document count.
	if int(d.get("version", 1)) < 4:
		sim.minions.clear()
		sim.minions.append(sim._new_unit_at_level(0, 1))
		sim.companions.clear()
	# Companions whose definitions were removed (placeholder characters)
	# leave the party; the crew is rebuilt when the roster changed. Runs
	# whenever the save holds any companion — even if every definition was
	# removed (known_ids empty) — so a lingering one is pruned to solo.
	if not sim.companions.is_empty():
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
				sim.minions.append(sim._new_unit_at_level(i, 1))
	# v7 -> v8: the dig turned into cave exploration + combat, a
	# completely different core loop. The old grid/jobs/dig_policy have
	# no equivalent and are simply not read above; battle state starts
	# fresh at stage 1 while everything the player earned (coins, items,
	# documents, companions, upgrades, altar level) is preserved. Every
	# party unit resets to level 1 at full HP/MP (their old dig-era
	# dicts carried no level/hp/mp, so this also covers "no such key").
	if int(d.get("version", 1)) < 8:
		sim.stage_index = 1
		sim.enemy_id = ""
		sim.enemy_hp = 0
		sim.exp_pool = 0
		sim.boss_active = false
		sim.boss_hp = 0
		for unit in sim.minions:
			unit.level = 1
			unit.hp = sim.unit_max_hp(unit)
			unit.mp = sim.unit_max_mp(unit)
		# Bought upgrade levels are kept, but their "effect" string was
		# baked in at purchase time under the old dig-era names — rename
		# in place so e.g. an already-bought pickaxe level still does
		# something (atk) instead of silently becoming inert.
		const OLD_EFFECT_RENAMES := {
			"dig_power_add": "atk_add",
		}
		for id: Variant in sim.upgrades.keys():
			var entry := sim.upgrades[id] as Dictionary
			var old_effect := str(entry.get("effect", ""))
			if OLD_EFFECT_RENAMES.has(old_effect):
				entry["effect"] = OLD_EFFECT_RENAMES[old_effect]
	else:
		sim.stage_index = int(d.get("stage_index", 1))
		sim.enemy_id = str(d.get("enemy_id", ""))
		sim.enemy_hp = int(d.get("enemy_hp", 0))
		sim.exp_pool = int(d.get("exp_pool", 0))
		sim.boss_active = bool(d.get("boss_active", false))
		sim.boss_hp = int(d.get("boss_hp", 0))
		sim.total_kills = int(d.get("total_kills", 0))
		sim.equipped_weapon_id = str(d.get("equipped_weapon_id", ""))
		sim.weapon_level = int(d.get("weapon_level", 0))
	return sim
