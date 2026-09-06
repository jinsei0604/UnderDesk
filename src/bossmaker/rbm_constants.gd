class_name RBMConstants
extends RefCounted

## RPG BOSS MAKER (working title) — shared constants for the standalone battle core.
## Deliberately independent of UD.* (UnderDesk's own constants) — see src/bossmaker/README.md.

enum Attribute { FIRE, ICE, LIGHTNING, WIND, NEUTRAL }

const ATTRIBUTE_BY_NAME := {
	"FIRE": Attribute.FIRE,
	"ICE": Attribute.ICE,
	"LIGHTNING": Attribute.LIGHTNING,
	"WIND": Attribute.WIND,
	"NEUTRAL": Attribute.NEUTRAL,
}

# v0.1-B §8: fixed pairwise weakness/resistance chart. NEUTRAL has neither.
const ATTRIBUTE_WEAKNESS := {
	Attribute.FIRE: Attribute.ICE,
	Attribute.ICE: Attribute.FIRE,
	Attribute.WIND: Attribute.LIGHTNING,
	Attribute.LIGHTNING: Attribute.WIND,
}

const ATTRIBUTE_RESISTANCE := {
	Attribute.FIRE: Attribute.FIRE,
	Attribute.ICE: Attribute.ICE,
	Attribute.WIND: Attribute.WIND,
	Attribute.LIGHTNING: Attribute.LIGHTNING,
}

const ATTRIBUTE_MULTIPLIER_WEAK := 1.2
const ATTRIBUTE_MULTIPLIER_RESIST := 0.8
const ATTRIBUTE_MULTIPLIER_NORMAL := 1.0

## Sentinel for "this unit has no SP resource at all" (the hammer tank).
## Not the same as SP == 0.
const NO_SP := -1

const NORMAL_ATTACK_ATK_MULTIPLIER := 1.0
const NORMAL_ATTACK_SP_GAIN := 10

const DEFEND_BASE_REDUCTION := 0.5
const DEFEND_BOOSTED_REDUCTION := 0.6
const IRON_WALL_REDUCTION := 0.10

static func attribute_from_name(value: String) -> Attribute:
	return ATTRIBUTE_BY_NAME.get(value, Attribute.NEUTRAL)

## Phase 2: ATTRIBUTE_BY_NAME（文字列→enum）の逆引き。ADVANCED AIの
## received_attribute_instant/last_received_attribute条件がDefinition上の
## 文字列表現（"FIRE"等）と実際の攻撃属性（enum）を比較するために使う。
## 5件程度の線形探索のみで、ダメージ発生のたび高々1回しか呼ばれない
## （RBMBattle._compute_and_apply_damage参照）ためコストは無視できる。
static func attribute_name(attribute: Attribute) -> String:
	for key in ATTRIBUTE_BY_NAME.keys():
		if ATTRIBUTE_BY_NAME[key] == attribute:
			return key
	return "NEUTRAL"

static func weakness_for(attribute: Attribute) -> Variant:
	return ATTRIBUTE_WEAKNESS.get(attribute, null)

static func resistance_for(attribute: Attribute) -> Variant:
	return ATTRIBUTE_RESISTANCE.get(attribute, null)

## 弱点1.2倍 / 耐性0.8倍 / それ以外1.0倍（v0.1-B §5・§8）。
## Single-value form, kept for source/behavior compatibility with anything
## still passing a single Attribute-or-null per side. v0.1-C's real battle
## damage path uses attribute_multiplier_for_lists() below instead.
static func attribute_multiplier(attack_attribute: Attribute, target_weak: Variant, target_resist: Variant) -> float:
	if target_weak != null and attack_attribute == target_weak:
		return ATTRIBUTE_MULTIPLIER_WEAK
	if target_resist != null and attack_attribute == target_resist:
		return ATTRIBUTE_MULTIPLIER_RESIST
	return ATTRIBUTE_MULTIPLIER_NORMAL

## v0.1-C 多属性対応: list-membership version of attribute_multiplier() above
## -- a unit may now have any number of weaknesses/resistances (0 or more
## each). Creator-side validation guarantees the same attribute is never
## registered as both a weakness and a resistance for one unit at once, so
## this engine never needs to arbitrate that case; the weak-checked-first
## order below exists purely to mirror the original single-value function's
## own check order, not to define a new tie-break rule.
static func attribute_multiplier_for_lists(attack_attribute: Attribute, target_weak: Array, target_resist: Array) -> float:
	if target_weak.has(attack_attribute):
		return ATTRIBUTE_MULTIPLIER_WEAK
	if target_resist.has(attack_attribute):
		return ATTRIBUTE_MULTIPLIER_RESIST
	return ATTRIBUTE_MULTIPLIER_NORMAL

## Generic "N turns, battle-turn-numbered, re-use refreshes rather than stacks" effect
## storage (v0.1-B §9). Shared by both per-unit effects (RBMUnit.timed_effects) and
## party-wide effects (RBMBattle.party_timed_effects) — same Dictionary shape either way.
static func set_timed_effect(effects: Dictionary, key: String, applied_at_turn: int, duration_turns: int, value: Variant = null) -> void:
	effects[key] = {
		"applied_at_turn": applied_at_turn,
		"duration_turns": duration_turns,
		"value": value,
	}

## v0.1-B §9: "使用したターンを1ターン目として数える" — active while
## current_turn is within [applied_at_turn, applied_at_turn + duration_turns - 1].
static func timed_effect_active(effects: Dictionary, key: String, current_turn: int) -> bool:
	if not effects.has(key):
		return false
	var entry: Dictionary = effects[key]
	return current_turn <= int(entry["applied_at_turn"]) + int(entry["duration_turns"]) - 1

static func timed_effect_value(effects: Dictionary, key: String, current_turn: int, default_value: Variant = null) -> Variant:
	if not timed_effect_active(effects, key, current_turn):
		return default_value
	return effects[key]["value"]
