class_name UDTestFixtures
extends RefCounted
## Shared strata/room definitions for core tests (independent of data files).


static func strata(document_chance: float = 0.0) -> UDStrataDB:
	return UDStrataDB.from_dicts([
		{
			"id": "test_soil",
			"name_key": "S",
			"depth_from": 1,
			"depth_to": 4,
			"terrain": "SOIL",
			"hardness": 2,
			"yield": "soil",
			"documents": ["d1", "d2", "d3"],
			"document_chance": document_chance,
		},
		{
			"id": "test_rock",
			"name_key": "R",
			"depth_from": 5,
			"depth_to": 9,
			"terrain": "ROCK",
			"hardness": 4,
			"yield": "stone",
			"documents": ["d4"],
			"document_chance": document_chance,
		},
	])


static func dorm_def() -> Dictionary:
	return {
		"id": "dorm",
		"name_key": "ROOM_DORM",
		"width": 2,
		"height": 1,
		"cost": {"soil": 10},
		"effect": "minion_add",
	}
