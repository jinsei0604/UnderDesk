class_name RBMTitleBootPreview
extends Control

## タイトル→START→システム起動演出→(挑戦/作成へ入る直前)。
##
## §本番採用(6回目のフィードバック): 複数回のプレビュー確認を経て採用が
## 決まり、RBMTitleBootLauncher(rbm_title_boot_launcher.gd)経由で本番の
## 起動導線(RBMGameRoot._title_screen配下)へ組み込まれている。このファイル
## 自身の見た目・タイミング・状態機械はプレビュー確認時から変更していない
## ——フォントの読み込み元をres://アセットへ差し替えた点のみ本番化に伴う
## 技術的な調整。HANDOFFフェーズの点線プレースホルダー画面は依然「本番の
## 実際の挑戦/作成画面とは別」のプレビュー内表示のままだが、
## RBMTitleBootLauncherがTO_HANDOFFへ入った瞬間(プレースホルダーが実際に
## 見える前)に自身ごと非表示にするため、本番では表示されない——既存の
## 挑戦/作成選択画面(_title_screen自身)がそのまま露出する。
##
## 完全に独立: 既存タイトル完成画像(title_screen_makers_and_challengers.png、
## ドット絵ファンタジー・龍のシルエットを含む)は参照・依存しない。挑戦/
## 作成画面自身のロジック・RBMCreatorEntry/RBMChallengeEntry・戦闘・
## オンライン機能には一切触れない。
##
## 世界観: 「Makers & Challengersというゲームシステムへログインする」感覚を
## 主役にする——中で遊ぶ/作るボス戦のドット絵ファンタジーとは明確にレイヤー
## を分けるという指示どおり、既存タイトル完成画像は意図的に一切表示しない。
## 配色はCreator UI(RBMCreatorUiKit)と同じ濃紺+シアンパレットをそのまま
## 再利用し、世界観の連続性を出す。過剰なネオン/回路装飾は避ける。
##
## 3回目のフィードバックを反映: タイトルは必ず横1列(二重見え禁止)、
## SYSTEM COREをタイトル背後の大きな低輝度エンブレム(リング/目盛り/十字線/
## ゆっくり回転する走査弧)に育てM&C固有の識別モチーフにする、START左右の
## 収束ラインとCOREの同期点灯、画面端の最小限のシステム情報、SYSTEM BOOT→
## CONNECTING→SYSTEM ONLINEという状態遷移(数値%表示は使わない)。
##
## 移植しやすさ: 進行は単一の_process(delta)による状態機械(_Phase)＋経過
## 時間の関数だけで表現し(RBMTitleEffects/RBMTitleBootOverlayと同じ方針)、
## Tweenの多重起動・pause/resume整合性の管理を持ち込まない。採用が決まった
## 場合、この状態機械と各ビルド関数はほぼそのままRBMGameRoot側へ移植できる
## 想定(タイトル完成画像を表示する既存レイヤーとの重ね順だけ調整すればよい)。

signal preview_reached_handoff

## TITLE: START待ち(針は実PCローカル時刻)。TITLE_FADE_OUT: タイトル/
## サブタイトル/収束ラインを短くフェード&収束(ロードUIは同時表示しない)。
## HAND_ACCEL: 「タイトル画面の最大の見せ場」——実時刻を起点に、針がまず
## しばらく主役のまま(HAND_STEADY_DURATION)動き続け、その後だんだん加速
## (HAND_RAMP_DURATION)し、何回転もする最高速度を維持したまま
## (HAND_SUSTAIN_DURATION)外周リング/目盛り/走査弧が活性化しきる。回転は
## 一度も止めない。CORE_TRANSFORM: その勢いのまま、背後の大きな低輝度
## COREが縮小・変形して明るいロードリングになる(速度をCORE_ACTIVE_
## SPIN_SPEEDへなだらかに落ち着かせるだけで、途中で止まったり逆再生したり
## はしない)。BOOT: 状態遷移テキスト+セグメントゲージ。ONLINE_HOLD:
## 「SYSTEM ONLINE」を一瞬強調表示。FLASH: 短い確認フラッシュ。
## TO_HANDOFF: ハンドオフへクロスフェード。HANDOFF: 挑戦/作成へ入る直前の
## プレースホルダー。
enum _Phase { TITLE, TITLE_FADE_OUT, HAND_ACCEL, CORE_TRANSFORM, BOOT, ONLINE_HOLD, FLASH, TO_HANDOFF, HANDOFF }

const TITLE_FADE_OUT_DURATION := 0.25

## §HAND_ACCEL内の3段階。4回目のフィードバック(通常音→高速回転音への
## 変化が急、中間の加速区間をもっと長く)を反映し、RAMPを大幅に延長した
## (1.1秒→2.6秒)——tick/tockの間隔が少しずつ短くなる過程・中速域を
## しっかり聞かせてから、最後だけ一気に高速化する、という聴感上の流れを
## 作るための時間を確保する。STEADY: 針がまだ「時計」として主役のまま、
## 実時計よりは速いが読める速度で回り続ける段階(まだ活性化させない)。
## RAMP: そこからだんだん速度を上げていく段階(活性化も同時に0→1へ進める、
## 大部分は緩やかな中速域として過ごす)。SUSTAIN: 針の形が見えなくなる
## ほどの最高速度に達し、外周リング/目盛り/走査弧が完全に活性化しきった
## 状態を短く見せる段階。
const HAND_STEADY_DURATION := 0.7
const HAND_RAMP_DURATION := 2.6
const HAND_SUSTAIN_DURATION := 0.7
const CORE_TRANSFORM_DURATION := 0.65
const HANDOFF_FADE_DURATION := 0.30
const FLASH_DURATION := 0.20
const ONLINE_HOLD_DURATION := 0.40

## §実ロード進捗ではないため数値%は使わない。状態遷移テキストだけで
## 「起動していく」感覚を出す(最後のSYSTEM ONLINEはBOOT_STEPSに含めず、
## ONLINE_HOLDフェーズ専用の強調表示にする)。
const BOOT_STEPS: Array[String] = ["SYSTEM BOOT", "CONNECTING"]
const BOOT_STEP_DURATION := 0.5

const GAUGE_SEGMENTS := 18

## SYSTEM COREの、アイドル時(背後の大きな低輝度エンブレム)とロードリング時
## (中央・明るいコンパクトな輪)の半径。位置(アンカー)は今回どちらも同じ
## 中心点のまま——サイズと明るさ/見た目だけが変形する。
const CORE_ANCHOR_V := 0.48
const CORE_IDLE_HALF := 260.0
const CORE_ACTIVE_HALF := 80.0
const CORE_SWEEP_SPIN_SPEED := 0.9
const CORE_ACTIVE_SPIN_SPEED := 2.6

## 時計機能(強化版): 針・時計目盛りは、CORE全体の半径(CORE_IDLE_HALF)では
## なく、その一部でしかないこの小さな「文字盤」半径を基準にする——タイトル/
## サブタイトルはCORE中心よりかなり上にあるため、この文字盤サイズなら
## 「本物の時計のように長い針」にしても、どの時刻・どの加速角度でも文字へ
## 届かない(実測で確認済み、詳細はコメント参照)。CORE自身の大きな外周
## リング/十字線/走査弧は、この文字盤より一回り大きい「SYSTEM CORE」の
## 装飾として別に残す(無地、目盛りは持たない)。
const CORE_CLOCK_FACE_FRACTION := 0.32

## §HAND_ACCELの速度カーブ(rad/s)。STEADYはまだ「時計」と分かる速さ、
## PEAKは「針の形が見えなくなるほど」の最高速度(1秒あたり約5.4回転)。
## CORE_TRANSFORM中はPEAKに近い速度をできるだけ長く保ち(§CORE_TRANSFORM_
## SPEED_EASE_POWER参照)、その終盤だけ一気にCORE_ACTIVE_SPIN_SPEED
## (ロードリングの通常速度)へ落ち着かせる——「高速回転のまま消えていき、
## 消えながら起動演出へ繋がる」という今回の演出意図を反映するため、
## フェード/縮小の間ずっと速度を下げ続けるのではなく、直前まで速さを
## 維持することを優先する。0まで減速したり止まったりすることは無い
## (「回転を止めない」方針)。
const HAND_STEADY_SPEED := 4.5
const HAND_PEAK_SPEED := 34.0
const HAND_HOUR_SPIN_RATIO := 0.6
const SWEEP_ACCEL_MULTIPLIER := 4.0
## CORE_TRANSFORM中の速度減衰カーブの指数——大きいほど「終盤まで速いまま
## 一気に落ち着く」形になる(1.0なら線形、3.0で顕著なease-in)。
const CORE_TRANSFORM_SPEED_EASE_POWER := 3.0

## §「針だけが消え、枠がそのままシステム起動UIになる」: CORE_TRANSFORM
## 全体(0..1)のうち、このフラクション分だけで針(hand_alpha)を1→0まで
## 消し切る——外周リング/目盛り/十字線は(blend/highlightで見た目だけ
## 変わりつつ)フェードせず残り続けるのとは別に、針だけを一足先に消す
## ことで「針が消え、残った枠がそのままロードUIへ変化する」という後半の
## ビートをはっきり見せる。針はこの間も_spin_offset由来の角度で回転し
## 続ける(止まって見える瞬間を作らないため、最優先の修正点)。
const HAND_FADE_TRANSFORM_FRACTION := 0.55

const GLOW_PULSE_PERIOD := 2.4
const AMBIENT_SCANLINE_PERIOD := 7.0
const HOVER_LERP_SPEED := 5.0

const COLOR_BG_TOP := Color("#05070a")
const COLOR_BG_BOTTOM := Color("#0d131a")

## §4回目のフィードバック(タイトルフォント比較→採用): 4候補
## (Oxanium SemiBold/Michroma/Rajdhani SemiBold/Exo 2 SemiBold)を静止画で
## 比較した結果、タイトルには第一候補どおりOxanium SemiBoldを採用し、
## サブタイトル等の小さなUI文字にはRajdhani Mediumを採用する。
##
## §本番統合(6回目のフィードバック): 比較検討段階ではプロジェクト外の
## 絶対パスから確認用にダウンロードしたファイルを直接読み込んでいたが、
## 本番実装にあたりres://assets_bossmaker/fonts/へ正式に配置し直した
## (フォント自体・文字間隔・発光等の見た目はここでは一切変更していない、
## 読み込み元をres://アセットへ差し替えただけ)。
const TITLE_FONT_PATH := "res://assets_bossmaker/fonts/Oxanium-SemiBold.ttf"
const UI_FONT_PATH := "res://assets_bossmaker/fonts/Rajdhani-Medium.ttf"
const TITLE_LETTER_SPACING := 3

var _title_font: FontFile
var _ui_font: FontFile

var _phase: _Phase = _Phase.TITLE
var _elapsed_in_phase := 0.0
var _elapsed_global := 0.0
var _boot_total_duration := 0.0

var _fade_from: CanvasItem
var _fade_to: CanvasItem

var _title_layer: Control
var _boot_group: Control
var _boot_content_inner: Control
var _handoff_layer: Control
var _flash_overlay: ColorRect

var _title_glow: TextureRect
var _start_button: Button
var _start_glow: TextureRect
var _line_left: _ConvergeLine
var _line_right: _ConvergeLine
var _hover_amount := 0.0
var _hover_target := 0.0

var _core_symbol: _CoreSymbol
var _core_sweep_angle := 0.0
var _sweep_speed_multiplier := 1.0
var _accel_activation := 0.0

## §HAND_ACCEL〜起動演出全体で共有する「唯一の回転」——時計の針(hour/
## minute_angle)もロードUIの回転弧(spinner_angle)も、同じ_spin_offsetを
## 元に計算する(針とロードUIを別々の角度変数にしないことで、両者の間に
## speed/angleの継ぎ目が原理的に生まれない設計にしてある)。_spin_speedが
## 現在の回転速度(rad/s)で、フェーズごとに以下のように変化する:
## HAND_ACCEL(STEADY→RAMP→SUSTAIN)で0→定常→加速→最高速度、
## CORE_TRANSFORMで最高速度→CORE_ACTIVE_SPIN_SPEEDへなだらかに落ち着き、
## BOOT以降はCORE_ACTIVE_SPIN_SPEEDで一定——0になる/止まる瞬間は無い。
var _spin_offset := 0.0
var _spin_speed := 0.0
var _transform_start_spin_speed := 0.0

## §HAND_ACCEL: START時点の実時刻の針角度を起点として保持しておく
## (実時刻からいきなり無関係な角度へ飛ばず、「今表示していた時刻の針が、
## そのまま加速して回り出す」ようにするため)。_spin_hands_activeがtrueの
## 間、_update_core_angles()が毎フレーム(フェーズを問わず)これらから
## 現在の針角度を計算し続ける——HAND_ACCEL専用の関数の中だけで計算すると
## CORE_TRANSFORM中に更新が止まり、フェード中の針が「止まって見える」
## 不具合になる(実際に発生した不具合、この一元化で修正)。
var _accel_base_hour_angle := 0.0
var _accel_base_minute_angle := 0.0
var _spin_hands_active := false

## §時計機能: 中心近くの小さなデジタル時刻表示(HH:MM主体、秒は控えめに
## 小さく併記)。SYSTEM CORE本体の針/目盛りと同じくidle_alpha(1-blend)で
## フェードする——「あくまでSYSTEM COREの一部」という方針どおり、単独の
## UI要素としては独立させない。
var _digital_hm_label: Label
var _digital_ss_label: Label

var _boot_scanline: ColorRect
var _status_label: Label
var _gauge: _SegmentGauge

var _ambient_backdrop: _AmbientBackdrop

func _ready() -> void:
	# RBMGameRoot._sync_size_to_viewport()と同じ既知の対処: このNode自身に
	# Controlの親が存在しない場合(このプレビューを単独のシーンルートとして
	# 直接実行する場合)、set_anchors_preset(FULL_RECT)だけではsizeが実際の
	# ビューポートに追従しない(0のままになる)ため、position/sizeを直接
	# ビューポートへ同期する(アンカー切替による加算バグを避けるため、
	# アンカー自体は変更しない——RBMGameRoot側のコメント参照)。将来
	# RBMGameRoot._title_screen配下へ子として移植する場合は、親が既に
	# ControlのFULL_RECTになるため通常のset_anchors_preset(FULL_RECT)の
	# ままで正しく動く。
	if get_parent() is Control:
		# 実機確認で判明した不具合の修正: このNodeがまだ一度もレイアウトされて
		# いない(size=(0,0)の)状態で、既に親が付いている状況で
		# set_anchors_preset(FULL_RECT)を呼ぶと、既定のPRESET_MODE_MINSIZEが
		# 「現在の(まだ0の)サイズを維持する」ようoffsetを逆算してしまい
		# (実測: offset_right=-1280のような値になる)、結果としてこのNode
		# 自身のsizeが常に(0,0)のまま——中の全要素が画面左上に潰れて見える
		# 不具合になっていた。apply_image_fraction_rect()等、このプロジェクト
		# の他の箇所と同じく、set_anchors_presetの直後にoffsetを明示的に
		# 0へ矯正することで確実にFULL_RECTにする。
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0.0
		offset_right = 0.0
		offset_top = 0.0
		offset_bottom = 0.0
	else:
		position = Vector2.ZERO
		size = get_viewport_rect().size
		get_tree().root.size_changed.connect(_on_root_window_size_changed)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot_total_duration = BOOT_STEP_DURATION * BOOT_STEPS.size()

	_load_preview_fonts()
	_build_backdrop()

	_core_symbol = _CoreSymbol.new()
	_core_symbol.name = "SystemCore"
	_core_symbol.anchor_left = 0.5
	_core_symbol.anchor_right = 0.5
	_core_symbol.anchor_top = CORE_ANCHOR_V
	_core_symbol.anchor_bottom = CORE_ANCHOR_V
	_core_symbol.offset_left = -CORE_IDLE_HALF
	_core_symbol.offset_right = CORE_IDLE_HALF
	_core_symbol.offset_top = -CORE_IDLE_HALF
	_core_symbol.offset_bottom = CORE_IDLE_HALF
	_core_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_core_symbol)

	_build_digital_clock_labels()

	_title_layer = _build_title_layer()
	add_child(_title_layer)

	_boot_group = _build_boot_group()
	add_child(_boot_group)

	_handoff_layer = _build_handoff_layer()
	add_child(_handoff_layer)
	_handoff_layer.modulate.a = 0.0
	_handoff_layer.visible = false

	_flash_overlay = ColorRect.new()
	_flash_overlay.name = "FlashOverlay"
	_flash_overlay.color = Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.0)
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_overlay)

	set_process(true)

func _on_root_window_size_changed() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

## res://アセットとして正式配置したフォントの読み込み。
func _load_preview_fonts() -> void:
	_title_font = load(TITLE_FONT_PATH)
	_ui_font = load(UI_FONT_PATH)

# =============================================================================
# 常時表示レイヤー(背景・ビネット・極薄いアンビエント)
# =============================================================================
##
## §4回目のフィードバック(端の装飾を整理): 四隅のコーナーHUDブラケット・
## 左下/右下/右上のシステム情報テキストは全て廃止した。画面外周は
## できるだけシンプルにし、主役を中央の「MAKERS & CHALLENGERS」/
## 「SYSTEM CORE」/「START」だけに絞る。

func _build_backdrop() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, COLOR_BG_TOP)
	gradient.set_color(1, COLOR_BG_BOTTOM)
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 4
	gradient_texture.height = 720
	gradient_texture.fill = GradientTexture2D.FILL_LINEAR
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)

	var bg := TextureRect.new()
	bg.name = "Backdrop"
	bg.texture = gradient_texture
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# §4: 低輝度グリッド・少数のデータ点/短いライン・ゆっくりした走査線を
	# まとめた、常時控えめなアンビエント演出(主役より目立たせない)。
	_ambient_backdrop = _AmbientBackdrop.new()
	_ambient_backdrop.name = "AmbientBackdrop"
	_ambient_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ambient_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ambient_backdrop)

	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = _make_vignette_texture(256)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

func _make_vignette_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var max_dist := center.length()
	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center) / max_dist
			var a := clampf((dist - 0.35) / 0.65, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * 0.55))
	return ImageTexture.create_from_image(img)

func _make_radial_glow_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var max_dist := size * 0.5
	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center) / max_dist
			var a := clampf(1.0 - dist, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

# =============================================================================
# TITLEフェーズ(文字はタイトル層、SYSTEM COREは別レイヤーで永続)
# =============================================================================

func _build_title_layer() -> Control:
	var layer := Control.new()
	layer.name = "TitleLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title_glow = TextureRect.new()
	_title_glow.name = "TitleGlow"
	_title_glow.texture = _make_radial_glow_texture(420)
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_title_glow.material = glow_material
	_title_glow.modulate = Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.07)
	_title_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_title_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_glow.anchor_left = 0.5
	_title_glow.anchor_right = 0.5
	_title_glow.anchor_top = 0.28
	_title_glow.anchor_bottom = 0.28
	_title_glow.offset_left = -210.0
	_title_glow.offset_right = 210.0
	_title_glow.offset_top = -210.0
	_title_glow.offset_bottom = 210.0
	layer.add_child(_title_glow)

	# §最重要: 横1列固定。白文字主体＋細いシアンの縁＋弱い発光のみ。大きく
	# ズレた二重描画は禁止——単一Labelのfont_outline(細い縁)＋位置ズレの
	# 無い背景ADDグローだけで表現する。
	var title := Label.new()
	title.name = "TitleText"
	title.text = "MAKERS & CHALLENGERS"
	title.add_theme_font_override("font", _title_font)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_PRIMARY)
	title.add_theme_color_override("font_outline_color", RBMCreatorUiKit.COLOR_SILVER_BRIGHT)
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_constant_override("letter_spacing", TITLE_LETTER_SPACING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.28
	title.anchor_bottom = 0.28
	title.offset_left = -480.0
	title.offset_right = 480.0
	title.offset_top = -26.0
	title.offset_bottom = 26.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "B O S S   C R E A T I O N   S Y S T E M"
	subtitle.add_theme_font_override("font", _ui_font)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.5
	subtitle.anchor_right = 0.5
	subtitle.anchor_top = 0.28
	subtitle.anchor_bottom = 0.28
	subtitle.offset_left = -300.0
	subtitle.offset_right = 300.0
	subtitle.offset_top = 34.0
	subtitle.offset_bottom = 54.0
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(subtitle)

	_start_glow = TextureRect.new()
	_start_glow.name = "StartGlow"
	_start_glow.texture = _make_radial_glow_texture(220)
	var start_glow_material := CanvasItemMaterial.new()
	start_glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_start_glow.material = start_glow_material
	_start_glow.modulate = Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.14)
	_start_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_start_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_start_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_glow.anchor_left = 0.5
	_start_glow.anchor_right = 0.5
	_start_glow.anchor_top = 0.62
	_start_glow.anchor_bottom = 0.62
	_start_glow.offset_left = -130.0
	_start_glow.offset_right = 130.0
	_start_glow.offset_top = -130.0
	_start_glow.offset_bottom = 130.0
	layer.add_child(_start_glow)

	# §2: START左右の細いシアンライン(初期状態は伸びきった状態、
	# TITLE_FADE_OUT中に中央(ボタン側)へ収束させる)。
	_line_left = _ConvergeLine.new()
	_line_left.name = "ConvergeLineLeft"
	_line_left.points_left = true
	_line_left.anchor_left = 0.5
	_line_left.anchor_right = 0.5
	_line_left.anchor_top = 0.62
	_line_left.anchor_bottom = 0.62
	_line_left.offset_left = -260.0
	_line_left.offset_right = -146.0
	_line_left.offset_top = -1.0
	_line_left.offset_bottom = 1.0
	_line_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_line_left)

	_line_right = _ConvergeLine.new()
	_line_right.name = "ConvergeLineRight"
	_line_right.points_left = false
	_line_right.anchor_left = 0.5
	_line_right.anchor_right = 0.5
	_line_right.anchor_top = 0.62
	_line_right.anchor_bottom = 0.62
	_line_right.offset_left = 146.0
	_line_right.offset_right = 260.0
	_line_right.offset_top = -1.0
	_line_right.offset_bottom = 1.0
	_line_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_line_right)

	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = "START"
	_start_button.focus_mode = Control.FOCUS_ALL
	_start_button.anchor_left = 0.5
	_start_button.anchor_right = 0.5
	_start_button.anchor_top = 0.62
	_start_button.anchor_bottom = 0.62
	_start_button.offset_left = -120.0
	_start_button.offset_right = 120.0
	_start_button.offset_top = -28.0
	_start_button.offset_bottom = 28.0
	_apply_start_button_style(_start_button)
	_start_button.pressed.connect(_on_start_pressed)
	_start_button.mouse_entered.connect(_on_start_hover_changed.bind(true))
	_start_button.mouse_exited.connect(_on_start_hover_changed.bind(false))
	_start_button.focus_entered.connect(_on_start_hover_changed.bind(true))
	_start_button.focus_exited.connect(_on_start_hover_changed.bind(false))
	layer.add_child(_start_button)

	return layer

func _apply_start_button_style(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = RBMCreatorUiKit.COLOR_PANEL
	normal.border_color = RBMCreatorUiKit.COLOR_PANEL_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 20.0
	normal.content_margin_right = 20.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = RBMCreatorUiKit.COLOR_SILVER_BRIGHT

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = RBMCreatorUiKit.COLOR_BAR_BACKGROUND
	pressed.border_color = RBMCreatorUiKit.COLOR_SILVER_BRIGHT

	var focus := hover.duplicate() as StyleBoxFlat

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", RBMCreatorUiKit.COLOR_SILVER_BRIGHT)
	button.add_theme_font_override("font", _ui_font)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_constant_override("letter_spacing", 2)

## §2: 「START選択時にラインとCOREが同期して点灯」——ホバー/フォーカス中は
## 収束ライン・COREの走査弧を揃って明るくする。
func _on_start_hover_changed(hovering: bool) -> void:
	_hover_target = 1.0 if hovering else 0.0

## §2: すぐにロード層を重ねない。まずタイトル層だけを短くフェードアウト
## させ(TITLE_FADE_OUT、ラインは同時に中央へ収束させる)、それが完全に
## 終わってからCORE_TRANSFORMへ進む。
func _on_start_pressed() -> void:
	if _phase != _Phase.TITLE:
		return
	_hover_target = 0.0
	_phase = _Phase.TITLE_FADE_OUT
	_elapsed_in_phase = 0.0

# =============================================================================
# SYSTEM COREシンボル(タイトル背後の大きな低輝度エンブレム→ロードリング)
# =============================================================================

## 時計機能: 中心のやや下(サブタイトルとSTARTの間の余白)にHH:MM+小さな秒を
## 常設で置く。位置はCORE自身のsize変化(拡大/縮小)に連動させず固定オフセット
## にしてある——CORE_TRANSFORM中に文字だけ不自然に縮むのを避けるため、
## フェード(alpha)のみで消えるようにする。
func _build_digital_clock_labels() -> void:
	_digital_hm_label = Label.new()
	_digital_hm_label.name = "DigitalClockHM"
	_digital_hm_label.text = "00:00"
	_digital_hm_label.add_theme_font_override("font", _ui_font)
	_digital_hm_label.add_theme_font_size_override("font_size", 15)
	_digital_hm_label.add_theme_color_override("font_color", Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.85))
	_digital_hm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_digital_hm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_digital_hm_label.anchor_left = 0.5
	_digital_hm_label.anchor_right = 0.5
	_digital_hm_label.anchor_top = CORE_ANCHOR_V
	_digital_hm_label.anchor_bottom = CORE_ANCHOR_V
	_digital_hm_label.offset_left = -46.0
	_digital_hm_label.offset_right = 2.0
	_digital_hm_label.offset_top = 40.0
	_digital_hm_label.offset_bottom = 62.0
	_digital_hm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_digital_hm_label)

	# §「秒表示を入れる場合も主張しすぎない」: HH:MMより一回り小さく、
	# 色も薄くしてすぐ右に添える(":32"のような表記)。
	_digital_ss_label = Label.new()
	_digital_ss_label.name = "DigitalClockSeconds"
	_digital_ss_label.text = ":00"
	_digital_ss_label.add_theme_font_override("font", _ui_font)
	_digital_ss_label.add_theme_font_size_override("font_size", 11)
	_digital_ss_label.add_theme_color_override("font_color", Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.45))
	_digital_ss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_digital_ss_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_digital_ss_label.anchor_left = 0.5
	_digital_ss_label.anchor_right = 0.5
	_digital_ss_label.anchor_top = CORE_ANCHOR_V
	_digital_ss_label.anchor_bottom = CORE_ANCHOR_V
	_digital_ss_label.offset_left = 2.0
	_digital_ss_label.offset_right = 34.0
	_digital_ss_label.offset_top = 44.0
	_digital_ss_label.offset_bottom = 63.0
	_digital_ss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_digital_ss_label)

## 時計機能の実装方針: Godot組み込みのTime.get_time_dict_from_system(false)
## ——引数falseでUTCではなくOS/PCのローカル時刻を返す——を毎フレーム読む
## だけの単純な実装(専用スレッドや外部API等は使わない、OSのローカル時計を
## そのまま信頼する)。戻り値はDictionary{"year","month","day","weekday",
## "hour","minute","second"}。
func _current_local_time() -> Dictionary:
	return Time.get_time_dict_from_system(false)

func _update_clock(_delta: float) -> void:
	var t := _current_local_time()
	var hour: int = t.get("hour", 0)
	var minute: int = t.get("minute", 0)
	var second: int = t.get("second", 0)

	_digital_hm_label.text = "%02d:%02d" % [hour, minute]
	_digital_ss_label.text = ":%02d" % second
	var idle_alpha := 1.0 - _core_symbol.blend
	_digital_hm_label.modulate.a = idle_alpha
	_digital_ss_label.modulate.a = idle_alpha

	var hour_frac := float(hour % 12) + float(minute) / 60.0
	_core_symbol.hour_angle = hour_frac / 12.0 * TAU - PI * 0.5
	var minute_frac := float(minute) + float(second) / 60.0
	_core_symbol.minute_angle = minute_frac / 60.0 * TAU - PI * 0.5
	_core_symbol.second_angle = float(second) / 60.0 * TAU - PI * 0.5

func _build_boot_group() -> Control:
	var group := Control.new()
	group.name = "BootGroup"
	group.set_anchors_preset(Control.PRESET_FULL_RECT)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_boot_content_inner = _build_boot_content()
	_boot_content_inner.visible = false
	group.add_child(_boot_content_inner)

	return group

func _build_boot_content() -> Control:
	var layer := Control.new()
	layer.name = "BootContent"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_boot_scanline = ColorRect.new()
	_boot_scanline.name = "BootScanline"
	_boot_scanline.color = Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.12)
	_boot_scanline.anchor_left = 0.0
	_boot_scanline.anchor_right = 1.0
	_boot_scanline.offset_left = 0.0
	_boot_scanline.offset_right = 0.0
	_boot_scanline.offset_top = 0.0
	_boot_scanline.offset_bottom = 3.0
	_boot_scanline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_boot_scanline)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = BOOT_STEPS[0]
	_status_label.add_theme_font_override("font", _ui_font)
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_PRIMARY)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.anchor_left = 0.5
	_status_label.anchor_right = 0.5
	_status_label.anchor_top = CORE_ANCHOR_V
	_status_label.anchor_bottom = CORE_ANCHOR_V
	_status_label.offset_left = -220.0
	_status_label.offset_right = 220.0
	_status_label.offset_top = CORE_ACTIVE_HALF + 20.0
	_status_label.offset_bottom = CORE_ACTIVE_HALF + 44.0
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status_label)

	var gauge_wrap := Control.new()
	gauge_wrap.name = "GaugeWrap"
	gauge_wrap.anchor_left = 0.5
	gauge_wrap.anchor_right = 0.5
	gauge_wrap.anchor_top = CORE_ANCHOR_V
	gauge_wrap.anchor_bottom = CORE_ANCHOR_V
	gauge_wrap.offset_left = -160.0
	gauge_wrap.offset_right = 160.0
	gauge_wrap.offset_top = CORE_ACTIVE_HALF + 54.0
	gauge_wrap.offset_bottom = CORE_ACTIVE_HALF + 66.0
	gauge_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(gauge_wrap)

	_gauge = _SegmentGauge.new()
	_gauge.name = "SegmentGauge"
	_gauge.segment_count = GAUGE_SEGMENTS
	_gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge_wrap.add_child(_gauge)

	return layer

## easeInOutに近い緩急を付けるための単純なsmoothstep(線形より上品に見える)。
func _smoothstep01(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

## §「高速回転→フェードアウト→起動演出へ自然移行」: 見た目(サイズ縮小・
## blendによるクロスフェード)は素直なsmoothstepで滑らかに進める一方、
## 回転速度は別カーブ(t^CORE_TRANSFORM_SPEED_EASE_POWER、ease-in)で
## 落ち着かせる——序盤〜中盤はほぼ最高速度を保ったまま針/目盛りが縮小・
## フェードしていき(「高速回転のまま消えていく」)、終盤の一瞬だけ
## CORE_ACTIVE_SPIN_SPEEDへ落ち着く。途中でゼロになったり逆回転したりは
## しない(「回転を止めない」方針)。
func _update_core_transform(_delta: float) -> void:
	var raw_t := clampf(_elapsed_in_phase / CORE_TRANSFORM_DURATION, 0.0, 1.0)
	var t := _smoothstep01(raw_t)
	var half := lerpf(CORE_IDLE_HALF, CORE_ACTIVE_HALF, t)
	_core_symbol.offset_left = -half
	_core_symbol.offset_right = half
	_core_symbol.offset_top = -half
	_core_symbol.offset_bottom = half
	_core_symbol.blend = t
	var speed_t := pow(raw_t, CORE_TRANSFORM_SPEED_EASE_POWER)
	_spin_speed = lerpf(_transform_start_spin_speed, CORE_ACTIVE_SPIN_SPEED, speed_t)

	# 針だけを一足先に(全体のHAND_FADE_TRANSFORM_FRACTION分で)消し切る。
	# リング/目盛り/枠はこの後もblend=1まで残り続け、そのまま縮小・
	# 明転してロードUIになる。
	var hand_t := clampf(raw_t / HAND_FADE_TRANSFORM_FRACTION, 0.0, 1.0)
	_core_symbol.hand_alpha = 1.0 - _smoothstep01(hand_t)

	if _elapsed_in_phase >= CORE_TRANSFORM_DURATION:
		_core_symbol.offset_left = -CORE_ACTIVE_HALF
		_core_symbol.offset_right = CORE_ACTIVE_HALF
		_core_symbol.offset_top = -CORE_ACTIVE_HALF
		_core_symbol.offset_bottom = CORE_ACTIVE_HALF
		_core_symbol.blend = 1.0
		_core_symbol.hand_alpha = 0.0
		_spin_speed = CORE_ACTIVE_SPIN_SPEED
		_boot_content_inner.visible = true
		_phase = _Phase.BOOT
		_elapsed_in_phase = 0.0

func _update_boot(delta: float) -> void:
	var progress := clampf(_elapsed_in_phase / _boot_total_duration, 0.0, 1.0)
	var step_idx := clampi(int(_elapsed_in_phase / BOOT_STEP_DURATION), 0, BOOT_STEPS.size() - 1)
	_status_label.text = BOOT_STEPS[step_idx]
	_gauge.lit_count = int(floor(progress * GAUGE_SEGMENTS))

	if _elapsed_in_phase >= _boot_total_duration:
		_gauge.lit_count = GAUGE_SEGMENTS
		_status_label.text = "SYSTEM ONLINE"
		_status_label.add_theme_font_size_override("font_size", 19)
		_status_label.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_SILVER_BRIGHT)
		_phase = _Phase.ONLINE_HOLD
		_elapsed_in_phase = 0.0

## §5: 末尾は短く——SYSTEM ONLINEを一瞬強調表示するだけで、すぐ次へ進む。
func _update_online_hold(_delta: float) -> void:
	if _elapsed_in_phase >= ONLINE_HOLD_DURATION:
		_phase = _Phase.FLASH
		_elapsed_in_phase = 0.0

func _update_flash(_delta: float) -> void:
	var t := clampf(_elapsed_in_phase / FLASH_DURATION, 0.0, 1.0)
	var a := sin(PI * t) * 0.5
	_flash_overlay.color.a = a
	if _elapsed_in_phase >= FLASH_DURATION:
		_flash_overlay.color.a = 0.0
		_handoff_layer.visible = true
		_start_crossfade(_boot_group, _handoff_layer, _Phase.TO_HANDOFF)

# =============================================================================
# HANDOFFフェーズ(挑戦/作成画面へ入る直前のプレースホルダー)
# =============================================================================

func _build_handoff_layer() -> Control:
	var layer := Control.new()
	layer.name = "HandoffLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := _DashedFrame.new()
	frame.name = "DashedFrame"
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -320.0
	frame.offset_right = 320.0
	frame.offset_top = -90.0
	frame.offset_bottom = 90.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(frame)

	var headline := Label.new()
	headline.name = "HandoffHeadline"
	headline.text = "CONNECTION ESTABLISHED"
	headline.add_theme_font_override("font", _ui_font)
	headline.add_theme_font_size_override("font_size", 22)
	headline.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_SILVER_BRIGHT)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.anchor_left = 0.5
	headline.anchor_right = 0.5
	headline.anchor_top = 0.5
	headline.anchor_bottom = 0.5
	headline.offset_left = -300.0
	headline.offset_right = 300.0
	headline.offset_top = -60.0
	headline.offset_bottom = -30.0
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(headline)

	var body := Label.new()
	body.name = "HandoffBody"
	body.text = "→ 既存の挑戦 / 作成 選択画面へ接続します\n(本プレビュー範囲外、本番統合時にここへ接続)"
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_SECONDARY)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.anchor_left = 0.5
	body.anchor_right = 0.5
	body.anchor_top = 0.5
	body.anchor_bottom = 0.5
	body.offset_left = -280.0
	body.offset_right = 280.0
	body.offset_top = -10.0
	body.offset_bottom = 50.0
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(body)

	return layer

# =============================================================================
# 汎用クロスフェード・常時アイドル演出
# =============================================================================

func _start_crossfade(from_layer: CanvasItem, to_layer: CanvasItem, next_phase: int) -> void:
	_fade_from = from_layer
	_fade_to = to_layer
	_phase = next_phase
	_elapsed_in_phase = 0.0

func _update_fade(_delta: float) -> void:
	var t := clampf(_elapsed_in_phase / HANDOFF_FADE_DURATION, 0.0, 1.0)
	_fade_from.modulate.a = 1.0 - t
	_fade_to.modulate.a = t
	if _elapsed_in_phase >= HANDOFF_FADE_DURATION:
		_fade_from.visible = false
		_fade_to.modulate.a = 1.0
		_phase = _Phase.HANDOFF
		preview_reached_handoff.emit()

func _process(delta: float) -> void:
	_elapsed_global += delta
	_elapsed_in_phase += delta
	_update_idle_effects(delta)
	_update_core_angles(delta)
	if _phase == _Phase.TITLE or _phase == _Phase.TITLE_FADE_OUT:
		_update_clock(delta)

	match _phase:
		_Phase.TITLE_FADE_OUT:
			_update_title_fade_out()
		_Phase.HAND_ACCEL:
			_update_hand_accel(delta)
		_Phase.CORE_TRANSFORM:
			_update_core_transform(delta)
		_Phase.BOOT:
			_update_boot(delta)
		_Phase.ONLINE_HOLD:
			_update_online_hold(delta)
		_Phase.FLASH:
			_update_flash(delta)
		_Phase.TO_HANDOFF:
			_update_fade(delta)
		_:
			pass

## §2: タイトル層だけを単独でフェードアウトしつつ、左右の収束ラインを
## 中央へ縮める(ロード側は一切表示しないため、重なりが起きようがない)。
## 完了したら、その瞬間の実時刻の針角度を起点としてHAND_ACCELへ進む
## (「現実の時間」から加速が始まる、という今回の要件どおり)。
func _update_title_fade_out() -> void:
	var t := clampf(_elapsed_in_phase / TITLE_FADE_OUT_DURATION, 0.0, 1.0)
	_title_layer.modulate.a = 1.0 - t
	_line_left.length_fraction = 1.0 - t
	_line_right.length_fraction = 1.0 - t
	if _elapsed_in_phase >= TITLE_FADE_OUT_DURATION:
		_title_layer.visible = false
		_title_layer.modulate.a = 1.0
		_digital_hm_label.visible = false
		_digital_ss_label.visible = false
		_accel_base_hour_angle = _core_symbol.hour_angle
		_accel_base_minute_angle = _core_symbol.minute_angle
		_spin_offset = 0.0
		_spin_hands_active = true
		_phase = _Phase.HAND_ACCEL
		_elapsed_in_phase = 0.0

## §タイトル画面最大の見せ場: 実時刻の針角度を起点に、
## STEADY(まだ「時計」のまま、実時計より速いが読める速度で回り続ける)
## →RAMP(だんだん速度を上げていく、同時に外周リング/目盛り/走査弧も
## 0→1で活性化していく)→SUSTAIN(何回転もする最高速度を維持し、活性化
## しきった状態を見せ続ける)、の3段階で構成する。回転(_spin_speed)は
## 一度もゼロにならず、常に前進し続ける。
func _update_hand_accel(_delta: float) -> void:
	var t := _elapsed_in_phase
	var ramp_start := HAND_STEADY_DURATION
	var ramp_end := HAND_STEADY_DURATION + HAND_RAMP_DURATION
	var sustain_end := ramp_end + HAND_SUSTAIN_DURATION

	if t < ramp_start:
		_spin_speed = HAND_STEADY_SPEED
		_accel_activation = 0.0
	elif t < ramp_end:
		var eased := _smoothstep01((t - ramp_start) / HAND_RAMP_DURATION)
		_spin_speed = lerpf(HAND_STEADY_SPEED, HAND_PEAK_SPEED, eased)
		_accel_activation = eased
	else:
		_spin_speed = HAND_PEAK_SPEED
		_accel_activation = 1.0

	_sweep_speed_multiplier = lerpf(1.0, SWEEP_ACCEL_MULTIPLIER, _accel_activation)

	if t >= sustain_end:
		# CORE_TRANSFORMへ引き継ぐ開始速度を記録するだけで、角度
		# (_spin_offset)自体はそのまま連続して進み続ける——ジャンプも
		# 停止もしない。
		_transform_start_spin_speed = _spin_speed
		_phase = _Phase.CORE_TRANSFORM
		_elapsed_in_phase = 0.0

## SYSTEM COREの回転(針とロードUIの回転弧、両方とも同じ_spin_offsetから
## 計算)と走査弧の角度を毎フレーム進める(常時、フェーズを問わない)。
## 針の角度もここで(HAND_ACCEL専用関数の中だけではなく)常に更新する
## ことで、CORE_TRANSFORM中に見た目がフェードしていく間も回転そのものは
## 止まらず進み続けるようにする(「止まって見える」不具合の修正箇所)。
func _update_core_angles(delta: float) -> void:
	_spin_offset += delta * _spin_speed
	_core_sweep_angle += delta * CORE_SWEEP_SPIN_SPEED * _sweep_speed_multiplier
	_core_symbol.sweep_angle = _core_sweep_angle
	if _spin_hands_active:
		_core_symbol.minute_angle = _accel_base_minute_angle + _spin_offset
		_core_symbol.hour_angle = _accel_base_hour_angle + _spin_offset * HAND_HOUR_SPIN_RATIO
	_core_symbol.spinner_angle = _spin_offset
	_core_symbol.spin_speed = _spin_speed

	_hover_amount = move_toward(_hover_amount, _hover_target, delta * HOVER_LERP_SPEED)
	_core_symbol.highlight = maxf(_hover_amount, _accel_activation)
	if is_instance_valid(_line_left):
		_line_left.modulate.a = lerpf(0.75, 1.0, _hover_amount)
		_line_right.modulate.a = lerpf(0.75, 1.0, _hover_amount)

func _update_idle_effects(_delta: float) -> void:
	var pulse := 0.5 + 0.5 * sin(TAU * _elapsed_global / GLOW_PULSE_PERIOD)
	_title_glow.modulate.a = lerpf(0.04, 0.09, pulse)
	_start_glow.modulate.a = lerpf(0.08, 0.18, pulse)

	var scan_t := fmod(_elapsed_global, AMBIENT_SCANLINE_PERIOD) / AMBIENT_SCANLINE_PERIOD
	_ambient_backdrop.scanline_y = scan_t * size.y
	_ambient_backdrop.elapsed = _elapsed_global
	_ambient_backdrop.queue_redraw()

	if _boot_scanline != null:
		var boot_scan_t := fmod(_elapsed_global, 1.1) / 1.1
		_boot_scanline.position.y = boot_scan_t * size.y

## §2: STARTボタン左右の、中央(ボタン)側を固定端として伸縮する細いライン。
## TITLE_FADE_OUT中にlength_fractionを1→0へ動かすと、外側の端が中央へ
## 収束していくように見える。
class _ConvergeLine extends Control:
	var points_left: bool = true
	var length_fraction: float = 1.0:
		set(value):
			if length_fraction != value:
				length_fraction = value
				queue_redraw()

	func _draw() -> void:
		var color := RBMCreatorUiKit.COLOR_SILVER_BRIGHT
		var w := size.x
		var y := size.y * 0.5
		var len := w * length_fraction
		if points_left:
			draw_line(Vector2(w, y), Vector2(w - len, y), color, 2.0)
		else:
			draw_line(Vector2(0.0, y), Vector2(len, y), color, 2.0)

## §1: M&C固有のSYSTEM COREシンボル。アイドル時(blend=0)はタイトル背後の
## 大きな低輝度エンブレム——外周リング・回転する目盛り・固定の十字線・
## ゆっくり回転する走査弧・中心点で構成する、一般的なSFスピナーとは異なる
## 「ダイヤル/レーダー」風の独自図形。START後は同一Nodeのまま縮小しつつ、
## blendでアクティブ時(blend=1、単純な回転弧のロードリング)へ滑らかに
## 切り替わる。半径は全てsize基準の相対値にしてあるため、親側でsize
## (=offsetの半値×2)をアニメーションさせるだけで自然に変形して見える。
class _CoreSymbol extends Control:
	var blend: float = 0.0:
		set(value):
			if blend != value:
				blend = value
				queue_redraw()
	var highlight: float = 0.0:
		set(value):
			if highlight != value:
				highlight = value
				queue_redraw()
	var sweep_angle: float = 0.0:
		set(value):
			sweep_angle = value
			queue_redraw()
	var spinner_angle: float = 0.0:
		set(value):
			spinner_angle = value
			queue_redraw()

	## 時計機能: 実際のPCローカル時刻から算出した針の角度(ラジアン、12時
	## 方向=-PI/2を0とする実時計と同じ向き)。回転自体はフェーズを問わず
	## 毎フレーム進み続ける(RBMTitleBootPreview._update_core_angles参照)
	## ——見た目のフェード(hand_alpha)と回転そのものを別の変数にして
	## あるのは、「針が止まって見える」不具合(フェード中に角度の更新が
	## 止まっていたことが原因)を再発させないため。
	var hour_angle: float = 0.0:
		set(value):
			hour_angle = value
			queue_redraw()
	var minute_angle: float = 0.0:
		set(value):
			minute_angle = value
			queue_redraw()
	var second_angle: float = 0.0:
		set(value):
			second_angle = value
			queue_redraw()

	## §「針だけが消え、枠(リング/目盛り/十字線)は残る」: 針・秒点・中心点・
	## モーションブラー残像だけをこの値でフェードする——外周リング/目盛り/
	## 十字線/走査弧はこの値の影響を受けず、常に描画され続ける。
	var hand_alpha: float = 1.0:
		set(value):
			if hand_alpha != value:
				hand_alpha = value
				queue_redraw()

	## §「針の形が見えなくなるくらい高速回転してよい」「針が消えていく過程を
	## きれいに見せる」: 現在の回転速度(rad/s)。閾値を超えると、分針/時針の
	## 少し前の角度に薄いコピーを重ねて描く簡易モーションブラーを有効にする
	## (実際の描画はフレームごとの単発線のままだが、この残像がある方が
	## 「速すぎて形が追えない」印象が動画・静止画の両方で伝わりやすい)。
	var spin_speed: float = 0.0:
		set(value):
			spin_speed = value
			queue_redraw()

	func _draw() -> void:
		var r: float = size.x * 0.5
		if r <= 0.0:
			return
		var center: Vector2 = size * 0.5
		var cyan := RBMCreatorUiKit.COLOR_SILVER_BRIGHT
		var dim := RBMCreatorUiKit.COLOR_SILVER_DIM
		var boost := 1.0 + highlight * 0.7

		# §「時計の外枠・リング・目盛りは残る」「残った時計の枠が、そのまま
		# 起動画面のリング/UIへ変化していく」: これらはblend/hand_alphaで
		# 消えることなく常に描画する——blendに応じて明るさ/太さだけを
		# idle⇔activeのスタイルへなだらかに寄せることで、「同じ枠がそのまま
		# ロードUIになる」自然な繋がりを表現する(サイズそのものは親側で
		# Controlのsizeをアニメーションさせて縮小させる)。
		var ring_alpha := clampf(lerpf(0.16 * boost, 0.5, blend), 0.0, 1.0)
		var ring_width := lerpf(maxf(1.0, r * 0.01), maxf(1.0, r * 0.02), blend)
		draw_arc(center, r * 0.98, 0.0, TAU, 64, Color(cyan.r, cyan.g, cyan.b, ring_alpha), ring_width, true)
		draw_arc(center, r * 0.55, 0.0, TAU, 48, Color(dim.r, dim.g, dim.b, 0.16), 1.0, true)

		var cross_a := 0.07
		draw_line(center - Vector2(r * 0.72, 0.0), center + Vector2(r * 0.72, 0.0), Color(cyan.r, cyan.g, cyan.b, cross_a), 1.0)
		draw_line(center - Vector2(0.0, r * 0.72), center + Vector2(0.0, r * 0.72), Color(cyan.r, cyan.g, cyan.b, cross_a), 1.0)

		# §時計モチーフ強化: 針/目盛りは、CORE全体の半径ではなく、その中の
		# 小さな「文字盤」(clock_r)基準で描く——「本物の時計のように長い
		# 針」にしても、タイトル/サブタイトル(CORE中心よりかなり上)へは
		# 実測上どの時刻・どの加速角度でも届かない大きさに抑えてある。
		var clock_r := r * RBMTitleBootPreview.CORE_CLOCK_FACE_FRACTION

		# 60分割の目盛り(5分毎=時位置の12本だけやや長く明るい)。実時計と
		# 同じ配置にすることで、ただの飾りのダイヤルではなく本物の時計と
		# して読める。目盛りも「枠」の一部として常に描画し続け、highlight
		# (加速の活性化)に応じて明るさだけが変わる。
		var tick_count := 60
		for i in range(tick_count):
			var ang := TAU * float(i) / float(tick_count) - PI * 0.5
			var dir := Vector2(cos(ang), sin(ang))
			var is_major := i % 5 == 0
			var inner := clock_r * (0.78 if is_major else 0.90)
			var outer := clock_r * 1.0
			var a := clampf((0.34 if is_major else 0.14) * boost, 0.0, 1.0)
			draw_line(center + dir * inner, center + dir * outer, Color(cyan.r, cyan.g, cyan.b, a), 1.3 if is_major else 0.8)

		# ここから先(針・秒点・中心点・走査弧・モーションブラー)だけが
		# hand_alphaでフェードする「針」カテゴリ。回転(角度)自体は
		# hand_alphaに関係なく常に最新値を使うため、消えていく間も
		# 止まって見えることはない。
		if hand_alpha > 0.01:
			# ゆっくり回転する走査弧(装飾専用、実時刻とは無関係の「システムが
			# 生きている」演出、START後は加速して速く/明るくなる)。
			draw_arc(center, r * 0.98, sweep_angle, sweep_angle + 0.45, 16, Color(cyan.r, cyan.g, cyan.b, clampf(0.28 * hand_alpha * boost, 0.0, 1.0)), maxf(1.5, r * 0.015), true)

			# 時計の針(時→分の順、TITLE中は実PCローカル時刻、START後は
			# HAND_ACCEL/CORE_TRANSFORMで進み続ける角度)。「太すぎず細めの
			# デザイン」方針どおり、CORE全体のrではなく固定px幅にして常に
			# 細く保つ。
			var hour_dir := Vector2(cos(hour_angle), sin(hour_angle))
			var minute_dir := Vector2(cos(minute_angle), sin(minute_angle))
			draw_line(center, center + hour_dir * clock_r * 0.55, Color(cyan.r, cyan.g, cyan.b, clampf(0.8 * hand_alpha * boost, 0.0, 1.0)), 2.0)
			draw_line(center, center + minute_dir * clock_r * 0.88, Color(cyan.r, cyan.g, cyan.b, clampf(0.85 * hand_alpha * boost, 0.0, 1.0)), 1.4)

			# 簡易モーションブラー: 一定速度を超えたら、少し前の角度に薄い
			# コピーを数本重ねる——速いほど残像が濃く/長くなり、「針の形が
			# 見えなくなるくらい」の高速回転を静止画・動画の両方で伝える。
			const BLUR_START_SPEED := 8.0
			const BLUR_FULL_SPEED := 26.0
			var blur_t := clampf((spin_speed - BLUR_START_SPEED) / (BLUR_FULL_SPEED - BLUR_START_SPEED), 0.0, 1.0)
			if blur_t > 0.0:
				var trail_count := 5
				for i in range(1, trail_count + 1):
					var back_angle := 0.06 * float(i) * blur_t
					var trail_alpha := clampf(0.85 * hand_alpha * boost * blur_t * (1.0 - float(i) / float(trail_count + 1)), 0.0, 1.0)
					var minute_trail_dir := Vector2(cos(minute_angle - back_angle), sin(minute_angle - back_angle))
					var hour_back_angle := back_angle * RBMTitleBootPreview.HAND_HOUR_SPIN_RATIO
					var hour_trail_dir := Vector2(cos(hour_angle - hour_back_angle), sin(hour_angle - hour_back_angle))
					draw_line(center, center + minute_trail_dir * clock_r * 0.88, Color(cyan.r, cyan.g, cyan.b, trail_alpha), 1.4)
					draw_line(center, center + hour_trail_dir * clock_r * 0.55, Color(cyan.r, cyan.g, cyan.b, trail_alpha * 0.7), 2.0)

			# 秒は針ではなく、文字盤のすぐ外側をゆっくり周回する小さな点だけ
			# にして「主張しすぎない」——1周60秒でticksの位置と一致する。
			var second_dir := Vector2(cos(second_angle), sin(second_angle))
			draw_circle(center + second_dir * clock_r * 0.94, 1.8, Color(cyan.r, cyan.g, cyan.b, 0.5 * hand_alpha))

			draw_circle(center, clock_r * 0.06, Color(cyan.r, cyan.g, cyan.b, 0.65 * hand_alpha))

		var active_alpha := blend
		if active_alpha > 0.01:
			draw_arc(center, r - maxf(2.0, r * 0.03), spinner_angle, spinner_angle + TAU * 0.66, 40, Color(cyan.r, cyan.g, cyan.b, active_alpha), maxf(2.0, r * 0.045), true)

## セグメント式ゲージ(滑らかな塗り潰しではなく、区切られた短冊が順に点灯する
## 見た目——「システムが起動していく」ニュアンスを出すための意図的な選択、
## 実数値の%表示は使わない)。
class _SegmentGauge extends Control:
	var segment_count: int = 18
	var lit_count: int = 0:
		set(value):
			if lit_count != value:
				lit_count = value
				queue_redraw()

	func _draw() -> void:
		var gap := 3.0
		var total_gap := gap * (segment_count - 1)
		var seg_width: float = (size.x - total_gap) / float(segment_count)
		for i in range(segment_count):
			var x := i * (seg_width + gap)
			var lit := i < lit_count
			var color := RBMCreatorUiKit.COLOR_SILVER_BRIGHT if lit else RBMCreatorUiKit.COLOR_BAR_BACKGROUND
			draw_rect(Rect2(x, 0.0, seg_width, size.y), color, true)

## ハンドオフ画面の、点線矩形フレーム(draw_dashed_lineをそのまま使う)。
class _DashedFrame extends Control:
	func _draw() -> void:
		var color := Color(RBMCreatorUiKit.COLOR_SILVER_BRIGHT.r, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.g, RBMCreatorUiKit.COLOR_SILVER_BRIGHT.b, 0.5)
		var w := size.x
		var h := size.y
		draw_dashed_line(Vector2(0, 0), Vector2(w, 0), color, 1.5, 6.0)
		draw_dashed_line(Vector2(w, 0), Vector2(w, h), color, 1.5, 6.0)
		draw_dashed_line(Vector2(w, h), Vector2(0, h), color, 1.5, 6.0)
		draw_dashed_line(Vector2(0, h), Vector2(0, 0), color, 1.5, 6.0)

## §4: 背景の極薄い動き——低輝度グリッド(静止)＋少数のデータ点(個別に
## ゆっくり明滅)＋ゆっくりした走査線(親から座標だけ渡される)を1つの
## Controlにまとめて毎フレーム再描画する。全て主役(タイトル/COREシンボル/
## ロードUI)より明らかに暗いアルファに抑える。
class _AmbientBackdrop extends Control:
	var scanline_y: float = 0.0
	var elapsed: float = 0.0

	## 決定論的な擬似ランダム点(実行のたびに変わらない固定配置)——毎フレーム
	## 乱数を引く処理はしない。位置は0..1の正規化座標、phase/periodは各点を
	## 独立して明滅させるための値。
	const DATA_POINTS: Array[Dictionary] = [
		{"pos": Vector2(0.12, 0.20), "period": 3.2, "phase": 0.0},
		{"pos": Vector2(0.88, 0.16), "period": 2.7, "phase": 0.8},
		{"pos": Vector2(0.08, 0.82), "period": 3.6, "phase": 1.6},
		{"pos": Vector2(0.92, 0.86), "period": 3.0, "phase": 2.3},
		{"pos": Vector2(0.16, 0.55), "period": 4.1, "phase": 0.5},
		{"pos": Vector2(0.84, 0.60), "period": 3.8, "phase": 1.1},
	]
	const DATA_TICKS: Array[Dictionary] = [
		{"pos": Vector2(0.15, 0.30), "dir": Vector2(1, 0.4), "length": 18.0},
		{"pos": Vector2(0.85, 0.28), "dir": Vector2(-1, 0.4), "length": 16.0},
		{"pos": Vector2(0.50, 0.94), "dir": Vector2(1, 0.0), "length": 22.0},
	]

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return

		var grid_color := Color(RBMCreatorUiKit.COLOR_SILVER_DIM.r, RBMCreatorUiKit.COLOR_SILVER_DIM.g, RBMCreatorUiKit.COLOR_SILVER_DIM.b, 0.045)
		var cols := 10
		var rows := 6
		for i in range(1, cols):
			var x := w * float(i) / float(cols)
			draw_line(Vector2(x, 0.0), Vector2(x, h), grid_color, 1.0)
		for j in range(1, rows):
			var y := h * float(j) / float(rows)
			draw_line(Vector2(0.0, y), Vector2(w, y), grid_color, 1.0)

		var dot_color := RBMCreatorUiKit.COLOR_SILVER_BRIGHT
		for def in DATA_POINTS:
			var p: Vector2 = def["pos"]
			var period: float = def["period"]
			var phase: float = def["phase"]
			var pulse := 0.5 + 0.5 * sin(TAU * elapsed / period + phase)
			var a := lerpf(0.05, 0.18, pulse)
			draw_circle(Vector2(p.x * w, p.y * h), 2.0, Color(dot_color.r, dot_color.g, dot_color.b, a))

		var tick_color := Color(dot_color.r, dot_color.g, dot_color.b, 0.09)
		for def in DATA_TICKS:
			var p: Vector2 = def["pos"]
			var dir: Vector2 = (def["dir"] as Vector2).normalized()
			var length: float = def["length"]
			var origin := Vector2(p.x * w, p.y * h)
			draw_line(origin, origin + dir * length, tick_color, 1.0)

		var scan_color := Color(dot_color.r, dot_color.g, dot_color.b, 0.03)
		draw_rect(Rect2(0.0, scanline_y, w, 2.0), scan_color, true)
