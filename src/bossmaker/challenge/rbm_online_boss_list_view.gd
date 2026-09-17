class_name RBMOnlineBossListView
extends Control

## Phase 4D-1 — 「オンライン」カテゴリ(旧「注目（準備中）」)専用の一覧画面。
## 既存のローカルカテゴリ一覧(_list_panel/_refresh_list())は無改修のまま
## 残し、オンライン専用の別パネルとして追加する——新しい別UIを一から
## 作るのではなく、既存のRBMChallengeUiKit/RBMUiThemeの共有スタイルを
## そのまま使う軽量な一覧+詳細画面。
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

signal boss_selected(boss_id: String, draft: RBMCreatorDraft, boss_name: String, author_name: String)
signal back_requested()

## 挑戦ハブ オンライン版「人気」/「高難度」連携(2026-09) — 5カテゴリ全て
## がこの画面を共有する。人気/高難度はSteam ticket不要(特定ユーザーに
## 紐づかない集計ランキングのため)、list_bosses()と同じ匿名GETの
## list_popular_bosses()/list_hard_bosses()を使う。
const CATEGORY_ONLINE := "online"
const CATEGORY_NEW := "new"
const CATEGORY_UNCHALLENGED := "unchallenged"
const CATEGORY_POPULAR := "popular"
const CATEGORY_HIGH_DIFFICULTY := "high_difficulty"

var _api_adapter: RBMBossApiAdapter
var _recorder: RBMOnlineChallengeRecorder
var _rows_container: VBoxContainer
var _status_label: Label
var _title_label: Label

var _current_mode: String = ""
var _current_category: String = CATEGORY_ONLINE

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

func _ready() -> void:
	if _api_adapter == null:
		_api_adapter = RBMBossApiAdapter.new()
		add_child(_api_adapter)
	if _recorder == null:
		_recorder = RBMOnlineChallengeRecorder.new()
		add_child(_recorder)
	_build_ui()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.name = "OnlineListColumn"
	column.anchor_right = 1.0
	column.anchor_bottom = 1.0
	column.offset_left = 40.0
	column.offset_right = -40.0
	column.offset_top = 40.0
	column.offset_bottom = -20.0
	add_child(column)

	var header_row := HBoxContainer.new()
	header_row.name = "OnlineListHeaderRow"
	column.add_child(header_row)

	var back_button := Button.new()
	back_button.name = "OnlineListBackButton"
	back_button.text = tr("← 挑戦ハブ")
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(func(): back_requested.emit())
	header_row.add_child(back_button)

	_title_label = Label.new()
	_title_label.name = "OnlineListTitleLabel"
	_title_label.text = tr("オンライン")
	_title_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	header_row.add_child(_title_label)

	var refresh_button := Button.new()
	refresh_button.name = "OnlineListRefreshButton"
	refresh_button.text = tr("更新")
	refresh_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	refresh_button.pressed.connect(func(): refresh())
	header_row.add_child(refresh_button)

	_status_label = Label.new()
	_status_label.name = "OnlineListStatusLabel"
	column.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.name = "OnlineListScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.name = "OnlineListRows"
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows_container)

## 挑戦ハブの各カテゴリボタンから呼ぶ入口。mode/categoryを保持したうえで
## refresh()する——「モードを切り替えたら現在のカテゴリを維持したまま
## 再取得」は、呼び出し側(RBMChallengeEntry)が現在のcategoryをそのまま
## 渡し直すことで実現する。
func refresh_with(mode: String, category: String, title_text: String) -> void:
	_current_mode = mode
	_current_category = category
	_title_label.text = title_text
	await refresh()

func refresh() -> void:
	_status_label.text = tr("読み込み中...")
	for child in _rows_container.get_children():
		child.queue_free()

	var response: Dictionary
	match _current_category:
		CATEGORY_UNCHALLENGED:
			response = await _recorder.list_unchallenged_bosses(_current_mode, 20)
		CATEGORY_POPULAR:
			response = await _api_adapter.list_popular_bosses(20, _current_mode)
		CATEGORY_HIGH_DIFFICULTY:
			response = await _api_adapter.list_hard_bosses(20, _current_mode)
		_:
			response = await _api_adapter.list_bosses(20, _current_mode)
	if not bool(response.get("ok", false)):
		_status_label.text = tr("取得できませんでした（%s）。しばらくしてから「更新」を押してください。") % str(response.get("error_kind", response.get("message", "unknown")))
		return

	var bosses: Array = response.get("bosses", [])
	if bosses.is_empty():
		_status_label.text = tr("公開されているボスはまだありません。")
		return

	_status_label.text = ""
	for boss_variant in bosses:
		if not (boss_variant is Dictionary):
			continue
		var boss: Dictionary = boss_variant
		_rows_container.add_child(_build_row(boss))

func _build_row(boss: Dictionary) -> Button:
	var button := Button.new()
	var boss_id := str(boss.get("id", ""))
	button.name = "OnlineBossRow_%s" % boss_id
	button.text = tr("%s　(作者: %s)") % [str(boss.get("boss_name", "")), str(boss.get("author_name", ""))]
	button.pressed.connect(func(): _on_row_pressed(boss_id))
	return button

func _on_row_pressed(boss_id: String) -> void:
	_status_label.text = tr("取得中...")
	var result: Dictionary = await RBMOnlineChallengeLoader.load_boss_for_challenge(_api_adapter, boss_id)
	if not bool(result.get("ok", false)):
		_status_label.text = tr("このボスは取得できませんでした（%s）。") % str(result.get("error", "unknown"))
		return
	_status_label.text = ""
	boss_selected.emit(
		str(result.get("boss_id", boss_id)),
		result["draft"],
		str(result.get("boss_name", "")),
		str(result.get("author_name", "")),
	)
