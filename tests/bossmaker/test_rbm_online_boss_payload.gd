extends GutTest

## Phase 4B/4D — RBMOnlineBossPayloadのbuild/validate往復テスト。
## Clear Check parity（Makerがクリアした条件とChallengerが実際に戦う
## 条件の一致）の核心部分をここで検証する。

func _playable_draft(boss_name: String = "オンラインテストボス") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.author_name = "作者A"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	return draft

func _cleared_draft(boss_name: String = "オンラインテストボス") -> RBMCreatorDraft:
	var draft := _playable_draft(boss_name)
	draft.record_clear_check_success()
	return draft

# ---------------------------------------------------------------------------
# build_for_publish
# ---------------------------------------------------------------------------

func test_build_for_publish_rejects_a_draft_that_never_cleared() -> void:
	var draft := _playable_draft()
	var result := RBMOnlineBossPayload.build_for_publish(draft)
	assert_false(result["ok"])
	assert_eq(result["error"], "clear_check_not_valid")

func test_build_for_publish_rejects_when_current_content_no_longer_matches_the_clear_check_snapshot() -> void:
	var draft := _cleared_draft()
	draft.hp = draft.hp + 500 # invalidates is_clear_check_currently_valid()
	var result := RBMOnlineBossPayload.build_for_publish(draft)
	assert_false(result["ok"])
	assert_eq(result["error"], "clear_check_not_valid")

func test_build_for_publish_succeeds_for_a_genuinely_cleared_draft() -> void:
	var draft := _cleared_draft()
	var result := RBMOnlineBossPayload.build_for_publish(draft)
	assert_true(result["ok"])
	var payload: Dictionary = result["payload"]
	assert_eq(int(payload["schema_version"]), RBMOnlineBossPayload.SCHEMA_VERSION)
	assert_eq(payload["boss_name"], "オンラインテストボス")
	assert_eq(payload["author_name"], "作者A")
	assert_true((payload["battle_hash"] as String).length() == 64)

func test_build_for_publish_never_includes_local_only_fields() -> void:
	var draft := _cleared_draft()
	var result := RBMOnlineBossPayload.build_for_publish(draft)
	var draft_fields: Dictionary = result["payload"]["draft_fields"]
	assert_false(draft_fields.has("published"))
	assert_false(draft_fields.has("published_at_unix_time"))
	assert_false(draft_fields.has("online_boss_id"))
	assert_false(draft_fields.has("online_published"))

## 2026-10(ユーザー確定仕様): 作者メッセージ(author_notes)は挑戦する人へ見せるものとして公開データに
## 含め、挑戦側で復元できる。戦闘内容ではないのでbattle_hashは変わらない。
func test_the_author_message_is_published_and_comes_back_for_the_challenger() -> void:
	var draft := _cleared_draft()
	var without := RBMOnlineBossPayload.build_for_publish(draft)
	draft.set_author_notes("居合の構えに入ったら守りを固めること。")
	var result := RBMOnlineBossPayload.build_for_publish(draft)
	var payload: Dictionary = result["payload"]
	assert_eq((payload["draft_fields"] as Dictionary)["author_notes"], "居合の構えに入ったら守りを固めること。")
	assert_eq(payload["battle_hash"], without["payload"]["battle_hash"], "the message is not battle content")
	var validated := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_true(validated["ok"])
	assert_eq((validated["draft"] as RBMCreatorDraft).author_notes, "居合の構えに入ったら守りを固めること。")

func test_an_unset_author_message_comes_back_empty() -> void:
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(_cleared_draft())["payload"]
	assert_eq((payload["draft_fields"] as Dictionary)["author_notes"], "")
	var validated := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_eq((validated["draft"] as RBMCreatorDraft).author_notes, "")

func test_a_published_author_message_keeps_the_existing_length_cap() -> void:
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(_cleared_draft())["payload"]
	(payload["draft_fields"] as Dictionary)["author_notes"] = "A".repeat(RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH + 50)
	var validated := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_true(validated["ok"], "a too long message is cut, not rejected (same as loading a saved stage)")
	assert_eq((validated["draft"] as RBMCreatorDraft).author_notes.length(), RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH)

func test_build_for_publish_battle_hash_ignores_cosmetic_fields() -> void:
	var draft_a := _cleared_draft()
	var draft_b := _cleared_draft()
	draft_b.battle_background = "day" if draft_a.battle_background != "day" else "night"
	draft_b.appearance_id = "totally_different_appearance"
	var hash_a: String = RBMOnlineBossPayload.build_for_publish(draft_a)["payload"]["battle_hash"]
	var hash_b: String = RBMOnlineBossPayload.build_for_publish(draft_b)["payload"]["battle_hash"]
	assert_eq(hash_a, hash_b, "background/appearance must not affect battle_hash, matching battle_content_snapshot()'s own contract")

func test_build_for_publish_battle_hash_changes_when_battle_content_changes() -> void:
	var draft_a := _cleared_draft()
	var draft_b := _playable_draft()
	draft_b.hp = 2000
	draft_b.record_clear_check_success()
	var hash_a: String = RBMOnlineBossPayload.build_for_publish(draft_a)["payload"]["battle_hash"]
	var hash_b: String = RBMOnlineBossPayload.build_for_publish(draft_b)["payload"]["battle_hash"]
	assert_ne(hash_a, hash_b)

# ---------------------------------------------------------------------------
# validate_for_challenge
# ---------------------------------------------------------------------------

func _valid_payload() -> Dictionary:
	var draft := _cleared_draft()
	return RBMOnlineBossPayload.build_for_publish(draft)["payload"]

func test_validate_for_challenge_accepts_a_well_formed_payload() -> void:
	var result := RBMOnlineBossPayload.validate_for_challenge(_valid_payload())
	assert_true(result["ok"])
	assert_true(result["draft"] is RBMCreatorDraft)

func test_validate_for_challenge_rejects_missing_schema_version() -> void:
	var payload := _valid_payload()
	payload.erase("schema_version")
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "unsupported_schema_version")

func test_validate_for_challenge_rejects_a_schema_version_newer_than_supported() -> void:
	var payload := _valid_payload()
	payload["schema_version"] = RBMOnlineBossPayload.MAX_SUPPORTED_SCHEMA_VERSION + 1
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "unsupported_schema_version")

func test_validate_for_challenge_rejects_missing_draft_fields() -> void:
	var payload := _valid_payload()
	payload.erase("draft_fields")
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "invalid_payload_shape")

func test_validate_for_challenge_rejects_a_malformed_skills_array() -> void:
	var payload := _valid_payload()
	(payload["draft_fields"] as Dictionary)["skills"] = "not an array"
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "invalid_payload_shape")

func test_validate_for_challenge_rejects_a_tampered_hp_value_via_hash_mismatch() -> void:
	var payload := _valid_payload()
	(payload["draft_fields"] as Dictionary)["hp"] = 999999
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "hash_mismatch")

func test_validate_for_challenge_rejects_a_tampered_battle_hash_field() -> void:
	var payload := _valid_payload()
	payload["battle_hash"] = "0000000000000000000000000000000000000000000000000000000000000000"
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "hash_mismatch")

func test_validate_for_challenge_rejects_missing_battle_hash() -> void:
	var payload := _valid_payload()
	payload.erase("battle_hash")
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "invalid_payload_shape")

func test_validate_for_challenge_rejects_a_definition_with_no_party() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "党なしボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.record_clear_check_success()
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(draft)["payload"]
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "definition_invalid")

## ボスHP最大値変更（99999）: battle_hashが内容と一致していても（＝改ざん
## 検知をすり抜けても）、hp自体がRBMDefinitionLoader.BOSS_HP_MAXを超える
## payloadはRBMDefinitionLoader.resolve()の時点でdefinition_invalidとして
## 拒否される——オンライン受信経路でも100000以上のHPが正規データとして
## 通らないことの直接確認。
func test_validate_for_challenge_rejects_hp_over_the_max_even_with_a_hash_that_matches_it() -> void:
	var draft := _playable_draft()
	draft.hp = RBMDefinitionLoader.BOSS_HP_MAX + 1
	draft.record_clear_check_success()
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(draft)["payload"]
	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_false(result["ok"])
	assert_eq(result["error"], "definition_invalid")

# ---------------------------------------------------------------------------
# Clear Check parity: the reconstructed draft must produce byte-identical
# battle content to the Maker's own Clear-Check-proven snapshot.
# ---------------------------------------------------------------------------

func test_reconstructed_draft_battle_content_snapshot_matches_the_makers_clear_check_snapshot() -> void:
	var maker_draft := _cleared_draft()
	var proven_snapshot := maker_draft.clear_check_snapshot_for_save()
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(maker_draft)["payload"]

	var result := RBMOnlineBossPayload.validate_for_challenge(payload)
	assert_true(result["ok"])
	var challenger_draft: RBMCreatorDraft = result["draft"]

	assert_eq(challenger_draft.battle_content_snapshot(), proven_snapshot)

func test_reconstructed_draft_produces_the_same_definition_as_the_makers_draft() -> void:
	var maker_draft := _cleared_draft()
	var payload: Dictionary = RBMOnlineBossPayload.build_for_publish(maker_draft)["payload"]
	var challenger_draft: RBMCreatorDraft = RBMOnlineBossPayload.validate_for_challenge(payload)["draft"]

	var maker_definition := maker_draft.to_definition()
	var challenger_definition := challenger_draft.to_definition()
	# boss_id is a locally-derived label (see _generate_boss_id()), not part of
	# reproducible battle content -- excluded from this comparison on purpose.
	(maker_definition["boss"] as Dictionary).erase("boss_id")
	(challenger_definition["boss"] as Dictionary).erase("boss_id")
	assert_eq(challenger_definition, maker_definition)
