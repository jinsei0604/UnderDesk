class_name RBMBattlePresenter
extends Node

## Displays already-resolved battle events. Never advances or mutates the simulation.
## The stage owns motion timing; its impact signal commits the corresponding HUD state.
signal entry_impact(entry: Dictionary)
## 1つの出来事の演出を始める時(entry_impact の前に1回)。BGM が覚醒の演出の始まりを知るのに使う(rbm_battle_bgm.gd)。
signal entry_started(entry: Dictionary)
## 侍のカウンターで entry_impact が反撃の瞬間まで遅れる全体攻撃で、ボスの攻撃が仲間に当たった瞬間に1回。
## entry は当たった仲間だけ(防いだ侍・反撃を除く)、state は「当たった仲間の HP だけ進めた表示」。HUD の HP・左下の文字を
## ダメージの数字と同じ瞬間に合わせるためだけのもの(記録・勝敗・次の行動は entry_impact のまま)。
signal entry_hits_landed(entry: Dictionary, state: Dictionary)
## 何回も当たる攻撃（2026-10-23）で、最後の一撃より前の当たりのたびに1回。state は「当たった分だけ HP を減らした表示」。
## HUD の HP をダメージの小さな数字と同じ瞬間に合わせるためだけのもの(記録・左下の文字・勝敗・次の行動は entry_impact のまま)。
signal entry_partial(state: Dictionary)
signal finished
## HUD の HP・SP のバーが新しい値へ動く時間(表示だけ。数値の文字はすぐ変わる)。
const BAR_EASE_TIME := 0.2

var enabled: bool = DisplayServer.get_name() != "headless"
var _stage: Node
var _battle: RBMBattle
var _entries: Array[Dictionary] = []
var _cursor: int = 0
var _playing: bool = false
var _impacted: bool = false
var _finishing_entry: bool = false
var _generation: int = 0
var _display_state: Dictionary = {}
## 今の出来事を始めた時の表示（何回も当たる攻撃で、当たった分を引く元）。
var _entry_start_state: Dictionary = {}

func setup(stage: Node) -> void:
	if _stage == stage:
		return
	cancel()
	if is_instance_valid(_stage):
		if _stage.has_signal("impact") and _stage.is_connected("impact", _on_stage_impact):
			_stage.disconnect("impact", _on_stage_impact)
		if _stage.has_signal("finished") and _stage.is_connected("finished", _on_stage_finished):
			_stage.disconnect("finished", _on_stage_finished)
		if _stage.has_signal("hits_landed") and _stage.is_connected("hits_landed", _on_stage_hits_landed):
			_stage.disconnect("hits_landed", _on_stage_hits_landed)
		if _stage.has_signal("partial_hits") and _stage.is_connected("partial_hits", _on_stage_partial_hits):
			_stage.disconnect("partial_hits", _on_stage_partial_hits)
	_stage = stage
	if is_instance_valid(_stage):
		if _stage.has_signal("impact"):
			_stage.connect("impact", _on_stage_impact)
		if _stage.has_signal("finished"):
			_stage.connect("finished", _on_stage_finished)
		if _stage.has_signal("hits_landed"):
			_stage.connect("hits_landed", _on_stage_hits_landed)
		if _stage.has_signal("partial_hits"):
			_stage.connect("partial_hits", _on_stage_partial_hits)

func can_animate() -> bool:
	return enabled and is_instance_valid(_stage) and _stage.has_method("play_entry") and _stage.has_signal("finished")

func is_playing() -> bool:
	return _playing

func display_state() -> Dictionary:
	return _display_state.duplicate(true)

func play(entries: Array, battle: RBMBattle, initial_state: Dictionary = {}) -> void:
	cancel()
	_battle = battle
	for entry in entries:
		_entries.append(entry)
	_display_state = initial_state.duplicate(true)
	if is_instance_valid(_stage) and _stage.has_method("set_state") and not initial_state.is_empty():
		_stage.call("set_state", _display_state)
	_playing = true
	_cursor = 0
	_advance(_generation)

func cancel() -> void:
	_generation += 1
	_playing = false
	_entries.clear()
	_cursor = 0
	_impacted = false
	_finishing_entry = false
	if is_instance_valid(_stage) and _stage.has_method("cancel"):
		_stage.call("cancel")

func _advance(generation: int) -> void:
	if generation != _generation or not _playing:
		return
	if _cursor >= _entries.size():
		_playing = false
		_entries.clear()
		finished.emit()
		return
	_impacted = false
	_finishing_entry = false
	var entry: Dictionary = _entries[_cursor]
	_entry_start_state = _display_state.duplicate(true)
	entry_started.emit(entry)
	# 味方の覚醒が解けた（"awakening_end"）は動きを持たない。表示（数値・オーラ・札）だけすぐ進める。
	if not can_animate() or str(entry.get("action", "none")) in ["none", "awakening_end"] or bool(entry.get("failed", false)):
		_on_stage_impact(entry)
		_on_stage_finished()
		return
	var skill := RBMBattleUiKit.find_skill_for_actor(entry.get("actor"), str(entry.get("skill_id", "")), _battle)
	_stage.call("play_entry", entry, skill)

func _on_stage_impact(incoming_entry: Dictionary) -> void:
	if not _playing or _impacted or _cursor >= _entries.size():
		return
	if incoming_entry != _entries[_cursor]:
		return
	_impacted = true
	var entry: Dictionary = _entries[_cursor]
	_display_state = (entry.get("visual_state", _display_state) as Dictionary).duplicate(true)
	if is_instance_valid(_stage) and _stage.has_method("set_state"):
		_stage.call("set_state", _display_state)
	entry_impact.emit(entry)

## カウンターの前に、ボスの攻撃が当たった仲間の HP だけを先に表示へ出す(entry_impact は反撃の瞬間のまま)。
func _on_stage_hits_landed(incoming_entry: Dictionary) -> void:
	if not _playing or _impacted or _cursor >= _entries.size():
		return
	if incoming_entry != _entries[_cursor]:
		return
	var entry: Dictionary = _entries[_cursor]
	var hit_entry := hits_before_counter(entry)
	if hit_entry.is_empty():
		return
	_display_state = state_before_counter(_display_state, entry)
	if is_instance_valid(_stage) and _stage.has_method("set_state"):
		_stage.call("set_state", _display_state)
	entry_hits_landed.emit(hit_entry, _display_state.duplicate(true))

## 何回も当たる攻撃の途中の当たり: 当たった分だけ HP を減らした表示を出す(entry_impact は最後の一撃のまま)。
func _on_stage_partial_hits(incoming_entry: Dictionary, landed: Dictionary) -> void:
	if not _playing or _impacted or _cursor >= _entries.size():
		return
	if incoming_entry != _entries[_cursor]:
		return
	_display_state = partial_state(_entry_start_state, _display_state, _entries[_cursor], landed)
	if is_instance_valid(_stage) and _stage.has_method("set_state"):
		_stage.call("set_state", _display_state)
	entry_partial.emit(_display_state.duplicate(true))

## 今の表示 current に、出来事を始めた時の HP（start）から当たった分（landed: {キー: 合計}）を引いた HP を入れたもの。
## 最後の一撃の後の HP（visual_state）より下には下げない。最後の一撃で戦闘不能になる相手も、最後の一撃までは 1 で止める
## （戦闘不能の表示・音は最後の一撃の entry_impact で）。HP 以外（SP・状態・ターン・勝敗）は変えない。
static func partial_state(start: Dictionary, current: Dictionary, entry: Dictionary, landed: Dictionary) -> Dictionary:
	var state := current.duplicate(true)
	var after: Dictionary = entry.get("visual_state", {})
	for key in landed:
		var is_boss := str(key) == "boss"
		var unit: Dictionary = state.get("boss", {}) if is_boss else (state.get("party", {}) as Dictionary).get(str(key), {})
		var first: Dictionary = start.get("boss", {}) if is_boss else (start.get("party", {}) as Dictionary).get(str(key), {})
		var last: Dictionary = after.get("boss", {}) if is_boss else (after.get("party", {}) as Dictionary).get(str(key), {})
		if unit.is_empty() or first.is_empty() or last.is_empty():
			continue
		var hp_start := int(first.get("hp", 0))
		var hp_final := int(last.get("hp", 0))
		var lowest := mini(hp_start, hp_final if hp_final > 0 else 1)
		unit["hp"] = clampi(hp_start - int(landed[key]), lowest, hp_start)
	return state

## 全体攻撃のうち、カウンターで防がれずに当たった仲間だけの出来事(反撃の情報を除く)。当たった仲間がいなければ空。
static func hits_before_counter(entry: Dictionary) -> Dictionary:
	if not entry.has("hits"):
		return {}
	var landed := {}
	var hits: Dictionary = entry["hits"]
	for uid in hits:
		var hit = hits[uid]
		if hit is Dictionary and bool(hit.get("blocked", false)):
			continue
		landed[uid] = hit
	if landed.is_empty():
		return {}
	var out := entry.duplicate(true)
	out["hits"] = landed
	for key in ["counter", "blocked", "reflected"]:
		out.erase(key)
	return out

## 直前の表示に、ボスの攻撃が当たった仲間の状態(HP・SP・戦闘不能)だけを進めたもの。ボス・ターン・勝敗・防いだ侍は
## まだ変えない(反撃の瞬間の entry_impact で visual_state 全体になる)。
static func state_before_counter(before: Dictionary, entry: Dictionary) -> Dictionary:
	var state := before.duplicate(true)
	var after: Dictionary = entry.get("visual_state", {})
	var party: Dictionary = state.get("party", {})
	var after_party: Dictionary = after.get("party", {})
	for uid in hits_before_counter(entry).get("hits", {}):
		var key := str(uid)
		if after_party.has(key):
			party[key] = (after_party[key] as Dictionary).duplicate(true)
	state["party"] = party
	return state

func _on_stage_finished() -> void:
	if not _playing or _finishing_entry or _cursor >= _entries.size():
		return
	# A stage without an impact marker still commits each event exactly once.
	if not _impacted:
		_on_stage_impact(_entries[_cursor])
	_finishing_entry = true
	_cursor += 1
	_advance.call_deferred(_generation)

func _exit_tree() -> void:
	cancel()

## Update existing named HUD nodes without destroying the actor playing a motion.
## animate: 命中の瞬間(演出の再生中)は HP・SP のバーを BAR_EASE_TIME で新しい値へ動かす。それ以外(画面の作り直し・
## REWIND・やり直し)はすぐ値を入れ、動いている途中のバーも止める。数値の文字はいつもすぐ変わる。
static func apply_status_snapshot(view: Control, state: Dictionary, animate := false) -> void:
	if state.is_empty():
		return
	var party: Dictionary = state.get("party", {})
	for id_key in party:
		var unit: Dictionary = party[id_key]
		var unit_id := int(unit.get("id", id_key))
		var hp := int(unit.get("hp", 0))
		var max_hp := int(unit.get("max_hp", 1))
		var sp := int(unit.get("sp", 0))
		var max_sp := int(unit.get("max_sp", RBMConstants.NO_SP))
		var name_label := view.find_child("PartyRowName_%d" % unit_id, true, false) as Label
		if name_label != null:
			name_label.text = "%s%s" % [TranslationServer.translate(str(unit.get("display_name", ""))), TranslationServer.translate("（戦闘不能）") if hp <= 0 else ""]
		var hp_label := view.find_child("PartyRowHP_%d" % unit_id, true, false) as Label
		if hp_label != null:
			hp_label.text = "HP %d / %d" % [hp, max_hp]
		var hp_bar := view.find_child("PartyRowHPBar_%d" % unit_id, true, false) as ProgressBar
		if hp_bar != null:
			_set_bar(hp_bar, maxf(1.0, float(max_hp)), hp, animate)
		var sp_label := view.find_child("PartyRowSP_%d" % unit_id, true, false) as Label
		if sp_label != null:
			sp_label.text = "SP -" if max_sp == RBMConstants.NO_SP else "SP %d / %d" % [sp, max_sp]
		var sp_bar := view.find_child("PartyRowSPBar_%d" % unit_id, true, false) as ProgressBar
		if sp_bar != null:
			_set_bar(sp_bar, maxf(1.0, float(max_sp)), sp, animate)
		var card := view.find_child("PartyRow_%d" % unit_id, true, false) as Control
		if card != null:
			card.modulate = Color(1.0, 1.0, 1.0, 0.55 if hp <= 0 else 1.0)
			apply_awakening_chip(card, unit_id, bool(unit.get("awakened", false)), int(unit.get("awakening_turns_left", 0)))
	var boss_label := view.find_child("BossLabel", true, false) as Label
	if boss_label != null:
		var boss: Dictionary = state.get("boss", {})
		boss_label.text = TranslationServer.translate("%s　（ターン%d）") % [str(boss.get("display_name", "")), int(state.get("turn", 1))]
	apply_boss_bar(view, state, animate)

## 味方のカードの「覚醒 残りN」の札（rbm_fullscreen_battle_ui.gd が作る。無いカードでは何もしない）。
## 残りは「あと何回の自分の行動で解けるか」（発動した行動の間は設定した回数のまま）。
static func apply_awakening_chip(card: Control, unit_id: int, awakened: bool, turns_left: int) -> void:
	var chip := card.find_child("PartyRowAwakening_%d" % unit_id, true, false) as Control
	if chip == null:
		return
	chip.visible = awakened
	var text := chip.find_child("PartyRowAwakeningText_%d" % unit_id, true, false) as Label
	if text != null:
		text.text = TranslationServer.translate("覚醒 残り%d") % maxi(0, turns_left) if awakened else ""

## ボスの HP バー（rbm_boss_hp_bar.gd）へ、表示している状態のボスを入れる。挑戦で作者が HP を非公開にしている時は量を出さない
## （ボスの詳細と同じ設定）。演出の再生中は命中の瞬間（apply_status_snapshot）だけ、それ以外は戦闘画面の配置の更新から呼ぶ。
static func apply_boss_bar(view: Control, state: Dictionary, animate := false) -> void:
	var boss_bar := view.find_child("BossHpBar", true, false)
	if boss_bar != null and boss_bar.has_method("apply_state"):
		var visibility = view.get("_visibility")
		var hp_visible: bool = not (visibility is Dictionary) or bool((visibility as Dictionary).get("hp", true))
		boss_bar.apply_state(state.get("boss", {}), bool(state.get("is_awakened", false)), hp_visible, animate)

## バーへ値を入れる。animate の時は今の値から BAR_EASE_TIME で動かす(実際の画面だけ。テストの画面のない実行ではすぐ入れる)。
## 前のバーの動きは必ず止める(REWIND・作り直しの値が、動いていた古い行き先で上書きされないように)。
static func _set_bar(bar: ProgressBar, max_value: float, value: float, animate: bool) -> void:
	if bar.has_meta("value_tween"):
		var running = bar.get_meta("value_tween")
		if running is Tween and (running as Tween).is_valid():
			# 同じ値へ動いている途中なら、そのまま動かす(何回も当たる攻撃で、別の人に当たるたびに動き直して着くのが遅れないように)
			if animate and is_equal_approx(float(bar.get_meta("value_target", NAN)), value) and is_equal_approx(bar.max_value, max_value):
				return
			(running as Tween).kill()
		bar.remove_meta("value_tween")
	bar.max_value = max_value
	if not animate or DisplayServer.get_name() == "headless" or not bar.is_inside_tree() or is_equal_approx(bar.value, value):
		bar.value = value
		return
	var tween := bar.create_tween()
	tween.tween_property(bar, "value", value, BAR_EASE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bar.set_meta("value_tween", tween)
	bar.set_meta("value_target", value)
