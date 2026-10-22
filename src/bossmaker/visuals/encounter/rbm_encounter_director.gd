class_name RBMEncounterDirector
extends Node
## 戦闘開始前の登場演出と勝利演出の進行役（表示専用）。挑戦（RBMChallengeBattleView）とクリアチェック
## （RBMCreatorClearCheckView）の戦闘画面が1つずつ持つ。TEST BATTLE では使わない（ユーザーの決定）。
## - 戦闘画面の操作の流れ（「挑戦する」・クリアチェックの「開始」・「もう一度挑戦」・「最初からやり直す」）で始めた戦闘だけで
##   有効にする（begin_battle()）。start_battle() を直接呼んだ戦闘（テスト・ほかの演出の検証ツール）では今までどおり出さない。
## - 登場: 戦闘を始めた直後、最初の行動を見せる前に流す。終わったら呼び出し元が最初の行動の演出（開幕）へ進む。
## - 勝利: 味方が勝った行動の命中（presenter の entry_impact で決着が分かった時）から、とどめのスロー → 演出の終わり（presenter の
##   finished）の後にボスの倒れ方・味方の反応・勝利の文字。結果パネルは演出の後に出す（呼び出し元は holds_outcome() の間は隠す）。
## - 飛ばせない。演出の間はコマンド・ボタンを押せない（コマンドの入力を止める＋画面の層の入力を止める板）。
## - 撃破ターン = 決着した時の戦闘のターン。クリアタイム = 登場が終わって操作できるようになってから、とどめが当たるまで（実時間）。
## - 戦闘の状態・乱数・行動順・保存データ・クリアの記録には触れない（読むだけ）。cancel() でいつでも元の見た目へ戻す。

const DefeatWarmup = preload("res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_warmup.gd")
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
const VictoryPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
const ScreenClose = preload("res://src/bossmaker/visuals/encounter/rbm_screen_close.gd")
const EncounterAssets = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_assets.gd")
const Audio = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_audio.gd")
## 登場の素材が揃うまで待つ上限（秒）。超えたら登場を出さずに戦闘を始める（黒い画面のまま止まらないように）。
const INTRO_WAIT_LIMIT := 6.0
## 勝利の素材が揃うまで待つ上限（秒）。超えたら揃っている物だけで始める。
const VICTORY_WAIT_LIMIT := 2.0

signal intro_finished
signal victory_result_shown

var view: Control
var audio: Node
## この戦闘で登場・勝利の演出を使うか（begin_battle() で有効、deactivate() で無効）。
var active := false
var boss_name := ""
var author := ""
## 検証用: 素材がキャッシュに無い時も読み込んでよいか（本番は false）。
var allow_load := false

var _defeat_warmup: Node2D
var _defeat_materials_requested := false
var _intro: Node2D
var _intro_wait := -1.0     # 登場の素材を待っている間の経過秒（待っていない時は -1）
var _intro_done_fn: Callable
var _victory: Node2D
var _victory_state := "none"  # none / final / waiting / playing / shown
var _victory_wait := 0.0
var _clock_start_ms := -1
var clear_seconds := 0.0
var final_turn := 0
var timeline: Array = []

func setup(battle_view: Control) -> void:
	view = battle_view
	name = "EncounterDirector"
	audio = Audio.new()
	audio.name = "EncounterAudio"
	add_child(audio)
	set_process(false)

## 戦闘画面の操作の流れで始めた戦闘で呼ぶ（info: {boss_name, author}）。
func begin_battle(info: Dictionary) -> void:
	cancel()
	active = true
	boss_name = str(info.get("boss_name", ""))
	author = str(info.get("author", ""))
	_clock_start_ms = -1
	clear_seconds = 0.0
	final_turn = 0
	timeline.clear()

## 登場・勝利を使わない戦闘（start_battle() を直接呼んだ）。
func deactivate() -> void:
	cancel()
	active = false
	if is_inside_tree():
		ScreenClose.release_all(get_tree())

func stage() -> Control:
	if not is_instance_valid(view):
		return null
	var row = view.get("_battlefield_ally_row")
	if not is_instance_valid(row) or not row.has_meta("visual_stage"):
		return null
	return row.get_meta("visual_stage") as Control

func hud() -> Control:
	var st := stage()
	return st.get_meta("battle_hud") as Control if is_instance_valid(st) and st.has_meta("battle_hud") else null

func boss_asset() -> String:
	var st := stage()
	if not is_instance_valid(st):
		return ""
	return str((st.get("_asset_ids") as Dictionary).get("boss", ""))

func party_assets() -> Array:
	var st := stage()
	var out: Array = []
	if not is_instance_valid(st):
		return out
	for key in st.get("_party_keys"):
		out.append(str((st.get("_asset_ids") as Dictionary).get(key, "")))
	return out

## 登場か勝利（結果パネルを出すまで）を再生している・待っているか。この間は行動を受け付けない。
func is_playing() -> bool:
	return _intro_wait >= 0.0 or is_instance_valid(_intro) or _victory_state in ["final", "waiting", "playing"]

## 結果パネルを隠しておく間か（勝利の決着が分かってから、勝利演出が結果パネルを出すまで）。
func holds_outcome() -> bool:
	return _victory_state in ["final", "waiting", "playing"]

# ---------------------------------------------------------------------------
# 登場

## 登場を流す。素材・画面が揃うまで待ってから始め、終わったら on_done を呼ぶ。登場が無い時はすぐ on_done。
func play_intro(on_done: Callable) -> void:
	_intro_done_fn = on_done
	if not active:
		_finish_intro()
		return
	_intro_wait = 0.0
	_lock(true)
	set_process(true)

func _intro_ready() -> bool:
	if not is_instance_valid(view) or not view.is_visible_in_tree():
		return false
	var wb = view.get("_world_battle")
	if wb == null or not bool(wb.get("built")):
		return false
	var st := stage()
	if not is_instance_valid(st) or not (st.get("_visuals") as Dictionary).has("boss"):
		return false
	var boss := boss_asset()
	_prepare_defeat_material(boss)
	if not IntroPlayer.has_intro(boss):
		return true
	return _assets_ready([[boss, "intro"], [boss, "final_blow"]] + _ally_kinds("intro_ally"))

## GPU compilation only; the existing material-ready and intro/result contracts remain unchanged.
func _prepare_defeat_material(boss: String) -> void:
	if _defeat_materials_requested: return
	_defeat_materials_requested = true
	if DisplayServer.get_name() == "headless" or not DefeatWarmup.supports(boss): return
	var session = view.get("session")
	var can_awaken: bool = session != null and session.battle != null and not session.battle.awakening.is_empty()
	if not can_awaken and not boss.ends_with("_awakened"): return
	_defeat_warmup = DefeatWarmup.new()
	_defeat_warmup.subject = boss.trim_suffix("_awakened")
	add_child(_defeat_warmup)

func _ally_kinds(kind: String) -> Array:
	var out: Array = []
	for a in party_assets():
		out.append([a, kind])
	return out

## 事前読み込みに、その素材を読み終えたか聞く（足りない物は先頭に回して読ませる）。
func _assets_ready(requests: Array) -> bool:
	var st := stage()
	var warm = st.get("_presentation_warmup") if is_instance_valid(st) else null
	if warm == null:
		return true
	var ready := true
	for r in requests:
		if not (warm.call("ensure", EncounterAssets, str(r[0]), str(r[1])) as Array).is_empty():
			ready = false
	return ready

func _start_intro() -> void:
	_intro_wait = -1.0
	var boss := boss_asset()
	if not IntroPlayer.has_intro(boss):
		ScreenClose.release_all(get_tree())
		_finish_intro()
		return
	audio.hold(IntroPlayer.warm_paths_keys(boss), allow_load)
	var p: Node2D = IntroPlayer.new()
	p.boss = boss
	p.boss_name = boss_name
	p.author = author
	p.setup(stage(), view, hud(), audio)
	_intro = p
	p.finished.connect(_on_intro_player_finished)
	p.play()
	timeline.append(["intro_start", Time.get_ticks_msec()])
	# 黒い幕（前の画面が閉じた後）を外す。登場は黒から始まる。
	ScreenClose.release_all(get_tree())

func _on_intro_player_finished() -> void:
	_intro = null
	timeline.append(["intro_end", Time.get_ticks_msec()])
	_finish_intro()

func _finish_intro() -> void:
	_intro_wait = -1.0
	_lock(false)
	# クリアタイムは、登場が終わって操作できるようになった時から数える
	_clock_start_ms = Time.get_ticks_msec()
	intro_finished.emit()
	var fn := _intro_done_fn
	_intro_done_fn = Callable()
	if fn.is_valid():
		fn.call()

# ---------------------------------------------------------------------------
# 勝利

## presenter の entry_impact ごとに呼ぶ。味方の勝ちで決着した命中なら、とどめのスローを始める。
func on_impact(entry: Dictionary) -> void:
	if not active or _victory_state != "none":
		return
	var vs: Dictionary = entry.get("visual_state", {})
	if not bool(vs.get("battle_over", false)) or str(vs.get("winner", "")) != "ally":
		return
	var boss := boss_asset()
	if not VictoryPlayer.has_victory(boss) or not is_instance_valid(stage()):
		return
	final_turn = int(vs.get("turn", 1))
	clear_seconds = maxf(0.0, (Time.get_ticks_msec() - _clock_start_ms) / 1000.0) if _clock_start_ms >= 0 else 0.0
	timeline.append(["final_impact", Time.get_ticks_msec()])
	audio.hold(VictoryPlayer.final_blow_keys(), allow_load)
	var p: Node2D = VictoryPlayer.new()
	p.boss = boss
	p.boss_name = boss_name
	p.turn = final_turn
	p.clear_seconds = clear_seconds
	p.setup(stage(), view, hud(), audio)
	p.show_result_fn = _on_victory_show_result
	_victory = p
	_victory_state = "final"
	p.on_final_impact()

## presenter の finished で呼ぶ。勝利演出を始めたら true（呼び出し元は結果パネルを出さず、入力も止めたままにする）。
func on_presentation_finished() -> bool:
	if _victory_state != "final":
		return false
	_victory_state = "waiting"
	_victory_wait = 0.0
	_lock(true)
	set_process(true)
	return true

func _victory_ready() -> bool:
	var boss := boss_asset()
	return _assets_ready([[boss, "victory"]] + _ally_kinds("victory_ally"))

func _begin_victory() -> void:
	_victory_state = "playing"
	timeline.append(["victory_begin", Time.get_ticks_msec()])
	audio.hold(VictoryPlayer.victory_keys(boss_asset()), allow_load)
	(_victory.get_script() as Script).call("hold_ally_sheets", party_assets(), allow_load)
	_victory.call("begin")

func _on_victory_show_result() -> void:
	_victory_state = "shown"
	timeline.append(["victory_result", Time.get_ticks_msec()])
	_lock(false)
	victory_result_shown.emit()
	if is_instance_valid(view) and view.has_method("_on_encounter_result_shown"):
		view.call("_on_encounter_result_shown")

func _process(delta: float) -> void:
	if _intro_wait >= 0.0:
		_intro_wait += delta
		if _intro_ready():
			_start_intro()
		elif _intro_wait >= INTRO_WAIT_LIMIT:
			push_warning("encounter intro skipped: assets or screen not ready")
			ScreenClose.release_all(get_tree())
			_finish_intro()
	if _victory_state == "waiting":
		_victory_wait += delta
		if _victory_ready() or _victory_wait >= VICTORY_WAIT_LIMIT:
			_begin_victory()
	if _intro_wait < 0.0 and _victory_state != "waiting":
		set_process(false)

# ---------------------------------------------------------------------------

## 今の演出をやめて、元の見た目へ戻す（戦闘をやり直す・画面を出る・画面が隠れる・REWIND）。
func cancel() -> void:
	if is_instance_valid(_defeat_warmup): _defeat_warmup.queue_free()
	_defeat_warmup = null
	_defeat_materials_requested = false
	var was_locked := is_playing()
	_intro_wait = -1.0
	_intro_done_fn = Callable()
	if is_instance_valid(_intro):
		_intro.call("cancel")
	_intro = null
	if is_instance_valid(_victory):
		_victory.call("cancel")
	_victory = null
	_victory_state = "none"
	if is_instance_valid(audio):
		audio.stop_all()
	# 前の画面が閉じた後の黒い幕は、ここでは外さない（戦闘を始め直す時、登場が始まるまで黒のまま待つため。
	# 幕は登場が始まった時・登場を出さないと決まった時に外し、外されなくても rbm_screen_close.gd が上限の秒数で外す）。
	set_process(false)
	if was_locked:
		_lock(false)

func _lock(on: bool) -> void:
	if is_instance_valid(view) and view.has_method("_set_presentation_input_locked"):
		view.call("_set_presentation_input_locked", on)

func _exit_tree() -> void:
	cancel()
