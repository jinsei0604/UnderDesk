class_name RBMUnit
extends RefCounted

## Runtime battle-unit state for the RPG BOSS MAKER battle core.
## Used for both ally units and the single boss unit (is_ally distinguishes them).

var id: int = -1
var display_name: String = ""
var is_ally: bool = true

var attribute: RBMConstants.Attribute = RBMConstants.Attribute.NEUTRAL
## Variant: an RBMConstants.Attribute value, or null if this unit has no weakness/resistance.
var weak_attribute: Variant = null
var resist_attribute: Variant = null

var max_hp: int = 1
var hp: int = 1
var atk: int = 0
var spd: int = 0

## RBMConstants.NO_SP if this unit has no SP resource at all (the hammer tank).
var max_sp: int = RBMConstants.NO_SP
var sp: int = 0

var skills: Array[Dictionary] = []

## True only during the current battle-turn; reset every turn.
var is_defending: bool = false

## Duration-based effects keyed by effect name (e.g. "atk_buff").
## See RBMConstants.set_timed_effect / timed_effect_active / timed_effect_value.
var timed_effects: Dictionary = {}

## 居合の構え: multiplier applied to this unit's next attack-skill damage only.
## 1.0 means "no bonus pending". Not turn-limited — persists until consumed or the
## unit is downed (v0.1-B §10).
var next_attack_bonus_multiplier: float = 1.0

## カウンター: true only while this unit is poised to intercept the first attack it
## receives this battle-turn. Always cleared at turn end regardless of trigger.
var counter_pending_this_turn: bool = false
var active_counter_skill: Dictionary = {}

## かばう: the ally unit id this unit (the tank) is shielding this battle-turn only.
## -1 means "not protecting anyone".
var protecting_ally_id: int = -1

func is_downed() -> bool:
	return hp <= 0

func has_sp_resource() -> bool:
	return max_sp != RBMConstants.NO_SP

## Applies a fixed heal amount, clamped to max_hp. Returns the amount actually healed.
func heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before

## v0.1-B §10: iai/counter state must clear the instant this unit is downed.
func clear_on_downed() -> void:
	next_attack_bonus_multiplier = 1.0
	counter_pending_this_turn = false
	active_counter_skill = {}
