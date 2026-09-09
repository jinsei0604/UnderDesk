class_name RBMFakeBossApiAdapter
extends RBMBossApiAdapter

## Phase 4C/4D/4E — RBMBossApiAdapterと同じ公開面を持つテスト専用の偽実装。
## 実HTTPには一切触れない(RBMFakeSteamAdapterと同じ既存パターン)。
## テストが`configure_*`で応答をあらかじめ用意し、呼ばれた引数を記録する。

var _publish_response: Dictionary = {"ok": true, "boss_id": "fake-boss-id", "revision": 1}
var _unpublish_response: Dictionary = {"ok": true}
var _list_response: Dictionary = {"ok": true, "bosses": []}
var _get_response: Dictionary = {"ok": true, "boss": {}}

var publish_calls: Array[Dictionary] = []
var unpublish_calls: Array[Dictionary] = []
var list_calls: Array[int] = []
var get_calls: Array[String] = []

func _ready() -> void:
	pass # 実HTTPRequestは作らない。

func configure_publish_response(response: Dictionary) -> void:
	_publish_response = response

func configure_unpublish_response(response: Dictionary) -> void:
	_unpublish_response = response

func configure_list_response(response: Dictionary) -> void:
	_list_response = response

func configure_get_response(response: Dictionary) -> void:
	_get_response = response

func publish(ticket_hex: String, payload: Dictionary, boss_id: String = "") -> Dictionary:
	publish_calls.append({"ticket": ticket_hex, "payload": payload, "boss_id": boss_id})
	return _publish_response.duplicate(true)

func unpublish(ticket_hex: String, boss_id: String) -> Dictionary:
	unpublish_calls.append({"ticket": ticket_hex, "boss_id": boss_id})
	return _unpublish_response.duplicate(true)

func list_bosses(limit: int = 20) -> Dictionary:
	list_calls.append(limit)
	return _list_response.duplicate(true)

func get_boss(id: String) -> Dictionary:
	get_calls.append(id)
	return _get_response.duplicate(true)
