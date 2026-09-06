class_name RBMSupabaseResponse
extends RefCounted

## Supabase最小接続PoC §7/§8 — HTTPレスポンス(response_code + body)の解釈だけを
## 行う純粋関数の集合。RBMSupabaseClient（実際にHTTPRequestを飛ばす側）から
## 意図的に分離してある——「実際のSupabase通信を毎回行うテストだけに依存
## しない」(§7)ため、この解釈ロジックだけをネットワーク無しで直接テスト
## できるようにするための切り出し。
##
## 戻り値は常にこの形のDictionary:
##   ok: bool                — 成功したか
##   error_kind: String      — "" | "network_error" | "http_4xx" | "http_5xx"
##                              | "json_parse_failed"
##   http_status: int        — 実際のHTTPステータスコード（通信自体が失敗した
##                              場合は-1）
##   message: String         — デバッグ出力向けの人間可読な要約
##   supabase_message: String — レスポンス本文の"message"フィールド（あれば）
##   supabase_code: String    — レスポンス本文の"code"フィールド（あれば、
##                              PostgRESTのエラーコード等）
##   rows: Array              — 成功時、JSON配列としてパースした行データ
##
## §8「Publishable keyそのものをログへ出力しない」——この関数群はkey自体を
## 一切引数に取らない設計なので、呼び出し側がkeyを混入させない限り構造的に
## 安全。

## HTTPRequest.request()自体がError（OK以外）を返した場合——DNS失敗や
## URL不正等、リクエストがネットワークへ出る前に失敗したケース。
static func network_error(reason: String) -> Dictionary:
	return {
		"ok": false,
		"error_kind": "network_error",
		"http_status": -1,
		"message": "ネットワークエラー: %s" % reason,
		"supabase_message": "",
		"supabase_code": "",
		"rows": [],
	}

## HTTPRequest.request_completed信号を受けた後の実際のレスポンス解釈。
static func parse(response_code: int, body: PackedByteArray) -> Dictionary:
	var body_text := body.get_string_from_utf8()

	if response_code >= 500:
		var parsed_5xx := _try_parse_supabase_error(body_text)
		return {
			"ok": false,
			"error_kind": "http_5xx",
			"http_status": response_code,
			"message": "Supabaseサーバーエラー (HTTP %d)" % response_code,
			"supabase_message": parsed_5xx.get("message", ""),
			"supabase_code": parsed_5xx.get("code", ""),
			"rows": [],
		}

	if response_code >= 400:
		var parsed_4xx := _try_parse_supabase_error(body_text)
		return {
			"ok": false,
			"error_kind": "http_4xx",
			"http_status": response_code,
			"message": "リクエストエラー (HTTP %d)" % response_code,
			"supabase_message": parsed_4xx.get("message", ""),
			"supabase_code": parsed_4xx.get("code", ""),
			"rows": [],
		}

	# 200番台——成功。PostgRESTは成功時、行の配列（Prefer: return=representation
	# 付きINSERT、または通常のSELECT）をJSON配列として返す。204 No Content
	# （Preferヘッダ無しINSERT等、本文が空）はrows=[]の成功として扱う。
	if body_text.strip_edges().is_empty():
		return {
			"ok": true,
			"error_kind": "",
			"http_status": response_code,
			"message": "成功（本文なし）",
			"supabase_message": "",
			"supabase_code": "",
			"rows": [],
		}

	var json := JSON.new()
	if json.parse(body_text) != OK:
		return {
			"ok": false,
			"error_kind": "json_parse_failed",
			"http_status": response_code,
			"message": "JSON解析に失敗しました: %s" % json.get_error_message(),
			"supabase_message": "",
			"supabase_code": "",
			"rows": [],
		}

	var parsed: Variant = json.get_data()
	var rows: Array = parsed if parsed is Array else [parsed]
	return {
		"ok": true,
		"error_kind": "",
		"http_status": response_code,
		"message": "成功（%d件）" % rows.size(),
		"supabase_message": "",
		"supabase_code": "",
		"rows": rows,
	}

## PostgREST/Supabaseのエラー本文は通常 {"message": "...", "code": "..."} の
## 形——解析に失敗しても（本文が空、HTMLエラーページ等）静かに空文字列を
## 返すだけで、呼び出し元のhttp_4xx/5xx判定自体は既に確定しているため実害
## なし（このプロジェクト全体の「壊れていても静かにフォールバックする」
## 既存方針、RBMLocalStageRepository.read_stage_stats()と同じ流儀）。
static func _try_parse_supabase_error(body_text: String) -> Dictionary:
	if body_text.strip_edges().is_empty():
		return {}
	var json := JSON.new()
	if json.parse(body_text) != OK:
		return {}
	var parsed: Variant = json.get_data()
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	return {
		"message": str(data.get("message", "")),
		"code": str(data.get("code", "")),
	}
