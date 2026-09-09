class_name RBMOnlineChallengeLoader
extends RefCounted

## Phase 4D — 選択したオンラインボスを、既存Challengeが使う
## Draft/Definition/Battle経路へ安全に接続する。新しい別Battleエンジンは
## 作らない(ユーザー確定仕様)。
##
## 経路(§4D-3): 詳細取得 → validation → schema_version確認 →
## battle_hash確認 → Challenge用データへ変換。この順序は
## RBMOnlineBossPayload.validate_for_challenge()が内部で担う
## (schema_version確認 → 型検証 → battle_hash再計算・突合 →
## RBMDefinitionLoader.resolve()による意味検証)。

static func load_boss_for_challenge(api_adapter: RBMBossApiAdapter, boss_id: String) -> Dictionary:
	var response: Dictionary = await api_adapter.get_boss(boss_id)
	if not bool(response.get("ok", false)):
		return {
			"ok": false,
			"error": str(response.get("error_kind", "network_error")),
			"message": str(response.get("message", "")),
		}

	var boss_row_variant: Variant = response.get("boss", null)
	if not (boss_row_variant is Dictionary):
		return {"ok": false, "error": "invalid_response", "message": "Server response was missing 'boss'"}
	var boss_row: Dictionary = boss_row_variant

	var payload_variant: Variant = boss_row.get("payload", null)
	if not (payload_variant is Dictionary):
		return {"ok": false, "error": "invalid_payload", "message": "Server response was missing 'payload'"}

	var validated := RBMOnlineBossPayload.validate_for_challenge(payload_variant)
	if not bool(validated.get("ok", false)):
		return {
			"ok": false,
			"error": str(validated.get("error", "invalid_payload")),
			"message": str(validated.get("details", "")),
		}

	return {
		"ok": true,
		"draft": validated["draft"],
		"boss_id": str(boss_row.get("id", boss_id)),
		"boss_name": str(boss_row.get("boss_name", "")),
		"author_name": str(boss_row.get("author_name", "")),
		"revision": int(boss_row.get("revision", 1)),
	}
