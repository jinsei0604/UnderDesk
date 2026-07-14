extends GutTest
## Document unlock conditions (§7.3 "ID＋条件"): gated documents stay
## underground until their conditions hold. Conditions are injected data,
## never serialized, so gating cannot break save compatibility.


func _conditions() -> Dictionary:
	return {
		"d2": {"min_docs": 1},
		"d3": {"requires_companions": ["c1"]},
	}


func _fight_next(sim: UDSim) -> void:
	# Two ticks = one trash kill in the fixtures (tick 1 spawns, tick 2
	# kills — test_trash hp 4 < the level-1 protagonist's attack), so this
	# is exactly one document-roll opportunity — the combat equivalent of
	# digging one cell.
	sim.advance(2)


func test_ungated_documents_drop_normally() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], [], _conditions())
	_fight_next(sim)
	assert_eq(sim.discovered_documents.size(), 1)
	assert_eq(sim.discovered_documents[0], "d1", "only d1 is unlocked at 0 docs")


func test_min_docs_gate_opens_with_progress() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], [], _conditions())
	_fight_next(sim)
	_fight_next(sim)
	assert_eq(sim.discovered_documents.size(), 2)
	assert_true(sim.discovered_documents.has("d2"), "d2 unlocked once 1 doc found")


func test_companion_gate_blocks_until_join() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], [], {
		"d1": {"requires_companions": ["c1"]},
		"d2": {"requires_companions": ["c1"]},
		"d3": {"requires_companions": ["c1"]},
	})
	_fight_next(sim)
	assert_eq(sim.discovered_documents.size(), 0, "all opening-band docs are gated")
	sim.companions.append("c1")
	_fight_next(sim)
	assert_eq(sim.discovered_documents.size(), 1, "gate opens when c1 joins")


func test_item_gate() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], [], {
		"d1": {"requires_items": ["relic"]},
		"d2": {"requires_items": ["relic"]},
		"d3": {"requires_items": ["relic"]},
	})
	_fight_next(sim)
	assert_eq(sim.discovered_documents.size(), 0)
	sim.items["relic"] = 1
	_fight_next(sim)
	assert_eq(sim.discovered_documents.size(), 1, "gate opens with the item")


func test_gating_is_deterministic() -> void:
	var a := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 11, [], [], _conditions())
	var b := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 11, [], [], _conditions())
	for sim: UDSim in [a, b]:
		sim.advance(200)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_conditions_survive_roundtrip_via_injection() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], [], _conditions())
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), [], [], _conditions()
	)
	assert_eq(restored.doc_conditions, _conditions(), "conditions re-injected")
	assert_false(restored._doc_unlocked("d2"), "gate state derives from sim state")
	assert_true(restored._doc_unlocked("d1"))


