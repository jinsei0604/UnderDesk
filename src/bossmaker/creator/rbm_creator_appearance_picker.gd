class_name RBMCreatorAppearancePicker
extends Control

const VisualAssets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")

## Phase 1 Step 4 §1-3 — dedicated "ボス外見一覧" page (grid, current-selection
## highlight, 選択/戻る). Grid is built directly from
## RBMCreatorAppearanceCatalog.all(), so adding more entries later needs no
## change here.
##
## 画面全体を使ったレイアウト・即決定への再設計(2回目の改修)§1-2: この
## Controlは_steps_root(RBMCreatorMain.gd)と同じ「root_column(VBoxContainer)
## の兄弟」として配置される——_steps_rootがsize_flags_vertical=EXPAND_FILLを
## 明示しているのと同じ理由で、これを付けないとroot_column内で自分の
## 最小サイズ(=中身が小さい間はごく小さい矩形)しか確保できず、「画面左上に
## 小さくまとまる」原因になっていた。

signal confirmed(appearance_id: String)
signal cancelled

## カード1枚のサイズ——「ボス画像が主役、名前は下に添える」構成で、画像
## 表示領域(IMAGE_AREA_MIN_SIZE)がカード全体の残り高さをsize_flags_vertical=
## EXPAND_FILLで自動的に占有するため、覚醒対応カード(バッジ+切替ボタン行が
## 追加で挟まる)でも非対応カードでも、ハードコードした個別倍率無しで
## 「画像が7〜8割」の見え方になる。
const CARD_SIZE := Vector2(340, 260)
const CARD_INNER_MARGIN := 12
const CARD_SEPARATION := 6
## 画像表示領域の最小サイズ——旧実装の200x96よりさらに拡大。実際の表示
## サイズはEXPAND_FILLによりこれより大きくなる(カード内の余った高さを
## 全て画像へ渡すため)。
const IMAGE_AREA_MIN_SIZE := Vector2(280, 160)
const GRID_SEPARATION := 24
## 「戻る」ボタンの下に置く行と、画面全体に対する余白——RBMCreatorTestBattleView
## の CONTENT_SIDE_MARGIN_PX/CONTENT_TOP_MARGIN_PX と同じ技法(この画面自身の
## 矩形いっぱいにanchorしたcolumnへ、offsetでピクセル単位の余白を持たせる)。
const CONTENT_SIDE_MARGIN_PX := 60.0
const CONTENT_TOP_MARGIN_PX := 40.0
const CONTENT_BOTTOM_MARGIN_PX := 24.0
## バッジ/切替ボタンはどちらもこの小さいフォントサイズへ揃える——控えめな
## 補助表示として統一する。
const OVERLAY_FONT_SIZE := RBMUiTheme.FONT_SIZE_SMALL

var _selected_id: String = ""
var _opened_with_id: String = ""
var _entry_buttons: Dictionary = {}  # id(String) -> Button（カード全体そのもの）
## 覚醒(Awakening)後プレビュー——カードごとに完全に独立した状態
## (id -> bool)。あるカードの切替が他のカードへ波及しないようにするため、
## 単一の共有状態ではなく必ずid別に保持する。
var _preview_awakened: Dictionary = {}  # id(String) -> bool
var _preview_swatches: Dictionary = {}  # id(String) -> TextureRect
var _preview_toggle_buttons: Dictionary = {}  # id(String) -> Button（覚醒対応の外見のみ存在）

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.name = "Column"
	column.anchor_right = 1.0
	column.anchor_bottom = 1.0
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.offset_top = CONTENT_TOP_MARGIN_PX
	column.offset_bottom = -CONTENT_BOTTOM_MARGIN_PX
	add_child(column)
	column.add_child(Label.new())  # title placeholder

	## グリッド自体はカードの最小サイズぶんしか場所を取らないため、
	## 余った縦横の空間はCenterContainerで中央へ寄せる——「画面全体を使う」
	## ことと「カード同士を無理に密着・引き伸ばしさせない」ことを両立する。
	var grid_center := CenterContainer.new()
	grid_center.name = "GridCenter"
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(grid_center)

	var grid := GridContainer.new()
	grid.name = "AppearanceGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", GRID_SEPARATION)
	grid.add_theme_constant_override("v_separation", GRID_SEPARATION)
	grid_center.add_child(grid)
	for entry in RBMCreatorAppearanceCatalog.all():
		_build_card(grid, entry)

	var actions := HBoxContainer.new()
	column.add_child(actions)
	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = tr("戻る")
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(_on_back_pressed)
	actions.add_child(back_button)

## `entry`はRBMCreatorAppearanceCatalog.all()の1件と同じ形
## ({"id","name","supports_awakening"})——実運用では常にそこから呼ぶが、
## 独立したメソッドに切り出してあるのは、既存6体の外見が全てsupports_
## awakening=falseの間でも、「覚醒対応の外見が来たらどう描画するか」を
## テスト側がその場限りのfixture Dictionaryを直接渡して検証できるように
## するため(RBMCreatorAppearanceCatalog.ENTRIESはGodotのconstとして
## 実行時読み取り専用のため書き換えられない——本物のボスデータを勝手に
## 覚醒対応へ変更せずに済む)。
##
## カード構造の再設計§5-7/§9: カード全体(画像+名前+バッジ/切替ボタン)を
## 1つのButton(`card`)にし、押した瞬間に選択即決定する。中身の画像/名前/
## バッジ等は`mouse_filter = MOUSE_FILTER_IGNORE`にして、クリックが自分の
## 手前で消費されず必ず`card`まで届くようにする——ただし「覚醒後を見る」
## トグルボタンだけは実在のButtonのまま(既定のMOUSE_FILTER_STOP)残すため、
## そのボタン領域を押した場合はGodotの通常のヒットテスト(最も手前の実在
## Controlが優先される)によって`card`側のpressedは発火しない。
func _build_card(grid: GridContainer, entry: Dictionary) -> void:
	var id := str(entry["id"])
	var supports_awakening: bool = bool(entry.get("supports_awakening", false))

	var card := Button.new()
	card.name = "Appearance_%s" % id
	card.toggle_mode = true
	card.custom_minimum_size = CARD_SIZE
	card.pressed.connect(_on_card_pressed.bind(id))
	grid.add_child(card)
	_entry_buttons[id] = card

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", CARD_INNER_MARGIN)
	margin.add_theme_constant_override("margin_right", CARD_INNER_MARGIN)
	margin.add_theme_constant_override("margin_top", CARD_INNER_MARGIN)
	margin.add_theme_constant_override("margin_bottom", CARD_INNER_MARGIN)
	card.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", CARD_SEPARATION)
	margin.add_child(content)

	## 画像表示領域: size_flags_vertical=EXPAND_FILLにより、カード内で
	## 名前ラベル(・覚醒対応カードのみ追加される下記overlay_row)が使う分を
	## 除いた残り高さを丸ごと画像に渡す——「画像が主役」をボスごとの
	## 特別扱い無しで実現する。
	var preview_area := Control.new()
	preview_area.name = "AppearancePreviewArea_%s" % id
	preview_area.custom_minimum_size = IMAGE_AREA_MIN_SIZE
	preview_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(preview_area)

	var swatch := TextureRect.new()
	swatch.name = "AppearancePreview_%s" % id
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	swatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_area.add_child(swatch)
	_preview_swatches[id] = swatch
	_preview_awakened[id] = false

	if supports_awakening:
		## バッジ/切替ボタンは、画像の上に重ねるのではなく画像の「下」の
		## 専用の行に置く——画像・名前・バッジ・ボタンのいずれとも重ならない
		## ようにするため(前回のGPU検証で発見した重なりバグの再発防止)。
		var overlay_row := HBoxContainer.new()
		overlay_row.name = "AwakeningOverlayRow_%s" % id
		overlay_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(overlay_row)

		var toggle_button := Button.new()
		toggle_button.name = "AwakenedPreviewToggle_%s" % id
		toggle_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
		toggle_button.text = tr("覚醒後を見る")
		toggle_button.add_theme_font_size_override("font_size", OVERLAY_FONT_SIZE)
		# B項: supports_awakening==trueでも覚醒後アセットがまだ制作
		# されていない場合はdisabledにする——「覚醒対応」と「素材が
		# 実在する」は別概念(§3確定)。
		toggle_button.disabled = not VisualAssets.has_awakened_design(VisualAssets.boss_asset(id))
		toggle_button.pressed.connect(_on_preview_toggle_pressed.bind(id))
		overlay_row.add_child(toggle_button)
		_preview_toggle_buttons[id] = toggle_button

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_row.add_child(spacer)

		var badge := Label.new()
		badge.name = "AwakeningCapableBadge_%s" % id
		badge.text = tr("覚醒可能")
		badge.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		overlay_row.add_child(badge)

	_refresh_preview_texture(id)

	var name_label := Label.new()
	name_label.name = "AppearanceName_%s" % id
	name_label.text = tr(str(entry["name"]))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)

## 画面を開き直すたびに、全カードのプレビューを必ず通常状態へ戻す——
## 前回覚醒後を見ていた状態を持ち越さない（確定仕様）。ボス選択そのもの
## (_selected_id/select())とは完全に別の状態のため、ここでは触れない。
func open(current_appearance_id: String) -> void:
	_opened_with_id = current_appearance_id
	for id in _preview_awakened.keys():
		_preview_awakened[id] = false
		_refresh_preview_texture(id)
	select(current_appearance_id)

func select(appearance_id: String) -> void:
	_selected_id = appearance_id
	for id in _entry_buttons.keys():
		(_entry_buttons[id] as Button).button_pressed = (id == appearance_id)

## カード(画像+名前を含むカード全体)を押した瞬間に選択即決定する——
## 二段階確認(旧「決定」ボタン)は廃止(§6-7確定)。
func _on_card_pressed(id: String) -> void:
	select(id)
	confirmed.emit(id)

## 覚醒後プレビュー切替——これはあくまで画像プレビューであり、ボス選択
## 操作(_selected_id/select()/confirmedシグナル)には一切触れない。押した
## カードのidだけを更新するため、他のカードの表示には波及しない。
## card自体のButtonより手前にある実在のButtonのため、Godotの通常の
## ヒットテストにより、このボタンを押してもcardのpressedは発火しない
## (§9確定)。
func _on_preview_toggle_pressed(id: String) -> void:
	_preview_awakened[id] = not bool(_preview_awakened.get(id, false))
	_refresh_preview_texture(id)

func _refresh_preview_texture(id: String) -> void:
	var swatch: TextureRect = _preview_swatches.get(id)
	if not is_instance_valid(swatch):
		return
	var asset_id := VisualAssets.boss_asset(id)
	var awakened: bool = bool(_preview_awakened.get(id, false))
	var effective_asset_id := VisualAssets.awakened_asset_id(asset_id) if awakened else asset_id
	swatch.texture = VisualAssets.texture(effective_asset_id, 0)
	var toggle_button: Button = _preview_toggle_buttons.get(id)
	if is_instance_valid(toggle_button):
		toggle_button.text = tr("通常時を見る") if awakened else tr("覚醒後を見る")

## 「戻る」は選択内容を変更しない——開いた時点のboss idへ表示上のハイライト
## だけ戻してから閉じる(§8確定)。
func _on_back_pressed() -> void:
	select(_opened_with_id)
	cancelled.emit()
