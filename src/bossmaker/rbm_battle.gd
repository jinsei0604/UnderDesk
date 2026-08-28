class_name RBMBattle
extends RefCounted

## RPG BOSS MAKER (working title) — standalone Phase 1 battle core.
##
## Deliberately independent of UDSim (see src/bossmaker/README.md): no DEF stat,
## no REWIND, no parts, no items, no leveling. UI-agnostic — this class has no
## dependency on any Control/Node and can be driven entirely from a script or a
## test. A future Creator/UI would call resolve_turn() exactly the way the tests
## in tests/bossmaker/ do.
##
## Turn structure (v0.1-B §11): each call to resolve_turn() is one whole
## "戦闘全体ターン" — TURN START (reset per-turn postures) → NORMAL ACTION PHASE
## (every living combatant acts once, in a fixed SPD-sorted order) → TURN END
## (turn-scoped state, e.g. counter stance, clears). Phase 1 does not yet register
## any start/end-of-turn interrupts (指定行動) — that capability is deferred to a
## later step — but the phase boundaries already exist as the seam for it.

var party: Array[RBMUnit] = []
var boss: RBMUnit
var boss_def: Dictionary = {}

## Party-wide duration effects (防御強化 / 鉄壁). Same shape as RBMUnit.timed_effects.
var party_timed_effects: Dictionary = {}

## Computed once at construction (SPD never changes mid-battle in Phase 1 — no
## SPD buffs/debuffs exist) and then simply cycled every turn.
var turn_order: Array[String] = []

var current_turn: int = 1
var battle_over: bool = false
var winner: String = ""

var rng: RandomNumberGenerator

func _init(ally_defs: Array[Dictionary], p_boss_def: Dictionary, rng_seed: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var next_id := 0
	for def in ally_defs:
		party.append(RBMDataLoader.unit_from_ally_def(def, next_id))
		next_id += 1
	boss_def = p_boss_def
	boss = RBMDataLoader.unit_from_boss_def(p_boss_def)
	turn_order = _compute_turn_order()

## v0.1-B §10 (confirmed): SPD descending; equal SPD favors an ally over the boss;
## no random tie-break. Allies never share SPD with each other in the fixed
## roster, so the only realistic tie is "one ally vs the boss".
func _compute_turn_order() -> Array[String]:
	var entries: Array[Dictionary] = []
	for unit in party:
		entries.append({"token": "ally:%d" % unit.id, "spd": unit.spd, "is_ally": true, "tiebreak": unit.id})
	entries.append({"token": "boss", "spd": boss.spd, "is_ally": false, "tiebreak": 0})
	entries.sort_custom(_entry_is_before)
	var order: Array[String] = []
	for entry in entries:
		order.append(str(entry["token"]))
	return order

func _entry_is_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["spd"]) != int(b["spd"]):
		return int(a["spd"]) > int(b["spd"])
	if bool(a["is_ally"]) != bool(b["is_ally"]):
		return bool(a["is_ally"])
	return int(a["tiebreak"]) < int(b["tiebreak"])

func _unit_by_id(id: int) -> RBMUnit:
	for unit in party:
		if unit.id == id:
			return unit
	return null

func _unit_for_token(token: String) -> RBMUnit:
	if token == "boss":
		return boss
	return _unit_by_id(int(token.substr(5)))

func _living_allies() -> Array[RBMUnit]:
	var out: Array[RBMUnit] = []
	for unit in party:
		if not unit.is_downed():
			out.append(unit)
	return out

func _find_skill(unit: RBMUnit, skill_id: String) -> Dictionary:
	for skill in unit.skills:
		if str(skill.get("id", "")) == skill_id:
			return skill
	return {}

func _check_battle_over() -> void:
	if battle_over:
		return
	if boss.is_downed():
		battle_over = true
		winner = "ally"
		return
	if _living_allies().is_empty():
		battle_over = true
		winner = "boss"

## ally_actions: Dictionary[String unit_id -> Dictionary action]. A missing entry,
## or one with an unrecognized "type", is NOT a implicit attack (Step 2 fix #3) —
## it resolves as an explicit no-op failure ("unspecified_action" / "invalid_action")
## so a broken caller can never silently deal damage it never asked for.
## action shapes: {"type":"attack"} / {"type":"defend"} /
##                {"type":"skill","skill_id":String,"target_id":int}
func resolve_turn(ally_actions: Dictionary) -> Dictionary:
	var log: Array[Dictionary] = []
	if battle_over:
		return {"log": log, "battle_over": true, "winner": winner, "turn": current_turn}

	# The turn number this call is resolving — captured before any mutation, and
	# returned as-is regardless of whether current_turn advances afterward (Step 2
	# fix #5: "turn" always means "the turn just resolved", never the next one).
	var resolved_turn := current_turn

	# TURN START — reset per-turn postures, then pre-apply "防御" (only) for the
	# WHOLE turn: it is a locked-in base command, not resolved lazily at the acting
	# unit's own turn-order slot, so a low-SPD defender still reduces an
	# earlier-acting boss's damage that same turn (Step 2 confirmation #1).
	# かばう (a skill, not a base command) is deliberately NOT pre-applied here —
	# it only takes effect once the tank's own action actually resolves below
	# (Step 2 fix #2).
	for unit in party:
		unit.is_defending = false
		unit.protecting_ally_id = -1
	for id_key in ally_actions.keys():
		var action: Dictionary = ally_actions[id_key]
		var unit := _unit_by_id(int(id_key))
		if unit == null or unit.is_downed():
			continue
		if str(action.get("type", "")) == "defend":
			unit.is_defending = true

	# NORMAL ACTION PHASE
	for token in turn_order:
		if battle_over:
			break
		var acting := _unit_for_token(token)
		if acting == null or acting.is_downed():
			continue
		if acting.is_ally:
			var id_key := str(acting.id)
			if not ally_actions.has(id_key):
				log.append({"actor": acting.id, "action": "none", "failed": true, "reason": "unspecified_action"})
			else:
				log.append(_resolve_ally_action(acting, ally_actions[id_key]))
		else:
			log.append(_resolve_boss_action(acting))
		_check_battle_over()

	# TURN END — every turn-scoped posture clears here, regardless of whether it
	# ever triggered, so state is fully at rest between resolve_turn() calls
	# (Step 2 fix #4).
	for unit in party:
		unit.counter_pending_this_turn = false
		unit.active_counter_skill = {}
		unit.is_defending = false
		unit.protecting_ally_id = -1

	if not battle_over:
		current_turn += 1

	return {"log": log, "battle_over": battle_over, "winner": winner, "turn": resolved_turn}

## Step 2 fix #3: an unrecognized action "type" must never be treated as an attack.
func _resolve_ally_action(unit: RBMUnit, action: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", ""))
	match action_type:
		"attack":
			return _resolve_normal_attack(unit)
		"defend":
			return {"actor": unit.id, "action": "defend"}
		"skill":
			return _resolve_ally_skill(unit, str(action.get("skill_id", "")), int(action.get("target_id", -1)))
		_:
			return {"actor": unit.id, "action": "none", "failed": true, "reason": "invalid_action", "raw_type": action_type}

## v0.1-B §7: 無属性・ATK×1.0・SP消費0・使用でSP+10（最大SP超えない）。
## v0.1-B §10: 通常攻撃は「攻撃スキル」ではない — 居合の対象外。
func _resolve_normal_attack(unit: RBMUnit) -> Dictionary:
	var result := {"actor": unit.id, "action": "attack"}
	var amount := _compute_and_apply_damage(unit, boss, RBMConstants.NORMAL_ATTACK_ATK_MULTIPLIER, RBMConstants.Attribute.NEUTRAL, false)
	result["target"] = "boss"
	result["amount"] = amount
	if unit.has_sp_resource():
		unit.sp = mini(unit.max_sp, unit.sp + RBMConstants.NORMAL_ATTACK_SP_GAIN)
	_check_battle_over()
	return result

func _resolve_ally_skill(unit: RBMUnit, skill_id: String, target_id: int) -> Dictionary:
	var skill := _find_skill(unit, skill_id)
	var result := {"actor": unit.id, "action": "skill", "skill_id": skill_id}
	if skill.is_empty():
		result["failed"] = true
		result["reason"] = "unknown_skill"
		return result

	var effect := str(skill.get("effect", ""))

	# Step 2 fix #7: validate the target BEFORE spending SP. A since-downed
	# target means the whole action is 不発 (void) — no SP cost, no redirect.
	var validation := _validate_skill_target(unit, skill, effect, target_id)
	if not bool(validation.get("valid", true)):
		result["failed"] = true
		result["reason"] = str(validation.get("reason", "invalid_target"))
		return result

	var cost := int(skill.get("sp_cost", 0))
	if unit.has_sp_resource():
		if unit.sp < cost:
			result["failed"] = true
			result["reason"] = "insufficient_sp"
			return result
		unit.sp -= cost

	match effect:
		"damage":
			var atk_mult := float(skill.get("atk_multiplier", 1.0))
			var attribute := RBMConstants.attribute_from_name(str(skill.get("attribute", "NEUTRAL")))
			result["target"] = "boss"
			result["amount"] = _compute_and_apply_damage(unit, boss, atk_mult, attribute, true)
		"heal":
			_resolve_heal_skill(unit, skill, target_id, result)
		"sp_recover_single_no_self":
			_resolve_sp_recover_single(unit, skill, target_id, result)
		"sp_recover_all_no_self":
			_resolve_sp_recover_all(unit, skill, result)
		"buff_atk_self":
			var mult := float(skill.get("buff_multiplier", 1.0))
			var duration := int(skill.get("duration_turns", 1))
			RBMConstants.set_timed_effect(unit.timed_effects, "atk_buff", current_turn, duration, mult)
		"buff_next_attack":
			unit.next_attack_bonus_multiplier = float(skill.get("buff_multiplier", 2.0))
		"counter_stance":
			unit.counter_pending_this_turn = true
			unit.active_counter_skill = skill
		"guard_boost":
			var duration := int(skill.get("duration_turns", 1))
			var rate := float(skill.get("new_rate", RBMConstants.DEFEND_BOOSTED_REDUCTION))
			RBMConstants.set_timed_effect(party_timed_effects, "guard_boost", current_turn, duration, rate)
		"party_damage_reduction":
			var duration := int(skill.get("duration_turns", 1))
			var rate := float(skill.get("reduction_rate", RBMConstants.IRON_WALL_REDUCTION))
			RBMConstants.set_timed_effect(party_timed_effects, "iron_wall", current_turn, duration, rate)
		"guard_redirect":
			# Step 2 fix #2: かばう only takes effect here, at the tank's own
			# action resolution — never pre-applied at TURN START.
			unit.protecting_ally_id = target_id
			result["protecting"] = target_id
		_:
			pass

	_check_battle_over()
	return result

## Step 2 fix #7: returns whether `skill`'s target is currently valid, checked
## BEFORE any SP is spent. Effects with no meaningful external target (self/
## party-wide effects) are always valid. TOCTOU is not a concern — nothing
## mutates state between this check and the actual application in the same
## synchronous call.
func _validate_skill_target(caster: RBMUnit, skill: Dictionary, effect: String, target_id: int) -> Dictionary:
	match effect:
		"damage":
			if boss.is_downed():
				return {"valid": false, "reason": "target_downed"}
		"heal":
			match str(skill.get("target", "ally_chosen")):
				"ally_chosen", "ally_chosen_no_self":
					var no_self := str(skill.get("target", "")) == "ally_chosen_no_self"
					var target := _unit_by_id(target_id)
					if target == null or target.is_downed() or (no_self and target_id == caster.id):
						return {"valid": false, "reason": "invalid_target"}
				_:
					pass  # "ally_all" always has some valid subset, even if empty.
		"sp_recover_single_no_self":
			var target := _unit_by_id(target_id)
			if target == null or target.is_downed() or target_id == caster.id or not target.has_sp_resource():
				return {"valid": false, "reason": "invalid_target"}
		"guard_redirect":
			var target := _unit_by_id(target_id)
			if target == null or target.is_downed():
				return {"valid": false, "reason": "invalid_target"}
		_:
			pass
	return {"valid": true}

func _resolve_heal_skill(caster: RBMUnit, skill: Dictionary, target_id: int, result: Dictionary) -> void:
	var amount := int(skill.get("heal_amount", 0))
	match str(skill.get("target", "ally_chosen")):
		"ally_chosen", "ally_chosen_no_self":
			var no_self := str(skill.get("target", "")) == "ally_chosen_no_self"
			var target := _unit_by_id(target_id)
			if target == null or target.is_downed() or (no_self and target_id == caster.id):
				result["failed"] = true
				result["reason"] = "invalid_target"
			else:
				result["target"] = target.id
				result["amount"] = target.heal(amount)
		"ally_all":
			var healed := {}
			for unit in party:
				if not unit.is_downed():
					healed[unit.id] = unit.heal(amount)
			result["healed"] = healed
		_:
			pass

func _resolve_sp_recover_single(caster: RBMUnit, skill: Dictionary, target_id: int, result: Dictionary) -> void:
	var amount := int(skill.get("sp_amount", 0))
	var target := _unit_by_id(target_id)
	if target == null or target.is_downed() or target_id == caster.id or not target.has_sp_resource():
		result["failed"] = true
		result["reason"] = "invalid_target"
		return
	var before := target.sp
	target.sp = mini(target.max_sp, target.sp + amount)
	result["target"] = target.id
	result["amount"] = target.sp - before

func _resolve_sp_recover_all(caster: RBMUnit, skill: Dictionary, result: Dictionary) -> void:
	var amount := int(skill.get("sp_amount", 0))
	var recovered := {}
	for unit in party:
		if unit.id != caster.id and not unit.is_downed() and unit.has_sp_resource():
			var before := unit.sp
			unit.sp = mini(unit.max_sp, unit.sp + amount)
			recovered[unit.id] = unit.sp - before
	result["recovered"] = recovered

func _pick_boss_normal_action() -> Dictionary:
	var candidates: Array = boss_def.get("normal_action_candidates", [])
	if candidates.is_empty():
		return {}
	var total_weight := 0.0
	for candidate in candidates:
		total_weight += float(candidate.get("weight", 1.0))
	if total_weight <= 0.0:
		return _find_skill(boss, str(candidates[0].get("skill_id", "")))
	var roll := rng.randf() * total_weight
	var cumulative := 0.0
	for candidate in candidates:
		cumulative += float(candidate.get("weight", 1.0))
		if roll < cumulative:
			return _find_skill(boss, str(candidate.get("skill_id", "")))
	return _find_skill(boss, str(candidates[-1].get("skill_id", "")))

func _resolve_boss_action(unit: RBMUnit) -> Dictionary:
	var skill := _pick_boss_normal_action()
	if skill.is_empty():
		return {"actor": "boss", "action": "none"}
	var result := {"actor": "boss", "action": "skill", "skill_id": str(skill.get("id", ""))}
	match str(skill.get("effect", "")):
		"damage":
			var atk_mult := float(skill.get("atk_multiplier", 1.0))
			var attribute := RBMConstants.attribute_from_name(str(skill.get("attribute", "NEUTRAL")))
			if str(skill.get("target", "ally_random_single")) == "ally_all":
				# Required fix #1: かばう must never apply to an all-target attack.
				var hits := {}
				for ally in party:
					if not ally.is_downed():
						hits[ally.id] = _apply_boss_hit_to_ally(ally, atk_mult, attribute, false)
				result["hits"] = hits
			else:
				var living := _living_allies()
				if living.is_empty():
					result["failed"] = true
				else:
					var target: RBMUnit = living[rng.randi_range(0, living.size() - 1)]
					var hit := _apply_boss_hit_to_ally(target, atk_mult, attribute, true)
					for key in hit.keys():
						result[key] = hit[key]
		"heal":
			result["amount"] = unit.heal(int(skill.get("heal_amount", 0)))
		"buff_atk_self":
			var mult := float(skill.get("buff_multiplier", 1.0))
			var duration := int(skill.get("duration_turns", 1))
			RBMConstants.set_timed_effect(unit.timed_effects, "atk_buff", current_turn, duration, mult)
		_:
			pass
	_check_battle_over()
	return result

## Resolves one boss attack landing on `target` — applying かばう redirection
## (single-target attacks only, per required fix #1: `allow_redirect` must be
## false for an "ally_all" hit) and カウンター interception (unrestricted — the
## spec never limits counter to single-target attacks). v0.1-B §7, §10, §16.
## Returns a partial log dict to be merged into the caller's result.
func _apply_boss_hit_to_ally(target: RBMUnit, atk_mult: float, attribute: RBMConstants.Attribute, allow_redirect: bool) -> Dictionary:
	var actual_target := target
	if allow_redirect:
		for unit in party:
			if unit.protecting_ally_id == target.id and not unit.is_downed():
				actual_target = unit
				break

	if actual_target.counter_pending_this_turn:
		actual_target.counter_pending_this_turn = false
		var counter_skill := actual_target.active_counter_skill
		actual_target.active_counter_skill = {}
		var counter_attribute := RBMConstants.attribute_from_name(str(counter_skill.get("attribute", "NEUTRAL")))
		var counter_mult := float(counter_skill.get("atk_multiplier", 1.0))
		var reflected := _compute_and_apply_damage(actual_target, boss, counter_mult, counter_attribute, true)
		# Required fix #6: the incoming hit that the counter blocked is explicitly
		# logged as amount=0, distinct from the (separate, real) reflected damage.
		return {"blocked": true, "counter": true, "target": actual_target.id, "amount": 0, "reflected": reflected}

	var amount := _compute_and_apply_damage(boss, actual_target, atk_mult, attribute, false)
	return {"amount": amount, "target": actual_target.id}

## The single damage formula for both directions (v0.1-B §6, §7):
##   ATK × スキル倍率 × 属性補正 × (居合ボーナス, if applicable) × ダメージ軽減
## No intermediate rounding; the final result alone is rounded, and 0 is a valid
## result (no UnderDesk-style max(1, ...) floor).
func _compute_and_apply_damage(attacker: RBMUnit, target: RBMUnit, skill_multiplier: float, attack_attribute: RBMConstants.Attribute, is_attack_skill_use: bool) -> int:
	var atk_buff := float(RBMConstants.timed_effect_value(attacker.timed_effects, "atk_buff", current_turn, 1.0))
	var base_atk := float(attacker.atk) * atk_buff
	var attribute_mult := RBMConstants.attribute_multiplier(attack_attribute, target.weak_attribute, target.resist_attribute)
	var bonus_mult := 1.0
	if is_attack_skill_use and attacker.next_attack_bonus_multiplier != 1.0:
		bonus_mult = attacker.next_attack_bonus_multiplier
		attacker.next_attack_bonus_multiplier = 1.0
	var reduction_mult := _damage_reduction_multiplier(target)
	var raw := base_atk * skill_multiplier * attribute_mult * bonus_mult * reduction_mult
	var final_amount := int(round(raw))
	target.hp = maxi(0, target.hp - final_amount)
	if target.is_downed():
		target.clear_on_downed()
	return final_amount

## v0.1-B §7/§16: multiple reduction sources stack multiplicatively. Only applies
## when the target is an ally — the boss has no defend/軽減 mechanics in Phase 1.
func _damage_reduction_multiplier(target: RBMUnit) -> float:
	if not target.is_ally:
		return 1.0
	var mult := 1.0
	if target.is_defending:
		var rate := RBMConstants.DEFEND_BASE_REDUCTION
		if RBMConstants.timed_effect_active(party_timed_effects, "guard_boost", current_turn):
			rate = float(RBMConstants.timed_effect_value(party_timed_effects, "guard_boost", current_turn, RBMConstants.DEFEND_BOOSTED_REDUCTION))
		mult *= (1.0 - rate)
	if RBMConstants.timed_effect_active(party_timed_effects, "iron_wall", current_turn):
		var iron_rate := float(RBMConstants.timed_effect_value(party_timed_effects, "iron_wall", current_turn, RBMConstants.IRON_WALL_REDUCTION))
		mult *= (1.0 - iron_rate)
	return mult
