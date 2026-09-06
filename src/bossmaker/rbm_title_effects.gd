class_name RBMTitleEffects
extends Control

## タイトル画面 ループ演出追加。
##
## 完成静止画（TitleBackground、res://assets_bossmaker/art/
## title_screen_makers_and_challengers.png）には一切触れない——このControl
## 自身がその上に重なる「別レイヤー」として、炎の揺らぎ／魔力装置の明滅／
## ボスの目の発光、の3種類だけを描く。RBMGameRoot._build_ui()から一度だけ
## インスタンス化され、以後はタイトル画面へ出入りするたび親(_title_screen)
## の.visibleが切り替わるだけ——このNode自身が再構築されることは無い。
##
## 実装方式: 発光点ごとに個別のTween/AnimationPlayerを持たせるのではなく、
## 単一の_process(delta)でelapsed時間を積算し、各発光点のalpha（明るさ）を
## sin波（発光点ごとに独立した周期・位相）から直接計算するだけ——「タイトル
## へ戻ってきたら演出が停止/多重起動/発光強度が累積する」という懸念を、
## そもそも起動・停止という離散状態を一切持たない設計（sin(time)は常に
## 同じ入力に対し同じ出力を返す純粋な関数）にすることで構造的に排除する。
## Tween.tween_property()の多重起動・ループ回数管理・pause/resumeの整合性
## といった状態管理そのものが存在しない。
##
## パフォーマンス: 発光点は合計9個（炎4＋魔力装置3＋目2）、いずれも_ready()
## で一度だけ生成する固定のTextureRect——_process内でNode生成/破棄は一切
## 行わない。_process自身もis_visible_in_tree()がfalseの間（Creator/
## Challenge画面にいる間）は即returnし、無駄な計算を避ける。
##
## 発光の見た目: 単一の共有ソフト減衰円テクスチャ（_ready()で一度だけ
## Image/ImageTextureとして生成、RGBは白・alphaだけが中心1.0→外周0.0へ
## 二乗減衰する）を全発光点で使い回し、CanvasItemMaterial(BLEND_MODE_ADD)
## で加算合成する——下の完成画像を隠す/塗り潰すのではなく、既存の光源
## ピクセルを実際に明るくする方向の合成にすることで「静止画の炎/結晶/目が
## 少し強く光る」という自然な見た目になる（単純な半透明色パッチを乗せる
## alpha合成より、光源の演出として適切なためADDを選んだ）。色そのものは
## 各TextureRect.modulateのRGBで指定し、alpha（明るさ）だけを_process側で
## 時間変化させる。
##
## 座標: 完成画像(1672x941)のピクセル座標で実測した値（tools/配下の
## グリッド線付きクロップを目視して測定する使い捨てスクリプト、確認後に
## 削除済み）。RBMGameRoot.apply_image_fraction_rect()と全く同じ比率変換を
## 再利用し、実行時のControlサイズに関わらず正しい位置へ重なるようにする
## （このNode自身がRBMGameRootの_title_screenと同じFULL_RECT系列の子孫で
## あることが前提）。

# =============================================================================
# 発光点の定義（画像ピクセル座標での外接矩形、実測値）
# =============================================================================

## §3: 実際に炎が描かれている位置だけ——壁の松明2箇所＋祭壇前の松明2箇所。
## 小さな蝋燭類（卓上の灯り等）は「控えめ」の方針を優先し対象外とした
## （実装後報告で開示）。
const FIRE_POINTS: Array[Dictionary] = [
	{"name": "TorchGlow_WallLeft", "rect": Rect2(5.0, 395.0, 60.0, 60.0), "period": 1.35, "phase": 0.00},
	{"name": "TorchGlow_WallRight", "rect": Rect2(1570.0, 405.0, 60.0, 60.0), "period": 1.55, "phase": 0.55},
	{"name": "TorchGlow_AltarLeft", "rect": Rect2(664.0, 496.0, 48.0, 48.0), "period": 1.45, "phase": 0.90},
	{"name": "TorchGlow_AltarRight", "rect": Rect2(954.0, 498.0, 48.0, 48.0), "period": 1.60, "phase": 0.20},
]
const FIRE_COLOR := Color(1.0, 0.56, 0.16)
const FIRE_BASE_ALPHA := 0.20
const FIRE_AMPLITUDE := 0.16
## §3: 「わずかに揺らぎがある方が望ましいが乱数で毎フレーム激しく変化させ
## ない」——主波(period/phase)に、決定論的な高周波の副波を少量重ねるだけで
## "自然な不規則感"を表現する（毎フレーム乱数を引く処理は使わない）。
const FIRE_WOBBLE_PERIOD := 0.33
const FIRE_WOBBLE_AMOUNT := 0.05

## §5: 青(結晶)/赤(結晶)/緑(ランタン)の3個。§6: 全て周期・位相をずらす。
const DEVICE_POINTS: Array[Dictionary] = [
	{"name": "DeviceGlow_Red", "rect": Rect2(100.0, 475.0, 110.0, 110.0), "color": Color(1.0, 0.32, 0.14), "period": 2.6, "phase": 0.0},
	{"name": "DeviceGlow_Blue", "rect": Rect2(240.0, 415.0, 110.0, 110.0), "color": Color(0.28, 0.55, 1.0), "period": 3.2, "phase": 1.05},
	{"name": "DeviceGlow_Green", "rect": Rect2(400.0, 420.0, 80.0, 80.0), "color": Color(0.35, 1.0, 0.4), "period": 2.9, "phase": 2.0},
]
const DEVICE_BASE_ALPHA := 0.18
const DEVICE_AMPLITUDE := 0.16

## §7: ボスの目2点。左右は同時に発光する（別個体の目が別々のタイミングで
## 光ると不自然なため、位相は共有する——§6の「装置は位相をずらす」とは
## 異なる対象であり、意図的に同期させている）。
const EYE_POINTS: Array[Dictionary] = [
	{"name": "EyeGlow_Left", "rect": Rect2(816.0, 438.0, 18.0, 18.0)},
	{"name": "EyeGlow_Right", "rect": Rect2(849.0, 439.0, 18.0, 18.0)},
]
const EYE_COLOR := Color(1.0, 0.42, 0.10)
## §7: 「5〜10秒に1回」の中央値。パルス自体の長さは「一瞬光って戻る」が
## 自然に見える長さとして0.75秒（判断値、報告に開示）。
const EYE_PERIOD := 7.5
const EYE_PULSE_DURATION := 0.75
const EYE_PULSE_AMPLITUDE := 0.55

const GLOW_TEXTURE_SIZE := 96

# =============================================================================
# Phase 2「局所ピクセルアニメーション」— 炎の形状アニメーション
# =============================================================================
##
## FIRE_POINTS（周囲への光、上記・無改修）とは別に、実際に炎の"形"が動いて
## 見えるスプライトアニメーションをここに追加する。
##
## 実装方式（v2、壁まで動く不具合の修正版）: Claude Code側で新しいAI画像は
## 一切生成していない。完成背景画像そのもの（title_screen_makers_and_
## challengers.png、無改修）から4箇所の炎だけをシード付き領域成長法
## （4連結flood fill、明るさ+暖色度のOR条件——白熱コアは明るいが暖色度は
## 中程度、オレンジ本体は暖色度が高いが明るさは中程度なので、片方だけの
## 単純な閾値では両方を同時に拾えない。境界1px分を追加で収縮し、迷う境界
## ピクセルを除外）で透過背景へ抽出し、その抽出結果（マスク）だけを行単位で
## 水平方向へ小さくシフトさせて4コマの透過PNGを焼き込んだ（tools/配下の
## 使い捨てC#ベイクスクリプト、確認後に削除済み）。マスク外のピクセルは
## 4コマ全てでalpha=0——石壁・松明・ブラケット・台座・環境光は一切ピクセル
## データに含まれないため、シフト処理そのものが触れる対象になり得ない
## （旧v1の「炎を含む矩形全体をシフトする」方式が壁まで動かしていた根本
## 原因を、透過抽出という設計そのもので構造的に排除した）。シフト量は
## マスク自身の最下行（根本）でほぼ0・最上行（先端）に近いほど大きくなる
## 形で各行ごとに計算し、4フレームは同じ最大振幅のsin波を4等分点
## (0,+max,0,-max)でサンプリングして生成——先端が中央→右→中央→左と循環
## する自然な揺れになる。壁までは動かないため矩形全体をシフトしていた
## v1と異なり、垂直方向の伸縮（Frame C相当）を再度試す余地もあったが、
## 「小さな変化で十分」という指示に沿い水平シフトのみを継続採用した。
##
## rectは各炎の抽出に使ったROIそのものと完全一致させている（ROIがそのまま
## 画面上の表示位置になるため、抽出元と表示先がズレると透過オーバーレイが
## 本物の炎の真上に正確に重ならなくなる）。v1のrectより一回り広い——
## 透過部分は描画されないので、余白が増えても無害（背景を隠さない）。
const FIRE_SHAPE_POINTS: Array[Dictionary] = [
	{"name": "FireShape_WallLeft", "prefix": "fire_wall_left", "rect": Rect2(0.0, 375.0, 75.0, 95.0), "frame_duration": 0.16, "start_offset": 0.00},
	{"name": "FireShape_WallRight", "prefix": "fire_wall_right", "rect": Rect2(1560.0, 365.0, 100.0, 100.0), "frame_duration": 0.19, "start_offset": 0.35},
	{"name": "FireShape_AltarLeft", "prefix": "fire_altar_left", "rect": Rect2(630.0, 460.0, 100.0, 90.0), "frame_duration": 0.21, "start_offset": 0.55},
	{"name": "FireShape_AltarRight", "prefix": "fire_altar_right", "rect": Rect2(920.0, 460.0, 100.0, 90.0), "frame_duration": 0.24, "start_offset": 0.10},
]
const FIRE_SHAPE_FRAME_COUNT := 4
const FIRE_SHAPE_DIR := "res://assets_bossmaker/art/title_effects/"

# =============================================================================
# Phase 2「局所ピクセルアニメーション」— 火の粉
# =============================================================================
##
## §7: 特に大きく見える炎（実測クロップで最も背の高かった壁松明2箇所）から
## だけ、時々1〜2個の火の粉を出す——4箇所全部からではない（「少量」の方針）。
## tipは炎の先端付近の画像ピクセル座標（目視測定）。
const SPARK_EMITTER_POINTS: Array[Dictionary] = [
	{"tip": Vector2(30.0, 398.0), "min_interval": 2.2, "max_interval": 4.0},
	{"tip": Vector2(1615.0, 383.0), "min_interval": 2.4, "max_interval": 4.2},
]
## §16: Node生成/破棄を毎フレーム行わないため、固定サイズのプールを
## _ready()で一度だけ作り、以後は再利用する（spawn=空きスロットの状態を
## 書き換えるだけ）。
const SPARK_POOL_SIZE := 4
const SPARK_LIFETIME_MIN := 0.9
const SPARK_LIFETIME_MAX := 1.3
const SPARK_RISE_PX := 22.0
const SPARK_DRIFT_MAX_PX := 4.0
const SPARK_SIZE_PX := 3.0
const SPARK_FADE_IN_FRAC := 0.15
const SPARK_FADE_OUT_FRAC := 0.30
const SPARK_COLOR := Color(1.0, 0.8, 0.38)
const SPARK_PEAK_ALPHA := 0.85

# =============================================================================
# Phase 2「局所ピクセルアニメーション」— 魔力装置内部の光点移動
# =============================================================================
##
## §9/§10: 既存のDeviceGlow_*（周囲への明滅、上記・無改修）は残したまま、
## 装置内部を下→上へ移動して消える小さな光点だけを追加する。容器・台座
## （完成画像自身の一部、無改修）は一切動かさない——動くのはこの光点のみ。
const DEVICE_MOTE_POINTS: Array[Dictionary] = [
	{"name": "DeviceMote_Red", "color": Color(1.0, 0.5, 0.22), "x": 155.0, "y_bottom": 565.0, "y_top": 500.0, "period": 2.4, "phase": 0.0},
	{"name": "DeviceMote_Blue", "color": Color(0.42, 0.68, 1.0), "x": 295.0, "y_bottom": 520.0, "y_top": 430.0, "period": 3.2, "phase": 1.1},
	{"name": "DeviceMote_Green", "color": Color(0.48, 1.0, 0.55), "x": 440.0, "y_bottom": 495.0, "y_top": 440.0, "period": 2.8, "phase": 2.0},
]
const DEVICE_MOTE_SIZE_PX := 16.0
const DEVICE_MOTE_PEAK_ALPHA := 0.55
const DEVICE_MOTE_FADE_IN_FRAC := 0.15
const DEVICE_MOTE_FADE_OUT_FRAC := 0.20

var _elapsed: float = 0.0
var _shared_glow_texture: ImageTexture
var _shared_additive_material: CanvasItemMaterial
var _shared_spark_texture: ImageTexture

## _process()が毎フレーム読む、発光点ごとのメタデータ。Dictionaryの配列
## そのまま持つ（このプロジェクト全体で既に確立されているDictionary多用の
## 慣習に合わせる、専用クラスを新設するほどの複雑さではないため）。
var _fire_nodes: Array[Dictionary] = []
var _device_nodes: Array[Dictionary] = []
var _eye_nodes: Array[Dictionary] = []
var _fire_shape_nodes: Array[Dictionary] = []
var _spark_pool: Array[Dictionary] = []
var _spark_emitters: Array[Dictionary] = []
var _device_mote_nodes: Array[Dictionary] = []

var _fire_layer: Control
var _device_layer: Control
var _eye_layer: Control
var _fire_shape_layer: Control
var _spark_layer: Control
var _device_mote_layer: Control

func _ready() -> void:
	_shared_glow_texture = _make_radial_glow_texture(GLOW_TEXTURE_SIZE)
	_shared_additive_material = CanvasItemMaterial.new()
	_shared_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_shared_spark_texture = _make_spark_texture()

	# 描画順（§2）: 背景 → 局所ピクセルアニメーション(FireShapeEffects/
	# SparkEffects/DeviceMoteEffects) → 既存の控えめな発光(FireEffects/
	# MagicGlowEffects/BossEyeGlow) → UI。ただし炎については、輪郭のはっきり
	# したスプライトの下に柔らかい後光が回り込んで見える方が自然なため、
	# FireEffects（後光）を先に描き、その上へFireShapeEffects（実際に動く
	# 炎の形）を重ねる——「実際のCanvas描画順は最も自然に見えるよう調整して
	# 構わない」という許可の範囲内の判断（報告で開示）。魔力の光点も同様に
	# 装置の後光の上に重ねる。
	_fire_layer = _make_full_rect_layer("FireEffects")
	_fire_shape_layer = _make_full_rect_layer("FireShapeEffects")
	_spark_layer = _make_full_rect_layer("SparkEffects")
	_device_layer = _make_full_rect_layer("MagicGlowEffects")
	_device_mote_layer = _make_full_rect_layer("DeviceMoteEffects")
	_eye_layer = _make_full_rect_layer("BossEyeGlow")

	for def in FIRE_POINTS:
		var node := _build_glow_node(_fire_layer, def["name"], def["rect"], FIRE_COLOR)
		_fire_nodes.append({"node": node, "period": def["period"], "phase": def["phase"]})

	for def in DEVICE_POINTS:
		var node := _build_glow_node(_device_layer, def["name"], def["rect"], def["color"])
		_device_nodes.append({"node": node, "period": def["period"], "phase": def["phase"]})

	for def in EYE_POINTS:
		var node := _build_glow_node(_eye_layer, def["name"], def["rect"], EYE_COLOR)
		_eye_nodes.append({"node": node})

	for def in FIRE_SHAPE_POINTS:
		_fire_shape_nodes.append(_build_fire_shape_node(_fire_shape_layer, def))

	for point in SPARK_EMITTER_POINTS:
		_spark_emitters.append({
			"tip": point["tip"],
			"min_interval": point["min_interval"],
			"max_interval": point["max_interval"],
			"next_spawn": randf_range(0.5, 2.0),
		})
	for i in range(SPARK_POOL_SIZE):
		_spark_pool.append(_build_spark_slot(_spark_layer, i))

	for def in DEVICE_MOTE_POINTS:
		_device_mote_nodes.append(_build_device_mote_node(_device_mote_layer, def))

	set_process(true)

func _process(delta: float) -> void:
	# §11: _title_screenが非表示（Creator/Challenge画面にいる間）は計算
	# 自体をスキップする——is_visible_in_tree()はこのNode自身が親の非表示を
	# 継承した結果を見るだけで、RBMGameRoot側の参照を新たに持つ必要がない。
	if not is_visible_in_tree():
		return
	_elapsed += delta

	for entry in _fire_nodes:
		var node: TextureRect = entry["node"]
		var period: float = entry["period"]
		var phase: float = entry["phase"]
		var primary := sin(TAU * (_elapsed / period) + phase)
		var wobble := sin(TAU * (_elapsed / FIRE_WOBBLE_PERIOD) + phase * 3.7)
		var alpha := FIRE_BASE_ALPHA + FIRE_AMPLITUDE * 0.5 * primary + FIRE_WOBBLE_AMOUNT * 0.5 * wobble
		node.modulate.a = clampf(alpha, 0.0, 1.0)

	for entry in _device_nodes:
		var node: TextureRect = entry["node"]
		var period: float = entry["period"]
		var phase: float = entry["phase"]
		var wave := sin(TAU * (_elapsed / period) + phase)
		var alpha := DEVICE_BASE_ALPHA + DEVICE_AMPLITUDE * 0.5 * wave
		node.modulate.a = clampf(alpha, 0.0, 1.0)

	var eye_alpha := _eye_pulse_alpha(_elapsed)
	for entry in _eye_nodes:
		var node: TextureRect = entry["node"]
		node.modulate.a = eye_alpha

	_process_fire_shapes()
	_process_sparks()
	_process_device_motes()

## Phase 2: 各炎の現在のコマを、その炎専用のframe_duration/start_offsetから
## 決める——4箇所とも速度・開始位相が異なるため完全同期しない（§6相当の
## 考え方を炎にも適用）。
func _process_fire_shapes() -> void:
	for entry in _fire_shape_nodes:
		var node: TextureRect = entry["node"]
		var textures: Array = entry["textures"]
		var frame_duration: float = entry["frame_duration"]
		var start_offset: float = entry["start_offset"]
		var idx := int(floor((_elapsed + start_offset) / frame_duration)) % FIRE_SHAPE_FRAME_COUNT
		var tex: Texture2D = textures[idx]
		if node.texture != tex:
			node.texture = tex

## Phase 2 §7: 各発生源の次のスポーンタイミングをelapsedベースで管理し、
## 到達したらプールの空きスロットへ1個だけ火の粉を割り当てる。アクティブな
## 火の粉は上昇＋横ドリフト＋フェイドイン/アウトを時間の関数として計算する
## だけ——毎フレームのNode生成/破棄は無い。
func _process_sparks() -> void:
	for emitter in _spark_emitters:
		if _elapsed >= float(emitter["next_spawn"]):
			_spawn_spark(emitter["tip"])
			emitter["next_spawn"] = _elapsed + randf_range(float(emitter["min_interval"]), float(emitter["max_interval"]))

	for slot in _spark_pool:
		if not bool(slot["active"]):
			continue
		var t := (_elapsed - float(slot["spawn_time"])) / float(slot["lifetime"])
		if t >= 1.0:
			slot["active"] = false
			(slot["node"] as TextureRect).visible = false
			continue
		var start_pos: Vector2 = slot["start_pos"]
		var drift_dx: float = slot["drift_dx"]
		var pos := start_pos + Vector2(drift_dx * t, -SPARK_RISE_PX * t)
		var alpha := 1.0
		if t < SPARK_FADE_IN_FRAC:
			alpha = t / SPARK_FADE_IN_FRAC
		elif t > 1.0 - SPARK_FADE_OUT_FRAC:
			alpha = (1.0 - t) / SPARK_FADE_OUT_FRAC
		var node: TextureRect = slot["node"]
		node.modulate.a = clampf(alpha, 0.0, 1.0) * SPARK_PEAK_ALPHA
		var half := SPARK_SIZE_PX * 0.5
		RBMGameRoot.apply_image_fraction_rect(node, Rect2(pos.x - half, pos.y - half, SPARK_SIZE_PX, SPARK_SIZE_PX))

func _spawn_spark(tip: Vector2) -> void:
	for slot in _spark_pool:
		if bool(slot["active"]):
			continue
		slot["active"] = true
		slot["spawn_time"] = _elapsed
		slot["start_pos"] = tip
		slot["drift_dx"] = randf_range(-SPARK_DRIFT_MAX_PX, SPARK_DRIFT_MAX_PX)
		slot["lifetime"] = randf_range(SPARK_LIFETIME_MIN, SPARK_LIFETIME_MAX)
		(slot["node"] as TextureRect).visible = true
		return
	# プールが全て使用中——今回のスポーンは見送る（新規Nodeは作らない、
	# SPARK_POOL_SIZEに対しSPARK_EMITTER_POINTS数・発生間隔から通常は
	# 起こらない想定だが、起きても静かにスキップするだけで安全）。

## Phase 2 §10/§11: 装置内部の光点は下(y_bottom)→上(y_top)へ一方向に移動し、
## 端でフェイドしてから瞬時にリセットする（往復ではなく一方向の周期運動）。
## 赤/青/緑は個別のperiod/phaseを持つため同期しない。
func _process_device_motes() -> void:
	for entry in _device_mote_nodes:
		var node: TextureRect = entry["node"]
		var x: float = entry["x"]
		var y_bottom: float = entry["y_bottom"]
		var y_top: float = entry["y_top"]
		var period: float = entry["period"]
		var phase: float = entry["phase"]
		var t := fmod(_elapsed + phase, period) / period
		var y := lerpf(y_bottom, y_top, t)
		var alpha := 1.0
		if t < DEVICE_MOTE_FADE_IN_FRAC:
			alpha = t / DEVICE_MOTE_FADE_IN_FRAC
		elif t > 1.0 - DEVICE_MOTE_FADE_OUT_FRAC:
			alpha = (1.0 - t) / DEVICE_MOTE_FADE_OUT_FRAC
		node.modulate.a = clampf(alpha, 0.0, 1.0) * DEVICE_MOTE_PEAK_ALPHA
		var half := DEVICE_MOTE_SIZE_PX * 0.5
		RBMGameRoot.apply_image_fraction_rect(node, Rect2(x - half, y - half, DEVICE_MOTE_SIZE_PX, DEVICE_MOTE_SIZE_PX))

## §7/§8: 通常時は0（＝完成画像そのまま、加算成分ゼロ）。EYE_PERIODごとに
## EYE_PULSE_DURATION秒だけ、0→ピーク→0の滑らかな山を1回だけ描く——連続
## 明滅ではなく「時々ふっと強く光って戻る」を表現する。
func _eye_pulse_alpha(elapsed: float) -> float:
	var t_in_cycle := fmod(elapsed, EYE_PERIOD)
	if t_in_cycle >= EYE_PULSE_DURATION:
		return 0.0
	return EYE_PULSE_AMPLITUDE * sin(PI * t_in_cycle / EYE_PULSE_DURATION)

func _make_full_rect_layer(layer_name: String) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer

func _build_glow_node(parent: Control, node_name: String, pixel_rect: Rect2, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = _shared_glow_texture
	rect.material = _shared_additive_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# TextureRectは既定でexpand_mode=EXPAND_KEEP_SIZE（テクスチャの実サイズ
	# =96x96を自身の最小サイズとして報告する）——アンカーがそれより小さい
	# 矩形を要求しても、Godotのレイアウトが最小サイズ優先で肥大化させて
	# しまう（実測で発覚：右松明のsizeが常に96x96に張り付いていたのは
	# これが原因）。EXPAND_IGNORE_SIZEでこの制約を外し、_title_backgroundと
	# 同じ設定にする——アンカーが計算した矩形どおりの実サイズになる。
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.modulate = Color(color.r, color.g, color.b, 0.0)
	RBMGameRoot.apply_image_fraction_rect(rect, pixel_rect)
	parent.add_child(rect)
	return rect

## 中心=不透明、外周=透明の柔らかい円形グラデーション（RGBは白固定、alpha
## だけが二乗減衰）——一度だけ生成し、全発光点で使い回す。色はTextureRect
## 側のmodulateで指定するため、このテクスチャ自体は色を持たない。
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

## Phase 2: 4枚の焼き込み済みフレーム画像をロードし、コマ送りを担当する
## TextureRectを1個だけ_ready()時に作る（_process側は毎フレームtextureを
## 差し替えるだけで、Node自体の生成/破棄は行わない）。
func _build_fire_shape_node(parent: Control, def: Dictionary) -> Dictionary:
	var textures: Array = []
	for i in range(FIRE_SHAPE_FRAME_COUNT):
		var path := "%s%s_f%d.png" % [FIRE_SHAPE_DIR, def["prefix"], i]
		var tex: Texture2D = load(path)
		textures.append(tex)

	var rect := TextureRect.new()
	rect.name = def["name"]
	rect.texture = textures[0]
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	# 焼き込み済みフレーム自体が背景から直接クロップしたピクセル絵のため、
	# 補間で滲ませず元のドット密度のまま表示する（滑らかな拡大縮小フィルタ
	# だと「元背景に馴染む」効果がむしろ損なわれる）。
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RBMGameRoot.apply_image_fraction_rect(rect, def["rect"])
	parent.add_child(rect)

	return {
		"node": rect,
		"textures": textures,
		"frame_duration": def["frame_duration"],
		"start_offset": def["start_offset"],
	}

## Phase 2 §16: プール用の火の粉スロットを1個だけ生成する（初期状態は非表示・
## 未アクティブ）。共有の火花テクスチャ＋通常alpha合成（ソフトな加算グロー
## ではなく、輪郭のはっきりした小さな四角ピクセルにする方針、§8）。
func _build_spark_slot(parent: Control, index: int) -> Dictionary:
	var rect := TextureRect.new()
	rect.name = "Spark_%d" % index
	rect.texture = _shared_spark_texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.modulate = Color(SPARK_COLOR.r, SPARK_COLOR.g, SPARK_COLOR.b, 0.0)
	rect.visible = false
	parent.add_child(rect)
	return {
		"node": rect,
		"active": false,
		"spawn_time": 0.0,
		"start_pos": Vector2.ZERO,
		"drift_dx": 0.0,
		"lifetime": 1.0,
	}

## §8: 背景の解像度/ドット密度に合わせた、輪郭のはっきりした小さな正方形
## ピクセル1枚——滑らかな円形グローではなく硬いエッジにする（現代的な
## Particleの丸い粒とは明確に異なる見た目にする方針）。
func _make_spark_texture() -> ImageTexture:
	var size := int(SPARK_SIZE_PX)
	if size < 1:
		size = 1
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

## Phase 2 §9/§10: 装置内部を移動する光点を1個だけ生成する（既存の
## DeviceGlow_*と同じ共有グロー質感=柔らかい加算合成のテクスチャ/素材を
## 再利用——「装置内部の魔力の光」として周囲の明滅と統一感を持たせる）。
func _build_device_mote_node(parent: Control, def: Dictionary) -> Dictionary:
	var rect := TextureRect.new()
	rect.name = def["name"]
	rect.texture = _shared_glow_texture
	rect.material = _shared_additive_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var color: Color = def["color"]
	rect.modulate = Color(color.r, color.g, color.b, 0.0)
	var half := DEVICE_MOTE_SIZE_PX * 0.5
	var x: float = def["x"]
	var y_bottom: float = def["y_bottom"]
	RBMGameRoot.apply_image_fraction_rect(rect, Rect2(x - half, y_bottom - half, DEVICE_MOTE_SIZE_PX, DEVICE_MOTE_SIZE_PX))
	parent.add_child(rect)

	return {
		"node": rect,
		"x": x,
		"y_bottom": y_bottom,
		"y_top": def["y_top"],
		"period": def["period"],
		"phase": def["phase"],
	}
