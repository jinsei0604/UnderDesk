extends SceneTree

## Phase 4A-1 — Steam認証基盤の実機確認スクリプト(手動実行専用)。
## tools/supabase_poc/verify_connection.gdと同じ実行パターン
## (「実際のSteam通信を毎回行うテストだけに依存しない」——オフラインで
## 検証できるロジックはGUT側、実Steamクライアントが必要なこの確認だけを
## ここへ分離してある)。
##
## §重要: AppID 480(ValveのSpacewar開発確認用)はあくまで開発確認用途。
## ここで確認できるのは、Steam初期化・ログイン状態・SteamID64取得・
## persona name取得・GetAuthTicketForWebApi呼び出し・callback受信・
## ticket生成・hex変換・CancelAuthTicketまで——
## 「Makers & Challengers本番認証(AuthenticateUserTicket)の成功」は
## 正式AppID取得後のPhase 4A-2の確認範囲であり、ここでは確認しない。
##
## 事前準備:
##   1. Steamクライアントを起動し、ログインしておく。
##   2. steam_dev_appid.local.txt に 480 (または保有しているAppID)を
##      書いておく(.gitignore対象、正式AppIDは書かない)。
##   3. steam_appid.txt (プロジェクトルート、.gitignore対象)にも同じ
##      値を置いておく——GodotSteamがsteam_appid.txt規約を併用する
##      実装でも動くようにするための保険。
##
## 実行(headlessでは動かない、実Steamクライアントとの通信が必要):
##   godot --path . -s res://tools/steam_poc/verify_steam_init.gd

var _auth: RBMSteamAuth
var _timed_out := false

func _init() -> void:
	print("Steam認証基盤 実機確認PoC(AppID 480開発確認用) — 開始します")
	print("§注意: これはPhase 4A-2の本番認証確認ではありません。")

	if not RBMSteamConfig.is_configured():
		printerr("STEAM_APP_ID未設定です。steam_dev_appid.local.txt に開発用AppID(480等)を書いてください。")
		quit(1)
		return

	if RBMSteamConfig.app_id() == RBMSteamConfig.OFFICIAL_APP_ID and RBMSteamConfig.OFFICIAL_APP_ID != 0:
		printerr("OFFICIAL_APP_IDが設定されています。このPoCは開発用AppIDでのみ実行してください。")
		quit(1)
		return

	print("① 使用するAppID: %d (開発用オーバーライド: %s)" % [RBMSteamConfig.app_id(), RBMSteamConfig.is_using_development_override()])

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

	print("④ SteamID64(文字列): %s" % _auth.steam_id())
	print("⑤ persona name: %s" % _auth.persona_name())

	print("⑥ GetAuthTicketForWebApiを呼びます(identity=%s)..." % RBMSteamAuth.WEB_API_IDENTITY)
	if not _auth.request_web_api_ticket():
		printerr("request_web_api_ticket()が開始できませんでした。")
		quit(1)
		return

	# ここから先はticket_ready/ticket_failedシグナル待ち——通常のフレーム
	# 処理でRBMSteamAuth._process()がrun_callbacks()を回し続けるので、
	# このSceneTreeスクリプト自身が能動的に何かをする必要はない。

func _on_ticket_ready(hex_ticket: String) -> void:
	print("⑦ callback受信: ticket取得成功")
	print("⑧ hex変換結果(先頭32文字のみ表示): %s..." % hex_ticket.substr(0, 32))
	print("   hex文字列の長さ: %d" % hex_ticket.length())
	var consumed := _auth.consume_ticket_hex()
	print("⑨ consume_ticket_hex()で一度だけ取得: %s" % (consumed.length() > 0))
	print("⑩ 二度目のconsume_ticket_hex(): '%s' (空文字であるべき)" % _auth.consume_ticket_hex())
	_auth.complete_ticket()
	print("⑪ complete_ticket()でCancelAuthTicket相当を実行、状態: %s" % _auth.current_auth_state())
	print("=== 実機確認 PASS(AppID 480開発確認の範囲内) ===")
	print("§注意: AuthenticateUserTicketによるMakers & Challengers本番認証はPhase 4A-2で確認します。")
	quit(0)

func _on_ticket_failed(reason: String) -> void:
	printerr("callback失敗またはtimeout: %s" % reason)
	print("=== 実機確認 FAIL ===")
	quit(1)
