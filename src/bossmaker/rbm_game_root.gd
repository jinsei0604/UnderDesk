class_name RBMGameRoot
extends Control

## Makers & Challengersの起動ルート。project.godotから直接起動する。
##
## CREATE/CHALLENGEを選択する共通画面を持ち、既存の確定済みRBMCreatorEntry
## （Step 6）・RBMChallengeEntry（Step 7）を「1つだけ生成して保持し、
## 表示/非表示を切り替える」という、この2クラス自身が既に内部で使っている
## のと同じ設計パターンでそのまま子として保有する——両クラスの内部ロジック
## （STEP1〜7・TEST BATTLE・Clear Check・保存・一覧・検索・確認画面・戦闘・
## REWIND無し・restart・quit）には一切変更を加えていない。
##
## §4/§5: 各Entryへの出入りは、双方に新設した`exit_requested`シグナルと
## `enter_create()`/`enter_challenge()`という薄い公開メソッド経由のみで
## 行う——このルート自身がEntry内部のprivate状態へ直接触れることは無い。

var _title_screen: Control
var _title_background_fallback: ColorRect
var _title_background: TextureRect
var _title_effects: RBMTitleEffects
var _menu_panel: Control
var _create_button: Button
var _challenge_button: Button

var creator_entry: RBMCreatorEntry
var challenge_entry: RBMChallengeEntry

func _ready() -> void:
	## Step 8 最終最小修正 §1: このシーンルート自身にはControlの親が存在
	## しないため、サイズはビューポートに対して手動で同期する必要がある
	## （project.godotのwindow/stretch/mode="canvas_items"設定下で、単純に
	## Control.set_anchors_preset(FULL_RECT)を呼ぶだけでは実際のsizeが(0,0)
	## のままになる現象を確認済み）。
	##
	## 前回の実装はTOP_LEFT→FULL_RECT(PRESET_MODE_KEEP_SIZE)というアンカー
	## 切替を毎回行っており、これがCodex指摘どおり2回目以降の呼び出しで
	## サイズが親サイズ分加算される不具合（1280x720のはずが2560x1440へ
	## 倍化）の原因だった——FULL_RECTアンカーを一度でも適用した後にTOP_LEFT
	## へ戻すと、直前の（既にFULL_RECTとして解決済みの）実座標を「そのまま
	## 維持する」形でoffsetが再計算され、次にFULL_RECT(KEEP_SIZE)へ戻す際に
	## その実座標へさらにビューポート分のoffsetが加算されてしまっていた。
	##
	## 修正: アンカーを一切変更せず、常にTOP_LEFT（既定、非stretch、
	## anchor_left==anchor_right==anchor_top==anchor_bottom==0）のまま
	## position/sizeを直接ビューポートへ同期する——アンカー切替という
	## 可変な中間状態が無いため、何度呼んでも同じ入力(get_viewport_rect())
	## に対して同じ出力になる（加算されない）。TOP_LEFTアンカーへ.sizeを
	## 書き込むこと自体はGodotの警告対象外（警告は「非対称なopposite
	## anchors」＝stretch系アンカーのみが対象）。creator_entry/
	## challenge_entry自身は既存どおりFULL_RECTアンカーでこのルートの
	## rectいっぱいに広がる——このルート自身のposition/sizeが正しくなり
	## さえすれば、その先の連鎖（main/各STEPビュー等）は無改修のまま
	## 正しく機能する。
	## ウィンドウが後からリサイズされた場合（window/size/resizable=true）
	## にも追従できるようWindow.size_changedへ1回だけ接続する（多重接続
	## 防止のため_ready()内の一度きりの接続のみ、毎フレーム同期はしない）。
	_sync_size_to_viewport()
	get_tree().root.size_changed.connect(_on_root_window_size_changed)
	_build_ui()
	_se_audio = preload("res://src/bossmaker/rbm_audio.gd").for_owner(self)
	_se_audio.bind_ui(self)
	get_tree().node_added.connect(_se_node_added)

func _on_root_window_size_changed() -> void:
	_sync_size_to_viewport()

func _sync_size_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

## 実機プレイ改善①§12: 主要UIが画面左上へ寄りすぎていた（各画面の内容
## VBoxContainerがbareなControlの子として既定のTOP_LEFTアンカー・自然サイズ
## のまま、offset無しでx=0,y=0に直接置かれていたため）。個々の内容の並び・
## ロジック・値は一切変更せず、各画面の最上位VBoxContainer自身の水平方向
## だけをストレッチアンカー化し左右に同じ余白を持たせる（＝水平方向のみ
## 中央寄せ）＋上端にも小さな余白を追加する——縦方向は既存どおり内容量に
## 応じた自然な高さのまま（STEP3のスキル一覧等、内容が動的に増減する画面を
## 無理に垂直中央寄せすると表示のたびに大きく上下へ跳ねるため、意図的に
## 縦方向は変更しない）。「全部のControlを完全な画面中央一点へ寄せる」の
## ではなく、左右の余白によって視線が中央付近へ来る程度の調整に留める。
const CONTENT_SIDE_MARGIN_PX := 80.0

## タイトル画面完成アート反映 — 採用された完成画像（Makers & Challengers、
## ロゴ・背景・「挑戦」「作成」ボタンの絵まで全て含む1枚絵）。§1により
## Claude Code側でこの画像を再加工/再生成/トリミングし直すことは禁止
## されているため、ここでは配置のみを行う。
const TITLE_IMAGE_PATH := "res://assets_bossmaker/art/title_screen_makers_and_challengers.png"

## 完成画像自身のピクセル解像度と、その中に描かれた「挑戦」「作成」ボタン絵
## の外接矩形（画像ピクセル座標）。tools/配下の使い捨てスクリプト
## （グリッド線付きクロップを目視して実測、確認後に削除済み）で測定した値
## そのもの——目分量の当て推量ではなく実測値。この矩形を画像サイズに対する
## 比率へ変換し、実行時のControlサイズに関わらず正しい位置へ透明クリック
## 領域を配置する（_apply_image_fraction_rect参照）。
const TITLE_IMAGE_SIZE := Vector2(1672.0, 941.0)
const CHALLENGE_BUTTON_PIXEL_RECT := Rect2(518.0, 775.0, 290.0, 97.0)
const CREATE_BUTTON_PIXEL_RECT := Rect2(860.0, 775.0, 290.0, 97.0)

## pixel_rect（TITLE_IMAGE_SIZE基準のピクセル座標）をTITLE_IMAGE_SIZEに対する
## 比率へ変換し、controlのアンカーとして設定する（offsetは全て0——アンカー
## 自体が最終位置を表す）。controlの親（またはその祖先の連鎖）が_title_screen
## と同じFULL_RECT矩形である前提——static化してRBMTitleEffectsからも共有
## する（タイトル画面ループ演出追加、発光点の座標変換に同じロジックが必要
## なため、重複実装せずこちらを再利用する）。
static func apply_image_fraction_rect(control: Control, pixel_rect: Rect2) -> void:
	control.anchor_left = pixel_rect.position.x / TITLE_IMAGE_SIZE.x
	control.anchor_right = (pixel_rect.position.x + pixel_rect.size.x) / TITLE_IMAGE_SIZE.x
	control.anchor_top = pixel_rect.position.y / TITLE_IMAGE_SIZE.y
	control.anchor_bottom = (pixel_rect.position.y + pixel_rect.size.y) / TITLE_IMAGE_SIZE.y
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = 0.0
	control.offset_bottom = 0.0

func _build_ui() -> void:
	# §8: このThemeはタイトル画面コンテナ自身にだけ設定する（RBMGameRoot自体
	# には設定しない）——Godotの継承カスケードでCreator/Challengeの各STEP
	# 画面（今回意図的に再デザインしない）へ副作用が及ぶのを避けるための
	# 意図的なスコープ限定（詳細はRBMUiTheme冒頭コメント参照）。
	_title_screen = Control.new()
	_title_screen.name = "TitleScreen"
	_title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_screen.theme = RBMUiTheme.build_theme()
	add_child(_title_screen)

	# タイトル画面完成アート反映§4/§5: 背景は完成画像そのもの。
	# ①COLOR_BACKGROUNDの単色ベース（常時表示、STRETCH_KEEP_ASPECT_CENTERED
	# が縦横比を保ったまま画像を収めた際にごく僅かに生じ得るレターボックス
	# 隙間の色として使う——画像自体は1672:941≒16:9でproject.godot側の
	# 基準解像度（1280x720、window/stretch/aspect="keep"によりget_viewport_
	# rect()は常にこの16:9比を保つ）とほぼ一致するため、実際の隙間は
	# 1280x720基準でごく僅少）②完成画像本体（STRETCH_KEEP_ASPECT_CENTERED
	# ＝縦横比を保ったまま画面全体へ収める、引き伸ばし・トリミングなし）。
	_title_background_fallback = ColorRect.new()
	_title_background_fallback.name = "TitleBackgroundFallback"
	_title_background_fallback.color = RBMUiTheme.COLOR_BACKGROUND
	_title_background_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_background_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(_title_background_fallback)

	_title_background = TextureRect.new()
	_title_background.name = "TitleBackground"
	_title_background.texture = load(TITLE_IMAGE_PATH)
	_title_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(_title_background)

	# タイトル画面 ループ演出追加 §9: 完成静止画(_title_background)と操作
	# ボタン(ChallengeModeButton/CreateModeButton)の間に挟む、独立した演出
	# レイヤー。背景画像には一切触れず、炎/魔力装置/ボスの目の3種類の軽量
	# ループ演出だけをここへ重ねる（詳細はRBMTitleEffects冒頭コメント参照）。
	_title_effects = RBMTitleEffects.new()
	_title_effects.name = "TitleEffects"
	_title_effects.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(_title_effects)

	# §3/§6: 既存の"_menu_panel"という名前・左右CONTENT_SIDE_MARGIN_PXの
	# 余白は既存テストが直接参照するため維持する——ただし完成画像がタイトル
	# ロゴ・ボタン絵まで全て担うため、このPanel自身には今回何も追加しない
	# （空のプレースホルダーとして残すだけ、後方互換のためのみ存在）。
	_menu_panel = Control.new()
	_menu_panel.name = "GameRootMenuPanel"
	_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_panel.offset_left = CONTENT_SIDE_MARGIN_PX
	_menu_panel.offset_right = -CONTENT_SIDE_MARGIN_PX
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(_menu_panel)

	# §3: 旧・文字ベースの仮タイトル「RPG BOSS MAKER」は削除——完成画像自身
	# がロゴを含むため二重表示になる。

	# §3/§6/§7: 「挑戦」「作成」——完成画像に描かれたボタン絵の位置へ透明な
	# クリック領域を重ねる（画像は_title_backgroundが担当、Godot側は入力
	# 判定のみ）。_title_background自身（またはそのアンカーコンテナである
	# _title_screen）へ直接アンカーする——TITLE_IMAGE_SIZE基準の比率と
	# STRETCH_KEEP_ASPECT_CENTEREDの実際の表示矩形はこのproject.godot設定
	# 下ではほぼ一致するため、_apply_image_fraction_rect()の比率アンカー
	# だけで正確に重なる（TextureRectの内部フィット計算を複製する必要が
	# 無い）。ノード名"ChallengeModeButton"/"CreateModeButton"・text値
	# ("挑戦"/"作成"、テキストは非表示だが既存テスト互換のため保持）・
	# シグナル配線は無改修。
	_challenge_button = Button.new()
	_challenge_button.name = "ChallengeModeButton"
	_challenge_button.text = "挑戦"
	_challenge_button.theme_type_variation = RBMUiTheme.VARIATION_IMAGE_HOTSPOT_BUTTON
	_challenge_button.focus_mode = Control.FOCUS_ALL
	apply_image_fraction_rect(_challenge_button, CHALLENGE_BUTTON_PIXEL_RECT)
	_challenge_button.pressed.connect(_on_challenge_pressed)
	_title_screen.add_child(_challenge_button)

	_create_button = Button.new()
	_create_button.name = "CreateModeButton"
	_create_button.text = "作成"
	_create_button.theme_type_variation = RBMUiTheme.VARIATION_IMAGE_HOTSPOT_BUTTON
	_create_button.focus_mode = Control.FOCUS_ALL
	apply_image_fraction_rect(_create_button, CREATE_BUTTON_PIXEL_RECT)
	_create_button.pressed.connect(_on_create_pressed)
	_title_screen.add_child(_create_button)

	creator_entry = RBMCreatorEntry.new()
	creator_entry.name = "CreatorEntry"
	creator_entry.set_anchors_preset(Control.PRESET_FULL_RECT)
	creator_entry.visible = false
	creator_entry.exit_requested.connect(_on_creator_exit_requested)
	add_child(creator_entry)

	challenge_entry = RBMChallengeEntry.new()
	challenge_entry.name = "ChallengeEntry"
	challenge_entry.set_anchors_preset(Control.PRESET_FULL_RECT)
	challenge_entry.visible = false
	challenge_entry.exit_requested.connect(_on_challenge_exit_requested)
	add_child(challenge_entry)

	_show_menu()

func _on_create_pressed() -> void:
	creator_entry.enter_create()
	_show_only(creator_entry)

func _on_challenge_pressed() -> void:
	challenge_entry.enter_challenge()
	_show_only(challenge_entry)

func _on_creator_exit_requested() -> void:
	_show_menu()

func _on_challenge_exit_requested() -> void:
	_show_menu()

## _title_screen（背景2層＋_menu_panelを内包する共通の親）を切り替える——
## _menu_panelだけを切り替えると、そのsiblingである背景レイヤー
## （_title_background_fallback/_title_background）だけがCreator/Challenge
## 画面の裏に残ったまま表示され続けてしまう（_menu_panelを追加した際に
## 発見・修正した実バグ）。_menu_panel.visible自体も既存テストが直接参照
## するため引き続き同期して更新する。
func _show_menu() -> void:
	_title_screen.visible = true
	_menu_panel.visible = true
	creator_entry.visible = false
	challenge_entry.visible = false

func _show_only(node: Control) -> void:
	_title_screen.visible = false
	_menu_panel.visible = false
	creator_entry.visible = (node == creator_entry)
	challenge_entry.visible = (node == challenge_entry)

var _se_audio: Node
func _se_node_added(node: Node) -> void:
	if is_ancestor_of(node) and node is BaseButton:
		_se_bind_deferred.call_deferred(weakref(node))

func _se_bind_deferred(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if is_instance_valid(node) and is_instance_valid(_se_audio) and node.is_inside_tree():
		_se_audio.bind_ui(node)
