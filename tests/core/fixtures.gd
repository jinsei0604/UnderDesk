class_name UDTestFixtures
extends RefCounted
## Shared enemy/stage definitions for core tests (independent of data files).


static func enemies() -> UDEnemyDB:
	return UDEnemyDB.from_dicts([
		{"id": "test_trash", "name_key": "X", "hp": 4, "atk": 1, "def": 0,
			"exp": 3, "coins": 2, "is_boss": false},
		{"id": "test_boss", "name_key": "X", "hp": 20, "atk": 3, "def": 1,
			"exp": 15, "coins": 10, "is_boss": true},
	])


## `document_chance` on the non-gate band, matching the old strata fixture's
## optional param (0.0 by default so document rolls are opt-in per test).
static func stages(document_chance: float = 0.0) -> UDStageDB:
	return UDStageDB.from_dicts([
		{
			"id": "test_band", "name_key": "X",
			"stage_from": 1, "stage_to": 4,
			"trash_pool": ["test_trash"], "boss_id": "",
			"documents": ["d1", "d2", "d3"], "document_chance": document_chance,
		},
		{
			"id": "test_gate", "name_key": "X",
			"stage_from": 5, "stage_to": 5,
			"trash_pool": ["test_trash"], "boss_id": "test_boss",
			"documents": ["d4"], "document_chance": document_chance,
		},
		{
			"id": "test_deep", "name_key": "X",
			"stage_from": 6, "stage_to": 9,
			"trash_pool": ["test_trash"], "boss_id": "",
			"documents": [], "document_chance": document_chance,
		},
	])


static func skills() -> UDSkillDB:
	return UDSkillDB.from_dicts([
		{"id": "test_skill", "name_key": "X", "desc_key": "X",
			"mp_cost": 2, "power": 5, "target": "enemy", "effect": "damage"},
	])


static func weapons() -> UDShopDB:
	return UDShopDB.from_dicts([
		{"id": "test_dagger", "name_key": "X", "desc_key": "X",
			"buy_cost": 100, "base_atk": 5, "atk_per_level": 2,
			"upgrade_base_cost": 50, "upgrade_cost_mult": 1.5, "max_level": 3},
		{"id": "test_axe", "name_key": "X", "desc_key": "X",
			"buy_cost": 500, "base_atk": 15, "atk_per_level": 3,
			"upgrade_base_cost": 100, "upgrade_cost_mult": 1.5, "max_level": 3},
	])
