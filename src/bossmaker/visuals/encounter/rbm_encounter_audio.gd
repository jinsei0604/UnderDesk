extends Node
## 登場・勝利の演出の音（表示専用。戦闘の状態・乱数・保存データには触れない）。
## 鍵は "enc:<名前>"（assets_bossmaker/audio/encounter/<名前>.wav、この演出のために作った音）と
## "game:<名前>"（assets_bossmaker/audio/<名前>.wav、既存の音を読むだけ）。
## 音量は本番の RBMAudio と同じ基準（-9dB + gain）。長い音の一部だけを使う時は from（開始秒）と length（長さ）を渡す
## （終わりは短くフェードして止める）。演出の時刻（age）から鳴らし、時間は advance(dt) で外から進める。
## 素材は事前読み込み（rbm_presentation_warmup.gd が warm_paths() を読む）で読み終えている前提で、ここでは
## ResourceLoader のキャッシュから受け取るだけ（再生中に初めて読まない。読めていない音は鳴らさない）。

const BASE_DB := -9.0
const ENCOUNTER_ROOT := "res://assets_bossmaker/audio/encounter/"
const GAME_ROOT := "res://assets_bossmaker/audio/"
const VOICES := 12
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _stops := {}   # player -> {end, fade, db}
var _next := 0
var history: Array = []
var clock := 0.0
var muted := false

func _ready() -> void:
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

static func path_of(key: String) -> String:
	if key.begins_with("enc:"):
		return ENCOUNTER_ROOT + key.substr(4) + ".wav"
	if key.begins_with("game:"):
		return GAME_ROOT + key.substr(5) + ".wav"
	return ""

## 鍵の一覧 → 読み込む素材の一覧（warm_paths() 用）。
static func paths_of(keys: Array) -> Array[String]:
	var out: Array[String] = []
	for k in keys:
		var p := path_of(str(k))
		if not p.is_empty() and not out.has(p):
			out.append(p)
	return out

## 鍵の音を受け取る。読み込み済み（キャッシュにある）か、テスト・検証で allow_load の時だけ読む。
func stream(key: String, allow_load: bool = false) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var path := path_of(key)
	var s: AudioStream = null
	if not path.is_empty() and (ResourceLoader.has_cached(path) or allow_load) and ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s != null:
		_streams[key] = s
	return s

## 再生を始める前に、使う音をまとめて受け取っておく（キャッシュに無い物は allow_load の時だけ読む）。
func hold(keys: Array, allow_load: bool = false) -> void:
	for k in keys:
		stream(str(k), allow_load)

func play(key: String, gain_db: float = 0.0, from: float = 0.0, length: float = -1.0, pitch: float = 1.0) -> void:
	history.append([snappedf(clock, 0.001), key, gain_db])
	if history.size() > 128:
		history.pop_front()
	var s := stream(key)
	if s == null or muted or not is_inside_tree() or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stop()
	_stops.erase(p)
	p.stream = s
	p.volume_db = BASE_DB + gain_db
	p.pitch_scale = pitch
	p.play(from)
	if length > 0.0:
		_stops[p] = {"end": clock + length, "fade": minf(0.12, length * 0.3), "db": BASE_DB + gain_db}

func advance(dt: float) -> void:
	clock += dt
	for p in _stops.keys():
		var e: Dictionary = _stops[p]
		var left: float = float(e.end) - clock
		if left <= 0.0:
			p.stop()
			_stops.erase(p)
		elif left < float(e.fade):
			p.volume_db = float(e.db) + linear_to_db(maxf(0.001, left / float(e.fade)))

func stop_all() -> void:
	for p in _players:
		p.stop()
	_stops.clear()
