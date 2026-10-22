extends Node2D
## 命中した相手の上に出るダメージ・回復の数字（全員・全部の技で共通の部品）。表示専用。
## ステージの impact（命中が確定した瞬間）で、その出来事の結果（ダメージ・回復・SP回復・カウンターの反撃）を読んで出すだけ。
## 戦闘の状態・乱数・次の行動・演出の時間には触れない。演出の終わりを待たせない（数字が出ている間も次の行動へ進める）。
##
## 動き（2026-10-22 の参考動画「跳ねるダメージ数字」の結論の値をこの画面の大きさに合わせたもの）:
## 数字を1桁ずつ、左の桁から STAGGER ずつ遅らせて跳ねさせる（波のように見える）。1桁の跳ね方は HOP の間に
## 「上がる時は減速 → 落ちる時は加速 → 着地 → 高さの 0.32 倍だけもう一度跳ねる → 着地」。最後の桁が跳ね終わってから
## HOLD だけ揃って見せ、FADE で消える。
## 桁は小さなドット絵の数字（1度だけ作って使い回す）を NEAREST で拡大して描く。毎フレーム作る物は無い。

const STAGGER := 0.055
const HOP := 0.62
const HOP_HEIGHT := 26.0
const HOLD := 0.9
const FADE := 0.26
## ドット絵の数字の1画素の大きさ（画面の座標で）。
const PIXEL := 3.0
const GLYPH_W := 6
const GLYPH_H := 8
## 桁の送り（ドット絵の画素で）。縁取り1画素ずつが隣と重なり、塗りは重ならない。
const ADVANCE := 7
## 同じ相手に続けて当たった時、前の数字を上へずらす量。
const STACK_STEP := 30.0
## 画面の上下の、HUD がかぶる帯（数字をこの内側へ収める）。
const SAFE_TOP := 64.0
const SAFE_BOTTOM := 176.0
const SAFE_SIDE := 12.0

const OUTLINE := Color("120c1c")
const SHADOW := Color(0.04, 0.02, 0.08, 0.55)
## 種類ごとの塗り（上の明るい色 → 下の色）。弱点は参考動画のクリティカルと同じ黄色。
const PALETTES := {
	"damage": [Color("ffffff"), Color("d6dbe8")],
	"weak": [Color("fff27a"), Color("f5a623")],
	"resist": [Color("c3cede"), Color("7f8ca3")],
	"heal": [Color("c8ffb0"), Color("49c96a")],
	"sp": [Color("bdf0ff"), Color("48a6f2")],
}
## 色だけに頼らないための小さな添え書き（戦闘の文字の欄と同じ言葉・翻訳）。HUD と同じ字体で描く。
const TAGS := {"weak": "弱点！", "resist": "耐性！"}
const TAG_SIZE := 18

const GLYPHS := {
	"0": [".####.", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."],
	"1": ["..##..", ".###..", "####..", "..##..", "..##..", "..##..", "..##..", "######"],
	"2": [".####.", "##..##", "....##", "...##.", "..##..", ".##...", "##....", "######"],
	"3": [".####.", "##..##", "....##", "..###.", "....##", "....##", "##..##", ".####."],
	"4": ["...##.", "..###.", ".####.", "##.##.", "##.##.", "######", "...##.", "...##."],
	"5": ["######", "##....", "##....", "#####.", "....##", "....##", "##..##", ".####."],
	"6": [".####.", "##..##", "##....", "#####.", "##..##", "##..##", "##..##", ".####."],
	"7": ["######", "##..##", "....##", "...##.", "..##..", "..##..", "..##..", "..##.."],
	"8": [".####.", "##..##", "##..##", ".####.", "##..##", "##..##", "##..##", ".####."],
	"9": [".####.", "##..##", "##..##", "##..##", ".#####", "....##", "##..##", ".####."],
	"+": ["......", "..##..", "..##..", "######", "######", "..##..", "..##..", "......"],
	"S": [".####.", "##..##", "##....", ".####.", "....##", "....##", "##..##", ".####."],
	"P": ["#####.", "##..##", "##..##", "##..##", "#####.", "##....", "##....", "##...."],
}

## 種類と文字 → 縁取り・影つきの小さな画像。全部の数字で共有する（最初に使った時に1度だけ作る）。
static var _glyph_cache: Dictionary = {}

var stage: Control
## 表示の速さ（ステージの set_motion_speed() と同じ値。勝利演出のとどめのスローで数字も遅くなる）。
var time_scale := 1.0
var _numbers: Array[Dictionary] = []
var _font: Font

func _ready() -> void:
	z_index = 120
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

## 添え書きの字体（ステージに効いているテーマの字体＝HUD の日本語・英語と同じ）。
func _tag_font() -> Font:
	if _font == null:
		_font = stage.get_theme_default_font() if is_instance_valid(stage) else ThemeDB.fallback_font
	return _font

## 1つの出来事（ログの entry）の結果を、命中した相手ごとに出す。skill はその行動の技（通常攻撃は空）。
## part: "all"（全部）/ "hits"（カウンターの前: ボスの攻撃が当たった仲間だけ。防いだ人・反撃は出さない）
##       / "reflected"（カウンターの反撃が当たった時: ボスへの反撃のダメージだけ）。
func show_entry(entry: Dictionary, skill: Dictionary, battle: Variant, part := "all") -> void:
	if bool(entry.get("failed", false)):
		return
	var action := str(entry.get("action", ""))
	if not action in ["attack", "skill"]:
		return
	var batch: Array[Dictionary] = []
	if entry.has("hits"):
		var hits: Dictionary = entry["hits"]
		for uid in hits:
			var hit: Dictionary = hits[uid] if hits[uid] is Dictionary else {"target": uid, "amount": hits[uid]}
			_add_hit(batch, hit, skill, battle, part)
	elif entry.has("healed"):
		var healed: Dictionary = entry["healed"]
		for uid in healed:
			_add(batch, str(uid), int(healed[uid]), "heal")
	elif entry.has("recovered"):
		var recovered: Dictionary = entry["recovered"]
		for uid in recovered:
			_add(batch, str(uid), int(recovered[uid]), "sp")
	elif entry.has("amount") or entry.has("reflected"):
		var target := str(entry.get("target", entry.get("actor", "boss")))
		var label := "ダメージ" if action == "attack" else str(RBMBattleUiKit.AMOUNT_UNIT_BY_EFFECT.get(str(skill.get("effect", "")), "ダメージ"))
		if label == "回復":
			_add(batch, target, int(entry.get("amount", 0)), "heal")
		elif label == "SP回復":
			_add(batch, target, int(entry.get("amount", 0)), "sp")
		else:
			_add_hit(batch, entry, skill, battle, part)
	_place(batch)

## 1人への攻撃。カウンターで防いだ時は、防いだ側には出さず、ボスへの反撃のダメージだけを出す。
func _add_hit(batch: Array[Dictionary], hit: Dictionary, skill: Dictionary, battle: Variant, part := "all") -> void:
	if bool(hit.get("blocked", false)):
		if hit.has("reflected") and part != "hits":
			_add(batch, "boss", int(hit["reflected"]), "damage")
		return
	if part == "reflected":
		return
	var target := str(hit.get("target", "boss"))
	var kind := "damage"
	var unit = _unit(battle, target)
	if unit != null and not skill.is_empty():
		match RBMBattleUiKit.attribute_hit_kind(skill, unit):
			"weak": kind = "weak"
			"resist": kind = "resist"
	_add(batch, target, int(hit.get("amount", 0)), kind)

func _add(batch: Array[Dictionary], key: String, amount: int, kind: String) -> void:
	if amount <= 0 and kind in ["heal", "sp"]:
		return
	if not is_instance_valid(stage) or not stage._visuals.has(key):
		return
	var text := str(maxi(amount, 0))
	if kind == "heal":
		text = "+" + text
	elif kind == "sp":
		text = "SP+" + text
	batch.append({"key": key, "text": text, "kind": kind})

func _unit(battle: Variant, key: String) -> Variant:
	if not battle is RBMBattle:
		return null
	if key == "boss":
		return battle.boss
	return RBMBattleUiKit.unit_by_id(battle, int(key))

## 相手の上（ボスは胸、味方は頭の上）に置き、画面の内側へ収める。同じ瞬間の数字どうしが重なる時は上へずらす。
## 同じ相手にまだ前の数字が出ていれば、前の数字を1段上げる（新しい数字はいつも同じ高さに出る）。
func _place(batch: Array[Dictionary]) -> void:
	if batch.is_empty():
		return
	var placed: Array[Rect2] = []
	for n in batch:
		var key: String = n["key"]
		for old in _numbers:
			if old["key"] == key:
				old["stack"] = float(old["stack"]) + STACK_STEP
		var digits_width: float = _text_width(n["text"])
		# 添え書き（弱点！など）は数字の左に置く（跳ねる数字とぶつからない）。全体の真ん中を相手に合わせる。
		n["tag_w"] = ceilf(_tag_font().get_string_size(tr(TAGS[n["kind"]]), HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x) + 6.0 if TAGS.has(n["kind"]) else 0.0
		var width: float = digits_width + n["tag_w"]
		var anchor := _anchor(key)
		var top_room := HOP_HEIGHT + GLYPH_H * PIXEL
		var x := clampf(anchor.x - width * 0.5, SAFE_SIDE, maxf(SAFE_SIDE, stage.size.x - SAFE_SIDE - width))
		var y := clampf(anchor.y, SAFE_TOP + top_room, maxf(SAFE_TOP + top_room, stage.size.y - SAFE_BOTTOM))
		var rect := Rect2(x, y - GLYPH_H * PIXEL, width, GLYPH_H * PIXEL)
		for _try in range(4):
			var hit := false
			for other in placed:
				if other.grow(2.0).intersects(rect):
					hit = true
					break
			if not hit or rect.position.y - STACK_STEP < SAFE_TOP + HOP_HEIGHT:
				break
			rect.position.y -= STACK_STEP
		placed.append(rect)
		n["origin"] = Vector2(rect.position.x + n["tag_w"], rect.end.y).round()
		n["age"] = 0.0
		n["stack"] = 0.0
		n["lift"] = 0.0
		n["life"] = (n["text"].length() - 1) * STAGGER + HOP + HOLD + FADE
		_numbers.append(n)
	set_process(true)
	queue_redraw()

func _anchor(key: String) -> Vector2:
	var visual: Control = stage._visuals[key]
	if key != "boss" and visual.has_method("visible_rect"):
		var bounds: Rect2 = visual.call("visible_rect")
		if bounds.size != Vector2.ZERO:
			return Vector2(visual.position.x + bounds.get_center().x, visual.position.y + bounds.position.y - 4.0)
	return stage._chest(key) - Vector2(0, 8)

func _text_width(text: String) -> float:
	return ((text.length() - 1) * ADVANCE + GLYPH_W) * PIXEL

func _process(delta: float) -> void:
	var step := delta * time_scale
	for i in range(_numbers.size() - 1, -1, -1):
		var n: Dictionary = _numbers[i]
		n["age"] = float(n["age"]) + step
		n["lift"] = lerpf(float(n["lift"]), float(n["stack"]), minf(1.0, delta * 32.0))
		if float(n["age"]) >= float(n["life"]):
			_numbers.remove_at(i)
	if _numbers.is_empty():
		set_process(false)
	queue_redraw()

## 1桁の跳ね（0〜1 の進み → 上方向の量）。上がる時は減速、落ちる時は加速、着地後にもう一度小さく跳ねる。
static func hop_offset(p: float) -> float:
	if p <= 0.0 or p >= 0.74:
		return 0.0
	if p < 0.24:
		var a := p / 0.24
		return HOP_HEIGHT * (1.0 - (1.0 - a) * (1.0 - a))
	if p < 0.46:
		var b := (p - 0.24) / 0.22
		return HOP_HEIGHT * (1.0 - b * b)
	if p < 0.60:
		var c := (p - 0.46) / 0.14
		return HOP_HEIGHT * 0.32 * (1.0 - (1.0 - c) * (1.0 - c))
	var d := (p - 0.60) / 0.14
	return HOP_HEIGHT * 0.32 * (1.0 - d * d)

func _draw() -> void:
	for n in _numbers:
		var age: float = n["age"]
		var text: String = n["text"]
		var alpha := clampf((float(n["life"]) - age) / FADE, 0.0, 1.0)
		var origin: Vector2 = n["origin"] - Vector2(0, roundf(float(n["lift"])))
		var glyph_size := Vector2(GLYPH_W + 2, GLYPH_H + 3) * PIXEL
		for i in range(text.length()):
			var local := age - i * STAGGER
			if local < 0.0:
				break
			var appear := clampf(local / 0.04, 0.0, 1.0)
			var y := origin.y - GLYPH_H * PIXEL - PIXEL - roundf(hop_offset(local / HOP))
			var pos := Vector2(origin.x + (i * ADVANCE - 1) * PIXEL, y)
			draw_texture_rect(_glyph(text[i], n["kind"]), Rect2(pos, glyph_size), false, Color(1, 1, 1, alpha * appear))
		if TAGS.has(n["kind"]):
			var tag: String = tr(TAGS[n["kind"]])
			var color: Color = PALETTES[n["kind"]][0]
			color.a = alpha * clampf(age / 0.08, 0.0, 1.0)
			var outline := OUTLINE
			outline.a = color.a
			var at := Vector2(origin.x - float(n["tag_w"]), origin.y - 3.0)
			draw_string_outline(_tag_font(), at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE, 6, outline)
			draw_string(_tag_font(), at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE, color)

## 今出ている数字を消す（戦闘を出た・別の戦闘になった・画面が隠れた時）。
func clear() -> void:
	_numbers.clear()
	time_scale = 1.0
	set_process(false)
	queue_redraw()

func active_count() -> int:
	return _numbers.size()

## 検証用: 今出ている数字の位置と文字（表示には使わない）。
func audit() -> Array:
	var out: Array = []
	for n in _numbers:
		out.append({"key": n["key"], "text": n["text"], "kind": n["kind"], "origin": n["origin"], "age": n["age"], "lift": n["lift"], "stack": n["stack"]})
	return out

static func _glyph(ch: String, kind: String) -> ImageTexture:
	var cache_key := kind + ":" + ch
	if _glyph_cache.has(cache_key):
		return _glyph_cache[cache_key]
	var rows: Array = GLYPHS.get(ch, GLYPHS["0"])
	var palette: Array = PALETTES.get(kind, PALETTES["damage"])
	var w := GLYPH_W + 2
	var h := GLYPH_H + 3
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fill := func(x: int, y: int) -> bool:
		return y >= 0 and y < GLYPH_H and x >= 0 and x < GLYPH_W and str(rows[y])[x] == "#"
	for y in range(h):
		for x in range(w):
			var gx := x - 1
			var gy := y - 1
			if fill.call(gx, gy):
				var t := clampf(float(gy) / float(GLYPH_H - 1), 0.0, 1.0)
				image.set_pixel(x, y, (palette[0] as Color).lerp(palette[1], snappedf(t, 0.34)))
				continue
			var near := false
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					if fill.call(gx + ox, gy + oy):
						near = true
			if near:
				image.set_pixel(x, y, OUTLINE)
			elif fill.call(gx, gy - 2) or fill.call(gx - 1, gy - 2) or fill.call(gx + 1, gy - 2):
				image.set_pixel(x, y, SHADOW)
	var texture := ImageTexture.create_from_image(image)
	_glyph_cache[cache_key] = texture
	return texture
