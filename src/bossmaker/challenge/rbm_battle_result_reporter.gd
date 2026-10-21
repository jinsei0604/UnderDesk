class_name RBMBattleResultReporter
extends Node

## オンラインのボスとの戦闘の結果を、戦闘チケットでサーバーへ送る（2026-10-23）。RBMChallengeEntry の子。
##
## 戦闘チケット（サーバーが出す1回限りの札。Steam で確かめた本人・ボスに結びつく）:
## - 挑戦を始めた時の記録（record-challenge-attempt）の応答で、最初の戦闘のチケットを受け取る。
## - 戦闘が決着したら、そのチケットで結果を送り、同じ応答で次の戦闘のチケットを受け取る（「もう一度挑戦」で通信を増やさない）。
## - 途中でやり直した戦闘は結果が出ていないので、同じチケットを次の戦闘に使う。
## - 次のチケットが無いまま次の戦闘を始めた時だけ、issue-battle-ticket で1枚取りに行く。
## - チケットが取れなくても戦闘は止めない。チケットの無い戦闘の結果は数えられない（勝ちの討伐記録は旧来の経路で決める）。
## - サーバーがチケットに対応していない（旧版のサーバー・戻した時）と分かったら、その挑戦の間は取りに行かない。
##
## 送信待ち（RBMBattleResultOutbox）: 決着した結果に1つだけの id をつけて手元に残してから送る。通信が切れた・ゲームを終えた
## 結果は、次の機会（挑戦トップを開いた時・次の挑戦を始めた時。間隔は1分以上）に同じ id でまとめて送り直す（サーバーは
## 同じ結果を1回しか数えない）。数えた・数え済み・数えられない（チケットが違う・期限切れ）と答えが来たものだけを消す。
##
## 討伐記録（勝ちだけ）は、送った結果の応答（作者本人か・難関ボス討伐の認定・初回クリア時のクリア率）で決める
## （defeat_confirmed）。チケットが無かった・数えられなかった勝ちは defeat_without_ticket（旧来のクリアの記録で判断する）。
## 戦闘・乱数・行動順には触れない（確定した勝敗を受け取るだけ）。

## 送った勝ちが数えられた（または数え済み）。by_owner は真偽値か null、server_rate は数か null。
signal defeat_confirmed(context: Dictionary, by_owner: Variant, hard_awarded: bool, server_rate: Variant)
## チケットの無い勝ち・数えられなかった勝ち（旧来のクリアの記録で、討伐記録に数えるかを決める）。
signal defeat_without_ticket(boss_id: String, context: Dictionary)

## 送信待ちだけの送り直し（決着した直後の送信は除く）の最短の間隔。Supabase の無料枠への負荷を抑える。
const FLUSH_INTERVAL_MSEC := 60 * 1000

## RBMOnlineChallengeRecorder を返す Callable と、今のアカウントの RBMBattleResultOutbox を返す Callable（RBMChallengeEntry が渡す）。
var recorder_source: Callable
var outbox_source: Callable

var _session := 0
var _boss_id := ""
var _context: Dictionary = {}
## 次に決着する戦闘に使うチケット（空なら無い）。
var _battle_ticket := ""
## この挑戦の間に、チケットを持ってくるかもしれない通信の数（挑戦の記録・結果の送信・チケットの発行）。
var _ticket_requests := 0
## チケットの無いまま次の戦闘が始まった（今の通信が持ってこなければ、取りに行く）。
var _ticket_wanted := false
## サーバーがチケットに対応しているか（null = まだ分からない）。
var _tickets_supported: Variant = null
## この起動で入れた結果の控え（result_id → 挑戦の控え。討伐記録の判断に、挑戦の控えそのものを使う）。
var _live_contexts: Dictionary = {}
## 手元に書けなかった結果（ディスクの失敗など。この起動の間だけメモリに持って送る）。
var _unsaved: Array = []
var _flushing := false
var _flush_again := false
var _next_ticket_wanted := false
var _last_flush_msec := -1

func _recorder() -> RBMOnlineChallengeRecorder:
	return recorder_source.call()

func _outbox() -> RBMBattleResultOutbox:
	return outbox_source.call()

## 今の挑戦のボス（無ければ空）。
func boss_id() -> String:
	return _boss_id

## 次の戦闘に使うチケットを持っているか（テスト・検証用）。
func has_battle_ticket() -> bool:
	return not _battle_ticket.is_empty()

## オンラインのボスの挑戦を始めた時: 挑戦の記録を送り、最初の戦闘のチケットを受け取る。context は討伐記録の控え
## （attempt_by_owner をここで入れる）。
func begin_challenge(boss_id: String, context: Dictionary) -> void:
	_session += 1
	_boss_id = boss_id
	_context = context
	_battle_ticket = ""
	_ticket_requests = 1
	_ticket_wanted = false
	_tickets_supported = null
	var session := _session
	var response: Dictionary = await _recorder().record_challenge_attempt(boss_id)
	if not context.is_empty():
		context["attempt_by_owner"] = RBMChallengeEntry.server_by_owner(response)
	if session != _session:
		return
	_ticket_requests -= 1
	if bool(response.get("ok", false)):
		var ticket := str(response.get("battle_ticket", "")) if response.get("battle_ticket", null) is String else ""
		# 挑戦の記録は成功したのに、チケットもその理由も無い → チケットに対応していないサーバー
		_tickets_supported = not ticket.is_empty() or response.has("ticket_status")
		_accept_ticket(session, ticket)
	_after_ticket_request()

## 挑戦をやめた・一覧へ戻った時。届いていない結果は送信待ちに残る。
func end_challenge() -> void:
	_session += 1
	_boss_id = ""
	_context = {}
	_battle_ticket = ""
	_ticket_requests = 0
	_ticket_wanted = false

## 戦闘画面で新しい戦闘を始めた時（「もう一度挑戦」「最初からやり直す」）。
func on_battle_restarted() -> void:
	if _boss_id.is_empty() or not _battle_ticket.is_empty() or _tickets_supported == false:
		return
	if _ticket_requests > 0:
		_ticket_wanted = true
		return
	_request_ticket()

## 戦闘が決着した時（1戦闘1回）。チケットがあれば結果を送信待ちに入れて送る。
func on_battle_decided(won: bool) -> void:
	if _boss_id.is_empty():
		return
	var ticket := _battle_ticket
	_battle_ticket = ""
	if ticket.is_empty():
		if won:
			defeat_without_ticket.emit(_boss_id, _context)
		return
	var entry := RBMBattleResultOutbox.make_entry(_boss_id, ticket, won, _context)
	_live_contexts[str(entry.result_id)] = _context
	if not _outbox().add(entry):
		_unsaved.append(entry)
	flush(true)

## 送信待ちがあり、前に送ってから間隔が空いていれば送る（挑戦トップを開いた時・挑戦を始めた時）。
func flush_if_due() -> void:
	if _flushing:
		return
	if _last_flush_msec >= 0 and Time.get_ticks_msec() - _last_flush_msec < FLUSH_INTERVAL_MSEC:
		return
	if _outbox().entries().is_empty() and _unsaved.is_empty():
		return
	flush()

## 送信待ちを送る（最大20件ずつ）。want_next_ticket なら、今の挑戦のボスの次のチケットも同じ応答で受け取る。
func flush(want_next_ticket: bool = false) -> void:
	if want_next_ticket:
		_next_ticket_wanted = true
	if _flushing:
		_flush_again = true
		return
	var box := _outbox()
	var pending := box.entries()
	pending.append_array(_unsaved)
	var next_boss := _boss_id if _next_ticket_wanted and _tickets_supported != false else ""
	_next_ticket_wanted = false
	if pending.is_empty() and next_boss.is_empty():
		return
	_flushing = true
	var session := _session
	if not next_boss.is_empty():
		_ticket_requests += 1
	var batch := pending.slice(0, RBMBattleResultOutbox.SEND_BATCH)
	var payload: Array = []
	for e in batch:
		payload.append({"boss_id": e.boss_id, "battle_ticket": e.battle_ticket, "result_id": e.result_id, "outcome": e.outcome})
	var response: Dictionary = await _recorder().submit_battle_results(payload, next_boss)
	_last_flush_msec = Time.get_ticks_msec()
	_flushing = false
	var ok := bool(response.get("ok", false)) and response.get("results", null) is Array
	if ok:
		_apply_results(box, batch, response["results"])
	if not next_boss.is_empty() and session == _session:
		_ticket_requests -= 1
		if ok:
			_accept_ticket(session, str(response.get("next_battle_ticket", "")) if response.get("next_battle_ticket", null) is String else "")
		_after_ticket_request()
	if _flush_again or _next_ticket_wanted or (ok and pending.size() > batch.size()):
		_flush_again = false
		flush()

## 1件ごとの答え: 数えた・数え済み → 消して討伐記録へ。数えられない（invalid・used・expired）→ 消す（勝ちは旧来の経路で
## 討伐記録を決める）。それ以外（error・答えが無い）→ 残して後で送り直す。
func _apply_results(box: RBMBattleResultOutbox, batch: Array, results: Array) -> void:
	var by_id := {}
	for e in batch:
		by_id[str(e.result_id)] = e
	var done: Array = []
	for r in results:
		if not r is Dictionary or not by_id.has(str(r.get("result_id", ""))):
			continue
		var rid := str(r.result_id)
		var entry: Dictionary = by_id[rid]
		var status := str(r.get("status", ""))
		if status == "counted" or status == "duplicate":
			done.append(rid)
			if str(entry.outcome) == "clear":
				var rate: Variant = r.get("first_clear_rate", null)
				defeat_confirmed.emit(_context_of(entry), r.get("by_owner", null) if r.get("by_owner", null) is bool else null,
					r.get("hard_awarded", false) is bool and bool(r.get("hard_awarded", false)),
					clampf(float(rate), 0.0, 1.0) if (rate is float or rate is int) else null)
		elif status == "invalid" or status == "used" or status == "expired":
			done.append(rid)
			if str(entry.outcome) == "clear":
				defeat_without_ticket.emit(str(entry.boss_id), _context_of(entry))
	for rid in done:
		_live_contexts.erase(rid)
	_unsaved = _unsaved.filter(func(e): return not done.has(str(e.result_id)))
	box.remove(done)

## 討伐記録の控え: この起動で入れた結果なら挑戦の控えそのもの（空なら空のまま = 記録しない）、前の起動の結果なら
## 送信待ちに残した値から作る。
func _context_of(entry: Dictionary) -> Dictionary:
	if _live_contexts.has(str(entry.result_id)):
		var c: Dictionary = _live_contexts[str(entry.result_id)]
		if not c.is_empty():
			c["at"] = int(entry.get("at", -1))
		return c
	return {"boss_id": str(entry.boss_id), "mode": str(entry.get("mode", "")), "rate": float(entry.get("rate", -1.0)),
		"attempt_by_owner": entry.get("attempt_by_owner", null) if entry.get("attempt_by_owner", null) is bool else null,
		"published_here": bool(entry.get("published_here", false)), "at": int(entry.get("at", -1))}

func _request_ticket() -> void:
	_ticket_requests += 1
	var session := _session
	var boss := _boss_id
	var response: Dictionary = await _recorder().issue_battle_ticket(boss)
	if session != _session:
		return
	_ticket_requests -= 1
	if bool(response.get("ok", false)) and response.get("battle_ticket", null) is String:
		_accept_ticket(session, str(response.battle_ticket))
	_after_ticket_request()

func _accept_ticket(session: int, ticket: String) -> void:
	if session == _session and not ticket.is_empty() and _battle_ticket.is_empty():
		_battle_ticket = ticket

## 通信が終わった時: チケットの無いまま次の戦闘が始まっていて、もう持ってくる通信が無ければ、1回だけ取りに行く。
func _after_ticket_request() -> void:
	if not _battle_ticket.is_empty():
		_ticket_wanted = false
		return
	if _ticket_requests == 0 and _ticket_wanted and _tickets_supported != false:
		_ticket_wanted = false
		_request_ticket()
