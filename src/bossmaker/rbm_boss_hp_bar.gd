extends Control
## 戦闘画面のボスの HP バー（全部のボスで共通。表示専用の独立した部品）。戦闘の状態・計算には触れない。
## 表示する値は RBMBattlePresenter.apply_status_snapshot() が渡す「今表示している状態」（命中の瞬間に進む）だけ。
## - 減った時: 白く一瞬光り、BAR_EASE_TIME で減る。減った分は明るい色で少し残ってから縮む（どれだけ減ったかが分かる）。
## - 増えた時（回復・覚醒の回復）: BAR_EASE_TIME で増える。
## - 覚醒した後は色を変え、「覚醒」の札を添える（色だけに頼らない）。
## - 挑戦で作者が HP を非公開にしている時は、残りの量が分からない表示にし、数値は「HP　？？？」（ボスの詳細と同じ）。
## 見た目は案C（2026-10-23 ユーザーが採用。rbm_battle_hud_style.gd）: 左上に「BOSS」と「覚醒」の札、右に数値、下に細いバー。
## ボスの名前（BossLabel）はこの部品の外の文字で、左の「BOSS」の下・数値と同じ行に置く（rbm_fullscreen_battle_ui.gd）。

const HudStyle = preload("res://src/bossmaker/rbm_battle_hud_style.gd")

const BAR_EASE_TIME := 0.2
const CHIP_HOLD := 0.35
const CHIP_SHRINK := 0.45
const FLASH_TIME := 0.14
const BAR_HEIGHT := 8.0
## 数値の行の文字の下端（部品の上からの位置）。ボスの名前と同じ行。
const VALUE_BASELINE := 40.0
const FONT_SIZE := 16
const TAG_FONT_SIZE := 12

const FRAME := Color(0.263, 0.937, 1.0, 0.55)
const TRACK := Color("061019")
const FILL_TOP := Color("ff7a8a")
const FILL_BOTTOM := Color("c42d4f")
const AWAKENED_TOP := Color("ff74e0")
const AWAKENED_BOTTOM := Color("7d1d8a")
const HIDDEN_TOP := Color("6b7480")
const HIDDEN_BOTTOM := Color("3a414b")
const CHIP := Color("f6dfae")
const NOTCH := Color(0, 0, 0, 0.45)
const TAG_FILL := Color("3a0d33")
const TAG_EDGE := Color("ff7ad9")
const TAG_TEXT := Color("ffd6f1")

var hp := 0
var max_hp := 1
var awakened := false
var hp_visible := true
var _shown := 1.0      # 塗りの今の割合
var _chip := 1.0       # 減った分の割合（塗りより右に残る）
var _chip_start := 1.0
var _target := 1.0
var _from := 1.0
var _ease := -1.0      # 塗りが動いている間の経過（動いていない時は -1）
var _chip_age := -1.0  # 減った分が縮むまでの経過
var _flash := 0.0
var _has_state := false
var _font: Font

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 58)
	set_process(false)

## 今表示しているボスの状態を入れる。animate: 命中の瞬間（演出の再生中）だけ true。作り直し・REWIND はすぐ入れる。
func apply_state(boss: Dictionary, is_awakened: bool, visible_hp: bool, animate := false) -> void:
	if boss.is_empty():
		return
	var new_max := maxi(1, int(boss.get("max_hp", 1)))
	var new_hp := clampi(int(boss.get("hp", 0)), 0, new_max)
	var ratio := float(new_hp) / float(new_max)
	var lost := _has_state and ratio < _target - 0.0001
	var same := _has_state and new_hp == hp and new_max == max_hp
	hp = new_hp
	max_hp = new_max
	awakened = is_awakened
	hp_visible = visible_hp
	# 同じ値がもう一度来た時（演出の後の画面の更新・何回も当たる攻撃で別の人に当たった時など）は、減っている途中・
	# 減った分が縮む途中の動きを止めない（動き直しもしない）
	if same:
		queue_redraw()
		return
	if not _has_state or not animate or DisplayServer.get_name() == "headless" or not is_inside_tree():
		_has_state = true
		_shown = ratio
		_chip = ratio
		_target = ratio
		_ease = -1.0
		_chip_age = -1.0
		_flash = 0.0
		set_process(false)
		queue_redraw()
		return
	_from = _shown
	_target = ratio
	_ease = 0.0
	if lost:
		_chip = maxf(_chip, _from)
		_chip_start = _chip
		_chip_age = 0.0
		_flash = FLASH_TIME
	else:
		_chip = maxf(ratio, minf(_chip, ratio))
		_chip_age = -1.0
	set_process(true)
	queue_redraw()

## 右に出す文字（非公開の時は「HP　？？？」。ボスの詳細と同じ言葉）。
func display_text() -> String:
	return ("HP %s / %s" % [HudStyle.commas(hp), HudStyle.commas(max_hp)]) if hp_visible else tr("HP　%s") % tr("？？？")

## 今の数値（検証用。表示には使わない）。
func audit() -> Dictionary:
	return {"hp": hp, "max_hp": max_hp, "awakened": awakened, "hp_visible": hp_visible, "shown": _shown, "chip": _chip, "target": _target, "animating": is_processing()}

## バーの矩形（この部品の中の位置）。
func bar_rect() -> Rect2:
	return Rect2(1, size.y - BAR_HEIGHT - 1, maxf(40.0, size.x - 2), BAR_HEIGHT)

## 右の数値の左端（この部品の中の位置）。一番長い数値（HP 最大 / 最大）が入る幅で決める（値が変わっても動かない）。
## ボスの名前はここより左に収める。
func text_left() -> float:
	return size.x - ceilf(maxf(_value_width("HP %s / %s" % [HudStyle.commas(max_hp), HudStyle.commas(max_hp)]), _value_width(display_text())))

func _value_width(text: String) -> float:
	if hp_visible:
		var font := HudStyle.number_font()
		return font.get_string_size("HP", HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.CAPTION_SIZE).x + 6.0 + font.get_string_size(text.trim_prefix("HP "), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return _jp_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x

func _jp_font() -> Font:
	if _font == null:
		_font = get_theme_default_font()
	return _font

func _process(delta: float) -> void:
	if _ease >= 0.0:
		_ease += delta
		var t := clampf(_ease / BAR_EASE_TIME, 0.0, 1.0)
		_shown = lerpf(_from, _target, 1.0 - (1.0 - t) * (1.0 - t))
		if t >= 1.0:
			_shown = _target
			_ease = -1.0
	if _chip_age >= 0.0:
		_chip_age += delta
		if _chip_age > CHIP_HOLD:
			var k := clampf((_chip_age - CHIP_HOLD) / CHIP_SHRINK, 0.0, 1.0)
			_chip = lerpf(_chip_start, _shown, k)
			if k >= 1.0:
				_chip = _shown
				_chip_age = -1.0
	else:
		_chip = maxf(_shown, minf(_chip, _shown))
	_flash = maxf(0.0, _flash - delta)
	if _ease < 0.0 and _chip_age < 0.0 and _flash <= 0.0:
		set_process(false)
	queue_redraw()

func _draw() -> void:
	if not _has_state:
		return
	var number_font := HudStyle.number_font()
	# 左上: 「BOSS」と、覚醒した後は「覚醒」の札
	draw_string(number_font, Vector2(0, 12), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.CAPTION_SIZE, HudStyle.CYAN)
	if awakened:
		var tag := tr("覚醒")
		var x := ceilf(number_font.get_string_size("BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.CAPTION_SIZE).x) + 10.0
		var pill := Rect2(x, 0, ceilf(_jp_font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT_SIZE).x) + 20.0, 18)
		draw_style_box(HudStyle.pill(TAG_FILL, TAG_EDGE), pill)
		draw_string(_jp_font(), Vector2(pill.position.x + 10.0, 14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT_SIZE, TAG_TEXT)
	# 右: 数値（名前と同じ行）
	var text := display_text()
	var right := size.x
	if hp_visible:
		var value := text.trim_prefix("HP ")
		var value_w := number_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(number_font, Vector2(right - value_w, VALUE_BASELINE), value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HudStyle.TEXT)
		var caption_w := number_font.get_string_size("HP", HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.CAPTION_SIZE).x
		draw_string(number_font, Vector2(right - value_w - 6.0 - caption_w, VALUE_BASELINE), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.CAPTION_SIZE, HudStyle.CYAN)
	else:
		var w := _jp_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(_jp_font(), Vector2(right - w, VALUE_BASELINE), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HudStyle.TEXT)
	# 下: バー（外の暗い線 → 水色の細い線 → 中の暗い地）
	var bar := bar_rect()
	draw_rect(bar.grow(2), Color(0, 0, 0, 0.75))
	draw_rect(bar.grow(1), FRAME)
	draw_rect(bar, TRACK)
	var inner := bar.grow(-1)
	var top := HIDDEN_TOP if not hp_visible else (AWAKENED_TOP if awakened else FILL_TOP)
	var bottom := HIDDEN_BOTTOM if not hp_visible else (AWAKENED_BOTTOM if awakened else FILL_BOTTOM)
	var shown := 1.0 if not hp_visible else _shown
	var chip := 1.0 if not hp_visible else _chip
	if chip > shown:
		draw_rect(Rect2(inner.position.x + inner.size.x * shown, inner.position.y, inner.size.x * (chip - shown), inner.size.y), CHIP)
	var fill_w := roundf(inner.size.x * shown)
	if fill_w > 0.0:
		var half := floorf(inner.size.y * 0.5)
		draw_rect(Rect2(inner.position, Vector2(fill_w, half)), top)
		draw_rect(Rect2(inner.position + Vector2(0, half), Vector2(fill_w, inner.size.y - half)), bottom)
		draw_rect(Rect2(inner.position, Vector2(fill_w, 1)), top.lightened(0.45))
		if not hp_visible:
			# 非公開: 縞で「量は分からない」ことを示す（値によって変わらない）
			var x := 0.0
			while x < fill_w:
				draw_rect(Rect2(inner.position + Vector2(x, 0), Vector2(3, inner.size.y)), Color(0, 0, 0, 0.22))
				x += 9.0
	for q in [0.25, 0.5, 0.75]:
		draw_rect(Rect2(inner.position.x + roundf(inner.size.x * q), inner.position.y, 1, inner.size.y), NOTCH)
	if _flash > 0.0:
		draw_rect(inner, Color(1, 1, 1, 0.55 * _flash / FLASH_TIME))
