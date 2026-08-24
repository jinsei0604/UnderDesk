class_name UDBattleItemDB
extends RefCounted
## Battle-only consumables from data/battle_items/*.json (HP/SPポーション
## 追加, 2026-08-25) — same flat-Dictionary-per-file convention as
## UDSkillDB/UDItemDB. NOT the same thing as UDItemDB's permanent treasure
## collection (§19: "一般的なRPGのインベントリに99個持つアイテムでは
## ありません...恒久所持品システムへ無理に統合しない") — these are a
## finite per-boss-fight resource (sim.battle_item_counts, reset to
## UD.BATTLE_ITEM_START_COUNT by every start_boss_fight() call).
## Each def: {id, name_key, desc_key, heal_stat: "hp"|"sp", heal_percent:
## float}. heal_percent is intentionally data-driven, not hardcoded in
## GDScript (§2 「回復率を大量にハードコードしない」) — 30% today is a
## placeholder balance value, adjustable per-file without touching code.

var _items: Dictionary = {}  # id -> def


static func from_dicts(defs: Array) -> UDBattleItemDB:
	var db := UDBattleItemDB.new()
	for def: Variant in defs:
		var item := def as Dictionary
		db._items[item["id"]] = item
	return db


static func load_from_dir(dir_path: String) -> UDBattleItemDB:
	return UDBattleItemDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> Dictionary:
	assert(_items.has(id))
	return _items[id]


func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _items.keys():
		ids.append(id)
	ids.sort()
	return ids
