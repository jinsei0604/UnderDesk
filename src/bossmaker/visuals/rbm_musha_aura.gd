extends Node2D
## 覚醒後の朽ちた機械武者の「常時オーラ」= 存在しているだけで戦場全体の状態が変わる圧
## (黒墨・静圧・光を奪う・色が死ぬ・空間が圧に沈む)。炎ではなく、本体を隠さない。
##
## 「覚醒状態」に従う独立した部品: ステージの外見が覚醒後(musha_awakened)の間は常に
## 表示し、攻撃終了・Buff終了では止めない。戦闘状態・乱数を持たず読まず、ステージ破棄で
## 必ず消える。覚醒演出(rbm_musha_awakening.gd)は出現区間の強さ(power_override)だけを
## 渡す。覚醒の瞬間的な風圧解放(rbm_musha_awakened_vfx.gd::wind_release)とは別物。
##
## 構成(すべて本体=ステージのボス(z=1)より背面、味方(z=2)より背面に描く):
## - 戦場全体: 全面パス1枚(rbm_musha_aura_shaders.gd の post)。松明が力を失い、床・背景の
##   色が死に、全体が少し沈み、画面端に筆で擦ったような墨がにじむ。2〜3秒に一度、空間が
##   ごくわずか(端で約2px)縮んで沈む。ボスはこのパスより前面なので影響を受けず、白い外套と
##   赤い単眼が相対的に浮く。味方はパスより前面なので、同じ補正を味方の見た目にだけ掛ける。
## - 黒墨は足元だけ: ボスの足元に低く地面を這う墨染み+石畳の溝に沿って伸びて消える細い墨筆。
##   味方の足元にも薄く小さな墨染み。体まわりの霞・浮遊する墨粒は無い。
## - 単眼: 数秒に一度だけ少し強く光り、その瞬間だけ戦場が一段沈み・画面端の墨が強まり・
##   足元の墨染みが膨らむ。ごく低頻度の斬痕(黒中心・縁にわずかな暗赤)と、画面端から入る
##   太い墨筆の掠れもある。白い線・水色・円弧・魔法陣は使わない。
## - 演出中(stage.is_playing())は出来事(眼の光・空間圧・斬痕・画面端の墨)を静かに引っ込め、
##   常時の色・光・足元の墨だけを残す。
##
## 時間割は rbm_musha_aura_timeline.gd(純粋関数)、墨の描画は rbm_musha_aura_ink.gd。
const Shaders = preload("res://src/bossmaker/visuals/rbm_musha_aura_shaders.gd")
const Timeline = preload("res://src/bossmaker/visuals/rbm_musha_aura_timeline.gd")
const Ink = preload("res://src/bossmaker/visuals/rbm_musha_aura_ink.gd")
const AWAKENED_ASSET := "musha_awakened"
## 覚醒後の抜刀待機の単眼(足元から)。フレーム画像上の(-46,-473)を表示倍率0.335で換算。
const EYE_OFFSET := Vector2(-15.4, -158.5)
## 空間圧・暗化の中心(ボスの胸のあたり)。
const CHEST_OFFSET := Vector2(0, -95)
const BOSS_BLOT_SIZE := Vector2(500, 100)
const BOSS_BLOT_RADIUS := Vector2(158, 24)
const ALLY_BLOT_SIZE := Vector2(180, 60)
const ALLY_BLOT_RADIUS := Vector2(56, 10)
## 背景画像(battle_courtyard_*)上の松明の炎の位置(画像に対する割合)。標準背景(中庭)の画像だけのもので、
## ボスの専用背景(rbm_battle_backgrounds.gd)では松明を探さない(パスに day/night を含んでいても当てはめない)。
const TORCH_UVS := {
	"night": [Vector2(0.366, 0.404), Vector2(0.633, 0.404)],
	"day": [Vector2(0.338, 0.404), Vector2(0.703, 0.408)],
}
## 松明の光が弱まる半径(背景画像の表示倍率1あたり)。
const TORCH_RADIUS := 96.7
const ALLY_SLOTS := 4

## 覚醒演出の途中(まだ外見が覚醒後へ切り替わる前)に、演出側が強さを直接指定するための値。
## 負なら「覚醒状態に従って常時(power=1)」。
var power_override := -1.0
var age := 0.0
## 戦場全体への影響の広がり(0〜1)。演出中の出現に合わせて数秒かけて広がる。
var amount := 0.0
## 眼が光った瞬間の戦場・墨の反応(0〜1)、眼の光(0〜1)、空間圧(0〜1)。いずれも演出中は0へ引っ込む。
var jolt := 0.0
var eye := 0.0
var compression := 0.0
var quiet_gate := 1.0

var _stage: Control
var _raw := 0.0
var _ramping := false
var _event_age := 0.0   # 出来事(眼・空間圧・斬痕・画面端)の時計。演出中は止まる
var _aura_age := 0.0    # オーラが現れてからの時計(足元の墨筆の予定に使う)
var _post: ColorRect
var _boss_blot: ColorRect
var _ally_blots: Array = []
var _ink: Node2D
var _eye: Node2D
var _ally_mat: ShaderMaterial
var _allies_on := false
var _context_key := ""
var _paths: Array = []
var _torches: Array = [Vector2(-1000, -1000), Vector2(-1000, -1000)]
var _torch_radius := TORCH_RADIUS * 0.77
var _bg_image: Image
var _bg_image_id := 0

func _init() -> void:
	visible = false
	_post = _make_rect(Shaders.material("post"), 1)
	_boss_blot = _make_rect(Shaders.material("blot"), 1)
	var boss_mat := _boss_blot.material as ShaderMaterial
	boss_mat.set_shader_parameter("rad", BOSS_BLOT_RADIUS)
	boss_mat.set_shader_parameter("fleck_k", 0.7)
	for i in range(ALLY_SLOTS):
		var rect := _make_rect(Shaders.material("blot"), 1)
		var mat := rect.material as ShaderMaterial
		mat.set_shader_parameter("rad", ALLY_BLOT_RADIUS)
		mat.set_shader_parameter("phase", 1.3 + i * 1.7)
		_ally_blots.append(rect)
	_ink = Node2D.new()
	_ink.z_index = 1
	_ink.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_ink)
	_ink.draw.connect(_draw_ink)
	_eye = Node2D.new()
	_eye.z_index = 3
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_eye.material = additive
	add_child(_eye)
	_eye.draw.connect(_draw_eye)

func _make_rect(material_value: ShaderMaterial, z: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = z
	rect.material = material_value
	rect.visible = false
	add_child(rect)
	return rect

func configure(stage: Control) -> void:
	_stage = stage
	refresh()

## 覚醒状態(外見が覚醒後か)に合わせて表示/非表示を更新する。
func refresh() -> void:
	var awakened := is_instance_valid(_stage) and str(_stage._asset_ids.get("boss", "")) == AWAKENED_ASSET
	if power_override >= 0.0:
		_ramping = true
	visible = awakened or power_override >= 0.0
	if not visible:
		_reset()
	elif awakened and power_override < 0.0 and not _ramping:
		# 覚醒済みのスナップショットの復元(覚醒演出を再生しない)は、広がりを待たずに完成形から始める。
		_raw = 1.0
		amount = Timeline.amount_from_raw(_raw)
	_redraw()

func power() -> float:
	return power_override if power_override >= 0.0 else 1.0

func _reset() -> void:
	_raw = 0.0
	amount = 0.0
	_ramping = false
	_event_age = 0.0
	_aura_age = 0.0
	jolt = 0.0
	eye = 0.0
	compression = 0.0
	_apply_allies(false)

func _redraw() -> void:
	_ink.queue_redraw()
	_eye.queue_redraw()

func _process(delta: float) -> void:
	age += delta
	if not visible or not is_instance_valid(_stage):
		if _allies_on:
			_apply_allies(false)
		return
	_advance(delta)
	_update_scene()
	_redraw()

## 状態を進める(表示専用。戦闘の状態・乱数には触れない)。
func _advance(delta: float) -> void:
	var p := clampf(power(), 0.0, 1.0)
	if _raw < p:
		_raw = minf(p, _raw + delta / Timeline.RAMP_SECONDS)
	elif _raw > p:
		_raw = p
	if _raw >= 1.0:
		_ramping = false
	amount = Timeline.amount_from_raw(_raw)
	var playing: bool = _stage.has_method("is_playing") and _stage.is_playing()
	if _raw > 0.0:
		_aura_age += delta
		if not playing:
			_event_age += delta
	quiet_gate = move_toward(quiet_gate, 0.0 if playing else 1.0, delta * 6.0)
	jolt = Timeline.jolt(_event_age) * quiet_gate
	eye = Timeline.eye_env(_event_age) * quiet_gate
	compression = Timeline.compress(_event_age) * quiet_gate

func _update_scene() -> void:
	var size := _stage.size
	var foot := _home_foot("boss")
	_ensure_context(foot, size)
	var on := amount > 0.0
	_post.visible = on
	_post.position = Vector2.ZERO
	_post.size = size
	var post := _post.material as ShaderMaterial
	post.set_shader_parameter("rect_px", size)
	post.set_shader_parameter("center", foot + CHEST_OFFSET)
	post.set_shader_parameter("torch_a", _torches[0])
	post.set_shader_parameter("torch_b", _torches[1])
	post.set_shader_parameter("torch_r", _torch_radius)
	post.set_shader_parameter("time", age)
	post.set_shader_parameter("amount", amount)
	post.set_shader_parameter("jolt", jolt)
	post.set_shader_parameter("comp", compression)
	# 足元の墨染み(ボス): 演出中の出現(power)に同期して現れる。
	_place_blot(_boss_blot, foot, BOSS_BLOT_SIZE, clampf(power(), 0.0, 1.0))
	# 味方の足元の墨染み: 戦場全体の影響とともに少しだけ濃くなる。
	var keys: Array = _stage._party_keys
	for i in range(ALLY_SLOTS):
		var rect: ColorRect = _ally_blots[i]
		if i < keys.size() and _stage._visuals.has(keys[i]) and on:
			_place_blot(rect, _home_foot(str(keys[i])), ALLY_BLOT_SIZE, 0.90 * amount)
		else:
			rect.visible = false
	_apply_allies(on)

func _place_blot(rect: ColorRect, foot: Vector2, blot_size: Vector2, strength: float) -> void:
	rect.visible = strength > 0.0
	if not rect.visible:
		return
	var corner := foot - Vector2(blot_size.x * 0.5, blot_size.y * 0.56)
	rect.position = corner
	rect.size = blot_size
	var mat := rect.material as ShaderMaterial
	mat.set_shader_parameter("origin", corner)
	mat.set_shader_parameter("c", foot + Vector2(0, -3))
	mat.set_shader_parameter("time", age)
	mat.set_shader_parameter("jolt", jolt)
	mat.set_shader_parameter("amount", strength)

## ボスの足元(静止位置)。攻撃で本体が動いても、墨染みは地面に残る。
func _home_foot(key: String) -> Vector2:
	var visual: Control = _stage._visuals.get(key)
	if not is_instance_valid(visual):
		return _stage.size * 0.5
	var home: Vector2 = _stage._homes.get(key, visual.position)
	var foot := Vector2.ZERO
	if visual.has_method("foot_position"):
		foot = visual.call("foot_position")
	return (home + foot).round()

## 味方は全面パスより前面(z=2)なので、同じ低彩度・低輝度化を味方の見た目にだけ掛ける。
func _apply_allies(on: bool) -> void:
	_allies_on = on
	if not is_instance_valid(_stage):
		return
	if on:
		if _ally_mat == null:
			_ally_mat = Shaders.material("ally")
		_ally_mat.set_shader_parameter("amount", amount)
		_ally_mat.set_shader_parameter("jolt", jolt)
	for key in _stage._visuals:
		if key == "boss":
			continue
		var visual: Control = _stage._visuals[key]
		if not is_instance_valid(visual):
			continue
		if on:
			if visual.material != _ally_mat:
				visual.material = _ally_mat
				_share_with_children(visual, true)
		elif _ally_mat != null and visual.material == _ally_mat:
			visual.material = null
			_share_with_children(visual, false)

func _share_with_children(visual: Control, on: bool) -> void:
	for child in visual.get_children():
		if child is CanvasItem:
			(child as CanvasItem).use_parent_material = on

func _exit_tree() -> void:
	if _allies_on:
		_apply_allies(false)

# ---------------------------------------------------------------------------
# 背景(松明の位置と石畳の溝)。ステージ直下のTextureRectが背景の時だけ使う。無ければ松明・溝は省く。
# ---------------------------------------------------------------------------

func _find_background() -> TextureRect:
	for child in _stage.get_children():
		if child is TextureRect and (child as TextureRect).texture != null:
			return child
	return null

func _ensure_context(foot: Vector2, size: Vector2) -> void:
	var bg := _find_background()
	var texture_id := bg.texture.get_instance_id() if bg != null else 0
	var key := "%s|%s|%s|%s" % [foot, size, texture_id, bg.size if bg != null else Vector2.ZERO]
	if key == _context_key:
		return
	_context_key = key
	_paths = []
	_torches = [Vector2(-1000, -1000), Vector2(-1000, -1000)]
	if bg == null:
		return
	if texture_id != _bg_image_id:
		_bg_image_id = texture_id
		_bg_image = bg.texture.get_image()
		if _bg_image != null and not _bg_image.is_empty() and _bg_image.is_compressed():
			_bg_image.decompress()
	if _bg_image == null or _bg_image.is_empty():
		return
	var tex_size := Vector2(_bg_image.get_size())
	var scale_v := Vector2(bg.size.x / tex_size.x, bg.size.y / tex_size.y)
	if bg.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		var s := maxf(scale_v.x, scale_v.y)
		scale_v = Vector2(s, s)
	var offset := bg.position + (bg.size - tex_size * scale_v) * 0.5
	var image := _bg_image
	var luminance := func(p: Vector2) -> float:
		var u := clampi(int((p.x - offset.x) / scale_v.x), 1, image.get_width() - 2)
		var v := clampi(int((p.y - offset.y) / scale_v.y), 1, image.get_height() - 2)
		var sum := 0.0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := image.get_pixel(u + dx, v + dy)
				sum += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		return sum / 9.0
	_paths = Ink.groove_paths(luminance, foot, size.y - 12.0)
	var path := bg.texture.resource_path
	for theme_name in TORCH_UVS:
		if path.contains("battle_courtyard_" + theme_name):
			for i in range(2):
				var uv: Vector2 = TORCH_UVS[theme_name][i]
				_torches[i] = offset + uv * tex_size * scale_v
			_torch_radius = TORCH_RADIUS * scale_v.x
			break

# ---------------------------------------------------------------------------
# 描画(本体の背面): 溝に沿う墨筆 / 斬痕 / 画面端から入る墨筆
# ---------------------------------------------------------------------------

func _draw_ink() -> void:
	if not visible or not is_instance_valid(_stage) or amount <= 0.0:
		return
	var foot := _home_foot("boss")
	var strength := clampf(power(), 0.0, 1.0)
	for info in Timeline.active_traces(_aura_age):
		var index: int = info.path
		if index < _paths.size():
			Ink.trace(_ink, _paths[index], info, strength, jolt)
	var slash := Timeline.slash(_event_age)
	if int(slash.index) >= 0:
		var shape := Timeline.slash_shape(int(slash.index))
		Ink.slash(_ink, foot + Vector2(shape.offset), shape, float(slash.local), quiet_gate)
	var edge := Timeline.edge(_event_age)
	if int(edge.index) >= 0 and quiet_gate > 0.01:
		var shape := Timeline.edge_shape(int(edge.index), _stage.size)
		var u: float = edge.u
		var head := 1.0 - pow(1.0 - clampf(u / 0.40, 0.0, 1.0), 3.0)
		var tail := 0.9 * smoothstep(0.50, 1.0, u)
		var alpha := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.80, 1.0, u)) * (0.70 + 0.30 * jolt) * quiet_gate
		Ink.brush(_ink, shape.base, shape.theta, shape.bend, shape.length, shape.width, shape.seed, head, tail, alpha)

# 単眼: 数秒に一度だけ少し強く赤く光る(加算)。常時は元絵の細い赤線のみ。
func _draw_eye() -> void:
	if not visible or not is_instance_valid(_stage) or eye < 0.01:
		return
	var boss: Control = _stage._visuals.get("boss")
	if not is_instance_valid(boss) or not boss.visible:
		return
	var at := (_home_foot("boss") + EYE_OFFSET).round()
	_eye.draw_rect(Rect2(at + Vector2(-13, -4), Vector2(26, 8)), Color(0.55, 0.03, 0.03, 0.10 * eye))
	_eye.draw_rect(Rect2(at + Vector2(-9, -2), Vector2(18, 5)), Color(0.75, 0.05, 0.04, 0.20 * eye))
	_eye.draw_rect(Rect2(at + Vector2(-6, -1), Vector2(13, 2)), Color(1.0, 0.20, 0.14, 0.75 * eye))
