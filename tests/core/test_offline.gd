extends GutTest


func test_elapsed_ticks_basic() -> void:
	assert_eq(UDOffline.elapsed_ticks(1000, 1100), 50, "100s at 2s/tick")


func test_elapsed_ticks_clock_rollback_is_zero() -> void:
	assert_eq(UDOffline.elapsed_ticks(2000, 1000), 0)


func test_elapsed_ticks_capped_at_24h() -> void:
	var three_days: int = 3 * 24 * 60 * 60
	assert_eq(UDOffline.elapsed_ticks(0, three_days), UD.MAX_OFFLINE_TICKS)
