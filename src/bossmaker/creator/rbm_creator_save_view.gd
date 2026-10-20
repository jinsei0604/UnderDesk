class_name RBMCreatorSaveView
extends Control

## Phase 1 Step 6 §38/§39/§40 — 保存フロー画面。RBMCreatorMainの兄弟ビューと
## して実装（RBMCreatorTestBattleView/RBMCreatorClearCheckViewと同じ既存
## パターン）。実際のRepository呼び出しはすべてmain.press_save_as_new()/
## main.press_overwrite_save()/main.boss_name_already_saved_elsewhere()
## 経由——このビュー自身はUI提示のみを担う。
##
## 見た目は案A「王道RPG」（2026-10-18 ユーザーの決定。比較の資料は prototypes/result_screens_2026-10-17/）:
## ボスの戦闘背景を暗く敷き、大きな見出し（保存／保存しました）→ 金の二重枠の「保存するボス」の窓（絵・名前・
## クリアチェックと公開の状態・SIMPLE/HARDCORE）→「▶」で選ぶメニュー。同じ名前の確認・保存できなかった時の文も
## 同じ見た目。名前の付いた部品（SaveNewButton など）と押した時の処理は今までどおり。

signal return_to_creator_requested

## 実機プレイ改善③ item4: 保存成功画面専用の戻り先シグナル。既存の
## return_to_creator_requested（選択画面の「戻る」——保存せずSTEP7へ戻る、
## 無改修）とは意図的に別のシグナルにした——保存"成功後"だけ、STEP7を経由
## せずクリエイター一覧へ直帰させるため。
signal return_to_creator_list_requested

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

const Kit = preload("res://src/bossmaker/rbm_result_screen_kit.gd")
const Escape = preload("res://src/bossmaker/rbm_escape.gd")
const S = Kit.S
## 中身の幅（1280 から左右の余白を除いた幅）。中身はこの幅の中央にそろえる。
const CONTENT_W := 1280.0 - 2.0 * CONTENT_SIDE_MARGIN_PX
const CENTER_X := CONTENT_W * 0.5
## 「保存するボス」の窓とメニューの位置（中身の中での位置）。
const BOSS_WINDOW := Rect2(CENTER_X - 350.0, 188.0, 700.0, 230.0)
const MENU := Rect2(CENTER_X - 200.0, 486.0, 400.0, 0.0)
const NOTE := Rect2(CENTER_X - 350.0, 428.0, 700.0, 52.0)

var main: Node  # RBMCreatorMain

var _content: Control
var _boss_window: Control
var _boss_art: Control

var _choice_panel: Control
var _boss_name_label: Label
var _save_new_button: Button       # §39 新規stage: [保存する]
var _overwrite_button: Button      # §39 保存済みstage: [上書き保存]
var _save_as_new_button: Button    # §39 保存済みstage: [新しいボスとして保存]
var _back_button: Button
var _error_label: Label

var _same_name_panel: Control
var _same_name_message_label: Label
var _same_name_confirm_button: Button
var _same_name_cancel_button: Button
var _pending_same_name_action: String = ""

var _success_panel: Control
var _success_stage_id_label: Label
var _success_return_button: Button
var _publish_hint_label: Label

## 戦闘背景（ボスの専用背景か昼／夜の標準背景）。この画面の一番奥に暗くして描く。
var _backdrop_texture: Texture2D
var _tweens: Array[Tween] = []
var _generation := 0

func setup(p_main: Node) -> void:
	main = p_main
	_build_ui()

func _build_ui() -> void:
	# 金への再配色・枠の差し替え（RBMWorldUi.walk）を受けない（この画面は自分で見た目を持つ）
	set_meta("world_skip", true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_content = Control.new()
	_content.name = "SaveContent"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.anchor_right = 1.0
	_content.anchor_bottom = 1.0
	_content.offset_left = CONTENT_SIDE_MARGIN_PX
	_content.offset_right = -CONTENT_SIDE_MARGIN_PX
	add_child(_content)

	# 保存するボスの窓（3つの欄で同じ。絵・状態・札は開くたびに作る）
	_boss_window = Kit.window(_content, BOSS_WINDOW, tr("保存するボス"), "SaveBossWindow")
	_boss_art = Control.new()
	_boss_art.name = "SaveBossArt"
	_boss_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_window.add_child(_boss_art)
	_boss_name_label = Kit.label(_boss_window, "", Rect2(196, 56, 470, 32), 20, S.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "SaveBossNameLabel")

	_build_choice_panel(_content)
	_build_same_name_panel(_content)
	_build_success_panel(_content)

## 3つの欄（選ぶ・同じ名前の確認・できた）の入れ物。中身の全体に広がり、メニューの窓は menu_holder に作る。
func _new_panel(parent: Control, node_name: String, title: String, title_name: String) -> Control:
	var p := Control.new()
	p.name = node_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var holder := Control.new()
	holder.name = "MenuHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(holder)
	var t := Kit.label(p, title, Rect2(0, 54, CONTENT_W, 84), 64, S.GOLD, HORIZONTAL_ALIGNMENT_CENTER, title_name, S.number_font())
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("shadow_offset_x", 4)
	t.add_theme_constant_override("shadow_offset_y", 4)
	return p

func _new_button(parent: Control, node_name: String, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _build_choice_panel(parent: Control) -> void:
	_choice_panel = _new_panel(parent, "SaveChoicePanel", tr("保存"), "SaveTitleLabel")
	_error_label = Kit.wrap(_choice_panel, "", NOTE, 15, Kit.RED, HORIZONTAL_ALIGNMENT_CENTER, "SaveErrorLabel")
	_save_new_button = _new_button(_choice_panel, "SaveNewButton", tr("保存する"), _on_save_new_pressed)
	_overwrite_button = _new_button(_choice_panel, "OverwriteButton", tr("上書き保存"), _on_overwrite_pressed)
	_save_as_new_button = _new_button(_choice_panel, "SaveAsNewButton", tr("新しいボスとして保存"), _on_save_as_new_pressed)
	_back_button = _new_button(_choice_panel, "SaveBackButton", tr("戻る"), _on_back_pressed)

func _build_same_name_panel(parent: Control) -> void:
	_same_name_panel = _new_panel(parent, "SameNameWarningPanel", tr("保存"), "SameNameTitleLabel")
	_same_name_panel.visible = false
	_same_name_message_label = Kit.wrap(_same_name_panel, tr("同じ名前のボス戦がすでに保存されています。\nそれでも保存しますか？"), NOTE, 16, S.GOLD, HORIZONTAL_ALIGNMENT_CENTER, "SameNameMessageLabel")
	_same_name_confirm_button = _new_button(_same_name_panel, "SameNameConfirmButton", tr("保存する"), _on_same_name_confirmed)
	_same_name_cancel_button = _new_button(_same_name_panel, "SameNameCancelButton", tr("キャンセル"), _on_same_name_cancelled)

func _build_success_panel(parent: Control) -> void:
	_success_panel = _new_panel(parent, "SaveSuccessPanel", tr("保存しました"), "SaveSuccessTitleLabel")
	_success_panel.visible = false
	# ステージID は「保存するボス」の窓の右下に重ねる
	_success_stage_id_label = Kit.label(_success_panel, "", Rect2(BOSS_WINDOW.position + Vector2(330, 164), Vector2(340, 28)), 14, S.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, "SuccessStageIdLabel", S.number_font())
	_publish_hint_label = Kit.wrap(_success_panel, tr("最終確認の画面の「オンライン公開」で公開できます"), NOTE, 16, S.EMPHASIS, HORIZONTAL_ALIGNMENT_CENTER, "PublishHint")
	_success_return_button = _new_button(_success_panel, "SuccessReturnButton", tr("クリエイター一覧に戻る"), _on_success_return_pressed)

func _draw() -> void:
	# 一番奥: ボスの戦闘背景を、画面を覆う大きさで暗く描き、さらに薄い幕を重ねる
	if _backdrop_texture != null:
		var tex_size := _backdrop_texture.get_size()
		var scale := maxf(size.x / tex_size.x, size.y / tex_size.y)
		var drawn := tex_size * scale
		draw_texture_rect(_backdrop_texture, Rect2((size - drawn) * 0.5, drawn), false, Color(0.45, 0.5, 0.58))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.035, 0.05, 0.45))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), S.BG)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

## 「保存するボス」の窓の中身（絵・クリアチェックと公開の状態・SIMPLE/HARDCORE）と背景を、今のボスで作り直す。
func _refresh_boss() -> void:
	for c in _boss_art.get_children():
		_boss_art.remove_child(c)
		c.queue_free()
	var draft: RBMCreatorDraft = main.draft if main != null and main.get("draft") is RBMCreatorDraft else null
	if draft == null:
		return
	var asset := RBMVisualAssets.boss_asset(draft.appearance_id)
	_backdrop_texture = RBMBattleBackgrounds.texture_for(asset, draft.battle_background)
	queue_redraw()
	Kit.boss_sprite(_boss_art, asset, Rect2(24, 54, 150, 150))
	var cleared := draft.is_clear_check_currently_valid()
	var published := draft.is_online_published()
	Kit.label(_boss_art, ("✓ " + tr("クリアチェック達成済み")) if cleared else ("・" + tr("未達成")), Rect2(196, 98, 470, 28), 16, Kit.OK if cleared else S.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "ClearCheckStatus")
	Kit.label(_boss_art, "・" + (tr("オンライン公開中") if published else tr("オンライン未公開")), Rect2(196, 128, 470, 28), 16, S.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "PublishStatus")
	S.mode_tag(_boss_art, draft.creator_mode, Vector2(196, 166))
	# 公開の案内は、クリアチェックを通っていて、まだ公開していない時だけ
	_publish_hint_label.visible = cleared and not published

## panel の今出しているボタンで「▶」のメニューを作り、見出し・窓・メニューを順に出す。最初のフォーカスは focus_button。
func _present(panel: Control, focus_button: Button) -> void:
	_generation += 1
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	var holder := panel.get_node("MenuHolder") as Control
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var buttons: Array[Button] = []
	for c in panel.get_children():
		if c is Button and (c as Button).visible:
			buttons.append(c)
	var menu := Kit.menu(holder, MENU, buttons, "SaveMenu")
	if not is_inside_tree():
		return
	var title := panel.get_child(1) as Control
	title.position = Vector2(0, 54)
	_tweens.append(Kit.enter(title, 0.0, 0.45, Vector2(0, -40)))
	_boss_window.position = BOSS_WINDOW.position
	_tweens.append(Kit.enter(_boss_window, 0.25, 0.3, Vector2.ZERO, 0.94))
	for b in buttons:
		_tweens.append(Kit.enter(b, 0.9, 0.25, Vector2(0, 12)))
	Kit.enter(menu, 0.9, 0.25, Vector2(0, 12))
	var target := focus_button if focus_button != null and focus_button.visible else (buttons[0] if not buttons.is_empty() else null)
	if target != null:
		var generation := _generation
		get_tree().create_timer(1.15).timeout.connect(func():
			if generation == _generation and is_instance_valid(target) and target.is_visible_in_tree():
				target.grab_focus())

## §39: 新規stage(current_stage_id空)か保存済みstageかでボタン構成を切り替える。
func open() -> void:
	_error_label.text = ""
	_pending_same_name_action = ""
	_same_name_panel.visible = false
	_success_panel.visible = false
	_choice_panel.visible = true
	_boss_name_label.text = main.draft.boss_name
	var has_current_stage: bool = not main.current_stage_id.is_empty()
	_save_new_button.visible = not has_current_stage
	_overwrite_button.visible = has_current_stage
	_save_as_new_button.visible = has_current_stage
	_set_boss_window_title(tr("保存するボス"))
	_refresh_boss()
	# 最初のフォーカスは安全な側（上書きは置かない。UI_UX §12/§13）
	_present(_choice_panel, _back_button if has_current_stage else _save_new_button)

func _on_back_pressed() -> void:
	return_to_creator_requested.emit()

func _set_boss_window_title(text: String) -> void:
	var title := _boss_window.find_child("WindowTitle", false, false) as Label
	if title != null:
		title.text = text

## Esc（PX-13、2026-10-18）: 同じ名前の確認はキャンセル、保存のしかたを選ぶ欄は「戻る」。保存できた画面では何もしない。
func _unhandled_input(event: InputEvent) -> void:
	if not Escape.pressed(self, event):
		return
	if _same_name_panel.visible:
		Escape.consume(self)
		_on_same_name_cancelled()
	elif _choice_panel.visible:
		Escape.consume(self)
		_on_back_pressed()

# --- §23 新規stageの初回保存 / §25 新しいボスとして保存 ---
# Repository視点では同一操作（save_new）——ボタンの見た目だけが異なる。

func _on_save_new_pressed() -> void:
	_try_save_new()

func _on_save_as_new_pressed() -> void:
	_try_save_new()

func _try_save_new() -> void:
	if bool(main.boss_name_already_saved_elsewhere()):
		_pending_same_name_action = "save_new"
		_choice_panel.visible = false
		_same_name_panel.visible = true
		# 確認の最初のフォーカスは安全な側（キャンセル。UI_UX §13）
		_present(_same_name_panel, _same_name_cancel_button)
		return
	_do_save_new()

func _on_same_name_confirmed() -> void:
	_same_name_panel.visible = false
	if _pending_same_name_action == "save_new":
		_do_save_new()
	_pending_same_name_action = ""

func _on_same_name_cancelled() -> void:
	_same_name_panel.visible = false
	_choice_panel.visible = true
	_pending_same_name_action = ""
	_present(_choice_panel, _back_button if _overwrite_button.visible else _save_new_button)

func _do_save_new() -> void:
	var result: Dictionary = main.press_save_as_new()
	if not bool(result.get("ok", false)):
		# 同じ名前の確認から来た時は、選ぶ欄を出し直す
		var was_hidden := not _choice_panel.visible
		_choice_panel.visible = true
		preload("res://src/bossmaker/rbm_audio.gd").cue(self, "ui_error")
		_error_label.text = _failure_text(result)
		if was_hidden:
			_present(_choice_panel, _back_button)
		return
	_show_success(str(result.get("stage_id", "")))

# --- §24 上書き保存（自分自身と同名なのは当然なので同名警告なし、§26末尾） ---

func _on_overwrite_pressed() -> void:
	var result: Dictionary = main.press_overwrite_save()
	if not bool(result.get("ok", false)):
		preload("res://src/bossmaker/rbm_audio.gd").cue(self, "ui_error")
		_error_label.text = _failure_text(result)
		return
	_show_success(main.current_stage_id)

## 保存できなかった理由（回復量の上限など、理由の文があればそれを出す）。
func _failure_text(result: Dictionary) -> String:
	var message := str(result.get("message", ""))
	return tr("保存に失敗しました") if message.is_empty() else tr("保存できません：%s") % message

func _show_success(stage_id: String) -> void:
	preload("res://src/bossmaker/rbm_audio.gd").cue(self, "ui_save")
	_choice_panel.visible = false
	_same_name_panel.visible = false
	_success_panel.visible = true
	_success_stage_id_label.text = tr("ステージID：%s") % stage_id
	# 保存した後は「保存したボス」（以前は「保存するボス」のままだった、2026-10-18）
	_set_boss_window_title(tr("保存したボス"))
	_refresh_boss()
	_present(_success_panel, _success_return_button)

## 実機プレイ改善③ item4: 保存成功後「クリエイター一覧に戻る」は、STEP7等の
## 中間STEPを一切経由せず、保存済みボス一覧（RBMCreatorEntryの「保存した
## ボス戦を編集」一覧画面）へ直接戻る。保存成功→Creator（STEP7）→
## クリエイター一覧、という無駄な1操作を無くすための専用シグナル
## （RBMCreatorMain._on_save_return_to_creator_list()参照）。保存内容・
## stage_id・未保存変更状態はこのシグナル発火より前（_do_save_new()/
## _on_overwrite_pressed()）で既に確定済みのため、ここでは一切触れない。
func _on_success_return_pressed() -> void:
	return_to_creator_list_requested.emit()
