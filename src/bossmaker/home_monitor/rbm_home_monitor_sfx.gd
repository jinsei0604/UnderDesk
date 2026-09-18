class_name RBMHomeMonitorSfx
extends Node

## RBMHomeMonitorPanel(左下「挑戦」／右下「ボス作成」モニター)へBOOT/拡大
## のSFXを同期させるアダプタ。RBMTitleBootLauncherがRBMTitleBootPreviewに
## 対して行っているのと同じ手法——対象のRBMHomeMonitorPanel自身のロジック・
## タイミング・見た目には一切触れず、外部からその実際の視覚状態
## (_state/_panel_draw/_reticle/_status_label/_label/size)を毎フレーム
## 読むだけ。SFXは固定秒数のタイマーではなく、対応する視覚イベントの実際の
## 発生を検知して発火する(承認済みプレビュー、tools/_home_monitor_sfx_
## preview_gpu.gd の right_creator_sfx_v2 版で確認済みの合成音・発火ロジック
## をそのまま移植したもの——音素材・発火条件とも変更していない)。
##
## 対応関係(承認済み):
##   クリック  ↔ ラベルが実際に強く発光し始めた瞬間(label.modulate.r上昇)
##   BOOT開始  ↔ scan_posが非アクティブ→アクティブに切り替わった瞬間
##   リング表示 ↔ reticle.alphaが0から立ち上がった最初のフレーム
##   セグメント点灯 ↔ reticle.lit_ticksが実際に増えた瞬間(2つごと)
##   四隅到達  ↔ panel_draw.boot_corner_stageが1/2/3/4を超えた瞬間
##   LINK ESTABLISHED ↔ status_label.textが実際に切り替わった瞬間
##   拡大開始  ↔ panel.sizeがhome_rectから実際に変化し始めた瞬間
##   全面到達  ↔ panel.sizeが1280x720に一致した瞬間
## 左右は同じM&Cシステムとして共通のSFXを使う——最後の確定音のピッチだけ
## ごく僅かに差を付ける(承認済み仕様どおり)。

var panel: RBMHomeMonitorPanel
var side: String = "left"

var _sfx: Dictionary = {}
var _was_booting := false
var _prev_label_bright := false
var _prev_scan_pos := -1.0
var _ring_started := false
var _prev_lit_ticks := 0
var _prev_corner_ceil := 0
var _prev_status_text := ""
var _expand_started := false
var _settled_fired := false

func _ready() -> void:
	_sfx = _build_sfx(side)
	for key in _sfx.keys():
		var v = _sfx[key]
		if v is AudioStreamPlayer:
			add_child(v)
		elif v is Array:
			for p in v:
				add_child(p)

func play_hover() -> void:
	if is_instance_valid(panel) and panel._state == RBMHomeMonitorPanel._State.IDLE:
		(_sfx.hover as AudioStreamPlayer).play()

## 遷移完了/タイトルへ戻る際に、鳴り残った音を即座に止める。
func stop_all() -> void:
	for key in _sfx.keys():
		var v = _sfx[key]
		if v is AudioStreamPlayer:
			if v.playing:
				v.stop()
		elif v is Array:
			for p in v:
				if p.playing:
					p.stop()

func _process(_delta: float) -> void:
	if not is_instance_valid(panel):
		return
	if panel._state != RBMHomeMonitorPanel._State.BOOTING:
		if _was_booting:
			_reset_edge_trackers()
		return
	_was_booting = true

	var cur_bright: bool = panel._label.modulate.r > 1.05
	if cur_bright and not _prev_label_bright:
		(_sfx.click as AudioStreamPlayer).play()
	_prev_label_bright = cur_bright

	var cur_scan_pos: float = panel._panel_draw.scan_pos
	if _prev_scan_pos < 0.0 and cur_scan_pos >= 0.0:
		(_sfx.boot_start as AudioStreamPlayer).play()
	_prev_scan_pos = cur_scan_pos

	var cur_alpha: float = panel._reticle.alpha
	if not _ring_started and cur_alpha > 0.02:
		_ring_started = true
		(_sfx.ring_pulse as AudioStreamPlayer).play()

	var cur_ticks: int = panel._reticle.lit_ticks
	if cur_ticks > _prev_lit_ticks and cur_ticks % 2 == 0:
		(_sfx.ring_pulse as AudioStreamPlayer).play()
	_prev_lit_ticks = cur_ticks

	var stage_ceil: int = int(ceil(panel._panel_draw.boot_corner_stage))
	if stage_ceil > _prev_corner_ceil and stage_ceil <= 4:
		var idx: int = stage_ceil - 1
		var corner_players: Array = _sfx.corner
		(corner_players[idx] as AudioStreamPlayer).play()
		_prev_corner_ceil = stage_ceil

	var cur_text: String = panel._status_label.text
	if cur_text == "LINK ESTABLISHED" and _prev_status_text != "LINK ESTABLISHED":
		(_sfx.link_established as AudioStreamPlayer).play()
	_prev_status_text = cur_text

	if not _expand_started and panel.size != panel.home_rect.size:
		_expand_started = true
		(_sfx.expand as AudioStreamPlayer).play()
	if _expand_started and not _settled_fired and panel.size == RBMHomeMonitorPanel.SCREEN_SIZE:
		_settled_fired = true
		(_sfx.settle as AudioStreamPlayer).play()

func _reset_edge_trackers() -> void:
	_was_booting = false
	_prev_label_bright = false
	_prev_scan_pos = -1.0
	_ring_started = false
	_prev_lit_ticks = 0
	_prev_corner_ceil = 0
	_prev_status_text = ""
	_expand_started = false
	_settled_fired = false

# =============================================================================
# 仮SFX合成 — 承認済みプレビュー(right_creator_sfx_v2)から一切変更していない
# (周波数・長さ・音量・波形とも同一)
# =============================================================================

func _build_sfx(p_side: String) -> Dictionary:
	var d := {}
	d["hover"] = _player(_tone(880.0, 880.0, 0.09, 0.01, 0.06, 0.12))
	d["click"] = _player(_tone(660.0, 880.0, 0.10, 0.005, 0.08, 0.16, 0.15))
	d["boot_start"] = _player(_mix([
		_tone(100.0, 140.0, 0.18, 0.02, 0.12, 0.11),
		_tone(150.0, 210.0, 0.18, 0.02, 0.12, 0.06),
	]))
	d["ring_pulse"] = _player(_tone(550.0, 550.0, 0.05, 0.005, 0.03, 0.07))
	var corner_freqs := [440.0, 494.0, 554.0, 622.0]
	var corner_players: Array = []
	for f in corner_freqs:
		corner_players.append(_player(_tone(f, f, 0.07, 0.005, 0.05, 0.11)))
	d["corner"] = corner_players
	d["link_established"] = _player(_mix_sequence([
		_tone(659.0, 659.0, 0.12, 0.005, 0.05, 0.16),
		_tone(880.0, 880.0, 0.14, 0.005, 0.09, 0.16, 0.12),
	], 0.10))
	d["expand"] = _player(_air_swell(0.5, 0.10))
	var settle_end := 260.0 if p_side == "left" else 280.0
	d["settle"] = _player(_tone(300.0, settle_end, 0.06, 0.005, 0.05, 0.08))
	return d

func _player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Master"
	return p

func _tone(freq0: float, freq1: float, duration: float, attack: float, release: float, volume: float, harmonic2_amt: float = 0.0) -> AudioStreamWAV:
	var mix_rate := 44100
	var n: int = max(1, int(duration * mix_rate))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in range(n):
		var t: float = float(i) / mix_rate
		var freq: float = lerp(freq0, freq1, float(i) / float(max(1, n - 1)))
		phase += TAU * freq / mix_rate
		var s: float = sin(phase)
		if harmonic2_amt > 0.0:
			s = (s + harmonic2_amt * sin(phase * 2.0)) / (1.0 + harmonic2_amt)
		var env: float = 1.0
		if t < attack:
			env = t / attack
		var t_from_end: float = duration - t
		if t_from_end < release:
			env = min(env, max(0.0, t_from_end) / release)
		var sample: float = clamp(s * env * volume, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _air_swell(duration: float, volume: float) -> AudioStreamWAV:
	var mix_rate := 44100
	var n: int = max(1, int(duration * mix_rate))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var smoothed := 0.0
	for i in range(n):
		var raw: float = rng.randf_range(-1.0, 1.0)
		smoothed = lerp(smoothed, raw, 0.06)
		var frac: float = float(i) / float(max(1, n - 1))
		var env: float = sin(frac * PI)
		var sample: float = clamp(smoothed * env * volume, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _mix(streams: Array) -> AudioStreamWAV:
	var longest: AudioStreamWAV = streams[0]
	for s in streams:
		if s.data.size() > longest.data.size():
			longest = s
	var n: int = longest.data.size() / 2
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var sum := 0.0
		for s in streams:
			var sdata: PackedByteArray = s.data
			if i * 2 + 1 < sdata.size():
				sum += sdata.decode_s16(i * 2) / 32767.0
		var sample: float = clamp(sum, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = longest.mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _mix_sequence(streams: Array, gap_sec: float) -> AudioStreamWAV:
	var mix_rate := 44100
	var gap_samples: int = int(gap_sec * mix_rate)
	var total_samples := 0
	for s in streams:
		total_samples += (s.data.size() / 2) + gap_samples
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	var cursor := 0
	for s in streams:
		var sdata: PackedByteArray = s.data
		var count: int = sdata.size() / 2
		for i in range(count):
			bytes.encode_s16((cursor + i) * 2, sdata.decode_s16(i * 2))
		cursor += count + gap_samples
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream
