class_name RBMBattleResultOutbox
extends RefCounted

## 決着した戦闘の結果の送信待ち（2026-10-23）。オンラインのボスとの戦闘が決着したら、結果（勝ち・負け）に
## 1つだけの id（UUID）をつけてここへ入れてから送る。届いたと分かった（サーバーが数えた・数え済みと答えた・数えられない
## と答えた）ものだけを消し、通信が切れた・ゲームを終えたものは残して、次の機会（挑戦トップ・次の挑戦の開始）に同じ id で
## 送り直す。サーバーは同じ結果を1回しか数えない（submit-battle-result）。
## - アカウントごとの手元のファイル: <stages の隣>/battle_results/<アカウント>.json（書き込みは一時ファイルからの置き換え）。
##   Steam Cloud には入れない（ほかの PC が同じ結果を送り直しても、サーバーは1回しか数えないので害は無い）。
## - サーバーのチケットの期限（30日）を過ぎたものは、サーバーでも受け付けられないので捨てる。手元に残すのは最大200件
##   （古いものから捨てる）。
## - persistent = false（保存先を分けていないヘッドレスのテスト）は、ファイルに書かずにメモリにだけ持つ。
## 戦闘・乱数・ステージの保存データ・討伐記録には触れない（討伐記録は、送った結果の応答で RBMChallengeEntry が決める）。

const FORMAT := "rbm_battle_result_outbox"
const VERSION := 1
const SUBDIR_NAME := "battle_results"
## サーバーの戦闘チケットの期限と同じ（秒）。
const KEEP_SECONDS := 30 * 24 * 3600
## 1回の送信に入れる数（サーバーの上限と同じ）。
const SEND_BATCH := 20
const MAX_ENTRIES := 200

var account_id := RBMDefeatRecord.LOCAL_ACCOUNT
var persistent := true
## メモリだけの時の中身（persistent = false）。
var _memory: Array = []

func _init(account: String = RBMDefeatRecord.LOCAL_ACCOUNT, persist: bool = true) -> void:
	account_id = RBMDefeatRecord.sanitize_account(account)
	persistent = persist

static func outbox_dir() -> String:
	return RBMLocalStageRepository.stages_dir().get_base_dir() + "/" + SUBDIR_NAME

func path() -> String:
	return "%s/%s.json" % [outbox_dir(), account_id]

## 新しい結果の id（UUID v4）。
static func new_result_id() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]

## 送信待ちの1件。context は討伐記録の判断に要る控え（mode・rate・attempt_by_owner・published_here）。
static func make_entry(boss_id: String, battle_ticket: String, won: bool, context: Dictionary, at_unix: int = -1) -> Dictionary:
	return {
		"result_id": new_result_id(),
		"boss_id": boss_id,
		"battle_ticket": battle_ticket,
		"outcome": "clear" if won else "loss",
		"mode": str(context.get("mode", "")),
		"rate": float(context.get("rate", -1.0)),
		"attempt_by_owner": context.get("attempt_by_owner", null) if context.get("attempt_by_owner", null) is bool else null,
		"published_here": bool(context.get("published_here", false)),
		"at": at_unix if at_unix >= 0 else int(Time.get_unix_time_from_system()),
	}

static func _valid(e: Variant) -> bool:
	if not e is Dictionary:
		return false
	for key in ["result_id", "boss_id", "battle_ticket", "outcome"]:
		if not (e as Dictionary).get(key, null) is String or str(e[key]).is_empty():
			return false
	return str(e.outcome) == "clear" or str(e.outcome) == "loss"

## 今の送信待ち（古い順）。壊れた行・期限を過ぎた行は除く（除いたら書き直す）。
func entries(now_unix: int = -1) -> Array:
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var raw := _read()
	var kept: Array = []
	for e in raw:
		if _valid(e) and now - int((e as Dictionary).get("at", 0)) <= KEEP_SECONDS:
			kept.append(e)
	if kept.size() != raw.size():
		_write(kept)
	return kept

## 1件入れる（同じ id はもう一度入れない）。上限を超えたら古いものから捨てる。手元に書けたら true。
func add(entry: Dictionary) -> bool:
	if not _valid(entry):
		return false
	var list := entries()
	for e in list:
		if str(e.result_id) == str(entry.result_id):
			return true
	list.append(entry)
	while list.size() > MAX_ENTRIES:
		list.pop_front()
	return _write(list)

## 届いたと分かった結果を消す。
func remove(result_ids: Array) -> void:
	if result_ids.is_empty():
		return
	var gone := {}
	for id in result_ids:
		gone[str(id)] = true
	var list := entries()
	var kept: Array = []
	for e in list:
		if not gone.has(str(e.result_id)):
			kept.append(e)
	if kept.size() != list.size():
		_write(kept)

func _read() -> Array:
	if not persistent:
		return _memory.duplicate(true)
	var p := path()
	if not FileAccess.file_exists(p):
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) != OK or not json.data is Dictionary or str(json.data.get("format", "")) != FORMAT \
			or not json.data.get("results", null) is Array:
		# 壊れた送信待ちは消さずに脇へ避ける（討伐記録と同じ）
		DirAccess.rename_absolute(p, p + ".corrupt.%d" % int(Time.get_unix_time_from_system()))
		return []
	return json.data.results

func _write(list: Array) -> bool:
	if not persistent:
		_memory = list.duplicate(true)
		return true
	var data := {"format": FORMAT, "version": VERSION, "account": account_id, "results": list}
	return RBMLocalStageRepository._atomic_write(path(), JSON.stringify(data, "\t", false))
