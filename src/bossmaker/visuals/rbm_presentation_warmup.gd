extends Node
## 演出の素材の事前読み込み(共通部品・表示専用)。
## 演出の多くは、再生を始めたフレームや途中で画像・音・データを load() する。起動して最初の再生では
## それがその場の読み込みになり、演出の始まりが止まる。ここでは、この戦闘の演出が読むものを裏のスレッドで
## 読み込み、参照を持つ。Godot のリソースキャッシュに残るので、演出側の load() はそのまますぐに返る
## (演出の描き方・時刻は変えない)。
##
## いつ読み始めるか(QA-06):
## - 戦闘を始める前の画面(Creator の最終確認・クリアチェックの確認・挑戦のボスの確認)が、ステージの
##   prepare_presentations() 経由で prepare() を呼ぶ。ボス・外見・味方・技・覚醒が確定した最も早い時点で、
##   戦闘画面を開く前から読み始める(計画のためだけに、使い捨ての戦闘を作る)。
## - 戦闘が始まると(ステージの configure())、その戦闘で計画し直す。同じ内容なら持っている物はそのまま。
## - prepare() されずに戦闘が始まった時だけ、戦闘画面を開いた直後の重いフレームを避けて
##   START_DELAY_FRAMES 待ってから読み始める。
## - release() で手放す(戦闘を出る時・確認画面を離れる時)。
## - 演出を始める時に、その演出の素材をまだ読み終えていなければ(戦闘を始める前の画面からすぐに戦闘を始めた・
##   遅い PC など)、ステージがその行動の演出の開始を待ち、ここが足りない素材を先頭に回して読む(ensure())。
##   事前読み込みを早く始めるのが第一の対策で、この待ちは、間に合わない時も演出の最中に同期で読まないための安全策。
##
## 何を先に読むか: 戦闘の流れ(rbm_battle.gd の advance_to_next_decision)で、早く要る可能性がある順。
##   1. 戦闘を開くと同時に再生されうる物: 1ターン目のターン開始時の指定行動 → 開始時に条件を満たす覚醒
##      → ボスが味方全員より速い時(同じ速さは味方が先)のボスの技と1ターン目の置き換えの指定行動
##   2. 最初の入力で再生されうる物: 開始時に使える味方の専用の技 → HP の条件を持つ覚醒(最初の攻撃で満たしうる)
##   3. ボスの1ターン目の技 → 味方の被弾・防御の姿勢 → 1ターン目の終わりの指定行動
##   4. それ以降(ほかの覚醒・開始時に使えない味方の専用の技)
## 覚醒した後(ボスの外見が覚醒後に替わった後)は、覚醒後の外見の技へ計画し直す。
##
## 何を読むかは、各演出スクリプトの静的関数 warm_paths(asset_id, kind) -> Array[String] が宣言する
## (ボス・技ごとの知識は演出側に置く)。kind は "single" / "all" / "support" / "awakening"、
## 味方の専用の技では SKILL_PRESENTATIONS の kind。共通の決まりとして、味方の被弾・防御の姿勢
## (REACTION_POSES)も読む(どのボスの攻撃でも使う)。
## 読み込みは1件ずつ頼む(読み終えた画像をGPUへ送る処理が1フレームに重ならないように)。
## 戦闘の状態・乱数・行動順・保存データは読むだけで変えない。
const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
## 味方の防御・かばう(10)と被弾(11)の姿勢。
const REACTION_POSES := [10, 11]
## rbm_battle_stage.gd の振り分けと同じ分け方: 回復・強化は支援、全体を狙う技は全体、それ以外は単体。
const SUPPORT_EFFECTS := ["heal", "self_heal", "buff_atk_self", "atk_self_buff"]
const KIND_ORDER := ["single", "all", "support"]
## 覚醒の条件のうち、最初の攻撃(ボスの HP の変化)で満たしうるもの。
const HP_CONDITIONS := ["hp_at_most", "hp_at_least", "hp_between"]
## prepare() されずに戦闘が始まった時、読み始めるまで待つフレーム数(戦闘画面を開いた直後の重いフレームに重ねない)。
const START_DELAY_FRAMES := 30

var _stage: Control
var _key := ""
var _planned: Array[String] = []
var _queue: Array[String] = []
var _loading := ""
var _held: Dictionary = {}
## 読み始めるまで待つ残りのフレーム数(prepare() されていない戦闘の時だけ)。
var _hold_frames := 0
## prepare() で受け取った計画の材料 {key, battle(使い捨て), boss_id, party}。release() で空にする。
var _prepared: Dictionary = {}
## prepare()・release() の時点でステージが持っていた(前の)戦闘。これは計画の材料にしない。
var _ignored_battle := 0
## prepare() で頼まれた準備(使い捨ての戦闘を作る → 計画を作る、を別々のフレームで行う)。
var _prepare_request: Dictionary = {}
## 読めなかった素材(演出の開始をこれのために待たない)。
var _failed: Dictionary = {}
## 演出スクリプト -> warm_paths() を持つか
static var _declares: Dictionary = {}
## パス -> 素材があるか(ResourceLoader.exists() を計画のたびに繰り返さない)
static var _exists: Dictionary = {}

func configure(stage: Control) -> void:
	_stage = stage

func _process(_delta: float) -> void:
	_collect()
	if _step_prepare():
		return
	refresh()
	if _hold_frames > 0:
		_hold_frames -= 1
	else:
		_request()

## 戦闘を始める前の画面から(ステージ経由で)呼ぶ。この戦闘の演出の素材を、次のフレームから裏で読み始める。
## 呼んだ画面のフレームを重くしないように、ここでは頼むだけにして、使い捨ての戦闘を作る・計画を作るは
## この後のフレームで1つずつ行う(_step_prepare())。
func prepare(definition: Dictionary, appearance_id: String) -> void:
	var key := "prepare|%d|%s" % [definition.hash(), appearance_id]
	if str(_prepared.get("key", "")) == key or str(_prepare_request.get("key", "")) == key:
		return
	_prepare_request = {"key": key, "definition": definition, "appearance": appearance_id}
	_ignored_battle = _battle_id()

## 頼まれた準備を1段進めた時は true(そのフレームはほかの処理をしない)。
func _step_prepare() -> bool:
	if _prepare_request.is_empty():
		return false
	if not _prepare_request.has("battle"):
		var started := RBMDefinitionLoader.start_battle(_prepare_request["definition"], 0)
		if not bool(started.get("ok", false)):
			release()
			return true
		_prepare_request["battle"] = started["battle"]
		return true
	var battle = _prepare_request["battle"]
	var party: Array = []
	for unit in battle.party:
		party.append(str(unit.character_id))
	_prepared = {"key": _prepare_request["key"], "battle": battle, "boss_id": Assets.boss_asset(str(_prepare_request["appearance"])), "party": party}
	_prepare_request = {}
	refresh()
	_request()
	return true

## 事前読み込みで持っていた素材を手放す(戦闘を出る時・確認画面を離れる時)。次の prepare() か、新しい戦闘が
## 始まるまで読まない(ステージが持ったままの前の戦闘からは計画しない)。
func release() -> void:
	_prepared = {}
	_prepare_request = {}
	_ignored_battle = _battle_id()
	_key = ""
	_planned.clear()
	_queue.clear()
	_held.clear()
	_hold_frames = 0
	_failed.clear()

## 計画の材料が替わった時だけ計画し直し、要らなくなったものを手放す。
func refresh() -> void:
	var source := _source()
	var key := str(source.get("key", ""))
	if key == _key:
		return
	_key = key
	_planned = plan_from(source)
	for path in _held.keys():
		if not _planned.has(path):
			_held.erase(path)
	_queue.clear()
	for path in _planned:
		if not _held.has(path) and path != _loading:
			_queue.append(path)
	_hold_frames = START_DELAY_FRAMES if bool(source.get("from_battle", false)) and _prepared.is_empty() and _prepare_request.is_empty() and not _queue.is_empty() else 0

## この戦闘の演出が読むもの(存在するものだけ、重複なし、早く要る可能性がある順)。
func plan_from(source: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var battle = source.get("battle")
	var boss_id := str(source.get("boss_id", ""))
	if battle == null or boss_id.is_empty() or not is_instance_valid(_stage):
		return out
	var tables := {"single": _stage.BOSS_SINGLE_PRESENTATIONS, "all": _stage.BOSS_ALL_PRESENTATIONS, "support": _stage.BOSS_SUPPORT_PRESENTATIONS}
	var party: Array = source.get("party", [])
	var kinds := _boss_kinds(battle)
	# 覚醒は、覚醒する前の外見の間だけ(覚醒した後は覚醒後の外見の技へ計画し直す)。
	var awakening: Dictionary = battle.awakening
	var awakening_script = null if boss_id.ends_with(Assets.AWAKENED_SUFFIX) else _stage.BOSS_AWAKENING_PRESENTATIONS.get(boss_id)
	var can_awaken := awakening_script != null and not awakening.is_empty()
	# 1. 戦闘を開くと同時に再生されうる物
	for kind in _scripted_kinds(battle, "turn_start_interrupt"):
		_ask(out, tables[kind].get(boss_id), boss_id, kind)
	if can_awaken and battle._evaluate_condition_group(awakening):
		_ask(out, awakening_script, boss_id, "awakening")
	if _boss_acts_first(battle):
		for kind in _scripted_kinds(battle, "replace") + kinds:
			_ask(out, tables[kind].get(boss_id), boss_id, kind)
	# 2. 最初の入力で再生されうる物
	var later_skills: Array = []
	for skill_id in _stage.SKILL_PRESENTATIONS:
		var entry: Dictionary = _stage.SKILL_PRESENTATIONS[skill_id]
		if _usable_at_start(battle, str(entry.get("actor", "")), str(skill_id)):
			_ask(out, entry.get("script"), str(entry.get("actor", "")), str(entry.get("kind", "")))
		elif party.has(str(entry.get("actor", ""))):
			later_skills.append(entry)
	if can_awaken and _has_hp_condition(awakening):
		_ask(out, awakening_script, boss_id, "awakening")
	# 3. ボスの1ターン目の技 → 味方の被弾・防御の姿勢 → 1ターン目の終わりの指定行動
	for kind in kinds:
		_ask(out, tables[kind].get(boss_id), boss_id, kind)
	for character_id in party:
		for pose in REACTION_POSES:
			_add(out, Assets.frame_path(str(character_id), pose))
	for kind in _scripted_kinds(battle, "turn_end_interrupt"):
		_ask(out, tables[kind].get(boss_id), boss_id, kind)
	# 4. それ以降
	if can_awaken:
		_ask(out, awakening_script, boss_id, "awakening")
	for entry in later_skills:
		_ask(out, entry.get("script"), str(entry.get("actor", "")), str(entry.get("kind", "")))
	return out

## 演出を始める境界(ステージの _start_dedicated())から呼ぶ。その演出が宣言した素材のうち、まだ読み終えて
## いない物を返す(空なら始めてよい)。読み終えていない物は計画に加え(手放されないように)、読む順の先頭へ回す。
## 読めなかった素材は待たない(演出がこれまでどおり自分で読もうとする)。
func ensure(script: Variant, asset_id: String, kind: String) -> Array[String]:
	_collect()
	var paths: Array[String] = []
	_ask(paths, script, asset_id, kind)
	var missing: Array[String] = []
	for path in paths:
		if _held.has(path) or _failed.has(path):
			continue
		if not _planned.has(path):
			_planned.append(path)
		if ResourceLoader.has_cached(path):
			# 既に読み込まれている(参照を持つだけ。読み込みは起きない)。
			_held[path] = load(path)
			continue
		missing.append(path)
	for i in range(missing.size() - 1, -1, -1):
		if missing[i] != _loading:
			_queue.erase(missing[i])
			_queue.push_front(missing[i])
	if not missing.is_empty():
		_hold_frames = 0
		_request()
	return missing

## 持っているもの(テスト・計測用)。
func held_paths() -> Array:
	return _held.keys()

func planned_paths() -> Array[String]:
	return _planned.duplicate()

## 計画したものをすべて読み終えたか(計画が無い時は false)。
func is_ready() -> bool:
	return not _key.is_empty() and _queue.is_empty() and _loading.is_empty()

## 計画の材料: ステージが新しい戦闘を持っていればその戦闘、無ければ prepare() で受け取った物。
func _source() -> Dictionary:
	var id := _battle_id()
	if id != 0 and id != _ignored_battle:
		var party: Array = []
		for key in _stage._party_keys:
			party.append(str(_stage._asset_ids.get(key, "")))
		var boss_id := str(_stage._asset_ids.get("boss", ""))
		return {"key": "battle|%d|%s|%s" % [id, boss_id, party], "battle": _stage._battle, "boss_id": boss_id, "party": party, "from_battle": true}
	return _prepared

func _battle_id() -> int:
	if not is_instance_valid(_stage) or _stage._battle == null:
		return 0
	return _stage._battle.get_instance_id()

static func _kind_of(skill: Dictionary) -> String:
	if str(skill.get("effect", skill.get("type", "damage"))) in SUPPORT_EFFECTS:
		return "support"
	if str(skill.get("target", "")) in ["ally_all", "all"]:
		return "all"
	return "single"

func _boss_kinds(battle) -> Array[String]:
	var found := {}
	for skill in battle.boss.skills:
		found[_kind_of(skill)] = true
	var kinds: Array[String] = []
	for kind in KIND_ORDER:
		if found.has(kind):
			kinds.append(kind)
	return kinds

## 1ターン目の指定行動(timing ごと)の技の種類。
func _scripted_kinds(battle, timing: String) -> Array[String]:
	var kinds: Array[String] = []
	for entry in battle.boss_def.get("scripted_actions", []):
		if int(entry.get("turn", -1)) != 1 or str(entry.get("timing", "")) != timing:
			continue
		for skill in battle.boss.skills:
			if str(skill.get("id", "")) == str(entry.get("skill_id", "")) and not kinds.has(_kind_of(skill)):
				kinds.append(_kind_of(skill))
	return kinds

## 行動順は速さの降順で、同じ速さなら味方が先(RBMBattle._compute_turn_order)。
static func _boss_acts_first(battle) -> bool:
	for unit in battle.party:
		if int(unit.spd) >= int(battle.boss.spd):
			return false
	return true

static func _has_hp_condition(awakening: Dictionary) -> bool:
	for condition in awakening.get("conditions", []):
		if str(condition.get("type", "")) in HP_CONDITIONS:
			return true
	return false

## 味方の専用の技を、戦闘の開始時の SP で使えるか。
static func _usable_at_start(battle, character_id: String, skill_id: String) -> bool:
	for unit in battle.party:
		if str(unit.character_id) != character_id:
			continue
		for skill in unit.skills:
			if str(skill.get("id", "")) == skill_id:
				return int(unit.sp) >= int(skill.get("sp_cost", 0))
	return false

func _ask(out: Array[String], script: Variant, asset_id: String, kind: String) -> void:
	if not script is Script or not _declares_paths(script):
		return
	for path in (script as Script).call("warm_paths", asset_id, kind):
		_add(out, str(path))

static func _declares_paths(script: Script) -> bool:
	if not _declares.has(script):
		var found := false
		for method in script.get_script_method_list():
			if str(method.name) == "warm_paths":
				found = true
				break
		_declares[script] = found
	return bool(_declares[script])

static func _add(out: Array[String], path: String) -> void:
	if path.is_empty() or out.has(path):
		return
	if not _exists.has(path):
		_exists[path] = ResourceLoader.exists(path)
	if _exists[path]:
		out.append(path)

func _request() -> void:
	while _loading.is_empty() and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if _held.has(path):
			continue
		if ResourceLoader.has_cached(path):
			# 既に読み込まれている(参照を持つだけ。読み込みは起きない)。
			_held[path] = load(path)
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_loading = path
		else:
			_failed[path] = true

func _collect() -> void:
	if _loading.is_empty() or ResourceLoader.load_threaded_get_status(_loading) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var resource := ResourceLoader.load_threaded_get(_loading)
	if resource == null:
		_failed[_loading] = true
	elif _planned.has(_loading):
		_held[_loading] = resource
	_loading = ""

## 頼んだ読み込みは必ず1回受け取る(受け取らないと、読み込み側が素材を持ち続ける)。ステージが別の親へ
## 付け替えられる時(戦闘画面が全画面の配置へ移す時。_exit_tree)は、準備も読み込みもそのまま続ける。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _loading.is_empty():
		ResourceLoader.load_threaded_get(_loading)
		_loading = ""
