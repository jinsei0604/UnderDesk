class_name RBMCreatorTopChoice
extends Control

## ボス戦作成トップの2つの選択肢（2026-10、ユーザーが完成イメージで承認した「案A＋案C」）。
## ふだんは同じ幅の2枚（案A）。マウスを重ねる／キーボードで選ぶと、選んだ方が広く（720px）、
## もう一方が狭く（408px）なる（案C、0.22秒の ease-out、UI_UX §3）。どちらを選んでいるかが分かり、
## 動きはその変化を伝えるためだけに使う（UI_UX §15）。カードの間の隙間では選択をそのまま保ち、
## 2枚の外へ出ると元の同じ幅に戻る（キーボードで選んでいるカードがあれば、そのカードのまま）。
##
## 左「新しいボス戦を作る」= 主な行動（水色の枠）。右「保存したボス戦を編集」= 保存件数と内訳。
## 絵は RBMCreatorTopArt（画像を使わない図形）。押した時の処理は呼び出し側（RBMCreatorEntry）が持つ。

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const M := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
const Art := preload("res://src/bossmaker/creator/rbm_creator_top_art.gd")

const AREA_SIZE := Vector2(1152, 480)
const GAP := 24.0
const WIDE := 720.0
const NARROW := 408.0
const DURATION := 0.22
const ART_RECT_HEIGHT := 184.0
const CTA_TOP := 412.0
const CTA_HEIGHT := 52.0
const NONE := -1
const OUTSIDE := Vector2(-100000, -100000)

## 1枚のカード。Button 自身は何も描かず（文字は子の Label）、カードの地・枠・絵の枠を _draw で描く。
## glow = 選ばれている度合い（0〜1）、lit = 「作成を始める」などの帯が光る度合い。
class Card:
	extends Button
	var primary := false
	var glow := 0.0
	var lit := 0.0
	var art: Control
	var title_label: Label
	var description_label: Label
	## 選ばれている時だけ見せる補足（glow に合わせて現れる）。
	var extra: Control
	var cta: M.CtaStrip

	func setup(is_primary: bool, title: String, description: String, art_node: Control, cta_text: String) -> void:
		primary = is_primary
		text = ""
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		add_theme_stylebox_override("focus", S.focus_ring())
		M.accessible_name(self, title)
		art = art_node
		art.name = "Art"
		add_child(art)
		title_label = S.label(self, title, Rect2(32, 214, 300, 36), 26, S.TEXT, "TitleLabel")
		description_label = S.label(self, description, Rect2(32, 256, 300, 46), 15, S.MUTED, "DescriptionLabel")
		description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		cta = M.cta_strip(self, Rect2(16, CTA_TOP, 300, CTA_HEIGHT), cta_text, 18, "CtaStrip")
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func set_layout(area: Rect2, glow_value: float, lit_value: float) -> void:
		position = area.position
		size = area.size
		glow = glow_value
		lit = lit_value
		var w := area.size.x
		art.position = Vector2(16, 16)
		art.size = Vector2(w - 32, ART_RECT_HEIGHT)
		art.call("set_glow", glow)
		title_label.size.x = w - 64
		description_label.size.x = w - 64
		if extra != null:
			extra.modulate.a = glow
			extra.visible = glow > 0.0
		cta.position = Vector2(16, CTA_TOP)
		cta.size = Vector2(w - 32, CTA_HEIGHT)
		cta.set_lit(lit, glow)
		queue_redraw()

	func _draw() -> void:
		var fill := (Color("0d222a") if primary else S.CARD).lerp(Color("123540"), glow)
		var mode := get_draw_mode()
		if mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED:
			fill = Color("0b1f24")
		var edge := (Color(S.ACCENT, 0.7) if primary else S.CARD_EDGE).lerp(S.ACCENT, glow)
		var box := S.box(Color(fill, 0.95), edge)
		box.shadow_color = Color(S.ACCENT, (0.12 if primary else 0.0) + 0.16 * glow)
		box.shadow_size = int(round((6.0 if primary else 0.0) + 4.0 * glow))
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(0, 10, 3, size.y - 20), S.ACCENT if primary else S.SILVER.lerp(S.ACCENT, glow))
		var inset := Rect2(16, 16, size.x - 32, ART_RECT_HEIGHT)
		draw_rect(inset, S.INSET)
		draw_rect(inset, Color("1a2830"), false, 1.0)
		var mark := Color(S.SILVER, 0.25 + 0.35 * glow)
		var p := inset.grow(-8.0)
		for corner in [[p.position, Vector2(1, 1)], [Vector2(p.end.x, p.position.y), Vector2(-1, 1)], [Vector2(p.position.x, p.end.y), Vector2(1, -1)], [p.end, Vector2(-1, -1)]]:
			var at: Vector2 = corner[0]
			var d: Vector2 = corner[1]
			draw_rect(Rect2(Vector2(at.x if d.x > 0 else at.x - 12, at.y if d.y > 0 else at.y - 2), Vector2(12, 2)), mark)
			draw_rect(Rect2(Vector2(at.x if d.x > 0 else at.x - 2, at.y if d.y > 0 else at.y - 12), Vector2(2, 12)), mark)

var new_card: Card
var edit_card: Card
## 選ばれているカード（0 = 新しく作る、1 = 編集、NONE = どちらも選ばれていない）。
var selected := NONE
## 0.5 = 同じ幅、1.0 = 新しく作るが広い、0.0 = 編集が広い。
var amount := 0.5
var _from := 0.5
var _to := 0.5
var _t := 1.0
## 最後に分かっているマウスの位置（画面の座標）。まだ分からなければ領域の外。
var _pointer := OUTSIDE
var _count_caption: Label
var _count_value: Label
var _count_suffix: Label
var _count_empty: Label
var _status_chips: Control

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = AREA_SIZE

func _ready() -> void:
	set_process(false)
	new_card = Card.new()
	new_card.name = "NewBossButton"
	add_child(new_card)
	new_card.setup(true, tr("新しいボス戦を作る"), tr("SIMPLE か HARDCORE を選んで、\n最初から作ります。"), Art.NewBattleArt.new(), tr("作成を始める"))
	S.label(new_card, tr("作り方は次の画面で選びます"), Rect2(32, 318, 340, 22), 13, S.MUTED, "ModeNoteLabel")
	var simple_tag := S.mode_tag(new_card, RBMCreatorDraft.CREATOR_MODE_SIMPLE, Vector2(32, 346))
	simple_tag.name = "ModeTagSimple"
	S.mode_tag(new_card, RBMCreatorDraft.CREATOR_MODE_ADVANCED, Vector2(32 + simple_tag.get_combined_minimum_size().x + 8, 346)).name = "ModeTagHardcore"

	edit_card = Card.new()
	edit_card.name = "EditSavedBossButton"
	add_child(edit_card)
	edit_card.setup(false, tr("保存したボス戦を編集"), tr("保存したボス戦を選んで、\n続きを作ったり直したりします。"), Art.SavedBattlesArt.new(), tr("一覧を開く"))
	_count_caption = S.label(edit_card, tr("保存済み"), Rect2(32, 316, 80, 30), 14, S.MUTED, "SavedCountCaption")
	_count_value = S.label(edit_card, "0", Rect2(32, 312, 60, 36), 22, S.TEXT, "SavedCountValue")
	M.number_font(_count_value)
	_count_suffix = S.label(edit_card, "", Rect2(32, 316, 320, 30), 14, S.MUTED, "SavedCountSuffix")
	_count_empty = S.label(edit_card, tr("保存したボス戦はまだありません"), Rect2(32, 316, 340, 30), 14, S.MUTED, "SavedEmptyLabel")
	_status_chips = Control.new()
	_status_chips.name = "SavedStatusChips"
	_status_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_chips.position = Vector2(32, 352)
	edit_card.add_child(_status_chips)
	edit_card.extra = _status_chips
	set_counts({})

	for i in range(2):
		var card: Card = [new_card, edit_card][i]
		card.focus_entered.connect(select.bind(i))
		card.focus_exited.connect(_on_card_focus_exited, CONNECT_DEFERRED)
	visibility_changed.connect(_on_visibility_changed)
	set_process_input(is_visible_in_tree())
	_apply()

## 保存件数と内訳（total / draft / playable / clear_checked / published）。0件の時は「まだありません」。
func set_counts(counts: Dictionary) -> void:
	var total := int(counts.get("total", 0))
	var empty := total == 0
	_count_empty.visible = empty
	for node in [_count_caption, _count_value, _count_suffix]:
		node.visible = not empty
	M.fit_width(_count_caption)
	_count_value.text = str(total)
	_count_value.position.x = _count_caption.position.x + _count_caption.size.x + 8
	M.fit_width(_count_value)
	_count_suffix.text = tr("件　（うち下書き %d件）") % int(counts.get("draft", 0))
	_count_suffix.position.x = _count_value.position.x + _count_value.size.x + 4
	for child in _status_chips.get_children():
		_status_chips.remove_child(child)
		child.queue_free()
	if empty:
		return
	var x := 0.0
	var chips := [
		[tr("✓ クリアチェック済み %d") % int(counts.get("clear_checked", 0)), S.EMPHASIS, "ClearCheckedChip"],
		[tr("挑戦可能 %d") % int(counts.get("playable", 0)), S.SILVER, "PlayableChip"],
		[tr("公開中 %d") % int(counts.get("published", 0)), S.EMPHASIS, "PublishedChip"],
	]
	for chip in chips:
		var t := M.tag(_status_chips, chip[0], Vector2(x, 0), chip[1], Color("2a3a44"), Color(S.INSET, 0.9), false, chip[2])
		x += t.get_combined_minimum_size().x + 8

## index のカードを選ぶ（NONE で選択なし）。幅は DURATION 秒かけて変わる。instant なら即座に。
func select(index: int, instant: bool = false) -> void:
	var target := 0.5 if index == NONE else (1.0 if index == 0 else 0.0)
	selected = index
	if instant:
		amount = target
		_from = target
		_to = target
		_t = 1.0
		set_process(false)
		_apply()
		return
	if is_equal_approx(target, _to) and (_t < 1.0 or is_equal_approx(amount, target)):
		return
	_from = amount
	_to = target
	_t = 0.0
	set_process(true)

func _process(delta: float) -> void:
	_t = minf(1.0, _t + delta / DURATION)
	amount = lerpf(_from, _to, 1.0 - pow(1.0 - _t, 3.0))
	_apply()
	if _t >= 1.0:
		set_process(false)

func _apply() -> void:
	if new_card == null:
		return
	var new_width := roundf(lerpf(NARROW, WIDE, amount))
	var edit_width := AREA_SIZE.x - GAP - new_width
	var new_glow := clampf((amount - 0.5) * 2.0, 0.0, 1.0)
	var edit_glow := clampf((0.5 - amount) * 2.0, 0.0, 1.0)
	# 主な行動の帯はふだんから光らせ、編集が選ばれた時だけ消す。
	new_card.set_layout(Rect2(0, 0, new_width, AREA_SIZE.y), new_glow, 1.0 - edit_glow)
	edit_card.set_layout(Rect2(new_width + GAP, 0, edit_width, AREA_SIZE.y), edit_glow, edit_glow)

func _focused_card() -> int:
	if new_card.has_focus():
		return 0
	if edit_card.has_focus():
		return 1
	return NONE

func _card_at(at: Vector2) -> int:
	if new_card.get_global_rect().has_point(at):
		return 0
	if edit_card.get_global_rect().has_point(at):
		return 1
	return NONE

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_moved((event as InputEventMouseMotion).position)

## マウスが動いた（画面の座標）。カードの上ならそのカードを選び、カードの間の隙間ではそのまま、
## 2枚の外へ出たら、キーボードで選んでいるカードがあればそのカード、無ければ選択なしに戻す。
## （ボタンの mouse_entered/exited は、カードの上にいる間は親のこの領域へ届かないため、位置で決める。）
func pointer_moved(at: Vector2) -> void:
	_pointer = at
	var hit := _card_at(at)
	if hit != NONE:
		select(hit)
	elif not get_global_rect().has_point(at):
		select(_focused_card())

func _on_card_focus_exited() -> void:
	if _focused_card() != NONE:
		return
	var hit := _card_at(_pointer)
	if hit != NONE:
		select(hit)
	elif not get_global_rect().has_point(_pointer):
		select(NONE)

## 表示されている間だけマウスの動きを見る。画面を離れて戻ってきた時は、どちらも選ばれていない状態から始める。
func _on_visibility_changed() -> void:
	set_process_input(is_visible_in_tree())
	if not is_visible_in_tree():
		_pointer = OUTSIDE
		select(NONE, true)
