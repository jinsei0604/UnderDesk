class_name RBMCreatorStep5Party
extends Control

## STEP4「攻略パーティ」。
##
## 2026-10-17 UI 刷新（ユーザーが案C「RPG風の編成」を採用。プレビュー prototypes/step4_party_2026-10-17）:
##   上   = 戦場の床に並ぶパーティ（最大 MAX_PARTY_SIZE=4 の枠。空きは影の枠）。並んだキャラクターを押すと選べる。
##   中   = 5人の仲間の札（ドット絵・名前・役割。編成中は ✓、CUSTOM の印）。押すと下の人物の札が変わる。
##   下   = 人物の札（名前・属性・役割・説明・能力のバー・得意技・ほかの技）と「編成に入れる／編成から外す」
##          「ステータス編集」。
##   「ステータス編集」で、選んだキャラクターの[使用可能スキル]／[性能調整]を重ねて開く（中身・操作は以前と同じ:
##   使用可能スキルは「編集→決定／キャンセル」、性能調整は SIMPLE は表示だけ・HARDCORE は値の編集）。
##   「全員を標準に戻す」（HARDCORE）は舞台の見出しの右。
## 編成の仕様（候補5人から1〜4人、重複なし）・保存の形・draft の API は変えていない。
## 役割・説明・技の短い説明は RBMPartyRosterKit（マスターデータと戦闘の処理から決めた）。
##
## 以前の作り（2026-09-05、カード列＋「＋キャラクターを追加」の候補一覧＋選択キャラクター設定）から引き継いだもの:
##   §13/§17 使用可能スキル（旧 RBMCreatorStep6PartySkills から移設したロジック）、§15 CUSTOM の印
##   （draft.is_ally_customized()）、§16 全員を標準に戻す（draft.reset_all_ally_overrides()、ADVANCED 専用）。

const CONTENT_SIDE_MARGIN_PX := 40.0
const CONTENT_TOP_MARGIN_PX := 24.0
## 中身が下部の「戻る/次へ/作成を終了」の帯へ貼り付かないための余白。
const CONTENT_BOTTOM_MARGIN_PX := 12.0
## ステータス編集のタブ領域の最小の高さ。中身が長ければ内部で縦スクロールする。
const TAB_SCROLL_MIN_HEIGHT_PX := 160.0
## タブ領域のホイール1刻み（Godot の既定では約20pxしか動かず、長い性能調整を送りにくいため）。
const TAB_SCROLL_WHEEL_STEP_PX := 40.0
## 中央の欄の大きさがまだ決まっていない時（画面に出す前）に使う大きさ（1280×720 の本番の欄と同じ）。
const FALLBACK_AREA := Vector2(644, 503)
const GAP := 8.0
const BACKGROUND := "res://assets_bossmaker/art/battle_courtyard_night.png"

const TAB_SKILLS := "skills"
const TAB_PERFORMANCE := "performance"

const K := preload("res://src/bossmaker/creator/rbm_party_roster_kit.gd")
const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")

## 値は表示用文字列——キー(effect_id/target_id)はスキル定義の内部IDで
## あり翻訳対象ではない。呼び出し側で.get()の結果へtr()を適用する。
const SKILL_EFFECT_LABELS := {
	"damage": "攻撃",
	"heal": "HP回復",
	"sp_recover_single_no_self": "SP回復",
	"sp_recover_all_no_self": "全体SP回復",
	"buff_atk_self": "ATK自己強化",
	"buff_next_attack": "次回攻撃強化",
	"counter_stance": "カウンター",
	"guard_redirect": "かばう",
	"guard_boost": "防御強化",
	"party_damage_reduction": "被ダメージ軽減",
}

const SKILL_TARGET_LABELS := {
	"boss": "ボス",
	"ally_chosen": "味方単体",
	"ally_chosen_no_self": "自分以外の味方単体",
	"ally_all": "味方全体",
}

var draft: RBMCreatorDraft
var main: Node

## 編成の画面（舞台・仲間の札・人物の札）。中身は refresh() のたびに作り直す。
var _canvas: Control
var _count_label: Label
var _reset_all_button: Button
## 人物の札の「編成に入れる」（見ているキャラクターが編成に入っていない時だけある）。
var _add_button: Button
var _status_button: Button

## 見ているキャラクター（5人のだれでも）。ステータス編集の対象は、この人が編成に入っている時だけ。
var _selected_character_id: String = ""
var _selected_tab: String = TAB_SKILLS
## ステータス編集を開いているか。
var _status_sheet_open := false

## ステータス編集（重ねて開く）。中のタブ・技の一覧・操作ボタンの作りは以前のまま。
var _sheet_layer: Control
var _selected_settings_panel: VBoxContainer
var _selected_empty_label: Label
var _selected_header_label: Label
var _tab_row: HBoxContainer
var _skills_tab_button: Button
var _performance_tab_button: Button
var _tab_content: VBoxContainer
var _tab_scroll: ScrollContainer
## 使用可能スキルタブの操作ボタン行(編集 / 決定・キャンセル)。一覧のスクロールに入れず、タブ領域のすぐ下に常に出す。
var _skills_actions_bar: MarginContainer
var _skills_actions: HBoxContainer

## §13相当（旧RBMCreatorStep6PartySkillsから移設）——選択中の1人分のみ保持する。
var _skills_editing := false
var _staged_allowed: Dictionary = {}  # skill_id -> bool

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	_canvas = Control.new()
	_canvas.name = "PartyStepCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.offset_left = CONTENT_SIDE_MARGIN_PX
	_canvas.offset_right = -CONTENT_SIDE_MARGIN_PX
	_canvas.offset_top = CONTENT_TOP_MARGIN_PX
	_canvas.offset_bottom = -CONTENT_BOTTOM_MARGIN_PX
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 紺＋水色の新しい見た目（RBMChallengeListStyle）。作成画面の共通の再配色（RBMWorldUi.walk）を受けない。
	# ステータス編集の中身（以前からの部品）は今までどおり共通の見た目にする。
	_canvas.set_meta("world_skip", true)
	add_child(_canvas)
	# 中央の欄の大きさが決まった・変わった時に作り直す（ウィンドウの大きさを変えた時など）。
	_canvas.resized.connect(func(): _rebuild_canvas())
	# この画面は別のボスを作る・開く時も使い回す（draft の中身だけが入れ替わる）。
	visibility_changed.connect(_on_visibility_changed)
	_build_status_sheet()
	refresh()

## STEP4 を開いた時（ほかの STEP・別のボスから来た時）は、重ねたステータス編集を閉じ、
## 編成に入っていない人を見ていれば編成の1人目を見せる。編成の中で選んでいた人はそのまま。
## 表示は直後の refresh()（RBMCreatorMain._refresh()）で作り直す。
func _on_visibility_changed() -> void:
	if not visible or draft == null:
		return
	_status_sheet_open = false
	_skills_editing = false
	_staged_allowed.clear()
	if not draft.party_character_ids.is_empty() and not draft.party_character_ids.has(_selected_character_id):
		_selected_character_id = draft.party_character_ids[0]

# ---------------------------------------------------------------------------
# ステータス編集（重ねて開く）
# ---------------------------------------------------------------------------

func _build_status_sheet() -> void:
	_sheet_layer = Control.new()
	_sheet_layer.name = "StatusEditLayer"
	_sheet_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet_layer.offset_left = CONTENT_SIDE_MARGIN_PX
	_sheet_layer.offset_right = -CONTENT_SIDE_MARGIN_PX
	_sheet_layer.offset_top = CONTENT_TOP_MARGIN_PX
	_sheet_layer.offset_bottom = -CONTENT_BOTTOM_MARGIN_PX
	_sheet_layer.visible = false
	add_child(_sheet_layer)
	# 後ろの編成の画面を暗くし、押せないようにする。
	var dim := ColorRect.new()
	dim.name = "StatusEditDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_layer.add_child(dim)
	var sheet := PanelContainer.new()
	sheet.name = "StatusEditSheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 12
	sheet.offset_right = -12
	sheet.offset_top = 8
	sheet.offset_bottom = -8
	var style := S.box(Color("0a1218"), S.ACCENT_SOFT)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	sheet.add_theme_stylebox_override("panel", style)
	_sheet_layer.add_child(sheet)

	_selected_settings_panel = VBoxContainer.new()
	_selected_settings_panel.name = "SelectedCharacterSettingsPanel"
	_selected_settings_panel.add_theme_constant_override("separation", 8)
	sheet.add_child(_selected_settings_panel)

	var head := HBoxContainer.new()
	head.name = "StatusEditHeader"
	_selected_settings_panel.add_child(head)
	_selected_header_label = Label.new()
	_selected_header_label.name = "SelectedCharacterHeaderLabel"
	_selected_header_label.theme_type_variation = RBMCreatorUiKit.VARIATION_SECTION_LABEL
	_selected_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_header_label.clip_text = true
	head.add_child(_selected_header_label)
	var close := Button.new()
	close.name = "StatusEditCloseButton"
	close.text = tr("閉じる")
	close.add_theme_font_size_override("font_size", 14)
	S.button_style(close)
	close.pressed.connect(close_status_sheet)
	head.add_child(close)

	_selected_empty_label = Label.new()
	_selected_empty_label.name = "SelectedCharacterEmptyLabel"
	_selected_empty_label.text = tr("編成に入れると、ステータスを編集できます")
	_selected_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_settings_panel.add_child(_selected_empty_label)

	_tab_row = HBoxContainer.new()
	_tab_row.name = "SelectedCharacterTabRow"
	_selected_settings_panel.add_child(_tab_row)
	_skills_tab_button = Button.new()
	_skills_tab_button.name = "SkillsTabButton"
	_skills_tab_button.text = tr("使用可能スキル")
	_skills_tab_button.toggle_mode = true
	_skills_tab_button.pressed.connect(_on_tab_selected.bind(TAB_SKILLS))
	_tab_row.add_child(_skills_tab_button)
	_performance_tab_button = Button.new()
	_performance_tab_button.name = "PerformanceTabButton"
	_performance_tab_button.text = tr("性能調整")
	_performance_tab_button.toggle_mode = true
	_performance_tab_button.pressed.connect(_on_tab_selected.bind(TAB_PERFORMANCE))
	_tab_row.add_child(_performance_tab_button)

	var tab_scroll := ScrollContainer.new()
	tab_scroll.name = "SelectedCharacterTabScroll"
	tab_scroll.custom_minimum_size = Vector2(0.0, TAB_SCROLL_MIN_HEIGHT_PX)
	tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_scroll.gui_input.connect(_on_tab_scroll_gui_input.bind(tab_scroll))
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	S.style_scrollbar(tab_scroll.get_v_scroll_bar())
	_selected_settings_panel.add_child(tab_scroll)
	_tab_scroll = tab_scroll
	_tab_content = VBoxContainer.new()
	_tab_content.name = "SelectedCharacterTabContent"
	_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.add_child(_tab_content)

	_skills_actions_bar = MarginContainer.new()
	_skills_actions_bar.name = "SkillsTabActionsBar"
	_skills_actions_bar.visible = false
	_selected_settings_panel.add_child(_skills_actions_bar)
	_skills_actions = HBoxContainer.new()
	_skills_actions.name = "SkillsTabActions"
	_skills_actions_bar.add_child(_skills_actions)

## タブ領域のホイールをTAB_SCROLL_WHEEL_STEP_PXずつ動かす。端に着いて動かない時は受け取らない。
func _on_tab_scroll_gui_input(event: InputEvent, tab_scroll: ScrollContainer) -> void:
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	var direction := 0.0
	if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1.0
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1.0
	else:
		return
	var factor := wheel.factor if wheel.factor > 0.0 else 1.0
	var bar := tab_scroll.get_v_scroll_bar()
	var before := tab_scroll.scroll_vertical
	tab_scroll.scroll_vertical = int(clamp(before + direction * TAB_SCROLL_WHEEL_STEP_PX * factor, 0.0, max(0.0, bar.max_value - bar.page)))
	if tab_scroll.scroll_vertical != before:
		tab_scroll.accept_event()

## 「ステータス編集」: 見ているキャラクター（編成に入っている人）の使用可能スキル・性能調整を開く。
func open_status_sheet() -> void:
	if not draft.party_character_ids.has(_selected_character_id):
		return
	_status_sheet_open = true
	refresh()

func close_status_sheet() -> void:
	_status_sheet_open = false
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

func is_status_sheet_open() -> bool:
	return _sheet_layer.visible

# ---------------------------------------------------------------------------
# パーティ追加/削除（既存API）
# ---------------------------------------------------------------------------

## 既存プログラム的API（テスト/呼び出し元向け）——「編成に入れる」「編成から外す」も同じ経路。
## add_party_character()/remove_party_character() 自体の重複禁止・上限判定は無改修。
func toggle_character(character_id: String) -> void:
	if draft.party_character_ids.has(character_id):
		draft.remove_party_character(character_id)
	else:
		draft.add_party_character(character_id)
	refresh()
	main.on_party_changed()

## 人物の札の「編成に入れる」（見ているキャラクターを入れる）。4人そろっていれば何もしない。
func _on_add_pressed() -> void:
	if draft.party_character_ids.has(_selected_character_id) or draft.party_character_ids.size() >= RBMDefinitionLoader.MAX_PARTY_SIZE:
		return
	toggle_character(_selected_character_id)

func _on_remove_pressed(character_id: String) -> void:
	toggle_character(character_id)

# ---------------------------------------------------------------------------
# キャラクターを選ぶ（仲間の札・並んだキャラクター）
# ---------------------------------------------------------------------------

func select_character(character_id: String) -> void:
	if _selected_character_id == character_id:
		return
	_selected_character_id = character_id
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

func selected_character_id() -> String:
	return _selected_character_id

func _on_reset_all_overrides_pressed() -> void:
	draft.reset_all_ally_overrides()
	refresh()

func _on_tab_selected(tab: String) -> void:
	_selected_tab = tab
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

# ---------------------------------------------------------------------------
# refresh — 編成の画面とステータス編集
# ---------------------------------------------------------------------------

func refresh() -> void:
	if not K.IDS.has(_selected_character_id):
		_selected_character_id = draft.party_character_ids[0] if not draft.party_character_ids.is_empty() else str(K.IDS[0])
	# 編成から外れた人のステータス編集は閉じる。
	if not draft.party_character_ids.has(_selected_character_id):
		_status_sheet_open = false
		_skills_editing = false
		_staged_allowed.clear()
	_rebuild_canvas()
	_refresh_selected_settings()

func _area() -> Vector2:
	return _canvas.size if _canvas.size.x > 1.0 and _canvas.size.y > 1.0 else FALLBACK_AREA

func _rebuild_canvas() -> void:
	if _canvas == null or draft == null:
		return
	# queue_free()だけだと同じフレームで同じ名前の新しい部品が自動で改名されるため、先にツリーから外す。
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	_add_button = null
	_status_button = null
	var area := _area()
	var stage_h := clampf(area.y * 0.38, 170.0, 196.0)
	var bench_h := 92.0
	var sheet_y := stage_h + GAP + bench_h + GAP
	_build_stage(Rect2(0, 0, area.x, stage_h))
	_build_bench(Rect2(0, stage_h + GAP, area.x, bench_h))
	_build_character_sheet(Rect2(0, sheet_y, area.x, area.y - sheet_y))

## 戦場の床に並ぶパーティ（4つの枠）。
func _build_stage(rect: Rect2) -> void:
	var stage := Control.new()
	stage.name = "PartyFormationStage"
	stage.position = rect.position
	stage.size = rect.size
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(stage)
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = load(BACKGROUND)
	bg.size = rect.size
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.modulate = Color(0.55, 0.62, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bg)
	S.gradient_rect(stage, Rect2(0, 0, rect.size.x, rect.size.y), Color(S.BG, 0.55), Color(S.BG, 0.15))
	# 見出し（絵の上なので暗い帯を敷く）
	K.panel(stage, Rect2(0, 0, rect.size.x, 34), Color(S.BG, 0.82), Color(0, 0, 0, 0))
	K.label(stage, tr("パーティ編成"), Rect2(14, 3, 220, 28), 17, S.TEXT, "PartyStageTitle")
	_count_label = K.label(stage, tr("%d / %d人") % [draft.party_character_ids.size(), RBMDefinitionLoader.MAX_PARTY_SIZE], Rect2(rect.size.x - 120, 3, 106, 28), 18, S.TEXT, "PartyCountLabel")
	_count_label.add_theme_font_override("font", S.number_font())
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# §16 全員を標準に戻す（HARDCORE のみ）
	_reset_all_button = K.button(stage, tr("全員を標準に戻す"), Rect2(0, 3, 0, 28), false, "ResetAllAllyOverridesButton", _on_reset_all_overrides_pressed, 13)
	_reset_all_button.position.x = rect.size.x - 128 - _reset_all_button.size.x
	_reset_all_button.visible = draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED
	S.rect(stage, Rect2(0, 34, rect.size.x, 1), S.PANEL_EDGE)
	var slot_w := rect.size.x / float(RBMDefinitionLoader.MAX_PARTY_SIZE)
	var floor_y := rect.size.y - 42
	for i in RBMDefinitionLoader.MAX_PARTY_SIZE:
		var sx := i * slot_w
		if i < draft.party_character_ids.size():
			var id: String = draft.party_character_ids[i]
			var focused := id == _selected_character_id
			var hit := K.card_button(stage, Rect2(sx + 8, 42, slot_w - 16, rect.size.y - 48), focused, "FormationSlot_%d" % i, select_character.bind(id))
			hit.self_modulate = Color(1, 1, 1, 0.55 if focused else 0.0)
			RBMMenuUi.accessible_name(hit, K.name_of(id))
			var ring := K.Ring.new()
			ring.color = K.attribute_color(str(draft.master_character_def(id).get("attribute", "NEUTRAL")))
			ring.position = Vector2(sx + slot_w * 0.5 - 44, floor_y - 10)
			ring.size = Vector2(88, 20)
			stage.add_child(ring)
			K.sprite(stage, id, Rect2(sx + slot_w * 0.5 - 60, floor_y - 100, 120, 100), false, "FormationSprite_%d" % i)
			var plate := K.panel(stage, Rect2(sx + 10, floor_y + 6, slot_w - 20, 32), Color(S.BG, 0.88), Color(K.role_color(id), 0.7), "FormationPlate_%d" % i)
			var icon := K.RoleIcon.new()
			icon.kind = K.role_kind(id)
			icon.color = K.role_color(id)
			icon.position = Vector2(8, 9)
			icon.size = Vector2(14, 14)
			plate.add_child(icon)
			K.label(plate, K.name_of(id), Rect2(28, 3, slot_w - 56, 26), 14, S.TEXT)
		else:
			var empty := K.panel(stage, Rect2(sx + 18, 52, slot_w - 36, rect.size.y - 62), Color(S.BG, 0.35), Color(S.SILVER, 0.28), "EmptySlot_%d" % i)
			var t := K.label(empty, tr("空き"), Rect2(0, 0, empty.size.x, empty.size.y), 14, S.MUTED)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## 5人の仲間の札（押すと下の人物の札が変わる）。縦に「絵・名前・役割」。編成中は ✓、調整済みは CUSTOM。
func _build_bench(rect: Rect2) -> void:
	var tile_w := (rect.size.x - GAP * 4) / 5.0
	for i in K.IDS.size():
		var id: String = K.IDS[i]
		var focused := id == _selected_character_id
		var joined := draft.party_character_ids.has(id)
		var r := Rect2(rect.position.x + i * (tile_w + GAP), rect.position.y, tile_w, rect.size.y)
		var b := K.card_button(_canvas, r, focused, "SelectCharacterButton_%s" % id, select_character.bind(id))
		RBMMenuUi.accessible_name(b, K.name_of(id))
		K.sprite(b, id, Rect2(tile_w * 0.5 - 26, 4, 52, 44), not joined and not focused, "Sprite")
		var name_label := K.label(b, K.name_of(id), Rect2(4, 49, tile_w - 8, 20), 14, S.TEXT, "Name")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var role := K.label(b, K.role_text(id), Rect2(4, 69, tile_w - 8, 18), 12, K.role_color(id), "Role")
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var icon := K.RoleIcon.new()
		icon.kind = K.role_kind(id)
		icon.color = K.role_color(id)
		icon.size = Vector2(11, 11)
		var role_w := role.get_theme_font("font").get_string_size(role.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		icon.position = Vector2(tile_w * 0.5 - role_w * 0.5 - 15, 72)
		b.add_child(icon)
		if joined:
			var tag := K.label(b, "✓", Rect2(tile_w - 24, 4, 20, 20), 15, S.ACCENT, "InPartyTag")
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# §15: 性能・使用可能スキルのどちらかを調整している時だけ
		if draft.is_ally_customized(id):
			var custom := K.label(b, "CUSTOM", Rect2(4, 4, 60, 18), 12, S.GOLD, "CustomBadgeLabel_%s" % id)
			custom.add_theme_font_override("font", S.number_font())

## 人物の札: 名前・属性・役割・説明・能力（左）、得意技・ほかの技・操作（右）。
func _build_character_sheet(rect: Rect2) -> void:
	var id := _selected_character_id
	var def := draft.effective_character_def(id)
	var p := K.panel(_canvas, rect, S.PANEL, S.PANEL_EDGE, "CharacterSheet")
	S.rect(p, Rect2(0, 0, 3, rect.size.y), K.role_color(id))
	var w := rect.size.x
	var left_w := w * 0.5
	K.label(p, K.name_of(id), Rect2(16, 8, left_w - 24, 28), 19, S.TEXT, "SheetName")
	var x := 16.0
	x += K.attribute_chip(p, str(def.get("attribute", "NEUTRAL")), Vector2(x, 42)) + 6
	K.role_chip(p, id, Vector2(x, 42), 14, true, left_w - 8 - x)
	K.wrap_label(p, K.description(id), Rect2(16, 70, left_w - 28, 58), 14, S.MUTED, "SheetDescription")
	for i in K.STAT_KEYS.size():
		K.stat_bar(p, def, K.STAT_KEYS[i], Rect2(16 + (i % 2) * (left_w - 28) * 0.5, 134 + (i / 2) * 20, (left_w - 28) * 0.5 - 10, 18), "SheetStat_%s" % K.STAT_KEYS[i])
	# 右: 得意技とほかの技（使わない設定の技には印）
	var rx := left_w + 8
	var rw := w - rx - 16
	K.label(p, tr("得意技"), Rect2(rx, 10, rw, 20), 13, S.GOLD)
	var sig := K.skill_by_id(def, str(K.SIGNATURE.get(id, "")))
	var sig_panel := K.panel(p, Rect2(rx, 32, rw, 50), Color("15130d", 0.9), S.GOLD_EDGE, "SignatureSkill")
	K.label(sig_panel, _skill_label(id, sig), Rect2(10, 3, rw - 70, 24), 15, S.TEXT, "SignatureName")
	var sp := K.label(sig_panel, K.sp_text(sig), Rect2(rw - 62, 3, 52, 24), 12, S.GOLD)
	sp.add_theme_font_override("font", S.number_font())
	sp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	K.label(sig_panel, K.skill_effect(sig), Rect2(10, 25, rw - 20, 22), 13, S.MUTED, "SignatureEffect")
	var others: Array[String] = []
	for skill in def.get("skills", []):
		if skill is Dictionary and str((skill as Dictionary).get("id", "")) != str(K.SIGNATURE.get(id, "")):
			others.append(_skill_label(id, skill))
	K.wrap_label(p, tr("ほかの技：%s") % tr("・").join(others), Rect2(rx, 88, rw, 40), 13, S.MUTED, "OtherSkills")
	# 操作: 編成に入れる／外す（左）、ステータス編集（右）
	var by := rect.size.y - 44
	var joined := draft.party_character_ids.has(id)
	var main_button: Button
	if joined:
		main_button = K.button(p, tr("編成から外す"), Rect2(rx, by, rw * 0.5, 36), false, "RemoveCharacterButton_%s" % id, _on_remove_pressed.bind(id), 14)
	else:
		var full := draft.party_character_ids.size() >= RBMDefinitionLoader.MAX_PARTY_SIZE
		main_button = K.button(p, tr("4人そろっています") if full else tr("編成に入れる"), Rect2(rx, by, rw * 0.5, 36), true, "AddCharacterButton", _on_add_pressed, 15)
		main_button.disabled = full
		_add_button = main_button
	var sx := rx + main_button.size.x + 8
	_status_button = K.button(p, tr("ステータス編集"), Rect2(sx, by, w - 16 - sx, 36), joined, "StatusEditButton", open_status_sheet, 14)
	_status_button.disabled = not joined
	if not joined:
		_status_button.tooltip_text = tr("編成に入れると、ステータスを編集できます")

## 技の名前（編成の人で、使わない設定にした技には印を添える。使える技の設定は編成の人にだけある）。
func _skill_label(character_id: String, skill: Dictionary) -> String:
	var text := K.skill_name(skill)
	if draft.party_character_ids.has(character_id) and not draft.is_ally_skill_allowed(character_id, str(skill.get("id", ""))):
		text += tr("（使わない）")
	return text

# ---------------------------------------------------------------------------
# ステータス編集の中身（§12〜§17。タブ・使用可能スキル・性能調整の作りは以前のまま）
# ---------------------------------------------------------------------------

func _refresh_selected_settings() -> void:
	var has_selection := draft.party_character_ids.has(_selected_character_id)
	_sheet_layer.visible = _status_sheet_open and has_selection
	_selected_empty_label.visible = not has_selection
	_selected_header_label.visible = has_selection
	_tab_row.visible = has_selection
	for child in _skills_actions.get_children():
		_skills_actions.remove_child(child)
		child.queue_free()
	_skills_actions_bar.visible = false
	_tab_scroll.custom_minimum_size.y = TAB_SCROLL_MIN_HEIGHT_PX
	if not has_selection:
		for child in _tab_content.get_children():
			_tab_content.remove_child(child)
			child.queue_free()
		return

	var master := draft.master_character_def(_selected_character_id)
	_selected_header_label.text = "%s　%s" % [tr("ステータス編集"), K.name_of(_selected_character_id)]
	_skills_tab_button.button_pressed = (_selected_tab == TAB_SKILLS)
	_performance_tab_button.button_pressed = (_selected_tab == TAB_PERFORMANCE)

	for child in _tab_content.get_children():
		_tab_content.remove_child(child)
		child.queue_free()
	if _selected_tab == TAB_SKILLS:
		_build_skills_tab(_selected_character_id, master)
		_skills_actions_bar.visible = true
		_tab_scroll.custom_minimum_size.y = max(0.0, TAB_SCROLL_MIN_HEIGHT_PX - CONTENT_BOTTOM_MARGIN_PX - _skills_actions.get_combined_minimum_size().y)
	else:
		_build_performance_tab(_selected_character_id)

# --- 使用可能スキルタブ（旧RBMCreatorStep6PartySkillsから移設） ---------

func _build_skills_tab(character_id: String, master: Dictionary) -> void:
	if _skills_editing:
		_build_skills_edit_panel(character_id, master)
	else:
		_build_skills_normal_panel(character_id, master)

func _build_skills_normal_panel(character_id: String, master: Dictionary) -> void:
	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		var row := HBoxContainer.new()
		_tab_content.add_child(row)
		var label := Label.new()
		label.name = "SkillStatusLabel_%s_%s" % [character_id, skill_id]
		var allowed := draft.is_ally_skill_allowed(character_id, skill_id)
		label.text = "%s   %s" % [tr(str(skill.get("display_name", skill_id))), tr("使用可") if allowed else tr("使用不可")]
		row.add_child(label)

	var edit_button := Button.new()
	edit_button.name = "EditPartySkillsButton_%s" % character_id
	edit_button.text = tr("編集")
	edit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_button.pressed.connect(_on_edit_skills_pressed.bind(character_id))
	_skills_actions.add_child(edit_button)

func _on_edit_skills_pressed(character_id: String) -> void:
	_skills_editing = true
	var master := draft.master_character_def(character_id)
	var snapshot := {}
	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		snapshot[skill_id] = draft.is_ally_skill_allowed(character_id, skill_id)
	_staged_allowed = snapshot
	refresh()

func _build_skills_edit_panel(character_id: String, master: Dictionary) -> void:
	var bulk_row := HBoxContainer.new()
	_tab_content.add_child(bulk_row)
	var on_button := Button.new()
	on_button.name = "AllOnButton_%s" % character_id
	on_button.text = tr("すべてON")
	on_button.pressed.connect(_on_staged_all_pressed.bind(true))
	bulk_row.add_child(on_button)
	var off_button := Button.new()
	off_button.name = "AllOffButton_%s" % character_id
	off_button.text = tr("すべてOFF")
	off_button.pressed.connect(_on_staged_all_pressed.bind(false))
	bulk_row.add_child(off_button)

	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		var row := HBoxContainer.new()
		_tab_content.add_child(row)
		var check := CheckButton.new()
		check.name = "SkillCheck_%s_%s" % [character_id, skill_id]
		check.button_pressed = bool(_staged_allowed.get(skill_id, draft.is_ally_skill_allowed(character_id, skill_id)))
		check.toggled.connect(func(pressed: bool): _on_staged_skill_toggled(skill_id, pressed))
		row.add_child(check)
		var label := Label.new()
		var effect_id := str(skill.get("effect", ""))
		var target_id := str(skill.get("target", ""))
		var target_text := tr(str(SKILL_TARGET_LABELS.get(target_id, target_id))) if not target_id.is_empty() else "-"
		label.text = tr("%s（%s、対象:%s、SP消費%s）") % [
			tr(str(skill.get("display_name", skill_id))), tr(str(SKILL_EFFECT_LABELS.get(effect_id, effect_id))),
			target_text, str(int(skill.get("sp_cost", 0))),
		]
		row.add_child(label)

	var confirm_button := Button.new()
	confirm_button.name = "ConfirmPartySkillsButton_%s" % character_id
	confirm_button.text = tr("決定")
	confirm_button.pressed.connect(_on_confirm_skills_pressed.bind(character_id))
	_skills_actions.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelPartySkillsButton_%s" % character_id
	cancel_button.text = tr("キャンセル")
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_cancel_skills_pressed)
	_skills_actions.add_child(cancel_button)

func _on_staged_skill_toggled(skill_id: String, pressed: bool) -> void:
	_staged_allowed[skill_id] = pressed

func _on_staged_all_pressed(allowed: bool) -> void:
	var master := draft.master_character_def(_selected_character_id)
	for skill in master.get("skills", []):
		_staged_allowed[str(skill.get("id", ""))] = allowed
	refresh()

func _on_confirm_skills_pressed(character_id: String) -> void:
	for skill_id in _staged_allowed.keys():
		draft.set_ally_skill_allowed(character_id, str(skill_id), bool(_staged_allowed[skill_id]))
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

func _on_cancel_skills_pressed() -> void:
	_skills_editing = false
	_staged_allowed.clear()
	refresh()

## 既存プログラム的API（テスト/呼び出し元向け）——実UIの「編集→決定」フロー
## とは独立して常に即座にドラフトへ反映する、既存の挙動をそのまま維持。
func set_skill_allowed(character_id: String, skill_id: String, allowed: bool) -> void:
	draft.set_ally_skill_allowed(character_id, skill_id, allowed)
	refresh()

func set_all_for_character(character_id: String, allowed: bool) -> void:
	draft.set_all_ally_skills_allowed(character_id, allowed)
	refresh()

# --- 性能調整タブ（旧_populate_character_info()から移設、無改修ロジック） ---

func _build_performance_tab(character_id: String) -> void:
	var master := draft.master_character_def(character_id)
	if master.is_empty():
		return
	var effective := draft.effective_character_def(character_id)
	if draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
		_build_stat_override_editor(character_id, effective)
	else:
		var stats_label := Label.new()
		stats_label.name = "CharacterInfoStatsLabel"
		stats_label.text = tr("HP：%d\nATK：%d\nSPD：%d") % [
			int(master.get("hp", 0)), int(master.get("atk", 0)), int(master.get("spd", 0)),
		]
		_tab_content.add_child(stats_label)
	var effective_by_id := {}
	for skill_variant in effective.get("skills", []):
		if skill_variant is Dictionary:
			effective_by_id[str((skill_variant as Dictionary).get("id", ""))] = skill_variant
	for skill_variant in master.get("skills", []):
		var master_skill: Dictionary = skill_variant
		var skill_id := str(master_skill.get("id", ""))
		_add_skill_performance_card(character_id, master_skill, effective_by_id.get(skill_id, master_skill))

func _add_skill_performance_card(character_id: String, skill: Dictionary, effective_skill: Dictionary) -> void:
	var skill_id := str(skill.get("id", ""))
	var card := PanelContainer.new()
	card.name = "CharacterSkillCard_%s" % skill_id
	_tab_content.add_child(card)
	var column := VBoxContainer.new()
	card.add_child(column)
	_add_info_label(column, "SkillNameLabel_%s" % skill_id, tr(str(skill.get("display_name", skill_id))))
	var effect := str(skill.get("effect", ""))
	_add_info_label(column, "SkillTypeLabel_%s" % skill_id, tr("種類：%s") % tr(str(SKILL_EFFECT_LABELS.get(effect, effect))))
	if skill.has("attribute"):
		var attribute_id := str(skill.get("attribute", ""))
		_add_info_label(column, "SkillAttributeLabel_%s" % skill_id, tr("属性：%s") % tr(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id))))
	if skill.has("target"):
		var target_id := str(skill.get("target", ""))
		_add_info_label(column, "SkillTargetLabel_%s" % skill_id, tr("対象：%s") % tr(str(SKILL_TARGET_LABELS.get(target_id, target_id))))
	_add_skill_effect_lines(column, draft.effective_character_def(character_id), effective_skill, effect, skill_id)
	if draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
		_add_skill_override_editor(column, character_id, skill, effective_skill)

func _build_stat_override_editor(character_id: String, effective: Dictionary) -> void:
	var caption := Label.new()
	caption.text = tr("ハードコア ステータス設定")
	_tab_content.add_child(caption)
	var labels := {"hp": "HP", "atk": "ATK", "spd": "SPD", "max_sp": "Max SP"}
	for field in RBMDefinitionLoader.ALLY_STAT_OVERRIDE_FIELDS:
		var row := HBoxContainer.new()
		row.name = "AllyStatOverrideRow_%s_%s" % [character_id, field]
		_tab_content.add_child(row)
		var value_label := Label.new()
		value_label.name = "AllyStatOverrideLabel_%s_%s" % [character_id, field]
		value_label.text = str(labels[field])
		row.add_child(value_label)
		var spin := SpinBox.new()
		spin.name = "AllyStatOverrideSpin_%s_%s" % [character_id, field]
		spin.min_value = 1.0
		spin.max_value = float(RBMDefinitionLoader.ALLY_OVERRIDE_INT_MAX)
		spin.step = 1.0
		spin.value = float(effective[field])
		spin.value_changed.connect(_on_stat_override_changed.bind(character_id, field))
		row.add_child(spin)
	var reset := Button.new()
	reset.name = "ResetAllyStatsButton_%s" % character_id
	reset.text = tr("キャラクターステータスを標準値へ戻す")
	reset.pressed.connect(_on_reset_character_stats_pressed.bind(character_id))
	_tab_content.add_child(reset)

func _add_skill_override_editor(parent: Control, character_id: String, master_skill: Dictionary, effective_skill: Dictionary) -> void:
	var skill_id := str(master_skill.get("id", ""))
	var labels := {
		"atk_multiplier": "倍率", "heal_amount": "回復量", "sp_amount": "SP回復量",
		"sp_cost": "SP消費", "buff_multiplier": "強化倍率", "duration_turns": "効果時間",
		"new_rate": "防御軽減率", "reduction_rate": "被ダメージ軽減率",
	}
	for field in RBMDefinitionLoader.ally_skill_override_fields(master_skill):
		var row := HBoxContainer.new()
		row.name = "AllySkillOverrideRow_%s_%s_%s" % [character_id, skill_id, field]
		parent.add_child(row)
		var value_label := Label.new()
		value_label.name = "AllySkillOverrideLabel_%s_%s_%s" % [character_id, skill_id, field]
		value_label.text = tr(str(labels[field]))
		row.add_child(value_label)
		var spin := SpinBox.new()
		spin.name = "AllySkillOverrideSpin_%s_%s_%s" % [character_id, skill_id, field]
		if ["atk_multiplier", "buff_multiplier"].has(field):
			spin.min_value = 0.0
			spin.max_value = RBMDefinitionLoader.ALLY_OVERRIDE_MULTIPLIER_MAX
			spin.step = 0.01
			spin.allow_greater = false
			spin.value = float(effective_skill[field])
		elif ["new_rate", "reduction_rate"].has(field):
			spin.min_value = 0.0
			spin.max_value = 1.0
			spin.step = 0.01
			spin.allow_greater = false
			spin.value = float(effective_skill[field])
		else:
			spin.min_value = 1.0 if field == "duration_turns" else 0.0
			spin.max_value = float(RBMDefinitionLoader.ALLY_OVERRIDE_INT_MAX)
			spin.step = 1.0
			spin.value = float(effective_skill[field])
		spin.value_changed.connect(_on_skill_override_changed.bind(character_id, skill_id, field))
		row.add_child(spin)
	var reset := Button.new()
	reset.name = "ResetAllySkillButton_%s_%s" % [character_id, skill_id]
	reset.text = tr("このスキルを標準値へ戻す")
	reset.pressed.connect(_on_reset_skill_pressed.bind(character_id, skill_id))
	parent.add_child(reset)

func _on_stat_override_changed(value: float, character_id: String, field: String) -> void:
	draft.set_ally_stat_override(character_id, field, value)

func _on_skill_override_changed(value: float, character_id: String, skill_id: String, field: String) -> void:
	draft.set_ally_skill_override(character_id, skill_id, field, value)

func _on_reset_character_stats_pressed(character_id: String) -> void:
	draft.reset_ally_character_stats(character_id)
	refresh()

func _on_reset_skill_pressed(character_id: String, skill_id: String) -> void:
	draft.reset_ally_skill(character_id, skill_id)
	refresh()

func _add_skill_effect_lines(parent: Control, master: Dictionary, skill: Dictionary, effect: String, skill_id: String) -> void:
	match effect:
		"damage":
			var base_damage := RBMBattle.compute_damage_amount(float(master.get("atk", 0)), float(skill.get("atk_multiplier", 1.0)), 1.0, 1.0, 1.0)
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("基礎ダメージ：%d") % base_damage)
			_add_info_label(parent, "SkillEffectNoteLabel_%s" % skill_id, tr("属性補正・一時強化前"))
		"heal":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("基本回復量：%d") % int(skill.get("heal_amount", 0)))
			_add_info_label(parent, "SkillEffectNoteLabel_%s" % skill_id, tr("対象の不足HPまで"))
		"sp_recover_single_no_self":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("自分以外の味方単体のSPを%d回復") % int(skill.get("sp_amount", 0)))
		"sp_recover_all_no_self":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("自分以外の味方全体のSPを%d回復") % int(skill.get("sp_amount", 0)))
		"buff_atk_self":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("ATK：%s倍") % str(float(skill.get("buff_multiplier", 1.0))))
			_add_info_label(parent, "SkillDurationLabel_%s" % skill_id, tr("効果時間：%dターン") % int(skill.get("duration_turns", 1)))
		"buff_next_attack":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("次の攻撃スキル：%s倍") % str(float(skill.get("buff_multiplier", 1.0))))
		"counter_stance":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("攻撃を無効化して反撃（ATK倍率：%s倍）") % str(float(skill.get("atk_multiplier", 1.0))))
		"guard_redirect":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("味方単体への攻撃をかばう"))
		"guard_boost":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("防御時の軽減率：%d%%") % int(round(float(skill.get("new_rate", 0.0)) * 100.0)))
			_add_info_label(parent, "SkillDurationLabel_%s" % skill_id, tr("効果時間：%dターン") % int(skill.get("duration_turns", 1)))
		"party_damage_reduction":
			_add_info_label(parent, "SkillEffectLabel_%s" % skill_id, tr("パーティの被ダメージ軽減：%d%%") % int(round(float(skill.get("reduction_rate", 0.0)) * 100.0)))
			_add_info_label(parent, "SkillDurationLabel_%s" % skill_id, tr("効果時間：%dターン") % int(skill.get("duration_turns", 1)))

func _add_info_label(parent: Control, node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

## Esc（PX-13、2026-10-18）を、この STEP の中の画面が受け取ったら true（RBMCreatorMain が STEP を戻らない）。
## スキルの編集中ならキャンセル、「ステータス編集」を開いていれば閉じる。
func escape() -> bool:
	if _skills_editing:
		_on_cancel_skills_pressed()
		return true
	if _status_sheet_open:
		close_status_sheet()
		return true
	return false

func is_step_valid() -> bool:
	return draft.step5_is_valid()

func validation_message() -> String:
	if draft.party_character_ids.is_empty():
		return tr("パーティを1人以上選んでください")
	return ""
