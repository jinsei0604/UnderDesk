class_name RBMChallengeHubView
extends Control

## CHALLENGE UI再設計 §2〜§6 — 挑戦ハブ。CHALLENGEへ入って最初に表示される
## 画面（RBMChallengeEntry.enter_challenge()の新しい既定表示）。
##
## §3: カテゴリ/ランダム/検索ボタンはすべて文字ベースのみ——仮アイコン・
## 絵文字は一切追加しない。将来アイコンを追加しやすいよう
## RBMChallengeUiKit.build_category_button()を経由するが、現時点ではその
## 関数自体が画像領域を持たない。
##
## §7: 検索/ランダムは、RBMChallengeEntry既存の_list_panel（ローカル公開
## ステージの共通一覧、この画面の外側で構築・保持される）を使う。
##
## 挑戦ハブ オンライン移行(2026-09) — SIMPLE/HARDCORE/オンライン/新着/
## 未挑戦/人気/高難度の全7ボタンが、Supabase上の公開ボス一覧
## (RBMOnlineBossListView)へ接続される(RBMChallengeEntry.
## _on_hub_category_selected()参照)。人気=ユニーク挑戦者数ベース、
## 高難度=補正クリア率ベースの正式な算出方法が確定したため、いずれも
## disabled=trueの「準備中」表示から通常のボタンへ切り替えた。このクラス
## 自身はどの経路でも一覧を一切構築しない、純粋にカテゴリ選択の入口だけを
## 担う。

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

const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

func _ready() -> void:
	_build_ui()
	var world = preload("res://src/bossmaker/rbm_world_ui.gd").new()
	world.challenge_layout(self)
	world.walk(self)

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.name = "HubColumn"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.offset_top = CONTENT_TOP_MARGIN_PX
	column.offset_bottom = -20.0
	add_child(column)

	var title := Label.new()
	title.name = "HubTitleLabel"
	title.text = tr("挑戦")
	title.theme_type_variation = RBMUiTheme.VARIATION_TITLE_LABEL
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "HubSubtitleLabel"
	subtitle.text = tr("遊びたいボスを選んでください")
	subtitle.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	column.add_child(subtitle)

	column.add_child(HSeparator.new())
	column.add_child(_section_heading(tr("モードから探す")))
	var mode_row := HBoxContainer.new()
	mode_row.name = "ModeRow"
	column.add_child(mode_row)
	mode_row.add_child(RBMChallengeUiKit.build_category_button("SIMPLE", "SimpleCategoryButton", func(): category_selected.emit(CATEGORY_SIMPLE)))
	mode_row.add_child(RBMChallengeUiKit.build_category_button("HARDCORE", "HardcoreCategoryButton", func(): category_selected.emit(CATEGORY_HARDCORE)))

	column.add_child(HSeparator.new())
	column.add_child(_section_heading(tr("ボスを見つける")))
	var discover_row_1 := HBoxContainer.new()
	discover_row_1.name = "DiscoverRow1"
	column.add_child(discover_row_1)
	# CHALLENGE discovery 最終調整 §3: 「注目」のランキングアルゴリズムは
	# 未確定のため、押しても通常一覧を注目順であるかのように見せない
	# ——既存のButton.disabled（無効状態、RBMUiThemeの既存disabledスタイル
	# をそのまま使う、新しい見た目は作らない）で「準備中」を示す。文言に
	# も明示し、アイコンは追加しない（§3）。
	# Phase 4D: 「注目（準備中）」プレースホルダーをオンライン一覧の入口として
	# 有効化する(ランキングアルゴリズム自体はPhase 5まで未実装のまま——
	# ここは単に公開済みオンラインボスの一覧を開くだけ)。
	discover_row_1.add_child(RBMChallengeUiKit.build_category_button(tr("オンライン"), "FeaturedCategoryButton", func(): category_selected.emit(CATEGORY_FEATURED)))
	discover_row_1.add_child(RBMChallengeUiKit.build_category_button(tr("新着"), "NewCategoryButton", func(): category_selected.emit(CATEGORY_NEW)))
	# オンライン版「未挑戦」(2026-09)正式実装: Steamユーザー×オンラインboss
	# の挑戦履歴(boss_challenge_records)をサーバー側で確認できるようになった
	# ため有効化した——「オンライン」がPhase 4D-1で有効化されたのと同じ経緯。
	discover_row_1.add_child(RBMChallengeUiKit.build_category_button(tr("未挑戦"), "UnchallengedCategoryButton", func(): category_selected.emit(CATEGORY_UNCHALLENGED)))

	var discover_row_2 := HBoxContainer.new()
	discover_row_2.name = "DiscoverRow2"
	column.add_child(discover_row_2)
	# オンライン版「人気」/「高難度」(2026-09)正式実装: 正式な算出方法
	# (ユニーク挑戦者数ベースの人気順、補正クリア率ベースの高難度順)が
	# 確定したため有効化した——「未挑戦」と同じ経緯。
	discover_row_2.add_child(RBMChallengeUiKit.build_category_button(tr("人気"), "PopularCategoryButton", func(): category_selected.emit(CATEGORY_POPULAR)))
	discover_row_2.add_child(RBMChallengeUiKit.build_category_button(tr("高難度"), "HighDifficultyCategoryButton", func(): category_selected.emit(CATEGORY_HIGH_DIFFICULTY)))

	column.add_child(HSeparator.new())
	var utility_row := HBoxContainer.new()
	utility_row.name = "UtilityRow"
	column.add_child(utility_row)
	var random_button := Button.new()
	random_button.name = "RandomChallengeButton"
	random_button.text = tr("ランダムで挑戦")
	random_button.pressed.connect(func(): random_requested.emit())
	utility_row.add_child(random_button)
	var search_button := Button.new()
	search_button.name = "SearchBossButton"
	search_button.text = tr("ボスを検索")
	search_button.pressed.connect(func(): search_requested.emit())
	utility_row.add_child(search_button)

	var back_button := Button.new()
	back_button.name = "BackToRootButton"
	back_button.text = tr("← 戻る")
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(func(): back_to_root_requested.emit())
	column.add_child(back_button)

func _section_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	return label
