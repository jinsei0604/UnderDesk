class_name RBMCreatorAppearancePicker
extends Control

const VisualAssets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const Menu := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
const PreviewVideo := preload("res://src/bossmaker/creator/rbm_boss_preview_video.gd")

## ボス選択（ボスの外見を選ぶ画面）。2026-10-28 ユーザー承認の案（prototypes/menu_boss_select_designs_2026-10-28）で作り直した:
## 左にボスのカードの一覧（スクロール）、右に選んだボスのプロフィール（戦闘と同じ背景の上の立ち絵・名前・特徴・
## 覚醒できるボスだけ「覚醒後を見る」／「通常に戻す」・単体攻撃と全体攻撃のプレビュー枠・「このボスにする」）。
## カードを押すと選ぶだけで、決定は「このボスにする」（以前の「押した瞬間に決定」から変更）。
## 指定4体の攻撃は既存演出の録画を再生する。他のボスは準備中。一覧は RBMCreatorAppearanceCatalog.all() から作る。
## RBMCreatorMain の root_column の中に置かれ、見た目は紺＋水色（RBMMenuUi）を自分で持つ（共通の再配色を受けない）。

signal confirmed(appearance_id: String)
signal cancelled

const LIST_WIDTH := 400.0
const CARD_HEIGHT := 84.0
const THUMB_SIZE := Vector2(84, 68)
const THUMB_FIT := Vector2(72, 60)
const STAGE_HEIGHT := 250.0
const BOSS_FIT := Vector2(300, 196)
## プロフィールの特徴（ボスごと、通常／覚醒後）。表示用の文言（翻訳する）。
const FEATURES := {
	"appearance_slime": {"normal": ["ぷるぷると弾む赤いスライム", "体を伸ばして素早く殴りかかる"]},
	"appearance_wolf": {"normal": ["青い毛並みの素早い狼", "鋭い牙で飛びかかる"]},
	"appearance_knight": {"normal": ["黒い鎧に身を包んだ騎士", "大剣で重い一撃を放つ"]},
	"appearance_dragon": {"normal": ["大きな翼を持つ緑の竜", "炎の息で焼き払う"], "awakened": ["黒い体と赤い翼の覚醒した姿", "黒い炎の息と隕石で攻め立てる"]},
	"appearance_ghost": {"normal": ["炎のような衣をまとう幽霊", "ふわりと漂いながら襲いかかる"]},
	"appearance_golem": {"normal": ["岩でできた巨大なゴーレム", "拳で地面を叩きつける"]},
	"appearance_musha": {"normal": ["墨をまとう朽ちた機械の武者", "刀の一閃で斬りかかる"], "awakened": ["墨に染まり力を増した姿", "墨の刃が戦場をおおう"]},
	"appearance_astronaut": {"normal": ["宇宙から来た謎の飛行士", "重力をあやつって戦う"], "awakened": ["宇宙の力を解き放った姿", "惑星やブラックホールを呼び出す"]},
	"appearance_gentleman": {"normal": ["礼儀正しい異形の紳士", "優雅な身のこなしから攻撃を仕掛ける"], "awakened": ["本性を現した異形の姿", "紳士の面影はもうない"]},
	"appearance_plush": {"normal": ["つぎはぎだらけのぬいぐるみ", "かわいい見た目で油断を誘う"], "awakened": ["覚醒して恐ろしい姿に変わったぬいぐるみ", "かわいさの奥に恐ろしさがひそむ"]},
}

var _selected_id: String = ""
var _opened_with_id: String = ""
var _entry_buttons: Dictionary = {}  # id(String) -> Button（一覧のカード）
var _entries: Dictionary = {}  # id(String) -> カタログの1件
## 覚醒後のプレビュー（ボスごとに独立。開き直すと全部通常へ戻る）。
var _preview_awakened: Dictionary = {}  # id(String) -> bool
var _grid: GridContainer
var _count_label: Label
var _stage_bg: TextureRect
var _boss_sprite: TextureRect
var _boss_shadow: TextureRect
var _state_tag: Label
var _name_label: Label
var _features: VBoxContainer
var _toggle: Button
var _preview_title: Label
var _preview_captions: Array[Label] = []
var _preview_frames: Array[Panel] = []
var _preview_videos: Array[AspectRatioContainer] = []
var _preview_pause: Button
var _previews_paused := false
var _selected_label: Label
var _confirm_button: Button

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_meta("world_skip", true)
	# 見出しの下の線など、この画面の外へはみ出す飾りを切る。
	clip_contents = true
	_build_ui()

func _build_ui() -> void:
	Menu.add_backdrop(self, "PickerBackdrop")
	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_pressed)
	Menu.header(self, back_button, tr("戻る"), tr("ボスを選ぶ"), tr("外見と攻撃の雰囲気を見て、作るボスを決めます"), "PickerTitleLabel", "PickerSubtitleLabel")

	var body := HBoxContainer.new()
	body.name = "PickerBody"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 24
	body.offset_right = -24
	body.offset_top = 92
	body.offset_bottom = -18
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	body.add_child(_build_list())
	body.add_child(_build_profile())

	var first := ""
	for entry in RBMCreatorAppearanceCatalog.all():
		# 体験版は竜・スライム・幽霊・機械武者だけ（RBMEdition）。製品版は全員。
		if not RBMEdition.allows_appearance(str(entry["id"])):
			continue
		_build_card(_grid, entry)
		if first.is_empty():
			first = str(entry["id"])
	_count_label.text = tr("%d体") % _entries.size()
	if not first.is_empty():
		select(first)

# ---------------------------------------------------------------------------
# 左: ボスの一覧

func _build_list() -> Panel:
	var panel := Panel.new()
	panel.name = "BossListPanel"
	panel.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.92), S.PANEL_EDGE))
	Menu.section(panel, tr("ボス一覧"), Vector2(16, 12), "BossListTitle")
	_count_label = S.label(panel, "", Rect2(250, 12, 134, 28), 13, S.MUTED, "BossListCount")
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var scroll := ScrollContainer.new()
	scroll.name = "GridScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_right = -8
	scroll.offset_top = 50
	scroll.offset_bottom = -8
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	S.style_scrollbar(scroll.get_v_scroll_bar())
	_grid = GridContainer.new()
	_grid.name = "AppearanceGrid"
	_grid.columns = 1
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	return panel

## 一覧のカード1枚（押すと選ぶ。決定は「このボスにする」）。`entry` は RBMCreatorAppearanceCatalog.all() の1件と同じ形
## （{"id","name","supports_awakening"}）。テストがその場の fixture を渡して確かめられるよう、独立したメソッドにしてある。
func _build_card(grid: GridContainer, entry: Dictionary) -> void:
	var id := str(entry["id"])
	_entries[id] = entry
	_preview_awakened[id] = false
	var card := Button.new()
	card.name = "Appearance_%s" % id
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(LIST_WIDTH - 36, CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Menu.card_styles(card, false)
	var selected := S.box(Color("0f2a30", 0.96), S.ACCENT)
	selected.shadow_color = Color(S.ACCENT, 0.2)
	selected.shadow_size = 6
	card.add_theme_stylebox_override("pressed", selected)
	card.add_theme_stylebox_override("hover_pressed", selected)
	card.pressed.connect(_on_card_pressed.bind(id))
	grid.add_child(card)
	_entry_buttons[id] = card
	var bar := ColorRect.new()
	bar.name = "SelectedBar"
	bar.color = S.ACCENT
	bar.size = Vector2(4, CARD_HEIGHT)
	bar.visible = false
	card.add_child(bar)
	var area := Panel.new()
	area.name = "AppearancePreviewArea_%s" % id
	area.position = Vector2(10, 8)
	area.size = THUMB_SIZE
	area.add_theme_stylebox_override("panel", S.box(S.INSET, Color("1a2830")))
	card.add_child(area)
	var thumb := TextureRect.new()
	thumb.name = "AppearancePreview_%s" % id
	thumb.texture = S.fitted_sprite(VisualAssets.boss_asset(id), THUMB_FIT)
	if thumb.texture == null:
		thumb.texture = VisualAssets.texture(VisualAssets.boss_asset(id), 0)
	thumb.position = Vector2(6, 4)
	thumb.size = THUMB_SIZE - Vector2(12, 8)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	area.add_child(thumb)
	var name_label := S.label(card, tr(str(entry["name"])), Rect2(108, 12, LIST_WIDTH - 36 - 120, 30), 18, S.SILVER, "AppearanceName_%s" % id)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if bool(entry.get("supports_awakening", false)):
		Menu.tag(card, tr("覚醒あり"), Vector2(108, 48), S.HARD, S.HARD_EDGE, Color(S.INSET, 0.9), false, "AwakeningCapableBadge_%s" % id)
	else:
		S.label(card, tr("覚醒なし"), Rect2(108, 46, 160, 24), 12, S.DIM, "NoAwakeningLabel_%s" % id)
	_ignore_mouse(card)

func _ignore_mouse(card: Control) -> void:
	for child in card.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------------------------------------------------------------------------
# 右: プロフィール

func _build_profile() -> Panel:
	var panel := Panel.new()
	panel.name = "AppearanceProfile"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.96), S.PANEL_EDGE))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 1
	column.offset_right = -1
	column.offset_top = 1
	column.offset_bottom = -12
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	# 立ち絵の舞台（戦闘と同じ背景）と、右側の名前・特徴・覚醒の切り替え
	var stage := Control.new()
	stage.name = "ProfileStage"
	stage.custom_minimum_size = Vector2(0, STAGE_HEIGHT)
	stage.clip_contents = true
	column.add_child(stage)
	_stage_bg = TextureRect.new()
	_stage_bg.name = "ProfileStageBackground"
	_stage_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_stage_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.add_child(_stage_bg)
	var shade := S.gradient_rect(stage, Rect2(0, 0, 100, 100), Color(S.PANEL, 0.0), Color(S.PANEL, 0.95), true, 0.40, 0.66)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fade := S.gradient_rect(stage, Rect2(0, 0, 100, 60), Color(S.PANEL, 0.0), Color(S.PANEL, 1.0))
	fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -60
	_boss_shadow = S.floor_shadow(stage, Rect2(0, 0, 260, 30))
	_boss_sprite = TextureRect.new()
	_boss_sprite.name = "ProfileBossSprite"
	_boss_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_boss_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.add_child(_boss_sprite)
	var info := VBoxContainer.new()
	info.name = "ProfileInfo"
	info.anchor_left = 0.555
	info.anchor_right = 1.0
	info.anchor_bottom = 1.0
	info.offset_left = 0
	info.offset_right = -20
	info.offset_top = 20
	info.offset_bottom = -12
	info.add_theme_constant_override("separation", 6)
	stage.add_child(info)
	var tag_row := HBoxContainer.new()
	info.add_child(tag_row)
	_state_tag = Menu.tag(tag_row, "", Vector2.ZERO, S.HARD, S.HARD_EDGE, Color(S.INSET, 0.9), false, "ProfileStateTag")
	_name_label = Menu.shadow(S.label(info, "", Rect2(0, 0, 10, 44), 28, S.TEXT, "ProfileBossName"))
	_name_label.custom_minimum_size = Vector2(0, 44)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var rule := ColorRect.new()
	rule.color = S.PANEL_EDGE
	rule.custom_minimum_size = Vector2(0, 1)
	info.add_child(rule)
	var caption := S.label(info, tr("特徴"), Rect2(0, 0, 10, 22), 13, S.DIM, "ProfileFeaturesCaption")
	caption.custom_minimum_size = Vector2(0, 22)
	_features = VBoxContainer.new()
	_features.name = "ProfileFeatures"
	_features.add_theme_constant_override("separation", 2)
	_features.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(_features)
	_toggle = Button.new()
	_toggle.name = "AwakenedPreviewToggle"
	_toggle.custom_minimum_size = Vector2(200, 40)
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_toggle.add_theme_font_size_override("font_size", 15)
	_toggle.pressed.connect(func(): _on_preview_toggle_pressed(_selected_id))
	info.add_child(_toggle)
	stage.resized.connect(_place_boss)

	# 攻撃のプレビュー（録画を無音ループ再生）
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 30)
	column.add_child(head)
	_preview_title = Menu.section(head, "", Vector2(16, 2), "PreviewTitle")
	_preview_pause = Button.new()
	_preview_pause.name = "PreviewPauseButton"
	_preview_pause.text = tr("プレビューを一時停止")
	_preview_pause.add_theme_font_size_override("font_size", 12)
	S.button_style(_preview_pause)
	head.add_child(_preview_pause)
	_preview_pause.anchor_left = 1.0
	_preview_pause.anchor_right = 1.0
	_preview_pause.offset_left = -210
	_preview_pause.offset_right = -16
	_preview_pause.offset_top = 0
	_preview_pause.offset_bottom = 30
	_preview_pause.pressed.connect(_toggle_preview_pause)
	var frames := HBoxContainer.new()
	frames.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frames.add_theme_constant_override("separation", 8)
	column.add_child(frames)
	var frames_left := Control.new()
	frames_left.custom_minimum_size = Vector2(6, 0)
	frames.add_child(frames_left)
	for node_name in ["SingleAttackPreview", "AllAttackPreview"]:
		frames.add_child(_preview_frame(node_name))
	var frames_right := Control.new()
	frames_right.custom_minimum_size = Vector2(6, 0)
	frames.add_child(frames_right)

	# 決定
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, 56)
	column.add_child(bottom)
	var bottom_left := Control.new()
	bottom_left.custom_minimum_size = Vector2(22, 0)
	bottom.add_child(bottom_left)
	_selected_label = S.label(bottom, "", Rect2(0, 0, 10, 56), 15, S.SILVER, "SelectedBossLabel")
	_selected_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_label.clip_text = true
	_selected_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_confirm_button = Button.new()
	_confirm_button.name = "ConfirmAppearanceButton"
	_confirm_button.text = tr("このボスにする")
	_confirm_button.icon = Menu.icon("right", S.ACCENT)
	_confirm_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_confirm_button.custom_minimum_size = Vector2(300, 52)
	_confirm_button.add_theme_font_size_override("font_size", 20)
	S.button_style(_confirm_button, true)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	bottom.add_child(_confirm_button)
	var bottom_right := Control.new()
	bottom_right.custom_minimum_size = Vector2(14, 0)
	bottom.add_child(bottom_right)
	return panel

## 既存の枠内に動画を収める。未収録のボスは準備中の表示を残す。
func _preview_frame(node_name: String) -> Panel:
	var box := Panel.new()
	box.name = node_name
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.clip_contents = true
	box.add_theme_stylebox_override("panel", S.box(S.INSET, Color("1f3a44")))
	var grid := Control.new()
	grid.name = "PreviewPlaceholder"
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grid)
	grid.draw.connect(func():
		for gx in range(0, int(grid.size.x), 20):
			grid.draw_rect(Rect2(gx, 0, 1, grid.size.y), Color(S.ACCENT, 0.05))
		for gy in range(0, int(grid.size.y), 20):
			grid.draw_rect(Rect2(0, gy, grid.size.x, 1), Color(S.ACCENT, 0.05))
		var c := (grid.size / 2.0 + Vector2(0, -6)).round()
		for row in range(-12, 13, 3):
			grid.draw_rect(Rect2(c.x - 9, c.y + row, 24 - absi(row) * 2, 3), Color(S.SILVER, 0.55)))
	grid.resized.connect(grid.queue_redraw)
	var video := PreviewVideo.new()
	video.start_delay = 1 + _preview_videos.size()
	video.name = "PreviewVideo"
	box.add_child(video)
	video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video.offset_left = 2
	video.offset_right = -2
	video.offset_top = 38
	video.offset_bottom = -2
	_preview_videos.append(video)
	var cap := Menu.shadow(S.label(box, "", Rect2(14, 10, 260, 24), 15, S.TEXT, "PreviewCaption"))
	_preview_captions.append(cap)
	var loop := Menu.tag(box, "LOOP", Vector2.ZERO, S.MUTED, Color("2a3a44"), Color(S.INSET, 0.9), true, "PreviewLoopTag")
	loop.anchor_left = 1.0
	loop.anchor_right = 1.0
	loop.offset_left = -62
	loop.offset_right = -12
	loop.offset_top = 12
	loop.offset_bottom = 30
	var wait := S.label(box, tr("プレビュー準備中"), Rect2(0, 0, 10, 24), 13, S.MUTED, "PreviewPending")
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	wait.anchor_left = 0.0
	wait.anchor_right = 1.0
	wait.offset_left = 0
	wait.offset_right = 0
	wait.offset_top = 20
	wait.offset_bottom = 44
	_preview_frames.append(box)
	return box

func _place_boss() -> void:
	if _boss_sprite.texture == null:
		return
	var stage := _boss_sprite.get_parent() as Control
	var cx := roundf(stage.size.x * 0.555 / 2.0)
	var foot := stage.size.y - 18.0
	_boss_sprite.size = S.fitted_size(_boss_sprite.texture, BOSS_FIT)
	_boss_sprite.position = Vector2(cx - _boss_sprite.size.x / 2.0, foot - _boss_sprite.size.y).round()
	_boss_shadow.position = Vector2(cx - 130, foot - 20)

# ---------------------------------------------------------------------------
# 状態

## 画面を開き直すたびに、覚醒後のプレビューを全部通常へ戻し、今のボスを選んだ状態にする。
func open(current_appearance_id: String) -> void:
	_opened_with_id = current_appearance_id
	for id in _preview_awakened.keys():
		_preview_awakened[id] = false
	select(current_appearance_id if _entries.has(current_appearance_id) else _selected_id)

func select(appearance_id: String) -> void:
	_selected_id = appearance_id
	for id in _entry_buttons.keys():
		var card := _entry_buttons[id] as Button
		card.button_pressed = (id == appearance_id)
		(card.get_node("SelectedBar") as CanvasItem).visible = card.button_pressed
		(card.find_child("AppearanceName_%s" % id, false, false) as Label).add_theme_color_override("font_color", S.TEXT if card.button_pressed else S.SILVER)
	_refresh_profile()

func selected_appearance_id() -> String:
	return _selected_id

## 一覧のカードを押した時: 選んでプロフィールを出すだけ（決定は「このボスにする」）。
func _on_card_pressed(id: String) -> void:
	select(id)

func _on_confirm_pressed() -> void:
	if _entries.has(_selected_id):
		confirmed.emit(_selected_id)

## 覚醒後のプレビューの切り替え（表示だけ。選んでいるボス・決定には触れない）。
func _on_preview_toggle_pressed(id: String) -> void:
	if not _entries.has(id):
		return
	_preview_awakened[id] = not bool(_preview_awakened.get(id, false))
	if id == _selected_id:
		_refresh_profile()

func is_showing_awakened(id: String) -> bool:
	return bool(_preview_awakened.get(id, false))

## 旧名（一覧のカードの絵を切り替えていた頃）。今はプロフィールの絵を描き直す。
func _refresh_preview_texture(id: String) -> void:
	if id == _selected_id:
		_refresh_profile()

func _refresh_profile() -> void:
	if not _entries.has(_selected_id):
		return
	var entry: Dictionary = _entries[_selected_id]
	var asset := VisualAssets.boss_asset(_selected_id)
	var supports := bool(entry.get("supports_awakening", false))
	var has_awakened := supports and VisualAssets.has_awakened_design(asset)
	var awakened := has_awakened and bool(_preview_awakened.get(_selected_id, false))
	var shown := VisualAssets.awakened_asset_id(asset) if awakened else asset
	_stage_bg.texture = RBMBattleBackgrounds.texture_for(shown, "night")
	_boss_sprite.texture = S.fitted_sprite(shown, BOSS_FIT)
	if _boss_sprite.texture == null:
		_boss_sprite.texture = VisualAssets.texture(shown, 0)
	_place_boss()
	var name := tr(str(entry["name"]))
	_name_label.text = (tr("%s（覚醒後）") % name) if awakened else name
	_state_tag.visible = supports
	_state_tag.text = tr("覚醒後") if awakened else tr("覚醒あり")
	for child in _features.get_children():
		_features.remove_child(child)
		child.queue_free()
	var lines: Dictionary = FEATURES.get(_selected_id, {})
	for line in lines.get("awakened" if awakened else "normal", lines.get("normal", [])):
		var l := S.label(_features, "・" + tr(str(line)), Rect2(0, 0, 10, 24), 14, S.SILVER)
		l.custom_minimum_size = Vector2(0, 24)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toggle.visible = supports
	_toggle.disabled = not has_awakened
	_toggle.text = tr("通常に戻す") if awakened else tr("覚醒後を見る")
	_toggle.icon = Menu.icon("left" if awakened else "right", S.SILVER if awakened else S.HARD)
	_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if awakened else HORIZONTAL_ALIGNMENT_RIGHT
	if awakened:
		S.button_style(_toggle)
		_toggle.remove_theme_color_override("font_color")
	else:
		S.button_style(_toggle)
		var st := S.box(Color("2a1410", 0.95), S.HARD)
		st.content_margin_left = 16
		st.content_margin_right = 16
		_toggle.add_theme_stylebox_override("normal", st)
		_toggle.add_theme_color_override("font_color", Color("ffd0c2"))
	_preview_title.text = tr("覚醒後の攻撃のプレビュー") if awakened else tr("攻撃のプレビュー")
	var captions := [tr("覚醒後の単体攻撃"), tr("覚醒後の全体攻撃")] if awakened else [tr("単体攻撃"), tr("全体攻撃")]
	for i in _preview_captions.size():
		_preview_captions[i].text = captions[i]
		_preview_frames[i].add_theme_stylebox_override("panel", S.box(S.INSET, Color(S.HARD_EDGE, 0.8) if awakened else Color("1f3a44")))
		var available: bool = _preview_videos[i].configure(_selected_id, awakened, "single" if i == 0 else "all")
		_preview_frames[i].get_node("PreviewPlaceholder").visible = not available
		_preview_frames[i].get_node("PreviewPending").visible = not available
		_preview_frames[i].get_node("PreviewLoopTag").visible = available
	_preview_pause.visible = _preview_videos.any(func(video): return video.visible)
	# 決めるのはボスそのもの（覚醒後の姿を見ていても同じボス）。
	_selected_label.text = tr("選択中：%s") % name

## 「戻る」は選択内容を変えない——開いた時のボスへ選び直してから閉じる。
func _on_back_pressed() -> void:
	select(_opened_with_id)
	cancelled.emit()

func _toggle_preview_pause() -> void:
	_previews_paused = not _previews_paused
	for video in _preview_videos: video.set_paused(_previews_paused)
	_preview_pause.text = tr("プレビューを再生") if _previews_paused else tr("プレビューを一時停止")
