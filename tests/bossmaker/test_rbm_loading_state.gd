extends GutTest

## Phase 7 — 共通ロード表示(ロジックのみ)基盤 RBMLoadingStateのテスト。
## UI表示は一切対象外——begin()/end()/is_loading()の状態管理そのものだけ
## を検証する。static varに唯一の共有インスタンスを保持する設計のため、
## 各テストの前後で必ずreset_for_testing()し、他のテストへ状態を持ち
## 越さないようにする。

func before_each() -> void:
	RBMLoadingState.reset_for_testing()

func after_each() -> void:
	RBMLoadingState.reset_for_testing()

func test_initially_not_loading() -> void:
	assert_false(RBMLoadingState.is_loading())

func test_begin_makes_it_loading() -> void:
	RBMLoadingState.begin("op_a")
	assert_true(RBMLoadingState.is_loading())

func test_end_after_begin_stops_loading() -> void:
	RBMLoadingState.begin("op_a")
	RBMLoadingState.end("op_a")
	assert_false(RBMLoadingState.is_loading())

func test_overlapping_operations_stay_loading_until_all_end() -> void:
	RBMLoadingState.begin("op_a")
	RBMLoadingState.begin("op_b")
	RBMLoadingState.end("op_a")
	assert_true(RBMLoadingState.is_loading(), "op_b is still in flight, so is_loading() must not fall back to false")
	RBMLoadingState.end("op_b")
	assert_false(RBMLoadingState.is_loading())

func test_ending_operations_in_reverse_order_still_works() -> void:
	RBMLoadingState.begin("op_a")
	RBMLoadingState.begin("op_b")
	RBMLoadingState.end("op_b")
	assert_true(RBMLoadingState.is_loading(), "op_a is still in flight")
	RBMLoadingState.end("op_a")
	assert_false(RBMLoadingState.is_loading())

func test_same_operation_id_begun_twice_requires_two_ends() -> void:
	RBMLoadingState.begin("op_a")
	RBMLoadingState.begin("op_a")
	RBMLoadingState.end("op_a")
	assert_true(RBMLoadingState.is_loading(), "a second begin() for the same id must not be cleared by a single end()")
	RBMLoadingState.end("op_a")
	assert_false(RBMLoadingState.is_loading())

func test_end_without_a_matching_begin_is_ignored_and_does_not_error() -> void:
	RBMLoadingState.end("never_begun")
	assert_false(RBMLoadingState.is_loading())

func test_end_called_more_times_than_begin_does_not_go_negative_or_break_later_tracking() -> void:
	RBMLoadingState.begin("op_a")
	RBMLoadingState.end("op_a")
	RBMLoadingState.end("op_a")
	assert_false(RBMLoadingState.is_loading())
	RBMLoadingState.begin("op_a")
	assert_true(RBMLoadingState.is_loading(), "tracking must still work correctly for op_a after an extra end() call")
	RBMLoadingState.end("op_a")
	assert_false(RBMLoadingState.is_loading())

## 失敗経路の後始末——実際の呼び出し元(RBMOnlineBossListView.refresh()等)は
## awaitの直後で必ずend()するため、後続の分岐がどこでreturnしても
## loading状態は既に正しく後始末されている、という契約をここで模する。
func test_failure_path_cleanup_matches_the_begin_then_end_immediately_after_await_pattern() -> void:
	RBMLoadingState.begin("fetch")
	var response := {"ok": false, "error_kind": "network_error"}
	RBMLoadingState.end("fetch")
	if not bool(response.get("ok", false)):
		assert_false(RBMLoadingState.is_loading(), "loading must already be false before the failure branch runs")
		return
	fail_test("unreachable")

func test_loading_started_and_ended_signals_fire_with_the_operation_id() -> void:
	var started_ids: Array = []
	var ended_ids: Array = []
	RBMLoadingState.shared().loading_started.connect(func(id: String): started_ids.append(id))
	RBMLoadingState.shared().loading_ended.connect(func(id: String): ended_ids.append(id))

	RBMLoadingState.begin("op_a")
	RBMLoadingState.end("op_a")

	assert_eq(started_ids, ["op_a"])
	assert_eq(ended_ids, ["op_a"])

func test_loading_state_changed_signal_fires_once_on_the_true_to_false_and_false_to_true_edges_only() -> void:
	var transitions: Array = []
	RBMLoadingState.shared().loading_state_changed.connect(func(is_loading: bool): transitions.append(is_loading))

	RBMLoadingState.begin("op_a")
	RBMLoadingState.begin("op_b")
	RBMLoadingState.end("op_a")
	RBMLoadingState.end("op_b")

	assert_eq(transitions, [true, false], "the signal must fire only on the actual 0->1 and 1->0 edges, not for every begin/end call")

func test_active_operation_ids_reflects_currently_in_flight_operations() -> void:
	RBMLoadingState.begin("op_a")
	RBMLoadingState.begin("op_b")
	assert_eq(RBMLoadingState.active_operation_ids().size(), 2)
	RBMLoadingState.end("op_a")
	assert_eq(RBMLoadingState.active_operation_ids(), ["op_b"])
	RBMLoadingState.end("op_b")
	assert_eq(RBMLoadingState.active_operation_ids(), [])

func test_reset_for_testing_clears_state_between_tests() -> void:
	RBMLoadingState.begin("leftover")
	RBMLoadingState.reset_for_testing()
	assert_false(RBMLoadingState.is_loading())
	assert_eq(RBMLoadingState.active_operation_ids(), [])
