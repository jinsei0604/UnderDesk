class_name RBMUnit
extends RefCounted

## Runtime battle-unit state for the RPG BOSS MAKER battle core.
## Used for both ally units and the single boss unit (is_ally distinguishes them).

var id: int = -1
var display_name: String = ""
var is_ally: bool = true

## Phase 2: 固定5キャラクターのマスターJSON上のid（"hero"/"tank"等、
## RBMDefinitionLoader.KNOWN_ALLY_PATHSのキーと一致）。ADVANCED AIの
## character_alive/character_downed/character_downed_instant条件が、
## パーティ内の配列位置に依存しない安定した参照でユニットを特定するために
## 使う（既存のint idはparty配列内の位置由来で、パーティ構成が変わると
## 同じcharacter_idでも別のidになりうるため、この用途には使えない）。
## ボスユニットは空文字列のまま（ボスに複数種類はなく参照する必要が無い）。
var character_id: String = ""

var attribute: RBMConstants.Attribute = RBMConstants.Attribute.NEUTRAL

## v0.1-C 多属性対応: a unit may have any number of weaknesses/resistances (0
## or more each) -- each entry is an RBMConstants.Attribute. Creator-side
## validation guarantees the same attribute is never registered as both a
## weakness and a resistance for one unit simultaneously (out of scope for
## this engine to re-validate/arbitrate -- see RBMConstants.attribute_multiplier_for_lists).
var weak_attributes: Array = []
var resist_attributes: Array = []

## v0.1-B single-value fields, kept ONLY so code/tests written before v0.1-C's
## multi-attribute support keep reading exactly what they always did (a single
## RBMConstants.Attribute value, or null if this unit has no weakness/
## resistance at all). Computed live off the list above -- never a second,
## independently-settable copy -- so the two representations can never drift
## out of sync with each other.
var weak_attribute: Variant:
	get: return weak_attributes[0] if not weak_attributes.is_empty() else null
var resist_attribute: Variant:
	get: return resist_attributes[0] if not resist_attributes.is_empty() else null

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
