class_name UDPlatform
extends RefCounted
## Platform-services abstraction (§8: src/platform/). Distribution is
## itch.io (decided 2026-07-12), which has no built-in achievements or
## cloud-save API, so this is a silent no-op for now. Achievements stay
## local (UDAchievements writes to user://). If a networked feature
## (e.g. guild trading with other players) needs a backend later, that
## backend subclasses this — game code only ever talks to this
## interface, so adding one stays a one-line change in create().


static func create() -> UDPlatform:
	return UDPlatform.new()


## Called once per achievement, the first time it is earned.
func notify_unlock(_achievement_id: String) -> void:
	pass
