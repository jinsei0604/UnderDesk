class_name RBMDataLoader
extends RefCounted

## Loads RPG BOSS MAKER JSON definitions (allies, boss) into plain Dictionaries,
## and builds runtime RBMUnit instances from them.
##
## This is the same shape of data a future Creator would author and hand to the
## battle core — see src/bossmaker/README.md.

static func load_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

static func _skills_from_def(def: Dictionary) -> Array[Dictionary]:
	var raw: Array = def.get("skills", [])
	var typed: Array[Dictionary] = []
	for entry in raw:
		if entry is Dictionary:
			typed.append(entry)
	return typed

static func unit_from_ally_def(def: Dictionary, id: int) -> RBMUnit:
	var unit := RBMUnit.new()
	unit.id = id
	unit.display_name = str(def.get("display_name", def.get("id", "")))
	unit.is_ally = true
	unit.attribute = RBMConstants.attribute_from_name(str(def.get("attribute", "NEUTRAL")))
	unit.weak_attribute = RBMConstants.weakness_for(unit.attribute)
	unit.resist_attribute = RBMConstants.resistance_for(unit.attribute)
	unit.max_hp = int(def.get("hp", 1))
	unit.hp = unit.max_hp
	unit.atk = int(def.get("atk", 0))
	unit.spd = int(def.get("spd", 0))
	var max_sp_value: Variant = def.get("max_sp", RBMConstants.NO_SP)
	unit.max_sp = int(max_sp_value) if max_sp_value != null else RBMConstants.NO_SP
	unit.sp = unit.max_sp if unit.has_sp_resource() else 0
	unit.skills = _skills_from_def(def)
	return unit

## Boss units have no id of their own in Phase 1 (single-boss encounters only);
## weak/resist attributes are author-set (v0.1-A: "ボスの弱点・耐性は...作者が設定できる")
## and may each be null (no weakness / no resistance at all).
static func unit_from_boss_def(def: Dictionary) -> RBMUnit:
	var unit := RBMUnit.new()
	unit.id = -1
	unit.display_name = str(def.get("display_name", def.get("id", "")))
	unit.is_ally = false
	unit.max_hp = int(def.get("hp", 1))
	unit.hp = unit.max_hp
	unit.atk = int(def.get("atk", 0))
	unit.spd = int(def.get("spd", 0))
	unit.max_sp = RBMConstants.NO_SP
	var weak: Variant = def.get("weak_attribute", null)
	var resist: Variant = def.get("resist_attribute", null)
	unit.weak_attribute = RBMConstants.attribute_from_name(str(weak)) if weak != null else null
	unit.resist_attribute = RBMConstants.attribute_from_name(str(resist)) if resist != null else null
	unit.skills = _skills_from_def(def)
	return unit
