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

signal boss_selected(boss_id: String, draft: RBMCreatorDraft, boss_name: String, author_name: String)
signal back_requested()

var _api_adapter: RBMBossApiAdapter
var _rows_container: VBoxContainer
var _status_label: Label

func set_api_adapter_for_testing(adapter: RBMBossApiAdapter) -> void:
	_api_adapter = adapter

func _ready() -> void:
	if _api_adapter == null:
		_api_adapter = RBMBossApiAdapter.new()
		add_child(_api_adapter)
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

	var title := Label.new()
	title.name = "OnlineListTitleLabel"
	title.text = tr("オンライン")
	title.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	header_row.add_child(title)

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

func refresh() -> void:
	_status_label.text = tr("読み込み中...")
	for child in _rows_container.get_children():
		child.queue_free()

	var response: Dictionary = await _api_adapter.list_bosses()
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
