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

static func weakness_for(attribute: Attribute) -> Variant:
	return ATTRIBUTE_WEAKNESS.get(attribute, null)

static func resistance_for(attribute: Attribute) -> Variant:
	return ATTRIBUTE_RESISTANCE.get(attribute, null)

## 弱点1.2倍 / 耐性0.8倍 / それ以外1.0倍（v0.1-B §5・§8）。
static func attribute_multiplier(attack_attribute: Attribute, target_weak: Variant, target_resist: Variant) -> float:
	if target_weak != null and attack_attribute == target_weak:
		return ATTRIBUTE_MULTIPLIER_WEAK
	if target_resist != null and attack_attribute == target_resist:
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
