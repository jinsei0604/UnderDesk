extends RefCounted
## Register only approved, implemented rooms. The launch room is cached for this process;
## returning home or recreating the launcher must not change it.
const ROOMS := {
	"musha": preload("res://src/bossmaker/title_rooms/musha_room.tscn"),
	"gentleman": preload("res://src/bossmaker/title_rooms/gentleman_room.tscn"),
	"astronaut": preload("res://src/bossmaker/title_rooms/astronaut_room.tscn"),
}
## 起動で使う部屋は、体験版・製品版とも宇宙飛行士だけ（2026-11-04 体験版、2026-11-08 製品版もユーザー判断: ほかの部屋は品質が足りない）。
## ほかの部屋は登録と素材を残す（直した時に LAUNCH_ROOM を戻せるように）。
const LAUNCH_ROOM := "astronaut"
static var _session_room_id: String = ""

static func session_room_id() -> String:
	if _session_room_id.is_empty():
		_session_room_id = LAUNCH_ROOM
	return _session_room_id

static func create_session_room() -> Node2D:
	return ROOMS[session_room_id()].instantiate() as Node2D
