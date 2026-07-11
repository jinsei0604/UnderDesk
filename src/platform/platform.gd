class_name UDPlatform
extends RefCounted
## Platform-services abstraction (§8: src/platform/). The desktop build
## is a silent no-op; a Steam backend will subclass this and forward
## unlocks to the Steamworks API. Game code only ever talks to this
## interface, so shipping without Steam stays a one-line change.


static func create() -> UDPlatform:
	# Steam backend lands here later (P4): detect and return UDSteam.
	return UDPlatform.new()


## Called once per achievement, the first time it is earned.
func notify_unlock(_achievement_id: String) -> void:
	pass
