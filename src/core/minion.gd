class_name UDMinion
extends RefCounted
## A party unit (2026-07-15 redesign: dig -> cave exploration + combat).
## No position/pathing — battle is not spatial. Growth (max HP/MP/ATK/DEF)
## is computed from level via an injected growth-def Dictionary
## (UDSim._growth_def_for_unit()), not stored, mirroring how dig_power()
## used to be computed rather than saved.

var id: int
var display_name: String
var level: int = 1
var hp: int = 1
var mp: int = 0


static func create(p_id: int, p_level: int, p_hp: int, p_mp: int) -> UDMinion:
	var minion := UDMinion.new()
	minion.id = p_id
	minion.display_name = UD.MINION_NAMES[p_id % UD.MINION_NAMES.size()]
	minion.level = p_level
	minion.hp = p_hp
	minion.mp = p_mp
	return minion


## Art assets are named after the companion's data id (companion_2 ->
## minion_2.png), not the party's join order. A minion's slot index in
## sim.minions is positional (protagonist=0, then one per sim.companions
## entry in order), so the UI derives the art variant from the matching
## companion id instead of trusting the slot index directly (§6).
static func art_variant_for_companion(companion_id: String) -> int:
	var digits := ""
	for i in range(companion_id.length() - 1, -1, -1):
		var ch := companion_id[i]
		if not ch.is_valid_int():
			break
		digits = ch + digits
	return int(digits) if digits != "" else 1


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"level": level,
		"hp": hp,
		"mp": mp,
	}


static func from_dict(d: Dictionary) -> UDMinion:
	var minion := UDMinion.new()
	minion.id = int(d["id"])
	minion.display_name = str(d["display_name"])
	minion.level = int(d.get("level", 1))
	minion.hp = int(d.get("hp", 1))
	minion.mp = int(d.get("mp", 0))
	return minion
