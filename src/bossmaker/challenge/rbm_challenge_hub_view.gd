class_name RBMChallengeHubView
extends Control

## CHALLENGE UI再設計 §2〜§6 — 挑戦ハブ。CHALLENGEへ入って最初に表示される
## 画面（RBMChallengeEntry.enter_challenge()の新しい既定表示）。
##
## §7: 検索/ランダムは、RBMChallengeEntry既存の_list_panel（ローカル公開
## ステージの共通一覧、この画面の外側で構築・保持される）を使う。
##
## 挑戦ハブ オンライン移行(2026-09) — SIMPLE/HARDCORE/オンライン/新着/
## 未挑戦/人気/高難度の全7ボタンが、Supabase上の公開ボス一覧
## (RBMOnlineBossListView)へ接続される(RBMChallengeEntry.
## _on_hub_category_selected()参照)。このクラス自身はどの経路でも一覧を
## 一切構築しない、純粋にカテゴリ選択の入口だけを担う。
##
## 見た目の刷新（2026-10、ユーザーが完成イメージで承認）: 城の広間の背景と金の枠をやめ、
## 挑戦側のオンライン一覧と同じ紺＋水色（RBMMenuUi／RBMChallengeListStyle）にした。
## 上から「モードから探す」（SIMPLE／HARDCORE の大きなカード）、「ボスを見つける」（5つのタイル）、
## 「そのほかの探し方」（検索・ランダム）。各ボタンは自分の文字（Button.text）で名前を見せ、
## 説明・札・矢印は子のノードで添える（矢印は画像ではなく図形）。

signal category_selected(category: String)
signal random_requested
signal search_requested
signal back_to_root_requested

## RBMChallengeUiKit.filter_by_mode()等が直接読む値と一致させる——ハブ側
## だけの独自カテゴリID体系を新たに作らない。
const CATEGORY_SIMPLE := "simple"
const CATEGORY_HARDCORE := "hardcore"
const CATEGORY_FEATURED := "featured"
const CATEGORY_NEW := "new"
const CATEGORY_UNCHALLENGED := "unchallenged"
const CATEGORY_POPULAR := "popular"
const CATEGORY_HIGH_DIFFICULTY := "high_difficulty"

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const M := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")

const MODE_CARD_SIZE := Vector2(590, 176)
const MODE_CARD_TOP := 136.0
const MODE_CARD_STEP := 610.0
const TILE_SIZE := Vector2(228, 118)
const TILE_TOP := 372.0
const TILE_STEP := 243.0
const TOOL_BUTTON_SIZE := Vector2(220, 46)
const TOOL_BUTTON_TOP := 558.0
const LEFT := 40.0
## 「あなたの討伐記録」（2026-10-16）: 右下。SIMPLE と HARDCORE を横に並べ、その下に金色の「難関ボス討伐」。
const RECORD_LEFT := 650.0
const RECORD_TOP := 556.0
const RECORD_WIDTH := 590.0
const RECORD_CARD_HEIGHT := 66.0
const RECORD_HARD_HEIGHT := 54.0
const RECORD_GAP := 10.0
var _record_values: Dictionary = {}

func _ready() -> void:
	set_meta("world_skip", true)
	_build_ui()

func _build_ui() -> void:
	M.add_backdrop(self, "HubBackground")

	var back_button := Button.new()
	back_button.name = "BackToRootButton"
	back_button.pressed.connect(func(): back_to_root_requested.emit())
	M.header(self, back_button, tr("戻る"), tr("挑戦"), tr("遊びたいボスを選んでください"), "HubTitleLabel", "HubSubtitleLabel")

	M.section(self, tr("モードから探す"), Vector2(LEFT, 100))
	_mode_card(0, "SIMPLE", tr("シンプルなボス戦"), tr("基本の設定で作られたボス戦から探します"), S.SILVER, "SimpleCategoryButton", [tr("技を割合で使い分ける")], CATEGORY_SIMPLE)
	_mode_card(1, "HARDCORE", tr("作り込まれたボス戦"), tr("行動の順番や条件まで作り込まれたボス戦から探します"), S.HARD, "HardcoreCategoryButton", [tr("行動の順番と条件"), tr("覚醒することも")], CATEGORY_HARDCORE)

	M.section(self, tr("ボスを見つける"), Vector2(LEFT, 336))
	var tiles := [
		[tr("オンライン"), tr("公開中のすべてのボス"), "FeaturedCategoryButton", CATEGORY_FEATURED],
		[tr("新着"), tr("新しく公開されたボス"), "NewCategoryButton", CATEGORY_NEW],
		[tr("未挑戦"), tr("まだ挑戦していないボス"), "UnchallengedCategoryButton", CATEGORY_UNCHALLENGED],
		[tr("人気"), tr("挑戦した人が多い順"), "PopularCategoryButton", CATEGORY_POPULAR],
		[tr("高難度"), tr("クリア率が低い順"), "HighDifficultyCategoryButton", CATEGORY_HIGH_DIFFICULTY],
	]
	for i in range(tiles.size()):
		_tile(i, tiles[i][0], tiles[i][1], tiles[i][2], tiles[i][3])

	M.section(self, tr("そのほかの探し方"), Vector2(LEFT, 522))
	var search := _tool_button(LEFT, tr("ボスを検索"), "SearchBossButton", func(): search_requested.emit())
	_tool_button(search.position.x + search.size.x + 16, tr("ランダムで挑戦"), "RandomChallengeButton", func(): random_requested.emit())

	M.section(self, tr("あなたの討伐記録"), Vector2(RECORD_LEFT, 522), "DefeatRecordTitle")
	var half := (RECORD_WIDTH - RECORD_GAP) * 0.5
	_record_card("simple", "SIMPLE", true, S.SILVER, S.CARD_EDGE, Rect2(RECORD_LEFT, RECORD_TOP, half, RECORD_CARD_HEIGHT), "DefeatRecordSimple")
	_record_card("hardcore", "HARDCORE", true, S.HARD, S.HARD_EDGE, Rect2(RECORD_LEFT + half + RECORD_GAP, RECORD_TOP, half, RECORD_CARD_HEIGHT), "DefeatRecordHardcore")
	_record_card("hard", tr("難関ボス討伐"), false, S.GOLD, S.GOLD_EDGE, Rect2(RECORD_LEFT, RECORD_TOP + RECORD_CARD_HEIGHT + RECORD_GAP, RECORD_WIDTH, RECORD_HARD_HEIGHT), "DefeatRecordHard")
	set_defeat_counts({})

## SIMPLE／HARDCORE の大きなカード。名前（Button.text、英字）・副題・説明・特徴の札・「一覧を見る」。
func _mode_card(index: int, mode_name: String, subtitle: String, description: String, color: Color, node_name: String, tags: Array, category: String) -> void:
	var card := Button.new()
	card.name = node_name
	card.position = Vector2(LEFT + index * MODE_CARD_STEP, MODE_CARD_TOP)
	card.size = MODE_CARD_SIZE
	M.card_styles(card, false, Vector4(30, 18, 160, MODE_CARD_SIZE.y - 68))
	M.card_title(card, mode_name, 36, color, true)
	card.pressed.connect(func(): category_selected.emit(category))
	add_child(card)
	M.accent_bar(card, color, MODE_CARD_SIZE.y)
	S.label(card, subtitle, Rect2(30, 72, 420, 28), 18, S.TEXT, "SubtitleLabel")
	S.label(card, description, Rect2(30, 102, 530, 26), 13, S.MUTED, "DescriptionLabel")
	var x := 30.0
	for text in tags:
		var t := M.tag(card, text, Vector2(x, 138), S.SILVER, Color("3a4a53"), Color(S.INSET, 0.9))
		x += t.get_combined_minimum_size().x + 8
	var open := S.label(card, tr("一覧を見る"), Rect2(MODE_CARD_SIZE.x - 210, 72, 160, 30), 14, S.SILVER, "OpenListLabel")
	open.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var arrow := M.arrow(card, Vector2(MODE_CARD_SIZE.x - 38, 80), S.SILVER)
	M.on_highlight(card, func(on: bool) -> void:
		open.add_theme_color_override("font_color", S.TEXT if on else S.SILVER)
		arrow.set_color(S.ACCENT if on else S.SILVER))

## 「ボスを見つける」のタイル。名前（Button.text）・説明・上辺の短い線・矢印。
func _tile(index: int, title: String, description: String, node_name: String, category: String) -> void:
	var tile := Button.new()
	tile.name = node_name
	tile.position = Vector2(LEFT + index * TILE_STEP, TILE_TOP)
	tile.size = TILE_SIZE
	M.card_styles(tile, false, Vector4(18, 22, 44, TILE_SIZE.y - 52))
	M.card_title(tile, title, 20, S.TEXT)
	tile.pressed.connect(func(): category_selected.emit(category))
	add_child(tile)
	var line := S.rect(tile, Rect2(18, 0, 36, 2), S.ACCENT_SOFT, "TopLine")
	var desc := S.label(tile, description, Rect2(18, 58, TILE_SIZE.x - 30, 40), 13, S.MUTED, "DescriptionLabel")
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var arrow := M.arrow(tile, Vector2(TILE_SIZE.x - 30, 30), Color(S.SILVER, 0.6))
	M.on_highlight(tile, func(on: bool) -> void:
		line.color = S.ACCENT if on else S.ACCENT_SOFT
		arrow.set_color(S.ACCENT if on else Color(S.SILVER, 0.6)))

## 討伐記録の1枚（押せない表示だけのカード）: 左に小さな名前、右に大きな数。left の縦線と枠は種類の色。
func _record_card(key: String, caption: String, latin: bool, color: Color, edge: Color, area: Rect2, node_name: String) -> void:
	var card := Panel.new()
	card.name = node_name
	card.position = area.position
	card.size = area.size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := Color("15130d", 0.94) if key == "hard" else Color(S.CARD, 0.93)
	card.add_theme_stylebox_override("panel", S.box(fill, edge))
	add_child(card)
	M.accent_bar(card, color, area.size.y)
	var name_label := S.label(card, caption, Rect2(22, 0, area.size.x * 0.6, area.size.y), 16 if latin else 15, color, "CaptionLabel")
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if latin:
		name_label.add_theme_font_override("font", S.number_font())
	var value := S.label(card, "0", Rect2(area.size.x * 0.4, 0, area.size.x * 0.6 - 24, area.size.y), 40 if key != "hard" else 34, S.TEXT if key != "hard" else S.GOLD, "ValueLabel")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_override("font", S.number_font())
	_record_values[key] = value

## 討伐記録の数を出す（RBMChallengeEntry が挑戦トップを出す時に、今のアカウントの記録 RBMDefeatRecord.counts() を渡す）。
func set_defeat_counts(counts: Dictionary) -> void:
	for key in ["simple", "hardcore", "hard"]:
		if _record_values.has(key):
			(_record_values[key] as Label).text = str(int(counts.get(key, 0)))

## 今出している討伐記録の数（テスト・検証用）。
func defeat_counts_shown() -> Dictionary:
	var out := {}
	for key in _record_values:
		out[key] = int((_record_values[key] as Label).text)
	return out

func _tool_button(x: float, text: String, node_name: String, callback: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.position = Vector2(x, TOOL_BUTTON_TOP)
	b.add_theme_font_size_override("font_size", 15)
	S.button_style(b)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(callback)
	add_child(b)
	b.size = Vector2(maxf(TOOL_BUTTON_SIZE.x, b.get_combined_minimum_size().x), TOOL_BUTTON_SIZE.y)
	return b
