class_name RBMHomeTopMonitorBattlePreview
extends Control

## ホーム画面(タイトル画面)の上中央モニターへ、実際のM&C戦闘を無音・自動
## ループ再生するプレビュー。承認済み独立プレビュー(tools/preview_home_
## top_monitor_battle_gpu.gd、確認後に削除済み)の見た目・タイミング・
## 固定シーケンスをそのまま本番実装したもの——新しいデザイン・演出提案は
## 行っていない。
##
## 設計方針:
## - 別SubViewportでRBMChallengeBattleView(本番と同じクラス)を裏レンダリ
##   ングし、UIチャンパネル(行動順/コマンド/HP・SPカード/ログ/ボス名バナー/
##   やり直し/やめる)だけを非表示にした戦場そのものを、承認済みクロップ窓
##   (BATTLE_CROP)でモニターRectへはめ込む。横伸ばしはしない。
## - 技の発火はRBMBattleStage.play_entry()を直接呼ぶ、既存QAツール
##   (tools/verify_battle_visuals_gpu.gd等)と同じ手法——戦闘シミュレー
##   ション/乱数/行動順には一切触れない、表示専用の再生。
## - start_loop()/stop_loop()はRBMGameRoot側から、ホーム画面の表示/非表示
##   に合わせて呼ばれる想定(タイトル/ホームを離れたら停止、戻ったら再開)。

const SCREEN_SIZE := Vector2(1280.0, 720.0)
# 承認済みクロップ窓(実測: tools/_inspect_battle_layout2_gpu.gd、
# tools/_crop_test2_gpu.gd、いずれも確認後に削除済み)。ボス+味方4人の
# 全身(足元まで)とステージ地面が収まる。
const BATTLE_CROP := Rect2(164.0, 240.0, 780.0, 294.0)
const ROSTER := ["hero", "butler", "samurai", "healer"]

var _battle_sub: SubViewport
var _view: RBMChallengeBattleView
var _stage: Node
var _feed: RBMHomeTopMonitorBattleDraw
var _masters: Dictionary = {}
var _hero_id := -1
var _butler_id := -1
var _samurai_id := -1
var _healer_id := -1

var _running := false
var _initialized := false
var _run_token := 0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_battle_sub = SubViewport.new()
	_battle_sub.name = "TopMonitorBattleSubViewport"
	_battle_sub.size = Vector2i(int(SCREEN_SIZE.x), int(SCREEN_SIZE.y))
	_battle_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_battle_sub)

	_feed = RBMHomeTopMonitorBattleDraw.new()
	_feed.name = "BattleFeed"
	_feed.position = Vector2.ZERO
	_feed.size = size
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	resized.connect(func():
		_feed.size = size)

	call_deferred("_init_battle")

func _init_battle() -> void:
	# 音声完全OFF(このプレビュー専用のSubViewport内で完結させたいところだが、
	# Masterバス全体をmuteする方式はRBMHomeMonitorSfx等ホーム画面側の他の
	# 音にも影響するため、代わりにこのバトル映像自体が音を鳴らさないよう
	# RBMAudioへは一切bindしない(通常のUIボタンのみが自動バインドされる
	# 仕組みのため、ここでは何もしなければ鳴らない)。
	var definition: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	definition["party"] = []
	for id in ROSTER:
		var master: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/allies/" + id + ".json")
		_masters[id] = master
		var skill_ids: Array = []
		for skill in master.get("skills", []):
			skill_ids.append(skill["id"])
		definition["party"].append({"character_id": id, "allowed_skill_ids": skill_ids})

	_view = RBMChallengeBattleView.new()
	_battle_sub.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.set_boss_appearance("appearance_golem")
	_view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_golem")

	for i in range(8):
		await get_tree().process_frame
	var ticks := 0
	while _view._presenter.is_playing() and ticks < 600:
		await get_tree().process_frame
		ticks += 1

	_view._boss_label.visible = false
	_view._party_rows.visible = false
	_view._turn_order_panel.visible = false
	_view._command_area.visible = false
	_view._restart_button.visible = false
	_view._quit_button.visible = false
	var log_row := _view.find_child("LogRow", true, false) as Control
	if log_row != null:
		log_row.visible = false

	_stage = _view._battlefield_ally_row.get_meta("visual_stage", null)
	_hero_id = _actor_id("hero")
	_butler_id = _actor_id("butler")
	_samurai_id = _actor_id("samurai")
	_healer_id = _actor_id("healer")

	_feed.source_tex = _battle_sub.get_texture()
	_feed.src_rect = BATTLE_CROP

	_initialized = true
	if _running:
		_loop_forever(_run_token)

## ホーム画面へ入った/戻った時に呼ぶ。多重起動しても安全(既に再生中なら
## 何もしない)。
func start_loop() -> void:
	if _running:
		return
	_running = true
	_battle_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _initialized:
		_loop_forever(_run_token)

## ホーム画面を離れる時に呼ぶ。再生中のシーケンスは次のawait地点で自然に
## 停止する(_run_tokenの不一致で判定)——戦闘シミュレーションには一切
## 触れていないため、途中で止めても不整合は起きない。
func stop_loop() -> void:
	_running = false
	_run_token += 1
	if is_instance_valid(_battle_sub):
		_battle_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _actor_id(character_id: String) -> int:
	for unit in _view.session.battle.party:
		if unit.character_id == character_id:
			return unit.id
	return -1

func _skill(character_id: String, skill_id: String) -> Dictionary:
	for skill in _masters[character_id].get("skills", []):
		if skill.get("id") == skill_id:
			return skill
	return {}

func _loop_forever(token: int) -> void:
	while _alive(token):
		await _play_sequence(token)

## 固定シーケンス(承認済み、ランダム化なし):
## 待機 → ヒーラー雷単体 → 勇者必殺 → 老執事必殺 →
## 侍カウンター構え → ボス単体攻撃(必ず侍へ) → カウンター成立 →
## ヒーラー必殺(全体回復) → 待機 → (呼び出し元でループ)
func _play_sequence(token: int) -> void:
	await _hold(token, 1.5)
	if not _alive(token):
		return

	await _play(token, {"actor": _healer_id, "action": "skill", "skill_id": "healer_shock", "target": "boss", "amount": 20}, _skill("healer", "healer_shock"))
	await _hold(token, 0.2)
	if not _alive(token):
		return

	await _play(token, {"actor": _hero_id, "action": "skill", "skill_id": "hero_burst_slash", "target": "boss", "amount": 40}, _skill("hero", "hero_burst_slash"))
	await _hold(token, 0.2)
	if not _alive(token):
		return

	await _play(token, {"actor": _butler_id, "action": "skill", "skill_id": "butler_grand_ice", "target": "boss", "amount": 60}, _skill("butler", "butler_grand_ice"))
	await _hold(token, 0.2)
	if not _alive(token):
		return

	await _play(token, {"actor": _samurai_id, "action": "skill", "skill_id": "samurai_counter"}, _skill("samurai", "samurai_counter"))
	await _hold(token, 0.15)
	if not _alive(token):
		return

	await _play(token, {"actor": "boss", "action": "attack", "target": _samurai_id, "amount": 20, "counter": true}, {})
	await _hold(token, 0.2)
	if not _alive(token):
		return

	var healed: Dictionary = {_hero_id: 200, _butler_id: 200, _samurai_id: 200, _healer_id: 200}
	await _play(token, {"actor": _healer_id, "action": "skill", "skill_id": "healer_heal_all", "healed": healed}, _skill("healer", "healer_heal_all"))

	await _hold(token, 1.0)

func _alive(token: int) -> bool:
	return _running and token == _run_token and is_instance_valid(_stage)

func _play(token: int, entry: Dictionary, skill: Dictionary) -> void:
	if not _alive(token):
		return
	_stage.play_entry(entry, skill)
	var ticks := 0
	while _alive(token) and _stage.is_playing() and ticks < 420:
		await get_tree().process_frame
		ticks += 1

func _hold(token: int, seconds: float) -> void:
	var elapsed := 0.0
	while _alive(token) and elapsed < seconds:
		await get_tree().process_frame
		var dt: float = get_tree().root.get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		elapsed += dt
