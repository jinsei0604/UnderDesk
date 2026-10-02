class_name RBMOnlineBossListView
extends Control

## Phase 4D-1 — 「オンライン」カテゴリ(旧「注目（準備中）」)専用の一覧画面。
## 既存のローカルカテゴリ一覧(_list_panel/_refresh_list())は無改修のまま
## 残し、オンライン専用の別パネルとして追加する。
##
## 一覧はboss_name/author_name/published_atの概要のみ(§4D-2)、選択した
## 1件だけ詳細payloadを取得する(§4D-3)。
##
## 挑戦ハブ SIMPLE/HARDCORE/新着連携(2026-09) — 挑戦ハブの複数カテゴリ
## ボタンがこの同じ画面を共有するようになったため、現在のmode/categoryを
## この画面自身が保持する(§「オンライン一覧側に必要最小限の状態として、
## current mode / current category を保持できるようにしてください」)。
## 実際の絞り込み・並び替えはlist-bosses(Edge Function)側で行う——この
## クラス自身はmode/categoryをAPI呼び出しへ渡して結果をそのまま表示する
## だけで、クライアント側で再フィルタ・再ソートはしない。
##
## オンラインと新着の違い(2026-10): どちらもlist-bosses(公開日時の新しい順、
## 公開中の全ボスが対象)の先頭20件から始まる。「オンライン」は公開中の全ボスを
## 見て回る入口で、「さらに表示」で次の20件を一覧の末尾へ足していける
## (サーバーのnext_cursorで続きの位置を受け取る)。「新着」は最新20件だけで、
## 続きは読まない(カードに公開日を添える)。
##
## 2カラムの画面(2026-10、モックアップで確定): 左 = ボスカード一覧(RBMOnlineBossCard)、
## 右 = 選択中ボスの詳細(RBMOnlineBossDetailPanel)。上部は「挑戦ハブ」へ戻るボタン・
## カテゴリ名・モード切替(すべて/SIMPLE/HARDCORE)。カードを選ぶと詳細を取得して右に出し
## (自動では選ばない)、右の「挑戦する」で challenge_requested を出す(戦闘の開始は
## RBMChallengeEntryの既存の経路が行う)。見た目の部品はRBMChallengeListStyle。

signal boss_selected(boss_id: String, draft: RBMCreatorDraft, boss_name: String, author_name: String)
signal back_requested()
## 右の詳細の「挑戦する」が押された(詳細は取得済み)。
signal challenge_requested(boss_id: String, draft: RBMCreatorDraft)

## 挑戦ハブ オンライン版「人気」/「高難度」連携(2026-09) — 5カテゴリ全て
## がこの画面を共有する。人気/高難度はSteam ticket不要(特定ユーザーに
## 紐づかない集計ランキングのため)、list_bosses()と同じ匿名GETの
## list_popular_bosses()/list_hard_bosses()を使う。人気/高難度のカードには
## 順位を付け、人気=挑戦者数・高難度=クリア率を強調する(RBMOnlineBossCard)。
const CATEGORY_ONLINE := "online"
const CATEGORY_NEW := "new"
const CATEGORY_UNCHALLENGED := "unchallenged"
const CATEGORY_POPULAR := "popular"
const CATEGORY_HIGH_DIFFICULTY := "high_difficulty"

## Phase 7 共通ロード表示(ロジックのみ) — オンライン/新着/未挑戦/人気/
## 高難度は全てこの画面のrefresh()を経由する1本の通信なので、まとめて
## 1つのoperation_idで管理する(RBMLoadingState参照)。
const LOADING_OP_LIST := "online_boss_list"
const LOADING_OP_DETAIL := "online_boss_detail"
## 「オンライン」の「さらに表示」(続きのページの取得)。
const LOADING_OP_MORE := "online_boss_list_more"

## 1回に取得する件数(新着/未挑戦/人気/高難度の件数、オンラインの1ページの件数)。
const PAGE_SIZE := 20

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const WorldUi := preload("res://src/bossmaker/rbm_world_ui.gd")
const LIST_RECT := Rect2(24, 92, 444, 612)
const DETAIL_RECT := Rect2(484, 92, 772, 612)
const SKELETON_CARD_COUNT := 5

## 一覧の通信(先頭ページ・続き・詳細)が1本終わった。次の通信は、これを待ってから行う。
signal _list_request_finished()

var _api_adapter: RBMBossApiAdapter
var _recorder: RBMOnlineChallengeRecorder
var _title_label: Label
var _mode_buttons: Dictionary = {}
var _count_label: Label
var _status_title_label: Label
var _status_label: Label
var _retry_button: Button
var _scroll: ScrollContainer
var _skeleton_container: VBoxContainer
var _rows_container: VBoxContainer
var _more_error_label: Label
var _load_more_button: Button
var _detail: RBMOnlineBossDetailPanel

var _current_mode: String = ""
var _current_category: String = CATEGORY_ONLINE

# 「オンライン」のページ送り(2026-10): 次のページの位置(list-bossesのnext_cursor)、
# 続きがあるか、続きを取得中か、表示済みのboss_id(同じボスを2回並べない)。
var _next_cursor := ""
var _has_more := false
var _loading_more := false
var _shown_ids: Dictionary = {}
# 一覧の取り直し(refresh)のたびに進む番号。取得中にモード/カテゴリが変わったら、
# 古い要求の結果をこの番号で見分けて捨てる。
var _list_token := 0
# 一覧の通信が進行中か。HTTPRequestは同時に1本しか使えないので、通信は1本ずつ行う。
var _list_busy := false

# 選択(2026-10): 選んだボス、その詳細(取得済みなら)、一覧の行(boss_id -> 行の内容)。
# 詳細の取得もtokenで見分け、別のボスを選び直したら古い結果は捨てる。
var _selected_id := ""
var _selected_draft: RBMCreatorDraft = null
var _detail_token := 0
var _summaries: Dictionary = {}

func set_api_adapter_for_testing(adapter: RBMBossApiAdapter) -> void:
	_api_adapter = adapter

## 「未挑戦」はSteam ticketによる本人確認が必要なため、list_bosses()とは
## 別のRBMOnlineChallengeRecorder(RBMSteamTicketProvider経由でticketを
## 取得してからlist-unchallenged-bossesを呼ぶ)を使う。
func set_recorder_for_testing(recorder: RBMOnlineChallengeRecorder) -> void:
	_recorder = recorder

func current_mode() -> String:
	return _current_mode

func current_category() -> String:
	return _current_category

func selected_boss_id() -> String:
	return _selected_id

## 上部に出すカテゴリ名(ハブのSIMPLE/HARDCOREから開いても、見出しはカテゴリ名。モードは右上の切替で示す)。
static func category_title(category: String) -> String:
	match category:
		CATEGORY_NEW:
			return TranslationServer.translate("新着")
		CATEGORY_UNCHALLENGED:
			return TranslationServer.translate("未挑戦")
		CATEGORY_POPULAR:
			return TranslationServer.translate("人気")
		CATEGORY_HIGH_DIFFICULTY:
			return TranslationServer.translate("高難度")
		_:
			return TranslationServer.translate("オンライン")

func _ready() -> void:
	if _api_adapter == null:
		_api_adapter = RBMBossApiAdapter.new()
		add_child(_api_adapter)
	if _recorder == null:
		_recorder = RBMOnlineChallengeRecorder.new()
		add_child(_recorder)
	_build_ui()

func _build_ui() -> void:
	# 親(挑戦画面)いっぱいに広げる。set_anchors_preset()だけだと、親が既に大きさを
	# 持っている時点で呼ばれると今の大きさ(0)を保つ余白が入り、一覧の欄が0の高さに
	# なって行が1つも見えなかった(2026-10に実画面で確認して修正)。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 地: 挑戦ハブと同じ城の広間を、ほぼ黒まで沈めて奥行きだけ残す(既存の背景画像)。
	var background := TextureRect.new()
	background.name = "OnlineListBackground"
	background.texture = load(S.SCREEN_BACKGROUND_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(S.BG, 0.9)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_header()
	_build_list_panel()

	_detail = RBMOnlineBossDetailPanel.new()
	_detail.name = "OnlineBossDetailPanel"
	_detail.position = DETAIL_RECT.position
	_detail.size = DETAIL_RECT.size
	_detail.challenge_pressed.connect(_on_challenge_pressed)
	add_child(_detail)

func _build_header() -> void:
	var world = WorldUi.new()
	var back_button := Button.new()
	back_button.name = "OnlineListBackButton"
	back_button.text = tr("挑戦ハブ")
	back_button.icon = world.icon("left", S.SILVER)
	back_button.position = Vector2(24, 20)
	back_button.size = Vector2(150, 42)
	back_button.add_theme_font_size_override("font_size", 15)
	S.button_style(back_button)
	back_button.pressed.connect(func(): back_requested.emit())
	add_child(back_button)
	# 英語など文字が長い言語でもはみ出さないよう、文字に合わせて広げてから見出しを右に置く。
	back_button.size = Vector2(maxf(150.0, back_button.get_combined_minimum_size().x), 42)

	var title_x := back_button.position.x + back_button.size.x + 22
	S.rect(self, Rect2(title_x, 28, 4, 26), S.ACCENT_SOFT)
	_title_label = S.label(self, category_title(_current_category), Rect2(title_x + 16, 18, 400, 46), 27, S.TEXT, "OnlineListTitleLabel")

	var modes := [["", tr("すべて"), "OnlineListModeAll"], [RBMCreatorDraft.CREATOR_MODE_SIMPLE, "SIMPLE", "OnlineListModeSimple"], [RBMCreatorDraft.CREATOR_MODE_ADVANCED, "HARDCORE", "OnlineListModeHardcore"]]
	var x := 1256.0
	for i in range(modes.size() - 1, -1, -1):
		var mode: String = modes[i][0]
		var segment := Button.new()
		segment.name = modes[i][2]
		segment.text = modes[i][1]
		segment.add_theme_font_size_override("font_size", 14)
		if not mode.is_empty():
			segment.add_theme_font_override("font", S.number_font())
		segment.pressed.connect(_on_mode_segment_pressed.bind(mode))
		add_child(segment)
		segment.size = Vector2(maxf(124.0 if i == 2 else 108.0, segment.get_combined_minimum_size().x), 40)
		x -= segment.size.x
		segment.position = Vector2(x, 21)
		x -= 4
		_mode_buttons[mode] = segment
	_update_mode_buttons()

	S.rect(self, Rect2(24, 76, 1232, 1), Color(S.PANEL_EDGE, 0.9))
	S.rect(self, Rect2(24, 76, 64, 1), S.ACCENT_SOFT)

func _build_list_panel() -> void:
	var panel := Panel.new()
	panel.name = "OnlineListPanel"
	panel.position = LIST_RECT.position
	panel.size = LIST_RECT.size
	panel.add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.96), S.PANEL_EDGE))
	add_child(panel)
	S.section_title(panel, tr("ボス一覧"), Vector2(16, 12))

	var refresh_button := Button.new()
	refresh_button.name = "OnlineListRefreshButton"
	refresh_button.text = tr("更新")
	refresh_button.add_theme_font_size_override("font_size", 13)
	S.button_style(refresh_button)
	refresh_button.pressed.connect(func(): refresh())
	panel.add_child(refresh_button)
	refresh_button.size = Vector2(maxf(76.0, refresh_button.get_combined_minimum_size().x), 32)
	refresh_button.position = Vector2(LIST_RECT.size.x - 16 - refresh_button.size.x, 10)
	_count_label = S.label(panel, "", Rect2(150, 12, refresh_button.position.x - 162, 28), 12, S.MUTED, "OnlineListCountLabel")
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var area := Rect2(8, 52, LIST_RECT.size.x - 12, LIST_RECT.size.y - 60)
	_scroll = ScrollContainer.new()
	_scroll.name = "OnlineListScroll"
	_scroll.position = area.position
	_scroll.size = area.size
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	S.style_scrollbar(_scroll.get_v_scroll_bar())
	panel.add_child(_scroll)
	# 操作対象の白い枠(カードの外側3px)が切れないよう、左右と上に少し余白を取る。
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top"]:
		margin.add_theme_constant_override(side, 4)
	_scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "OnlineListColumn"
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_skeleton_container = VBoxContainer.new()
	_skeleton_container.name = "OnlineListSkeleton"
	_skeleton_container.add_theme_constant_override("separation", 10)
	_skeleton_container.visible = false
	column.add_child(_skeleton_container)
	for i in range(SKELETON_CARD_COUNT):
		_skeleton_container.add_child(_skeleton_card())

	_rows_container = VBoxContainer.new()
	_rows_container.name = "OnlineListRows"
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 10)
	column.add_child(_rows_container)

	# 「さらに表示」に失敗した時の一言(一覧の続きとしてボタンのすぐ上に出す)。
	_more_error_label = Label.new()
	_more_error_label.name = "OnlineListMoreErrorLabel"
	_more_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_more_error_label.custom_minimum_size = Vector2(RBMOnlineBossCard.SIZE.x, 0)
	_more_error_label.add_theme_font_size_override("font_size", 13)
	_more_error_label.add_theme_color_override("font_color", S.HARD)
	_more_error_label.visible = false
	column.add_child(_more_error_label)

	# 「オンライン」で続きがある時だけ出す。押すと次の20件を一覧の末尾へ追加する。
	_load_more_button = Button.new()
	_load_more_button.name = "OnlineListLoadMoreButton"
	_load_more_button.text = tr("さらに表示")
	_load_more_button.icon = WorldUi.new().icon("down", S.SILVER)
	_load_more_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_load_more_button.custom_minimum_size = Vector2(RBMOnlineBossCard.SIZE.x, 48)
	_load_more_button.add_theme_font_size_override("font_size", 15)
	S.button_style(_load_more_button)
	_load_more_button.visible = false
	_load_more_button.pressed.connect(func(): load_more())
	column.add_child(_load_more_button)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 6)
	column.add_child(tail)

	# 一覧が無い時(空・取得失敗)の表示。見出し(失敗時だけ)+説明+「もう一度読み込む」(失敗時だけ)。
	_status_title_label = S.label(panel, "", Rect2(area.position.x, 222, area.size.x, 28), 16, S.TEXT, "OnlineListStatusTitleLabel")
	_status_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label = S.label(panel, "", Rect2(area.position.x + 16, 250, area.size.x - 32, 48), 13, S.MUTED, "OnlineListStatusLabel")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_retry_button = Button.new()
	_retry_button.name = "OnlineListRetryButton"
	_retry_button.text = tr("もう一度読み込む")
	_retry_button.add_theme_font_size_override("font_size", 15)
	S.button_style(_retry_button)
	_retry_button.visible = false
	_retry_button.pressed.connect(func(): refresh())
	panel.add_child(_retry_button)
	_retry_button.size = Vector2(maxf(200.0, _retry_button.get_combined_minimum_size().x), 42)
	_retry_button.position = Vector2((LIST_RECT.size.x - _retry_button.size.x) / 2.0, 300)

func _skeleton_card() -> Control:
	var card := Panel.new()
	card.custom_minimum_size = RBMOnlineBossCard.SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", S.box(S.CARD, Color("1c2830")))
	S.rect(card, Rect2(10, 10, 96, 96), Color("0b1116"))
	S.rect(card, Rect2(122, 18, 190, 14), S.SKELETON)
	S.rect(card, Rect2(122, 44, 96, 10), S.SKELETON)
	S.rect(card, Rect2(122, 82, 74, 18), S.SKELETON)
	S.rect(card, Rect2(250, 70, 60, 30), S.SKELETON)
	S.rect(card, Rect2(330, 70, 60, 30), S.SKELETON)
	return card

## 挑戦ハブの各カテゴリボタンから呼ぶ入口。mode/categoryを保持したうえで
## refresh()する——「モードを切り替えたら現在のカテゴリを維持したまま
## 再取得」は、呼び出し側(RBMChallengeEntry)が現在のcategoryをそのまま
## 渡し直すことで実現する。
func refresh_with(mode: String, category: String, title_text: String) -> void:
	_current_mode = mode
	_current_category = category
	_title_label.text = title_text
	_update_mode_buttons()
	await refresh()

## 右上のモード切替(すべて/SIMPLE/HARDCORE)。カテゴリはそのままで、一覧を先頭から取り直す。
func _on_mode_segment_pressed(mode: String) -> void:
	_current_mode = mode
	_update_mode_buttons()
	refresh()

func _update_mode_buttons() -> void:
	for mode in _mode_buttons:
		S.segment_style(_mode_buttons[mode], mode == _current_mode)

## 一覧を最初から取り直す(カテゴリ/モードの切り替え・「更新」・「もう一度読み込む」)。表示中の行、
## 「オンライン」の続きの位置(cursor)、選択中のボスは捨てる。
func refresh() -> void:
	_list_token += 1
	var token := _list_token
	_next_cursor = ""
	_has_more = false
	_shown_ids.clear()
	_summaries.clear()
	_clear_selection()
	_detail.show_empty(false)
	_more_error_label.visible = false
	_update_load_more_button()
	_show_list_message("", "", false)
	_count_label.text = tr("読み込み中...")
	_skeleton_container.visible = true
	for child in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()
	# 取り直した一覧は先頭から見せる(「さらに表示」で下まで読んだ後にモード/カテゴリを
	# 切り替えても、新しい一覧の途中から始まらない)。
	_scroll.scroll_vertical = 0
	# 前の通信(取り直し・さらに表示・詳細)がまだ終わっていなければ、終わるのを待ってから通信する。
	# その結果はtokenが変わったので使われない。待つ間にさらに切り替えられたら、
	# この取り直しはやめて最後の切り替えだけを通信する。
	while _list_busy:
		await _list_request_finished
		if token != _list_token:
			return

	var response: Dictionary
	_list_busy = true
	RBMLoadingState.begin(LOADING_OP_LIST)
	match _current_category:
		CATEGORY_UNCHALLENGED:
			response = await _recorder.list_unchallenged_bosses(_current_mode, PAGE_SIZE)
		CATEGORY_POPULAR:
			response = await _api_adapter.list_popular_bosses(PAGE_SIZE, _current_mode)
		CATEGORY_HIGH_DIFFICULTY:
			response = await _api_adapter.list_hard_bosses(PAGE_SIZE, _current_mode)
		_:
			# オンラインも新着も、まずは最新の先頭ページ。続きを読むのはオンラインだけ。
			response = await _api_adapter.list_bosses(PAGE_SIZE, _current_mode)
	RBMLoadingState.end(LOADING_OP_LIST)
	_finish_list_request()
	if token != _list_token:
		return # 取得中に別のカテゴリ/モードへ切り替わった——古い結果は使わない
	_skeleton_container.visible = false
	_count_label.text = ""
	if not bool(response.get("ok", false)):
		_show_list_message(tr("一覧を取得できませんでした"), tr("通信エラー（%s）") % str(response.get("error_kind", response.get("message", "unknown"))), true)
		return

	if _current_category == CATEGORY_ONLINE:
		_take_paging(response)
	var bosses: Array = response.get("bosses", [])
	if bosses.is_empty():
		_show_list_message("", tr("公開されているボスはまだありません。"), false)
		_update_load_more_button()
		return

	_append_rows(bosses)
	_update_load_more_button()
	_detail.show_empty(true)

## 「オンライン」で、表示中の一覧の続き(次の20件)を末尾へ追加する。続きが無い・取得中・
## 別カテゴリなら何もしない。失敗しても表示済みの行と続きの位置は残すので、もう一度押せば
## 同じ続きを取り直せる。
func load_more() -> void:
	if _current_category != CATEGORY_ONLINE or not _has_more or _next_cursor.is_empty() or _loading_more:
		return
	var token := _list_token
	_loading_more = true
	_more_error_label.visible = false
	_update_load_more_button()
	# 詳細の取得などが進行中なら、終わるのを待ってから続きを取りに行く。
	while _list_busy:
		await _list_request_finished
		if token != _list_token:
			_loading_more = false
			_update_load_more_button()
			return
	_list_busy = true
	RBMLoadingState.begin(LOADING_OP_MORE)
	var response: Dictionary = await _api_adapter.list_bosses(PAGE_SIZE, _current_mode, _next_cursor)
	RBMLoadingState.end(LOADING_OP_MORE)
	_loading_more = false
	if token == _list_token:
		if bool(response.get("ok", false)):
			_take_paging(response)
			_append_rows(response.get("bosses", []))
		else:
			_more_error_label.text = tr("続きを取得できませんでした（%s）") % str(response.get("error_kind", response.get("message", "unknown")))
			_more_error_label.visible = true
		_update_load_more_button()
	_finish_list_request()

## 通信を1本終えたことにして、待っている取り直しがあれば通信させる。
func _finish_list_request() -> void:
	_list_busy = false
	_list_request_finished.emit()

## 続きがあるかと次の位置を、list-bossesの応答から受け取る(古いサーバーで項目が無ければ続き無し)。
func _take_paging(response: Dictionary) -> void:
	_next_cursor = str(response.get("next_cursor", "")) if bool(response.get("has_more", false)) else ""
	_has_more = not _next_cursor.is_empty()

## 一覧の末尾へカードを足す。既に表示しているボスは足さない。人気/高難度はサーバーの順が順位。
func _append_rows(bosses: Array) -> void:
	var ranked := _current_category == CATEGORY_POPULAR or _current_category == CATEGORY_HIGH_DIFFICULTY
	for boss_variant in bosses:
		if not (boss_variant is Dictionary):
			continue
		var boss: Dictionary = boss_variant
		var boss_id := str(boss.get("id", ""))
		if _shown_ids.has(boss_id):
			continue
		_shown_ids[boss_id] = true
		_summaries[boss_id] = boss
		var card := RBMOnlineBossCard.new()
		card.name = "OnlineBossRow_%s" % boss_id
		card.setup(boss, _current_category, _shown_ids.size() if ranked else 0)
		card.set_selected(boss_id == _selected_id)
		card.pressed.connect(_on_card_pressed.bind(boss_id))
		_rows_container.add_child(card)
	_count_label.text = tr("%d件表示中") % _shown_ids.size() if not _shown_ids.is_empty() else ""

func _update_load_more_button() -> void:
	_load_more_button.visible = _current_category == CATEGORY_ONLINE and _has_more
	_load_more_button.disabled = _loading_more
	_load_more_button.text = tr("読み込み中...") if _loading_more else tr("さらに表示")

## title: 失敗時の見出し(空なら出さない)。message: 説明。retry: 「もう一度読み込む」を出すか。
func _show_list_message(title: String, message: String, retry: bool) -> void:
	_status_title_label.text = title
	_status_title_label.visible = not title.is_empty()
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", S.HARD if retry else S.MUTED)
	_status_label.add_theme_font_size_override("font_size", 13 if retry else 15)
	_retry_button.visible = retry

# ---------------------------------------------------------------------------
# 選択と詳細

func _clear_selection() -> void:
	_selected_id = ""
	_selected_draft = null
	_detail_token += 1

func _on_card_pressed(boss_id: String) -> void:
	if boss_id == _selected_id and _selected_draft != null:
		return # 選んで詳細も出ている——取り直さない
	_selected_id = boss_id
	_selected_draft = null
	for card in _rows_container.get_children():
		if card is RBMOnlineBossCard:
			(card as RBMOnlineBossCard).set_selected((card as RBMOnlineBossCard).boss_id == boss_id)
	var summary: Dictionary = _summaries.get(boss_id, {})
	_detail.show_loading(summary)
	await _fetch_detail(boss_id, summary)

func _fetch_detail(boss_id: String, summary: Dictionary) -> void:
	_detail_token += 1
	var token := _detail_token
	while _list_busy:
		await _list_request_finished
		if token != _detail_token:
			return
	_list_busy = true
	RBMLoadingState.begin(LOADING_OP_DETAIL)
	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(_api_adapter, boss_id)
	RBMLoadingState.end(LOADING_OP_DETAIL)
	_finish_list_request()
	if token != _detail_token:
		return # 取得中に別のボスを選び直した/一覧を取り直した——古い結果は使わない
	if not bool(result.get("ok", false)):
		_detail.show_error(summary, tr("このボスは取得できませんでした（%s）。") % str(result.get("error", "unknown")))
		return
	var draft: RBMCreatorDraft = result["draft"]
	# 名前・作者は詳細の応答に入っていればそちら(最新)、空なら一覧の行のまま。
	var shown := summary.duplicate()
	for key in ["boss_name", "author_name"]:
		if not str(result.get(key, "")).is_empty():
			shown[key] = result[key]
	_selected_draft = draft
	_detail.show_boss(shown, draft)
	# 「挑戦する」(challenge_requested)と同じく、選んだカードのboss_idで知らせる。
	boss_selected.emit(boss_id, draft, str(shown.get("boss_name", "")), str(shown.get("author_name", "")))

func _on_challenge_pressed() -> void:
	if _selected_draft == null or _selected_id.is_empty():
		return
	challenge_requested.emit(_selected_id, _selected_draft)

## 新着カードの公開日(テスト・既存呼び出しのための入口。中身はRBMChallengeListStyle)。
static func _published_date_text(published_at: String, utc_offset_minutes: int) -> String:
	return RBMChallengeListStyle.published_date_text(published_at, utc_offset_minutes)
