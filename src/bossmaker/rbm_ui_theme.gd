class_name RBMUiTheme
extends RefCounted

## Phase 3.5 — 全ゲームUI ビジュアル統一・正式化パス。
##
## RPG BOSS MAKER（Makers & Challengers）全体——タイトル画面／CREATE（SIMPLE・
## HARDCORE・ADVANCED）／CHALLENGE一覧・確認／TEST BATTLE・Clear Check・
## CHALLENGE戦闘／各種詳細・LOG・REWIND・結果・確認ダイアログ——が共有する、
## 唯一のUIデザイン基準。
##
## 方針（ユーザー指示§2/§6/§7/§11/§12を直接反映）:
## - 色は最小限の固定パレット（背景/パネル/枠線/文字2段階/アクセント1色/
##   控えめな副系統1色）のみ。ボタンごとに別配色にしない。
## - 角丸はごく軽く（4px）。光沢・グラデーション・グロー・ドロップシャドウは
##   一切使わない。
## - フォントサイズはTitle/Section/Body/Small の4段階のみ
##   （Theme Type Variationとして"TitleLabel"/"SectionLabel"/"SmallLabel"を
##   登録し、無印のLabelは既定でBody）。
## - ボタンはNormal/Hover/Pressed/Disabledの4状態で、形は共通のまま色味
##   だけが変化する——サイズは呼び出し側のcustom_minimum_size/テキスト量
##   側で調整し（タイトル画面の大ボタン・戦闘コマンドの小ボタン等）、
##   StyleBox自体（角丸・枠線・padding比率）は共通のまま。
## - 「PrimaryButton」（既定のButton、通常攻撃/スキル/防御/挑戦/作成/対象選択/
##   スキル一覧行等——ゲームを前に進める主要操作）と「SecondaryButton」
##   （LOG/REWIND/×/戻る/終了/やめる/最初からやり直す等——補助・離脱操作）の
##   2種類のみに絞る。警告色の大量使用（§10/§12で明示禁止）を避けるため、
##   「終了/やめる」等の破壊的操作にも専用の第3系統は作らず、Secondaryへ
##   統一する。
## - §6/§7（今回の主要修正）: 従来はPrimaryButtonのNormal状態自体がアクセント
##   色（銅）で塗られていた——「主要Buttonすべてを全面オレンジで塗る」という
##   今回名指しで禁止された見た目そのものだった。Normal＝暗色（鉄/石を思わせる
##   COLOR_BUTTON_BASE）、Hover/Focus＝縁が銅アクセントへ変化＋わずかな明度差、
##   Pressed＝Hoverよりわずかに沈んだ暗色、という状態マッピングへ全面差し替え。
##   形（角丸・枠線幅・padding）は一切変更していない。
##
## 適用範囲（今回拡張、実装後報告§3で開示）: 従来はタイトル画面コンテナと
## 3戦闘View自身のルートにのみ明示適用していた（Creator/Challengeへの意図
## しない波及を避けるため）。今回はCreator/Challengeの入口自身
## （RBMCreatorEntry/RBMChallengeEntry、いずれもextends Controlの独立した
## ルート）へも同じ方式で明示適用し、ゲーム全体を統一する——ただし
## RBMGameRoot自体には今回も適用しない（タイトル画面のHotspot/ループ演出
## Controlへ意図せず波及させないため、既存の判断を維持）。Godotの
## Theme継承はこの2つの新しい適用点から、その子孫（CreatorMain配下の
## 全STEPビュー、Challenge一覧/確認/戦闘ビュー）へそのままカスケードする。

# =============================================================================
# パレット（最小限、固定）
# =============================================================================

const COLOR_BACKGROUND := Color(0.078, 0.090, 0.114)      # #14171d 画面全体の地色
const COLOR_PANEL := Color(0.114, 0.129, 0.161)            # #1d2129 パネル/カード背景
const COLOR_PANEL_BORDER := Color(0.220, 0.243, 0.286)     # #383e49 パネル/枠線
const COLOR_TEXT_PRIMARY := Color(0.906, 0.914, 0.929)     # #e7e9ed 主要文字
const COLOR_TEXT_SECONDARY := Color(0.596, 0.624, 0.671)   # #989faa 補助文字
const COLOR_TEXT_DISABLED := Color(0.376, 0.396, 0.435)    # #60656f 無効状態の文字

## アクセント（ゲームを前に進める主要操作のHover/Focus/選択状態にのみ現れる、
## 1色のみ）——落ち着いた琥珀/朱色系（松明の暖色を思わせるトーン）。
const COLOR_ACCENT := Color(0.729, 0.396, 0.184)           # #ba652f
const COLOR_ACCENT_HOVER := Color(0.804, 0.463, 0.243)     # #cd763e
const COLOR_ACCENT_PRESSED := Color(0.596, 0.310, 0.137)   # #984f23

## §6/§7: ボタンのNormal状態そのものの塗り色——暗い鉄／石を思わせる、
## COLOR_PANELよりわずかに明るいトーン（背景に完全に沈み込まず「押せる
## 要素」として視認できる程度の差）。ここにアクセント色は一切使わない。
const COLOR_BUTTON_BASE := Color(0.145, 0.161, 0.196)       # #252932
const COLOR_BUTTON_BASE_HOVER := Color(0.180, 0.200, 0.243) # #2e3340 わずかな明度差
const COLOR_BUTTON_BASE_PRESSED := Color(0.106, 0.118, 0.145) # #1b1e25 Hoverより沈む
const COLOR_BUTTON_BASE_DISABLED := Color(0.098, 0.110, 0.133) # #191c22

## 副系統（補助/離脱操作、警告色の大量使用を避けるため中間トーンに留める）。
const COLOR_SECONDARY := Color(0.184, 0.204, 0.243)        # #2f343e
const COLOR_SECONDARY_HOVER := Color(0.243, 0.267, 0.310)  # #3e444f
const COLOR_SECONDARY_PRESSED := Color(0.145, 0.161, 0.192) # #252931

## §19: HP/SPバー識別色——ダメージ計算やゲームバランスには一切関与しない、
## 表示専用の色。HPは暖色（松明・生命）、SPは魔力装置の青系と揃えた寒色。
## 両方とも彩度を抑え、Glow無しでも視認できる十分な明度に留める。
const COLOR_HP_FILL := Color(0.694, 0.263, 0.243)          # #b1433e
const COLOR_SP_FILL := Color(0.278, 0.475, 0.647)          # #4779a5
const COLOR_BAR_BACKGROUND := Color(0.078, 0.086, 0.106)    # #14161b
const COLOR_BAR_BORDER := Color(0.220, 0.243, 0.286)        # panel borderと共通

const CORNER_RADIUS := 4
const BAR_CORNER_RADIUS := 2
const BORDER_WIDTH := 1

# =============================================================================
# フォントサイズ（4段階のみ）
# =============================================================================

const FONT_SIZE_TITLE := 40
const FONT_SIZE_SECTION := 20
const FONT_SIZE_BODY := 16
const FONT_SIZE_SMALL := 13

const VARIATION_TITLE_LABEL := "TitleLabel"
const VARIATION_SECTION_LABEL := "SectionLabel"
const VARIATION_SMALL_LABEL := "SmallLabel"
const VARIATION_SECONDARY_BUTTON := "SecondaryButton"
const VARIATION_HP_BAR := "HPBar"
const VARIATION_SP_BAR := "SPBar"

## タイトル画面完成アート反映§4/§11: 完成画像へ重ねる透明クリック領域専用の
## ボタン系統。Normal時は完全に透明（画像側の見た目をそのまま使う）で、
## Hover/Pressed/Focusだけがごく薄い半透明ハイライト/控えめな枠として現れる
## ——「派手な発光/巨大な枠/画像を隠すオーバーレイ/AIっぽいGlow」の明示禁止
## を踏まえ、影・光沢・グラデーションは一切使わない。
const VARIATION_IMAGE_HOTSPOT_BUTTON := "ImageHotspotButton"

# =============================================================================
# 余白（体系化、§11）
# =============================================================================

const BUTTON_CONTENT_MARGIN_H := 18.0
const BUTTON_CONTENT_MARGIN_V := 10.0
const PANEL_CONTENT_MARGIN := 16.0

## build_theme()自体は呼び出しのたび新規Theme resourceを構築する（副作用が
## 一切無い純関数）——RBMBattleUiKit等の他クラスと同じ「共有可変ステートを
## 持たない」方針にそのまま合わせるため、キャッシュは呼び出し側（各screen
## の_build_ui()、1回だけ呼ぶ）に委ねる。
static func build_theme() -> Theme:
	var theme := Theme.new()

	_configure_button(theme)
	_configure_secondary_button(theme)
	_configure_image_hotspot_button(theme)
	_configure_label(theme)
	_configure_panel(theme)
	_configure_progress_bars(theme)
	_configure_inputs(theme)
	_configure_separator(theme)

	return theme

# -----------------------------------------------------------------------
# Button（既定＝Primary。通常攻撃/スキル/防御/挑戦/作成/対象選択候補/
# スキル一覧行等、ゲームを前に進める主要操作はこの既定のまま使う）
#
# §6/§7: Normal＝暗色（COLOR_BUTTON_BASE、鉄/石系）、Hover＝わずかな明度差＋
# 縁が銅アクセントへ変化、Pressed＝Hoverよりさらに沈む、Focus＝既存の細い
# 銅枠（_focus_box、無改修）——「アクセント色は主要操作のHover/Focus/選択で
# だけ現れる」という§6自身の方針を、Buttonの既定状態にも一貫して適用した。
# -----------------------------------------------------------------------

static func _configure_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _button_box(COLOR_BUTTON_BASE, COLOR_PANEL_BORDER))
	theme.set_stylebox("hover", "Button", _button_box(COLOR_BUTTON_BASE_HOVER, COLOR_ACCENT))
	theme.set_stylebox("pressed", "Button", _button_box(COLOR_BUTTON_BASE_PRESSED, COLOR_ACCENT_PRESSED))
	theme.set_stylebox("disabled", "Button", _button_box(COLOR_BUTTON_BASE_DISABLED, COLOR_PANEL_BORDER))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_color("font_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BODY)

## SecondaryButton（Theme Type Variation）——LOG/REWIND/×/戻る/終了/やめる/
## 最初からやり直す等、補助・離脱操作。形（角丸・枠線・padding）はPrimaryと
## 完全に同じまま、塗り色だけを控えめなトーンへ差し替える——「全く別
## デザインにはしない」（§10）をそのまま実装したもの。§7「Hover→控えめな
## 銅・暖色の縁『または』明度変化」のうち、Secondaryは意図的に後者（中立的な
## 明度変化のみ）を採用——補助操作にまでアクセント色を持ち込むと、かえって
## 主要操作との優先度の区別が薄れるため（実装後報告§2で開示）。
static func _configure_secondary_button(theme: Theme) -> void:
	theme.set_type_variation(VARIATION_SECONDARY_BUTTON, "Button")
	theme.set_stylebox("normal", VARIATION_SECONDARY_BUTTON, _button_box(COLOR_SECONDARY, COLOR_PANEL_BORDER))
	theme.set_stylebox("hover", VARIATION_SECONDARY_BUTTON, _button_box(COLOR_SECONDARY_HOVER, COLOR_PANEL_BORDER))
	theme.set_stylebox("pressed", VARIATION_SECONDARY_BUTTON, _button_box(COLOR_SECONDARY_PRESSED, COLOR_PANEL_BORDER))
	theme.set_stylebox("disabled", VARIATION_SECONDARY_BUTTON, _button_box(Color(COLOR_SECONDARY, 0.5), COLOR_PANEL_BORDER))
	theme.set_stylebox("focus", VARIATION_SECONDARY_BUTTON, _focus_box())
	theme.set_color("font_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_SECONDARY)
	theme.set_color("font_hover_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_DISABLED)
	theme.set_color("font_focus_color", VARIATION_SECONDARY_BUTTON, COLOR_TEXT_SECONDARY)
	theme.set_font_size("font_size", VARIATION_SECONDARY_BUTTON, FONT_SIZE_BODY)

## タイトル画面完成アート反映§3/§4: 完成画像上の「挑戦」「作成」ボタン絵の
## ちょうど上へ重ねる透明クリック領域。画像そのものが見た目を担うため、
## テキストは持たない（呼び出し側でbutton.text = ""にする）——ここでは形
## （四隅の角丸のみ、他ボタン系統と統一）と、ごく控えめな状態変化だけを
## 定義する。
static func _configure_image_hotspot_button(theme: Theme) -> void:
	theme.set_type_variation(VARIATION_IMAGE_HOTSPOT_BUTTON, "Button")

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	normal.set_corner_radius_all(CORNER_RADIUS)
	normal.set_content_margin_all(0.0)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(COLOR_TEXT_PRIMARY, 0.10)
	hover.set_corner_radius_all(CORNER_RADIUS)
	hover.set_content_margin_all(0.0)
	hover.border_width_left = BORDER_WIDTH
	hover.border_width_right = BORDER_WIDTH
	hover.border_width_top = BORDER_WIDTH
	hover.border_width_bottom = BORDER_WIDTH
	hover.border_color = Color(COLOR_TEXT_PRIMARY, 0.35)
	hover.shadow_size = 0
	hover.anti_aliasing = false

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(COLOR_TEXT_PRIMARY, 0.18)
	pressed.set_corner_radius_all(CORNER_RADIUS)
	pressed.set_content_margin_all(0.0)
	pressed.border_width_left = BORDER_WIDTH
	pressed.border_width_right = BORDER_WIDTH
	pressed.border_width_top = BORDER_WIDTH
	pressed.border_width_bottom = BORDER_WIDTH
	pressed.border_color = Color(COLOR_TEXT_PRIMARY, 0.5)
	pressed.shadow_size = 0
	pressed.anti_aliasing = false

	theme.set_stylebox("normal", VARIATION_IMAGE_HOTSPOT_BUTTON, normal)
	theme.set_stylebox("hover", VARIATION_IMAGE_HOTSPOT_BUTTON, hover)
	theme.set_stylebox("pressed", VARIATION_IMAGE_HOTSPOT_BUTTON, pressed)
	theme.set_stylebox("disabled", VARIATION_IMAGE_HOTSPOT_BUTTON, normal)
	# フォーカス表示も細い枠のみ（グロー無し）——focus_boxのアクセント色は
	# 他のフォーカス表現と統一する。
	theme.set_stylebox("focus", VARIATION_IMAGE_HOTSPOT_BUTTON, _focus_box())
	theme.set_color("font_color", VARIATION_IMAGE_HOTSPOT_BUTTON, Color(0, 0, 0, 0))
	theme.set_color("font_hover_color", VARIATION_IMAGE_HOTSPOT_BUTTON, Color(0, 0, 0, 0))
	theme.set_color("font_pressed_color", VARIATION_IMAGE_HOTSPOT_BUTTON, Color(0, 0, 0, 0))
	theme.set_color("font_focus_color", VARIATION_IMAGE_HOTSPOT_BUTTON, Color(0, 0, 0, 0))

static func _button_box(fill: Color, border: Color = COLOR_PANEL_BORDER) -> StyleBoxFlat:
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
	# 光沢/立体表現/シャドウは一切付けない（§7/§12）。
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

## focus枠——キーボード/ゲームパッド操作向け、視認性のためだけの細い枠線
## （光沢・グロー無し）。マウス操作のみのheadlessテスト経路には影響しない。
static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_corner_radius_all(CORNER_RADIUS)
	box.border_width_left = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.border_color = COLOR_ACCENT
	box.draw_center = false
	return box

# -----------------------------------------------------------------------
# Label（既定＝Body。Title/Section/Smallは明示的にtheme_type_variationを
# 付けたLabelのみ適用される）
# -----------------------------------------------------------------------

static func _configure_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BODY)

	theme.set_type_variation(VARIATION_TITLE_LABEL, "Label")
	theme.set_color("font_color", VARIATION_TITLE_LABEL, COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", VARIATION_TITLE_LABEL, FONT_SIZE_TITLE)

	theme.set_type_variation(VARIATION_SECTION_LABEL, "Label")
	theme.set_color("font_color", VARIATION_SECTION_LABEL, COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", VARIATION_SECTION_LABEL, FONT_SIZE_SECTION)

	theme.set_type_variation(VARIATION_SMALL_LABEL, "Label")
	theme.set_color("font_color", VARIATION_SMALL_LABEL, COLOR_TEXT_SECONDARY)
	theme.set_font_size("font_size", VARIATION_SMALL_LABEL, FONT_SIZE_SMALL)

# -----------------------------------------------------------------------
# Panel / PanelContainer（詳細ウィンドウ/LOGウィンドウ/戦場枠、共通の
# パネル系統——同じ背景・同じ余白・同じ枠線で統一する、§10「詳細ウィンドウ」
# 「LOGウィンドウ」節の直接実装）
# -----------------------------------------------------------------------

static func _configure_panel(theme: Theme) -> void:
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
	theme.set_stylebox("panel", "PanelContainer", box)
	theme.set_stylebox("panel", "Panel", box)

# -----------------------------------------------------------------------
# ProgressBar（§19: Godot標準の見た目そのままにしない——細め・暗い枠・
# 過剰な角丸なし・Glowなし。HP/SPを色で直感的に区別できる2 Variationのみ、
# 既定のProgressBar自体はどちらにも寄せず中立トーンにしておく——呼び出し側
## が明示的にHPBar/SPBarを指定し忘れても不自然な色にはならない保険）。
# -----------------------------------------------------------------------

static func _configure_progress_bars(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", _bar_background_box())
	theme.set_stylebox("fill", "ProgressBar", _bar_fill_box(COLOR_TEXT_SECONDARY))
	theme.set_font_size("font_size", "ProgressBar", FONT_SIZE_SMALL)

	theme.set_type_variation(VARIATION_HP_BAR, "ProgressBar")
	theme.set_stylebox("background", VARIATION_HP_BAR, _bar_background_box())
	theme.set_stylebox("fill", VARIATION_HP_BAR, _bar_fill_box(COLOR_HP_FILL))
	theme.set_font_size("font_size", VARIATION_HP_BAR, FONT_SIZE_SMALL)

	theme.set_type_variation(VARIATION_SP_BAR, "ProgressBar")
	theme.set_stylebox("background", VARIATION_SP_BAR, _bar_background_box())
	theme.set_stylebox("fill", VARIATION_SP_BAR, _bar_fill_box(COLOR_SP_FILL))
	theme.set_font_size("font_size", VARIATION_SP_BAR, FONT_SIZE_SMALL)

static func _bar_background_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_BAR_BACKGROUND
	box.set_corner_radius_all(BAR_CORNER_RADIUS)
	box.border_width_left = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.border_color = COLOR_BAR_BORDER
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

static func _bar_fill_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(BAR_CORNER_RADIUS)
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

# -----------------------------------------------------------------------
# 入力UI（§29: LineEdit/SpinBox/OptionButton/CheckBox/TextEdit——Creatorが
# Godot標準UIのまま大量に残って別ゲームに見えないようにする。操作性は一切
# 変更せず、色・枠・余白のみを他のUIと統一する）。
# -----------------------------------------------------------------------

static func _configure_inputs(theme: Theme) -> void:
	_configure_line_edit(theme)
	_configure_text_edit(theme)
	_configure_option_button(theme)
	_configure_spin_box(theme)
	_configure_check_box(theme)

static func _configure_line_edit(theme: Theme) -> void:
	var normal := _input_box(COLOR_BAR_BACKGROUND, COLOR_PANEL_BORDER)
	var focus := _input_box(COLOR_BAR_BACKGROUND, COLOR_ACCENT)
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("read_only", "LineEdit", _input_box(COLOR_BUTTON_BASE_DISABLED, COLOR_PANEL_BORDER))
	theme.set_color("font_color", "LineEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", COLOR_TEXT_DISABLED)
	theme.set_color("caret_color", "LineEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("selection_color", "LineEdit", Color(COLOR_ACCENT, 0.35))
	theme.set_font_size("font_size", "LineEdit", FONT_SIZE_BODY)

static func _configure_text_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "TextEdit", _input_box(COLOR_BAR_BACKGROUND, COLOR_PANEL_BORDER))
	theme.set_stylebox("focus", "TextEdit", _input_box(COLOR_BAR_BACKGROUND, COLOR_ACCENT))
	theme.set_color("font_color", "TextEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "TextEdit", COLOR_TEXT_DISABLED)
	theme.set_color("caret_color", "TextEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("selection_color", "TextEdit", Color(COLOR_ACCENT, 0.35))
	theme.set_font_size("font_size", "TextEdit", FONT_SIZE_BODY)

## OptionButtonはButton派生のため、まず既定Buttonスタイルを一通り継承する
## （Normal/Hover/Pressed/Disabledの状態マッピングは§6/§7と統一）。
static func _configure_option_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "OptionButton", _button_box(COLOR_BUTTON_BASE, COLOR_PANEL_BORDER))
	theme.set_stylebox("hover", "OptionButton", _button_box(COLOR_BUTTON_BASE_HOVER, COLOR_ACCENT))
	theme.set_stylebox("pressed", "OptionButton", _button_box(COLOR_BUTTON_BASE_PRESSED, COLOR_ACCENT_PRESSED))
	theme.set_stylebox("disabled", "OptionButton", _button_box(COLOR_BUTTON_BASE_DISABLED, COLOR_PANEL_BORDER))
	theme.set_stylebox("focus", "OptionButton", _focus_box())
	theme.set_color("font_color", "OptionButton", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "OptionButton", COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "OptionButton", COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "OptionButton", COLOR_TEXT_DISABLED)
	theme.set_font_size("font_size", "OptionButton", FONT_SIZE_BODY)
	# ドロップダウン展開後の一覧（PopupMenu、OptionButton自身が内部生成する）。
	theme.set_stylebox("panel", "PopupMenu", _panel_box())
	theme.set_stylebox("hover", "PopupMenu", _button_box(COLOR_BUTTON_BASE_HOVER, COLOR_ACCENT))
	theme.set_color("font_color", "PopupMenu", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_TEXT_PRIMARY)

static func _configure_spin_box(theme: Theme) -> void:
	# SpinBoxは内部にLineEditを1つ持つ構成のため、LineEdit側の統一だけで
	# 実質的にほぼ揃う。増減ボタン(up/down)のみ個別に定義する。
	theme.set_stylebox("up_background", "SpinBox", _button_box(COLOR_BUTTON_BASE, COLOR_PANEL_BORDER))
	theme.set_stylebox("up_background_hovered", "SpinBox", _button_box(COLOR_BUTTON_BASE_HOVER, COLOR_ACCENT))
	theme.set_stylebox("up_background_pressed", "SpinBox", _button_box(COLOR_BUTTON_BASE_PRESSED, COLOR_ACCENT_PRESSED))
	theme.set_stylebox("down_background", "SpinBox", _button_box(COLOR_BUTTON_BASE, COLOR_PANEL_BORDER))
	theme.set_stylebox("down_background_hovered", "SpinBox", _button_box(COLOR_BUTTON_BASE_HOVER, COLOR_ACCENT))
	theme.set_stylebox("down_background_pressed", "SpinBox", _button_box(COLOR_BUTTON_BASE_PRESSED, COLOR_ACCENT_PRESSED))

static func _configure_check_box(theme: Theme) -> void:
	theme.set_color("font_color", "CheckBox", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "CheckBox", COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "CheckBox", COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "CheckBox", COLOR_TEXT_DISABLED)
	theme.set_font_size("font_size", "CheckBox", FONT_SIZE_BODY)
	# チェック/未チェックのアイコンはGodot標準テーマのままにする（独自の
	# チェックマーク描画は今回のスコープ外——文字が読めれば十分、§29の
	# 「操作性を犠牲にしない」を優先）。

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
# HSeparator（§26「── 現在の状態 ──」のようなASCII罫線の代わりに、実際の
# 罫線Nodeで区切りたい箇所向け——細く控えめ、Panel枠線と同じ色）。
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
