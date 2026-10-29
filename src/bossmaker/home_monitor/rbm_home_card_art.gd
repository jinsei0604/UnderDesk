class_name RBMHomeCardArt
extends Control

## ホーム画面の「挑戦」「ボス作成」カードの見た目（2026-10-28、ユーザー承認の案。prototypes/menu_boss_select_designs_2026-10-28）。
## RBMHomeMonitorPanel（押す・BOOT・全画面へ広がる・効果音）の上に重ねる絵だけを持つ。クリックはパネルが受ける（ここは全部 IGNORE）。
## 挑戦: 夜の中庭・味方4人・機械武者。ホバーで勇者と侍が踏み込み、0.9 秒ごとの斬撃・閃き・火の粉。
## ボス作成: 設計台の上の竜のホログラム（左右に別のボスの小さなカード）。ホバーで色が付いて実体化し、きらめく。
## ホバーで少し浮き、白い枠と水色の光。反対側のカードは暗くなる。切り替えは約 0.15 秒でなめらかに。

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const Menu := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
const Frames := preload("res://src/bossmaker/visuals/encounter/rbm_encounter_ally_frames.gd")
const HOLOGRAM := preload("res://src/bossmaker/home_monitor/rbm_home_card_hologram.gdshader")
const BACKGROUND := "res://assets_bossmaker/art/battle_courtyard_night.png"
const ALLIES := ["hero", "samurai", "healer", "butler"]
const ORANGE := Color("ff9a3c")
const ART_HEIGHT := 150.0
## ホバーで浮く量（px）と、斬撃の周期（秒）。
const LIFT := 6.0
const SWING_PERIOD := 0.9

var kind := "challenge"
var hover := 0.0      # 自分に重ねている度合い（0〜1）
var dim := 0.0        # 反対側に重ねている度合い（暗くする）
var _hover_target := 0.0
var _dim_target := 0.0
var _t := 0.0
var _body: Control
var _style: StyleBoxFlat
var _art: Control
var _bg: TextureRect
var _boss: TextureRect
var _holo: TextureRect
var _allies: Node2D
var _fx: Node2D
var _marks: Control
var _shade: ColorRect
var _title: Label
var _sub: Label
var _cta
var _bar: ColorRect
var _tags: Array = []  # [Label, 文言の鍵]（言語の切り替えで書き直す）

func setup(p_kind: String, card_size: Vector2) -> void:
	kind = p_kind
	name = "HomeCardArt"
	size = card_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Frames.hold(ALLIES, true)
	_body = Panel.new()
	_body.name = "HomeCardBody"
	_body.size = card_size
	_body.clip_contents = true
	_style = S.box(Color("0d1a21", 0.97), Color(S.ACCENT, 0.55))
	_body.add_theme_stylebox_override("panel", _style)
	add_child(_body)
	_art = Control.new()
	_art.name = "HomeCardArtArea"
	_art.position = Vector2(12, 12)
	_art.size = Vector2(card_size.x - 24, ART_HEIGHT)
	_art.clip_contents = true
	_body.add_child(_art)
	if kind == "challenge":
		_build_challenge_art()
	else:
		_build_create_art()
	_fx = Node2D.new()
	_fx.name = "HomeCardFx"
	_art.add_child(_fx)
	_fx.draw.connect(_draw_fx)
	_marks = Control.new()
	_body.add_child(_marks)
	S.corner_marks(_marks, Rect2(16, 16, card_size.x - 32, ART_HEIGHT - 8), Color.WHITE)
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0)
	_shade.position = _art.position
	_shade.size = _art.size
	_body.add_child(_shade)
	_title = Menu.shadow(S.label(_body, "", Rect2(24, 170, 330, 44), 30, S.TEXT, "HomeCardTitle"))
	_sub = S.label(_body, "", Rect2(24, 210, card_size.x - 280, 28), 14, S.MUTED, "HomeCardSubtitle")
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if kind == "challenge":
		var first := Menu.tag(_body, tr("オンライン"), Vector2(24, 238), S.MUTED, Color("2a3a44"), Color(S.INSET, 0.9))
		var second := Menu.tag(_body, tr("ランキング"), Vector2(32 + first.size.x, 238), S.MUTED, Color("2a3a44"), Color(S.INSET, 0.9))
		_tags = [[first, "オンライン"], [second, "ランキング"]]
	else:
		Menu.tag(_body, "SIMPLE", Vector2(24, 238), S.SILVER, Color("3a4a53"), Color(S.INSET, 0.9), true)
		Menu.tag(_body, "HARDCORE", Vector2(100, 238), S.HARD, S.HARD_EDGE, Color(S.INSET, 0.9), true)
	_cta = Menu.cta_strip(_body, Rect2(card_size.x - 232, 184, 208, 50), "", 18, "HomeCardCta")
	_bar = ColorRect.new()
	_bar.color = Color(S.ACCENT, 0.0)
	_bar.size = Vector2(4, card_size.y)
	_body.add_child(_bar)
	refresh_locale()
	_ignore_mouse(self)
	_apply()

func refresh_locale() -> void:
	if _title == null:
		return
	_title.text = tr("挑戦") if kind == "challenge" else tr("ボス作成")
	_sub.text = tr("公開されたボス戦に挑む") if kind == "challenge" else tr("自分だけのボス戦を作って公開する")
	_cta.label.text = tr("挑戦する") if kind == "challenge" else tr("作成する")
	for entry in _tags:
		(entry[0] as Label).text = tr(str(entry[1]))
	if _tags.size() == 2:
		(_tags[1][0] as Label).position.x = 32 + (_tags[0][0] as Label).get_combined_minimum_size().x

func set_hover(on: bool) -> void:
	_hover_target = 1.0 if on else 0.0

func set_dim(on: bool) -> void:
	_dim_target = 1.0 if on else 0.0

## 押した後（BOOT が始まった）: カードの絵を素早く消し、パネルの起動演出を見せる。
func begin_boot() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)

## ホームに戻った時: ふだんの状態へ即座に戻す。
func reset() -> void:
	modulate.a = 1.0
	hover = 0.0
	dim = 0.0
	_hover_target = 0.0
	_dim_target = 0.0
	_apply()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var k := minf(1.0, delta * 14.0)
	hover += (_hover_target - hover) * k
	dim += (_dim_target - dim) * k
	_apply()

func _apply() -> void:
	_body.position = Vector2(0, -roundf(LIFT * hover))
	_style.bg_color = Color("0d1a21", 0.97).lerp(Color("10252d", 0.98), hover).lerp(Color("0a141a", 0.97), dim)
	_style.border_color = Color(S.ACCENT, 0.55).lerp(S.TEXT, hover).lerp(Color(S.ACCENT_SOFT, 0.35), dim)
	_style.set_border_width_all(2 if hover >= 0.5 else 1)
	_style.shadow_color = Color(S.ACCENT, 0.35 * hover)
	_style.shadow_size = int(round(14.0 * hover))
	_shade.color = Color(0, 0, 0, 0.35 * dim)
	_title.add_theme_color_override("font_color", S.TEXT.lerp(S.MUTED, dim))
	_sub.add_theme_color_override("font_color", S.MUTED.lerp(S.SILVER, hover))
	_cta.set_lit(hover, hover)
	_bar.color = Color(S.ACCENT, hover)
	if kind == "challenge":
		_bg.modulate = Color(0.45, 0.5, 0.6).lerp(Color(0.75, 0.8, 0.9), hover)
		var hit := _hit_flash()
		_boss.position = Vector2(_art.size.x - 50 - _boss.size.x + 8.0 * hover + 3.0 * hit, 146 - _boss.size.y).round()
		_boss.modulate = Color.WHITE.lerp(Color(1.6, 1.4, 1.4), hit)
		_allies.queue_redraw()
	else:
		var bob := roundf(sin(_t * 1.6) * 2.0)
		_holo.position = Vector2((_art.size.x - _holo.size.x) / 2.0, 138 - _holo.size.y + bob - 6.0 * hover).round()
		_boss.position = _holo.position
		_holo.modulate.a = 1.0 - hover
		_boss.modulate.a = hover
	_fx.queue_redraw()
	_marks.modulate = Color(S.SILVER, 0.4).lerp(Color(S.ACCENT, 0.9), hover)

func _build_challenge_art() -> void:
	_bg = TextureRect.new()
	_bg.texture = load(BACKGROUND)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg.size = _art.size
	_art.add_child(_bg)
	S.gradient_rect(_art, Rect2(0, _art.size.y - 50, _art.size.x, 50), Color(S.PANEL, 0.0), Color(S.PANEL, 0.85))
	_boss = _sprite("musha", Vector2(150, 142))
	_art.add_child(_boss)
	_allies = Node2D.new()
	_allies.name = "HomeCardAllies"
	_allies.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_allies.scale = Vector2(0.58, 0.58)
	_art.add_child(_allies)
	_allies.draw.connect(_draw_allies)

func _build_create_art() -> void:
	S.rect(_art, Rect2(Vector2.ZERO, _art.size), S.INSET)
	var grid := Node2D.new()
	_art.add_child(grid)
	grid.draw.connect(func():
		for x in range(0, int(_art.size.x), 24):
			grid.draw_rect(Rect2(x, 0, 1, _art.size.y), Color(S.ACCENT, 0.06))
		for y in range(0, int(_art.size.y), 24):
			grid.draw_rect(Rect2(0, y, _art.size.x, 1), Color(S.ACCENT, 0.06)))
	var side_material := ShaderMaterial.new()
	side_material.shader = HOLOGRAM
	side_material.set_shader_parameter("alpha", 0.45)
	for side in [["slime", Vector2(30, 30)], ["golem", Vector2(_art.size.x - 30 - 96, 30)]]:
		var box := Panel.new()
		box.position = side[1]
		box.size = Vector2(96, 96)
		box.add_theme_stylebox_override("panel", S.box(Color(S.ACCENT, 0.04), Color(S.ACCENT, 0.35)))
		_art.add_child(box)
		var s := _sprite(str(side[0]), Vector2(76, 76))
		s.position = Vector2((96 - s.size.x) / 2.0, 88 - s.size.y)
		s.material = side_material
		box.add_child(s)
	var holo_material := ShaderMaterial.new()
	holo_material.shader = HOLOGRAM
	holo_material.set_shader_parameter("alpha", 0.7)
	_holo = _sprite("dragon", Vector2(200, 124))
	_holo.material = holo_material
	_art.add_child(_holo)
	_boss = _sprite("dragon", Vector2(200, 124))
	_art.add_child(_boss)

func _sprite(asset: String, fit: Vector2) -> TextureRect:
	var tex := S.fitted_sprite(asset, fit)
	var r := TextureRect.new()
	r.texture = tex
	r.size = S.fitted_size(tex, fit) if tex != null else fit
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

## 斬撃が当たる瞬間の閃き（ホバー中だけ、SWING_PERIOD ごと）。
func _hit_flash() -> float:
	if hover < 0.05:
		return 0.0
	var p := fmod(_t, SWING_PERIOD) / SWING_PERIOD
	return hover * clampf(1.0 - absf(p - 0.45) / 0.08, 0.0, 1.0)

func _draw_allies() -> void:
	var swing := clampf((hover - 0.3) / 0.7, 0.0, 1.0)
	var lunge := 0.0
	if hover > 0.05:
		var p := fmod(_t, SWING_PERIOD) / SWING_PERIOD
		lunge = hover * (smoothstep(0.0, 0.4, p) - smoothstep(0.6, 1.0, p))
	var hero_pose := "b:2" if swing > 0.5 else "b:0"
	var samurai_pose := "b:3" if swing > 0.5 else "b:0"
	var list := [["healer", "b:0", Vector2(70, 140)], ["butler", "b:0", Vector2(80, 235)],
		["samurai", samurai_pose, Vector2(250 + 170 * swing + 30 * lunge, 140)], ["hero", hero_pose, Vector2(260 + 280 * swing + 90 * lunge, 240)]]
	for i in list.size():
		var a: Array = list[i]
		var bob := roundf(sin(_t * 2.2 + i * 1.3) * 1.5) if swing < 0.5 else 0.0
		Frames.draw(_allies, str(a[0]), str(a[1]), (a[2] as Vector2) + Vector2(0, bob))

func _draw_fx() -> void:
	var p := 3.0
	if kind == "challenge":
		# ふだんから火の粉がゆっくり昇る。
		for i in 14:
			var x := 300.0 + fmod(float(i) * 37.0, 200.0) + sin(_t + i) * 6.0
			var y := fmod(150.0 - fmod(float(i) * 53.0, 140.0) - _t * (10.0 + i % 4 * 4.0), 150.0)
			if y < 0:
				y += 150.0
			_fx.draw_rect(Rect2(Vector2(x, y).snapped(Vector2(p, p)), Vector2(p, p)), Color(ORANGE, 0.35 + 0.4 * hover))
		if hover < 0.05:
			return
		# 斬撃の弧（SWING_PERIOD ごとに振り抜く）と、当たった所の火の粉
		var q := fmod(_t, SWING_PERIOD) / SWING_PERIOD
		var sweep := clampf(q / 0.5, 0.0, 1.0)
		var fade := 1.0 - clampf((q - 0.5) / 0.4, 0.0, 1.0)
		for k in 2:
			var cx := 440.0 + k * 30.0
			var cy := 66.0 + k * 20.0
			for i in int(22 * sweep):
				var u := float(i) / 21.0
				var a := lerpf(-1.1, 0.9, u)
				var r := 62.0 - k * 10.0
				var pos := Vector2(cx + cos(a) * r, cy + sin(a) * r * 0.8).snapped(Vector2(p, p))
				var w := p * (1.0 + 2.0 * sin(u * PI))
				_fx.draw_rect(Rect2(pos, Vector2(w, w)), Color(Color.WHITE if k == 0 else ORANGE, 0.9 * hover * fade))
		if q > 0.45:
			for i in 20:
				var ang := float(i) * 2.4
				var dist := 10.0 + 40.0 * clampf((q - 0.45) / 0.4, 0.0, 1.0) + float(i % 5) * 4.0
				var pos := (Vector2(500, 80) + Vector2(cos(ang), sin(ang)) * dist).snapped(Vector2(p, p))
				_fx.draw_rect(Rect2(pos, Vector2(p, p)), Color(ORANGE if i % 3 else Color(1, 0.95, 0.7), hover * fade))
		var burst := _hit_flash()
		if burst > 0.0:
			_fx.draw_rect(Rect2(470, 56, 6 * p, p), Color(1, 1, 1, burst))
			_fx.draw_rect(Rect2(476, 50, 2 * p, 4 * p), Color(1, 1, 1, burst))
		return
	# ボス作成: 設計台の輪がゆっくり回り、ホログラムの走査線が下りる。重ねると実体化してきらめく。
	var c := Vector2(_art.size.x / 2.0, 134)
	for i in 48:
		var a := TAU * float(i) / 48.0 + _t * 0.6
		_fx.draw_rect(Rect2((c + Vector2(cos(a) * 120, sin(a) * 16)).snapped(Vector2(3, 3)), Vector2(3, 3)), Color(S.ACCENT, 0.4 + 0.35 * hover))
	for i in 36:
		var a := TAU * float(i) / 36.0 - _t * 0.9
		_fx.draw_rect(Rect2((c + Vector2(cos(a) * 84, sin(a) * 10)).snapped(Vector2(3, 3)), Vector2(3, 3)), Color(S.ACCENT, 0.22 + 0.23 * hover))
	var holo_a := 1.0 - hover
	if holo_a > 0.02:
		for y in range(int(_holo.position.y), int(_holo.position.y + _holo.size.y), 6):
			_fx.draw_rect(Rect2(_holo.position.x, y, _holo.size.x, 1), Color(S.INSET, 0.55 * holo_a))
		var sy := _holo.position.y + fmod(_t * 50.0, _holo.size.y)
		_fx.draw_rect(Rect2(_holo.position.x - 6, sy, _holo.size.x + 12, 2), Color(S.ACCENT, 0.6 * holo_a))
	if hover < 0.02:
		return
	var cx2 := _art.size.x / 2.0
	_fx.draw_rect(Rect2(cx2 - 110, 0, 220, 138), Color(S.ACCENT, 0.06 * hover))
	for i in 18:
		var x := cx2 - 120.0 + fmod(float(i) * 47.0, 240.0)
		var y := fmod(10.0 + fmod(float(i) * 31.0, 130.0) - _t * 20.0, 140.0)
		if y < 0:
			y += 140.0
		var tw := clampf(0.5 + 0.5 * sin(_t * 6.0 + i), 0.0, 1.0) * hover
		var col := Color(S.ACCENT, 0.9 * tw) if i % 2 else Color(1, 1, 1, 0.9 * tw)
		var at := Vector2(x, y).snapped(Vector2(p, p))
		if i % 4 == 0:
			_fx.draw_rect(Rect2(at + Vector2(-p, 0), Vector2(3 * p, p)), col)
			_fx.draw_rect(Rect2(at + Vector2(0, -p), Vector2(p, 3 * p)), col)
		else:
			_fx.draw_rect(Rect2(at, Vector2(p, p)), col)
