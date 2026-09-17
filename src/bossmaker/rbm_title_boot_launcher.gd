class_name RBMTitleBootLauncher
extends Control

## 承認済みのRBMTitleBootPreview(タイトル→START→時計加速→フェード→SYSTEM
## CORE起動演出)を本番の起動導線へ組み込むための薄いアダプタ。
##
## 目的: RBMTitleBootPreview自身は独立プレビューとして作られており、内部の
## HANDOFFフェーズでは「本プレビュー範囲外」の仮プレースホルダー画面
## (点線枠+CONNECTION ESTABLISHED)を表示する。本番ではその代わりに既存の
## 挑戦/作成選択画面(_title_screen自身、その場に元々ある)を見せたいため、
## このアダプタがプレビューの状態(_phase)を外部から監視するだけに留め、
## 「FLASHが終わりTO_HANDOFFへ入った瞬間」(プレースホルダーがまだ
## modulate.a=0で実際には見えていない1フレーム以内)に自身ごと非表示にする
## ——RBMTitleBootPreview自体のデザイン・タイミング・実装には一切手を
## 加えない。
##
## 入力ブロック: 起動演出中は自身(mouse_filter=STOP)が画面全体を覆うことで、
## 背後にある実際のChallengeModeButton/CreateModeButtonへの実クリックを
## 防ぐ——RBMTitleBootPreview自身は(単独プレビューとして動くよう)全要素が
## mouse_filter=IGNOREなので、この保護は外側のこのアダプタが担う。演出完了
## 後は自身を非表示にするだけで、既存のボタンがそのまま露出する
## (ChallengeModeButton/CreateModeButton自身のシグナル配線には一切触れない)。
##
## SFX: プレビュー確認・承認済みの6点(機械式時計tick/tock+滑らかな
## mechanical whirr+start確認音+システム起動音+SYSTEM ONLINEチャイム)を
## そのまま使用する。既存のRBMAudio(rbm_audio.gd、他セッション作業中のため
## 今回は一切変更しない)には触れず、このアダプタが専用のAudioStreamPlayer
## で独立に再生する——ボタンの汎用クリック/ホバー音(RBMAudio.bind_ui、
## RBMGameRoot経由で全ボタンへ自動的に付く既存の仕組み)とは別レイヤーとして
## 重なる想定(このSTARTボタンにも既存どおり自動で付く)。

signal boot_completed

const SFX_DIR := "res://assets_bossmaker/audio/title_boot/"

const TICK_RATE_MIN := 3.2
const TICK_RATE_MAX := 10.0
## accel_activationがこの区間に入るとtick/tock→whirrへクロスフェードする。
## 0.85は「tick_rateが約9拍/秒に達した頃」に相当し、プレビューで承認した
## 「8〜10回/秒程度からフェードさせる」「最後だけ一気に高速化」という設計
## そのまま。
const WHIRR_CROSSFADE_FROM := 0.85
const WHIRR_CROSSFADE_TO := 1.0

var _preview: RBMTitleBootPreview
var _revealed := false

var _player_start: AudioStreamPlayer
var _player_tick: AudioStreamPlayer
var _player_tock: AudioStreamPlayer
var _player_whirr: AudioStreamPlayer
var _player_boot: AudioStreamPlayer
var _player_chime: AudioStreamPlayer

var _next_is_tick := true
var _tick_cooldown := 0.0
var _whirr_started := false
var _boot_started := false
var _prev_phase = null
var _boot_fade_db := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_audio_players()

	var scene: PackedScene = load("res://src/bossmaker/title_boot_preview/rbm_title_boot_preview.tscn")
	_preview = scene.instantiate()
	add_child(_preview)

	var start_button: Control = _preview.find_child("StartButton", true, false)
	start_button.pressed.connect(_on_start_pressed)

	set_process(true)

func _build_audio_players() -> void:
	_player_start = _make_player(SFX_DIR + "sfx_start_confirm.wav")
	_player_tick = _make_player(SFX_DIR + "sfx_clock_tick.wav")
	_player_tock = _make_player(SFX_DIR + "sfx_clock_tock.wav")
	_player_whirr = _make_player(SFX_DIR + "sfx_mechanical_whirr.wav")
	_player_boot = _make_player(SFX_DIR + "sfx_boot_drone.wav")
	_player_chime = _make_player(SFX_DIR + "sfx_online_chime.wav")

	var boot_stream: AudioStreamWAV = _player_boot.stream
	boot_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	boot_stream.loop_begin = int(0.4 * boot_stream.mix_rate)
	boot_stream.loop_end = boot_stream.data.size() / 2 - 1

	var whirr_stream: AudioStreamWAV = _player_whirr.stream
	whirr_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	whirr_stream.loop_begin = int(0.6 * whirr_stream.mix_rate)
	whirr_stream.loop_end = whirr_stream.data.size() / 2 - 1

func _make_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = "Master"
	add_child(p)
	return p

func _on_start_pressed() -> void:
	_player_start.volume_db = linear_to_db(0.8)
	_player_start.play()

func _process(delta: float) -> void:
	if _revealed or not is_instance_valid(_preview):
		return

	_poll_audio(delta)

	if _preview._phase == RBMTitleBootPreview._Phase.TO_HANDOFF or _preview._phase == RBMTitleBootPreview._Phase.HANDOFF:
		_revealed = true
		set_process(false)
		# visible=falseは描画を止めるだけで、子のAudioStreamPlayerは止まらず
		# 鳴り続けてしまう(boot_droneはLOOP_FORWARDにしてあるため放置すると
		# 無限ループし続ける実害あり)——ハンドオフの瞬間に明示的に全て停止
		# する。
		_stop_all_audio()
		visible = false
		boot_completed.emit()

func _stop_all_audio() -> void:
	for p in [_player_tick, _player_tock, _player_whirr, _player_boot, _player_chime]:
		if p.playing:
			p.stop()

func _ensure_whirr_playing() -> void:
	if not _whirr_started:
		_player_whirr.play()
		_whirr_started = true

func _ensure_boot_playing() -> void:
	if not _boot_started:
		_player_boot.play()
		_boot_started = true

func _poll_audio(delta: float) -> void:
	var phase = _preview._phase
	var accel: float = _preview._accel_activation
	var hand_alpha: float = _preview._core_symbol.hand_alpha

	if phase == RBMTitleBootPreview._Phase.HAND_ACCEL or phase == RBMTitleBootPreview._Phase.CORE_TRANSFORM:
		var whirr_mix := smoothstep(WHIRR_CROSSFADE_FROM, WHIRR_CROSSFADE_TO, accel)
		var tick_gain := (1.0 - whirr_mix) * hand_alpha

		if tick_gain > 0.02:
			_tick_cooldown -= delta
			if _tick_cooldown <= 0.0:
				var rate := lerpf(TICK_RATE_MIN, TICK_RATE_MAX, clampf(accel, 0.0, 1.0))
				_tick_cooldown = 1.0 / rate
				var p := _player_tick if _next_is_tick else _player_tock
				_next_is_tick = not _next_is_tick
				p.volume_db = linear_to_db(clampf(0.55 * tick_gain, 0.0, 1.0))
				p.play()

		_ensure_whirr_playing()
		var whirr_gain := whirr_mix * hand_alpha
		_player_whirr.volume_db = linear_to_db(clampf(whirr_gain, 0.0, 1.0))
		_player_whirr.pitch_scale = lerpf(0.9, 1.35, clampf(accel, 0.0, 1.0))

		if phase == RBMTitleBootPreview._Phase.CORE_TRANSFORM:
			_ensure_boot_playing()
			_boot_fade_db = linear_to_db(clampf(1.0 - hand_alpha, 0.0, 0.85))
			_player_boot.volume_db = _boot_fade_db
	elif phase == RBMTitleBootPreview._Phase.BOOT or phase == RBMTitleBootPreview._Phase.ONLINE_HOLD or phase == RBMTitleBootPreview._Phase.FLASH:
		if _player_whirr.playing:
			_player_whirr.stop()
		_ensure_boot_playing()
		_player_boot.volume_db = linear_to_db(0.85)

	if _prev_phase != phase:
		if phase == RBMTitleBootPreview._Phase.ONLINE_HOLD:
			_player_chime.volume_db = linear_to_db(0.85)
			_player_chime.play()
		_prev_phase = phase
