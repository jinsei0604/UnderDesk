extends GutTest
## §12-2: serialize -> JSON text -> deserialize must reproduce identical state.


func test_roundtrip_mid_activity() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(0.5), 555)
	# 73 ticks of auto-battle: several kills, document rolls, and a stage
	# advance or two, exercising most of the serialized state at once.
	sim.advance(73)

	var json_text := JSON.stringify(sim.to_dict())
	var restored := UDSim.from_dict(JSON.parse_string(json_text), UDTestFixtures.enemies(), UDTestFixtures.stages(0.5))

	assert_eq(JSON.stringify(restored.to_dict()), json_text, "roundtrip identical")


func test_roundtrip_preserves_future() -> void:
	var original := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 777)
	original.advance(10)

	var json_text := JSON.stringify(original.to_dict())
	var restored := UDSim.from_dict(JSON.parse_string(json_text), UDTestFixtures.enemies(), UDTestFixtures.stages(1.0))

	original.advance(60)
	restored.advance(60)
	assert_eq(
		JSON.stringify(original.to_dict()),
		JSON.stringify(restored.to_dict()),
		"restored sim continues identically (RNG state survived)"
	)


func test_save_version_present() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	assert_eq(int(sim.to_dict()["version"]), UD.SAVE_VERSION)
