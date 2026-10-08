extends "res://src/bossmaker/visuals/rbm_musha_awakened_presentation.gd"
## 覚醒後の朽ちた機械武者の単体「境」/全体「界」(承認済み 2026-09-27)。行動ごとの rbm_musha_awakened_single / all.gd が継承する。
## 本体は「コマ送り」(原画のコマに、原画から作った構え・溜め・納め直しのコマを挟む)。絵を毎フレーム変形・揺らすことはしない。
## 前面の効果は元の赤い衝撃波・白い断裂を外し、すべて墨の層(rbm_musha_ink_director.gd)が墨で描く(技名の下地だけ残す)。
## 表示専用(戦闘の状態・乱数・行動順には触れない)。ダメージの通知(_strike)は元の着弾の時刻へ一度だけ。
##
## 単体: 刀を掲げてから振り下ろすまでに溜めを入れる(溜めの間に刀から立ち昇る墨が大きく激しくなる)。
##   そのため元の時刻(音・技名・画面揺れ・着弾=ダメージ通知)を SD 秒うしろへずらして再生する
##   (元の音は最初の 0.9 秒が無音なので、ずらしても振り下ろし・着弾の音はそのまま合う)。
## 全体: 「血振り(風切り音) → 納刀(鍔鳴り) → 居合の構え・溜め(オーラをすべて刀へ吸い込む) → 鯉口を切り、抜く瞬間
##   → 画面全体が真っ白になり見えない斬撃が8回走る → 白が引くと刀はもう鞘へ戻りかけていて、納めきって鍔鳴り
##   → 静かな間 → 8回の斬撃が同じ速さで味方の体に現れ、墨の大爆発(着弾)」。
##   元の時刻(技名・画面揺れ・着弾=ダメージ通知)は、2.45秒で ALL_HOLD 秒だけ止めて、着弾を遅れて入る斬撃(8.92秒)に合わせる。
##   元の音は区切って使い(_update_aoe_sound)、白い画面の斬る音・遅れて入る斬撃の音・納めきった鍔鳴りを足す。
##   足す音もステージの音と同じく、消音中(ホーム画面のモニター等)やステージが見えていない間は鳴らさない。
const Rig = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const PlaqueVFX = preload("res://src/bossmaker/visuals/rbm_musha_name_plaque_vfx.gd")
const AudioCatalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")
const SD := 2.4
const ALL_SKIP_AT := 2.45
const ALL_HOLD := 4.07

## 本体のコマ割り [開始時刻(演出の時刻), コマ]
const SINGLE_KEYS := [
	[0.00, "a3"], [0.12, "s1"], [0.20, "s0"], [2.95, "s0c"],
	[3.32, "s1"], [3.354, "s2"], [3.387, "s3i"], [3.66, "s3"], [4.55, "s3i"], [4.72, "s3"], [5.95, "a3"],
]
## 全体: 下げた刀を鯉口へ運ぶ(前へ振り下ろさない) → 鞘と一直線のまま納める → 鍔鳴り
## → 居合の構え(参考画像): 上体はわずか(5度)に前へ、膝を曲げて腰を落とし、刀を腰で寝かせて、袖口から出た右手で柄を握り、左手は鯉口を握る(kc1 → kc)
## → 溜め: 常時の墨のオーラをすべて刀(鯉口)へ吸い込んで無くし(約1.65秒)、オーラの無いまま構えてさらに溜める(約0.8秒)
## → 鯉口を切る(kcd) → 右手が柄を前へ引き、刀身が鯉口から出る = 抜く瞬間(a1c)
## → (画面全体が真っ白: 見えない速さで抜いて斬る。武者の絵は白の下で納め直しのコマへ替わる)
## → 白が引くと、居合の構えのまま刀身の最後の部分を約1.1秒かけてゆっくり鞘へ納めていく(kcn1 → kcs26 … kcs3) → 納めきって鍔鳴り(kc)
## → 遅れて味方に斬撃が入る間は構えたまま → 立ち上がり(kc1 → a0f)、原画の抜刀のコマ(a1 → a2)で刀を抜いて抜刀待機(a3)へ
const ALL_KEYS := [
	[0.00, "a3"], [1.34, "an1"], [1.62, "an2"], [1.88, "an3"], [2.10, "a0f"], [2.30, "kc1"], [2.52, "kc"],
	[4.75, "kcd"], [4.81, "a1c"], [4.90, "kcn1"], [5.96, "kcs26"], [6.12, "kcs22"], [6.26, "kcs18"], [6.39, "kcs14"],
	[6.51, "kcn2"], [6.63, "kcs7"], [6.74, "kcs3"], [6.85, "kc"],
	[10.09, "kc1"], [10.22, "a0f"], [10.36, "a1"], [10.50, "a2"], [10.64, "a3"],
]
var director
## ダメージの通知(_strike)を出す演出の時刻と、完成トラックを鳴らし始める演出の時刻(play()で決まる)。
var strike_at := 0.0
var track_at := 0.0
var rig_body: Node2D
var body_state: Dictionary = {}
var _flashed := {}
var _delay := 0.0
var _sound_started := true
var _aoe_player: AudioStreamPlayer
var _skipped := false

class RigBody extends Node2D:
	var owner_p
	## 元の本体と同じ読み取り口(足元・状態)。表示の検査用で、描き方には関係しない。
	var _foot: Vector2:
		get:
			return Vector2(owner_p.body_state.get("foot", Vector2.ZERO)) if owner_p != null else Vector2.ZERO
	var _state: Dictionary:
		get:
			return owner_p.body_state if owner_p != null else {}
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		if owner_p == null or owner_p.body_state.is_empty():
			return
		for g in owner_p.ghosts:
			Rig.draw(self, g.state, Color(0.85, 0.85, 0.95, float(g.a)))
		Rig.draw(self, owner_p.body_state)

## 突っ込みの残像: このコマの間だけ、直前のコマを半透明で薄く残す(0.2秒で消える)。
const GHOST_FRAMES := []
const GHOST_LIFE := 0.2
var ghosts: Array = []
var _trail: Array = []

func play(stage: Control) -> Tween:
	var tw := super.play(stage)
	if director == null and stage.has_method("musha_ink_director"):
		director = stage.musha_ink_director()
	rig_body = RigBody.new()
	rig_body.owner_p = self
	remove_child(_body)
	_body.queue_free()
	_body = rig_body
	add_child(rig_body)
	move_child(rig_body, 0)
	# 元の前面VFXを「技名の下地だけ」の版へ差し替える(位置・対象・色は元の値をそのまま渡す)
	var old = _vfx
	var nv = PlaqueVFX.new()
	nv.z_index = old.z_index
	nv.kind = old.kind
	nv.tint = old.tint
	nv.home = old.home
	nv.hit_at = old.hit_at
	nv.center = old.center
	nv.screen = old.screen
	nv.brush_at = old.brush_at
	var idx: int = old.get_index()
	remove_child(old)
	old.queue_free()
	add_child(nv)
	move_child(nv, idx)
	_vfx = nv
	if kind == "all":
		for pl in stage._sound._players:
			if pl.playing and pl.stream != null and str(pl.stream.resource_path).ends_with("musha_awakened_aoe.wav"):
				_aoe_player = pl
	if true:
		# 単体: 元の時刻・音を SD 秒うしろへ(溜めを入れる) / 全体: 2.45秒で ALL_HOLD 秒止める。進行の終わり方(反撃・終了)は元と同じ。
		tw.kill()
		if kind == "single":
			_delay = SD
			_sound_started = false
			duration = Motion.duration(kind) + SD
			strike_at = impact_time + SD
			track_at = SD
		else:
			duration = Motion.duration(kind) + ALL_HOLD
			strike_at = impact_time + ALL_HOLD
			track_at = 0.0
		tw = create_tween()
		tw.tween_method(_advance, 0.0, duration, duration)
		if stage._samurai_finish:
			tw.tween_callback(_restore_transform)
			var counter_duration: float = stage.SAMURAI_WIND_START_DELAY + stage.SamuraiWind.AFTERMATH_START + stage.SamuraiWind.AFTERMATH_DURATION + .05
			tw.tween_method(stage._samurai_finish_progress, 0.0, counter_duration, counter_duration)
		elif not stage._counters.is_empty():
			tw.tween_callback(_restore_transform)
			tw.tween_method(stage._counter_progress, 0.0, 1.0, .20)
			tw.tween_callback(stage._counter_impact)
		tw.tween_callback(stage._finish)
	_advance(0.0)
	return tw

## 単体は溜めを入れてから(SD 秒後に)完成トラックを1回だけ鳴らす。全体は開始時に鳴らし、区切って使う。
func _plays_track_on_start() -> bool:
	return kind != "single"

static func alt(t: float) -> float:
	return 1.0 if int(floor(t * 30.0 + 0.5)) % 2 == 0 else -1.0

## 演出の時刻 T → 元の時刻(音・技名・画面揺れ・着弾)。
func _prod_time(T: float) -> float:
	if kind == "single":
		return maxf(0.0, T - _delay)
	if T < ALL_SKIP_AT:
		return T
	return ALL_SKIP_AT if T < ALL_SKIP_AT + ALL_HOLD else T - ALL_HOLD

## 墨の効果に合わせた小さな揺れ(単体: 斬線への着弾 / 全体: 抜き打ち)。
func _extra_shake(T: float) -> Vector2:
	if kind == "all":
		# 遅れて入る斬撃の一回ごとに小さく揺れる
		var s := Vector2.ZERO
		for dt in FLURRY_DT:
			var a := T - (FLURRY_AT + float(dt))
			if a >= 0.0 and a < 0.08:
				s += Vector2(sin(T * 97.0), cos(T * 83.0) * 0.6) * 3.0 * (1.0 - a / 0.08)
		return s.round()
	var t0 := 3.70
	var amp := 5.0
	var k := 1.0 - smoothstep(t0, t0 + 0.18, T)
	if T < t0 or k <= 0.0:
		return Vector2.ZERO
	return (Vector2(sin(T * 97.0), cos(T * 83.0) * 0.6) * amp * k).round()

## 再生の最初と途中で load() する素材(rbm_presentation_warmup.gd が、ボスが決まった時点で裏で読み込んで持つ)。
## 元の本体の画像(super.play() で読んでから差し替える)・筆文字・コマ・完成トラックと、全体で足す音。
static func warm_paths(_asset_id: String, kind: String) -> Array[String]:
	var out: Array[String] = [Body.ROOT + "awakened.png", Body.ROOT + "swing.png", Brush.ROOT + "brush.png"]
	for k in (SINGLE_KEYS if kind == "single" else ALL_KEYS):
		out.append(Rig.texture_path(str(k[1])))
	if kind == "single":
		out.append(str(AudioCatalog.FILES["musha_awakened_single"]))
	else:
		for key in ["musha_awakened_aoe", "samurai_iai_draw", "neutral_sword_swing", "musha_single", "musha_aoe"]:
			out.append(str(AudioCatalog.FILES[key]))
	return out

func _frame_at(T: float) -> Dictionary:
	var keys := SINGLE_KEYS if kind == "single" else ALL_KEYS
	var cur: Array = keys[0]
	for k in keys:
		if T >= float(k[0]):
			cur = k
	return Rig.state(str(cur[1]), _home)

func _advance(T: float) -> void:
	if rig_body == null:
		super._advance(T)
		return
	if not active or not is_instance_valid(_stage):
		return
	age = T
	var t := _prod_time(T)   # 元の時刻(音・技名・画面揺れ・着弾)
	if kind == "all":
		_update_aoe_sound(T)
	if not _sound_started and T >= _delay:
		_sound_started = true
		if is_instance_valid(_stage._sound):
			var track := "musha_awakened_single" if kind == "single" else "musha_awakened_aoe"
			_stage._sound.play_sound(track, GlyphMotion.track_gain(track))
	var shake := Motion.shake_offset(t, Motion.shake_force(kind, t) if T >= _delay else 0.0).round() + _extra_shake(T)
	body_state = _frame_at(T)
	_update_ghosts(T)
	rig_body.position = shake
	rig_body.queue_redraw()
	_vfx.position = shake
	_vfx.advance(t if T >= _delay else -1.0)
	var anchor := Vector2(_stage.size.x * BRUSH_ANCHOR_X_RATIO, BRUSH_ANCHOR_Y)
	_brush.position = shake
	_brush.show_brush(GlyphMotion.glyph_index(_attribute), kind == "all", Motion.brush_age(kind, t) if T >= _delay else -1.0, anchor)
	_layout_party_T(T, t, shake)
	if is_instance_valid(director):
		var shown := body_state.duplicate()
		shown.foot = (body_state.foot as Vector2) + shake
		director.set_body(shown)
		var fs: Array = []
		for key in _target_keys:
			fs.append(_stage._foot(key))
		var al: Array = []
		for key in _stage._visuals:
			if key != "boss":
				al.append(_stage._foot(key))
		director.advance_attack(kind, T, shake, {"hit": _vfx.hit_at, "center": _vfx.center, "feet": fs, "allies": al})
	if T >= _delay and t >= impact_time and not _hit:
		_hit = true
		_stage._strike()

func _update_ghosts(T: float) -> void:
	ghosts = []
	if kind != "all":
		return
	if _trail.is_empty() or str(_trail[_trail.size() - 1].fr) != str(body_state.fr):
		_trail.append({"fr": str(body_state.fr), "state": body_state.duplicate(), "t": T})
	for i in range(_trail.size() - 1):
		var e: Dictionary = _trail[i]
		var nxt: Dictionary = _trail[i + 1]
		if not GHOST_FRAMES.has(str(nxt.fr)) and not GHOST_FRAMES.has(str(e.fr)):
			continue
		var age := T - float(nxt.t)
		if age < 0.0 or age > GHOST_LIFE:
			continue
		ghosts.append({"state": e.state, "a": 0.42 * (1.0 - age / GHOST_LIFE)})

## 全体の音: 元の音(musha_awakened_aoe.wav)を区切って使う。[演出の時刻, 元の音の位置(負なら止める)]
##   0〜2.45秒は元どおり(血振りの風切り音 1.35秒・納刀の鍔鳴り 2.1秒) → 無音
##   → 白い閃光に抜刀の風切り音(元の 4.45〜) → 止める → 納めきった瞬間に鋭い鍔鳴り(覚醒前の全体の音 musha_aoe.wav の 5.37〜: 覚醒前の納刀の音)
##   → 着弾に斬撃音(元の 4.75〜: 4.8秒の大きな音が着弾 8.92 に合う)
const AOE_SOUND := [[2.45, -1.0], [4.86, 4.45], [5.10, -1.0], [8.87, 4.75]]
var _snd_i := 0

const NOTO_CLICK_AT := 6.85
const NOTO_CLICK_FROM := 5.37
var _noto_player: AudioStreamPlayer
var _noto_done := false

## 白い画面の中の見えない斬撃の音(rbm_musha_ink_director.gd の FLASH_CUTS と同じ時刻): [演出の時刻, 音の高さ]
## 抜刀の鋭い音(samurai_iai_draw)を斬るたびに、1回おきに刀の風切り音(neutral_sword_swing)を重ねる。
const FLASH_CUT_SOUNDS := [[4.90, 1.0], [5.01, 1.12], [5.12, 0.94], [5.22, 1.2], [5.32, 1.05], [5.41, 1.25], [5.49, 0.9], [5.57, 1.15]]
## 遅れて入る見えない斬撃(rbm_musha_ink_director.gd の _draw_sweep と同じ時刻): 白い画面の中の斬撃と同じ間隔で、味方の体に斬撃が現れる
const FLURRY_AT := 8.05
const FLURRY_DT := [0.04, 0.15, 0.26, 0.36, 0.46, 0.55, 0.63, 0.71]
const FLURRY_STAGGER := 0.015
var _flurry_i := 0
var _cut_i := 0

## 足す音を鳴らしてよいか(ステージの音と同じ条件: 消音中・ステージが見えていない間は鳴らさない)。
func _audio_ok() -> bool:
	return is_instance_valid(_stage) and _stage.is_visible_in_tree() and is_instance_valid(_stage._sound) and not bool(_stage._sound.muted)

func _one_shot(path: String, pitch: float, db: float) -> void:
	if not _audio_ok():
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = load(path)
	pl.pitch_scale = pitch
	pl.volume_db = db
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)

## 音の一部分だけを鳴らす(from 秒から len 秒。終わりの 0.06 秒で小さくして止める)。
var _slices: Array = []

func _slice_shot(path: String, from: float, len: float, pitch: float, db: float) -> void:
	if not _audio_ok():
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = load(path)
	pl.pitch_scale = pitch
	pl.volume_db = db
	add_child(pl)
	pl.play(from)
	_slices.append([pl, from + len, db])

func _update_aoe_sound(T: float) -> void:
	while _cut_i < FLASH_CUT_SOUNDS.size() and T >= float(FLASH_CUT_SOUNDS[_cut_i][0]):
		var pitch: float = FLASH_CUT_SOUNDS[_cut_i][1]
		_one_shot("res://assets_bossmaker/audio/samurai_iai_draw.wav", pitch, 0.0)
		if _cut_i % 2 == 0:
			_one_shot("res://assets_bossmaker/audio/neutral_sword_swing.wav", pitch * 0.85, -3.0)
		_cut_i += 1
	# 遅れて入る斬撃の音: 白い画面の抜刀音とは別の、斬った瞬間の重い斬撃音(覚醒前の単体攻撃の音の 2.745秒〜を約0.2秒ずつ)
	while _flurry_i < FLURRY_DT.size() and T >= FLURRY_AT + float(FLURRY_DT[_flurry_i]):
		var fp: float = [1.0, 1.08, 0.94, 1.12, 0.98, 1.16, 0.92, 1.05][_flurry_i]
		_slice_shot("res://assets_bossmaker/audio/musha_single.wav", 2.745, 0.2, fp, 0.0)
		_flurry_i += 1
	for i in range(_slices.size() - 1, -1, -1):
		var sl: Array = _slices[i]
		var pl: AudioStreamPlayer = sl[0]
		if not is_instance_valid(pl):
			_slices.remove_at(i)
			continue
		var left: float = float(sl[1]) - pl.get_playback_position()
		if left <= 0.0:
			pl.stop()
			pl.queue_free()
			_slices.remove_at(i)
		elif left < 0.06:
			pl.volume_db = float(sl[2]) - 30.0 * (1.0 - left / 0.06)
	if not _noto_done and T >= NOTO_CLICK_AT and _audio_ok():
		_noto_done = true
		_noto_player = AudioStreamPlayer.new()
		_noto_player.stream = load("res://assets_bossmaker/audio/musha_aoe.wav")
		_noto_player.volume_db = 3.0
		add_child(_noto_player)
		_noto_player.play(NOTO_CLICK_FROM)
	if is_instance_valid(_noto_player) and _noto_player.playing and _noto_player.get_playback_position() > NOTO_CLICK_FROM + 0.14:
		_noto_player.stop()
	if not is_instance_valid(_aoe_player):
		return
	while _snd_i < AOE_SOUND.size() and T >= float(AOE_SOUND[_snd_i][0]):
		var pos: float = AOE_SOUND[_snd_i][1]
		if pos < 0.0:
			_aoe_player.stop()
		else:
			_aoe_player.play(pos)
		_snd_i += 1

func stop() -> void:
	if is_instance_valid(director):
		director.end_attack()
	super.stop()

## 味方: 着弾の瞬間の震え(ヒットストップ)と押し込まれる反動。元の被弾ポーズ・画面揺れはそのまま(元の時刻 t で判定)。
func _layout_party_T(T: float, t: float, shake: Vector2) -> void:
	var hits: Array
	if kind == "single":
		hits = [[3.70, 0.08, Vector2(-1, 0), 6.0], [4.55, 0.10, Vector2(-1, 0), 12.0]]
	else:
		# 遅れて入る斬撃の一回ごとに小さくのけぞり(武者に近い人から順に)、着弾で大きく押し込まれる
		hits = []
		for dt in FLURRY_DT:
			hits.append([FLURRY_AT + float(dt), 0.03, Vector2(-1, 0), 4.0, true])
		hits.append([8.92, 0.12, Vector2(-1, 0.2), 18.0, false])
	# 全体: 斬撃は武者に近い対象から順に入る(墨の層と同じ順・間隔)
	var order: Array = _target_keys.duplicate()
	order.sort_custom(func(p, q): return _stage._foot(p).x > _stage._foot(q).x)
	for key in _stage._visuals:
		if key == "boss":
			continue
		var at: Vector2 = Vector2(_stage._homes[key])
		if _stage._guards.has(key):
			var progress := smoothstep(0.0, .5, T) * (1.0 - smoothstep(duration - .50, duration, T))
			at += Vector2(_stage._guard_offsets[key]) * progress
			_stage._pose(key, 10)
		elif _target_keys.has(key):
			var flinch := false
			if kind == "all":
				var rk := order.find(key)
				for dt in FLURRY_DT:
					var a2 := T - (FLURRY_AT + float(dt) + FLURRY_STAGGER * float(rk))
					if a2 >= 0.0 and a2 < 0.07:
						flinch = true
			var reacting := (T >= _delay and Motion.target_reacting(kind, t)) or flinch
			if reacting != bool(_reacting.get(key, false)):
				_reacting[key] = reacting
				_stage._pose(key, _reaction_pose(key, reacting))
			for h in hits:
				var h0: float = float(h[0])
				if kind == "all" and h.size() > 4 and bool(h[4]):
					h0 += FLURRY_STAGGER * float(order.find(key))
				var a: float = T - h0
				if a < 0.0:
					continue
				var id := "%s_%.2f" % [key, h0]
				if not _flashed.has(id) and a < 0.05:
					_flashed[id] = true
					var vis = _stage._visuals[key]
					if vis.has_method("impact_flash"):
						vis.impact_flash()
				var hold: float = h[1]
				if a < hold:
					at += Vector2(2.0 * alt(T), 0)
				else:
					var b := a - hold
					at += (h[2] as Vector2) * float(h[3]) * (1.0 - pow(1.0 - clampf(b / 0.10, 0.0, 1.0), 2.0)) * (1.0 - smoothstep(0.18, 0.75, b))
		_stage._visuals[key].position = (at + shake).round()
