class_name RBMMotionCatalog
extends RefCounted

## A fixed visual vocabulary for the existing 20 skills. This catalog does not
## resolve targets, calculate damage, spend SP, or consume the battle RNG.
enum Pose { IDLE, ANTICIPATION, ATTACK, FOLLOWTHROUGH, AREA_WINDUP, AREA_RELEASE,
	FOCUS, SUPPORT, ULTIMATE_CHARGE, ULTIMATE_RELEASE, GUARD, HIT }

const SKILLS := {
	"hero_slash": ["fire_slash", "FIRE", 1, 2, 3, 0.20, 0.14, 0.20, 25.0],
	"hero_blaze_all": ["fire_sweep", "FIRE", 4, 5, 3, 0.27, 0.23, 0.23, 12.0],
	"hero_flame_wrap": ["fire_buff", "FIRE", 6, 7, 0, 0.28, 0.26, 0.20, 0.0],
	"hero_burst_slash": ["fire_burst", "FIRE", 8, 9, 3, 0.40, 0.24, 0.25, 38.0],
	"butler_ice_bolt": ["ice_bolt", "ICE", 1, 2, 3, 0.23, 0.24, 0.18, 0.0],
	"butler_ice_storm": ["ice_storm", "ICE", 4, 5, 3, 0.32, 0.30, 0.22, 0.0],
	"butler_sp_gift": ["sp_single", "SP", 6, 7, 0, 0.28, 0.30, 0.22, 0.0],
	"butler_grand_ice": ["ice_grand", "ICE", 8, 9, 3, 0.48, 0.34, 0.25, 0.0],
	"healer_shock": ["lightning", "LIGHTNING", 1, 2, 3, 0.24, 0.16, 0.22, 0.0],
	"healer_heal_single": ["heal_single", "HP", 6, 7, 0, 0.24, 0.26, 0.20, 0.0],
	"healer_heal_all": ["heal_all", "HP", 4, 5, 0, 0.30, 0.32, 0.22, 0.0],
	"healer_sp_all": ["sp_all", "SP", 8, 9, 0, 0.38, 0.34, 0.24, 0.0],
	"samurai_slash": ["wind_slash", "WIND", 1, 2, 3, 0.22, 0.10, 0.22, 32.0],
	"samurai_slash_all": ["wind_sweep", "WIND", 4, 5, 3, 0.28, 0.18, 0.24, 20.0],
	"samurai_iai": ["iai", "WIND", 6, 7, 7, 0.32, 0.23, 0.20, 0.0],
	"samurai_counter": ["counter_stance", "WIND", 8, 8, 8, 0.22, 0.21, 0.17, 0.0],
	"tank_smash": ["hammer", "NEUTRAL", 4, 5, 3, 0.30, 0.17, 0.25, 20.0],
	"tank_guard_swap": ["protect", "GUARD", 1, 10, 10, 0.20, 0.20, 0.20, 10.0],
	"tank_guard_boost": ["guard_boost", "GUARD", 6, 7, 7, 0.28, 0.26, 0.22, 0.0],
	"tank_iron_wall": ["iron_wall", "GUARD", 8, 9, 9, 0.36, 0.30, 0.24, 0.0],
}
const COLORS := {
	"FIRE": Color("ed8741"), "ICE": Color("88c5dc"), "LIGHTNING": Color("e4c76b"),
	"WIND": Color("aac68e"), "NEUTRAL": Color("c5b496"), "HP": Color("91b978"),
	"SP": Color("ac91cf"), "GUARD": Color("ccb779"),
}

static func profile(entry: Dictionary, skill: Dictionary = {}) -> Dictionary:
	var skill_id := str(entry.get("skill_id", skill.get("id", "")))
	var action := str(entry.get("action", ""))
	if bool(entry.get("failed", false)) or action == "none":
		return _from_row(["failed", "NEUTRAL", 0, 0, 0, 0.02, 0.04, 0.02, 0.0])
	if SKILLS.has(skill_id):
		return _from_row(SKILLS[skill_id])
	if action == "defend":
		return _from_row(["defend", "GUARD", 1, 10, 10, 0.15, 0.15, 0.15, 0.0])
	if action == "attack":
		return _from_row(["normal", "NEUTRAL", 1, 2, 3, 0.18, 0.13, 0.19, 20.0])
	var effect := str(skill.get("effect", skill.get("type", "damage")))
	var attribute := str(skill.get("attribute", "NEUTRAL"))
	if effect in ["heal", "self_heal"]:
		return _from_row(["heal_single", "HP", 6, 7, 0, 0.28, 0.25, 0.20, 0.0])
	if effect in ["buff_atk_self", "atk_self_buff"]:
		return _from_row(["boss_buff", attribute, 8, 9, 0, 0.30, 0.25, 0.20, 0.0])
	var is_all := str(skill.get("target", "")) in ["ally_all", "all"] or entry.has("hits")
	return _from_row(["boss_all" if is_all else "boss_single", attribute, 4 if is_all else 1,
		5 if is_all else 2, 3, 0.32 if is_all else 0.24, 0.24 if is_all else 0.18, 0.22, 10.0])

static func color_for(attribute: String) -> Color:
	return COLORS.get(attribute, COLORS["NEUTRAL"])

static func _from_row(row: Array) -> Dictionary:
	return {"kind": str(row[0]), "attribute": str(row[1]), "windup_pose": int(row[2]),
		"impact_pose": int(row[3]), "recover_pose": int(row[4]), "windup": float(row[5]),
		"travel": float(row[6]), "recovery": float(row[7]), "advance": float(row[8])}
