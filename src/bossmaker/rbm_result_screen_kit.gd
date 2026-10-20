extends RefCounted
## 戦闘の結果・クリアチェックの開始・保存の画面（2026-10-18 ユーザーの決定: 戦闘の結果は案C「シネマティック」、
## クリアチェックと保存は案A「王道RPG」。比較の資料は prototypes/result_screens_2026-10-17/）が共通に使う表示の部品。
## 色は挑戦トップ・STEP4 と同じ紺＋水色（RBMChallengeListStyle）に、案Aの見出しと枠だけ金。
## 表示だけを扱い、戦闘・保存・公開の状態には触れない。文字は呼び出し元が tr() を通して渡す。

const S = preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")

const RED := Color("e07a6a")
const OK := Color("74dcaa")

## 字間を広げた数字の字体（案Cの見出し「C L E A R」）。文字そのものは「CLEAR」のまま。
static var _spaced_fonts: Dictionary = {}
## 色の移り変わりの画像（一度作ったら使い回す。画面を出すたびに作ると、その瞬間のフレームが重くなる）。
static var _gradients: Dictionary = {}
## 裏で作っている絵の切り出し（RBMChallengeListStyle.fitted_sprite の鍵 -> {asset, fit, task, holder}）。
static var _warm_jobs: Dictionary = {}

# ---------------------------------------------------------------------------
# 絵の切り出しを前もって作る（PERFORMANCE.md §2.1: 結果の画面を出す瞬間に止まらない・停止を戦闘開始へ移さない）。
# 大きな絵（朽ちた機械武者は 1200×1800）の切り出しと縮小は 30ms 前後かかる。戦闘中に、画像の写し（メインスレッド、数ms）を
# 1フレームに1つだけ取り、切り出しと縮小（RBMChallengeListStyle.fit_image、同じ画素）は裏のスレッドで行う。

## asset を fit に収めた絵を、裏で作る予約をする（作ってある・予約済みなら何もしない）。
static func request_fitted(asset: String, fit: Vector2) -> void:
	if asset.is_empty() or S.has_fitted_sprite(asset, fit):
		return
	var key := S.fitted_sprite_key(asset, fit)
	if not _warm_jobs.has(key):
		_warm_jobs[key] = {"asset": asset, "fit": fit, "task": -1, "holder": {}}

## 予約を進める（呼び出し元が毎フレーム呼ぶ）。終わった物を絵にして置き、まだ始めていない物を1つだけ裏のスレッドへ渡す。
## 残りがあれば true。
static func advance_fitted() -> bool:
	var started := false
	for key in _warm_jobs.keys():
		var job: Dictionary = _warm_jobs[key]
		var task := int(job.task)
		if task >= 0:
			if WorkerThreadPool.is_task_completed(task):
				_finish_job(key)
			continue
		if started:
			continue
		started = true
		var asset: String = job.asset
		var fit: Vector2 = job.fit
		var source := RBMVisualAssets.texture(asset, 0)
		var image: Image = source.get_image() if source != null else null
		if image == null or image.is_empty():
			# 画像を読めない環境（headless など）は、今までどおり表示側で縮める
			_warm_jobs.erase(key)
			if source != null and not S.has_fitted_sprite(asset, fit):
				S.store_fitted_sprite(asset, fit, source)
			continue
		var holder: Dictionary = job.holder
		holder["image"] = image
		job.task = WorkerThreadPool.add_task(func(): holder["result"] = S.fit_image(image, fit), false, "result screen sprite")
	return not _warm_jobs.is_empty()

## 裏で作っている途中の絵を、今すぐ使えるようにする（終わるのを待つ。まだ始めていなければ予約を消す）。
static func finish_fitted(asset: String, fit: Vector2) -> void:
	var key := S.fitted_sprite_key(asset, fit)
	if not _warm_jobs.has(key):
		return
	if int(_warm_jobs[key].task) >= 0:
		_finish_job(key)
	else:
		_warm_jobs.erase(key)

static func _finish_job(key: String) -> void:
	var job: Dictionary = _warm_jobs[key]
	_warm_jobs.erase(key)
	WorkerThreadPool.wait_for_task_completion(int(job.task))
	var result = (job.holder as Dictionary).get("result", null)
	if S.has_fitted_sprite(job.asset, job.fit):
		return
	if result is Image:
		S.store_fitted_sprite(job.asset, job.fit, ImageTexture.create_from_image(result))
	else:
		S.store_fitted_sprite(job.asset, job.fit, RBMVisualAssets.texture(job.asset, 0))

static func spaced_font(spacing: int) -> Font:
	if not _spaced_fonts.has(spacing):
		var f := FontVariation.new()
		f.base_font = S.number_font()
		f.spacing_glyph = spacing
		_spaced_fonts[spacing] = f
	return _spaced_fonts[spacing]

## クリアタイム（秒）を「1:23」に。
static func time_text(seconds: float) -> String:
	var s := int(round(maxf(seconds, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]

## 1行の文字（大きさを決める前に切り取りの設定をする）。
static func label(parent: Node, text: String, rect: Rect2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, node_name := "", font: Font = null) -> Label:
	var l := Label.new()
	if not node_name.is_empty():
		l.name = node_name
	style_label(l, rect, size, color, align, font)
	l.text = text
	parent.add_child(l)
	return l

## 折り返す文字。
static func wrap(parent: Node, text: String, rect: Rect2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, node_name := "") -> Label:
	var l := Label.new()
	if not node_name.is_empty():
		l.name = node_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.position = rect.position
	l.size = rect.size
	l.text = text
	parent.add_child(l)
	return l

## 既にある文字（OutcomeLabel など、呼び出し元が作った物）を、この画面の見た目にする。
static func style_label(l: Label, rect: Rect2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, font: Font = null) -> void:
	l.theme_type_variation = &""
	l.clip_text = true
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	else:
		l.remove_theme_font_override("font")
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	l.position = rect.position
	l.size = rect.size

static func panel(parent: Node, rect: Rect2, fill: Color, edge: Color, width := 1, node_name := "") -> Panel:
	var p := Panel.new()
	if not node_name.is_empty():
		p.name = node_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", S.box(fill, edge, width))
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p

## 画面全体を暗くする幕（下の画面を押せないようにもする）。
static func dim(parent: Node, alpha: float, node_name := "Dim") -> ColorRect:
	var c := ColorRect.new()
	c.name = node_name
	c.color = Color(0.02, 0.035, 0.05, alpha)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

## 出方（表示専用）。from_offset から元の位置へ、透明から不透明へ。作った Tween を返す（途中で止める時に使う）。
## hide_until_start: 出始めるまで描かない（その時に初めて文字を描く。画面を出す1フレームに文字の準備を集めないため）。
## 呼び出し元のボタンなど、visible を状態に使う物には使わない。
static func enter(node: CanvasItem, delay: float, duration: float, from_offset := Vector2.ZERO, from_scale := 1.0, hide_until_start := false) -> Tween:
	if node == null:
		return null
	var c := node as Control
	var to_pos := c.position if c != null else Vector2.ZERO
	node.modulate.a = 0.0
	if c != null:
		c.position = to_pos + from_offset
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2.ONE * from_scale
	var tw := node.create_tween().set_parallel(true)
	if hide_until_start and delay > 0.0:
		node.visible = false
		tw.tween_callback(func(): node.visible = true).set_delay(delay)
	tw.tween_property(node, "modulate:a", 1.0, duration).set_delay(delay)
	if c != null:
		tw.tween_property(c, "position", to_pos, duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if from_scale != 1.0:
			tw.tween_property(c, "scale", Vector2.ONE, duration).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw

## ボスの絵（覚醒後なら覚醒後の絵）。足元をそろえて rect に収める。
static func boss_sprite(parent: Node, asset: String, rect: Rect2, modulate := Color.WHITE, node_name := "BossSprite") -> TextureRect:
	finish_fitted(asset, rect.size)
	var tex := S.fitted_sprite(asset, rect.size)
	if tex == null:
		return null
	var fit := S.fitted_size(tex, rect.size)
	var r := TextureRect.new()
	r.name = node_name
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2(rect.position.x + (rect.size.x - fit.x) * 0.5, rect.end.y - fit.y)
	r.size = fit
	r.modulate = modulate
	parent.add_child(r)
	return r

## 味方の絵（攻略パーティ RBMPartyRosterKit.sprite と同じ切り出し・足元の影・暗さ。影の画像は使い回す）。
static func ally_sprite(parent: Node, id: String, rect: Rect2, dark := false) -> TextureRect:
	finish_fitted(id, rect.size)
	var tex := S.fitted_sprite(id, rect.size)
	if tex == null:
		return null
	var fit := S.fitted_size(tex, rect.size)
	floor_shadow(parent, Rect2(rect.position.x + rect.size.x * 0.5 - fit.x * 0.42, rect.end.y - 9, fit.x * 0.84, 14))
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.texture = tex
	r.position = Vector2(rect.position.x + (rect.size.x - fit.x) * 0.5, rect.end.y - fit.y)
	r.size = fit
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dark:
		r.modulate = Color(0.55, 0.6, 0.64, 0.85)
	parent.add_child(r)
	return r

## 足元の楕円の影（RBMChallengeListStyle.floor_shadow と同じ見た目）。
static func floor_shadow(parent: Node, area: Rect2) -> TextureRect:
	if not _gradients.has("floor_shadow"):
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = g
		texture.width = 64
		texture.height = 64
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		_gradients["floor_shadow"] = texture
	return _texture_rect(parent, area, _gradients["floor_shadow"])

## 横の色の移り変わり（RBMChallengeListStyle.gradient_rect の横向きと同じ見た目。画像は横256×縦1で使い回す）。
static func hgradient(parent: Node, area: Rect2, from: Color, to: Color, start: float, end: float) -> TextureRect:
	var key := str(["h", from, to, start, end])
	if not _gradients.has(key):
		var g := Gradient.new()
		g.set_color(0, from)
		g.set_color(1, to)
		g.set_offset(0, start)
		g.set_offset(1, end)
		var texture := GradientTexture2D.new()
		texture.gradient = g
		texture.width = 256
		texture.height = 1
		texture.fill_to = Vector2(1, 0)
		_gradients[key] = texture
	return _texture_rect(parent, area, _gradients[key])

static func _texture_rect(parent: Node, area: Rect2, texture: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture = texture
	t.position = area.position
	t.size = area.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(t)
	return t

## 案A: 「撃破ターン ……… 16」の行。
static func leader_line(parent: Node, key: String, value: String, rect: Rect2, size: int, key_color: Color, value_color: Color, node_name := "") -> Control:
	var row := Control.new()
	if not node_name.is_empty():
		row.name = node_name
	row.position = rect.position
	row.size = rect.size
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var k := label(row, key, Rect2(0, 0, rect.size.x * 0.55, rect.size.y), size, key_color, HORIZONTAL_ALIGNMENT_LEFT, "Key")
	var v := label(row, value, Rect2(rect.size.x * 0.45, 0, rect.size.x * 0.55, rect.size.y), size + 2, value_color, HORIZONTAL_ALIGNMENT_RIGHT, "Value", S.number_font())
	var kw := k.get_theme_font("font").get_string_size(k.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var vw := v.get_theme_font("font").get_string_size(v.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size + 2).x
	var dots := Dots.new()
	dots.name = "Dots"
	dots.from_x = kw + 10.0
	dots.to_x = rect.size.x - vw - 10.0
	dots.color = Color(S.MUTED, 0.5)
	dots.position = Vector2(0, rect.size.y * 0.5 + 4)
	dots.size = Vector2(rect.size.x, 2)
	row.add_child(dots)
	return row

## 「………」の点（8px おきの 2×2 の点を1つの部品で描く）。
class Dots:
	extends Control
	var from_x := 0.0
	var to_x := 0.0
	var color := Color.WHITE
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var x := from_x
		while x < to_x:
			draw_rect(Rect2(x, 0, 2, 2), color)
			x += 8.0

## 案A: 二重の枠の窓（外は金、内は細い金）。title があれば上に見出しと線。
static func window(parent: Node, rect: Rect2, title := "", node_name := "") -> Control:
	var w := Control.new()
	if not node_name.is_empty():
		w.name = node_name
	w.position = rect.position
	w.size = rect.size
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(w)
	panel(w, Rect2(Vector2.ZERO, rect.size), Color(S.BG, 0.94), S.GOLD, 2)
	panel(w, Rect2(5, 5, rect.size.x - 10, rect.size.y - 10), Color(S.PANEL, 0.0), Color(S.GOLD_EDGE, 0.9), 1)
	if not title.is_empty():
		label(w, title, Rect2(22, 12, rect.size.x - 44, 26), 16, S.GOLD, HORIZONTAL_ALIGNMENT_LEFT, "WindowTitle")
		S.rect(w, Rect2(20, 42, rect.size.x - 40, 1), Color(S.GOLD_EDGE, 0.8))
	return w

## 案A: 開始・保存の画面の後ろ。ボスの戦闘背景を暗くして敷く。
static func backdrop(parent: Control, boss_asset: String, time_of_day: String) -> void:
	var bg := TextureRect.new()
	bg.name = "Backdrop"
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture = RBMBattleBackgrounds.texture_for(boss_asset, time_of_day)
	bg.modulate = Color(0.45, 0.5, 0.58)
	parent.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim(parent, 0.45, "BackdropDim")

## 案A: 「▶」で選ぶメニューの1行（文字だけ。マウスを重ねた・選んだ行は金の文字と薄い下地）。
static func menu_item_style(b: Button, size := 18) -> void:
	# 見た目は一度だけ作る（出すたびに作り直さない）。位置・大きさは呼び出し元が決める
	if b.get_meta("result_style", "") == "menu%d" % size:
		return
	b.set_meta("result_style", "menu%d" % size)
	b.theme_type_variation = &""
	var none := StyleBoxEmpty.new()
	var lit := S.box(Color(S.GOLD, 0.10), Color(S.GOLD, 0.0))
	lit.content_margin_left = 8
	none.content_margin_left = 8
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("disabled", none)
	for key in ["hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(key, lit)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", S.TEXT)
	for key in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, S.GOLD)
	b.add_theme_color_override("font_disabled_color", S.DIM)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)

## 案A: 「▶」のカーソルで選ぶメニュー。窓を parent に作り、buttons（呼び出し元のボタン。親は変えない。親は parent と同じ原点）を
## 窓の中の行に置く。カーソルはフォーカスの行に付き、マウスを重ねた行にもフォーカスが移る。返り値は窓。
static func menu(parent: Node, rect: Rect2, buttons: Array, node_name := "Menu") -> Control:
	var w := window(parent, Rect2(rect.position, Vector2(rect.size.x, 24.0 + 42.0 * buttons.size())), "", node_name)
	var cursor := label(w, "▶", Rect2(18, 12, 24, 40), 18, S.GOLD, HORIZONTAL_ALIGNMENT_LEFT, "MenuCursor")
	for i in buttons.size():
		var b: Button = buttons[i]
		menu_item_style(b, 18)
		b.position = rect.position + Vector2(42, 12 + 42 * i)
		b.size = Vector2(rect.size.x - 60, 40)
		b.set_meta("menu_row_y", 12.0 + 42.0 * i)
		b.set_meta("menu_cursor", cursor)
		if not b.has_meta("menu_bound"):
			b.set_meta("menu_bound", true)
			b.mouse_entered.connect(func():
				if b.is_visible_in_tree() and not b.disabled:
					b.grab_focus())
			b.focus_entered.connect(func():
				var c = b.get_meta("menu_cursor", null)
				if is_instance_valid(c):
					(c as Control).position.y = float(b.get_meta("menu_row_y", 12.0)))
	return w

## 案C: 下の黒い帯のボタン。挑戦トップと同じ枠付きのボタン（主は水色の枠）を、帯の上で読める大きさにする。
## （2026-10-18 ユーザー: 試作の文字だけのボタンは薄くて見づらい → 枠と下地を付け、文字を大きく明るく）
static func bar_button_style(b: Button, primary: bool) -> void:
	# 見た目は一度だけ作る（出すたびに作り直さない）
	var style_key := "bar_primary" if primary else "bar"
	if b.get_meta("result_style", "") == style_key:
		return
	b.set_meta("result_style", style_key)
	b.theme_type_variation = &""
	S.button_style(b, primary)
	b.add_theme_font_size_override("font_size", 20 if primary else 18)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, S.TEXT)
	if primary:
		# 主のボタンは下地も少し明るく（暗い帯の上で目に入るように）
		var normal := b.get_theme_stylebox("normal") as StyleBoxFlat
		if normal != null:
			normal.bg_color = Color("123a42")
			normal.set_border_width_all(2)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
