class_name RBMCreatorEntry
extends Control

## Phase 1 Step 6 §29〜§33/§36/§37/§41 — CREATEの入口。
## 「新しいボス戦を作る」/「保存したボス戦を編集」の2系統と、後者から開く
## ローカル保存stage一覧（検索・削除つき、CHALLENGE一覧とは別画面、§31/§47）。
##
## RBMCreatorMainを1つだけ保持し続け（構築のたびに破棄・再構築しない）、
## start_new()/start_loaded()で中身のフィールドだけを差し替える——これは
## RBMCreatorMain側の設計（STEPビュー群が保持するdraft参照を維持したまま
## フィールドだけ書き換える）とセットで、UI二重構築を避けるための構成。
##
## 見た目の刷新（2026-10、ユーザーが完成イメージで承認）: 入口・作成方法の選択・保存したボス戦の一覧の
## 3画面を、挑戦側のオンライン一覧と同じ紺＋水色（RBMMenuUi／RBMChallengeListStyle）にした。
## 城の扉・工房の背景画像は使わず、図形だけの地（RBMMenuUi.Backdrop）に置く。
##   入口           = 2枚の大きなカード（RBMCreatorTopChoice。選んだ方が広がる）
##   作成方法の選択 = SIMPLE／HARDCORE の大きなカード（設定できることの一覧つき）
##   一覧           = 左にカード（RBMSavedBossCard）、右に詳細（RBMSavedBossDetailPanel）。
##                    オンライン一覧のカード・詳細をそのまま土台にして、中身と操作（編集する・削除）だけ差し替える。
## 画面の切り替え・検索の条件・開く・削除の処理（確認つき）は従来のまま。
## 3画面とも RBMWorldUi.walk() の金への再配色を受けない（各画面のルートに meta "world_skip"）。

## Phase 1 Step 8 §4 — 共通ルートへ戻る要求。RBMCreatorMain自身の`exited`
## シグナル（既存・無改修、未保存変更警告を含む正式な退出処理の完了通知）
## とは別物——こちらはCREATE自体（RBMCreatorEntryのTOP画面）から共通ルート
## 画面へ戻る、Step 8で新設した1段外側の退出経路。共通ルート側がCreatorを
## 強制的に非表示にして既存の未保存変更警告を迂回することは無い——TOP画面へ
## 到達できる唯一の経路は既存のpress_exit_creator()（未保存変更警告を含む）
## がexitedを発火した後だけであり、このexit_requestedはその後にのみ発火する。
signal exit_requested

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const M := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
const Escape = preload("res://src/bossmaker/rbm_escape.gd")

## RBMCreatorGuideCharacterの表示scale/position（案内役の部品は残してあり、今の画面では使っていない）。
const GUIDE_CHARACTER_SCALE := 0.50
const GUIDE_CHARACTER_POSITION := Vector2(76.0, 19.0)

## 入口の2枚のカードの左上（全体 1152×480、RBMCreatorTopChoice）。
const TOP_CHOICE_POSITION := Vector2(64, 150)
## 作成方法の選択のカード。2026-10-29: 「設定できること」の一覧を外したので、高さを中身（区分・名前・説明・始めるボタン）に
## 合わせて 470→340 に詰め、以前のカードと同じ縦の中心（156＋470÷2）に置く。
const MODE_CARD_SIZE := Vector2(600, 340)
const MODE_CARD_TOP := 221.0
const MODE_CARD_STEP := 632.0
## 説明の欄の高さ（英語の HARDCORE の説明が3行になっても、下の「この方法で作成を始める」と重ならない）。
const DESCRIPTION_HEIGHT := 100.0
## 保存したボス戦の一覧の左右の欄・検索欄（挑戦側のオンライン一覧と同じ位置・大きさ）。
const LIST_RECT := Rect2(24, 92, 444, 612)
const DETAIL_RECT := Rect2(484, 92, 772, 612)
const NAME_SEARCH_RECT := Rect2(818, 21, 240, 40)
const ID_SEARCH_RECT := Rect2(1066, 21, 190, 40)
const DELETE_DIALOG_SIZE := Vector2(560, 272)

var main: RBMCreatorMain

var _top_panel: Control
var _top_choice: RBMCreatorTopChoice
## 入口の保存件数を、次に入口が見えた時に数え直すか。起動時の画面の作成では保存データを読まず、
## 最初に入口が見えた時・Creator から戻った時（保存した可能性がある）だけ数え直す。
## 一覧を読み込んだ時（削除の後も）は、その行から数えて入口へ渡す。
var _top_counts_dirty := true
var _mode_choice_panel: Control
var _mode_choice_content_built := false
var _guide_character: RBMCreatorGuideCharacter
var _list_panel: Control
var _name_search_field: LineEdit
var _id_search_field: LineEdit
var _list_rows: VBoxContainer
var _list_scroll: ScrollContainer
var _list_count_label: Label
var _list_warning: Panel
var _list_warning_label: Label
var _list_empty: Control
var _list_no_match: Control
var _saved_detail: RBMSavedBossDetailPanel
## 一覧で選んでいるボス戦と、一覧の各行（stage_id -> _saved_entries() の1件）。
var _selected_stage_id := ""
var _entries_by_id: Dictionary = {}
## 一覧に読み込んだ行（最終更新の新しい順）と、そのカード（stage_id -> RBMSavedBossCard）。
## 検索で外れたカードは隠すだけで作り直さない（_refresh_list() 参照）。
var _entries: Array = []
var _cards: Dictionary = {}
var _unreadable_count := 0
## 「覚醒」の札: ファイルの版（"stage_id:最終更新"）-> 覚醒するか。
var _awakening_by_version: Dictionary = {}

var _delete_confirm_panel: Control
var _delete_confirm_label: Label
var _delete_confirm_id_label: Label
var _delete_confirm_thumbnail: TextureRect
var _delete_cancel_button: Button
var _delete_target_stage_id: String = ""

func _ready() -> void:
	_build_ui()
	var world = preload("res://src/bossmaker/rbm_world_ui.gd").new()
	world.walk(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_refresh_top_counts_if_visible()

func _build_ui() -> void:
	# Phase 3.5 UI統一§0/§5/§9: RBMCreatorEntry自身がCREATE全体の唯一のルートControlのため、
	# ここへ明示適用するだけでCREATE配下（Creator本体のSTEP画面など）すべてへカスケードする。
	theme = RBMUiTheme.build_theme()
	RBMBattleUiKit.add_root_background(self)

	_build_top_panel()
	_build_mode_choice_panel()
	_build_list_panel()

	main = RBMCreatorMain.new()
	main.name = "CreatorMain"
	## Step 8 最終修正 §1: mainはこのControl(RBMCreatorEntry)自身へ無アンカーの
	## まま加えられており、bareなControlの子は親のサイズを自動で継承しない
	## ため、mainのサイズが(0,0)のままだった。RBMCreatorMain内部で
	## root_column（STEPナビゲーション全体を統括する最上位VBoxContainer）を
	## FULL_RECTでmain自身に固定しても、main自体が(0,0)であれば無意味になる
	## ——このアンカーがSTEP1〜7全体の重なり修正の前提となる大元の1行。
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.visible = false
	add_child(main)
	main.exited.connect(_on_creator_exited)
	# 実機プレイ改善③ item4: 保存成功後「クリエイター一覧に戻る」専用の
	# 退出経路——既存の_on_creator_exited()（TOP画面へ戻る）とは別に、
	# 保存済みボス一覧を直接開く。
	main.exited_to_saved_list.connect(_on_creator_exited_to_saved_list)

	_show_top()

## 画面1枚分の層（全画面、地つき）。
func _screen_layer(node_name: String, background_name: String) -> Control:
	var layer := Control.new()
	layer.name = node_name
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_meta("world_skip", true)
	add_child(layer)
	M.add_backdrop(layer, background_name)
	return layer

# ---------------------------------------------------------------------------
# 入口（ボス戦を作成）
# ---------------------------------------------------------------------------

func _build_top_panel() -> void:
	_top_panel = _screen_layer("EntryTopPanel", "EntryBackground")
	## Step 8 §4: CREATE自体を終了し共通ルート画面へ戻る（左上、各画面と同じ位置）。
	var back_to_root_button := Button.new()
	back_to_root_button.name = "BackToRootButton"
	back_to_root_button.pressed.connect(_on_back_to_root_pressed)
	M.header(_top_panel, back_to_root_button, tr("戻る"), tr("ボス戦を作成"), tr("新しく作るか、保存したボス戦を編集します"), "EntryTitleLabel", "EntryDescriptionLabel")

	_top_choice = RBMCreatorTopChoice.new()
	_top_choice.name = "EntryChoice"
	_top_choice.position = TOP_CHOICE_POSITION
	_top_panel.add_child(_top_choice)
	_top_choice.new_card.pressed.connect(_on_new_pressed)
	_top_choice.edit_card.pressed.connect(_on_edit_saved_pressed)

## 表示が切り替わる最中（NOTIFICATION_VISIBILITY_CHANGED）は子の is_visible_in_tree() がまだ古いため、
## 自分が見えていることと、入口の層そのものの visible で判断する。
func _refresh_top_counts_if_visible() -> void:
	if not _top_counts_dirty or _top_panel == null or not is_visible_in_tree() or not _top_panel.visible:
		return
	_top_counts_dirty = false
	_top_choice.set_counts(_counts_of(RBMLocalStageRepository.list()))

## 入口の「保存済み N件（うち下書き N件）」と内訳。
func _counts_of(entries: Array) -> Dictionary:
	var counts := {"total": 0, "draft": 0, "playable": 0, "clear_checked": 0, "published": 0}
	for entry in entries:
		counts["total"] += 1
		var status := str(entry.get("status", "draft"))
		if counts.has(status):
			counts[status] += 1
		if bool(entry.get("online_published", false)):  # オンラインに公開しているボス（PX-05）
			counts["published"] += 1
	return counts

# ---------------------------------------------------------------------------
# 作成方法の選択
# ---------------------------------------------------------------------------

## UI改善②: 「新しいボス戦を作る」を押した直後、STEP1へ進む前にSIMPLE/
## ADVANCEDのどちらで作るかをここで一度だけ選ばせる——以後、STEP1〜7の
## 途中でモード切替UIを常時見せない（切替が必要になった場合はSTEP7の
## 最終確認画面から行う、RBMCreatorStep7Summary._on_switch_mode_button_
## pressed()参照）。
##
## 中身はこの画面を初めて表示する直前（_show_mode_choice()）まで作らない——
## RBMCreatorEntryを生成するテストの大半はこの画面を一度も開かないため。
func _build_mode_choice_panel() -> void:
	_mode_choice_panel = Control.new()
	_mode_choice_panel.name = "ModeChoicePanel"
	_mode_choice_panel.visible = false
	_mode_choice_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mode_choice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_choice_panel.set_meta("world_skip", true)
	add_child(_mode_choice_panel)

func _ensure_mode_choice_content_built() -> void:
	if _mode_choice_content_built:
		return
	_mode_choice_content_built = true
	M.add_backdrop(_mode_choice_panel, "Background")
	var back := Button.new()
	back.name = "ModeChoiceBackButton"
	back.pressed.connect(_on_mode_choice_back_pressed)
	M.header(_mode_choice_panel, back, tr("ボス戦を作成"), tr("ボスを作る方法を選択"), "", "ModeChoiceTitleLabel")

	# 決める前に知っておくこと（作成開始後はモードを変更できない）と、迷った時の目安。
	var notice := Panel.new()
	notice.name = "MethodHeadingPanel"
	notice.position = Vector2(24, 92)
	notice.size = Vector2(1232, 44)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_theme_stylebox_override("panel", S.box(Color(S.INSET, 0.94), Color("1a2830")))
	_mode_choice_panel.add_child(notice)
	S.rect(notice, Rect2(0, 0, 3, 44), S.ACCENT)
	S.label(notice, tr("作成開始後はモードを変更できません"), Rect2(20, 7, 640, 30), 15, S.TEXT, "ModeChoiceHintLabel")
	var advice := S.label(notice, tr("迷ったら SIMPLE から始めるのがおすすめです"), Rect2(620, 7, 592, 30), 13, S.MUTED, "ModeChoiceAdviceLabel")
	advice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 2026-10-29 ユーザー確定の説明文（日本語はこの文のまま。句読点を足さない。HARDCORE は2文を改行して出す）。
	# 以前の「設定できること」の一覧（「SIMPLE で設定できることすべて」など）は、誤解を招くため外した。
	_mode_card(0, "SIMPLE", tr("シンプルで作る"), tr("使用率や指定ターンを設定して手軽にボスを作成"), S.SILVER, "ChooseSimpleModeButton",
		_on_choose_simple_mode_pressed)
	_mode_card(1, "HARDCORE", tr("ハードコアで作る"),
		"%s\n%s" % [tr("ターンごとの行動や複雑な発動条件を組み合わせボスの戦術を自由に設計"), tr("特殊な勝利条件も設定できる上級者向けモード")],
		S.HARD, "ChooseAdvancedModeButton", _on_choose_advanced_mode_pressed)

## SIMPLE／HARDCORE のカード。文字はすべて子の Label（Button.text は空）。カード全体が押せる。
func _mode_card(index: int, category: String, title: String, description: String, color: Color, node_name: String, callback: Callable) -> void:
	var card := Button.new()
	card.name = node_name
	card.position = Vector2(24 + index * MODE_CARD_STEP, MODE_CARD_TOP)
	card.size = MODE_CARD_SIZE
	M.card_styles(card, false)
	M.accessible_name(card, title)
	card.pressed.connect(callback)
	_mode_choice_panel.add_child(card)
	M.accent_bar(card, color, MODE_CARD_SIZE.y)
	M.number_font(S.label(card, category, Rect2(32, 26, 400, 56), 40, color, "CategoryLabel"))
	S.label(card, title, Rect2(32, 86, 520, 32), 21, S.TEXT, "TitleLabel")
	S.rect(card, Rect2(24, 134, 552, 1), Color(S.PANEL_EDGE, 0.9), "Rule")
	var desc := S.label(card, description, Rect2(32, 154, 544, DESCRIPTION_HEIGHT), 15, S.SILVER, "DescriptionLabel")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.add_theme_constant_override("line_spacing", 8)
	desc.size = Vector2(544, DESCRIPTION_HEIGHT)  # 折り返しを入れる前に文の長さへ広がった幅を、カードの中の幅へ戻す（英語の長い文）
	var cta := M.cta_strip(card, Rect2(20, MODE_CARD_SIZE.y - 76, 560, 56), tr("この方法で作成を始める"), 17)
	M.on_highlight(card, func(on: bool) -> void: cta.set_lit(1.0 if on else 0.0, 1.0 if on else 0.0))
	# 体験版: HARDCORE は製品版限定（押せない。札と帯の文で知らせる）。製品版は今までどおり。
	if node_name == "ChooseAdvancedModeButton" and not RBMEdition.allows_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED):
		card.disabled = true
		card.mouse_default_cursor_shape = Control.CURSOR_ARROW
		M.tag(card, tr("製品版限定"), Vector2(MODE_CARD_SIZE.x - 132, 30), S.HARD, S.HARD_EDGE, Color(S.INSET, 0.9), false, "FullVersionOnlyTag")
		cta.label.text = tr("製品版で利用できます")

# ---------------------------------------------------------------------------
# 保存したボス戦の一覧
# ---------------------------------------------------------------------------

func _build_list_panel() -> void:
	_list_panel = _screen_layer("EntryListPanel", "ListBackground")
	_list_panel.visible = false

	var list_back_button := Button.new()
	list_back_button.name = "ListBackButton"
	list_back_button.pressed.connect(_on_list_back_pressed)
	M.header(_list_panel, list_back_button, tr("ボス戦を作成"), tr("保存したボス戦を編集"), "", "EntryListTitleLabel")

	_name_search_field = _search_field("NameSearchField", tr("ボス名で検索"), NAME_SEARCH_RECT)
	_id_search_field = _search_field("IdSearchField", tr("ステージIDで検索"), ID_SEARCH_RECT)

	var panel := Panel.new()
	panel.name = "SavedListPanel"
	panel.position = LIST_RECT.position
	panel.size = LIST_RECT.size
	panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.96), S.PANEL_EDGE))
	_list_panel.add_child(panel)
	S.section_title(panel, tr("保存したボス戦"), Vector2(16, 12))
	_list_count_label = S.label(panel, "", Rect2(170, 12, LIST_RECT.size.x - 186, 28), 12, S.MUTED, "SavedCountLabel")
	_list_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 読み込めなかったファイルがあった時の一言（一覧は残す。壊れたファイルは従来どおり一覧に出さない、§43）。
	_list_warning = Panel.new()
	_list_warning.name = "SavedUnreadableWarning"
	_list_warning.position = Vector2(12, 50)
	_list_warning.size = Vector2(LIST_RECT.size.x - 24, 40)
	_list_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_warning.add_theme_stylebox_override("panel", S.box(Color(S.HARD_EDGE, 0.16), Color(S.HARD_EDGE, 0.8)))
	_list_warning.visible = false
	panel.add_child(_list_warning)
	_list_warning_label = S.label(_list_warning, "", Rect2(12, 0, _list_warning.size.x - 24, 40), 12, S.HARD, "SavedUnreadableLabel")

	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "SavedListScroll"
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	S.style_scrollbar(_list_scroll.get_v_scroll_bar())
	panel.add_child(_list_scroll)
	# 操作対象の白い枠(カードの外側3px)が切れないよう、左右と上に少し余白を取る（オンライン一覧と同じ）。
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top"]:
		margin.add_theme_constant_override(side, 4)
	_list_scroll.add_child(margin)
	_list_rows = VBoxContainer.new()
	_list_rows.name = "StageListRows"
	_list_rows.add_theme_constant_override("separation", 10)
	margin.add_child(_list_rows)

	_list_empty = _list_message(panel, "SavedListEmpty", tr("保存したボス戦はまだありません"), tr("「ボス戦を作成」の「新しいボス戦を作る」から作成し、\n保存するとここに並びます。"))
	_list_no_match = _list_message(panel, "SavedListNoMatch", tr("条件に合うボス戦はありません"), tr("ボス名は一部だけでも探せます。\nステージIDは10桁すべてを入力してください。"))
	var clear := Button.new()
	clear.name = "SavedListClearSearchButton"
	clear.text = tr("検索をクリア")
	clear.add_theme_font_size_override("font_size", 15)
	S.button_style(clear)
	clear.focus_mode = Control.FOCUS_ALL
	clear.pressed.connect(_on_clear_search_pressed)
	_list_no_match.add_child(clear)
	clear.size = Vector2(maxf(200.0, clear.get_combined_minimum_size().x), 42)
	clear.position = Vector2((LIST_RECT.size.x - clear.size.x) / 2.0, 312)

	_saved_detail = RBMSavedBossDetailPanel.new()
	_saved_detail.name = "SavedBossDetailPanel"
	_saved_detail.position = DETAIL_RECT.position
	_saved_detail.size = DETAIL_RECT.size
	_saved_detail.edit_pressed.connect(_on_detail_edit_pressed)
	_saved_detail.delete_pressed.connect(_on_detail_delete_pressed)
	_list_panel.add_child(_saved_detail)

	_build_delete_confirm_panel()

func _search_field(node_name: String, placeholder: String, area: Rect2) -> LineEdit:
	var field := LineEdit.new()
	field.name = node_name
	field.placeholder_text = placeholder
	field.position = area.position
	field.size = area.size
	field.clear_button_enabled = true
	M.search_field(field)
	field.text_changed.connect(func(_new_text: String): _refresh_list(false))
	_list_panel.add_child(field)
	return field

## 一覧の欄の中央に出す一言（0件・一致なし）。
func _list_message(panel: Control, node_name: String, title: String, hint: String) -> Control:
	var box := Control.new()
	box.name = node_name
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = LIST_RECT.size
	box.visible = false
	panel.add_child(box)
	var t := S.label(box, title, Rect2(8, 222, LIST_RECT.size.x - 16, 28), 16, S.TEXT, "MessageTitle")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h := S.label(box, hint, Rect2(24, 254, LIST_RECT.size.x - 48, 48), 13, S.MUTED, "MessageHint")
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return box

## 削除の確認（画面全体を暗くした上の中央のダイアログ）。最初の操作対象は安全な「キャンセル」（UI_UX §13）。
func _build_delete_confirm_panel() -> void:
	_delete_confirm_panel = Control.new()
	_delete_confirm_panel.name = "DeleteConfirmPanel"
	_delete_confirm_panel.visible = false
	_delete_confirm_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_delete_confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_list_panel.add_child(_delete_confirm_panel)
	var shade := ColorRect.new()
	shade.name = "DeleteConfirmShade"
	shade.color = Color(0.02, 0.03, 0.05, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_delete_confirm_panel.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dialog := Panel.new()
	dialog.name = "DeleteConfirmDialog"
	dialog.size = DELETE_DIALOG_SIZE
	dialog.position = ((Vector2(1280, 720) - DELETE_DIALOG_SIZE) / 2.0).floor()
	var box := S.box(S.PANEL, Color(S.HARD_EDGE, 0.95))
	box.shadow_color = Color(0, 0, 0, 0.6)
	box.shadow_size = 12
	dialog.add_theme_stylebox_override("panel", box)
	_delete_confirm_panel.add_child(dialog)
	S.rect(dialog, Rect2(0, 0, DELETE_DIALOG_SIZE.x, 3), S.HARD_EDGE)
	S.label(dialog, tr("このボス戦を削除しますか？"), Rect2(28, 22, 504, 36), 21, S.TEXT, "DeleteConfirmTitle")
	_delete_confirm_thumbnail = TextureRect.new()
	_delete_confirm_thumbnail.name = "DeleteConfirmThumbnail"
	_delete_confirm_thumbnail.position = Vector2(28, 74)
	_delete_confirm_thumbnail.size = Vector2(64, 64)
	_delete_confirm_thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_delete_confirm_thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_delete_confirm_thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_delete_confirm_thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(_delete_confirm_thumbnail)
	_delete_confirm_label = S.label(dialog, "", Rect2(108, 76, 424, 30), 18, S.TEXT, "DeleteConfirmLabel")
	_delete_confirm_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_delete_confirm_label.clip_text = true
	_delete_confirm_id_label = S.label(dialog, "", Rect2(108, 106, 424, 24), 13, S.MUTED, "DeleteConfirmStageId")
	M.number_font(_delete_confirm_id_label)
	var warning := S.label(dialog, tr("この操作は取り消せません。保存したデータは元に戻せなくなります。"), Rect2(28, 150, 504, 44), 14, S.HARD, "DeleteConfirmWarning")
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_delete_cancel_button = Button.new()
	_delete_cancel_button.name = "DeleteCancelButton"
	_delete_cancel_button.text = tr("キャンセル")
	_delete_cancel_button.add_theme_font_size_override("font_size", 15)
	S.button_style(_delete_cancel_button)
	_delete_cancel_button.focus_mode = Control.FOCUS_ALL
	_delete_cancel_button.pressed.connect(_on_delete_cancelled)
	dialog.add_child(_delete_cancel_button)
	var confirm := Button.new()
	confirm.name = "DeleteConfirmButton"
	confirm.text = tr("削除する")
	confirm.add_theme_font_size_override("font_size", 15)
	M.danger_style(confirm)
	confirm.pressed.connect(_on_delete_confirmed)
	dialog.add_child(confirm)
	for b in [_delete_cancel_button, confirm]:
		b.size = Vector2(maxf(150.0, b.get_combined_minimum_size().x), 46)
	confirm.position = Vector2(DELETE_DIALOG_SIZE.x - 28 - confirm.size.x, DELETE_DIALOG_SIZE.y - 28 - 46)
	_delete_cancel_button.position = Vector2(confirm.position.x - 12 - _delete_cancel_button.size.x, confirm.position.y)
	# ダイアログが開いている間、キーボードの操作対象が後ろの画面へ出ないよう、2つのボタンの間だけで動かす。
	for pair in [[_delete_cancel_button, confirm], [confirm, _delete_cancel_button]]:
		var from: Button = pair[0]
		var to: Button = pair[1]
		var path := from.get_path_to(to)
		from.focus_neighbor_left = path
		from.focus_neighbor_right = path
		from.focus_next = path
		from.focus_previous = path
		from.focus_neighbor_top = NodePath(".")
		from.focus_neighbor_bottom = NodePath(".")

# ---------------------------------------------------------------------------
# §30: 新しいボス戦を作る
# ---------------------------------------------------------------------------

func _on_new_pressed() -> void:
	_show_mode_choice()

## start_new()自体がdraft.restore_from_saved_dict({})経由でcreator_modeを
## 既定(SIMPLE)へリセットする——選んだモードの反映は必ずstart_new()の後で
## 行う（先に設定してもstart_new()に上書きされてしまうため）。
func _on_choose_simple_mode_pressed() -> void:
	main.start_new()
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	_mode_choice_panel.visible = false
	_show_creator()

func _on_choose_advanced_mode_pressed() -> void:
	if not RBMEdition.allows_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED):
		return
	main.start_new()
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	_mode_choice_panel.visible = false
	_show_creator()

func _on_mode_choice_back_pressed() -> void:
	_mode_choice_panel.visible = false
	_show_top()

# ---------------------------------------------------------------------------
# §31/§32/§33: 保存したボス戦を編集（一覧・検索）
# ---------------------------------------------------------------------------

func _on_edit_saved_pressed() -> void:
	_show_list()

## 一覧に出す行: RBMLocalStageRepository.list()（壊れたファイルは静かに除外済み、§43）の各行に、
## カードの「覚醒」の札のための awakening を足し、最終更新の新しい順に並べたもの。
## awakening はファイルの版（stage_id と最終更新）ごとに覚えておき、変わっていないファイルは読み直さない。
func _saved_entries() -> Array:
	var entries: Array = []
	for row in RBMLocalStageRepository.list():
		var entry: Dictionary = row.duplicate()
		var stage_id := str(row.get("stage_id", ""))
		var version := "%s:%d" % [stage_id, int(row.get("updated_unix_time", 0))]
		if not _awakening_by_version.has(version):
			var awakening := false
			var loaded := RBMLocalStageRepository.load_stage(stage_id)
			if bool(loaded.get("ok", false)):
				var draft := RBMCreatorDraft.new()
				draft.restore_from_saved_dict(loaded.get("draft_data", {}))
				# ボスの覚醒は SIMPLE でも設定できる（2026-10-29 ユーザー確定）ので、モードでは分けない。
				awakening = draft.has_awakening() and draft.supports_awakening()
			_awakening_by_version[version] = awakening
		entry["awakening"] = _awakening_by_version[version]
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a.get("updated_unix_time", 0))
		var tb := int(b.get("updated_unix_time", 0))
		if ta != tb:
			return ta > tb
		return str(a.get("stage_id", "")) < str(b.get("stage_id", "")))
	return entries

## 保存先にあるのに読み込めなかった（壊れている・形が違う）ボス戦の数。
func _unreadable_stage_count(readable_count: int) -> int:
	var dir := RBMLocalStageRepository.stages_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var files := 0
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".json") and _looks_like_stage_id(file_name.get_basename()):
			files += 1
	return maxi(0, files - readable_count)

static func _looks_like_stage_id(text: String) -> bool:
	if text.length() != 10:
		return false
	for i in range(text.length()):
		if not "0123456789".contains(text[i]):
			return false
	return true

## §32: 下書きも含めすべて表示、状態は都度算出（RBMLocalStageRepository.list()
## 自身が既にstatusをdraft/playable/clear_checkedとして返す）。
## §33: ボス名は大文字小文字を区別しない部分一致、stage_idは10桁完全一致。
## reload = 保存先から読み直す（一覧を開いた時・削除の後）。検索欄の入力では読み直さず、
## 読み込み済みの行を絞り込むだけ（保存データは一覧を開いている間に、この画面の外では変わらない）。
## カードは1件につき1枚を使い回し、検索で外れたカードは隠す（作り直さない）。読み直した時は、
## 内容が変わったカードと条件に合わないカードだけを捨てる。_list_rows の見えている子が、表示中の行。
func _refresh_list(reload: bool = true) -> void:
	if reload:
		_reload_entries()
	var name_query := _name_search_field.text
	var id_query := _id_search_field.text
	var shown := 0
	for entry in _entries:
		var stage_id := str(entry.get("stage_id", ""))
		var card: RBMSavedBossCard = _cards.get(stage_id)
		var boss_name := str(entry.get("boss_name", ""))
		var matches := (name_query.is_empty() or boss_name.to_lower().contains(name_query.to_lower())) and (id_query.is_empty() or stage_id == id_query)
		if matches:
			if card == null:
				card = _add_stage_row(entry)
			card.visible = true
			card.set_selected(stage_id == _selected_stage_id)
			_list_rows.move_child(card, shown)
			shown += 1
		elif card != null:
			if reload:
				_drop_card(stage_id)
			else:
				card.visible = false
	_update_list_state(_entries.size(), shown, _unreadable_count)
	if not _selected_stage_id.is_empty() and _find_row(_selected_stage_id) == null:
		_selected_stage_id = ""
	if _selected_stage_id.is_empty():
		_saved_detail.show_empty(shown > 0)

## 保存先から読み直す。内容が変わった・無くなったボス戦のカードは捨てる。入口の件数も同じ行から数え直す。
func _reload_entries() -> void:
	_entries = _saved_entries()
	var previous := _entries_by_id
	_entries_by_id = {}
	for entry in _entries:
		_entries_by_id[str(entry.get("stage_id", ""))] = entry
	for stage_id in _cards.keys():
		if not _entries_by_id.has(stage_id) or previous.get(stage_id, {}) != _entries_by_id[stage_id]:
			_drop_card(stage_id)
	_unreadable_count = _unreadable_stage_count(_entries.size())
	_top_choice.set_counts(_counts_of(_entries))
	_top_counts_dirty = false

func _drop_card(stage_id: String) -> void:
	var card: Node = _cards.get(stage_id)
	_cards.erase(stage_id)
	if is_instance_valid(card):
		card.get_parent().remove_child(card)
		card.queue_free()

## 件数・0件・一致なし・読み込めないファイルの表示。
func _update_list_state(total: int, shown: int, unreadable: int) -> void:
	if total == 0:
		_list_count_label.text = ""
	elif shown == total:
		_list_count_label.text = tr("%d件 / 更新が新しい順") % total
	else:
		_list_count_label.text = tr("%d件が一致 / 全%d件") % [shown, total]
	_list_warning.visible = unreadable > 0
	_list_warning_label.text = tr("読み込めないボス戦が%d件あります（ファイルが壊れている可能性）") % unreadable
	var top := 98.0 if unreadable > 0 else 52.0
	_list_scroll.position = Vector2(8, top)
	_list_scroll.size = Vector2(LIST_RECT.size.x - 12, LIST_RECT.size.y - top - 8)
	_list_scroll.visible = shown > 0
	_list_empty.visible = total == 0
	_list_no_match.visible = total > 0 and shown == 0

## 1件のカードを作る。押すと右に詳細を出す（開く・削除は詳細の「編集する」「削除」から）。
func _add_stage_row(entry: Dictionary) -> RBMSavedBossCard:
	var card := RBMSavedBossCard.new()
	# 先に一覧へ入れてから中身を作る（札を横に並べる時の文字の幅は、画面の文字の設定が届いてから測る）。
	_list_rows.add_child(card)
	card.setup_saved(entry)
	card.pressed.connect(_on_stage_card_pressed.bind(card.stage_id))
	_cards[card.stage_id] = card
	return card

## 表示中（検索で隠れていない）のカード。
func _find_row(stage_id: String) -> RBMSavedBossCard:
	var card: RBMSavedBossCard = _cards.get(stage_id)
	return card if card != null and card.visible else null

func _on_stage_card_pressed(stage_id: String) -> void:
	_selected_stage_id = stage_id
	for child in _list_rows.get_children():
		if child is RBMSavedBossCard:
			(child as RBMSavedBossCard).set_selected((child as RBMSavedBossCard).stage_id == stage_id)
	var summary := _detail_summary(stage_id)
	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	if not bool(loaded.get("ok", false)):
		_saved_detail.show_open_error(summary)
		return
	var draft := RBMCreatorDraft.new()
	draft.restore_from_saved_dict(loaded.get("draft_data", {}))
	_saved_detail.show_boss(summary, draft)

## 詳細に渡す行（名前が空なら「（名前未設定）」）。
func _detail_summary(stage_id: String) -> Dictionary:
	var summary: Dictionary = (_entries_by_id.get(stage_id, {"stage_id": stage_id}) as Dictionary).duplicate()
	if str(summary.get("boss_name", "")).is_empty():
		summary["boss_name"] = tr("（名前未設定）")
	return summary

func _on_detail_edit_pressed() -> void:
	if not _selected_stage_id.is_empty():
		_on_open_stage_pressed(_selected_stage_id)

func _on_detail_delete_pressed() -> void:
	if not _selected_stage_id.is_empty():
		_on_delete_stage_pressed(_selected_stage_id, str(_detail_summary(_selected_stage_id).get("boss_name", "")))

func _on_clear_search_pressed() -> void:
	_name_search_field.text = ""
	_id_search_field.text = ""
	_refresh_list()
	if _name_search_field.is_visible_in_tree():
		_name_search_field.grab_focus()

## §34/§43: 破損/存在しないstageならstart_loaded()が{"ok":false}を返す——
## クラッシュせず一覧画面に留まり、詳細に開けなかったことを出す。他の健全なstageは引き続き利用できる。
func _on_open_stage_pressed(stage_id: String) -> void:
	var result := main.start_loaded(stage_id)
	if bool(result.get("ok", false)):
		_show_creator()
	else:
		_saved_detail.show_open_error(_detail_summary(stage_id))

# ---------------------------------------------------------------------------
# §41/§42: 削除
# ---------------------------------------------------------------------------

func _on_delete_stage_pressed(stage_id: String, boss_name: String) -> void:
	_delete_target_stage_id = stage_id
	var entry: Dictionary = _entries_by_id.get(stage_id, {})
	_delete_confirm_label.text = boss_name if not boss_name.is_empty() else tr("（名前未設定）")
	_delete_confirm_id_label.text = tr("ステージID %s") % stage_id
	_delete_confirm_thumbnail.texture = S.fitted_sprite(RBMVisualAssets.boss_asset(str(entry.get("appearance_id", ""))), Vector2(64, 64))
	_delete_confirm_panel.visible = true
	if _delete_cancel_button.is_visible_in_tree():
		_delete_cancel_button.grab_focus()

func _on_delete_confirmed() -> void:
	RBMLocalStageRepository.delete(_delete_target_stage_id)
	if _delete_target_stage_id == _selected_stage_id:
		_selected_stage_id = ""
	_delete_confirm_panel.visible = false
	_delete_target_stage_id = ""
	_refresh_list()
	_focus_list_after_dialog()

func _on_delete_cancelled() -> void:
	_delete_confirm_panel.visible = false
	_delete_target_stage_id = ""
	var delete_button := _saved_detail.find_child("DetailDeleteButton", true, false) as Control
	if delete_button != null and delete_button.is_visible_in_tree():
		delete_button.grab_focus()

## 削除した後は、一覧の先頭のカード（無ければボス名の検索欄）を操作対象にする。
func _focus_list_after_dialog() -> void:
	if not _list_panel.is_visible_in_tree():
		return
	if _list_rows.get_child_count() > 0 and (_list_rows.get_child(0) as Control).visible:
		(_list_rows.get_child(0) as Control).grab_focus()
	else:
		_name_search_field.grab_focus()

func _on_list_back_pressed() -> void:
	_show_top()

## Esc で戻る（PX-13、2026-10-18）: 削除の確認 → キャンセル、保存したボス戦の一覧 → 作成トップ、作成方法の選択 → 作成トップ、
## 作成トップ → ホーム。ボス作成の画面（main）が出ている時は、main が自分で受ける。
func _unhandled_input(event: InputEvent) -> void:
	if not Escape.pressed(self, event) or main.visible:
		return
	if _delete_confirm_panel.visible:
		Escape.consume(self)
		_on_delete_cancelled()
	elif _list_panel.visible:
		Escape.consume(self)
		_on_list_back_pressed()
	elif _mode_choice_panel.visible:
		Escape.consume(self)
		_on_mode_choice_back_pressed()
	elif _top_panel.visible:
		Escape.consume(self)
		_on_back_to_root_pressed()

# ---------------------------------------------------------------------------
# §36/§37: Creatorからの退出
# ---------------------------------------------------------------------------

func _on_creator_exited() -> void:
	# Creator で保存した可能性があるので、入口の件数を数え直す。
	_top_counts_dirty = true
	_show_top()

## 実機プレイ改善③ item4: 保存成功→クリエイター一覧の直帰。_show_list()
## （既存、無改修）がRBMLocalStageRepository.list()から毎回再取得するため、
## 直前に保存されたばかりのstageも正しく一覧へ反映される。
func _on_creator_exited_to_saved_list() -> void:
	_show_list()

# ---------------------------------------------------------------------------
# Step 8 §4: 共通ルートとの接続
# ---------------------------------------------------------------------------

func _on_back_to_root_pressed() -> void:
	exit_requested.emit()

## 共通ルートがCREATEへ入るたびに呼ぶ公開エントリポイント。既存の
## _show_top()をそのまま呼ぶだけ——ロジック自体は無改修。
func enter_create() -> void:
	_show_top()

# ---------------------------------------------------------------------------

func _show_top() -> void:
	_top_panel.visible = true
	_mode_choice_panel.visible = false
	_list_panel.visible = false
	main.visible = false
	_refresh_top_counts_if_visible()

func _show_mode_choice() -> void:
	_ensure_mode_choice_content_built()
	_top_panel.visible = false
	_mode_choice_panel.visible = true
	_list_panel.visible = false
	main.visible = false

func _show_list() -> void:
	_name_search_field.text = ""
	_id_search_field.text = ""
	_delete_confirm_panel.visible = false
	_delete_target_stage_id = ""
	_selected_stage_id = ""
	_refresh_list()
	_list_scroll.scroll_vertical = 0
	_top_panel.visible = false
	_mode_choice_panel.visible = false
	_list_panel.visible = true
	main.visible = false

func _show_creator() -> void:
	_top_panel.visible = false
	_mode_choice_panel.visible = false
	_list_panel.visible = false
	main.visible = true
