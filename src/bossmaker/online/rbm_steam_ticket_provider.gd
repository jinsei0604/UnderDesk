class_name RBMSteamTicketProvider
extends RefCounted

## Phase 5 — publish/unpublish(RBMBossPublisher)と、オンライン挑戦記録
## (attempt/clear)・未挑戦一覧取得(RBMOnlineChallengeRecorder)が共有する、
## Steam ticket取得の最小手順だけを持つ純粋なヘルパー。
##
## RBMBossPublisher.PublishStateのような呼び出し側固有の状態機械・signal
## には一切関与しない——「利用可能性を確認し、ticketを要求し、callbackを
## 待って結果を返すだけ」の手順のみを持つ(既存のRBMBossPublisher.
## _acquire_ticket()/_await_ticket_result()と同じロジックをここへ集約し、
## 呼び出し側ごとの単純コピーを増やさない)。
##
## 戻り値: {"ok": true, "hex": String} または
##         {"ok": false, "error_kind": String, "message": String}

## 静的関数からはインスタンスメソッドtr()を呼べないため、
## TranslationServer.translate()を直接使う(RBMChallengeUiKit等、この
## プロジェクトの他の静的/純粋関数群と同じ既存パターン)。
static func acquire_ticket(steam_auth: RBMSteamAuth) -> Dictionary:
	if not steam_auth.is_available():
		return {"ok": false, "error_kind": "steam_unavailable", "message": TranslationServer.translate("Steamが利用できません。Steamを起動してログインしてください。")}
	if not steam_auth.is_logged_on():
		return {"ok": false, "error_kind": "steam_not_logged_on", "message": TranslationServer.translate("Steamにログインしていません。")}

	if not steam_auth.request_web_api_ticket():
		return {"ok": false, "error_kind": "steam_ticket_request_failed", "message": steam_auth.failure_reason()}

	# `while true`はbreak無しでは自然に抜けないが、GDScriptの静的解析は
	# ループ後の明示的なreturnを要求する(RBMBossPublisher._await_ticket_result()
	# に元々あった注釈と同じ理由)。
	while true:
		var state: RBMSteamAuth.AuthState = steam_auth.current_auth_state()
		if state == RBMSteamAuth.AuthState.READY:
			return {"ok": true, "hex": steam_auth.consume_ticket_hex()}
		if state == RBMSteamAuth.AuthState.FAILED or state == RBMSteamAuth.AuthState.CANCELLED:
			return {"ok": false, "error_kind": "steam_ticket_failed", "message": steam_auth.failure_reason()}
		await steam_auth.state_changed
	return {"ok": false, "error_kind": "unreachable", "message": ""}
