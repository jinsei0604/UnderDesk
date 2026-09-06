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
	unit.character_id = str(def.get("id", ""))
	unit.attribute = RBMConstants.attribute_from_name(str(def.get("attribute", "NEUTRAL")))
	# v0.1-C: allies remain single-attribute creatures (their own weakness/
	# resistance always derives from exactly one fixed pairwise chart lookup,
	# per RBMConstants.ATTRIBUTE_WEAKNESS/ATTRIBUTE_RESISTANCE) -- so their
	# list form is always 0 or 1 entries, never author-configured to be more.
	var ally_weak: Variant = RBMConstants.weakness_for(unit.attribute)
	unit.weak_attributes = [ally_weak] if ally_weak != null else []
	var ally_resist: Variant = RBMConstants.resistance_for(unit.attribute)
	unit.resist_attributes = [ally_resist] if ally_resist != null else []
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
	unit.weak_attributes = _attribute_list_from_def(def, "weak_attribute", "weak_attributes")
	unit.resist_attributes = _attribute_list_from_def(def, "resist_attribute", "resist_attributes")
	unit.skills = _skills_from_def(def)
	return unit

## v0.1-C 多属性対応: accepts either shape a boss `def` Dictionary may arrive
## in -- the new plural array key (preferred, if present: a list of attribute-
## name Strings, as RBMDefinitionLoader's resolved boss_def now always
## includes), or the legacy singular key (a single attribute-name String or
## null), which older/raw fixtures (e.g. hand-built test Dictionaries that
## predate v0.1-C) may still use on its own. Never both interpreted at once.
static func _attribute_list_from_def(def: Dictionary, singular_key: String, plural_key: String) -> Array:
	if def.has(plural_key):
		var raw: Array = def[plural_key]
		var out: Array = []
		for value_variant in raw:
			out.append(RBMConstants.attribute_from_name(str(value_variant)))
		return out
	var single: Variant = def.get(singular_key, null)
	return [RBMConstants.attribute_from_name(str(single))] if single != null else []
