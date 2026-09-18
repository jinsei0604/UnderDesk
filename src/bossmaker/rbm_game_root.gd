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
var _locale_button: Button
var _title_boot_launcher: RBMTitleBootLauncher
var _challenge_monitor: RBMHomeMonitorPanel
var _creator_monitor: RBMHomeMonitorPanel
var _challenge_monitor_sfx: RBMHomeMonitorSfx
var _creator_monitor_sfx: RBMHomeMonitorSfx

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

## ホーム画面3モニター背景反映(承認済み独立プレビューの本実装): 採用された
## 完成画像(Makers & Challengers、上中央/左下/右下の3モニター枠を含む
## 1枚絵)。背景画像自体の再加工/再生成/トリミングは禁止されているため、
## ここでは配置のみを行う。旧・完成画像(title_screen_makers_and_challengers.png、
## 挑戦/作成ボタンが画像へ直接焼き込まれた旧デザイン)は完全に置き換えた。
const TITLE_IMAGE_PATH := "res://assets_bossmaker/art/title_screen_home_monitors.png"

## 完成画像自身のピクセル解像度。RBMTitleEffectsが引き続きapply_image_
## fraction_rect()を共有するため保持する(画像サイズ自体は旧背景と同一)。
const TITLE_IMAGE_SIZE := Vector2(1672.0, 941.0)

## 左下「挑戦」／右下「ボス作成」モニターの確定Rect(1280x720基準、ユーザー
## 承認済みキャリブレーションの固定値)。位置/サイズの再調整はしない——
## 通常表示/ホバー/クリック判定/BOOT演出/拡大遷移の開始位置は全てこの2つの
## Rectだけを共通の基準にする(RBMHomeMonitorPanel参照)。
const HOME_MONITOR_CHALLENGE_RECT := Rect2(52.0, 365.0, 568.0, 248.0)
const HOME_MONITOR_CREATE_RECT := Rect2(660.0, 365.0, 568.0, 248.0)

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
	# レイヤー。ホーム画面3モニター背景反映により、炎/魔力装置/ボスの目の
	# 発光点は旧・完成画像の特定ピクセル位置に実測値で紐付いたものであり、
	# 新背景にはそれらの要素自体が存在しない(位置が無意味になる)ため、
	# ノード自体は既存テスト互換のためそのまま生成しつつ非表示にする——
	# RBMTitleEffects自身のロジック・構造には一切手を加えない。
	_title_effects = RBMTitleEffects.new()
	_title_effects.name = "TitleEffects"
	_title_effects.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_effects.visible = false
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

	# ホーム画面3モニター背景反映: 旧・完成画像に焼き込まれた「挑戦」「作成」
	# ボタン絵は新背景には存在しない。ChallengeModeButton/CreateModeButton
	# 自体はノード名・text値・シグナル配線(_on_challenge_pressed/
	# _on_create_pressed)を無改修のまま維持する——既存テスト
	# (test_rbm_e2e_full_journey.gd等、GUTの_btn()ヘルパーがノード名で検索し
	# .pressed.emit()する)との互換のためだけに存在する非表示の論理ボタンで
	# あり、実際のクリック判定は担わない(非表示・入力無視)。実際にユーザーが
	# クリックする表示/ホバー/BOOT/拡大遷移は、下で生成するRBMHomeMonitorPanel
	# (承認済み独立プレビューの本実装)が担い、その`activated`シグナルが
	# これらのボタンの`.pressed`を発火させることで、既存の遷移ロジックへ
	# そのまま接続する。
	_challenge_button = Button.new()
	_challenge_button.name = "ChallengeModeButton"
	_challenge_button.text = tr("挑戦")
	_challenge_button.visible = false
	_challenge_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_challenge_button.focus_mode = Control.FOCUS_NONE
	_challenge_button.pressed.connect(_on_challenge_pressed)
	_title_screen.add_child(_challenge_button)

	_create_button = Button.new()
	_create_button.name = "CreateModeButton"
	_create_button.text = tr("作成")
	_create_button.visible = false
	_create_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_button.focus_mode = Control.FOCUS_NONE
	_create_button.pressed.connect(_on_create_pressed)
	_title_screen.add_child(_create_button)

	# 承認済み独立プレビューの本実装: 左下「挑戦」／右下「ボス作成」モニター。
	# 通常表示/ホバー/クリック判定/BOOT演出/拡大遷移の開始位置は全て
	# HOME_MONITOR_CHALLENGE_RECT/HOME_MONITOR_CREATE_RECTだけを基準にする
	# (RBMHomeMonitorPanel冒頭コメント参照)。
	_challenge_monitor = RBMHomeMonitorPanel.new()
	_challenge_monitor.name = "ChallengeHomeMonitor"
	_challenge_monitor.home_rect = HOME_MONITOR_CHALLENGE_RECT
	_challenge_monitor.label_key = "挑戦"
	_title_screen.add_child(_challenge_monitor)

	_creator_monitor = RBMHomeMonitorPanel.new()
	_creator_monitor.name = "CreatorHomeMonitor"
	_creator_monitor.home_rect = HOME_MONITOR_CREATE_RECT
	_creator_monitor.label_key = "ボス作成"
	_title_screen.add_child(_creator_monitor)

	_challenge_monitor.other_panel = _creator_monitor
	_creator_monitor.other_panel = _challenge_monitor

	# 承認済みSFX同期(right_creator_sfx_v2)の本実装: RBMHomeMonitorPanel自身
	# には一切触れず、外部からその実際の視覚状態を監視して同期させる
	# アダプタ(RBMTitleBootLauncherと同じ手法。詳細はRBMHomeMonitorSfx冒頭
	# コメント参照)。
	_challenge_monitor_sfx = RBMHomeMonitorSfx.new()
	_challenge_monitor_sfx.name = "ChallengeHomeMonitorSfx"
	_challenge_monitor_sfx.panel = _challenge_monitor
	_challenge_monitor_sfx.side = "left"
	_title_screen.add_child(_challenge_monitor_sfx)

	_creator_monitor_sfx = RBMHomeMonitorSfx.new()
	_creator_monitor_sfx.name = "CreatorHomeMonitorSfx"
	_creator_monitor_sfx.panel = _creator_monitor
	_creator_monitor_sfx.side = "right"
	_title_screen.add_child(_creator_monitor_sfx)

	_challenge_monitor.mouse_entered.connect(func(): _challenge_monitor_sfx.play_hover())
	_creator_monitor.mouse_entered.connect(func(): _creator_monitor_sfx.play_hover())

	_challenge_monitor.activated.connect(func():
		_challenge_monitor_sfx.stop_all()
		_challenge_button.pressed.emit())
	_creator_monitor.activated.connect(func():
		_creator_monitor_sfx.stop_all()
		_create_button.pressed.emit())

	# 起動導線(承認済みプレビュー反映版): タイトル→START→時計SYSTEM CORE
	# 加速演出→SYSTEM BOOT/ONLINE→既存の挑戦/作成選択、という流れを、
	# 画面全体を覆う独立レイヤーとして追加する(詳細はRBMTitleBootLauncher
	# 冒頭コメント参照)。ChallengeModeButton/CreateModeButton自身やその
	# シグナル配線には一切触れない——この演出が完了すると自身を隠すだけで、
	# 既存のボタンがそのまま露出する。
	_title_boot_launcher = RBMTitleBootLauncher.new()
	_title_boot_launcher.name = "TitleBootLauncher"
	_title_boot_launcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_screen.add_child(_title_boot_launcher)

	# 言語切替ボタン——ホーム画面右上、モニター群(上中央/左下/右下)とは重ならない
	# 領域(いずれも画面下寄りにあるため右上は空いている)。RBMUiThemeの
	# SecondaryButton（LOG/戻る等、補助操作と同じ控えめな見た目）をそのまま
	# 使い、新しいデザイン言語は持ち込まない。表示文字列自体
	# （「日本語」「English」）は各言語の自称であり、どちらのUI言語でも
	# 変わらない——tr()は使わない。
	_locale_button = Button.new()
	_locale_button.name = "LocaleToggleButton"
	_locale_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_locale_button.focus_mode = Control.FOCUS_ALL
	_locale_button.custom_minimum_size = Vector2(112.0, 40.0)
	_locale_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_locale_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_locale_button.offset_left = -112.0 - 16.0
	_locale_button.offset_right = -16.0
	_locale_button.offset_top = 16.0
	_locale_button.offset_bottom = 16.0 + 40.0
	_locale_button.pressed.connect(_on_locale_button_pressed)
	_title_screen.add_child(_locale_button)
	RBMLocale.locale_changed.connect(_on_locale_changed)
	_update_locale_button_text()

	_build_creator_entry()
	_build_challenge_entry()

	_show_menu()

## ローカライズ監査（2026-09-11）で発見: RBMCreatorEntry/RBMCreatorMainは
## ここで一度だけ生成され、以後はvisibleの切替だけで使い回される（§4/§5の
## 既存設計どおり）——STEP1〜5・保存/公開/確認ダイアログ等のボタン文言は
## いずれも「生成時点でのtr()呼び出し結果」がそのまま.textへ書き込まれる
## ため、Godot自身のauto_translate（NOTIFICATION_TRANSLATION_CHANGED）は
## 「生成時点のロケールがja（tr()のソース言語）だった場合」に限り以後も
## 正しく再翻訳される。生成時点のロケールが既にen（前回セッションで
## Englishのまま終了し、次回起動時にその設定を読み込んだ場合）だと、
## .textにはtr()適用後の英語文字列そのものが書き込まれ、それはCSVの
## キー（日本語文字列）と一致しないため、以後どれだけlocale_changedが
## 発生してもCreator/Challenge側の表示は英語のまま更新されない（実GPU
## 検証で確認済みの実際の不具合——チェックリスト#3/#9に該当）。
## 個々のtr()呼び出し箇所すべてを再実行可能にする改修はCreator/Challenge
## 内部の広範囲な変更になるため今回は行わず、既存の「1つだけ生成して使い
## 回す」設計をそのまま活かした形で対処する: ロケール切替ボタン
## （_locale_button）は_title_screenの子であり、CreatorEntry/
## ChallengeEntryが表示されている間は決して押せない（_show_only()により
## 排他表示、かつCreator側は未保存変更があれば既存のpress_exit_creator()
## 確認フローを経てからしかタイトルへ戻れない）——つまりlocale_changedが
## 発生し得るのは常に「CreatorEntry/ChallengeEntryがどちらも非表示かつ
## 内部に保持すべき進行中の状態が無い」瞬間だけ、という既存のナビゲーション
## 制約を利用し、その瞬間にだけ両Entryを安全に作り直す（＝生成時のtr()を
## 新しいロケールで再実行させる）。Creator/Challenge自身の仕様・ロジックは
## 無改修——生成コードそのものを1回多く実行させるだけ。
func _on_locale_changed(_locale: String) -> void:
	_update_locale_button_text()
	_challenge_monitor.refresh_locale()
	_creator_monitor.refresh_locale()
	_rebuild_creator_and_challenge_entries_for_current_locale()

func _rebuild_creator_and_challenge_entries_for_current_locale() -> void:
	if is_instance_valid(creator_entry):
		creator_entry.queue_free()
	if is_instance_valid(challenge_entry):
		challenge_entry.queue_free()
	_build_creator_entry()
	_build_challenge_entry()
	creator_entry.visible = false
	challenge_entry.visible = false

func _build_creator_entry() -> void:
	creator_entry = RBMCreatorEntry.new()
	creator_entry.name = "CreatorEntry"
	creator_entry.set_anchors_preset(Control.PRESET_FULL_RECT)
	creator_entry.visible = false
	creator_entry.exit_requested.connect(_on_creator_exit_requested)
	add_child(creator_entry)

func _build_challenge_entry() -> void:
	challenge_entry = RBMChallengeEntry.new()
	challenge_entry.name = "ChallengeEntry"
	challenge_entry.set_anchors_preset(Control.PRESET_FULL_RECT)
	challenge_entry.visible = false
	challenge_entry.exit_requested.connect(_on_challenge_exit_requested)
	add_child(challenge_entry)

func _on_create_pressed() -> void:
	creator_entry.enter_create()
	_show_only(creator_entry)

func _on_challenge_pressed() -> void:
	challenge_entry.enter_challenge()
	_show_only(challenge_entry)

## 押すたびに日本語⇔Englishを切り替える。切替そのものはRBMLocale側の
## 責務（TranslationServer.set_locale()＋user://への永続化）——ここでは
## 呼び出しとボタン自身のラベル更新のみ行う。バトルロジック・セーブ・
## Clear Check・battle_hashには一切触れない（表示設定のみ）。
func _on_locale_button_pressed() -> void:
	RBMLocale.toggle_locale()

func _update_locale_button_text() -> void:
	_locale_button.text = "English" if RBMLocale.current_locale() == "ja" else "日本語"

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
	# Challenge/Creatorから戻った時(またはBOOT演出の途中で二重に呼ばれた
	# 場合でも)、モニターがBOOT/拡大の途中状態のまま残らないよう、必ず
	# 通常表示(home_rect・演出無し)へ戻す。
	_challenge_monitor.reset_to_idle()
	_creator_monitor.reset_to_idle()
	_challenge_monitor_sfx.stop_all()
	_creator_monitor_sfx.stop_all()

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
