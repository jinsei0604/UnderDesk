class_name RBMOnlineErrorText
extends RefCounted

## 通信の失敗を、遊ぶ人が読める文にする（2026-10-17、プレイ体験監査 PX-14・QA-23）。
## 以前は「通信エラー（network_error）」のように内部の error_kind がそのまま主な文として出ていた。
## 主な文は人が読める文にし、内部の error_kind は問い合わせ用に最後へ小さく添える（UI_UX §8）。
## 通信・判定の処理は変えない（応答の Dictionary を読むだけ）。

## 応答（{"ok": false, "error_kind": ..., "message": ...}）から、遊ぶ人向けの文を作る。
static func describe(response: Dictionary) -> String:
	var kind := error_kind_of(response)
	match kind:
		"steam_unavailable", "steam_not_logged_on":
			# RBMSteamTicketProvider が既に人の読める文（翻訳済み）を message に入れている
			var message := str(response.get("message", ""))
			return message if not message.is_empty() else TranslationServer.translate("Steamが利用できません。Steamを起動してログインしてください。")
		"steam_ticket_request_failed", "steam_ticket_failed":
			return TranslationServer.translate("Steamとの認証に失敗しました。Steamを起動し直して、もう一度お試しください。")
		"http_5xx":
			return TranslationServer.translate("サーバーが応答できない状態です。しばらくしてからもう一度お試しください。")
		"not_found":
			return TranslationServer.translate("見つかりませんでした。公開が取り下げられた可能性があります。")
		"unsupported_schema_version":
			return TranslationServer.translate("このボスは新しい版のゲームで作られています。ゲームを最新にしてください。")
		"invalid_response", "invalid_payload", "invalid_payload_shape", "hash_mismatch", "definition_invalid":
			return TranslationServer.translate("このボスのデータを読み込めませんでした。")
		"network_error", "":
			return TranslationServer.translate("通信できませんでした。インターネットへの接続を確かめて、もう一度お試しください。")
		_:
			return TranslationServer.translate("通信がうまくいきませんでした。もう一度お試しください。")

## 問い合わせ用の小さな1行（内部の error_kind）。
static func code_line(response: Dictionary) -> String:
	return TranslationServer.translate("（エラー: %s）") % error_kind_of(response)

## 主な文と、小さな1行をまとめたもの（1つのラベルに出す時）。
static func full_text(response: Dictionary) -> String:
	return "%s\n%s" % [describe(response), code_line(response)]

static func error_kind_of(response: Dictionary) -> String:
	var kind := str(response.get("error_kind", response.get("error", "")))
	if kind.is_empty():
		kind = str(response.get("message", ""))
	return kind if not kind.is_empty() else "unknown"
