extends GutTest

## ホーム画面モニター（左下「挑戦」／右下「ボス作成」、承認済み独立プレビュー
## の本実装）— 回帰テスト。
##
## 見た目・演出の質感（発光の強さ・タイミングの気持ちよさ等）はGUTでは
## 無理に検証せず、GPU実機のスクリーンショット/動画で別途確認する
## （ユーザー指示どおり）。ここでは以下だけを直接検証する:
##   - 確定Rect(左/右)が固定値のまま
##   - ホバー/クリック判定が各Rect（＝Controlのposition/size）に限定される
##   - 左クリックでChallenge遷移処理が呼ばれる
##   - 右クリックでCreator遷移処理が呼ばれる
##   - BOOT中の状態遷移(IDLE→BOOTING→タイトルへ戻るとIDLEへ復帰)が正常
##   - 二重入力/二重遷移が起きない
##
## 既存のdirtyな test_rbm_phase35_title_screen.gd には一切触れない
## （ユーザー指示どおり、新規ファイルとして追加）。

const CHALLENGE_RECT := Rect2(52.0, 365.0, 568.0, 248.0)
const CREATE_RECT := Rect2(660.0, 365.0, 568.0, 248.0)

func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(1280, 720)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

## test_rbm_e2e_full_journey.gd / test_rbm_phase35_step4_battle_ui.gdが既に
## 確立している「合成InputEventMouseButtonをgui_inputへ直接emitする」手法を
## そのまま踏襲する（RBMHomeMonitorPanelはPanelContainer系のControlと同様、
## gui_inputシグナルへの接続でクリックを検知するため）。
func _click(panel: RBMHomeMonitorPanel) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	panel.gui_input.emit(release)

func _await_seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		var dt: float = get_tree().root.get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		elapsed += dt

# =============================================================================
# 確定Rect
# =============================================================================

func test_confirmed_rects_are_fixed() -> void:
	assert_eq(RBMGameRoot.HOME_MONITOR_CHALLENGE_RECT, CHALLENGE_RECT, "left rect must not be re-adjusted")
	assert_eq(RBMGameRoot.HOME_MONITOR_CREATE_RECT, CREATE_RECT, "right rect must not be re-adjusted")

func test_monitor_panels_are_positioned_and_sized_from_the_confirmed_rect_only() -> void:
	var root := await _make_root()
	assert_eq(root._challenge_monitor.position, CHALLENGE_RECT.position)
	assert_eq(root._challenge_monitor.size, CHALLENGE_RECT.size)
	assert_eq(root._creator_monitor.position, CREATE_RECT.position)
	assert_eq(root._creator_monitor.size, CREATE_RECT.size)

# =============================================================================
# ホバー/クリック判定範囲
# =============================================================================

## GodotのControlは既定でposition/sizeそのものが当たり判定(_has_point)の
## 矩形になる——この2つが確定Rectと一致していることは、上のテストで既に
## 検証済み。ここでは実際にmouse_filter=STOPで入力を受け取る状態であり、
## かつそのControl自身の矩形がその外側へはみ出していないことを併せて
## 確認する。
func test_monitor_panels_accept_input_only_within_their_own_rect() -> void:
	var root := await _make_root()
	assert_eq(root._challenge_monitor.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(root._creator_monitor.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(root._challenge_monitor.get_rect(), CHALLENGE_RECT)
	assert_eq(root._creator_monitor.get_rect(), CREATE_RECT)

func test_hover_dims_only_the_other_panel() -> void:
	var root := await _make_root()
	root._challenge_monitor.mouse_entered.emit()
	await _await_seconds(0.25)
	assert_gt(root._creator_monitor._panel_draw.dim, 0.0, "hovering the left monitor should dim the right one")
	root._challenge_monitor.mouse_exited.emit()
	await _await_seconds(0.25)
	assert_almost_eq(root._creator_monitor._panel_draw.dim, 0.0, 0.01)

# =============================================================================
# クリック→遷移
# =============================================================================

func test_left_click_eventually_triggers_challenge_transition() -> void:
	var root := await _make_root()
	_click(root._challenge_monitor)
	await _await_seconds(3.0)
	assert_true(root.challenge_entry.visible, "挑戦 monitor must navigate to Challenge")
	assert_false(root._title_screen.visible)

func test_right_click_eventually_triggers_creator_transition() -> void:
	var root := await _make_root()
	_click(root._creator_monitor)
	await _await_seconds(3.0)
	assert_true(root.creator_entry.visible, "ボス作成 monitor must navigate to Creator")
	assert_false(root._title_screen.visible)

# =============================================================================
# BOOT中の状態遷移
# =============================================================================

func test_boot_state_transitions_from_idle_to_booting_and_back_to_idle_on_return() -> void:
	var root := await _make_root()
	assert_eq(root._challenge_monitor._state, RBMHomeMonitorPanel._State.IDLE)

	_click(root._challenge_monitor)
	await get_tree().process_frame
	assert_eq(root._challenge_monitor._state, RBMHomeMonitorPanel._State.BOOTING, "must enter BOOTING immediately on click")

	await _await_seconds(3.0)
	assert_true(root.challenge_entry.visible)
	assert_eq(root._challenge_monitor._state, RBMHomeMonitorPanel._State.BOOTING, "stays BOOTING until the title screen is shown again")

	# 戻り導線: Challengeから戻るとタイトルのモニターは通常表示へ復帰する。
	root._on_challenge_exit_requested()
	assert_eq(root._challenge_monitor._state, RBMHomeMonitorPanel._State.IDLE, "returning to the title screen must reset to IDLE")
	assert_eq(root._challenge_monitor.position, CHALLENGE_RECT.position)
	assert_eq(root._challenge_monitor.size, CHALLENGE_RECT.size)
	assert_eq(root._challenge_monitor.mouse_filter, Control.MOUSE_FILTER_STOP, "interactivity must be restored")

func test_expand_animation_grows_the_same_control_toward_fullscreen() -> void:
	var root := await _make_root()
	_click(root._challenge_monitor)
	await _await_seconds(0.3)
	# BOOT演出の途中(拡大が始まる前、boot_durは約0.88秒)ではまだhome_rectの
	# まま——別Controlへ差し替えるのではなく、同じControlのposition/size
	# をこの後に直接補間することを確認する。
	assert_eq(root._challenge_monitor.size, CHALLENGE_RECT.size, "still the original rect while BOOT is still in progress")
	await _await_seconds(3.0)
	assert_eq(root._challenge_monitor.size, RBMHomeMonitorPanel.SCREEN_SIZE, "the same Control has grown to fill the screen after expansion")

# =============================================================================
# 二重入力/二重遷移防止
# =============================================================================

func test_double_click_on_the_same_panel_during_boot_is_ignored() -> void:
	var root := await _make_root()
	# GDScriptのラムダはローカル変数を値渡しでキャプチャするため、可変
	# 参照として使えるよう1要素配列に包む（このセッションで既に確認済みの
	# 定石）。
	var activation_count := [0]
	root._challenge_monitor.activated.connect(func(): activation_count[0] += 1)

	_click(root._challenge_monitor)
	await get_tree().process_frame
	_click(root._challenge_monitor)
	_click(root._challenge_monitor)
	await _await_seconds(3.0)

	assert_eq(activation_count[0], 1, "a second click mid-BOOT must not trigger a second activation")

func test_boot_on_one_panel_disables_input_on_the_other() -> void:
	var root := await _make_root()
	_click(root._challenge_monitor)
	await get_tree().process_frame
	assert_eq(root._creator_monitor.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the other monitor must not be clickable while one is booting")
	await _await_seconds(3.0)

func test_clicking_the_other_panel_while_one_is_booting_does_not_start_a_second_boot() -> void:
	var root := await _make_root()
	var challenge_activations := [0]
	var creator_activations := [0]
	root._challenge_monitor.activated.connect(func(): challenge_activations[0] += 1)
	root._creator_monitor.activated.connect(func(): creator_activations[0] += 1)

	_click(root._challenge_monitor)
	await get_tree().process_frame
	# 反対側はmouse_filter=IGNOREになっているはずだが、念のためロジック側の
	# ガードも直接突いて二重遷移が起きないことを確認する。
	_click(root._creator_monitor)
	await _await_seconds(3.0)

	assert_eq(challenge_activations[0], 1)
	assert_eq(creator_activations[0], 0, "the other monitor must never activate while the first is still booting")
