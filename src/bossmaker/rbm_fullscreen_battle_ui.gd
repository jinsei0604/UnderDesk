extends "res://src/bossmaker/rbm_world_ui.gd"
## Common display layout for TEST, Clear Check and CHALLENGE.
## Existing controls keep their signals and session ownership.
## 見た目は案C（2026-10-23 ユーザーが採用。ダークネイビー＋水色、行動順は案Aの形＝右上に顔と名前の縦の並び、
## 行動順の下に LOG とやめる）。色・枠・ボタンは rbm_battle_hud_style.gd。既存の部品（名前・文字・シグナル）は変えず、
## 置き場所と見た目だけを変える。試作: prototypes/battle_ui_designs_2026-10-23。
var view: Control
var canvas: Control
var stage: Control
var command_scroll: ScrollContainer
var command_backdrop: Panel
var background: TextureRect
var current_background := ""
## 今の背景画像のパス(戦っているボスの専用背景。無ければ昼/夜の標準背景)。
var current_background_path := ""
## ボスごとの背景の任意の上書き(rbm_battle_backgrounds.gd)。表示専用で、戦闘・保存には関わらない。
var boss_backgrounds: Dictionary = RBMBattleBackgrounds.BOSS_BACKGROUNDS
## ボスごとの背景の命名規則(backgrounds/<boss_id>/background.png)。
var background_convention: String = RBMBattleBackgrounds.CONVENTION
var built := false
const BossHpBar = preload("res://src/bossmaker/rbm_boss_hp_bar.gd")
const HudStyle = preload("res://src/bossmaker/rbm_battle_hud_style.gd")
var boss_hp_bar: BossHpBar

## 配置（1280×720 の論理座標）。
const BOSS_PANEL := Rect2(16, 12, 640, 70)
const BOSS_BAR := Rect2(32, 18, 608, 58)
const BOSS_NAME := Rect2(32, 34, 440, 30)
## 最新の行動と結果の文字（高さ112pxのスクロール。全体攻撃の結果が全員分読めること、UI_UX §5.2）。枠は文字の行数に合わせる。
const LOG_AREA := Rect2(28, 92, 620, 112)
const LOG_PANEL := Rect2(16, 92, 640, 112)
## 戦場（ステージの絵が動く範囲。上の欄と味方の欄の間）。
const BATTLEFIELD := Rect2(16, 212, 1248, 340)
## やり直す・REWIND（ボスの欄と行動順の間）。
const SESSION_BUTTONS := Rect2(668, 12, 328, 36)
const ORDER_X := 1008.0
const ORDER_W := 256.0
const ORDER_ROW := 30.0
const PARTY_PANEL := Rect2(16, 560, 888, 146)
const PARTY_ROWS := Rect2(28, 572, 864, 122)
const COMMAND_X := 916.0
const COMMAND_W := 348.0
const COMMAND_BOTTOM := 706.0
## コマンドの欄の上端（コマンドを選ぶ時／技の一覧・対象を選ぶ時）。技の一覧の上端は LOG・やめるの下（味方4人＋ボスの5行でも重ならない）。
const COMMAND_TOP := 450.0
const COMMAND_TOP_SELECTING := 256.0

var _order_backdrop: Panel
var _log_backdrop: Panel
var _command_caption: Label
var _command_actor: Label
var _active_marker: Control
var _shadows: Control
## 行動中の味方（ACTIVE の札・頭の上の印・COMMAND の横の名前）。演出の再生中は、今動いている味方（ボスの行動中はなし）。
var _active_unit := -1
## 戦場の上の印（味方の足元の影・頭の上の印）を出すか。ホーム画面のモニターの見本の戦闘は出さない（承認済みの見た目のまま）。
var battlefield_marks := true

func setup(target: Control) -> void:
	view = target
	view.visibility_changed.connect(update.call_deferred)
	view._skill_list_panel.visibility_changed.connect(update.call_deferred)
	view._target_picker.visibility_changed.connect(update.call_deferred)
	if view is RBMCreatorClearCheckView:
		view._confirm_panel.visibility_changed.connect(update.call_deferred)
	update.call_deferred()

func place(c: Control, parent: Control, rect: Rect2) -> void:
	if c.get_parent() != parent: c.reparent(parent)
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.position = rect.position
	c.size = rect.size

func modal(content: Control, hud: Control, rect: Rect2, node_name: String) -> void:
	var overlay := Control.new()
	overlay.name = node_name
	hud.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 40
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.03,0.05,0.78)
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudStyle.panel(overlay,rect,"DialogPanel",true)
	place(content,overlay,Rect2(rect.position+Vector2(20,20),rect.size-Vector2(40,40)))
	content.add_theme_constant_override("separation",16)
	if content is HBoxContainer:
		for child in content.get_children():
			if child is Button:
				child.custom_minimum_size = Vector2(150,44)
				child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			elif child is Label:
				child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.visibility_changed.connect(func(): overlay.visible = content.visible)
	overlay.visible = content.visible

## 結果の画面（rbm_battle_result_panel.gd、画面全体）を戦闘画面の一番上に重ねる。名前（OutcomeDialog）は勝利演出が探して
## 薄くから出すのに使う。見た目は結果の画面が自分で持つ（金への再配色を受けない）。
func result_screen(content: Control, hud: Control) -> void:
	var overlay := Control.new()
	overlay.name = "OutcomeDialog"
	overlay.set_meta("world_skip", true)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 40
	if content.get_parent() != overlay: content.reparent(overlay)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.visibility_changed.connect(func(): overlay.visible = content.visible)
	overlay.visible = content.visible

func build() -> void:
	built = true
	canvas = Control.new()
	canvas.name = "FullScreenBattleCanvas"
	view.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage = view._battlefield_ally_row.get_meta("visual_stage")
	place(stage,canvas,Rect2(0,0,1280,720))
	stage.set_meta("fullscreen_formation",true)
	stage._layout_actors()
	background = TextureRect.new()
	background.name = "FullScreenBattleBackground"
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	stage.move_child(background,0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 味方の足元の影（背景のすぐ上、キャラクターの下）と、行動を選んでいる味方の頭の上の印（案C）
	var shadows := GroundShadows.new()
	shadows.name = "AllyGroundShadows"
	shadows.stage = stage
	_shadows = shadows
	_shadows.visible = battlefield_marks
	stage.add_child(_shadows)
	stage.move_child(_shadows,1)
	_shadows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_active_marker = ActiveMarker.new()
	_active_marker.name = "ActiveAllyMarker"
	_active_marker.visible = false
	stage.add_child(_active_marker)
	var hud := Control.new()
	hud.name = "BattleHUD"
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.z_index = 20
	# 表示専用: ステージの演出がUI欄の位置を知るため(朽ちた機械武者の着弾の墨を、着弾の瞬間だけUI欄の上にも重ねる)
	stage.set_meta("battle_hud", hud)
	# 左上: ボス（「BOSS」・覚醒の札・名前・HP の数値とバー）
	HudStyle.panel(hud,BOSS_PANEL,"BossPanel")
	place(view._boss_label,hud,BOSS_NAME)
	view._boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	view._boss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	view._boss_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	view._boss_label.clip_text = true
	# ボスの HP バー（独立した部品。値は RBMBattlePresenter.apply_status_snapshot() が入れる）
	boss_hp_bar = BossHpBar.new()
	boss_hp_bar.name = "BossHpBar"
	hud.add_child(boss_hp_bar)
	place(boss_hp_bar,hud,BOSS_BAR)
	# その下: 最新の行動と結果（左に水色の線。文字が無い時は枠も出さない）
	_log_backdrop = HudStyle.panel(hud,LOG_PANEL,"LatestInfoBackdrop")
	_log_backdrop.draw.connect(func(): _log_backdrop.draw_rect(Rect2(0,6,3,_log_backdrop.size.y-12),HudStyle.CYAN))
	place(view._log_label.get_parent().get_parent(),hud,LOG_AREA)
	var fitter := LogFitter.new()
	fitter.name = "LatestInfoFitter"
	fitter.backdrop = _log_backdrop
	fitter.label = view._log_label
	fitter.max_height = LOG_PANEL.size.y
	hud.add_child(fitter)
	# 右上: 行動順（顔と名前の縦の並び）
	_order_backdrop = HudStyle.panel(hud,Rect2(ORDER_X,12,ORDER_W,36+ORDER_ROW*4),"TurnOrderBackdrop")
	HudStyle.caption(hud,"TURN ORDER",Vector2(ORDER_X+16,16),"TurnOrderCaption")
	place(view._turn_order_panel,hud,Rect2(ORDER_X+10,42,ORDER_W-20,ORDER_ROW*4))
	view._turn_order_panel.get_node("TurnOrderTitleLabel").visible = false
	(view._turn_order_panel.get_node("TurnOrderList") as BoxContainer).add_theme_constant_override("separation",4)
	view._turn_order_panel.set_meta("world_skip",true)
	view._turn_order_panel.set_meta("row_decorator",_decorate_turn_row)
	for row in view._turn_order_panel.get_node("TurnOrderList").get_children():
		if row.has_meta("turn_order_entry"): _decorate_turn_row(row,row.get_meta("turn_order_entry"))
	# 下: 味方のカード
	HudStyle.panel(hud,PARTY_PANEL,"PartyPanel")
	place(view._party_rows,hud,PARTY_ROWS)
	view._party_rows.add_theme_constant_override("separation",10)
	view._party_rows.set_meta("world_skip",true)
	# The legacy Battlefield container is emptied above (its boss label and visual
	# stage are both already relocated onto the fullscreen canvas), so it no longer
	# has anything to draw. It stays hidden, but still needs a real rect describing
	# the on-screen area the stage/sprites actually occupy -- verify_battle_ui_gpu.gd
	# checks that the latest-info message sits above this area (below the boss panel).
	place(view._battlefield,hud,BATTLEFIELD)
	view._battlefield.visible = false
	# 右下: コマンド
	command_backdrop = HudStyle.panel(hud,Rect2(COMMAND_X,COMMAND_TOP,COMMAND_W,COMMAND_BOTTOM-COMMAND_TOP),"CommandBackdrop")
	_command_caption = HudStyle.caption(hud,"COMMAND",Vector2(COMMAND_X+18,COMMAND_TOP+14),"CommandCaption")
	_command_actor = Label.new()
	_command_actor.name = "CommandActorName"
	_command_actor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_command_actor.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_command_actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.label(_command_actor,14,HudStyle.MUTED)
	hud.add_child(_command_actor)
	command_scroll = ScrollContainer.new()
	command_scroll.name = "BattleCommandScroll"
	command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud.add_child(command_scroll)
	place(view._command_area,command_scroll,Rect2(0,0,COMMAND_W-28,236))
	view._command_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view._main_command_row.add_theme_constant_override("separation",10)
	view._skill_list_panel.add_theme_constant_override("separation",6)
	view._target_picker.add_theme_constant_override("separation",8)
	# 行動順の下: LOG・やめる（2026-10-23 ユーザーの指定。行動順の行数に合わせて update() で上下を決める）
	place(view.find_child("LogButton",true,false),hud,Rect2(ORDER_X,206,84,36))
	place(view._quit_button,hud,Rect2(ORDER_X+92,206,ORDER_W-92,36))
	# ボスの欄と行動順の間: やり直す・REWIND
	var session_y := SESSION_BUTTONS.position.y
	if view is RBMCreatorClearCheckView or view is RBMChallengeBattleView:
		place(view._restart_button,hud,Rect2(SESSION_BUTTONS.position.x,session_y,SESSION_BUTTONS.size.x,SESSION_BUTTONS.size.y))
		session_y += SESSION_BUTTONS.size.y+8
		modal(view._restart_confirm,hud,Rect2(190,260,900,180),"RestartDialog")
	if view is RBMCreatorTestBattleView or view is RBMCreatorClearCheckView:
		var rewind_scroll: Control = view._rewind_list.get_parent()
		rewind_scroll.custom_minimum_size = Vector2(240,SESSION_BUTTONS.size.y)
		place(rewind_scroll,hud,Rect2(SESSION_BUTTONS.position.x,session_y,SESSION_BUTTONS.size.x,SESSION_BUTTONS.size.y))
	if view is RBMCreatorTestBattleView or view is RBMChallengeBattleView:
		modal(view._quit_confirm,hud,Rect2(190,260,900,180),"QuitDialog")
	result_screen(view._outcome_area,hud)
	# Clear Check still owns its confirm/battle visibility state. Keep those nodes.
	if view is RBMCreatorClearCheckView:
		for child in view._battle_panel.get_children():
			if child is Control: child.hide()
	else:
		view.get_node("Column").hide()
	for detail in [view._ally_detail_overlay,view._boss_detail_overlay,view._log_window_overlay]:
		var detail_overlay: Control = detail["overlay"]
		detail_overlay.z_index = 60
		# These overlays are meant to behave like full-screen modal popups (see
		# build_detail_overlay's own doc comment), but they are plain children of
		# `view`, nested alongside the fullscreen HUD tree rather than as an actual
		# top-level popup. Without top_level, pointer clicks on their inner buttons
		# (e.g. the "close" button) were not reaching those buttons once the rest of
		# the screen was rebuilt into this absolute-positioned HUD -- only clicks
		# that fell through to the overlay's own catch-all "click anywhere closes"
		# handler worked. top_level=true fixes hit-testing without changing the
		# overlay's on-screen position (its anchors still resolve against `view`'s
		# own full-viewport rect).
		detail_overlay.top_level = true

func update() -> void:
	if not is_instance_valid(view) or not view.is_inside_tree(): return
	if not built: build()
	canvas.visible = not view._confirm_panel.visible if view is RBMCreatorClearCheckView else true
	var value: String = view.battle_background
	if view is RBMCreatorTestBattleView or view is RBMCreatorClearCheckView:
		if is_instance_valid(view.main) and view.main.get("draft") is RBMCreatorDraft:
			value = view.main.draft.battle_background
	current_background = value
	# 戦っているボスの専用背景(backgrounds/<boss_id>/background.png)。無いときは昼/夜の標準背景(rbm_battle_backgrounds.gd)。
	var path := RBMBattleBackgrounds.path_for(RBMVisualAssets.boss_asset(view._boss_appearance_id), value, boss_backgrounds, background_convention)
	if path != current_background_path:
		current_background_path = path
		background.texture = load(path)
	# 行動順の枠は行の数に合わせる。LOG・やめるはそのすぐ下。
	var rows := maxi(1, view._turn_order_panel.get_node("TurnOrderList").get_child_count())
	_order_backdrop.size.y = 36+ORDER_ROW*rows
	view._turn_order_panel.size.y = ORDER_ROW*rows
	var buttons_y := 12+_order_backdrop.size.y+8
	view.find_child("LogButton",true,false).position.y = buttons_y
	view._quit_button.position.y = buttons_y
	var selecting: bool = view._skill_list_panel.visible or view._target_picker.visible
	var top := maxf(COMMAND_TOP_SELECTING,buttons_y+36+14) if selecting else COMMAND_TOP
	command_backdrop.position.y = top
	command_backdrop.size.y = COMMAND_BOTTOM-top
	_command_caption.position.y = top+14
	_command_actor.position = Vector2(COMMAND_X+110,top+10)
	_command_actor.size = Vector2(COMMAND_W-128,20)
	command_scroll.position = Vector2(COMMAND_X+14,top+38)
	command_scroll.size = Vector2(COMMAND_W-28,COMMAND_BOTTOM-12-(top+38))
	# Content has natural minimum height; the viewport, exit and return controls stay fixed.
	view._command_area.custom_minimum_size.y = 0
	# ボスの HP バー: 演出の再生中は presenter が命中の瞬間に入れる（先のダメージを見せない）。それ以外（戦闘の開始・REWIND・
	# やり直し・演出の後）は今の戦闘の状態をすぐ入れる。
	if is_instance_valid(boss_hp_bar) and view.session != null and view.session.battle != null and not view._is_presenting():
		RBMBattlePresenter.apply_boss_bar(view, view.session.battle.presentation_state())
	# ボスの名前は右の数値の手前まで（長い名前は「…」で切る。全部の名前はボスの詳細で読める）
	view._boss_label.size.x = maxf(80.0,BOSS_BAR.position.x+boss_hp_bar.text_left()-14-BOSS_NAME.position.x)
	walk(view)
	_watch_presenter()
	if not view._is_presenting():
		_active_unit = _waiting_ally()
	_apply_style()
	# 技の一覧を開いた時（枠の大きさが決まった後）に、説明が枠に収まるかを確かめ直す（「戻る」を隠さない、2026-10-18）
	if view._skill_list_panel.visible and view.get("_skill_detail_label") != null:
		RBMBattleUiKit.fit_skill_detail.call_deferred(view._skill_detail_label)

## 行動を選んでいる味方（いなければ -1）。
func _waiting_ally() -> int:
	if view.session == null or view.session.battle == null or view.session.battle.battle_over:
		return -1
	if not view.session.is_waiting_for_ally_action():
		return -1
	return int(view.session.pending_ally_id())

## 演出の再生中は、行動を始めた味方を「行動中」にする（ボスの行動中は誰も行動中にしない）。
func _watch_presenter() -> void:
	var presenter = view.get("_presenter")
	if is_instance_valid(presenter) and not presenter.entry_started.is_connected(_on_entry_started):
		presenter.entry_started.connect(_on_entry_started)
	# 登場の演出が終わって操作できるようになった時（味方が先に動く戦闘では、ここで画面の更新が起きない）
	var encounter = view.get("_encounter")
	if is_instance_valid(encounter) and not encounter.intro_finished.is_connected(update):
		encounter.intro_finished.connect(update,CONNECT_DEFERRED)

func _on_entry_started(entry: Dictionary) -> void:
	var actor = entry.get("actor", "boss")
	_active_unit = -1 if str(actor) == "boss" or not str(actor).is_valid_int() else int(actor)
	if built:
		_apply_active()

## 案Cの見た目を付ける（walk() の金への再配色の後に毎回。同じ値なら作り直さない）。
func _apply_style() -> void:
	HudStyle.label(view._boss_label,20,HudStyle.TEXT)
	HudStyle.label(view._log_label,15,HudStyle.TEXT)
	for b in [view.find_child("LogButton",true,false),view._quit_button,view.get("_restart_button")]:
		if b is Button: HudStyle.button(b,15)
	if view.get("_rewind_list") != null:
		for b in view._rewind_list.get_children():
			if b is Button: HudStyle.button(b,15)
	for b in view._main_command_row.get_children():
		if b is Button: _command_button(b)
	for c in view._skill_list_panel.get_children():
		if c is Button:
			HudStyle.button(c,15,Vector4(14,6,12,6))
			c.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if str(c.name) == "SkillListBackButton": _back_button(c)
		elif c is Label and not c.has_meta("hud_c"):
			c.set_meta("hud_c",true)
			HudStyle.label(c,14,HudStyle.TEXT)
			c.add_theme_stylebox_override("normal",HudStyle.inner())
	for c in view._target_picker.get_children():
		if c is Button:
			HudStyle.button(c,16,Vector4(14,6,12,6))
			c.custom_minimum_size.y = 44
			c.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if str(c.name) == "TargetPickerBackButton": _back_button(c)
	for confirm in [view.get("_restart_confirm"),view.get("_quit_confirm")]:
		if confirm is Container:
			for c in confirm.get_children():
				if c is Button: HudStyle.button(c,16)
				elif c is Label: HudStyle.label(c,18,HudStyle.TEXT)
	for detail in [view._ally_detail_overlay,view._boss_detail_overlay,view._log_window_overlay]:
		var window := detail["panel"] as Control
		if not window.has_meta("hud_c"):
			window.set_meta("hud_c",true)
			window.add_theme_stylebox_override("panel",HudStyle.window())
		HudStyle.label(detail["title_label"],20,HudStyle.TEXT)
		HudStyle.button(detail["close_button"],15)
	for card in view._party_rows.get_children():
		if card is PanelContainer and not card.has_meta("hud_c"): _build_card(card)
	_apply_active()

## 行動中の味方: カードの光・ACTIVE の札、COMMAND の横の名前、頭の上の印。コマンドの欄は選べる時だけ光らせる。
## 名前は長い時（英語・ハンマー使い・戦闘不能）にカードの幅へ収まる大きさまで小さくする（15〜12px。12px は補足の文字の下限、UI_UX §2。
## 全部の名前は行動順・COMMAND の横に14pxで出る。それでも長ければ「…」）。
func _apply_active() -> void:
	var count := maxi(1,view._party_rows.get_child_count())
	var name_width := (PARTY_ROWS.size.x-10.0*(count-1))/count-16.0-46.0-8.0-4.0
	for card in view._party_rows.get_children():
		if not card.has_meta("hud_c"): continue
		var name_label := card.find_child("PartyRowName_%d" % int(card.get_meta("unit_id")),true,false) as Label
		# 幅はカードの幅からの計算と今の幅の小さい方（並べ直す前の古い幅で大きく見積もらない）
		if name_label != null: _fit_text(name_label,minf(name_width,name_label.size.x) if name_label.size.x > 1.0 else name_width,15,12)
		var active := int(card.get_meta("unit_id")) == _active_unit
		if card.has_meta("hud_active") and bool(card.get_meta("hud_active")) == active: continue
		card.set_meta("hud_active",active)
		card.add_theme_stylebox_override("panel",HudStyle.card(active))
		(card.get_meta("active_chip") as Control).visible = active
		(card.get_meta("face_frame") as Control).add_theme_stylebox_override("panel",HudStyle.face_frame(Color(HudStyle.CYAN,0.6 if active else 0.25)))
		card.queue_redraw()
	var unit: RBMUnit = null
	if _active_unit >= 0 and view.session != null and view.session.battle != null:
		unit = RBMBattleUiKit.unit_by_id(view.session.battle,_active_unit)
	_command_actor.text = tr(unit.display_name) if unit != null else ""
	var presenting: bool = view._is_presenting()
	var encounter = view.get("_encounter")
	var choosing: bool = not presenting and _active_unit >= 0 and not (is_instance_valid(encounter) and encounter.is_playing())
	command_backdrop.set("accent",choosing)
	_shadows.visible = battlefield_marks
	_place_marker(choosing and battlefield_marks)

func _fit_text(l: Label, width: float, largest: int, smallest: int) -> void:
	var font := l.get_theme_font("font")
	var font_size := largest
	while font_size > smallest and font.get_string_size(l.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
		font_size -= 1
	if l.get_theme_font_size("font_size") != font_size:
		l.add_theme_font_size_override("font_size",font_size)

func _place_marker(show: bool) -> void:
	var key := str(_active_unit)
	var visual: Control = stage._visuals.get(key) if show and stage._visuals.has(key) else null
	if visual == null or not visual.visible or not visual.has_method("visible_rect"):
		_active_marker.visible = false
		return
	var bounds: Rect2 = visual.call("visible_rect")
	_active_marker.position = (visual.position+Vector2(bounds.get_center().x,bounds.position.y)-Vector2(0,20)).round()
	_active_marker.visible = true

func _command_button(b: Button) -> void:
	HudStyle.button(b,19,Vector4(20,6,40,6))
	b.custom_minimum_size.y = 56
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("h_separation",16)
	var kind: String = {"AttackButton":"attack","OpenSkillListButton":"skill","DefendButton":"defend"}.get(str(b.name),"")
	if not kind.is_empty(): b.icon = HudStyle.icon(kind)
	if not b.has_meta("hud_c"):
		b.set_meta("hud_c",true)
		# 乗せた時・選んでいる時は右に ▶
		b.draw.connect(func():
			if b.disabled or not (b.is_hovered() or b.has_focus()): return
			var c := Vector2(b.size.x-24,b.size.y*0.5)
			b.draw_colored_polygon(PackedVector2Array([c+Vector2(-5,-8),c+Vector2(5,0),c+Vector2(-5,8)]),HudStyle.CYAN))

func _back_button(b: Button) -> void:
	b.icon = HudStyle.icon("back")
	b.custom_minimum_size = Vector2(150,40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("h_separation",10)

## 味方のカードを案Cの形にする（1枚につき1回）。名前・HP・SP の文字（テキスト）・名前付きの部品はそのまま。
## 顔を大きく額に入れ、名前の下に ACTIVE の札、HP・SP は左に水色の見出し・右に数値。
func _build_card(card: PanelContainer) -> void:
	var uid := int(str(card.name).trim_prefix("PartyRow_"))
	card.set_meta("hud_c",true)
	card.set_meta("unit_id",uid)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := card.get_node("PartyRowBody_%d" % uid) as BoxContainer
	body.add_theme_constant_override("separation",3)
	var header := body.get_node("PartyRowHeader_%d" % uid) as BoxContainer
	header.add_theme_constant_override("separation",8)
	var portrait := header.get_node("PartyRowPortrait_%d" % uid) as Control
	portrait.custom_minimum_size = Vector2(44,44)
	var frame := PanelContainer.new()
	frame.name = "PartyRowFace_%d" % uid
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(frame)
	header.move_child(frame,0)
	portrait.reparent(frame)
	var name_label := header.get_node("PartyRowName_%d" % uid) as Label
	var column := VBoxContainer.new()
	column.name = "PartyRowNameColumn_%d" % uid
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",4)
	header.add_child(column)
	name_label.reparent(column)
	HudStyle.label(name_label,15,HudStyle.TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var chip := PanelContainer.new()
	chip.name = "PartyRowActive_%d" % uid
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.add_theme_stylebox_override("panel",HudStyle.pill(Color(HudStyle.CYAN,0.18),HudStyle.CYAN))
	var chip_text := Label.new()
	chip_text.text = "ACTIVE"
	chip_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	HudStyle.label(chip_text,HudStyle.CAPTION_SIZE,HudStyle.CYAN,HudStyle.number_font())
	chip.add_child(chip_text)
	# ACTIVE の札の横に、覚醒している間だけ「覚醒 残りN」の札（味方の覚醒、2026-10-24。色だけに頼らず文字で出す）。
	var chips := HBoxContainer.new()
	chips.name = "PartyRowChips_%d" % uid
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation",4)
	column.add_child(chips)
	chips.add_child(chip)
	var awakening := PanelContainer.new()
	awakening.name = "PartyRowAwakening_%d" % uid
	awakening.mouse_filter = Control.MOUSE_FILTER_IGNORE
	awakening.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	awakening.add_theme_stylebox_override("panel",HudStyle.pill(HudStyle.AWAKENED_FILL,HudStyle.AWAKENED_EDGE))
	var awakening_text := Label.new()
	awakening_text.name = "PartyRowAwakeningText_%d" % uid
	awakening_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	HudStyle.label(awakening_text,HudStyle.CAPTION_SIZE,HudStyle.AWAKENED_TEXT)
	awakening.add_child(awakening_text)
	chips.add_child(awakening)
	var unit: RBMUnit = null
	if view.session != null and view.session.battle != null:
		unit = RBMBattleUiKit.unit_by_id(view.session.battle,uid)
	RBMBattlePresenter.apply_awakening_chip(card,uid,unit != null and unit.awakened,unit.awakening_turns_left if unit != null else 0)
	card.set_meta("active_chip",chip)
	card.set_meta("face_frame",frame)
	for key in ["PartyRowHP_%d","PartyRowSP_%d"]:
		var stat := body.find_child(key % uid,true,false) as Label
		if stat == null: continue
		stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudStyle.label(stat,14,Color(0,0,0,0),HudStyle.number_font())
		# 文字（"HP 408 / 450"）はそのまま持ち、見出しと数値に分けて描く。同じ部品の描画なので、文字が変わった
		# フレームで描き直される（ダメージの数字と HP の数値が同じフレームで変わる、2026-10-22 の同期を崩さない）。
		stat.draw.connect(_draw_stat.bind(stat))
	for key in ["PartyRowHPBar_%d","PartyRowSPBar_%d"]:
		var bar := body.find_child(key % uid,true,false) as ProgressBar
		if bar == null: continue
		var hp: bool = str(key).begins_with("PartyRowHP")
		bar.custom_minimum_size.y = 7 if hp else 5
		bar.add_theme_stylebox_override("background",HudStyle.bar_track())
		bar.add_theme_stylebox_override("fill",HudStyle.bar_fill(HudStyle.HP_TOP if hp else HudStyle.SP_TOP,HudStyle.HP_BOTTOM if hp else HudStyle.SP_BOTTOM))
	card.draw.connect(_draw_card_glow.bind(card))

func _draw_stat(stat: Label) -> void:
	var text := stat.text
	var cut := text.find(" ")
	var head := text.substr(0,cut) if cut > 0 else text
	var value := text.substr(cut+1) if cut > 0 else ""
	var font := HudStyle.number_font()
	var baseline := roundf((stat.size.y-font.get_height(14))*0.5+font.get_ascent(14))
	stat.draw_string(font,Vector2(0,baseline),head,HORIZONTAL_ALIGNMENT_LEFT,-1,HudStyle.CAPTION_SIZE,HudStyle.CYAN)
	var w := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
	stat.draw_string(font,Vector2(stat.size.x-w,baseline),value,HORIZONTAL_ALIGNMENT_LEFT,-1,14,HudStyle.TEXT)

func _draw_card_glow(card: Control) -> void:
	if not bool(card.get_meta("hud_active",false)): return
	for k in range(1,4):
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_corner_radius_all(4+k)
		ring.border_color = Color(HudStyle.CYAN,0.14-k*0.035)
		ring.set_border_width_all(2)
		card.draw_style_box(ring,Rect2(Vector2.ZERO,card.size).grow(k*2))

## 行動順の1行に、顔の写真と色を付ける（RBMBattleUiKit.refresh_turn_order_panel が行を作る時に呼ぶ）。
## 行の中の文字（▶・名前）はそのまま持つ（▶ の印は見せず、今の番は水色の帯と右の ▶ で示す）。
func _decorate_turn_row(row: Control, entry: Dictionary) -> void:
	if row.has_meta("hud_c"): return
	row.set_meta("hud_c",true)
	var current: bool = entry["status"] == RBMBattleUiKit.TURN_ORDER_STATUS_CURRENT
	var is_boss: bool = entry["is_boss"]
	row.add_theme_stylebox_override("panel",HudStyle.clear(Vector4(12,1,24,1)))
	var content := row.get_child(0) as BoxContainer
	content.add_theme_constant_override("separation",10)
	(content.get_child(0) as Control).visible = false
	var name_label := content.get_child(1) as Label
	HudStyle.label(name_label,14,HudStyle.BOSS_NAME if is_boss else HudStyle.TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var asset := _boss_asset() if is_boss else str(entry.get("character_id",""))
	var frame := PanelContainer.new()
	frame.name = "TurnOrderFace"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := (HudStyle.BOSS_EDGE if is_boss else HudStyle.CYAN) if current else HudStyle.CYAN_DIM
	frame.add_theme_stylebox_override("panel",HudStyle.face_frame(edge))
	frame.add_child(RBMBattleUiKit.build_face_portrait(asset,22,"TurnOrderFacePortrait"))
	content.add_child(frame)
	content.move_child(frame,1)
	if current:
		row.draw.connect(func():
			var w := row.size.x
			var h := row.size.y
			row.draw_polygon(PackedVector2Array([Vector2(0,0),Vector2(w,0),Vector2(w,h),Vector2(0,h)]),PackedColorArray([Color(HudStyle.CYAN,0.26),Color(HudStyle.CYAN,0.0),Color(HudStyle.CYAN,0.0),Color(HudStyle.CYAN,0.26)]))
			row.draw_rect(Rect2(0,0,3,h),HudStyle.CYAN)
			var c := Vector2(w-12,h*0.5)
			row.draw_colored_polygon(PackedVector2Array([c+Vector2(-3,-5),c+Vector2(4,0),c+Vector2(-3,5)]),HudStyle.CYAN))

## 今のボスの絵（覚醒した後は覚醒後の絵）。ステージが今出している絵に合わせる。
func _boss_asset() -> String:
	if is_instance_valid(stage) and not str(stage._asset_ids.get("boss","")).is_empty():
		return str(stage._asset_ids["boss"])
	return RBMVisualAssets.boss_asset(view._boss_appearance_id)

## 最新の行動の枠を、文字の行数に合わせる（文字が無い時は枠も出さない）。文字は演出の途中でも変わるので毎フレーム見る。
class LogFitter extends Node:
	var backdrop: Control
	var label: Label
	var max_height := 112.0
	var _seen := false
	var _last := ""
	var _last_width := -1.0
	func _process(_delta: float) -> void:
		if not is_instance_valid(backdrop) or not is_instance_valid(label):
			return
		if _seen and label.text == _last and label.size.x == _last_width:
			return
		_seen = true
		_last = label.text
		_last_width = label.size.x
		backdrop.visible = not _last.strip_edges().is_empty()
		if backdrop.visible:
			backdrop.size.y = clampf(label.get_minimum_size().y+14.0,40.0,max_height)

## 味方の足元の影（案C）。横は今の足元、縦は立っている地面（跳んでも影は地面に残る）。味方の絵が隠れている間
## （専用の技の演出が自分で絵を描く間など）は薄くして消す。戦闘の状態には触れない。
class GroundShadows extends Control:
	const FADE_TIME := 0.12
	var stage: Control
	var _alpha: Dictionary = {}
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		if not is_instance_valid(stage):
			return
		for key in stage._party_keys:
			var visual: Control = stage._visuals.get(key)
			var target := 1.0 if is_instance_valid(visual) and visual.visible else 0.0
			_alpha[key] = move_toward(float(_alpha.get(key,target)),target,delta/FADE_TIME)
		queue_redraw()
	func _draw() -> void:
		if not is_instance_valid(stage):
			return
		for key in stage._party_keys:
			var visual: Control = stage._visuals.get(key)
			var a := float(_alpha.get(key,0.0))
			if not is_instance_valid(visual) or a <= 0.0 or not stage._homes.has(key):
				continue
			var foot := Vector2.ZERO
			if visual.has_method("foot_position"):
				foot = visual.call("foot_position")
			var at := Vector2((visual.position+foot).x,(Vector2(stage._homes[key])+foot).y-2).round()
			draw_set_transform(at,0,Vector2(1,0.28))
			for k in range(4,0,-1):
				draw_circle(Vector2.ZERO,22+k*5,Color(0,0,0,0.12*a))
			draw_circle(Vector2.ZERO,22,Color(0,0,0,0.34*a))
		draw_set_transform(Vector2.ZERO)

## 行動を選んでいる味方の頭の上の印（水色の菱形と輪）。
class ActiveMarker extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(0,-9),Vector2(7,0),Vector2(0,9),Vector2(-7,0)]),HudStyle.CYAN)
		draw_arc(Vector2.ZERO,12,0,TAU,24,Color(HudStyle.CYAN,0.35),2)
