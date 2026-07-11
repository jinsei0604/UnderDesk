class_name UDDaily
extends RefCounted
## §5.4: one shared ley-line anomaly per day. The seed derives from the
## calendar date with a locally implemented FNV-1a hash, so every player
## rolls the same anomaly without a server. (String.hash() stability
## across engine versions is not guaranteed; §12-5 demands ours is.)


static func date_key(date: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


static func seed_for_date_key(key: String) -> int:
	var h: int = 0x811c9dc5
	for i in key.length():
		h = h ^ key.unicode_at(i)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h


## Deterministic pick from the (filename-sorted) anomaly list.
static func anomaly_for_date_key(anomalies: Array, key: String) -> Dictionary:
	if anomalies.is_empty():
		return {}
	return anomalies[seed_for_date_key(key) % anomalies.size()]
