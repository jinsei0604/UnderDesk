class_name RBMCreatorUiKit
extends RefCounted

## Creator本体UI刷新（2026-09-04）——STEP1〜6（Creator各工程）専用の
## 共通デザインシステム。
##
## 背景（ユーザー指示§1）: Home／作成入口／作成方法選択画面は世界観を強く
## 見せる画面（濃紺＋金の意匠、RBMCreatorEntry.METHOD_*／ModeChoice*系・
## ENTRY_*系、いずれも無改修のまま維持）だった。Creator本体（実際にボスを
## 作り込むSTEP1〜6）は役割が異なり、「ファンタジー世界観を残した、使い
## やすい編集ツール」（世界観30%／操作性70%）を目標とする——このファイルは
## その専用パレット・Theme・再利用可能なControl生成ヘルパーを集約する。
##
## 適用範囲（重要）: このThemeはRBMCreatorMain._steps_root（STEP1〜6の
## 6ビューだけが属するControl）へのみ適用する。TEST BATTLE／Clear Check／
## 保存画面／外見選択ピッカーは、_steps_rootの外側（root_columnの兄弟）に
## 位置するため、引き続き既存のRBMUiTheme（RBMCreatorEntry.theme経由の
## カスケード、暖色の銅アクセント）を使い続ける——それらの画面が既に依存
## しているHPBar/SPBar/SecondaryButton等のVariationを、この新Themeが
## 一切定義していないTheme resourceへ差し替えてしまう回帰リスクを、
## 「適用対象を最初から分ける」ことで構造的に避けている。
##
## 色（§2）: 金は一切使用しない。黒に近い濃紺／ダークネイビー／青灰色／
## 低彩度で青みを持つ落ち着いた銀／アイボリー寄りの白のみ。強い発光・
## ネオン表現は使わない。
##
## Note: STEP1〜6の個々の画面（rbm_creator_step2_stats.gd等）が既に使って
## いる`RBMUiTheme.VARIATION_SECONDARY_BUTTON`（キャンセル/削除ボタン等）は
## 文字列"SecondaryButton"の定数参照でしかないため、_steps_root配下では
## Godotのtheme_type_variation解決が「祖先の中で最も近いTheme resource」
## （＝このファイルがbuild_theme()した新Theme）を見るようになり、既存の
## 呼び出しコードを1行も変更せずに新しい配色へ自動的に切り替わる——
## VARIATION_SECONDARY_BUTTONという同じ文字列をこのファイルでも意図的に
## 再利用している。

# =============================================================================
# パレット（最小限、固定。金は使用しない）
# =============================================================================

const COLOR_PANEL := Color("#161c27")           # STEP画面のパネル/カード背景
const COLOR_PANEL_BORDER := Color("#3a4351")     # パネル/枠線（青灰色）
const COLOR_BAR_BACKGROUND := Color("#0b0e14")   # 入力欄などの最も暗い地色

const COLOR_TEXT_PRIMARY := Color("#e9edf3")     # アイボリー寄りの白
const COLOR_TEXT_SECONDARY := Color("#93a0b1")   # 補助文字（青灰色）
const COLOR_TEXT_DISABLED := Color("#5a6270")

## アクセント（銀／青銀。低彩度・青み・グロー無し、§2）。
const COLOR_SILVER := Color("#8b98aa")
const COLOR_SILVER_BRIGHT := Color("#bac6d6")
const COLOR_SILVER_DIM := Color("#454e5c")

## 通常ボタン（Button既定、§9）。
const COLOR_BUTTON_BASE := Color("#1b2230")
const COLOR_BUTTON_BASE_HOVER := Color("#232c3d")
const COLOR_BUTTON_BASE_PRESSED := Color("#12161f")
const COLOR_BUTTON_BASE_DISABLED := Color("#12151b")

## 副系統（戻る等、控えめ、§10「副操作なので控えめにします」）。
const COLOR_SECONDARY := Color("#161c27")
const COLOR_SECONDARY_HOVER := Color("#1d2532")
const COLOR_SECONDARY_PRESSED := Color("#0e131a")

## 主要ナビゲーション（次へ、§10「通常ボタンよりわずかに強い銀/青銀」）。
const COLOR_PRIMARY_NAV := Color("#202b3d")
const COLOR_PRIMARY_NAV_HOVER := Color("#293650")
const COLOR_PRIMARY_NAV_PRESSED := Color("#151c29")

const CORNER_RADIUS := 4
const BORDER_WIDTH := 1

const FONT_SIZE_SECTION := 19
const FONT_SIZE_BODY := 15
const FONT_SIZE_SMALL := 12

const VARIATION_SECONDARY_BUTTON := "SecondaryButton"
const VARIATION_SECTION_LABEL := "SectionLabel"
const VARIATION_SMALL_LABEL := "SmallLabel"

const BUTTON_CONTENT_MARGIN_H := 16.0
const BUTTON_CONTENT_MARGIN_V := 8.0
const PANEL_CONTENT_MARGIN := 16.0

## build_theme()自体は呼び出しのたび新規Theme resourceを構築する純関数
## （RBMUiTheme.build_theme()と同じ方針）。RBMCreatorMainが_steps_rootへ
## 一度だけ適用する。
static func build_theme() -> Theme:
	var theme := Theme.new()
	_configure_button(theme)
	_configure_secondary_button(theme)
	_configure_label(theme)
	_configure_panel(theme)
	_configure_inputs(theme)
	_configure_h_slider(theme)
	_configure_separator(theme)
	return theme

# -----------------------------------------------------------------------
# Button（既定＝通常ボタン。§9: Normal＝暗い紺、Hover＝わずかな明度差＋
# 銀の縁、Pressed＝Hoverよりわずかに沈む、Focus＝銀の細枠）
# -----------------------------------------------------------------------

static func _configure_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _box(COLOR_BUTTON_BASE, COLOR_SILVER_DIM))
	theme.set_stylebox("hover", "Button", _box(COLOR_BUTTON_BASE_HOVER, COLOR_SILVER_BRIGHT))
	theme.set_stylebox("pressed", "Button", _box(COLOR_BUTTON_BASE_PRESSED, COLOR_SILVER))
	theme.set_stylebox("disabled", "Button", _box(COLOR_BUTTON_BASE_DISABLED, COLOR_SILVER_DIM))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_color("font_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BODY)

## SecondaryButton（Theme Type Variation）——キャンセル/削除/戻る等の補助
## 操作。形（角丸・枠線・padding）は通常ボタンと同じまま、塗り色だけを
## より控えめなトーンへ差し替える。
static func _configure_secondary_button(theme: Theme) -> void:
	theme.set_type_variation(VARIATION_SECONDARY_BUTTON, "Button")
	theme.set_stylebox("normal", VARIATION_SECONDARY_BUTTON, _box(COLOR_SECONDARY, COLOR_SILVER_DIM))
	theme.set_stylebox("hover", VARIATION_SECONDARY_BUTTON, _box(COLOR_SECONDARY_HOVER, COLOR_SILVER))
	theme.set_stylebox("pressed", VARIATION_SECONDARY_BUTTON, _box(COLOR_SECONDARY_PRESSED, COLOR_SILVER_DIM))
	theme.set_stylebox("disabled", VARIATION_SECONDARY_BUTTON, _box(Color(COLOR_SECONDARY, 0.5), COLOR_SILVER_DIM))
	theme.set_stylebox("focus", VARIATION_SECONDARY_BUTTON, _focus_box())
	theme.set_color("font_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_SECONDARY)
	theme.set_color("font_hover_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_DISABLED)
	theme.set_color("font_focus_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_SECONDARY)
	theme.set_font_size("font_size", VARIATION_SECONDARY_BUTTON, FONT_SIZE_BODY)

static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(CORNER_RADIUS)
	box.set_content_margin_all(0.0)
	box.content_margin_left = BUTTON_CONTENT_MARGIN_H
	box.content_margin_right = BUTTON_CONTENT_MARGIN_H
	box.content_margin_top = BUTTON_CONTENT_MARGIN_V
	box.content_margin_bottom = BUTTON_CONTENT_MARGIN_V
	box.border_width_left = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.border_color = border
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

## focus枠——キーボード/ゲームパッド操作向けの、視認性のためだけの細い銀枠
## （光沢・グロー無し）。
static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_corner_radius_all(CORNER_RADIUS)
	box.border_width_left = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.border_color = COLOR_SILVER_BRIGHT
	box.draw_center = false
	return box

## _steps_rootの外側（RBMCreatorMain.root_column直下）に置かれる共有
## ナビゲーション行（戻る/最終確認へ戻る/次へ）向け——このTheme resource
## 自体のカスケードが届かないため、Buttonへ直接StyleBox/文字色を上書きする
## （RBMCreatorEntryのENTRY_*系ボタンと同じ確立済み手法）。これにより、
## TEST BATTLE/Clear Check/保存画面が今も使う既存RBMUiThemeのカスケードには
## 一切触れない。
static func style_secondary_button(button: Button) -> void:
	button.theme_type_variation = ""
	button.add_theme_stylebox_override("normal", _box(COLOR_SECONDARY, COLOR_SILVER_DIM))
	button.add_theme_stylebox_override("hover", _box(COLOR_SECONDARY_HOVER, COLOR_SILVER))
	button.add_theme_stylebox_override("pressed", _box(COLOR_SECONDARY_PRESSED, COLOR_SILVER_DIM))
	button.add_theme_stylebox_override("disabled", _box(Color(COLOR_SECONDARY, 0.5), COLOR_SILVER_DIM))
	button.add_theme_stylebox_override("focus", _focus_box())
	button.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_DISABLED)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_SECONDARY)
	button.add_theme_font_size_override("font_size", FONT_SIZE_BODY)

## §10「次へ」——通常ボタンよりわずかに強い銀/青銀の枠・背景。無効状態は
## 視覚的にも判別できるよう、暗く沈んだ塗り＋文字色で表現する。
static func style_primary_nav_button(button: Button) -> void:
	button.theme_type_variation = ""
	button.add_theme_stylebox_override("normal", _box(COLOR_PRIMARY_NAV, COLOR_SILVER))
	button.add_theme_stylebox_override("hover", _box(COLOR_PRIMARY_NAV_HOVER, COLOR_SILVER_BRIGHT))
	button.add_theme_stylebox_override("pressed", _box(COLOR_PRIMARY_NAV_PRESSED, COLOR_SILVER))
	button.add_theme_stylebox_override("disabled", _box(COLOR_BUTTON_BASE_DISABLED, COLOR_SILVER_DIM))
	button.add_theme_stylebox_override("focus", _focus_box())
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_DISABLED)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)
	button.add_theme_font_size_override("font_size", FONT_SIZE_BODY)

# -----------------------------------------------------------------------
# Label（既定＝Body。Section/Smallは明示的にtheme_type_variationを付けた
# Labelのみ適用される）
# -----------------------------------------------------------------------

static func _configure_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BODY)

	theme.set_type_variation(VARIATION_SECTION_LABEL, "Label")
	theme.set_color("font_color", VARIATION_SECTION_LABEL, COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", VARIATION_SECTION_LABEL, FONT_SIZE_SECTION)

	theme.set_type_variation(VARIATION_SMALL_LABEL, "Label")
	theme.set_color("font_color", VARIATION_SMALL_LABEL, COLOR_TEXT_SECONDARY)
	theme.set_font_size("font_size", VARIATION_SMALL_LABEL, FONT_SIZE_SMALL)

# -----------------------------------------------------------------------
# Panel / PanelContainer（§5: 各設定項目のカード。画面背景よりほんの少し
# 明るい濃紺、非常に細い青灰色/銀の枠、角丸はごく小さく）
# -----------------------------------------------------------------------

static func _configure_panel(theme: Theme) -> void:
	var box := panel_box()
	theme.set_stylebox("panel", "PanelContainer", box)
	theme.set_stylebox("panel", "Panel", box)

## _steps_rootの外側（root_columnの兄弟——ExitConfirmPanel等）にある
## PanelContainer/Panelは_steps_root.themeのカスケードが届かないため、
## この関数でCreator本体の通常カードと全く同じStyleBoxFlatを個別に
## 取得し、add_theme_stylebox_override("panel", ...)で明示付与する。
## _configure_panel()自身もこの同じ関数を使うことで、カスケード経由/
## 個別付与のどちらでも見た目が完全に一致することを保証する。
static func panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PANEL
	box.set_corner_radius_all(CORNER_RADIUS)
	box.set_content_margin_all(PANEL_CONTENT_MARGIN)
	box.border_width_left = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.border_color = COLOR_PANEL_BORDER
	box.shadow_size = 0
	return box

# -----------------------------------------------------------------------
# 入力UI（§29相当——LineEdit/SpinBox/OptionButton/CheckBox/TextEditが
# Godot標準の見た目のまま浮いて見えないよう、他STEPも含め既存の全入力種類
# を同じ配色で統一する。RBMUiTheme._configure_inputs()と同じ構成を、
# Creator専用パレットへ置き換えて踏襲——STEP2/STEP4/STEP6/STEP7が既に
# 使っているLineEdit/SpinBox/OptionButton/CheckBox/TextEditへ回帰なく
# 適用されることを保証する）。
# -----------------------------------------------------------------------

static func _configure_inputs(theme: Theme) -> void:
	_configure_line_edit(theme)
	_configure_text_edit(theme)
	_configure_option_button(theme)
	_configure_spin_box(theme)
	_configure_check_box(theme)

static func _configure_line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _input_box(COLOR_BAR_BACKGROUND, COLOR_PANEL_BORDER))
	theme.set_stylebox("focus", "LineEdit", _input_box(COLOR_BAR_BACKGROUND, COLOR_SILVER_BRIGHT))
	theme.set_stylebox("read_only", "LineEdit", _input_box(COLOR_BUTTON_BASE_DISABLED, COLOR_PANEL_BORDER))
	theme.set_color("font_color", "LineEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", COLOR_TEXT_DISABLED)
	theme.set_color("caret_color", "LineEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("selection_color", "LineEdit", Color(COLOR_SILVER, 0.35))
	theme.set_font_size("font_size", "LineEdit", FONT_SIZE_BODY)

static func _configure_text_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "TextEdit", _input_box(COLOR_BAR_BACKGROUND, COLOR_PANEL_BORDER))
	theme.set_stylebox("focus", "TextEdit", _input_box(COLOR_BAR_BACKGROUND, COLOR_SILVER_BRIGHT))
	theme.set_color("font_color", "TextEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "TextEdit", COLOR_TEXT_DISABLED)
	theme.set_color("caret_color", "TextEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("selection_color", "TextEdit", Color(COLOR_SILVER, 0.35))
	theme.set_font_size("font_size", "TextEdit", FONT_SIZE_BODY)

static func _configure_option_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "OptionButton", _box(COLOR_BUTTON_BASE, COLOR_SILVER_DIM))
	theme.set_stylebox("hover", "OptionButton", _box(COLOR_BUTTON_BASE_HOVER, COLOR_SILVER_BRIGHT))
	theme.set_stylebox("pressed", "OptionButton", _box(COLOR_BUTTON_BASE_PRESSED, COLOR_SILVER))
	theme.set_stylebox("disabled", "OptionButton", _box(COLOR_BUTTON_BASE_DISABLED, COLOR_SILVER_DIM))
	theme.set_stylebox("focus", "OptionButton", _focus_box())
	theme.set_color("font_color", "OptionButton", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "OptionButton", COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "OptionButton", COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "OptionButton", COLOR_TEXT_DISABLED)
	theme.set_font_size("font_size", "OptionButton", FONT_SIZE_BODY)
	theme.set_stylebox("panel", "PopupMenu", _panel_box())
	theme.set_stylebox("hover", "PopupMenu", _box(COLOR_BUTTON_BASE_HOVER, COLOR_SILVER_BRIGHT))
	theme.set_color("font_color", "PopupMenu", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_TEXT_PRIMARY)

static func _configure_spin_box(theme: Theme) -> void:
	theme.set_stylebox("up_background", "SpinBox", _box(COLOR_BUTTON_BASE, COLOR_SILVER_DIM))
	theme.set_stylebox("up_background_hovered", "SpinBox", _box(COLOR_BUTTON_BASE_HOVER, COLOR_SILVER_BRIGHT))
	theme.set_stylebox("up_background_pressed", "SpinBox", _box(COLOR_BUTTON_BASE_PRESSED, COLOR_SILVER))
	theme.set_stylebox("down_background", "SpinBox", _box(COLOR_BUTTON_BASE, COLOR_SILVER_DIM))
	theme.set_stylebox("down_background_hovered", "SpinBox", _box(COLOR_BUTTON_BASE_HOVER, COLOR_SILVER_BRIGHT))
	theme.set_stylebox("down_background_pressed", "SpinBox", _box(COLOR_BUTTON_BASE_PRESSED, COLOR_SILVER))

static func _configure_check_box(theme: Theme) -> void:
	theme.set_color("font_color", "CheckBox", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "CheckBox", COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "CheckBox", COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "CheckBox", COLOR_TEXT_DISABLED)
	theme.set_font_size("font_size", "CheckBox", FONT_SIZE_BODY)
	# チェック/未チェックのアイコンはGodot標準テーマのまま（RBMUiThemeと
	# 同じ判断——独自描画は今回のスコープ外、操作性を優先する）。

# -----------------------------------------------------------------------
# HSlider（Creator本体UIコンセプト確定パス §4——STEP2のHP/ATK/SPD等が使う
# HSliderが、それまでGodot既定の見た目（青系のグロー気味のノブ）のまま
# 残っていたため、Creator専用の意匠へ追加した）。
#
# 背景レール(slider)＝暗い青灰色、進捗部分(grabber_area)＝銀〜青銀、
# つまみ(grabber icon)＝小さくシンプルな銀の縦長バー（丸いモダンUIの
# ノブにはしない——素朴な矩形にとどめる）。Hover/Focus/ドラッグ中は
# Godot自身のSlider内蔵ロジックがgrabber_area_highlight/grabber_highlight
# へ自動的に切り替える——このファイル側は3状態分の見た目を用意するだけで、
# 切り替えタイミング自体は制御しない（強い発光は使わず、進捗部分/つまみが
# わずかに明るくなる程度に留める）。既存のmin_value/max_value/step/
# value_changedシグナル配線には一切関与しない（見た目のみ）。
# -----------------------------------------------------------------------

const SLIDER_TRACK_INSET_PX := 10.0
const SLIDER_GRABBER_SIZE := Vector2i(8, 18)

static func _configure_h_slider(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = COLOR_BAR_BACKGROUND
	track.set_corner_radius_all(2)
	track.content_margin_top = SLIDER_TRACK_INSET_PX
	track.content_margin_bottom = SLIDER_TRACK_INSET_PX
	track.border_width_left = BORDER_WIDTH
	track.border_width_right = BORDER_WIDTH
	track.border_width_top = BORDER_WIDTH
	track.border_width_bottom = BORDER_WIDTH
	track.border_color = COLOR_PANEL_BORDER
	track.shadow_size = 0
	track.anti_aliasing = false

	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_SILVER_DIM
	fill.set_corner_radius_all(2)
	fill.content_margin_top = SLIDER_TRACK_INSET_PX
	fill.content_margin_bottom = SLIDER_TRACK_INSET_PX
	fill.shadow_size = 0
	fill.anti_aliasing = false

	var fill_highlight := StyleBoxFlat.new()
	fill_highlight.bg_color = COLOR_SILVER
	fill_highlight.set_corner_radius_all(2)
	fill_highlight.content_margin_top = SLIDER_TRACK_INSET_PX
	fill_highlight.content_margin_bottom = SLIDER_TRACK_INSET_PX
	fill_highlight.shadow_size = 0
	fill_highlight.anti_aliasing = false

	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_highlight)
	theme.set_icon("grabber", "HSlider", _slider_grabber_texture(COLOR_SILVER, COLOR_SILVER_DIM))
	theme.set_icon("grabber_highlight", "HSlider", _slider_grabber_texture(COLOR_SILVER_BRIGHT, COLOR_SILVER))
	theme.set_icon("grabber_disabled", "HSlider", _slider_grabber_texture(COLOR_TEXT_DISABLED, COLOR_PANEL_BORDER))

## つまみ用の小さな矩形テクスチャを都度生成する（Theme Iconは StyleBox
## ではなくTexture2Dを要求するため）。同じ配色の組み合わせは使い回す
## （bossmakerテストスイート全体でbuild_theme()が繰り返し呼ばれるため）。
static var _slider_grabber_texture_cache: Dictionary = {}

static func _slider_grabber_texture(fill: Color, border: Color) -> ImageTexture:
	var key := "%s|%s" % [fill.to_html(), border.to_html()]
	if _slider_grabber_texture_cache.has(key):
		return _slider_grabber_texture_cache[key]
	var size := SLIDER_GRABBER_SIZE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for x in range(size.x):
		for y in range(size.y):
			var is_border := x == 0 or x == size.x - 1 or y == 0 or y == size.y - 1
			image.set_pixel(x, y, border if is_border else fill)
	var texture := ImageTexture.create_from_image(image)
	_slider_grabber_texture_cache[key] = texture
	return texture

static func _input_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(CORNER_RADIUS)
	box.set_content_margin_all(0.0)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	box.border_width_left = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.border_color = border
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

static func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PANEL
	box.set_corner_radius_all(CORNER_RADIUS)
	box.set_content_margin_all(6.0)
	box.border_width_left = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.border_color = COLOR_PANEL_BORDER
	box.shadow_size = 0
	return box

# -----------------------------------------------------------------------
# HSeparator/VSeparator（§4: ヘッダー下の細い区切り線と同系統の色）。
# -----------------------------------------------------------------------

static func _configure_separator(theme: Theme) -> void:
	var box := StyleBoxLine.new()
	box.color = COLOR_PANEL_BORDER
	box.thickness = 1
	theme.set_stylebox("separator", "HSeparator", box)
	var vbox := StyleBoxLine.new()
	vbox.color = COLOR_PANEL_BORDER
	vbox.thickness = 1
	vbox.vertical = true
	theme.set_stylebox("separator", "VSeparator", vbox)

# =============================================================================
# 再利用可能なControl生成ヘルパー（§6/§12: 今後のCreator各工程でも使う
# 「セクション見出し」「共通ヘッダー」）
# =============================================================================

## セクション見出し（§6）: 本文より一段大きく、アイボリー〜白。左側に
## ごく小さな銀/青銀の縦アクセントを添える——装飾を主役にしない（幅3px・
## 高さは文字の8割程度のみ、唐草・大きな紋章は使わない）。
static func build_section_title(text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "SectionTitleRow"
	row.add_theme_constant_override("separation", 8)

	var accent := ColorRect.new()
	accent.name = "SectionAccent"
	accent.color = COLOR_SILVER
	accent.custom_minimum_size = Vector2(3.0, FONT_SIZE_SECTION * 0.8)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(accent)

	var label := Label.new()
	label.name = "SectionTitleLabel"
	label.text = text
	label.theme_type_variation = VARIATION_SECTION_LABEL
	row.add_child(label)
	return row

## §8: ボスプレビュー領域そのものの背景/枠。「ボスイラスト表示領域」として
## 認識できる見た目にする——非常に暗い紺の地＋細い青灰色/銀の枠＋四隅の
## ごく短い銀色コーナーライン（唐草・豪華な額縁は使わない）。実際のプレビュー
## 内容（現在はColorRect＋placeholder、将来はTextureRect）はこの上に子として
## 重ねて描かれる——親子構造・役割はSTEP1側で無改修のまま維持する。
class AppearancePreviewFrame:
	extends Control

	const BG_COLOR := Color("#0a0d13")
	const BORDER_COLOR := Color("#3a4351")
	const CORNER_COLOR := Color("#8b98aa")
	const CORNER_LENGTH := 14.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
		draw_rect(Rect2(Vector2.ONE * 0.5, size - Vector2.ONE), BORDER_COLOR, false, 1.0)
		var corners := [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]
		for corner in corners:
			var dir_x := 1.0 if corner.x < size.x * 0.5 else -1.0
			var dir_y := 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_line(corner, corner + Vector2(dir_x * CORNER_LENGTH, 0.0), CORNER_COLOR, 2.0)
			draw_line(corner, corner + Vector2(0.0, dir_y * CORNER_LENGTH), CORNER_COLOR, 2.0)

## 共通ヘッダー（§3/§4）: 左に「ボス作成｜<工程名>」、右上に「STEP n / 総数」
## という文字表示のみ——添付デザインにあった横方向の進捗ライン/ノードは
## 採用しない（§3で明示禁止）。下端に極細の銀線＋左端のごく小さな菱形の
## みを添える（唐草・巨大な紋章・豪華な額縁は使わない、§4）。
## title_label/step_labelはRBMCreatorMain._refresh()が現在のSTEPに応じて
## 都度.textを書き換える（このクラス自身は現在STEPの状態を持たない）。
class HeaderBar:
	extends Control

	const DIVIDER_COLOR := Color("#3a4351")
	const DIAMOND_COLOR := Color("#8b98aa")
	const HEADER_HEIGHT_PX := 44.0
	const DIVIDER_MARGIN_PX := 8.0
	## 実機確認（2026-09-05）: 左右マージン無しだと「STEP n / 総数」が画面
	## 右端ぎりぎりに接し、文字が窮屈/一部切れて見える——他STEP画面が使う
	## 80px規模の左右余白は持たせず（ヘッダーはウィンドウ全幅の常設要素の
	## ため）、視認性のためだけの控えめな余白を確保する。
	const SIDE_MARGIN_PX := 20.0

	var title_label: Label
	var step_label: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, HEADER_HEIGHT_PX)

		var row := HBoxContainer.new()
		row.name = "HeaderRow"
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = SIDE_MARGIN_PX
		row.offset_right = -SIDE_MARGIN_PX
		row.offset_bottom = -DIVIDER_MARGIN_PX
		row.add_theme_constant_override("separation", 16)
		add_child(row)

		title_label = Label.new()
		title_label.name = "HeaderTitleLabel"
		title_label.theme_type_variation = RBMCreatorUiKit.VARIATION_SECTION_LABEL
		title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title_label)

		step_label = Label.new()
		step_label.name = "HeaderStepLabel"
		step_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		step_label.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_SECONDARY)
		row.add_child(step_label)

	func _draw() -> void:
		var y := size.y - 1.0
		draw_line(Vector2(SIDE_MARGIN_PX - 10.0, y), Vector2(size.x - SIDE_MARGIN_PX, y), DIVIDER_COLOR, 1.0)
		var diamond := PackedVector2Array([
			Vector2(4.0, y - 4.0), Vector2(8.0, y), Vector2(4.0, y + 4.0), Vector2(0.0, y),
		])
		draw_colored_polygon(diamond, DIAMOND_COLOR)

# =============================================================================
# Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）—— STEP1〜4共通の
# 左STEPナビ／右BOSS PROFILEパネル。STEP5（最終確認）だけはこのフレーム
# 自体を使わない例外——RBMCreatorMainが_step_nav_column/_boss_profile_panel
# 自身のvisibleをcurrent_step==STEP_COUNTで切り替えるだけで、Container
# （HBoxContainer）が非表示の子を自動的にレイアウトから除外するため、
# 中央のコンテンツ領域は追加コード無しでSTEP5だけウィンドウ幅いっぱいに
# 広がる。
# =============================================================================

## 左STEPナビ（§4/§6）: 装飾を持たない、STEP1〜4の名前一覧のみ。現在の
## STEPだけ明るい文字色＋左端の細い銀アクセントで強調する（横方向の進捗
## ライン/ノードは使わない、HeaderBarと同じ§3の方針）。クリックで該当STEPへ
## 直接移動する——RBMCreatorMain.go_to_step()自体は検証(is_step_valid)を
## 一切行わない既存設計のまま（「編集」ボタン・press_return_to_summary()と
## 同じ、任意のSTEPへ自由に行き来できる既存ナビゲーション哲学を踏襲）。
class StepNavColumn:
	extends Control

	const WIDTH_PX := 150.0
	const ITEM_HEIGHT_PX := 40.0
	const ACCENT_WIDTH_PX := 3.0

	var _rows: Array = []  # [{"button":Button,"accent":ColorRect}]
	var _on_select: Callable

	func setup(step_names: Array, on_select: Callable) -> void:
		_on_select = on_select
		name = "StepNavColumn"
		custom_minimum_size = Vector2(WIDTH_PX, 0.0)
		var column := VBoxContainer.new()
		column.name = "StepNavColumnList"
		column.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(column)
		for i in range(step_names.size()):
			var row := HBoxContainer.new()
			row.name = "StepNavRow_%d" % (i + 1)
			row.custom_minimum_size = Vector2(0.0, ITEM_HEIGHT_PX)
			column.add_child(row)
			var accent := ColorRect.new()
			accent.name = "StepNavAccent_%d" % (i + 1)
			accent.color = Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT, 0.0)
			accent.custom_minimum_size = Vector2(ACCENT_WIDTH_PX, 0.0)
			row.add_child(accent)
			var button := Button.new()
			button.name = "StepNavButton_%d" % (i + 1)
			button.text = str(step_names[i])
			button.flat = true
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.size_flags_vertical = Control.SIZE_EXPAND_FILL
			button.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_SECONDARY)
			button.pressed.connect(_on_select.bind(i + 1))
			row.add_child(button)
			_rows.append({"button": button, "accent": accent})

	func set_current_step(step: int) -> void:
		for i in range(_rows.size()):
			var is_current := (i + 1) == step
			var entry: Dictionary = _rows[i]
			var button: Button = entry["button"]
			var accent: ColorRect = entry["accent"]
			button.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_PRIMARY if is_current else RBMCreatorUiKit.COLOR_TEXT_SECONDARY)
			accent.color = Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT, 1.0 if is_current else 0.0)

## 右BOSS PROFILEパネル（§4/§8）: STEP1〜4で常時表示する「今のボスの状態」
## 要約——実際に存在するDraftデータのみを表示する（レベル/ボスレベルという
## 概念は現在のRPG BOSS MAKERに存在しないため一切表示しない、DEF等の架空
## ステータスも追加しない）。RBMCreatorMain._refresh()が既存の各STEPビュー
## と同じタイミングでupdate(draft)を呼ぶだけの、自身では状態を持たない
## 表示専用ウィジェット——draft側のどのメソッドも変更しない。
class BossProfilePanel:
	extends Control

	const VisualAssets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
	const WIDTH_PX := 240.0
	const PREVIEW_MIN_SIZE := Vector2(0.0, 120.0)

	var _preview_surface: Control
	var _preview_swatch: TextureRect
	var _name_label: Label
	var _hp_label: Label
	var _atk_label: Label
	var _spd_label: Label
	var _weak_label: Label
	var _resist_label: Label
	var _skills_label: Label
	var _actions_label: Label
	var _party_label: Label

	func _ready() -> void:
		name = "BossProfilePanel"
		custom_minimum_size = Vector2(WIDTH_PX, 0.0)
		var scroll := ScrollContainer.new()
		scroll.name = "BossProfileScroll"
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(scroll)
		var column := VBoxContainer.new()
		column.name = "BossProfileColumn"
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 10)
		scroll.add_child(column)

		column.add_child(RBMCreatorUiKit.build_section_title("BOSS PROFILE"))

		_preview_surface = RBMCreatorUiKit.AppearancePreviewFrame.new()
		_preview_surface.name = "BossProfilePreview"
		_preview_surface.custom_minimum_size = PREVIEW_MIN_SIZE
		column.add_child(_preview_surface)
		_preview_swatch = TextureRect.new()
		_preview_swatch.name = "BossProfilePreviewSwatch"
		_preview_swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
		_preview_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_preview_swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_preview_swatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_preview_surface.add_child(_preview_swatch)

		_name_label = _stat_label(column, "BossProfileNameLabel")
		_name_label.theme_type_variation = RBMCreatorUiKit.VARIATION_SECTION_LABEL
		_hp_label = _stat_label(column, "BossProfileHpLabel")
		_atk_label = _stat_label(column, "BossProfileAtkLabel")
		_spd_label = _stat_label(column, "BossProfileSpdLabel")
		_weak_label = _stat_label(column, "BossProfileWeakLabel")
		_resist_label = _stat_label(column, "BossProfileResistLabel")

		column.add_child(HSeparator.new())
		column.add_child(_sub_heading("SKILLS"))
		_skills_label = _stat_label(column, "BossProfileSkillsLabel")

		column.add_child(HSeparator.new())
		column.add_child(_sub_heading("ACTIONS"))
		_actions_label = _stat_label(column, "BossProfileActionsLabel")

		column.add_child(HSeparator.new())
		column.add_child(_sub_heading("PARTY"))
		_party_label = _stat_label(column, "BossProfilePartyLabel")

	func _sub_heading(text: String) -> Label:
		var label := Label.new()
		label.text = text
		label.theme_type_variation = RBMCreatorUiKit.VARIATION_SMALL_LABEL
		return label

	func _stat_label(parent: Control, node_name: String) -> Label:
		var label := Label.new()
		label.name = node_name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(label)
		return label

	## §8: 実在するDraftデータのみ——レベル/DEF等は一切参照しない。
	func update(draft: RBMCreatorDraft) -> void:
		if draft.appearance_id.is_empty():
			_preview_swatch.texture = null
		else:
			_preview_swatch.texture = VisualAssets.texture(VisualAssets.boss_asset(draft.appearance_id), 0)
		_name_label.text = draft.boss_name if not draft.boss_name.is_empty() else "（未設定）"
		_hp_label.text = "HP：%d" % draft.hp
		_atk_label.text = "ATK：%d" % draft.atk
		_spd_label.text = "SPD：%d" % draft.spd
		_weak_label.text = "弱点：%s" % (", ".join(_attribute_labels(draft.weak_attributes)) if not draft.weak_attributes.is_empty() else "なし")
		_resist_label.text = "耐性：%s" % (", ".join(_attribute_labels(draft.resist_attributes)) if not draft.resist_attributes.is_empty() else "なし")

		if draft.skills.is_empty():
			_skills_label.text = "（未設定）"
		else:
			var skill_names: Array = []
			for skill in draft.skills:
				skill_names.append(str(skill.get("name", "")))
			_skills_label.text = "、".join(skill_names)

		_actions_label.text = _actions_summary(draft)

		if draft.party_character_ids.is_empty():
			_party_label.text = "（未選択）"
		else:
			var names: Array = []
			for character_id in draft.party_character_ids:
				var master := draft.master_character_def(character_id)
				names.append(str(master.get("display_name", character_id)))
			_party_label.text = "、".join(names)

	## §15/§27相当のACTIONS要約——旧最終確認画面(RBMCreatorStep7Summary)が
	## 持っていた「実際に組んだ内容をそのまま読める形」のロジックをこの
	## 常設パネルへ移設したもの（STEP5最終確認は§20/§21によりSTEP名+編集
	## ボタンのみへ簡略化されるため、内容そのものを見る場所としてここへ
	## 引き継いだ——機能を削除したのではなく置き場所を変えただけ）。
	func _actions_summary(draft: RBMCreatorDraft) -> String:
		if draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
			if draft.action_sequence.is_empty():
				return "（未設定）"
			var lines: Array = []
			for i in range(draft.action_sequence.size()):
				var slot: Dictionary = draft.action_sequence[i]
				var summary := RBMActionPatternSummary.slot_summary(slot, draft, i)
				lines.append("%02d %s" % [int(summary["ordinal"]), str(summary["name"])])
			return "\n".join(lines)
		var lines: Array = []
		for skill_id in draft.normal_action_percentages.keys():
			var skill := draft.find_skill(str(skill_id))
			var pct := float(draft.normal_action_percentages.get(str(skill_id), 0.0))
			lines.append("通常：%s %.1f%%" % [str(skill.get("name", "?")), pct])
		for entry in draft.scripted_actions:
			var skill := draft.find_skill(str(entry.get("skill_id", "")))
			lines.append("指定：ターン%d %s" % [int(entry.get("turn", 0)), str(skill.get("name", "?"))])
		return "\n".join(lines) if not lines.is_empty() else "（未設定）"

	func _attribute_labels(attributes: Array) -> Array:
		var labels: Array = []
		for attribute in attributes:
			var attribute_id := str(attribute)
			labels.append(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)))
		return labels
