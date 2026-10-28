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

## 味方の覚醒（2026-10-24）。覚醒していない時の値（戦闘開始時の HP・ATK・SPD・最大SP。HARDCORE の性能調整を
## 入れた後の値）。覚醒は max_hp/atk/spd/max_sp をこの値×倍率へ置き換え、解除でこの値へ戻す（元の値は書き換えない）。
var base_max_hp: int = 1
var base_atk: int = 0
var base_spd: int = 0
var base_max_sp: int = RBMConstants.NO_SP
var awakened: bool = false
var awakening_multiplier: float = 1.0
## 残りの覚醒の行動回数（自分の行動の機会ごとに1減る。0 になった行動が終わると解除）。
var awakening_turns_left: int = 0
## 覚醒を発動した行動そのものは数えない（次の自分の行動から数える）。発動した行動が終わるまで true。
var awakening_fresh: bool = false

## 戦闘開始時に呼ぶ: 今の値を覚醒していない時の値として控える。
func remember_base_stats() -> void:
	base_max_hp = max_hp
	base_atk = atk
	base_spd = spd
	base_max_sp = max_sp

## 覚醒の倍率を掛けた値（端数は四捨五入、最大HP・最大SPは1以上）。
static func scaled_stat(base: int, multiplier: float, at_least: int = 0) -> int:
	return maxi(at_least, int(round(float(base) * multiplier)))

## 最大値が変わる時、今の値を同じ割合で移す（四捨五入）。0 は 0 のまま。1 以上は 1 以上を保つ（割合の移し替えで
## 戦闘不能・SP 0 にしない）。
static func carry_ratio(current: int, old_max: int, new_max: int) -> int:
	if current <= 0 or old_max <= 0:
		return 0
	return clampi(int(round(float(current) * float(new_max) / float(old_max))), 1, new_max)

## 覚醒する（SP の消費は呼び出し側が倍率を掛ける前に済ませる）。HP・SP は今の割合のまま最大値を変える。
func awaken(multiplier: float, turns: int) -> void:
	awakened = true
	awakening_multiplier = multiplier
	awakening_turns_left = turns
	awakening_fresh = true
	_apply_awakening_stats(multiplier)

## 覚醒を解く。HP・SP は今の割合のまま覚醒していない時の最大値へ戻す。覚醒以外の強化・弱体（atk_buff 等）には触れない。
func end_awakening() -> void:
	if not awakened:
		return
	_apply_awakening_stats(1.0)
	awakened = false
	awakening_multiplier = 1.0
	awakening_turns_left = 0
	awakening_fresh = false

func _apply_awakening_stats(multiplier: float) -> void:
	var new_max_hp := scaled_stat(base_max_hp, multiplier, 1)
	hp = carry_ratio(hp, max_hp, new_max_hp)
	max_hp = new_max_hp
	atk = scaled_stat(base_atk, multiplier)
	spd = scaled_stat(base_spd, multiplier)
	if base_max_sp != RBMConstants.NO_SP:
		var new_max_sp := scaled_stat(base_max_sp, multiplier, 1)
		sp = carry_ratio(sp, max_sp, new_max_sp)
		max_sp = new_max_sp

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
## 味方の覚醒も戦闘不能になった瞬間に解く（2026-10-24。HP は 0 のまま、最大値などは覚醒していない時の値へ）。
func clear_on_downed() -> void:
	next_attack_bonus_multiplier = 1.0
	counter_pending_this_turn = false
	active_counter_skill = {}
	end_awakening()
