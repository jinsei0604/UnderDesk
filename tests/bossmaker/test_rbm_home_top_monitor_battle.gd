extends GutTest

## 上中央モニターのボス戦プレビュー(承認済み独立プレビューの本実装)——
## 回帰テスト。
##
## 演出品質・戦闘映像の見た目・CRT表現の強さはGUTでは無理に検証せず、
## GPU実機のスクリーンショット/動画で別途確認する(ユーザー指示どおり)。
## ここでは以下だけを直接検証する:
##   - 確定Rectが固定値のまま
##   - ホーム画面表示中は自動再生(_running=true)される
##   - Challenge/Creatorへ入ると停止する
##   - タイトルへ戻ると再開する
##   - 表示パーティーが勇者/老執事/侍/ヒーラーの4人固定(ハンマー使いなし)
##   - ボスの見た目appearanceが竜ではない(禁止事項)

const TOP_RECT := Rect2(254.0, 37.0, 772.0, 291.0)

func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(1280, 720)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

func _await_battle_ready(root: RBMGameRoot) -> void:
	var ticks := 0
	while not root._top_monitor_battle._initialized and ticks < 300:
		await get_tree().process_frame
		ticks += 1
	assert_true(root._top_monitor_battle._initialized, "battle preview must finish initializing")

## テスト終了時、add_child_autofree()がノードを解放する前に必ず呼ぶ——
## start_loop()で開始した非同期ループ(await get_tree().process_frame)が
## 宙吊りのまま解放されると、次のresume時に「Resumed function after
## await, but class instance is gone」エラーになるため、stop_loop()で
## _run_tokenを進めたうえで1フレーム待ち、ループ側の_alive()チェックが
## 実際に働いて自然終了する猶予を与える。
func _settle(root: RBMGameRoot) -> void:
	root._top_monitor_battle.stop_loop()
	await get_tree().process_frame

func test_confirmed_rect_is_fixed() -> void:
	assert_eq(RBMGameRoot.HOME_TOP_MONITOR_RECT, TOP_RECT, "top monitor rect must not be re-adjusted")

func test_top_monitor_node_is_positioned_from_the_confirmed_rect_only() -> void:
	var root := await _make_root()
	assert_eq(root._top_monitor_battle.position, TOP_RECT.position)
	assert_eq(root._top_monitor_battle.size, TOP_RECT.size)
	# _init_battle()自身は一度きりのセットアップで独自のawaitループを持つ
	# ため(_run_tokenのキャンセルチェックを持たない)、解放前に完了させる。
	await _await_battle_ready(root)
	await _settle(root)

func test_battle_preview_autoplays_on_the_home_screen() -> void:
	var root := await _make_root()
	await _await_battle_ready(root)
	assert_true(root._top_monitor_battle._running, "must auto-play while the home screen is shown")
	await _settle(root)

func test_battle_preview_stops_when_entering_challenge_and_resumes_on_return() -> void:
	var root := await _make_root()
	await _await_battle_ready(root)
	assert_true(root._top_monitor_battle._running)

	root._show_only(root.challenge_entry)
	assert_false(root._top_monitor_battle._running, "must stop when the home screen is left")

	root._show_menu()
	assert_true(root._top_monitor_battle._running, "must resume when the home screen is shown again")
	await _settle(root)

func test_battle_preview_stops_when_entering_creator_and_resumes_on_return() -> void:
	var root := await _make_root()
	await _await_battle_ready(root)

	root._show_only(root.creator_entry)
	assert_false(root._top_monitor_battle._running)

	root._show_menu()
	assert_true(root._top_monitor_battle._running)
	await _settle(root)

func test_party_is_fixed_to_hero_butler_samurai_healer_without_tank() -> void:
	var root := await _make_root()
	await _await_battle_ready(root)
	var ids: Array = []
	for unit in root._top_monitor_battle._view.session.battle.party:
		ids.append(unit.character_id)
	ids.sort()
	var expected: Array = ["butler", "healer", "hero", "samurai"]
	assert_eq(ids, expected, "party must be exactly hero/butler/samurai/healer, no tank")
	await _settle(root)

func test_boss_appearance_is_not_the_dragon() -> void:
	var root := await _make_root()
	await _await_battle_ready(root)
	assert_eq(root._top_monitor_battle._view._boss_appearance_id, "appearance_golem")
	assert_ne(root._top_monitor_battle._view._boss_appearance_id, "appearance_dragon", "dragon is not finished and must not be used")
	await _settle(root)

func test_left_right_home_monitors_still_work_alongside_the_top_monitor() -> void:
	var root := await _make_root()
	await _await_battle_ready(root)
	assert_eq(root._challenge_monitor.position, RBMGameRoot.HOME_MONITOR_CHALLENGE_RECT.position)
	assert_eq(root._creator_monitor.position, RBMGameRoot.HOME_MONITOR_CREATE_RECT.position)
	assert_eq(root._challenge_monitor.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(root._creator_monitor.mouse_filter, Control.MOUSE_FILTER_STOP)
	await _settle(root)
