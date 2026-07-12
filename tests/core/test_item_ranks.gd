extends GutTest
## Stackable ranked collection (user spec 2026-07-12): per-rank caps
## Z10/S50/A100/B200/C500/D500, guild exchange rates Z←S×3, S←A×5,
## A←B×7, B←C×10 (C/D chest-only), altar offerings burn coins + items.

const RANKS := {
	"z1": "Z", "s1": "S", "s2": "S", "a1": "A", "b1": "B",
	"c1": "C", "d1": "D",
}


func _sim(rng_seed: int = 3) -> UDSim:
	var pool: Array[String] = []
	for id: Variant in RANKS.keys():
		pool.append(str(id))
	pool.sort()
	return UDSim.new_game(UDTestFixtures.strata(), rng_seed, pool, [], {}, RANKS)


func test_rank_caps_and_helpers() -> void:
	var sim := _sim()
	assert_eq(sim.item_rank("z1"), "Z")
	assert_eq(sim.item_cap("z1"), 10)
	assert_eq(sim.item_cap("d1"), 500)
	assert_eq(sim.item_rank("unknown"), UD.ITEM_DEFAULT_RANK, "missing rank defaults")
	assert_eq(sim.rank_below("Z"), "S")
	assert_eq(sim.rank_below("C"), "D")
	assert_eq(sim.rank_below("D"), "", "nothing below D")


func test_add_item_respects_cap() -> void:
	var sim := _sim()
	sim.items["z1"] = 9
	sim._add_item("z1", 5)
	assert_eq(sim.item_count("z1"), 10, "clamped to the Z cap")


func test_chest_skips_capped_items() -> void:
	var sim := _sim(777)
	for id: Variant in RANKS.keys():
		sim.items[str(id)] = sim.item_cap(str(id))
	var before := sim.items.duplicate()
	sim.dig_policy = UD.DigPolicy.DOWN
	sim.advance(400)
	assert_eq(sim.items, before, "everything at cap: chests only pay coins")


func test_exchange_success_consumes_lower_rank() -> void:
	var sim := _sim()
	sim.items["s1"] = 2
	sim.items["s2"] = 1
	assert_true(sim.exchange_item("z1", {"s1": 2, "s2": 1}), "Z costs S×3")
	assert_eq(sim.item_count("z1"), 1)
	assert_eq(sim.item_count("s1"), 0)
	assert_eq(sim.item_count("s2"), 0)


func test_exchange_rates_match_spec() -> void:
	assert_eq(int(UD.ITEM_EXCHANGE_COSTS["Z"]), 3)
	assert_eq(int(UD.ITEM_EXCHANGE_COSTS["S"]), 5)
	assert_eq(int(UD.ITEM_EXCHANGE_COSTS["A"]), 7)
	assert_eq(int(UD.ITEM_EXCHANGE_COSTS["B"]), 10)
	assert_false(UD.ITEM_EXCHANGE_COSTS.has("C"), "C has no exchange")
	assert_false(UD.ITEM_EXCHANGE_COSTS.has("D"), "D has no exchange")


func test_exchange_rejects_bad_offers() -> void:
	var sim := _sim()
	sim.items["s1"] = 5
	sim.items["a1"] = 7
	assert_false(sim.exchange_item("z1", {"s1": 2}), "short count")
	assert_false(sim.exchange_item("z1", {"a1": 3}), "wrong fodder rank")
	assert_false(sim.exchange_item("z1", {"s1": 4}), "over count")
	assert_false(sim.exchange_item("c1", {"d1": 1}), "C rank is chest-only")
	assert_false(sim.exchange_item("ghost", {"s1": 3}), "unknown target")
	sim.items["z1"] = sim.item_cap("z1")
	assert_false(sim.exchange_item("z1", {"s1": 3}), "target at cap")
	assert_eq(sim.item_count("s1"), 5, "failed offers consume nothing")


func test_altar_needs_building_and_coins() -> void:
	var sim := _sim()
	sim.inventory[UD.RES_GOLD] = 10000
	assert_false(sim.offer_at_altar(), "no altar built yet")
	sim.rooms.append({"id": "altar", "pos": Vector2i(2, 1), "effect": "doc_chance_add"})
	var power_before := sim.dig_power()
	var cost := sim.altar_offer_cost()
	assert_true(sim.offer_at_altar())
	assert_eq(sim.altar_level, 1)
	assert_eq(sim.dig_power(), power_before + 1, "each level adds dig power")
	assert_eq(int(sim.inventory[UD.RES_GOLD]), 10000 - cost)
	assert_gt(sim.altar_offer_cost(), cost, "cost scales per level")
	sim.inventory[UD.RES_GOLD] = 0
	assert_false(sim.offer_at_altar(), "cannot offer what you do not have")


func test_altar_demands_items_at_higher_levels() -> void:
	var sim := _sim()
	sim.rooms.append({"id": "altar", "pos": Vector2i(2, 1), "effect": "doc_chance_add"})
	sim.inventory[UD.RES_GOLD] = 1000000
	sim.altar_level = 4
	assert_eq(sim.altar_required_item_rank(), "D", "level 5 starts the D tier")
	assert_false(sim.offer_at_altar(), "item required but none offered")
	sim.items["c1"] = 1
	assert_false(sim.offer_at_altar("c1"), "wrong rank refused")
	sim.items["d1"] = 2
	assert_true(sim.offer_at_altar("d1"))
	assert_eq(sim.item_count("d1"), 1, "offering consumed the item")
	sim.altar_level = 29
	assert_eq(sim.altar_required_item_rank(), "Z", "level 30+ demands Z")


func test_altar_level_survives_roundtrip_but_not_prestige() -> void:
	var sim := _sim()
	sim.altar_level = 3
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.strata(), [], [], {}, RANKS
	)
	assert_eq(restored.altar_level, 3)
	for y in range(1, UD.PRESTIGE_MIN_DEPTH + 1):
		sim._ensure_rows(y + 2)
		sim.grid.set_terrain(Vector2i(UD.DEPOT_POS.x, y), UD.Terrain.AIR)
	var fresh := UDSim.prestige_reset(sim, UDTestFixtures.strata())
	assert_eq(fresh.altar_level, 0, "offerings are run-scoped")
	assert_eq(fresh.item_ranks, RANKS, "rank map carries into the next run")


func test_v4_item_array_migrates_to_counts() -> void:
	var sim := _sim()
	var d := sim.to_dict()
	d["version"] = 4
	d["items"] = ["s1", "d1"]
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)),
		UDTestFixtures.strata(), [], [], {}, RANKS
	)
	assert_eq(restored.item_count("s1"), 1)
	assert_eq(restored.item_count("d1"), 1)
	assert_eq(restored.distinct_items(), 2)


func test_stacked_items_survive_roundtrip() -> void:
	var sim := _sim()
	sim.items["s1"] = 7
	sim.items["d1"] = 123
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.strata(), [], [], {}, RANKS
	)
	assert_eq(restored.item_count("s1"), 7)
	assert_eq(restored.item_count("d1"), 123)


func test_real_item_files_declare_valid_ranks() -> void:
	var db := UDItemDB.load_from_dir("res://data/items")
	for id in db.all_ids():
		assert_true(db.rank(id) in UD.ITEM_RANKS, "%s rank valid" % id)
	assert_gt(db.ids_of_rank("D").size(), 0, "the common tier is populated")
