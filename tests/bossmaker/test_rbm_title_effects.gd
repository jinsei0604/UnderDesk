extends GutTest

## タイトル画面 ループ演出追加 — 回帰テスト。
##
## §15: TitleEffectsの存在・入力非遮断・Challenge/Create Hotspotの正常動作・
## タイトル再表示時のNode非増殖・_process多重実行の不在・複数回の開閉での
## 無エラー・1280x720での位置整合、を直接検証する。RBMGameRootを実際に
## インスタンス化し、Godot自身のレイアウト計算を経た本物のControlのみを
## 見る——test_rbm_phase35_title_screen.gdの_make_root()と同じ方針。

const HEADLESS_WINDOW_SIZE := Vector2(1280, 720)
const EPSILON := 0.5

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(HEADLESS_WINDOW_SIZE.x, HEADLESS_WINDOW_SIZE.y)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

func _assert_within_viewport(node: Control, viewport: Rect2, description: String) -> void:
	var top_left := node.global_position
	var bottom_right := node.global_position + node.size
	assert_true(top_left.x >= viewport.position.x - EPSILON, "%s: left edge (%s) must be within the viewport" % [description, top_left.x])
	assert_true(top_left.y >= viewport.position.y - EPSILON, "%s: top edge (%s) must be within the viewport" % [description, top_left.y])
	assert_true(bottom_right.x <= viewport.position.x + viewport.size.x + EPSILON, "%s: right edge (%s) must be within the viewport" % [description, bottom_right.x])
	assert_true(bottom_right.y <= viewport.position.y + viewport.size.y + EPSILON, "%s: bottom edge (%s) must be within the viewport" % [description, bottom_right.y])

# =============================================================================
# 存在・構造
# =============================================================================

func test_title_effects_node_exists_with_expected_sublayers() -> void:
	var root := await _make_root()
	assert_not_null(root._title_effects, "RBMGameRoot must hold a TitleEffects instance")
	assert_true(root._title_effects is RBMTitleEffects)
	assert_eq(root._title_effects.name, "TitleEffects")

	var fire_layer := root._title_effects.find_child("FireEffects", false, false)
	var device_layer := root._title_effects.find_child("MagicGlowEffects", false, false)
	var eye_layer := root._title_effects.find_child("BossEyeGlow", false, false)
	assert_not_null(fire_layer, "FireEffects sub-layer must exist")
	assert_not_null(device_layer, "MagicGlowEffects sub-layer must exist")
	assert_not_null(eye_layer, "BossEyeGlow sub-layer must exist")

	assert_eq(fire_layer.get_child_count(), RBMTitleEffects.FIRE_POINTS.size(), "one glow node per defined fire point")
	assert_eq(device_layer.get_child_count(), RBMTitleEffects.DEVICE_POINTS.size(), "one glow node per defined device point")
	assert_eq(eye_layer.get_child_count(), RBMTitleEffects.EYE_POINTS.size(), "one glow node per defined eye point")

## Phase 2: 局所ピクセルアニメーション用の3レイヤー（炎の形／火の粉／
## 装置内部の光点）が既存3レイヤーを置き換えるのではなく、追加されている
## こと。
func test_phase2_sublayers_exist_alongside_the_original_three() -> void:
	var root := await _make_root()
	var fire_shape_layer := root._title_effects.find_child("FireShapeEffects", false, false)
	var spark_layer := root._title_effects.find_child("SparkEffects", false, false)
	var device_mote_layer := root._title_effects.find_child("DeviceMoteEffects", false, false)
	assert_not_null(fire_shape_layer, "FireShapeEffects sub-layer must exist")
	assert_not_null(spark_layer, "SparkEffects sub-layer must exist")
	assert_not_null(device_mote_layer, "DeviceMoteEffects sub-layer must exist")

	assert_eq(fire_shape_layer.get_child_count(), RBMTitleEffects.FIRE_SHAPE_POINTS.size(), "one animated sprite per fire-shape point")
	assert_eq(spark_layer.get_child_count(), RBMTitleEffects.SPARK_POOL_SIZE, "spark pool must be a fixed size, built once")
	assert_eq(device_mote_layer.get_child_count(), RBMTitleEffects.DEVICE_MOTE_POINTS.size(), "one internal light per magic device")

	# §2: 既存3レイヤーは今回も破棄されていないこと（再確認）。
	assert_not_null(root._title_effects.find_child("FireEffects", false, false))
	assert_not_null(root._title_effects.find_child("MagicGlowEffects", false, false))
	assert_not_null(root._title_effects.find_child("BossEyeGlow", false, false))

## §9: TitleEffectsは背景と操作ボタンの間に位置すること（描画順＝子の並び順、
## ボタンより後ろ・背景より前）。
func test_title_effects_sits_between_background_and_buttons_in_child_order() -> void:
	var root := await _make_root()
	var children := root._title_screen.get_children()
	var bg_index := children.find(root._title_background)
	var effects_index := children.find(root._title_effects)
	var challenge_index := children.find(root._challenge_button)
	assert_true(bg_index < effects_index, "background must render before (be earlier than) TitleEffects")
	assert_true(effects_index < challenge_index, "TitleEffects must render before (be earlier than) the hotspot buttons")

# =============================================================================
# §10: 入力を遮断しないこと
# =============================================================================

func test_title_effects_layer_does_not_block_input() -> void:
	var root := await _make_root()
	assert_eq(root._title_effects.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	# TitleEffects配下の全Control（3レイヤー＋9個の発光点）が例外なく
	# MOUSE_FILTER_IGNOREであること——1つでもSTOP/PASSが紛れ込むと、その
	# 矩形の範囲でHotspot Buttonの入力を奪ってしまう。
	var stack: Array[Node] = [root._title_effects]
	var checked := 0
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			stack.append(child)
		if current is Control and current != root._title_effects:
			assert_eq((current as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s must not block mouse input" % current.name)
			checked += 1
	var expected_checked := 6 \
		+ RBMTitleEffects.FIRE_POINTS.size() + RBMTitleEffects.DEVICE_POINTS.size() + RBMTitleEffects.EYE_POINTS.size() \
		+ RBMTitleEffects.FIRE_SHAPE_POINTS.size() + RBMTitleEffects.SPARK_POOL_SIZE + RBMTitleEffects.DEVICE_MOTE_POINTS.size()
	assert_eq(checked, expected_checked, "sanity: every sub-layer (6, incl. Phase 2's 3 new ones) and every glow/animation node was actually checked")

func test_challenge_hotspot_still_clickable_with_effects_layer_present() -> void:
	var root := await _make_root()
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.challenge_entry.visible, "挑戦 must still navigate correctly with TitleEffects present")
	assert_false(root._title_screen.visible)

func test_create_hotspot_still_clickable_with_effects_layer_present() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.creator_entry.visible, "作成 must still navigate correctly with TitleEffects present")
	assert_false(root._title_screen.visible)

# =============================================================================
# §12: 繰り返し開閉してもNode増殖・多重起動・エラーが起きないこと
# =============================================================================

func test_returning_to_title_does_not_duplicate_effects_nodes() -> void:
	var root := await _make_root()
	var original_effects := root._title_effects
	var fire_layer: Control = root._title_effects.find_child("FireEffects", false, false)
	var device_layer: Control = root._title_effects.find_child("MagicGlowEffects", false, false)
	var eye_layer: Control = root._title_effects.find_child("BossEyeGlow", false, false)
	var fire_shape_layer: Control = root._title_effects.find_child("FireShapeEffects", false, false)
	var spark_layer: Control = root._title_effects.find_child("SparkEffects", false, false)
	var device_mote_layer: Control = root._title_effects.find_child("DeviceMoteEffects", false, false)

	for i in range(3):
		_btn(root, "CreateModeButton").pressed.emit()
		await get_tree().process_frame
		root._on_creator_exit_requested()
		await get_tree().process_frame
		_btn(root, "ChallengeModeButton").pressed.emit()
		await get_tree().process_frame
		root._on_challenge_exit_requested()
		await get_tree().process_frame

		# 同一インスタンスのまま——再構築されていないこと。
		assert_eq(root._title_effects, original_effects, "TitleEffects must not be rebuilt on round %d" % i)
		assert_eq(fire_layer.get_child_count(), RBMTitleEffects.FIRE_POINTS.size(), "fire glow node count must not grow on round %d" % i)
		assert_eq(device_layer.get_child_count(), RBMTitleEffects.DEVICE_POINTS.size(), "device glow node count must not grow on round %d" % i)
		assert_eq(eye_layer.get_child_count(), RBMTitleEffects.EYE_POINTS.size(), "eye glow node count must not grow on round %d" % i)
		assert_eq(fire_shape_layer.get_child_count(), RBMTitleEffects.FIRE_SHAPE_POINTS.size(), "fire-shape node count must not grow on round %d" % i)
		assert_eq(spark_layer.get_child_count(), RBMTitleEffects.SPARK_POOL_SIZE, "spark pool size must not grow on round %d" % i)
		assert_eq(device_mote_layer.get_child_count(), RBMTitleEffects.DEVICE_MOTE_POINTS.size(), "device-mote node count must not grow on round %d" % i)
		assert_true(root._title_screen.visible, "title screen must be visible again after round %d" % i)

func test_repeated_open_close_does_not_error() -> void:
	var root := await _make_root()
	for i in range(4):
		_btn(root, "ChallengeModeButton").pressed.emit()
		await get_tree().process_frame
		root._on_challenge_exit_requested()
		await get_tree().process_frame
	# GUTはこのテスト本体の実行中にランタイムエラーが発生すれば失敗として
	# 報告する——ここまで到達しエラー無く完了すること自体が確認。
	assert_true(root._title_screen.visible)

## §12: _processが多重実行されていないこと——直接2回呼び出し、_elapsedが
## 単純加算（2倍ではなく、渡したdeltaぶんだけ）であることを確認する。
func test_process_updates_elapsed_exactly_once_per_call() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	effects._elapsed = 0.0
	effects._process(1.0)
	assert_almost_eq(effects._elapsed, 1.0, 0.001, "one _process(1.0) call must advance elapsed by exactly 1.0")
	effects._process(1.0)
	assert_almost_eq(effects._elapsed, 2.0, 0.001, "elapsed must accumulate additively across separate calls, not double per call")

## §11: is_visible_in_tree()がfalseの間は計算自体を行わないこと。
func test_process_is_a_no_op_when_not_visible_in_tree() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	effects._elapsed = 5.0
	effects.visible = false
	effects._process(1.0)
	assert_almost_eq(effects._elapsed, 5.0, 0.001, "elapsed must not advance while not visible in tree")

	effects.visible = true
	effects._process(1.0)
	assert_almost_eq(effects._elapsed, 6.0, 0.001, "elapsed must resume advancing once visible again")

## §16: 非表示の間、Phase 2の新しい状態（炎のコマ・火の粉のスポーン・
## 装置内部の光点の位置）も一切更新されないこと（既存のalpha無変化テストと
## 同じ精神をPhase 2の3系統に拡張）。
func test_phase2_state_does_not_change_while_hidden() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	effects.visible = false
	var fire_texture_before: Texture2D = (effects._fire_shape_nodes[0]["node"] as TextureRect).texture
	var mote_alpha_before: float = (effects._device_mote_nodes[0]["node"] as TextureRect).modulate.a
	var any_spark_active_before := false
	for slot in effects._spark_pool:
		if bool(slot["active"]):
			any_spark_active_before = true

	# 非表示のまま、火の粉が確実にスポーンしうるだけの時間(数十秒相当)を
	# 複数回の_process呼び出しで積算しようとする——is_visible_in_tree()の
	# ガードにより、いずれも即returnし何も変化しないはずである。
	for i in range(50):
		effects._process(1.0)

	assert_eq((effects._fire_shape_nodes[0]["node"] as TextureRect).texture, fire_texture_before, "fire-shape frame must not advance while hidden")
	assert_almost_eq((effects._device_mote_nodes[0]["node"] as TextureRect).modulate.a, mote_alpha_before, 0.001, "device-mote alpha must not change while hidden")
	var any_spark_active_after := false
	for slot in effects._spark_pool:
		if bool(slot["active"]):
			any_spark_active_after = true
	assert_eq(any_spark_active_after, any_spark_active_before, "no spark must spawn while hidden, even after enough simulated time")

# =============================================================================
# 発光の値域
# =============================================================================

func test_glow_alpha_values_stay_within_designed_bounds_over_a_full_cycle() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	var max_fire_alpha := RBMTitleEffects.FIRE_BASE_ALPHA + RBMTitleEffects.FIRE_AMPLITUDE * 0.5 + RBMTitleEffects.FIRE_WOBBLE_AMOUNT * 0.5
	var max_device_alpha := RBMTitleEffects.DEVICE_BASE_ALPHA + RBMTitleEffects.DEVICE_AMPLITUDE * 0.5
	var eye_pulse_seen := false
	var eye_idle_seen := false

	var t := 0.0
	while t < 12.0:
		effects._elapsed = t
		effects._process(0.0)
		for entry in effects._fire_nodes:
			var a: float = (entry["node"] as TextureRect).modulate.a
			assert_true(a >= 0.0 and a <= max_fire_alpha + 0.01, "fire alpha %s must stay within designed bounds" % a)
		for entry in effects._device_nodes:
			var a: float = (entry["node"] as TextureRect).modulate.a
			assert_true(a >= 0.0 and a <= max_device_alpha + 0.01, "device alpha %s must stay within designed bounds" % a)
		var eye_a: float = (effects._eye_nodes[0]["node"] as TextureRect).modulate.a
		assert_true(eye_a >= 0.0 and eye_a <= RBMTitleEffects.EYE_PULSE_AMPLITUDE + 0.01, "eye alpha %s must stay within designed bounds" % eye_a)
		if eye_a > 0.05:
			eye_pulse_seen = true
		if eye_a == 0.0:
			eye_idle_seen = true
		t += 0.05

	assert_true(eye_pulse_seen, "over a 12s window (> EYE_PERIOD), the eyes must actually pulse at least once")
	assert_true(eye_idle_seen, "the eyes must also spend most of the cycle fully idle (alpha 0)")

## §7: 両目は同時に光ること（別々のタイミングでは不自然）。
func test_both_eyes_pulse_in_sync() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	effects._elapsed = RBMTitleEffects.EYE_PULSE_DURATION * 0.5
	effects._process(0.0)
	var left: float = (effects._eye_nodes[0]["node"] as TextureRect).modulate.a
	var right: float = (effects._eye_nodes[1]["node"] as TextureRect).modulate.a
	assert_almost_eq(left, right, 0.001, "both eyes must share the same pulse phase")
	assert_gt(left, 0.0, "sanity: mid-pulse alpha must be non-zero")

# =============================================================================
# §16: 1280x720で位置が大きくズレないこと
# =============================================================================

func test_glow_node_positions_stay_within_viewport_at_1280x720() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()
	for layer_name in ["FireEffects", "MagicGlowEffects", "BossEyeGlow", "FireShapeEffects", "DeviceMoteEffects"]:
		var layer: Control = root._title_effects.find_child(layer_name, false, false)
		for child in layer.get_children():
			_assert_within_viewport(child, viewport, "%s/%s" % [layer_name, child.name])

# =============================================================================
# Phase 2「局所ピクセルアニメーション」
# =============================================================================

## §3/§4/§6: 焼き込み済み4コマのフレームアニメーションが実際に存在し、
## 時間経過でコマが切り替わること（＝単なるalpha変化ではなく実際の絵の
## 差し替えが起きている）。
func test_fire_shape_animation_exists_and_cycles() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	assert_eq(effects._fire_shape_nodes.size(), RBMTitleEffects.FIRE_SHAPE_POINTS.size())
	var entry: Dictionary = effects._fire_shape_nodes[0]
	var node: TextureRect = entry["node"]
	var frame_duration: float = entry["frame_duration"]
	var seen_textures := {}

	var t := 0.0
	while t < frame_duration * (RBMTitleEffects.FIRE_SHAPE_FRAME_COUNT + 1):
		effects._elapsed = t
		effects._process(0.0)
		seen_textures[node.texture] = true
		t += frame_duration * 0.5

	assert_eq(seen_textures.size(), RBMTitleEffects.FIRE_SHAPE_FRAME_COUNT, "over one full cycle, all 4 baked frames must actually be shown (not stuck on one texture)")

## §6: 4箇所の炎は完全同期しないこと（frame_duration/start_offsetが
## いずれも異なるため、少なくとも一部の時刻でコマ番号が食い違うはず）。
func test_the_four_fires_are_not_perfectly_synchronized() -> void:
	var points: Array = RBMTitleEffects.FIRE_SHAPE_POINTS
	var frame_count: int = RBMTitleEffects.FIRE_SHAPE_FRAME_COUNT
	var desync_observed := false

	var t := 0.0
	while t < 4.0:
		var indices: Array[int] = []
		for def in points:
			var frame_duration: float = def["frame_duration"]
			var start_offset: float = def["start_offset"]
			var idx := int(floor((t + start_offset) / frame_duration)) % frame_count
			indices.append(idx)
		var first: int = indices[0]
		for idx in indices:
			if idx != first:
				desync_observed = true
		t += 0.05

	assert_true(desync_observed, "over a 4s window, the 4 fires must show different frame indices at least once (not perfectly synchronized)")

## §9/§10: 装置内部の光点が実際に動く（下→上へ座標が変化し、alphaも
## フェードイン/アウトする）こと——コンテナ・台座自体（TextureRectの絵の
## 内容）は今回一切触れておらず、動くのはこの光点ノードの位置/alphaのみ。
func test_device_internal_motion_animation_exists() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	var entry: Dictionary = effects._device_mote_nodes[0]
	var node: TextureRect = entry["node"]
	var period: float = entry["period"]

	# node.global_position depends on an actual sized/anchored layout tree
	# (this bare instance has none, unlike _make_root()) — instead read the
	# anchor fraction that apply_image_fraction_rect() itself computed from
	# the mote's current y, which is a layout-independent proxy for "did the
	# vertical position actually change".
	var anchor_tops: Array[float] = []
	var alphas: Array[float] = []
	var t := 0.0
	while t < period:
		effects._elapsed = t
		effects._process(0.0)
		anchor_tops.append(node.anchor_top)
		alphas.append(node.modulate.a)
		t += period * 0.1

	var min_anchor := anchor_tops[0]
	var max_anchor := anchor_tops[0]
	for a_top in anchor_tops:
		min_anchor = minf(min_anchor, a_top)
		max_anchor = maxf(max_anchor, a_top)
	assert_gt(max_anchor - min_anchor, 0.001, "the internal light must actually travel a visible vertical distance over one period")

	var max_alpha := 0.0
	var min_alpha := 1.0
	for a in alphas:
		max_alpha = maxf(max_alpha, a)
		min_alpha = minf(min_alpha, a)
	assert_gt(max_alpha, 0.05, "the internal light must actually become visible at some point in its cycle")
	assert_lt(min_alpha, max_alpha - 0.05, "the internal light must fade, not stay at constant alpha (proves it is not just a static dot)")

## §11: 赤/青/緑は完全同期しないこと（periodとphaseがいずれも異なるため、
## 同じ時刻でも周期内の進行度(t_in_cycle)が食い違うはず）。
func test_the_three_device_colors_are_not_perfectly_synchronized() -> void:
	var points: Array = RBMTitleEffects.DEVICE_MOTE_POINTS
	var desync_observed := false

	var t := 0.0
	while t < 6.0:
		var cycle_positions: Array[float] = []
		for def in points:
			var period: float = def["period"]
			var phase: float = def["phase"]
			var t_in_cycle := fmod(t + phase, period) / period
			cycle_positions.append(t_in_cycle)
		var first: float = cycle_positions[0]
		for v in cycle_positions:
			if absf(v - first) > 0.05:
				desync_observed = true
		t += 0.1

	assert_true(desync_observed, "over a 6s window, red/blue/green must show different cycle progress at least once (not perfectly synchronized)")

## §12: ボスの目の既存仕様（周期・パルス長・振幅）は今回変更しないこと——
## 定数値そのものを直接固定してリグレッションを検出する。
func test_boss_eye_existing_spec_is_unchanged_this_round() -> void:
	assert_almost_eq(RBMTitleEffects.EYE_PERIOD, 7.5, 0.001, "eye glow period must remain unchanged this round (§12)")
	assert_almost_eq(RBMTitleEffects.EYE_PULSE_DURATION, 0.75, 0.001, "eye pulse duration must remain unchanged this round (§12)")
	assert_almost_eq(RBMTitleEffects.EYE_PULSE_AMPLITUDE, 0.55, 0.001, "eye pulse amplitude must remain unchanged this round (§12)")
	assert_eq(RBMTitleEffects.EYE_POINTS.size(), 2, "still exactly the two eye points, no new boss-motion nodes added")

# =============================================================================
# 炎修正版（v2）— 「壁まで動く」不具合の回帰テスト
# =============================================================================

## §9-1: 炎フレームPNGが「炎周辺の背景まで含む不透明な矩形画像」に戻って
## いないことを検証する——旧v1バグの直接的な回帰ガード。透過抽出方式なら
## キャンバスの大部分（炎が実際に占める面積はごく一部）がalpha=0のはずで、
## 逆に旧v1のような不透明な矩形クロップなら透過ピクセルはほぼ0%になる。
func test_fire_frames_are_transparent_overlays_not_opaque_rectangles() -> void:
	for def in RBMTitleEffects.FIRE_SHAPE_POINTS:
		var prefix: String = def["prefix"]
		var path := "%s%s_f0.png" % [RBMTitleEffects.FIRE_SHAPE_DIR, prefix]
		var tex: Texture2D = load(path)
		assert_not_null(tex, "fire frame must exist at %s" % path)
		var img := tex.get_image()
		assert_eq(img.get_format(), Image.FORMAT_RGBA8, "%s must carry an alpha channel" % prefix)

		var total := img.get_width() * img.get_height()
		var transparent := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a < 0.02:
					transparent += 1
		var transparent_fraction := float(transparent) / float(total)
		assert_gt(transparent_fraction, 0.5, "%s: at least half the canvas must be fully transparent (got %.1f%%) -- an opaque background-including rectangle would be ~0%% transparent" % [prefix, transparent_fraction * 100.0])

## §9-2: フレーム間の差分（実際に動くピクセル）が、キャンバス全体ではなく
## 限定された範囲に収まっていることを確認する——差分が広範囲に散らばって
## いれば、炎以外の何か（壁のテクスチャ全体など）まで一緒に動いている
## 兆候となる。
func test_fire_frame_differences_stay_within_a_bounded_local_region() -> void:
	for def in RBMTitleEffects.FIRE_SHAPE_POINTS:
		var prefix: String = def["prefix"]
		var img0: Image = (load("%s%s_f0.png" % [RBMTitleEffects.FIRE_SHAPE_DIR, prefix]) as Texture2D).get_image()
		var img1: Image = (load("%s%s_f1.png" % [RBMTitleEffects.FIRE_SHAPE_DIR, prefix]) as Texture2D).get_image()
		assert_eq(img0.get_size(), img1.get_size(), "%s: frame0/frame1 canvas size must match" % prefix)

		var w := img0.get_width()
		var h := img0.get_height()
		var min_x := w
		var min_y := h
		var max_x := -1
		var max_y := -1
		var diff_count := 0
		for y in range(h):
			for x in range(w):
				if img0.get_pixel(x, y) != img1.get_pixel(x, y):
					diff_count += 1
					min_x = mini(min_x, x)
					min_y = mini(min_y, y)
					max_x = maxi(max_x, x)
					max_y = maxi(max_y, y)

		assert_gt(diff_count, 0, "%s: frame0 and frame1 must actually differ somewhere (proves the flame is genuinely animated)" % prefix)
		var diff_area := float((max_x - min_x + 1) * (max_y - min_y + 1))
		var total_area := float(w * h)
		assert_lt(diff_area / total_area, 0.5, "%s: the changed-pixel bounding box must cover well under half the canvas (localized to the flame tip, not the whole crop)" % prefix)

## §9-3: 実際のGDScriptランタイム(RBMTitleEffects._process)が選ぶフレーム
## テクスチャも、透過版アセットを正しく参照していること（アセット差し替え
## がコードの参照先まで正しく反映されていることの確認、パス文字列だけの
## 静的チェックでは検出できないランタイム経路）。
func test_runtime_fire_shape_nodes_reference_the_transparent_frames() -> void:
	var effects := RBMTitleEffects.new()
	add_child_autofree(effects)
	await get_tree().process_frame

	for entry in effects._fire_shape_nodes:
		var textures: Array = entry["textures"]
		for tex in textures:
			var img: Image = (tex as Texture2D).get_image()
			var has_transparent_pixel := false
			for y in range(img.get_height()):
				for x in range(img.get_width()):
					if img.get_pixel(x, y).a < 0.02:
						has_transparent_pixel = true
						break
				if has_transparent_pixel:
					break
			assert_true(has_transparent_pixel, "runtime-loaded fire frame texture must contain transparent pixels (confirms it is the v2 asset, not a stale opaque one)")
