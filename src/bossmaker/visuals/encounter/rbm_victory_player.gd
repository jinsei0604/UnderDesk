extends Node2D
## 勝利演出（案B＋案C。表示専用）を再生する。RBMEncounterDirector が作って動かす。
## 本番の戦闘画面のまま、とどめの一撃（本番の味方の演出）の命中からスロー（案C）→ 決着の後にボスごとの倒れ方（案C）
## → 味方それぞれの反応・ファンファーレ・弾む VICTORY!（案B）＋撃破ターン・クリアタイム → 本番の結果パネル。
## 結果の判定・クリアの記録（challenge_won・クリアチェックの成功の記録）・保存には触れない（記録は今のゲームと同じ流れの
## 瞬間に行われ、この演出を待たない）。結果パネルとボタンは演出が終わるまで出さない（呼び出し元が隠し、終わりで出す）。飛ばせない。
## とどめのスローは、戦場の今の行動の動き（ステージの Tween）だけを遅くする（ステージの set_motion_speed()。ゲーム全体の
## 時間 Engine.time_scale は変えない）。cancel() で、いつでも元の見た目（カメラ・ボス・味方・HUD・速さ・音）へ戻す。

signal finished

const Overlay = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_overlay.gd")
const Camera = preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
const FX = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_fx.gd")
const Layer = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_layer.gd")
const Sprites = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_sprites.gd")
const SPRITE_SHADER = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_sprite.gdshader")
const Allies = preload("res://src/bossmaker/visuals/encounter/rbm_victory_allies.gd")
const Banner = preload("res://src/bossmaker/visuals/encounter/rbm_victory_banner.gd")
const AllyFrames = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_ally_frames.gd")
const Audio = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_audio.gd")
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
const AuraGuard = preload("res://src/bossmaker/visuals/encounter/rbm_defeat_aura_guard.gd")
const DEFEAT := {
	"plush": preload("res://src/bossmaker/visuals/plush/rbm_plush_defeat.gd"),
	"plush_awakened": preload("res://src/bossmaker/visuals/plush/rbm_plush_defeat.gd"),
	"musha_awakened": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_musha_awakened.gd"),
	"astronaut_awakened": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_astronaut_awakened.gd"),
	"gentleman_awakened": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_gentleman_awakened.gd"),
	"dragon_awakened": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_dragon_awakened.gd"),
	"slime": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_slime.gd"),
	"wolf": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_wolf.gd"),
	"knight": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_knight.gd"),
	"dragon": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_dragon.gd"),
	"ghost": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_ghost.gd"),
	"golem": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_golem.gd"),
	"musha": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_musha.gd"),
	"astronaut": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_astronaut.gd"),
	"gentleman": preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_gentleman.gd"),
}
## 共通の倒れ方（専用の倒れ方が覚醒前のコマ絵に依存するボスを、覚醒した後に倒した時）。
const GENERIC := preload("res://src/bossmaker/visuals/encounter/defeat/rbm_defeat_generic.gd")
const BEFORE_AWAKENING_ONLY := ["musha", "gentleman"]
## 耐久勝利（HARDCORE の勝利条件「指定ターンを生き残る」で勝った時、2026-10-29）の演出。撃破の演出（DEFEAT）は使わない。
## ボスごとの耐久勝利専用の退場モーションは、ここへ「ボスの素材 ID: スクリプト」を足すだけで差し替わる（覚醒後は
## "<id>_awakened"、無ければ覚醒前の id のものを使う）。無いボスは共通の SURVIVAL_GENERIC（ボスは倒れない）。
const SURVIVAL := {}
const SURVIVAL_GENERIC := preload("res://src/bossmaker/visuals/encounter/defeat/rbm_survival_generic.gd")
## 全ボス共通の音（とどめの一撃・ファンファーレ・味方の小さな音）。
const COMMON_SOUNDS := ["enc:final_hit", "enc:fanfare_b", "enc:sparkle", "enc:watch_tick", "enc:sheathe", "enc:hammer_thud", "game:wind_swing"]
## 倒れ方が終わる少し前から、味方の反応とファンファーレを始める
const OVERLAP := 0.25
## 結果パネルを出すフェードの長さ
const RESULT_FADE := 0.22

var boss := "golem"
var boss_name := ""
var turn := 1
var clear_seconds := 0.0
## 耐久勝利（撃破の演出の代わりに survival_script() を使い、文字は「耐久成功！」）。
var survival := false
var stage: Control
var view: Control
var hud: Control
var sfx: Node
## 結果パネルを出す時に呼ぶ（呼び出し元の戦闘画面が、隠していた結果パネルを出す）。
var show_result_fn: Callable

var age := 0.0          # 決着（begin）からの時間
var duration := 4.0
var state := "idle"     # idle / final / playing / result / done
var overlay: CanvasLayer
var camera: RefCounted
var defeat: RefCounted
var allies: RefCounted
var banner: RefCounted
var fx: FX
var fx_back: FX
var boss_body: Node2D
var boss_flat: Node2D
var boss_dissolve: Node2D
var ally_layer: Node2D
var top: Node2D
var timeline_log: Array = []
var _fired := {}
var _final_age := 0.0
var _result_age := 0.0
var _hud_items: Array = []
var _hud_target := 1.0
var _hud_k := 1.0
var _hud_speed := 4.0
## 戦場の動きの速さ（とどめのスロー）。粒もこの速さで動かす。
var motion_speed := 1.0
var _attached := false
var _aura_guard: RefCounted

## ボスの絵（ステージのボスの素材 ID。覚醒した後は *_awakened）→ 倒れ方のスクリプト。無ければ null。
static func defeat_script(asset_id: String) -> Script:
	if DEFEAT.has(asset_id):
		return DEFEAT[asset_id]
	if asset_id.ends_with("_awakened"):
		var base := asset_id.trim_suffix("_awakened")
		if BEFORE_AWAKENING_ONLY.has(base):
			return GENERIC
		if DEFEAT.has(base):
			return DEFEAT[base]
	return null

## 耐久勝利の演出のスクリプト（ボス専用が無ければ共通）。
static func survival_script(asset_id: String) -> Script:
	if SURVIVAL.has(asset_id):
		return SURVIVAL[asset_id]
	var base := asset_id.trim_suffix("_awakened")
	if SURVIVAL.has(base):
		return SURVIVAL[base]
	return SURVIVAL_GENERIC

## このボスの勝利演出があるか。
static func has_victory(asset_id: String) -> bool:
	return defeat_script(asset_id) != null

## 勝利演出で読む素材（事前読み込みの warm_paths() 用）: ボスの12ポーズ・ボス専用のコマ絵・味方の中割りのコマ・音。
static func warm_paths(boss_id: String, party: Array) -> Array[String]:
	var out: Array[String] = []
	var script := defeat_script(boss_id)
	if script == null:
		return out
	var consts: Dictionary = script.get_script_constant_map()
	out.append_array(Array(consts.get("VFX_PATHS", [])))
	out.append_array(Sprites.pose_paths(boss_id))
	out.append_array(IntroPlayer.frame_paths_of(boss_id, consts.get("FRAMES", [])))
	out.append_array(AllyFrames.warm_paths(party))
	out.append_array(Audio.paths_of(COMMON_SOUNDS + Array(consts.get("SOUNDS", []))))
	var unique: Array[String] = []
	for p in out:
		if not p.is_empty() and not unique.has(p):
			unique.append(p)
	return unique

## とどめの命中の瞬間に鳴らす音の鍵。
static func final_blow_keys() -> Array:
	return ["enc:final_hit"]

## 勝利演出で鳴らす音の鍵（共通の音＋倒れ方の SOUNDS。耐久勝利なら耐久勝利の演出の SOUNDS）。
static func victory_keys(asset_id: String, for_survival: bool = false) -> Array:
	var script := survival_script(asset_id) if for_survival else defeat_script(asset_id)
	var keys: Array = COMMON_SOUNDS.duplicate()
	if script != null:
		keys.append_array(Array(script.get_script_constant_map().get("SOUNDS", [])))
	return keys

## 味方の中割りのコマの1枚絵を受け取っておく（勝利の本体を始める前）。
static func hold_ally_sheets(party: Array, allow_load: bool = false) -> void:
	AllyFrames.hold(party, allow_load)

## とどめの命中の瞬間に使う物だけ（決着の前に読み終えておく。とどめの音・ボスの被弾の姿勢）。
static func final_blow_paths(boss_id: String) -> Array[String]:
	var out: Array[String] = Audio.paths_of(["enc:final_hit"])
	var script := defeat_script(boss_id)
	if script != null:
		out.append_array(Array(script.get_script_constant_map().get("VFX_PATHS", [])))
	var poses := Sprites.pose_paths(boss_id)
	if poses.size() > 11:
		out.append(poses[11])
	return out

func setup(st: Control, battle_view: Control, battle_hud: Control, audio: Node) -> void:
	stage = st
	view = battle_view
	hud = battle_hud
	sfx = audio

## とどめの一撃の命中の瞬間に呼ぶ（本番の presenter の entry_impact で、決着した行動）。
func on_final_impact() -> void:
	_attach()
	timeline_log.append([0.0, "final_impact"])
	state = "final"
	_final_age = 0.0
	defeat.final_blow()
	hud_fade(0.0, 7.0)
	set_process(true)

## 決着の演出の本体を始める（本番の presenter の finished の後）。
func begin() -> void:
	_attach()
	timeline_log.append([snappedf(_final_age, 0.001), "begin"])
	set_motion_speed(1.0)
	camera.reset_keep()
	state = "playing"
	age = 0.0
	defeat.begin()
	allies.t0 = defeat.duration() - OVERLAP
	duration = allies.t0 + allies.LENGTH
	set_process(true)

## 戦場の動きの速さを変える（とどめのスロー）。ステージの今の行動の動きにだけ掛ける。
func set_motion_speed(k: float) -> void:
	motion_speed = k
	if is_instance_valid(stage) and stage.has_method("set_motion_speed"):
		stage.call("set_motion_speed", k)

func _attach() -> void:
	if _attached:
		return
	_attached = true
	Sprites.register_stage(stage)
	stage.add_child(self)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var boss_visual: Control = stage.get("_visuals")["boss"]
	var at_index := boss_visual.get_index() + 1
	fx_back = FX.new()
	fx_back.z_index = 1
	boss_body = _layer("VictoryBossBody", 1, 0)
	boss_flat = _layer("VictoryBossFlat", 1, 1)
	boss_dissolve = _layer("VictoryBossDissolve", 1, 2)
	for n in [fx_back, boss_body, boss_flat, boss_dissolve]:
		stage.add_child(n)
		stage.move_child(n, at_index)
		at_index += 1
	ally_layer = _layer("VictoryAllies", 2, -1)
	top = _layer("VictoryTop", 5, -1)
	fx = FX.new()
	fx.z_index = 6
	stage.add_child(ally_layer)
	stage.add_child(top)
	stage.add_child(fx)
	overlay = Overlay.new()
	view.add_child(overlay)
	camera = Camera.new()
	camera.attach(stage)
	banner = Banner.new()
	banner.p = self
	overlay.extra_draw.append(banner.draw)
	defeat = (survival_script(boss) if survival else defeat_script(boss)).new()
	_aura_guard = AuraGuard.new()
	_aura_guard.attach(stage,boss,top)
	defeat.p = self
	defeat.setup()
	allies = Allies.new()
	allies.p = self
	allies.setup()
	top.draw_fn = func(ci: CanvasItem):
		defeat.draw_top(ci)
		allies.draw_top(ci)

func _layer(n: String, z: int, shader_mode: int) -> Node2D:
	var l: Node2D = Layer.new()
	l.name = n
	l.z_index = z
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if shader_mode >= 0:
		var m := ShaderMaterial.new()
		m.shader = SPRITE_SHADER
		m.set_shader_parameter("mode", shader_mode)
		l.material = m
	return l

func shader(l: Node2D, key: String, value: Variant) -> void:
	(l.material as ShaderMaterial).set_shader_parameter(key, value)

func _process(delta: float) -> void:
	if is_instance_valid(sfx):
		sfx.advance(delta)
	camera.advance(delta)
	# 粒は戦場の速さで動かす（とどめのスローの間はゆっくり）
	fx.advance(delta * motion_speed)
	fx_back.advance(delta * motion_speed)
	_hud_step(delta)
	match state:
		"final":
			_final_age += delta
			defeat.final_advance(_final_age, delta)
		"playing":
			age += delta
			defeat.advance(age, delta)
			if age >= allies.t0:
				at(allies.t0, "fanfare", func(): sfx.play("enc:fanfare_b", -1.0))
			allies.advance(age, delta)
			banner.advance(age)
			if age >= duration:
				_show_result()
		"result":
			_result_age += delta
			var k := clampf(_result_age / RESULT_FADE, 0.0, 1.0)
			var dialog := _outcome_dialog()
			if dialog != null:
				dialog.modulate.a = k
			banner.fade_out(k)
			if k >= 1.0:
				_finish()
		"done":
			# 結果パネルを出した後も、倒れ切った戦場（味方の最後の姿勢）はそのまま見せる（粒だけ動かす）
			pass
	for l in [boss_body, boss_flat, boss_dissolve, ally_layer, top]:
		if is_instance_valid(l):
			l.queue_redraw()
	if is_instance_valid(overlay):
		overlay.refresh()

func at(t: float, key: String, fn: Callable) -> void:
	if age >= t and not _fired.has(key):
		_fired[key] = true
		timeline_log.append([snappedf(age, 0.001), key])
		fn.call()

## HUD を薄くする・戻す（結果パネルの暗幕などのダイアログは除く）。
func hud_fade(target: float, speed: float) -> void:
	if not is_instance_valid(hud):
		return
	if _hud_items.is_empty():
		for c in hud.get_children():
			if c is Control and not str(c.name) in ["OutcomeDialog", "RestartDialog", "QuitDialog"]:
				_hud_items.append(c)
	_hud_target = target
	_hud_speed = speed

func _hud_step(dt: float) -> void:
	if _hud_items.is_empty():
		return
	_hud_k = move_toward(_hud_k, _hud_target, dt * _hud_speed)
	for c in _hud_items:
		if is_instance_valid(c):
			(c as Control).modulate.a = _hud_k

func _outcome_dialog() -> Control:
	return hud.get_node_or_null("OutcomeDialog") as Control if is_instance_valid(hud) else null

## 本番の結果パネルを出す（短いフェード）。ファンファーレの余韻は鳴らしたまま。
func _show_result() -> void:
	if state == "result" or state == "done":
		return
	state = "result"
	_result_age = 0.0
	timeline_log.append([snappedf(age, 0.001), "result"])
	if is_instance_valid(overlay):
		overlay.block_input(false)
	if show_result_fn.is_valid():
		show_result_fn.call()
	var dialog := _outcome_dialog()
	if dialog != null:
		dialog.modulate.a = 0.0
	hud_fade(1.0, 4.5)

func _finish() -> void:
	state = "done"
	timeline_log.append([snappedf(age, 0.001), "done"])
	var dialog := _outcome_dialog()
	if dialog != null:
		dialog.modulate.a = 1.0
	finished.emit()

## 元の見た目へ戻す（結果パネルを閉じて次へ進む時・途中でやめる時）。finished は出さない。
func cancel() -> void:
	var was := state
	state = "done"
	timeline_log.append([snappedf(age, 0.001), "cancel:" + was])
	set_process(false)
	set_motion_speed(1.0)
	if is_instance_valid(sfx) and was != "done":
		sfx.stop_all()
	for c in _hud_items:
		if is_instance_valid(c):
			(c as Control).modulate.a = 1.0
	var dialog := _outcome_dialog()
	if dialog != null:
		dialog.modulate.a = 1.0
	if camera != null:
		camera.reset()
	if allies != null:
		allies.restore()
	if is_instance_valid(stage):
		var visuals: Dictionary = stage.get("_visuals")
		if visuals.has("boss") and is_instance_valid(visuals["boss"]):
			(visuals["boss"] as Control).visible = true
	for n in [fx_back, boss_body, boss_flat, boss_dissolve, ally_layer, top, fx, overlay]:
		if is_instance_valid(n):
			n.queue_free()
	queue_free()

func boss_foot() -> Vector2:
	return stage.call("_foot", "boss")
