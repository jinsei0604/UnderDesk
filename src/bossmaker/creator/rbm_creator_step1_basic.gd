class_name RBMCreatorStep1Basic
extends Control

const VisualAssets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")

## Phase 1 Step 4 §1 — STEP 1: ボス名 + 外見選択.
##
## §12（カードUI具体仕様）: 「入力フォームを常時見せる」のではなく「現在の
## 完成状態をカードで見せ、必要な時だけ編集する」——ボス名カード・外見カード
## の2枚を常時表示し、名前入力欄は「編集」を押した時だけカード内へ展開する
## （決定/キャンセルで通常表示へ戻る）。外見選択は既存のRBMCreatorAppearance
## Picker（フルスクリーン切替、confirmed/cancelledシグナル済み）をそのまま
## 再利用——「変更」ボタンで開き、決定/キャンセルでカード表示へ戻る動作は
## 元から満たされていたため、このファイル側の変更は不要だった。
## ボス名の保存形式・文字数制限・validation自体は無改修。

var draft: RBMCreatorDraft
var main: Node  # RBMCreatorMain, kept as Node to avoid a hard cyclic type dependency

var _name_edit: LineEdit
var _char_count_label: Label
var _appearance_button: Button
var _appearance_preview_label: Label
var _appearance_preview_aspect: AspectRatioContainer
var _appearance_preview_surface: Control

var _name_display_label: Label
var _edit_name_button: Button
var _name_normal_row: Control
var _name_edit_row: Control
var _appearance_preview_swatch: TextureRect
var _editing_name := false

## 実機プレイ改善①§12: RBMGameRootと同じ理由・同じ技法。columnの識別
## （view.get_child(0)としての位置づけ）は変えず、column自身のアンカー
## だけを変更する——column.size.y/global_position.yは既存どおり内容量に
## 応じた自然な値のまま（STEP画面のcontent_bottom<nav_top判定など、既存の
## 縦方向レイアウト前提には一切影響しない）。
const CONTENT_SIDE_MARGIN_PX := 80.0
## UI再配色パス: 左STEPナビ/右BOSS PROFILEと上端を揃えるため40→0に変更。
const CONTENT_TOP_MARGIN_PX := 0.0

## 実機プレイ改善② item3: LineEditはHSliderと同じ理由（RBMCreatorStep2Stats
## のCREATOR_SLIDER_MIN_SIZEのコメント参照）でcustom_minimum_sizeを持たない
## 限りテーマ既定の最小サイズ（実測8×16px相当）まで潰れ、MAX_BOSS_NAME_LENGTH
## (20文字)近くまで入力すると文字が見切れる。20文字（全角混在を想定）を
## 快適に編集できるだけの固定幅を明示的に与える——入力中に伸縮する方式では
## なく、既存のLineEdit横スクロール挙動（最大文字数超の入力自体は
## max_lengthが引き続き防ぐ）と組み合わせる。
const BOSS_NAME_EDIT_MIN_SIZE := Vector2(360.0, 32.0)

## 実機確認後の最終UI修正: 将来TextureRectへ差し替えてもカード全体を
## 作り直さずに済む、4:3の大きなプレビュー領域を最初から確保する。
const APPEARANCE_PREVIEW_MIN_SIZE := Vector2(400.0, 300.0)
## Creator本体UI刷新（2026-09-04）§2/§8: 旧値（暖色の茶灰色）は新しい
## 濃紺/青灰色パレットから明確に浮いていたため、RBMCreatorUiKit.
## AppearancePreviewFrame（プレビュー領域自体の暗い紺の地）と調和する、
## わずかに明るい中立の青灰色へ差し替えた。RBMCreatorAppearanceCatalog.
## placeholder_color()（選択済み外見ごとの識別用・意図的に鮮やかなHSV
## 配色、§4によりゲームデータとして無改修）とは別物。
const APPEARANCE_SWATCH_EMPTY_COLOR := Color("#232b38")

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.anchor_right = 1.0
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.offset_top = CONTENT_TOP_MARGIN_PX
	## Creator本体UI刷新（2026-09-04）§1「十分な余白」: 旧実装は既定の
	## VBoxContainer separation（実質ほぼ隙間なし）のまま2枚のカードを
	## 積んでいた。カード同士がくっついて見えないよう、明示的な間隔を持たせる。
	column.add_theme_constant_override("separation", 24)
	add_child(column)

	_build_name_card(column)
	_build_appearance_card(column)

func _build_name_card(parent: Control) -> void:
	var card := PanelContainer.new()
	card.name = "NameCard"
	parent.add_child(card)
	var card_column := VBoxContainer.new()
	card_column.add_theme_constant_override("separation", 10)
	card.add_child(card_column)

	## Creator本体UI刷新（2026-09-04）§6: セクション見出しは本文より一段
	## 大きく、左に小さな銀アクセント（RBMCreatorUiKit.build_section_title()、
	## 今後の他STEPでも再利用する共通ヘルパー）。
	card_column.add_child(RBMCreatorUiKit.build_section_title(tr("ボス名")))

	## §7: 左に現在の名前、右に操作ボタン、という横方向の構成。
	## _name_display_labelをSIZE_EXPAND_FILLにして残り幅を占有させることで、
	## ボタンをカード右端へ押し出す（添付デザインの左右分割そのもの——
	## ボタン自身のtext/node名は既存回帰テストの厳密一致対象のため無改修）。
	_name_normal_row = HBoxContainer.new()
	_name_normal_row.name = "NameNormalRow"
	card_column.add_child(_name_normal_row)
	_name_display_label = Label.new()
	_name_display_label.name = "NameDisplayLabel"
	_name_display_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_normal_row.add_child(_name_display_label)
	_edit_name_button = Button.new()
	_edit_name_button.name = "EditNameButton"
	_edit_name_button.pressed.connect(_on_edit_name_pressed)
	_name_normal_row.add_child(_edit_name_button)

	_name_edit_row = HBoxContainer.new()
	_name_edit_row.name = "NameEditRow"
	_name_edit_row.visible = false
	card_column.add_child(_name_edit_row)
	_name_edit = LineEdit.new()
	_name_edit.name = "BossNameEdit"
	_name_edit.custom_minimum_size = BOSS_NAME_EDIT_MIN_SIZE
	_name_edit.max_length = RBMCreatorDraft.MAX_BOSS_NAME_LENGTH
	_name_edit.text_changed.connect(_on_name_edit_text_changed)
	_name_edit_row.add_child(_name_edit)
	_char_count_label = Label.new()
	_char_count_label.name = "CharCountLabel"
	_name_edit_row.add_child(_char_count_label)
	var confirm_button := Button.new()
	confirm_button.name = "ConfirmNameButton"
	confirm_button.text = tr("決定")
	confirm_button.pressed.connect(_on_confirm_name_pressed)
	_name_edit_row.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelNameButton"
	cancel_button.text = tr("キャンセル")
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_cancel_name_pressed)
	_name_edit_row.add_child(cancel_button)

## Creator本体UI刷新（2026-09-04）§8: ボスイラスト表示領域をこのセクション
## の主役にする。旧実装は「プレビュー→説明文→ボタン」の縦積みで、プレビュー
## が単なる仮領域の1要素に見えていた——プレビューを左、説明文＋「外見を
## 変更」ボタンを右（プレビューと同じ高さの範囲で縦中央寄せ）に配置する
## 横並びへ変更し、「プレビュー領域の右側」（§8）という配置をそのまま
## 実現する。ノード名・親子の役割（_appearance_preview_surfaceが
## _appearance_preview_aspectの子である等、既存回帰テストが検証する構造）
## は一切変更していない——追加したのはpreview_row/info_columnという
## 2つの新しいレイアウト用コンテナのみ。
func _build_appearance_card(parent: Control) -> void:
	var card := PanelContainer.new()
	card.name = "AppearanceCard"
	parent.add_child(card)
	var card_column := VBoxContainer.new()
	card_column.add_theme_constant_override("separation", 12)
	card.add_child(card_column)

	card_column.add_child(RBMCreatorUiKit.build_section_title(tr("外見")))

	var preview_row := HBoxContainer.new()
	preview_row.name = "AppearancePreviewRow"
	preview_row.add_theme_constant_override("separation", 24)
	card_column.add_child(preview_row)

	_appearance_preview_aspect = AspectRatioContainer.new()
	_appearance_preview_aspect.name = "AppearancePreviewAspect"
	_appearance_preview_aspect.custom_minimum_size = APPEARANCE_PREVIEW_MIN_SIZE
	_appearance_preview_aspect.ratio = 4.0 / 3.0
	_appearance_preview_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	preview_row.add_child(_appearance_preview_aspect)

	## 「ボスプレビュー領域」として認識できる見た目（暗い紺の地＋細い枠＋
	## 四隅の短い銀コーナーライン）はRBMCreatorUiKit.AppearancePreviewFrame
	## （共通描画クラス）が担う——中身（ColorRect/placeholder、将来の
	## TextureRect）はこれまでどおりこの上に子として重ねる。
	_appearance_preview_surface = RBMCreatorUiKit.AppearancePreviewFrame.new()
	_appearance_preview_surface.name = "AppearancePreviewSurface"
	_appearance_preview_aspect.add_child(_appearance_preview_surface)
	_appearance_preview_swatch = TextureRect.new()
	_appearance_preview_swatch.name = "AppearancePreviewSwatch"
	_appearance_preview_swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_appearance_preview_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_appearance_preview_swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_appearance_preview_swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_appearance_preview_swatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_appearance_preview_surface.add_child(_appearance_preview_swatch)
	var placeholder_center := CenterContainer.new()
	placeholder_center.name = "AppearancePreviewPlaceholderCenter"
	placeholder_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	placeholder_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_appearance_preview_surface.add_child(placeholder_center)
	var placeholder_label := Label.new()
	placeholder_label.name = "AppearancePreviewPlaceholderLabel"
	placeholder_label.text = tr("ボスイラスト表示領域")
	placeholder_center.add_child(placeholder_label)

	var info_column := VBoxContainer.new()
	info_column.name = "AppearanceInfoColumn"
	info_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	## UI再配色パス: 左右STEPナビ/BOSS PROFILE幅の底上げで中央エリアが
	## 少し狭くなった分、外見名が長い場合にカード外へはみ出さないよう、
	## 残り幅いっぱいへ広げてから折り返す(SIZE_EXPAND_FILL+autowrap)。
	info_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_column.add_theme_constant_override("separation", 12)
	preview_row.add_child(info_column)

	_appearance_preview_label = Label.new()
	_appearance_preview_label.name = "AppearancePreviewLabel"
	_appearance_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_column.add_child(_appearance_preview_label)

	_appearance_button = Button.new()
	_appearance_button.name = "AppearanceButton"
	_appearance_button.text = tr("外見を変更")
	_appearance_button.pressed.connect(_on_appearance_button_pressed)
	info_column.add_child(_appearance_button)

func _on_edit_name_pressed() -> void:
	_editing_name = true
	_name_edit.text = draft.boss_name
	refresh()

## §12-2: 編集中はドラフトへ書き込まない（文字数表示だけを実測テキストから
## 都度更新する）——「決定」を押すまでキャンセルで元へ戻せることの前提。
func _on_name_edit_text_changed(value: String) -> void:
	_char_count_label.text = "%d / %d" % [value.length(), RBMCreatorDraft.MAX_BOSS_NAME_LENGTH]

func _on_confirm_name_pressed() -> void:
	_editing_name = false
	set_boss_name(_name_edit.text)

func _on_cancel_name_pressed() -> void:
	_editing_name = false
	refresh()

## §12外の既存プログラム的API——テスト/呼び出し元がUIを経由せず直接ボス名を
## 設定するための経路（実機UIの「編集→決定」フローとは独立して常に即座に
## ドラフトへ反映する、既存の挙動をそのまま維持）。
func set_boss_name(value: String) -> void:
	# LineEdit.max_length already prevents typing past 20 chars through real
	# input, but this API is also used directly by tests/callers.
	draft.boss_name = value.substr(0, RBMCreatorDraft.MAX_BOSS_NAME_LENGTH)
	refresh()

func _on_appearance_button_pressed() -> void:
	main.open_appearance_picker()

func refresh() -> void:
	_name_normal_row.visible = not _editing_name
	_name_edit_row.visible = _editing_name
	if draft.boss_name.is_empty():
		_name_display_label.text = tr("まだ設定されていません")
		_edit_name_button.text = tr("名前を決める")
	else:
		_name_display_label.text = draft.boss_name
		_edit_name_button.text = tr("編集")
	if not _editing_name:
		_name_edit.text = draft.boss_name
		_char_count_label.text = "%d / %d" % [draft.boss_name.length(), RBMCreatorDraft.MAX_BOSS_NAME_LENGTH]

	if draft.appearance_id.is_empty():
		_appearance_preview_label.text = tr("（未選択）")
		_appearance_preview_swatch.texture = null
	else:
		_appearance_preview_label.text = tr("現在の外見：%s") % RBMCreatorAppearanceCatalog.display_name(draft.appearance_id)
		_appearance_preview_swatch.texture = VisualAssets.texture(VisualAssets.boss_asset(draft.appearance_id), 0)
	_appearance_preview_surface.get_node("AppearancePreviewPlaceholderCenter").visible = _appearance_preview_swatch.texture == null

func is_step_valid() -> bool:
	return draft.step1_is_valid()

## Creator本体UI最終調整（2026-09-05）: 「ボス名を入力してください」は
## ヘッダー直下の共有ステータス行（RBMCreatorMain._status_label）へ単独で
## 表示されていたが、STEP1が既に持つ「ボス名」セクション自体（「まだ設定
## されていません」＋「名前を決める」）と情報が重複し、刷新前のガイド
## 表示が残っているように見えるとの判断で削除した——「次へ」を無効化する
## is_step_valid()自体（draft.step1_is_valid()）は無改修のまま、名前未入力
## の間は引き続き次工程へ進めない。文字数超過（現状LineEdit側のmax_length
## で入力自体を防いでおり到達しないが、テスト等の直接API経由では起こり
## うる）のメッセージは今回の削除対象外のため無改修のまま維持する。
func validation_message() -> String:
	if draft.boss_name.is_empty():
		return ""
	return tr("ボス名は%d文字以内にしてください") % RBMCreatorDraft.MAX_BOSS_NAME_LENGTH

