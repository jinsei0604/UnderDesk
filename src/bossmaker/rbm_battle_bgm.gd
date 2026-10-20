class_name RBMBattleBgm
extends Node

## 戦闘画面のボス専用BGMを鳴らす(音の専用)。戦闘の状態・乱数・行動順・保存データは読むだけで変えない。
## TEST BATTLE・クリアチェック・挑戦の画面が _ready で attach() して1つずつ持つ。曲は RBMBossBgm が決める。
##
## - 戦闘が始まったら覚醒前の曲を頭から流し、ループする(登場演出がある時は、登場が終わってから)。
## - 覚醒の演出が始まったら曲を消し、演出が終わって覚醒が表示されたら覚醒後の曲を頭から流す。
## - とどめ・全滅の命中で曲を消す(勝利・敗北の演出と結果の間は鳴らさない)。
## - やり直しは頭から流し直す。REWIND・中断した戦闘は、今表示している状態(覚醒前/後)の曲にする。
## - 画面が隠れたら(戦闘を出たら)すぐ止める。戦闘の SE を消している画面(ホーム画面のモニター)では鳴らさない。
## 再生器は1つだけなので、2曲が同時に鳴ることはない(替える時は前の曲を消してから次の曲を始める)。
## 曲は戦闘が始まった時に読み、その戦闘の間は保持する(覚醒の瞬間に初めて読まない)。

const NODE_NAME := "BattleBgm"
## BGM を流すバス(無ければ作り、Master へ送る)。今後の音量の設定はこのバスの音量を変える。
const BUS := "Music"
## 覚醒の演出が始まった時に曲を消す長さ(秒)。
const FADE_AWAKENING := 0.6
## とどめ・全滅の命中で曲を消す長さ(秒)。
const FADE_END := 1.2
## やり直し・REWIND で曲を替える前に消す長さ(秒)。
const FADE_SWITCH := 0.25

var view: Node
var player: AudioStreamPlayer
## false の画面では鳴らさず、曲も読まない(ホーム画面のモニターのプレビュー)。
var enabled := true
## テスト用に差し替えられる(普段は RBMBossBgm の表と命名規則)。
var table: Dictionary = RBMBossBgm.BOSS_BGM
var convention: String = RBMBossBgm.CONVENTION

var _battle: Object
var _presenter: Node
var _awakened_shown := false
var _awakening_playing := false
var _ended := false
var _restart := false
var _track := ""
var _fade_left := -1.0
var _fade_total := 0.0
var _base_db := 0.0
var _streams: Dictionary = {}
## 戦闘ごとに1回だけ曲を決めて覚えておく(毎フレームファイルを探さない)。[覚醒前, 覚醒後]
var _paths: Array[String] = ["", ""]
## [覚醒前, 覚醒後] の曲を鳴らす音量の調整(dB)。覚醒後の曲が無い時は覚醒前の値。
var _gains: Array[float] = [0.0, 0.0]
var _paths_boss := ""

## 戦闘の画面に1つ付ける(付いていればそれを返す)。
static func attach(p_view: Node) -> RBMBattleBgm:
	var existing := p_view.get_node_or_null(NODE_NAME) as RBMBattleBgm
	if existing != null:
		return existing
	var bgm := RBMBattleBgm.new()
	bgm.name = NODE_NAME
	bgm.view = p_view
	p_view.add_child(bgm)
	return bgm

static func ensure_bus() -> String:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
	return BUS

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "BgmPlayer"
	player.bus = ensure_bus()
	add_child(player)

## 鳴らしている曲のパス(消している途中も含む。鳴らしていなければ空文字)。
func current_track() -> String:
	return _track if player != null and player.playing else ""

## 今の状態で鳴らすべき曲のパス(鳴らさないなら空文字)。
func wanted_track() -> String:
	if not enabled or _battle == null or _ended or _awakening_playing or _muted() or _intro_playing():
		return ""
	_resolve_paths()
	return _paths[1 if _awakened_shown else 0]

func boss_id() -> String:
	return RBMVisualAssets.boss_asset(str(view.get("_boss_appearance_id"))) if is_instance_valid(view) else ""

func _process(delta: float) -> void:
	if not is_instance_valid(view) or player == null:
		return
	# 画面が隠れたら(戦闘を出たら)すぐ止める。一時停止にすると、次の戦闘の始まりに前の曲の続きが一瞬鳴る。
	var shown: bool = (view as CanvasItem).is_visible_in_tree() if view is CanvasItem else true
	if not shown:
		if player.playing:
			player.stop()
		_track = ""
		_fade_left = -1.0
		return
	_watch_battle()
	_connect_presenter()
	# 演出が止まっている時は、表示が戦闘に追いついている(REWIND・演出なしの画面)。ただし登場演出の間は、
	# 戦闘の冒頭の出来事(冒頭の覚醒など)をまだ見せていないので合わせない(登場の後、同じ処理の中で冒頭の演出が始まる)。
	var presenting := is_instance_valid(_presenter) and bool(_presenter.call("is_playing"))
	if _battle != null and not presenting and not _intro_playing():
		_awakening_playing = false
		_awakened_shown = bool(_battle.get("is_awakened"))
		_ended = bool(_battle.get("battle_over"))
	_update_player(delta)

func _watch_battle() -> void:
	var session: Variant = view.get("session")
	var battle: Object = (session as Object).get("battle") if session is Object else null
	if battle == _battle:
		return
	_battle = battle
	# 新しい戦闘は覚醒前の表示から始まる(冒頭で覚醒する時も、その演出で覚醒後になる)。
	_awakening_playing = false
	_ended = false
	_awakened_shown = false
	_restart = true
	_streams.clear()
	_paths_boss = ""
	# この戦闘で使う曲を先に読んでおく(覚醒の瞬間に初めて読まない)。音を消している画面では読まない。
	if battle != null and enabled and not _muted():
		_resolve_paths()
		for path in _paths:
			_stream(path)

func _resolve_paths() -> void:
	var id := boss_id()
	if id == _paths_boss and not id.is_empty():
		return
	_paths_boss = id
	_paths = [RBMBossBgm.path_for(id, false, table, convention), RBMBossBgm.path_for(id, true, table, convention)]
	var own_awakened := _paths[1] != _paths[0]
	_gains = [RBMBossBgm.volume_db(id, false, table), RBMBossBgm.volume_db(id, own_awakened, table)]

func _connect_presenter() -> void:
	var presenter: Variant = view.get("_presenter")
	if not presenter is Node or presenter == _presenter:
		return
	_presenter = presenter
	if _presenter.has_signal("entry_started") and not _presenter.is_connected("entry_started", _on_entry_started):
		_presenter.connect("entry_started", _on_entry_started)
	if _presenter.has_signal("entry_impact") and not _presenter.is_connected("entry_impact", _on_entry_impact):
		_presenter.connect("entry_impact", _on_entry_impact)

func _on_entry_started(entry: Dictionary) -> void:
	if str(entry.get("action", "")) == "awakening":
		_awakening_playing = true

func _on_entry_impact(entry: Dictionary) -> void:
	if str(entry.get("action", "")) == "awakening":
		_awakening_playing = false
	var state: Dictionary = entry.get("visual_state", {})
	if state.has("is_awakened"):
		_awakened_shown = bool(state["is_awakened"])
	if bool(state.get("battle_over", false)):
		_ended = true

func _update_player(delta: float) -> void:
	var wanted := wanted_track()
	var playing := player.playing
	if playing and (wanted != _track or _restart):
		if _fade_left < 0.0:
			_fade_total = _fade_length()
			_fade_left = _fade_total
		_fade_left -= delta
		if _fade_left > 0.0:
			player.volume_db = _base_db + linear_to_db(_fade_left / _fade_total)
			return
		player.stop()
		playing = false
	elif playing and _fade_left >= 0.0:
		# 消している途中で、また同じ曲を流すことになった(REWIND で演出が止まった時など)。
		_fade_left = -1.0
		player.volume_db = _base_db
		return
	if playing:
		return
	_fade_left = -1.0
	_restart = false
	_track = wanted
	if wanted.is_empty():
		return
	var stream := _stream(wanted)
	if stream == null:
		_track = ""
		return
	_base_db = _gains[maxi(0, _paths.find(wanted))]
	player.stream = stream
	player.volume_db = _base_db
	player.play()

func _fade_length() -> float:
	if not enabled or _battle == null or _muted():
		return 0.01
	if _ended:
		return FADE_END
	if _awakening_playing:
		return FADE_AWAKENING
	return FADE_SWITCH

func _stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if not _streams.has(path):
		_streams[path] = RBMBossBgm.load_stream(path)
	return _streams[path]

## 登場演出の間(素材を待っている間も含む)。決着の後の勝利演出は _ended で扱う。
func _intro_playing() -> bool:
	var encounter: Variant = view.get("_encounter")
	return encounter is Node and is_instance_valid(encounter) and bool((encounter as Node).call("is_playing"))

## 戦闘の SE を消している画面(ホーム画面のモニターのプレビュー)では BGM も鳴らさない。
func _muted() -> bool:
	var row: Variant = view.get("_battlefield_ally_row")
	if not row is Node or not (row as Node).has_meta("visual_stage"):
		return false
	var stage: Variant = (row as Node).get_meta("visual_stage")
	if not stage is Node or not is_instance_valid(stage):
		return false
	var sound := (stage as Node).get_node_or_null("RBMAudio")
	return sound != null and bool(sound.get("muted"))

func _exit_tree() -> void:
	if player != null:
		player.stop()
