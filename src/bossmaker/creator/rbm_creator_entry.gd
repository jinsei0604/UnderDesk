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

## Phase 1 Step 8 §4 — 共通ルートへ戻る要求。RBMCreatorMain自身の`exited`
## シグナル（既存・無改修、未保存変更警告を含む正式な退出処理の完了通知）
## とは別物——こちらはCREATE自体（RBMCreatorEntryのTOP画面）から共通ルート
## 画面へ戻る、Step 8で新設した1段外側の退出経路。共通ルート側がCreatorを
## 強制的に非表示にして既存の未保存変更警告を迂回することは無い——TOP画面へ
## 到達できる唯一の経路は既存のpress_exit_creator()（未保存変更警告を含む）
## がexitedを発火した後だけであり、このexit_requestedはその後にのみ発火する。
signal exit_requested

## Phase 3.5 UI統一§33バグ修正: RBMChallengeEntry.SEARCH_FIELD_MIN_SIZEと
## 同じ理由（検索欄のplaceholder_textが既定の極small幅で視覚的に切れて
## いた、§38）。
const SEARCH_FIELD_MIN_SIZE := Vector2(170.0, 32.0)

## 「作成方法を選択」画面の正式アート実装で使用する2素材。ユーザー提供の
## 完成アートをそのまま使用——新規AI生成・再加工は行っていない
## （RBMCreatorGuideCharacterのクラス冒頭コメント・最終報告参照）。
const MODE_CHOICE_BACKGROUND_PATH := "res://assets_bossmaker/art/creator_method_select_background.png"

## 右側UI簡略化パス（2026-09-04）: 説明パネル／SIMPLE・HARDCORE選択パネルは
## Godotの描画プリミティブ（現在はRBMWorldUi.method_layout()側）で再現して
## おり、画像素材は使用していない。旧mode_choice_description_panel.png/
## _selection_panel.pngは過去のデザイン検討の記録として資産フォルダに残置
## しているが、コードからの参照は無い。

## 「ボス戦を作成」TOP画面（_build_top_panel()）の背景。同じくユーザー
## 提供の完成アート（UIなしの扉背景）をそのまま使用——新規AI生成・
## 再加工は行っていない。
const TOP_BACKGROUND_PATH := "res://assets_bossmaker/art/creator_top_background.png"

## RBMCreatorGuideCharacterの表示scale/position。
## 修正パス（2026-09-03）§5〜§7: 背景をSTRETCH_KEEP_ASPECT_COVEREDへ変更
## した結果、部屋が旧CENTERED比で1280/960≈1.333倍拡大表示になったため、
## 家具とのスケール感が合うようキャラクターも一回り拡大した（旧0.4636→
## 0.50、部屋の拡大率をそのまま適用すると頭が画面上端を超えてしまうため
## 全量は追従させず、720px高に収まる範囲で家具比とのバランスを実際に
## レンダリングして調整した値）。足元は変更前と同じ画面y=700付近を維持。
const GUIDE_CHARACTER_SCALE := 0.50
const GUIDE_CHARACTER_POSITION := Vector2(76.0, 19.0)

var main: RBMCreatorMain

var _top_background: Control
var _top_panel: Control
var _mode_choice_panel: Control
var _mode_choice_content_built := false
var _guide_character: RBMCreatorGuideCharacter
var _list_panel: VBoxContainer
var _name_search_field: LineEdit
var _id_search_field: LineEdit
var _list_rows: VBoxContainer

var _delete_confirm_panel: VBoxContainer
var _delete_confirm_label: Label
var _delete_target_stage_id: String = ""

const STATUS_LABELS := {
	"draft": "下書き",
	"playable": "挑戦可能",
	"clear_checked": "✓ クリアチェック済み",
}

func _ready() -> void:
	_build_ui()
	var world = preload("res://src/bossmaker/rbm_world_ui.gd").new()
	world.entry_layout(self)
	world.walk(self)

func _build_ui() -> void:
	# Phase 3.5 UI統一§0/§5/§9: 従来はここに一切Themeを適用しておらず、
	# CREATE全体（TOP/モード選択/一覧/STEP1〜7/保存/外見選択）がGodot既定の
	# 見た目のまま残っていた。RBMCreatorEntry自身がCREATE全体の唯一の
	# ルートControl（RBMGameRootには適用しない既存方針を維持したまま）
	# であるため、ここへ明示適用するだけでCREATE配下すべてへカスケードする
	# ——3戦闘Viewが既に使っているのと全く同じ1行のパターン。
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

## 左右と上下に等しい安全余白を持つ全画面レイアウト。保存済み一覧画面
## （_build_list_panel()）でも共有する余白定数——この画面自体のTOP
## レイアウトは背景アート実装（下記）で絶対位置指定へ切り替えたため、
## ここでは他画面が引き続き使う3定数だけを残す。
const CONTENT_SIDE_MARGIN_PX := 60.0
const CONTENT_TOP_MARGIN_PX := 32.0
const CONTENT_BOTTOM_MARGIN_PX := 24.0

## 背景アート実装（2026-09-04）: 「ボス戦を作成」TOP画面専用の絶対位置
## レイアウト定数。ユーザー提供のデザインリファレンス画像（1672×941、UI
## 配置済みの完成イメージ）で実測した各要素の位置・寸法比率を1280×720へ
## 換算し、実機レンダリングと突き合わせながら調整した値——参照画像を
## そのまま貼り付けるのではなく、Godot UIとして再現するための数値のみ
## 抽出している。
const ENTRY_TITLE_TOP_PX := 90.0
const ENTRY_TITLE_HEIGHT_PX := 62.0
const ENTRY_TITLE_FONT_SIZE := 46
const ENTRY_TITLE_UNDERLINE_TOP_PX := 156.0
const ENTRY_TITLE_UNDERLINE_HEIGHT_PX := 14.0
const ENTRY_TITLE_UNDERLINE_WIDTH_PX := 280.0
const ENTRY_DESCRIPTION_TOP_PX := 198.0
const ENTRY_DESCRIPTION_HEIGHT_PX := 26.0
const ENTRY_DESCRIPTION_FONT_SIZE := 16
const ENTRY_MAIN_BUTTON_SIZE := Vector2(375.0, 80.0)
const ENTRY_MAIN_BUTTON_GAP_PX := 30
const ENTRY_MAIN_BUTTON_TOP_PX := 460.0
const ENTRY_MAIN_BUTTON_FONT_SIZE := 24
const ENTRY_BACK_BUTTON_SIZE := Vector2(150.0, 44.0)
const ENTRY_BACK_BUTTON_MARGIN_PX := 40.0

## 「ボス戦を作成」入口だけで使うパレット。メインボタン自体は作成方法
## 選択画面と同じ紺＋金の意匠（MethodChoiceSurface、完成イメージのボタン
## 意匠と同一系統のため流用）を使うので、ここにはタイトル・下線・戻る
## ボタン用の色だけを残す。
const ENTRY_COLOR_ACCENT := Color("#ad8748")
const ENTRY_COLOR_ACCENT_HOVER := Color("#d3aa5b")
const ENTRY_COLOR_TITLE := Color("#eadcbd")
const ENTRY_COLOR_DESCRIPTION := Color("#a89b84")
const ENTRY_COLOR_FRAME := Color("#705532")
const ENTRY_COLOR_BACK_HOVER := Color("#241b13")
const ENTRY_COLOR_BACK_PRESSED := Color("#120e0b")

## タイトル直下の細い金色装飾線＋中央の菱形。デザインリファレンス画像の
## タイトル下線と同じ構成（左右の線＋中央の菱形）を、画像を使わずGodotの
## 描画プリミティブだけで再現する。
class EntryTitleUnderline:
	extends Control

	func _draw() -> void:
		var y := size.y * 0.5
		var gap := 10.0
		draw_line(Vector2(0.0, y), Vector2(size.x * 0.5 - gap, y), Color(ENTRY_COLOR_FRAME, 0.85), 1.0)
		draw_line(Vector2(size.x * 0.5 + gap, y), Vector2(size.x, y), Color(ENTRY_COLOR_FRAME, 0.85), 1.0)
		var diamond := PackedVector2Array([
			Vector2(size.x * 0.5, y - 5.0),
			Vector2(size.x * 0.5 + 5.0, y),
			Vector2(size.x * 0.5, y + 5.0),
			Vector2(size.x * 0.5 - 5.0, y),
		])
		draw_colored_polygon(diamond, ENTRY_COLOR_ACCENT)

## 背景アート実装（2026-09-04）: ユーザー提供の完成アート（UIなしの扉背景、
## RBMCreatorGuideCharacterのクラス冒頭コメント・最終報告と同じく新規AI
## 生成・再加工は行っていない）を実背景として使用し、その上へGodot UI
## （Label/Button）としてタイトル・説明・メインボタン2つ・戻るボタンを
## 重ねる。デザインリファレンス画像（UI配置済みの完成イメージ）は絵として
## 貼り付けず、位置・サイズ・配色を再現するための参照にのみ用いた——
## タイトルを含む文字はすべてLabel/Buttonとして実装しているため、Hover・
## フォーカス・クリック・解像度対応・将来の文言変更が正常に機能する。
func _build_top_panel() -> void:
	_top_background = TextureRect.new()
	_top_background.name = "EntryBackground"
	_top_background.texture = load(TOP_BACKGROUND_PATH)
	_top_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 参照画像は1672×941（16:9とほぼ同一比率）——STRETCH_KEEP_ASPECT_COVERED
	# はモード選択画面の背景（MODE_CHOICE_BACKGROUND_PATH）でも使っている
	# 既存技法で、アスペクト比を保ったまま画面全体を覆う（画像の変形はしない）。
	_top_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_top_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_background)

	_top_panel = Control.new()
	_top_panel.name = "EntryTopPanel"
	_top_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_top_panel)

	var title := Label.new()
	title.name = "EntryTitleLabel"
	title.text = "ボス戦を作成"
	title.theme_type_variation = RBMUiTheme.VARIATION_TITLE_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", ENTRY_COLOR_TITLE)
	title.add_theme_font_size_override("font_size", ENTRY_TITLE_FONT_SIZE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.anchor_right = 1.0
	title.offset_top = ENTRY_TITLE_TOP_PX
	title.offset_bottom = ENTRY_TITLE_TOP_PX + ENTRY_TITLE_HEIGHT_PX
	_top_panel.add_child(title)

	var underline := EntryTitleUnderline.new()
	underline.name = "EntryTitleUnderline"
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underline.anchor_left = 0.5
	underline.anchor_right = 0.5
	underline.offset_left = -ENTRY_TITLE_UNDERLINE_WIDTH_PX * 0.5
	underline.offset_right = ENTRY_TITLE_UNDERLINE_WIDTH_PX * 0.5
	underline.offset_top = ENTRY_TITLE_UNDERLINE_TOP_PX
	underline.offset_bottom = ENTRY_TITLE_UNDERLINE_TOP_PX + ENTRY_TITLE_UNDERLINE_HEIGHT_PX
	_top_panel.add_child(underline)

	var description := Label.new()
	description.name = "EntryDescriptionLabel"
	description.text = "新しいボス戦を作るか、保存したボス戦を編集してください。"
	description.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", ENTRY_DESCRIPTION_FONT_SIZE)
	description.add_theme_color_override("font_color", ENTRY_COLOR_DESCRIPTION)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.anchor_right = 1.0
	description.offset_top = ENTRY_DESCRIPTION_TOP_PX
	description.offset_bottom = ENTRY_DESCRIPTION_TOP_PX + ENTRY_DESCRIPTION_HEIGHT_PX
	_top_panel.add_child(description)

	# 中央の扉を隠さず、扉の下側〜床付近に2つの横長ボタンを並べる
	# （デザインリファレンス画像で実測した比率）。HBoxContainerの中央寄せ
	# ＋固定間隔なら、左右の余白・高さ・間隔が自動的に完全対称になる。
	var button_row := HBoxContainer.new()
	button_row.name = "EntryMainButtonRow"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", ENTRY_MAIN_BUTTON_GAP_PX)
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_row.anchor_right = 1.0
	button_row.offset_top = ENTRY_MAIN_BUTTON_TOP_PX
	button_row.offset_bottom = ENTRY_MAIN_BUTTON_TOP_PX + ENTRY_MAIN_BUTTON_SIZE.y
	_top_panel.add_child(button_row)

	var new_button := Button.new()
	new_button.name = "NewBossButton"
	_configure_top_main_button(new_button, "新しいボス戦を作る")
	new_button.pressed.connect(_on_new_pressed)
	button_row.add_child(new_button)

	var edit_button := Button.new()
	edit_button.name = "EditSavedBossButton"
	_configure_top_main_button(edit_button, "保存したボス戦を編集")
	edit_button.pressed.connect(_on_edit_saved_pressed)
	button_row.add_child(edit_button)

	## Step 8 §4: CREATE自体を終了し共通ルート画面へ戻る。メインボタンより
	## 明確に弱い階層にするため、既存のVARIATION_SECONDARY_BUTTON系スタイル
	## （_configure_entry_back_button、無改修）のまま左下へ小さく配置する。
	var back_to_root_button := Button.new()
	back_to_root_button.name = "BackToRootButton"
	back_to_root_button.text = "← 戻る"
	_configure_entry_back_button(back_to_root_button)
	back_to_root_button.pressed.connect(_on_back_to_root_pressed)
	back_to_root_button.anchor_top = 1.0
	back_to_root_button.anchor_bottom = 1.0
	back_to_root_button.offset_left = ENTRY_BACK_BUTTON_MARGIN_PX
	back_to_root_button.offset_top = -ENTRY_BACK_BUTTON_MARGIN_PX - ENTRY_BACK_BUTTON_SIZE.y
	back_to_root_button.offset_bottom = -ENTRY_BACK_BUTTON_MARGIN_PX
	_top_panel.add_child(back_to_root_button)

## メインボタン2つ（「新しいボス戦を作る」「保存したボス戦を編集」）専用の
## 構成。装飾（外枠・細い内枠・四隅の小さな装飾・上辺中央の小さな菱形）は
## 作成方法選択画面のMethodChoiceSurfaceをdialogue=trueでそのまま再利用
## する——完成イメージのボタン意匠と全く同じ紺＋金の系統であるため新規に
## 描画クラスを増やさない。中身は1行の中央揃えラベルのみ（カテゴリ／説明文
## は持たない、完成イメージのボタンも1行のみのため）。
func _configure_top_main_button(button: Button, label_text: String) -> void:
	button.text = ""
	button.tooltip_text = label_text
	button.custom_minimum_size = ENTRY_MAIN_BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _entry_transparent_box())

	var surface := MethodChoiceSurface.new()
	surface.name = "MainButtonSurface"
	surface.dialogue = true
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(surface)

	var label := Label.new()
	label.name = "MainButtonLabel"
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", ENTRY_MAIN_BUTTON_FONT_SIZE)
	label.add_theme_color_override("font_color", METHOD_IVORY)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(label)
	surface.title_label = label

	var refresh := func() -> void:
		surface.set_state(button.is_hovered() or button.has_focus(), button.is_pressed())
	button.mouse_entered.connect(refresh)
	button.mouse_exited.connect(refresh)
	button.focus_entered.connect(refresh)
	button.focus_exited.connect(refresh)
	button.button_down.connect(func() -> void: surface.set_state(button.is_hovered() or button.has_focus(), true))
	button.button_up.connect(func() -> void: surface.set_state(button.is_hovered() or button.has_focus(), false))

func _entry_transparent_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_content_margin_all(0.0)
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

func _configure_entry_back_button(button: Button) -> void:
	button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	button.custom_minimum_size = ENTRY_BACK_BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _entry_back_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", _entry_back_box(Color(ENTRY_COLOR_BACK_HOVER, 0.72), ENTRY_COLOR_ACCENT, 1))
	button.add_theme_stylebox_override("pressed", _entry_back_box(Color(ENTRY_COLOR_BACK_PRESSED, 0.82), ENTRY_COLOR_ACCENT, 1))
	button.add_theme_stylebox_override("focus", _entry_back_box(Color(ENTRY_COLOR_BACK_HOVER, 0.72), ENTRY_COLOR_ACCENT, 1))
	button.add_theme_color_override("font_color", ENTRY_COLOR_DESCRIPTION)
	button.add_theme_color_override("font_hover_color", ENTRY_COLOR_ACCENT_HOVER)
	button.add_theme_color_override("font_pressed_color", ENTRY_COLOR_ACCENT)
	button.add_theme_color_override("font_focus_color", ENTRY_COLOR_ACCENT_HOVER)

func _entry_back_box(fill: Color, border: Color, bottom_border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(0)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	box.border_width_bottom = bottom_border_width
	box.border_color = border
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

## UI改善②: 「新しいボス戦を作る」を押した直後、STEP1へ進む前にSIMPLE/
## ADVANCEDのどちらで作るかをここで一度だけ選ばせる——以後、STEP1〜7の
## 途中でモード切替UIを常時見せない（切替が必要になった場合はSTEP7の
## 最終確認画面から行う、RBMCreatorStep7Summary._on_switch_mode_button_
## pressed()参照）。
##
## 正式アート実装（背景・案内役キャラクター）: この画面だけVBoxContainerの
## 縦積みレイアウトから、背景画像＋キャラクター＋台詞ウィンドウ＋選択肢を
## 層として重ねる構成へ作り直した。既存3ノード名（ChooseSimpleModeButton/
## ChooseAdvancedModeButton/ModeChoiceBackButton、既存テスト・呼び出し元が
## find_child()経由で参照——このファイル冒頭のSEARCH_FIELD_MIN_SIZE同様
## §36で確認済み）と、それぞれの.pressed接続・「後から最終確認画面で
## 変更できます」という既存仕様は無改修のまま維持する。旧ModeChoiceTitle
## Label/ModeChoiceHintLabelは廃止し、台詞ウィンドウ内の新Labelへ役割を
## 統合した（この2ノードは既存テストのいずれからも名前で参照されていない
## ことを事前にgrepで確認済み）。
##
## 背景・案内役キャラクター画像はいずれもユーザー提供の完成アートをそのまま
## 使用（新規AI生成・キャラデザイン変更・衣装変更・色変更は一切行っていない、
## 最終報告参照）。RBMGameRoot.TITLE_IMAGE_PATH+_title_background_fallback/
## _title_backgroundと同じ「STRETCH_KEEP_ASPECT_CENTERED＋EXPAND_IGNORE_
## SIZE」技法をそのまま踏襲——背景は再加工・トリミングせず、アスペクト比を
## 保ったまま1280×720へ収める（4:3画像のため左右にピラーボックスが生じる
## が、_build_ui()冒頭で既に呼んでいるadd_root_background(self)がルート
## 直下に置いた暗色ColorRectがそのまま余白を埋める——専用フォールバックを
## 二重に作る必要はない）。
##
## パフォーマンス上の判断: 背景画像＋案内役キャラクター（2枚のRGBAテクス
## チャ、うち体側は1067×1475）のロード・構築は、実際にこの画面を初めて
## 表示する直前（_show_mode_choice()）まで遅延させる——bossmakerテスト
## スイート全体で計測したところ、RBMCreatorEntryを生成するテストの大半は
## この画面を一度も開かない（別STEPへ直接進む/保存済みstage一覧を使う等）
## にもかかわらず、_build_ui()の中で無条件にこの重い構築を行うと該当しない
## テストにまで一律コストが乗ってしまうことが判明したため（§24「毎フレーム
## 処理の禁止」と同じ精神を、起動時の一括構築コストにも適用した判断）。
func _build_mode_choice_panel() -> void:
	_mode_choice_panel = Control.new()
	_mode_choice_panel.name = "ModeChoicePanel"
	_mode_choice_panel.visible = false
	_mode_choice_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mode_choice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mode_choice_panel)

func _ensure_mode_choice_content_built() -> void:
	if _mode_choice_content_built:
		return
	_mode_choice_content_built = true
	# Character-free selection is constructed directly; keep reusable guide assets intact.
	var background := TextureRect.new()
	background.name = "Background"
	background.texture = load(MODE_CHOICE_BACKGROUND_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_choice_panel.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var world = preload("res://src/bossmaker/rbm_world_ui.gd").new()
	world.method_layout(self)
	world.walk(_mode_choice_panel)

## 作成方法選択画面専用。共有Theme・入口・Creator本体へは適用しない。
const METHOD_INK := Color("#111925")
const METHOD_INK_HOVER := Color("#1c2938")
const METHOD_INK_PRESSED := Color("#0c121b")
const METHOD_GOLD := Color("#756142")
const METHOD_GOLD_LIGHT := Color("#b99b60")
const METHOD_IVORY := Color("#e9dfca")
const METHOD_IVORY_LIGHT := Color("#fff0d4")
const METHOD_MUTED := Color("#aaa495")

## 右側UI仕上げ（2026-09-04）: 3パネル共通の横幅（既存のdialogue_layer/
## choice_buttonsの幅と同じ640——アスペクト比640:371（説明パネル素材の
## 実測比）が既存の説明パネル高さ172とほぼ一致するため、配置を変更せず
## 素材の比率をそのまま活かせる）。選択パネルの高さは素材の実測アスペクト
## 比640:213（=6.42:1）からそのまま導出——「添付画像の素材比率をそのまま
## 強制する必要はない」が、今回は強制せずとも既存配置とちょうど合致した。
## 縦方向の間隔は3パネルとも同じ値に統一する（§5、旧実装は説明パネル→
## SIMPLE間が24px・SIMPLE→HARDCORE間が14pxとバラついていた）。
const MODE_CHOICE_PANEL_WIDTH_PX := 640.0
const MODE_CHOICE_DESCRIPTION_PANEL_HEIGHT_PX := 172.0
const MODE_CHOICE_SELECTION_PANEL_HEIGHT_PX := 100.0
const MODE_CHOICE_PANEL_GAP_PX := 20.0

class MethodChoiceSurface:
	extends Control

	var dialogue := false
	var amount := 0.0
	var target := 0.0
	var pressed := false
	var title_label: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func set_state(highlighted: bool, down: bool) -> void:
		target = 1.0 if highlighted else 0.0
		pressed = down
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		amount = move_toward(amount, target, delta / 0.12)
		if is_instance_valid(title_label):
			title_label.add_theme_color_override("font_color", METHOD_IVORY.lerp(METHOD_IVORY_LIGHT, amount))
		queue_redraw()
		if is_equal_approx(amount, target):
			set_process(false)

	func _draw() -> void:
		var fill := METHOD_INK_PRESSED if pressed else METHOD_INK.lerp(METHOD_INK_HOVER, amount)
		var edge := METHOD_GOLD.lerp(METHOD_GOLD_LIGHT, amount)
		# 不透明な紺の地に、ごく弱い上辺の明度差。背景を透かすガラスにはしない。
		draw_rect(Rect2(Vector2.ZERO, size), fill)
		for y in range(0, int(size.y), 2):
			var strength := 0.025 * (1.0 - float(y) / maxf(size.y, 1.0))
			draw_rect(Rect2(1.0, float(y), size.x - 2.0, 2.0), Color(METHOD_IVORY, strength))
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), edge, false, 1.0)
		draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Color(METHOD_GOLD, 0.25), false, 1.0)
		# 衣装の縁取りに合わせた短い角金具。大きな額縁や紋章は加えない。
		for corner in [Vector2(1, 1), Vector2(size.x - 1, 1), Vector2(1, size.y - 1), size - Vector2.ONE]:
			var direction := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
			draw_line(corner, corner + Vector2(direction.x * 12, 0), edge, 2.0)
			draw_line(corner, corner + Vector2(0, direction.y * 12), edge, 2.0)
		if dialogue:
			var center := Vector2(size.x * 0.5, 6.0)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-4, 0), center + Vector2(0, -3), center + Vector2(4, 0), center + Vector2(0, 3)]), METHOD_GOLD_LIGHT)
		else:
			draw_line(Vector2(2, 20), Vector2(2, size.y - 20), Color(METHOD_GOLD_LIGHT, amount), 3.0)


func _build_list_panel() -> void:
	_list_panel = VBoxContainer.new()
	_list_panel.name = "EntryListPanel"
	_list_panel.visible = false
	_list_panel.anchor_right = 1.0
	_list_panel.offset_left = CONTENT_SIDE_MARGIN_PX
	_list_panel.offset_right = -CONTENT_SIDE_MARGIN_PX
	_list_panel.offset_top = CONTENT_TOP_MARGIN_PX
	add_child(_list_panel)

	var title := Label.new()
	title.name = "EntryListTitleLabel"
	title.text = "保存したボス戦を編集"
	_list_panel.add_child(title)

	var search_row := HBoxContainer.new()
	_list_panel.add_child(search_row)
	_name_search_field = LineEdit.new()
	_name_search_field.name = "NameSearchField"
	_name_search_field.custom_minimum_size = SEARCH_FIELD_MIN_SIZE
	_name_search_field.placeholder_text = "ボス名で検索"
	_name_search_field.text_changed.connect(func(_new_text: String): _refresh_list())
	search_row.add_child(_name_search_field)
	_id_search_field = LineEdit.new()
	_id_search_field.name = "IdSearchField"
	_id_search_field.custom_minimum_size = SEARCH_FIELD_MIN_SIZE
	_id_search_field.placeholder_text = "ステージIDで検索"
	_id_search_field.text_changed.connect(func(_new_text: String): _refresh_list())
	search_row.add_child(_id_search_field)

	_list_rows = VBoxContainer.new()
	_list_rows.name = "StageListRows"
	# Phase 3.5 UI統一§9/§11: RBMChallengeEntryと同じ理由・同じ処置。
	_list_rows.add_theme_constant_override("separation", 10)
	_list_panel.add_child(_list_rows)

	var list_back_button := Button.new()
	list_back_button.name = "ListBackButton"
	list_back_button.text = "戻る"
	list_back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	list_back_button.pressed.connect(_on_list_back_pressed)
	_list_panel.add_child(list_back_button)

	_build_delete_confirm_panel()

func _build_delete_confirm_panel() -> void:
	_delete_confirm_panel = VBoxContainer.new()
	_delete_confirm_panel.name = "DeleteConfirmPanel"
	_delete_confirm_panel.visible = false
	_list_panel.add_child(_delete_confirm_panel)

	_delete_confirm_label = Label.new()
	_delete_confirm_label.name = "DeleteConfirmLabel"
	_delete_confirm_panel.add_child(_delete_confirm_label)

	var delete_row := HBoxContainer.new()
	_delete_confirm_panel.add_child(delete_row)
	var delete_confirm_button := Button.new()
	delete_confirm_button.name = "DeleteConfirmButton"
	delete_confirm_button.text = "削除する"
	delete_confirm_button.pressed.connect(_on_delete_confirmed)
	delete_row.add_child(delete_confirm_button)
	var delete_cancel_button := Button.new()
	delete_cancel_button.name = "DeleteCancelButton"
	delete_cancel_button.text = "キャンセル"
	delete_cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	delete_cancel_button.pressed.connect(_on_delete_cancelled)
	delete_row.add_child(delete_cancel_button)

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

## §32: 下書きも含めすべて表示、状態は都度算出（RBMLocalStageRepository.list()
## 自身が既にstatusをdraft/playable/clear_checkedとして返す）。
## §33: ボス名は大文字小文字を区別しない部分一致、stage_idは10桁完全一致。
func _refresh_list() -> void:
	for child in _list_rows.get_children():
		child.queue_free()
	var name_query := _name_search_field.text
	var id_query := _id_search_field.text
	for entry in RBMLocalStageRepository.list():
		var boss_name := str(entry.get("boss_name", ""))
		var stage_id := str(entry.get("stage_id", ""))
		if not name_query.is_empty() and not boss_name.to_lower().contains(name_query.to_lower()):
			continue
		if not id_query.is_empty() and stage_id != id_query:
			continue
		_add_stage_row(entry)

## §32: 最低限、ボス名/外見/stage_id/状態を表示する。
func _add_stage_row(entry: Dictionary) -> void:
	var stage_id := str(entry.get("stage_id", ""))
	var row := HBoxContainer.new()
	row.name = "StageRow_%s" % stage_id
	_list_rows.add_child(row)

	var status_key := str(entry.get("status", "draft"))
	var status_text: String = STATUS_LABELS.get(status_key, status_key)
	var appearance_id := str(entry.get("appearance_id", ""))
	var appearance_text := RBMCreatorAppearanceCatalog.display_name(appearance_id) if not appearance_id.is_empty() else "（未選択）"

	var label := Label.new()
	label.name = "StageRowLabel"
	label.text = "%s  [%s]  外見:%s  ID:%s" % [str(entry.get("boss_name", "")), status_text, appearance_text, stage_id]
	row.add_child(label)

	var open_button := Button.new()
	open_button.name = "OpenButton"
	open_button.text = "編集"
	open_button.pressed.connect(_on_open_stage_pressed.bind(stage_id))
	row.add_child(open_button)

	var delete_button := Button.new()
	delete_button.name = "DeleteButton"
	delete_button.text = "削除"
	delete_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	delete_button.pressed.connect(_on_delete_stage_pressed.bind(stage_id, str(entry.get("boss_name", ""))))
	row.add_child(delete_button)

## §34/§43: 破損/存在しないstageならstart_loaded()が{"ok":false}を返す——
## クラッシュせず一覧画面に留まるだけで、他の健全なstageは引き続き利用できる。
func _on_open_stage_pressed(stage_id: String) -> void:
	var result := main.start_loaded(stage_id)
	if bool(result.get("ok", false)):
		_show_creator()

# ---------------------------------------------------------------------------
# §41/§42: 削除
# ---------------------------------------------------------------------------

func _on_delete_stage_pressed(stage_id: String, boss_name: String) -> void:
	_delete_target_stage_id = stage_id
	_delete_confirm_label.text = "「%s」を削除しますか？\nステージID：%s\n\nこの操作は取り消せません。" % [boss_name, stage_id]
	_delete_confirm_panel.visible = true

func _on_delete_confirmed() -> void:
	RBMLocalStageRepository.delete(_delete_target_stage_id)
	_delete_confirm_panel.visible = false
	_delete_target_stage_id = ""
	_refresh_list()

func _on_delete_cancelled() -> void:
	_delete_confirm_panel.visible = false
	_delete_target_stage_id = ""

func _on_list_back_pressed() -> void:
	_show_top()

# ---------------------------------------------------------------------------
# §36/§37: Creatorからの退出
# ---------------------------------------------------------------------------

func _on_creator_exited() -> void:
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
	_top_background.visible = true
	_top_panel.visible = true
	_mode_choice_panel.visible = false
	_list_panel.visible = false
	main.visible = false

func _show_mode_choice() -> void:
	_ensure_mode_choice_content_built()
	_top_background.visible = false
	_top_panel.visible = false
	_mode_choice_panel.visible = true
	_list_panel.visible = false
	main.visible = false

func _show_list() -> void:
	_name_search_field.text = ""
	_id_search_field.text = ""
	_delete_confirm_panel.visible = false
	_refresh_list()
	_top_background.visible = false
	_top_panel.visible = false
	_mode_choice_panel.visible = false
	_list_panel.visible = true
	main.visible = false

func _show_creator() -> void:
	_top_background.visible = false
	_top_panel.visible = false
	_mode_choice_panel.visible = false
	_list_panel.visible = false
	main.visible = true

