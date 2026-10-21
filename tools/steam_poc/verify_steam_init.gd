extends SceneTree

## Steam 連携の実機確認スクリプト（手動実行専用。2026-10-21 に正式 AppID 5482410 へ更新）。
## tools/supabase_poc/verify_connection.gdと同じ実行パターン
## (「実際のSteam通信を毎回行うテストだけに依存しない」——オフラインで
## 検証できるロジックはGUT側、実Steamクライアントが必要なこの確認だけを
## ここへ分離してある)。
##
## 確かめること（クライアント側だけ）: Steam 初期化（RBMSteamConfig の AppID）・ログイン状態・このアカウントが
## アプリを持っているか・SteamID64 の取得・表示名の取得・GetAuthTicketForWebApi の呼び出し・callback の受信・
## ticket の hex 変換・一度だけ取り出せること・CancelAuthTicket。Steam Cloud は状態を読むだけ（書き込まない）。
## サーバーでの ticket の検証（AuthenticateUserTicket）は、書き出した版の tools/verify_export_online.gd --steam=1 で確かめる。
## SteamID と表示名は個人の情報なので、全部は出さない（SteamID は前後だけ、表示名は取れたかどうかだけ）。
##
## 事前準備: Steam クライアントを起動し、ログインしておく（AppID は RBMSteamConfig の正式値。試す時だけ
## steam_dev_appid.local.txt で上書きできる）。
##
## 実行（リポジトリの直下。窓のある起動で、本物の Steam クライアントと通信する）:
##   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/steam_poc/verify_steam_init.gd

var _auth: RBMSteamAuth
var _timed_out := false

func _init() -> void:
	print("Steam 連携 実機確認 — 開始します")

	if not RBMSteamConfig.is_configured():
		printerr("AppID が未設定です（RBMSteamConfig）。")
		quit(1)
		return

	print("① 使用するAppID: %d (正式値: %s / 開発用の上書き: %s)" % [RBMSteamConfig.app_id(),
		RBMSteamConfig.app_id() == RBMSteamConfig.OFFICIAL_APP_ID, RBMSteamConfig.is_using_development_override()])

	_auth = RBMSteamAuth.new()
	root.add_child(_auth)
	_auth.ticket_ready.connect(_on_ticket_ready)
	_auth.ticket_failed.connect(_on_ticket_failed)
	# _init()の同期実行中はまだ最初のフレーム処理前——実際のゲーム内での
	# 利用(ボタン押下等、常にフレーム処理後に起こる)と同じ状況にしてから
	# 進める。
	await process_frame

	var init_result := _auth.initialize()
	print("② Steam初期化結果: %s" % [init_result])

	if not _auth.is_available():
		printerr("Steamが利用できません(起動していない、または初期化失敗)。status=%s" % [init_result.get("status", -1)])
		print("=== 実機確認 結果: Steam利用不可のため以降は未確認(これ自体は安全なフォールバックとして正しい挙動) ===")
		quit(1)
		return

	print("③ Steamログイン状態: %s" % _auth.is_logged_on())
	if not _auth.is_logged_on():
		printerr("Steamにログインしていません。Steamクライアントへログインしてから再実行してください。")
		quit(1)
		return

	var steam: Object = Engine.get_singleton("Steam")
	print("③-2 GodotSteam: %s / このアカウントがアプリを持っている(isSubscribed): %s" % [
		steam.get_godotsteam_version() if steam.has_method("get_godotsteam_version") else "?", steam.isSubscribed()])
	print("④ SteamID64: %s（前後だけ表示）" % _mask(_auth.steam_id()))
	print("⑤ persona name: 取得できた=%s" % (not _auth.persona_name().is_empty()))
	_print_cloud_status(steam)

	print("⑥ GetAuthTicketForWebApiを呼びます(identity=%s)..." % RBMSteamAuth.WEB_API_IDENTITY)
	if not _auth.request_web_api_ticket():
		printerr("request_web_api_ticket()が開始できませんでした。")
		quit(1)
		return

	# ここから先はticket_ready/ticket_failedシグナル待ち——通常のフレーム
	# 処理でRBMSteamAuth._process()がrun_callbacks()を回し続けるので、
	# このSceneTreeスクリプト自身が能動的に何かをする必要はない。

## Steam Cloud の状態を読むだけ（ファイルの書き込み・削除・同期の操作はしない）。
func _print_cloud_status(steam: Object) -> void:
	var quota: Dictionary = steam.getQuota()
	print("⑤-2 Steam Cloud: アカウントで有効=%s / このアプリで有効=%s / 容量 total=%s available=%s / ファイル数=%s" % [
		steam.isCloudEnabledForAccount(), steam.isCloudEnabledForApp(),
		quota.get("total_bytes", "?"), quota.get("available_bytes", "?"), steam.getFileCount()])

func _mask(steam_id: String) -> String:
	if steam_id.length() < 8:
		return "(取得できない)" if steam_id.is_empty() else "****"
	return "%s…%s" % [steam_id.substr(0, 4), steam_id.substr(steam_id.length() - 3)]

func _on_ticket_ready(hex_ticket: String) -> void:
	print("⑦ callback受信: ticket取得成功")
	print("⑧ hex文字列の長さ: %d（中身は出さない）" % hex_ticket.length())
	var consumed := _auth.consume_ticket_hex()
	print("⑨ consume_ticket_hex()で一度だけ取得: %s" % (consumed.length() > 0))
	print("⑩ 二度目のconsume_ticket_hex(): '%s' (空文字であるべき)" % _auth.consume_ticket_hex())
	_auth.complete_ticket()
	print("⑪ complete_ticket()でCancelAuthTicket相当を実行、状態: %s" % _auth.current_auth_state())
	print("=== 実機確認 PASS（クライアント側: 初期化・SteamID・ticket の発行まで） ===")
	print("§注意: サーバーでの検証（AuthenticateUserTicket）は tools/verify_export_online.gd --steam=1 で確かめます。")
	quit(0)

func _on_ticket_failed(reason: String) -> void:
	printerr("callback失敗またはtimeout: %s" % reason)
	print("=== 実機確認 FAIL ===")
	quit(1)
