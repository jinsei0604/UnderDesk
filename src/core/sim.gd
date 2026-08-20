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
##
## 2026-08-18 「新企画v1」フェーズ0/1: 段階加入(join_at_docs)を廃止し、party
## は new_game() の時点で主人公+全companion_defsが揃う。ボス戦にREWIND
## (§10)と部位破壊(§8)を追加: start_boss_fight()が突入直前のスナップ
## ショット(boss_checkpoint)を取り、全滅または任意コマンドで
## rewind_boss_fight()がそこへ戻す。boss_intel(§12: 見た攻撃/破壊した
## 部位)だけはREWINDの対象外で、セーブを跨いで残る「プレイヤーの知識」。

signal document_discovered(doc_id: String)
signal item_found(item_id: String)

var tick_count: int = 0
var inventory: Dictionary = {}  # resource id -> int ("gold" only, in practice)
var minions: Array[UDMinion] = []
var discovered_documents: Array[String] = []
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
## Every story companion, present from turn one (新企画v1 §1, 2026-08-18:
## the staged join-by-document-count system is gone — new_game() fills
## this from every def in companion_defs immediately). Order determines
## party slot: minions[i+1] corresponds to companions[i].
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
## Which enemy the active boss fight is against. Needed because a fight
## is no longer always "the current band's boss": a cleared gate can be
## re-challenged from any later stage, where the current band has no
## boss_id of its own.
var boss_enemy_id: String = ""
## --- REWIND + body-part destruction (新企画v1 §8/§10, 2026-08-18) -----
## Snapshot captured once by start_boss_fight() (party HP/SP, boss_hp,
## boss_part_hp, RNG state) and restored verbatim by rewind_boss_fight().
## Empty outside of a boss fight.
var boss_checkpoint: Dictionary = {}
## Remaining HP of each of the active boss's body parts (data/enemies'
## optional "parts" array), part id -> int. Empty for a boss with no
## parts data — such a boss works exactly as it did before this system.
var boss_part_hp: Dictionary = {}
## Part ids reduced to 0 HP this attempt. Destroying a part only takes
## it out of boss_hp's separate main pool indirectly (via the boss's own
## action list honoring requires_part_intact, see _boss_choose_action) —
## a part's own HP is a distinct pool from boss_hp, never subtracted
## from it. Reset to [] by rewind_boss_fight(); see boss_intel below for
## what persists through a rewind instead.
var boss_parts_destroyed: Array[String] = []
## What the player has learned about a boss so far this save (新企画v1
## §12): boss id -> {"attacks_seen": Array[String], "parts_destroyed_
## seen": Array[String]}. Deliberately NOT part of boss_checkpoint — the
## one thing REWIND does not undo.
var boss_intel: Dictionary = {}
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
	# 新企画v1 §1: 全5人が最初から仲間 — 段階加入(join_at_docs)は廃止。
	# companions は起動時に注入された companion_defs の並び順そのまま
	# (companion_1..4 = 円/ヴァルド/司馬燿/サユ)、party slot 0 が主人公。
	for def: Variant in p_companion_defs:
		sim.companions.append(str((def as Dictionary)["id"]))
	for i in sim.companions.size() + 1:
		sim.minions.append(sim._new_unit_at_level(i, 1))
	return sim


func advance(ticks: int) -> void:
	for i in ticks:
		tick()


func tick() -> void:
	tick_count += 1
	if not boss_active:
		_auto_battle()


## --- Growth: per-unit stats computed from level, not stored ----------

## Which growth curve a party slot uses: the protagonist (slot 0) has a
## fixed curve in UD.*; companions (slot >= 1) use their own data file.
## Falls back to UD.FALLBACK_GROWTH if the slot has no matching def yet
## (should not normally happen).
func _growth_def_for_unit(unit: UDMinion) -> Dictionary:
	if unit.id == 0:
		return {
			"base_hp": UD.PROTAGONIST_BASE_HP, "hp_per_level": UD.PROTAGONIST_HP_PER_LEVEL,
			"base_sp": UD.PROTAGONIST_BASE_SP, "sp_per_level": UD.PROTAGONIST_SP_PER_LEVEL,
			"base_atk": UD.PROTAGONIST_BASE_ATK, "atk_per_level": UD.PROTAGONIST_ATK_PER_LEVEL,
			"base_def": UD.PROTAGONIST_BASE_DEF, "def_per_level": UD.PROTAGONIST_DEF_PER_LEVEL,
			"skills": UD.PROTAGONIST_SKILLS,
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


func unit_max_sp(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_sp"]) + (unit.level - 1) * int(g["sp_per_level"])


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
	unit.sp = unit_max_sp(unit)
	return unit


func _unit_by_id(unit_id: int) -> UDMinion:
	for unit in minions:
		if unit.id == unit_id:
			return unit
	return null


## Shared ledger bonuses (shop upgrades, altar) added on top of every
## living unit's own level-derived ATK/DEF — same "base + upgrades +
## altar" shape dig_power() used to have.
func party_atk_bonus() -> int:
	var bonus := 0
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
	# RPG_SYSTEM_DESIGN_v5 §5.1: idle-mode trash dies to a single hit
	# regardless of its stats — enemy HP/ATK/DEF only matter in manual
	# battles (they're designed as boss-fight companions). This keeps
	# idle pacing independent of the real chapter-scaled stat table
	# (hp 100 vs a low-level party would otherwise take minutes a kill).
	enemy_hp = 0
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
	_roll_document(stage)
	_roll_special_find()


## --- Manual boss fight (turn-based, player commands) -----------------

## Opens a boss encounter: the current gate's boss when standing at an
## undefeated gate, otherwise a REMATCH against the most recent cleared
## gate's boss (repeatable at will - a rematch pays rewards again but
## never advances the stage, see resolve_boss_round). The party is healed
## to full and a REWIND checkpoint (§10) is captured at this exact
## moment — start_boss_fight() is always "full strength, attempt zero".
func start_boss_fight() -> bool:
	if boss_active:
		return false
	var stage := stages.stage_for_index(stage_index)
	var boss_id := str(stage.get("boss_id", ""))
	if boss_id == "":
		boss_id = stages.last_boss_id_at_or_below(stage_index)
	if boss_id == "":
		return false
	_heal_party_full()
	boss_active = true
	boss_enemy_id = boss_id
	var def := enemies.get_enemy(boss_id)
	boss_hp = int(def["hp"])
	boss_part_hp = _initial_part_hp(def)
	boss_parts_destroyed = []
	boss_checkpoint = _capture_checkpoint()
	return true


## Starting HP for each of a boss def's optional body parts (新企画v1
## §8, data/enemies "parts" array). {} for a boss with none.
func _initial_part_hp(def: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry: Variant in def.get("parts", []) as Array:
		var part := entry as Dictionary
		result[str(part["id"])] = int(part["hp"])
	return result


## Only the fight-scoped fields (HP/SP) per unit, keyed by str(unit.id) —
## deliberately NOT unit.to_dict() (which also carries level, a permanent-
## progress field REWIND must never touch, 新企画v1仕様書 v2 §11/§29-12).
func _capture_checkpoint() -> Dictionary:
	var unit_hp_sp: Dictionary = {}
	for unit in minions:
		unit_hp_sp[str(unit.id)] = {"hp": unit.hp, "sp": unit.sp}
	return {
		"unit_hp_sp": unit_hp_sp,
		"boss_hp": boss_hp,
		"boss_part_hp": boss_part_hp.duplicate(),
		# 64-bit RNG state as strings (鉄則4): a raw int here would risk the
		# usual JSON-float corruption once this dict is serialized.
		"rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state),
	}


## Leaves the boss encounter entirely without resolving it (no penalty):
## the party returns to idle-farming trash at the gate. Distinct from
## rewind_boss_fight() below, which restarts the same attempt instead of
## exiting it.
func flee_boss_fight() -> bool:
	if not boss_active:
		return false
	boss_active = false
	boss_hp = 0
	boss_enemy_id = ""
	boss_part_hp = {}
	boss_parts_destroyed = []
	boss_checkpoint = {}
	return true


## Rewinds the CURRENT boss encounter to the checkpoint start_boss_fight()
## captured: party HP/SP, boss HP, and part durability all return to what
## they were at the start of this attempt (新企画v1 §10 — REWIND always
## returns to the start of the fight, never a mid-fight moment). The
## encounter stays active (boss_active is untouched) — this restarts the
## same fight, it does not leave it, unlike flee_boss_fight() above. Two
## triggers call this exact same command: automatically from resolve_
## boss_round() on a party wipe, and the player's own "REWIND" command at
## any point mid-fight (deliberately bailing out of a bad plan costs
## nothing extra over an accidental wipe). What does NOT come back:
## boss_intel (what the player has learned this save, §12 — the one
## thing REWIND does not undo) and anything outside the fight itself
## (coins, items, documents, level).
func rewind_boss_fight() -> bool:
	if not boss_active or boss_checkpoint.is_empty():
		return false
	var snapshot := boss_checkpoint
	# In-place HP/SP restore on the EXISTING minion objects, not a
	# minions.clear()+rebuild — a rebuilt-from-dict unit would only be as
	# safe as UDMinion.to_dict()/from_dict()'s field list, and that list
	# also includes level (see _capture_checkpoint()'s doc comment).
	# .get(...,{}) throughout tolerates a checkpoint from an older shape or
	# a unit id it doesn't recognize by simply leaving that unit's current
	# HP/SP untouched, rather than failing the whole rewind.
	var unit_hp_sp := snapshot.get("unit_hp_sp", {}) as Dictionary
	for unit in minions:
		var saved := unit_hp_sp.get(str(unit.id), {}) as Dictionary
		if not saved.is_empty():
			unit.hp = int(saved["hp"])
			unit.sp = int(saved["sp"])
	boss_hp = int(snapshot["boss_hp"])
	boss_part_hp = (snapshot["boss_part_hp"] as Dictionary).duplicate()
	boss_parts_destroyed = []
	_rng.seed = (snapshot["rng_seed"] as String).to_int()
	_rng.state = (snapshot["rng_state"] as String).to_int()
	return true


func _boss_def() -> Dictionary:
	return enemies.get_enemy(boss_enemy_id)


## Resolves exactly one round: every living unit's action (in order),
## then the boss's counter-attack on one target. `actions` is
## [{ "unit_id": int, "action": "attack"|"skill", "skill_id": String,
## "target_part": String }], one entry per living unit (units without an
## entry simply do nothing this round). `target_part` (新企画v1 §8,
## optional) names a body part from the boss's data; omitted or "" hits
## the boss's main HP exactly like before this system existed. Always
## resolves atomically — a party wipe here is handled by rewinding to
## the checkpoint within this same call (see below), never by leaving
## anything half-applied.
##
## The returned "log" (2026-07-19, added for the battle motion sequencer)
## is one entry per unit that actually acted this round, in `actions`
## order: {unit_id, action, skill_id, effect, target_type, target_id,
## target_part, amount}. It is a pure by-value report of what already
## happened — the round is still resolved atomically in this one call,
## nothing about it is deferred or replayable — so it needs no save-schema
## changes (it is a return value, not sim state) and does not change
## determinism: two sims fed identical actions from identical seeds
## produce identical logs because every field in it is derived from
## values already covered by the existing determinism tests. UI code uses
## it to *time* when an already-known result is revealed on screen (see
## main.gd), not to decide anything. A round that ends in a party wipe
## also carries "rewound": true — the sim has already rewound itself back
## to the checkpoint by the time this call returns, so boss_active/
## boss_hp/boss_part_hp already reflect the restarted attempt, not the
## moment of death.
func resolve_boss_round(actions: Array) -> Dictionary:
	if not boss_active:
		return {}
	var boss := _boss_def()
	var log: Array[Dictionary] = []
	for entry: Variant in actions:
		var action := entry as Dictionary
		var unit := _unit_by_id(int(action["unit_id"]))
		if unit == null or unit.hp <= 0:
			continue
		var target_part := str(action.get("target_part", ""))
		match str(action.get("action", "attack")):
			"attack":
				var amount := maxi(1, effective_atk(unit) - int(boss["def"]))
				_apply_boss_damage(amount, target_part)
				log.append({
					"unit_id": unit.id, "action": "attack", "skill_id": "",
					"effect": "damage", "target_type": "enemy",
					"target_id": boss_enemy_id, "target_part": target_part,
					"amount": amount,
				})
			"skill":
				var skill_id := str(action.get("skill_id", ""))
				var target_id := int(action.get("target_id", unit.id))
				var amount := _apply_skill(unit, skill_id, target_id, target_part)
				var skill_effect := ""
				var skill_target_type := "enemy"
				if skills.has_skill(skill_id):
					var skill := skills.get_skill(skill_id)
					skill_effect = str(skill.get("effect", "damage"))
					skill_target_type = str(skill.get("target", "enemy"))
				log.append({
					"unit_id": unit.id, "action": "skill", "skill_id": skill_id,
					"effect": skill_effect, "target_type": skill_target_type,
					"target_id": (target_id if skill_target_type == "ally" else boss_enemy_id),
					"target_part": (target_part if skill_target_type == "enemy" else ""),
					"amount": amount,
				})
	if boss_hp <= 0:
		var stage := stages.stage_for_index(stage_index)
		_grant_kill_rewards(boss, stage)
		# Only an undefeated gate advances the stage; a rematch against an
		# already-cleared gate's boss farms rewards but stays put.
		if str(stage.get("boss_id", "")) == boss_enemy_id:
			stage_index += 1
		boss_active = false
		boss_hp = 0
		boss_enemy_id = ""
		boss_part_hp = {}
		boss_parts_destroyed = []
		boss_checkpoint = {}
		return {"won": true, "lost": false, "log": log}
	var target := _boss_target()
	var boss_counter: Dictionary = {}
	if target != null:
		var chosen := _boss_choose_action(boss)
		var counter_amount := maxi(
			1, int(chosen.get("power", boss.get("atk", 0))) - effective_def(target))
		target.hp = maxi(0, target.hp - counter_amount)
		boss_counter = {
			"target_unit_id": target.id, "amount": counter_amount,
			"action_id": str(chosen.get("id", "attack")),
		}
		_record_boss_action_seen(str(chosen.get("id", "attack")))
	if _party_wiped():
		rewind_boss_fight()
		return {
			"won": false, "lost": true, "rewound": true,
			"log": log, "boss_counter": boss_counter,
		}
	return {"won": false, "lost": false, "log": log, "boss_counter": boss_counter}


## Routes damage to a body part's own durability pool when a valid,
## not-yet-destroyed part is targeted (新企画v1 §8) — otherwise (no part
## chosen, an already-destroyed part, or an unknown part id) it hits the
## boss's main HP exactly like before this system existed. A part and
## boss_hp are separate pools: destroying every part does not by itself
## reduce boss_hp — only boss_hp reaching 0 wins the fight (§7); parts
## instead change what the boss can still DO (see _boss_choose_action).
func _apply_boss_damage(amount: int, target_part: String) -> void:
	if target_part != "" and boss_part_hp.has(target_part) \
			and not boss_parts_destroyed.has(target_part):
		boss_part_hp[target_part] = int(boss_part_hp[target_part]) - amount
		if int(boss_part_hp[target_part]) <= 0:
			boss_part_hp[target_part] = 0
			boss_parts_destroyed.append(target_part)
			_record_boss_part_destroyed(target_part)
		return
	boss_hp -= amount


## Picks one of the boss's available actions this round (新企画v1 §8),
## honoring requires_part_intact gating against boss_parts_destroyed — an
## action naming a part the player has already broken is off the
## candidate list this and every future round of this attempt. A boss
## with no "actions" data in its def (every boss except the ones this
## system has been added to so far) falls back to a single unnamed
## "attack" action using its flat atk stat, unaffected by this system.
func _boss_choose_action(boss: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for entry: Variant in boss.get("actions", []) as Array:
		var action := entry as Dictionary
		var requires := str(action.get("requires_part_intact", ""))
		if requires != "" and boss_parts_destroyed.has(requires):
			continue
		candidates.append(action)
	if candidates.is_empty():
		return {"id": "attack", "power": int(boss.get("atk", 0))}
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _boss_intel_entry(boss_id: String) -> Dictionary:
	if boss_intel.has(boss_id):
		return boss_intel[boss_id] as Dictionary
	return {"attacks_seen": [], "parts_destroyed_seen": []}


## Only named (data-driven) actions are worth recording — the universal
## flat-atk fallback ("attack") is not information about this specific
## boss.
func _record_boss_action_seen(action_id: String) -> void:
	if action_id == "" or action_id == "attack":
		return
	var entry := _boss_intel_entry(boss_enemy_id)
	var seen := entry["attacks_seen"] as Array
	if not seen.has(action_id):
		seen.append(action_id)
	boss_intel[boss_enemy_id] = entry


func _record_boss_part_destroyed(part_id: String) -> void:
	var entry := _boss_intel_entry(boss_enemy_id)
	var seen := entry["parts_destroyed_seen"] as Array
	if not seen.has(part_id):
		seen.append(part_id)
	boss_intel[boss_enemy_id] = entry


## target_id is the ally to heal for an "ally"-target skill (defaults to
## the caster — self-heal — when omitted, matching the behavior before
## ally targeting existed). target_part (新企画v1 §8) only matters for a
## "damage" skill — see _apply_boss_damage(). Returns the amount of
## damage/healing actually applied (0 for an insufficient-SP no-op or an
## effect with no numeric result yet, e.g. buff_atk/buff_def/debuff/
## special) — 2026-07-19, added so resolve_boss_round's log can report a
## real number for the motion sequencer to show instead of just
## "something happened".
func _apply_skill(
		unit: UDMinion, skill_id: String, target_id: int = -1, target_part: String = "") -> int:
	if not skills.has_skill(skill_id) or not unit_skills(unit).has(skill_id):
		return 0
	var skill := skills.get_skill(skill_id)
	# sp_cost: null means "not balanced yet" (RPG_SYSTEM_DESIGN_v5 skills
	# not yet given a number) — treated as free rather than guessing a
	# figure; once real data supplies a cost this reads it normally.
	var raw_cost: Variant = skill.get("sp_cost", 0)
	var cost := 0 if raw_cost == null else int(raw_cost)
	if unit.sp < cost:
		return 0
	unit.sp -= cost
	var power := int(skill.get("power", 0))
	match str(skill.get("effect", "damage")):
		"damage":
			var amount := maxi(1, power - int(_boss_def()["def"]))
			_apply_boss_damage(amount, target_part)
			return amount
		"heal":
			var target := _unit_by_id(target_id) if target_id != -1 else unit
			if target == null or target.hp <= 0:
				target = unit
			# Same floor as the damage branch above, applied to "power"
			# instead of "power - def" (heals have no defense to net
			# against): most companion heals still have no "power" set
			# (RPG_SYSTEM_DESIGN_v5 numbers pending), and healing for 0 is
			# indistinguishable from the skill silently failing. This is a
			# floor, not an invented balance number — a skill with a real
			# power value is unaffected (maxi(1, 10) == 10).
			# The RETURNED amount is the actual hp delta after clamping to
			# max, not the requested/floored amount — a target already at
			# full hp has nothing to gain, and the caller (the boss-fight UI)
			# used to show a phantom "+1" heal popup on a full-hp ally
			# because it trusted the pre-clamp floor value instead of what
			# actually changed (2026-07-26 user report).
			var before_hp := target.hp
			var requested := maxi(1, power)
			target.hp = mini(unit_max_hp(target), before_hp + requested)
			return target.hp - before_hp
		_:
			# buff_atk / buff_def / debuff / special intentionally left as
			# a future extension — no lasting per-encounter modifier state
			# exists yet, so these skills consume SP and otherwise no-op.
			return 0


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
		unit.sp = unit_max_sp(unit)


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
	unit.sp = unit_max_sp(unit)
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


## Extra document drop chance from the altar facility. The "survey" shop
## upgrade that used to grant this is retired (2026-07-15, shop redesign:
## pickaxe/survey folded into the weapon system and the altar) — its
## per-level bonus now rides altar_level instead, alongside altar's
## existing +1 atk/level (party_atk_bonus()). _effect_levels_in() still
## reads any doc_chance_add already banked in upgrades so a save with
## survey levels bought before the retirement keeps that bonus frozen
## rather than losing it outright.
func document_chance_bonus() -> float:
	var bonus := 0.0
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
		"boss_enemy_id": boss_enemy_id,
		"boss_part_hp": boss_part_hp.duplicate(),
		"boss_parts_destroyed": boss_parts_destroyed.duplicate(),
		"boss_checkpoint": boss_checkpoint.duplicate(true),
		"boss_intel": boss_intel.duplicate(true),
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
			unit.sp = sim.unit_max_sp(unit)
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
		sim.boss_enemy_id = str(d.get("boss_enemy_id", ""))
		# A save from before rematches existed can be mid-fight without
		# recording which boss: derive it from the gate it must be at.
		if sim.boss_active and sim.boss_enemy_id == "":
			sim.boss_enemy_id = str(
				p_stages.stage_for_index(sim.stage_index).get("boss_id", ""))
			if sim.boss_enemy_id == "":
				sim.boss_active = false
				sim.boss_hp = 0
		# 新企画v1 §8/§10 (2026-08-18): all optional/additive — a save from
		# before this system existed simply has none, same as a boss with
		# no "parts" data in its def.
		for part_id: Variant in (d.get("boss_part_hp", {}) as Dictionary).keys():
			sim.boss_part_hp[str(part_id)] = int((d["boss_part_hp"] as Dictionary)[part_id])
		for part_id: Variant in d.get("boss_parts_destroyed", []) as Array:
			sim.boss_parts_destroyed.append(str(part_id))
		sim.boss_checkpoint = (d.get("boss_checkpoint", {}) as Dictionary).duplicate(true)
		for boss_id: Variant in (d.get("boss_intel", {}) as Dictionary).keys():
			var intel_entry := (d["boss_intel"] as Dictionary)[boss_id] as Dictionary
			var attacks_seen: Array[String] = []
			for a: Variant in intel_entry.get("attacks_seen", []) as Array:
				attacks_seen.append(str(a))
			var parts_seen: Array[String] = []
			for p: Variant in intel_entry.get("parts_destroyed_seen", []) as Array:
				parts_seen.append(str(p))
			sim.boss_intel[str(boss_id)] = {
				"attacks_seen": attacks_seen, "parts_destroyed_seen": parts_seen,
			}
		sim.total_kills = int(d.get("total_kills", 0))
		sim.equipped_weapon_id = str(d.get("equipped_weapon_id", ""))
		sim.weapon_level = int(d.get("weapon_level", 0))
	# v8 -> v9 (新企画v1 §1, 2026-08-18): companions no longer gate on
	# join_at_docs — every companion definition is present in the party
	# from the very start. An old save (whose companions array may hold
	# 0-3 of the 4 defs, mid-way through the old staged join) is
	# normalized to the full roster, same "rebuild party structure, keep
	# everything else" judgment as v7 -> v8 above (coins, items,
	# documents, upgrades, altar level are untouched).
	if int(d.get("version", 1)) < 9:
		var known_ids: Array[String] = []
		for def: Variant in p_companion_defs:
			known_ids.append(str((def as Dictionary)["id"]))
		sim.companions = known_ids
		sim.minions.clear()
		for i in known_ids.size() + 1:
			sim.minions.append(sim._new_unit_at_level(i, 1))
	return sim
