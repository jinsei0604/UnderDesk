class_name UDOffline
extends RefCounted
## Offline progression: elapsed wall-clock time -> tick count, capped (§7.1-4).
## The caller feeds the result to UDSim.advance(), which runs the exact same
## tick() used in realtime, guaranteeing equivalence.


static func elapsed_ticks(saved_unix_time: int, now_unix_time: int) -> int:
	var elapsed_seconds: int = maxi(0, now_unix_time - saved_unix_time)
	var ticks: int = int(float(elapsed_seconds) / UD.TICK_SECONDS)
	return mini(ticks, UD.MAX_OFFLINE_TICKS)
