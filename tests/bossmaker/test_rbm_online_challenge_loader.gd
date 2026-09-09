extends GutTest

## Phase 4D — RBMOnlineChallengeLoaderのfake駆動テスト。Online→Battle経路と
## Clear Check parityの結合部分を検証する。

func _cleared_draft(boss_name: String = "オンライン挑戦ボス") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	return draft

func _fake_api() -> RBMFakeBossApiAdapter:
	var api := RBMFakeBossApiAdapter.new()
	add_child_autofree(api)
	return api

func _boss_row_from(draft: RBMCreatorDraft, overrides: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(draft)["payload"]
	var row := {
		"id": "boss-1",
		"boss_name": draft.boss_name,
		"author_name": draft.author_name,
		"revision": 1,
		"payload": payload,
	}
	for key in overrides:
		row[key] = overrides[key]
	return row

func test_load_boss_for_challenge_returns_a_battle_ready_draft() -> void:
	var maker_draft := _cleared_draft()
	var api := _fake_api()
	api.configure_get_response({"ok": true, "boss": _boss_row_from(maker_draft)})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	assert_true(result["ok"])
	assert_eq(result["boss_name"], maker_draft.boss_name)
	assert_true(result["draft"] is RBMCreatorDraft)
	assert_eq(api.get_calls, ["boss-1"])

func test_load_boss_for_challenge_reproduces_the_makers_clear_check_snapshot_exactly() -> void:
	var maker_draft := _cleared_draft()
	var proven_snapshot := maker_draft.clear_check_snapshot_for_save()
	var api := _fake_api()
	api.configure_get_response({"ok": true, "boss": _boss_row_from(maker_draft)})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	var challenger_draft: RBMCreatorDraft = result["draft"]
	assert_eq(challenger_draft.battle_content_snapshot(), proven_snapshot)

func test_load_boss_for_challenge_surfaces_a_network_error_from_the_adapter() -> void:
	var api := _fake_api()
	api.configure_get_response({"ok": false, "error_kind": "network_error", "message": "timeout"})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	assert_false(result["ok"])
	assert_eq(result["error"], "network_error")

func test_load_boss_for_challenge_surfaces_not_found() -> void:
	var api := _fake_api()
	api.configure_get_response({"ok": false, "error_kind": "not_found", "message": "gone"})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	assert_false(result["ok"])
	assert_eq(result["error"], "not_found")

func test_load_boss_for_challenge_rejects_an_unsupported_schema_version() -> void:
	var maker_draft := _cleared_draft()
	var row := _boss_row_from(maker_draft)
	(row["payload"] as Dictionary)["schema_version"] = 999
	var api := _fake_api()
	api.configure_get_response({"ok": true, "boss": row})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	assert_false(result["ok"])
	assert_eq(result["error"], "unsupported_schema_version")

func test_load_boss_for_challenge_rejects_a_tampered_payload_via_hash_mismatch() -> void:
	var maker_draft := _cleared_draft()
	var row := _boss_row_from(maker_draft)
	(row["payload"] as Dictionary)["draft_fields"]["hp"] = 999999
	var api := _fake_api()
	api.configure_get_response({"ok": true, "boss": row})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	assert_false(result["ok"])
	assert_eq(result["error"], "hash_mismatch")

func test_load_boss_for_challenge_rejects_a_malformed_payload_shape() -> void:
	var api := _fake_api()
	api.configure_get_response({"ok": true, "boss": {"id": "boss-1", "boss_name": "x", "payload": "not a dict"}})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	assert_false(result["ok"])
	assert_eq(result["error"], "invalid_payload")

func test_load_boss_for_challenge_reconstructed_draft_battles_identically_via_definition_loader() -> void:
	var maker_draft := _cleared_draft()
	var api := _fake_api()
	api.configure_get_response({"ok": true, "boss": _boss_row_from(maker_draft)})

	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(api, "boss-1")
	var challenger_draft: RBMCreatorDraft = result["draft"]

	var started := RBMDefinitionLoader.start_battle(challenger_draft.to_definition())
	assert_true(bool(started.get("ok", false)))
	assert_true(started.get("battle") is RBMBattle)
