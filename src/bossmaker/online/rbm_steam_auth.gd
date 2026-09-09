class_name RBMSteamAuth
extends Node

## Phase 4A-1 — Steam認証基盤（正式AppID発行前の下準備のみ）。
##
## 目的はGetAuthTicketForWebApi()によるticket取得だけ——実際のSteam側
## 本人確認(AuthenticateUserTicket)はEdge Function側でPhase 4A-2に行う
## （§重要「SteamIDをクライアントから信用しない」——このクラスが返す
## steam_id()はデバッグ比較用途のみで、本人確認の根拠にしない）。
##
## 既存のRBMSupabaseClientと同じ「呼び出し側がこのNodeをシーンツリーへ
## 追加する軽量Node」の流儀（新しいautoload/シングルトンは導入しない）。
## 実際のGodotSteamシングルトンには一切直接触れず、RBMSteamAdapter経由
## でのみアクセスする——headlessのGUTはRBMFakeSteamAdapterへ差し替えて
## テストする。
##
## 使い方:
##   var auth := RBMSteamAuth.new()
##   add_child(auth)
##   auth.initialize()
##   if auth.is_available() and auth.is_logged_on():
##       auth.request_web_api_ticket()
##       # ticket_ready(hex) / ticket_failed(reason) シグナルを待つ

## GetAuthTicketForWebApiのidentity——クライアントと将来のEdge Function
## 側で同じ文字列を使う、固定値（ユーザー確定仕様）。
const WEB_API_IDENTITY := "makers-and-challengers-backend"

## Steamのcallback(get_ticket_for_web_api)が永久に返らない場合に備える
## timeout。既定15秒——実際のSteamworks呼び出しは通常数秒以内に完了する。
const DEFAULT_TICKET_TIMEOUT_SECONDS := 15.0

enum AuthState {
	IDLE,        ## まだticketを要求していない、または前回のticketが完全に片付いた状態。
	REQUESTING,  ## getAuthTicketForWebApi()を呼び、callbackを待っている。
	READY,       ## callbackが成功で返り、hex ticketが使用可能。
	IN_USE,      ## consume_ticket_hex()で一度取り出し済み——再利用不可。
	COMPLETED,   ## 使用後、complete_ticket()でSteam側handleを解放済み。
	CANCELLED,   ## 明示的にcancel_ticket()された。
	FAILED,      ## callback失敗、timeout、Steam未初期化等。
}

signal state_changed(new_state: AuthState)
signal ticket_ready(hex_ticket: String)
signal ticket_failed(reason: String)

var timeout_seconds: float = DEFAULT_TICKET_TIMEOUT_SECONDS

var _adapter: RBMSteamAdapter
var _state: AuthState = AuthState.IDLE
var _init_result: Dictionary = {}
var _available := false
var _current_handle: int = 0
var _current_hex: String = ""
var _failure_reason: String = ""
var _timeout_timer: Timer

## _ready()には依存しない——SceneTreeスクリプトの_init()から
## add_child()直後にinitialize()を呼ぶ用途(tools/steam_poc/
## verify_steam_init.gd)では、_ready()通知がメインループ開始前のため
## 同期的に届かないことがある。initialize()自身の先頭で確実にセットアップ
## する(何度呼んでも安全な冪等処理)。
func _ensure_setup() -> void:
	if _adapter == null:
		_adapter = RBMSteamAdapter.new()
	if not _adapter.ticket_for_web_api_received.is_connected(_on_ticket_for_web_api_received):
		_adapter.ticket_for_web_api_received.connect(_on_ticket_for_web_api_received)
	if _timeout_timer == null:
		_timeout_timer = Timer.new()
		_timeout_timer.name = "TicketTimeoutTimer"
		_timeout_timer.one_shot = true
		_timeout_timer.timeout.connect(_on_timeout)
		add_child(_timeout_timer)

func _exit_tree() -> void:
	# ゲーム終了・scene change時、未解放のticketを必ずcancelする。
	_cancel_internal("node exiting tree")

## GUT専用: 実GodotSteamへ一切触れないRBMFakeSteamAdapterへ差し替える。
## initialize()より前に呼ぶ想定(_ensure_setup()が上書きしないよう、
## 既にセットされたadapterへ再接続はしない)。
func set_adapter_for_testing(adapter: RBMSteamAdapter) -> void:
	_adapter = adapter

func adapter_for_testing() -> RBMSteamAdapter:
	return _adapter

## Steam初期化を試みる。AppID未設定・Steam未起動・初期化失敗のいずれも
## クラッシュせず、is_available()==falseとして安全に扱えるようにする。
func initialize() -> Dictionary:
	_ensure_setup()
	if not RBMSteamConfig.is_configured():
		_init_result = {"status": -1, "verbal": "STEAM_APP_ID未設定（環境変数、または steam_dev_appid.local.txt）。"}
		_available = false
		return _init_result

	_init_result = _adapter.init_ex(RBMSteamConfig.app_id(), false)
	_available = _adapter.has_steam() and int(_init_result.get("status", 1)) == 0
	if _available:
		set_process(true)
	return _init_result

func is_available() -> bool:
	return _available

func init_result() -> Dictionary:
	return _init_result.duplicate()

func is_logged_on() -> bool:
	return _available and _adapter.is_logged_on()

## SteamID64は文字列として返す——将来Godot→Edge Function(Deno)→
## PostgreSQLと渡す際、JavaScript Numberの安全整数範囲を超える事故を
## 避けるため(ユーザー確定仕様)。デバッグ比較用途のみで、本人確認の
## 根拠には使わない。
func steam_id() -> String:
	if not is_logged_on():
		return ""
	return str(_adapter.get_steam_id())

func persona_name() -> String:
	if not is_logged_on():
		return ""
	return _adapter.get_persona_name()

func current_auth_state() -> AuthState:
	return _state

func failure_reason() -> String:
	return _failure_reason

## callback前のbinary dataは絶対にサーバーへ送らない——READY状態でのみ
## hexが存在する。二重requestは拒否する(false を返すだけで例外にはしない)。
func request_web_api_ticket() -> bool:
	if not is_available():
		_fail("Steam is not available")
		return false
	if _state == AuthState.REQUESTING or _state == AuthState.READY or _state == AuthState.IN_USE:
		return false

	_current_hex = ""
	_failure_reason = ""
	_set_state(AuthState.REQUESTING)

	_current_handle = _adapter.request_auth_ticket_for_web_api(WEB_API_IDENTITY)
	if _current_handle == 0:
		_fail("getAuthTicketForWebApi returned an invalid handle")
		return false

	_timeout_timer.wait_time = maxf(timeout_seconds, 0.01)
	# _timeout_timerがまだ実際にツリーへ入っていない(例: 呼び出し側が
	# add_child()した直後、最初のフレーム処理が起きる前にinitialize()と
	# request_web_api_ticket()を同じ呼び出しの中で連続して呼んだ場合)は
	# Timer.start()がエラーになるため、ツリーへ入るのを待ってから始動する。
	if _timeout_timer.is_inside_tree():
		_timeout_timer.start()
	else:
		_timeout_timer.start.call_deferred()
	return true

## READY状態のticketを一度だけ取り出す。取り出した瞬間IN_USEへ遷移し、
## 二度目以降の呼び出しは""を返す(同じticketの意図しない再利用を防ぐ)。
func consume_ticket_hex() -> String:
	if _state != AuthState.READY:
		return ""
	_set_state(AuthState.IN_USE)
	return _current_hex

## サーバーへ送った後(成功・失敗いずれでも)呼ぶ——Steam側handleを解放し
## COMPLETEDへ遷移する。二重に呼んでも安全。
func complete_ticket() -> void:
	if _state != AuthState.IN_USE and _state != AuthState.READY:
		return
	_adapter.cancel_auth_ticket(_current_handle)
	_current_handle = 0
	_current_hex = ""
	_set_state(AuthState.COMPLETED)

## いつ呼んでも安全(成功/失敗/timeout/ユーザーキャンセル/ゲーム終了の
## いずれの経路からも呼ばれる)。handleが無い状態で呼んでも何もしない。
func cancel_ticket() -> void:
	_cancel_internal("cancel_ticket() called")

func _cancel_internal(_reason: String) -> void:
	if _current_handle == 0 and _state != AuthState.REQUESTING:
		return
	_timeout_timer.stop()
	_adapter.cancel_auth_ticket(_current_handle)
	_current_handle = 0
	_current_hex = ""
	_set_state(AuthState.CANCELLED)

func _process(_delta: float) -> void:
	if _available:
		_adapter.run_callbacks()

func _on_ticket_for_web_api_received(auth_ticket: int, result: int, ticket_size: int, ticket_buffer: PackedByteArray) -> void:
	# 古いrequestのcallbackが新しいrequestへ混入するのを防ぐ——handleが
	# 一致しない、またはREQUESTING状態でなければ(既にcancel/timeout済み
	# 等)無視する。
	if _state != AuthState.REQUESTING or auth_ticket != _current_handle:
		return
	_timeout_timer.stop()

	if result != RBMSteamAdapter.RESULT_OK:
		# 失敗結果でも、Steamworksの契約どおりhandleを必ずcancelしてから
		# 破棄する(§重要「成功・失敗・timeout・ユーザーキャンセル・
		# ゲーム終了のいずれでもcancelする」)。
		_adapter.cancel_auth_ticket(auth_ticket)
		_current_handle = 0
		_fail("Steam returned result code %d for the web API ticket" % result)
		return

	var effective_size: int = clampi(ticket_size, 0, ticket_buffer.size())
	var trimmed := ticket_buffer.slice(0, effective_size)
	_current_hex = trimmed.hex_encode()
	_set_state(AuthState.READY)
	ticket_ready.emit(_current_hex)

func _on_timeout() -> void:
	if _state != AuthState.REQUESTING:
		return
	var handle_to_cancel := _current_handle
	_current_handle = 0
	_fail("Timed out waiting for Steam's ticket callback (%.1fs)" % timeout_seconds)
	_adapter.cancel_auth_ticket(handle_to_cancel)

func _fail(reason: String) -> void:
	_failure_reason = reason
	_current_hex = ""
	_set_state(AuthState.FAILED)
	ticket_failed.emit(reason)

func _set_state(new_state: AuthState) -> void:
	_state = new_state
	state_changed.emit(new_state)

## PackedByteArrayをlowercase hexadecimal文字列へ変換する専用関数
## (テスト対象として独立)。Godot組込みのhex_encode()を使うが、将来
## Steam側APIの戻り値形式が変わっても、この1関数だけ直せばよいように
## 独立させている。sizeはSteamのticket_size(実際の有効長、bufferの
## 確保長より短いことがある)。
static func ticket_bytes_to_hex(buffer: PackedByteArray, size: int = -1) -> String:
	var effective_size: int = buffer.size() if size < 0 else clampi(size, 0, buffer.size())
	return buffer.slice(0, effective_size).hex_encode()
