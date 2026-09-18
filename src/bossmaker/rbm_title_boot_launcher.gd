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
## (ChallengeModeButton/CreateModeButtonへ自身のシグナル配線には一切触れない)。
##
## SFX(2026-09-18改訂: 音付きプレビューv2〜v8の一連の確認を経て確定した
## 最終版): 時計tick/tockの発火は、RBMTitleBootPreviewが針とロードUIの
## 回転に実際に使っている_spin_offset(累積角度)から直接導出する——
## SFX専用のタイマー/加速カーブは一切持たない。一定角度(TICK_ANGLE_STEP)
## 進むたびに1回発火するだけの単純な仕組みのため、針が2倍速で回れば
## 発火も自動的に2倍、4倍なら4倍になり、映像と音の速度が原理的にズレない。
## 音量はCORE_TRANSFORM中の_core_symbol.hand_alpha(針が視覚的にフェード
## アウトするタイミング)だけに従う——最高速のまま徐々に小さくなり、
## 急停止しない。SYSTEM CORE起動音(sfx_system_core_boot.wav)の音量は
## 同じhand_alphaから「1.0-hand_alpha」で算出するため、時計音が完全に
## 消える前から起動音が育ち始め、無音区間もリセットも発生しない
## (旧mechanical_whirrクロスフェード方式は廃止)。ゲージSEは
## RBMTitleBootPreview._gauge.lit_countの変化を検知して駆動する
## (1セグメント点灯=1音、100%到達後は追加で鳴らさない、最後に短い
## 確定音を1回)。既存のRBMAudio(rbm_audio.gd、他セッション作業中のため
## 一切変更しない)には触れず、このアダプタが専用のAudioStreamPlayerで
## 独立に再生する——ボタンの汎用クリック/ホバー音(RBMAudio.bind_ui、
## RBMGameRoot経由で全ボタンへ自動的に付く既存の仕組み)とは別レイヤーとして
## 重なる想定(このSTARTボタンにも既存どおり自動で付く)。

signal boot_completed

const SFX_DIR := "res://assets_bossmaker/audio/title_boot/"

## ユーザーフィードバック対応: タイトル起動SFXがゲーム全体の標準UI音量
## (RBMAudio.play_sound()の既定 -9.0dB、ボタンhover/click等で使用)より
## 明確に大きく聞こえていた。最大音量だった0.85(linear_to_db(0.85)≒
## -1.41dB)をちょうど-9.0dBへ揃えるための一律トリム量——相対バランス
## (tick/tock・boot・chime・gauge類の大小関係)は変えず、全体を同じだけ
## 下げるだけ。
const VOLUME_TRIM_DB := -7.6

## 一定角度(rad)ごとに1回tick/tockを発火する。HAND_STEADY_SPEED
## (4.5rad/s)のときに約2.5Hz(0.4秒間隔)になるよう校正した値——「通常時は
## 現在の自然なtick/tock感を維持する」という承認済み基準に合わせるための
## 数値で、以降の加速カーブは針の実際の回転速度(_spin_speed)がそのまま
## 反映される(SFX側で別途カーブを持たない)。
const TICK_ANGLE_STEP := 1.8

const TICK_POOL_SIZE := 6
const GAUGE_STEP_POOL_SIZE := 3

## SYSTEM CORE起動音のループ開始位置(秒)。sfx_system_core_boot.wavは
## root(110Hz)とfifth(165Hz=root*1.5)を厳密な3:2比で使っており、
## 2/110秒ごとに合成波形全体が同じ位相へ戻るため、この時刻以降は
## サンプル単位でクリックの無いシームレスループになる。
const BOOT_LOOP_BEGIN_SEC := 1.2

var _preview: RBMTitleBootPreview
var _revealed := false

var _player_start: AudioStreamPlayer
var _tick_pool: Array[AudioStreamPlayer] = []
var _tock_pool: Array[AudioStreamPlayer] = []
var _player_boot: AudioStreamPlayer
var _player_chime: AudioStreamPlayer
var _gauge_step_pool: Array[AudioStreamPlayer] = []
var _player_gauge_complete: AudioStreamPlayer

var _tick_idx := 0
var _tock_idx := 0
var _gauge_step_idx := 0

var _offset_initialized := false
var _last_tick_offset := 0.0
var _next_is_tick := true
var _boot_started := false
var _prev_phase = null
var _prev_lit_count := 0
var _gauge_completed := false

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
	for i in range(TICK_POOL_SIZE):
		_tick_pool.append(_make_player(SFX_DIR + "sfx_clock_tick.wav"))
		_tock_pool.append(_make_player(SFX_DIR + "sfx_clock_tock.wav"))
	for i in range(GAUGE_STEP_POOL_SIZE):
		_gauge_step_pool.append(_make_player(SFX_DIR + "sfx_gauge_step.wav"))
	_player_gauge_complete = _make_player(SFX_DIR + "sfx_gauge_complete.wav")
	_player_boot = _make_player(SFX_DIR + "sfx_system_core_boot.wav")
	_player_chime = _make_player(SFX_DIR + "sfx_online_chime.wav")

	var boot_stream: AudioStreamWAV = _player_boot.stream
	boot_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	boot_stream.loop_begin = int(BOOT_LOOP_BEGIN_SEC * boot_stream.mix_rate)
	boot_stream.loop_end = boot_stream.data.size() / 2 - 1

func _make_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = "Master"
	add_child(p)
	return p

func _on_start_pressed() -> void:
	_player_start.volume_db = linear_to_db(0.8) + VOLUME_TRIM_DB
	_player_start.play()

func _process(delta: float) -> void:
	if _revealed or not is_instance_valid(_preview):
		return

	_poll_audio(delta)

	if _preview._phase == RBMTitleBootPreview._Phase.TO_HANDOFF or _preview._phase == RBMTitleBootPreview._Phase.HANDOFF:
		_revealed = true
		set_process(false)
		# visible=falseは描画を止めるだけで、子のAudioStreamPlayerは止まらず
		# 鳴り続けてしまう(sfx_system_core_boot.wavはLOOP_FORWARDにして
		# あるため放置すると無限ループし続ける実害あり)——ハンドオフの瞬間に
		# 明示的に全て停止する。
		_stop_all_audio()
		visible = false
		boot_completed.emit()

func _stop_all_audio() -> void:
	for p in _tick_pool:
		if p.playing:
			p.stop()
	for p in _tock_pool:
		if p.playing:
			p.stop()
	for p in _gauge_step_pool:
		if p.playing:
			p.stop()
	for p in [_player_boot, _player_chime, _player_gauge_complete]:
		if p.playing:
			p.stop()

func _ensure_boot_playing() -> void:
	if not _boot_started:
		_player_boot.play()
		_boot_started = true

func _poll_audio(delta: float) -> void:
	var phase = _preview._phase
	var spin_offset: float = _preview._spin_offset
	var hand_alpha: float = _preview._core_symbol.hand_alpha
	var lit_count: int = _preview._gauge.lit_count

	if phase == RBMTitleBootPreview._Phase.HAND_ACCEL or phase == RBMTitleBootPreview._Phase.CORE_TRANSFORM:
		_update_angle_locked_ticks(spin_offset, hand_alpha)
		if phase == RBMTitleBootPreview._Phase.CORE_TRANSFORM:
			_ensure_boot_playing()
			_player_boot.volume_db = linear_to_db(clampf(1.0 - hand_alpha, 0.0, 0.85)) + VOLUME_TRIM_DB
	elif phase == RBMTitleBootPreview._Phase.BOOT or phase == RBMTitleBootPreview._Phase.ONLINE_HOLD or phase == RBMTitleBootPreview._Phase.FLASH:
		_ensure_boot_playing()
		_player_boot.volume_db = linear_to_db(0.85) + VOLUME_TRIM_DB

	if phase == RBMTitleBootPreview._Phase.BOOT:
		_update_gauge_sfx(lit_count)
	elif _prev_lit_count != 0 and phase != RBMTitleBootPreview._Phase.BOOT:
		_prev_lit_count = 0
		_gauge_completed = false

	if _prev_phase != phase:
		if phase == RBMTitleBootPreview._Phase.ONLINE_HOLD:
			_player_chime.volume_db = linear_to_db(0.85) + VOLUME_TRIM_DB
			_player_chime.play()
		_prev_phase = phase

## 角度クオンタイズによる発火本体。SFX専用のタイマー/カーブは持たず、
## RBMTitleBootPreview自身が針とロードUIの回転に使っている_spin_offset
## (累積角度)が一定量進むたびに1回発火するだけ——「加速カーブ」は
## _spin_offsetの進み方(=_spin_speed)がそのまま反映される。音量は
## hand_alphaだけに従う(速度に応じたフェードは行わない——最高速のまま
## 音量だけが下がることで「時計が高速回転したまま消えていく」感覚を
## 保つ、確認済みの設計)。
func _update_angle_locked_ticks(spin_offset: float, hand_alpha: float) -> void:
	if not _offset_initialized:
		_last_tick_offset = spin_offset
		_offset_initialized = true
		return

	var guard := 0
	while spin_offset - _last_tick_offset >= TICK_ANGLE_STEP and guard < 64:
		_last_tick_offset += TICK_ANGLE_STEP
		guard += 1
		_fire_tick(hand_alpha)

func _fire_tick(gate: float) -> void:
	if gate > 0.01:
		var pool := _tick_pool if _next_is_tick else _tock_pool
		var idx := _tick_idx if _next_is_tick else _tock_idx
		var p: AudioStreamPlayer = pool[idx % pool.size()]
		p.pitch_scale = 1.0
		p.volume_db = linear_to_db(clampf(0.55 * gate, 0.0, 1.0)) + VOLUME_TRIM_DB
		p.play()
	if _next_is_tick:
		_tick_idx += 1
	else:
		_tock_idx += 1
	_next_is_tick = not _next_is_tick

## ゲージSE: RBMTitleBootPreview._gauge.lit_countの変化だけを検知して
## 駆動する(独立タイマーは持たない)。1セグメント点灯=1音、満了後は
## 追加で鳴らさない、最後に短い確定音を1回。
func _update_gauge_sfx(lit_count: int) -> void:
	if lit_count > _prev_lit_count:
		for i in range(_prev_lit_count, lit_count):
			var p := _gauge_step_pool[_gauge_step_idx % _gauge_step_pool.size()]
			_gauge_step_idx += 1
			p.volume_db = linear_to_db(0.5) + VOLUME_TRIM_DB
			p.play()
		_prev_lit_count = lit_count
	if lit_count >= RBMTitleBootPreview.GAUGE_SEGMENTS and not _gauge_completed:
		_gauge_completed = true
		_player_gauge_complete.volume_db = linear_to_db(0.6) + VOLUME_TRIM_DB
		_player_gauge_complete.play()
