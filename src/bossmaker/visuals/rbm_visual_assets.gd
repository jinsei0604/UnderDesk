class_name RBMVisualAssets
extends RefCounted

## Presentation-only asset map. No combat master or saved appearance ID changes.
const ROOT := "res://assets_bossmaker/battle/"
const POSE_COUNT := 12
const POSE_CANVAS := Vector2(512, 512)
const POSE_FOOT := Vector2(256, 460)
const ALLY_IDS := ["hero", "butler", "healer", "samurai", "tank"]
const BOSS_IDS := ["slime", "wolf", "knight", "dragon", "ghost", "golem"]
const HEIGHTS := {"hero": 100.222222, "butler": 104.777778, "healer": 82.0, "samurai": 104.777778, "tank": 111.611111,
	"slime": 150.0, "wolf": 155.0, "knight": 170.0, "dragon": 180.0, "ghost": 160.0, "golem": 180.0}
const APPEARANCES := {
	"appearance_slime": "slime", "appearance_wolf": "wolf", "appearance_knight": "knight",
	"appearance_dragon": "dragon", "appearance_ghost": "ghost", "appearance_golem": "golem",
}
## 覚醒(Awakening)後の外見の命名規約——通常appearanceの資産と同じROOT配下、
## asset_id + AWAKENED_SUFFIXという名前のフォルダに専用design.png/framesを
## 置くだけで自動的に認識される(known()がこのsuffixを剥がした素の
## asset_idをBOSS_IDSに照らして判定するため、BOSS_IDS自体へ個別に追記する
## 必要はない)。今はまだどのボスにも覚醒後アセットが存在しないため、
## has_awakened_design()は常にfalseを返す——呼び出し側(RBMBattleStage)は
## そのまま通常の外見を保つ(is_awakened自体の内部状態には一切影響しない)。
## ボスごとの実際の覚醒後デザイン・専用モーションはユーザー側で別途制作し、
## このフォルダへ配置するだけで有効になる。
const AWAKENED_SUFFIX := "_awakened"

static var _texture_cache: Dictionary = {}

static func known(asset_id: String) -> bool:
	if ALLY_IDS.has(asset_id) or BOSS_IDS.has(asset_id):
		return true
	if asset_id.ends_with(AWAKENED_SUFFIX):
		return BOSS_IDS.has(asset_id.substr(0, asset_id.length() - AWAKENED_SUFFIX.length()))
	return false

static func awakened_asset_id(asset_id: String) -> String:
	return asset_id + AWAKENED_SUFFIX

static func has_awakened_design(asset_id: String) -> bool:
	return ResourceLoader.exists(design_path(awakened_asset_id(asset_id)), "Texture2D")

static func boss_asset(appearance_id: String) -> String:
	# Empty/unknown IDs remain explicit unknowns. Do not invent a saved or visual
	# mapping between a fixture boss ID and one of the six authored appearances.
	return str(APPEARANCES.get(appearance_id, ""))

static func display_height(asset_id: String) -> float:
	return float(HEIGHTS.get(asset_id, 100.0))

static func design_path(asset_id: String) -> String:
	return ROOT + asset_id + "/design.png" if known(asset_id) else ""

static func frame_path(asset_id: String, pose: int) -> String:
	return ROOT + asset_id + "/frames/%02d.png" % clampi(pose, 0, POSE_COUNT - 1) if known(asset_id) else ""

static func texture(asset_id: String, pose: int = 0) -> Texture2D:
	var path := frame_path(asset_id, pose)
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path, "Texture2D"):
		path = frame_path(asset_id, 0)
	if not ResourceLoader.exists(path, "Texture2D"):
		path = design_path(asset_id)
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path) as Texture2D
	return _texture_cache[path] as Texture2D

static func has_pose_frames(asset_id: String) -> bool:
	for pose in range(POSE_COUNT):
		if not ResourceLoader.exists(frame_path(asset_id, pose), "Texture2D"):
			return false
	return true

static func clear_cache() -> void:
	_texture_cache.clear()
