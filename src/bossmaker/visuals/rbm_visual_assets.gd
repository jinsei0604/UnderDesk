class_name RBMVisualAssets
extends RefCounted

## Presentation-only asset map. No combat master or saved appearance ID changes.
const ROOT := "res://assets_bossmaker/battle/"
const POSE_COUNT := 12
const POSE_CANVAS := Vector2(512, 512)
const POSE_FOOT := Vector2(256, 460)
const ALLY_IDS := ["hero", "butler", "healer", "samurai", "tank"]
const BOSS_IDS := ["slime", "wolf", "knight", "dragon", "ghost", "golem", "musha", "astronaut", "gentleman"]
const HEIGHTS := {"hero": 100.222222, "butler": 104.777778, "healer": 82.0, "samurai": 104.777778, "tank": 111.611111,
	"slime": 150.0, "wolf": 155.0, "knight": 170.0, "dragon": 180.0, "ghost": 160.0, "golem": 180.0, "musha": 180.0,
	# 覚醒後の朽ちた機械武者: 抜刀待機(高さ579px)を試作の確定倍率0.335で表示する。
	"musha_awakened": 193.965, "astronaut": 116.0, "astronaut_awakened": 116.0, "gentleman": 160.0, "gentleman_awakened": 160.0}
const APPEARANCES := {
	"appearance_slime": "slime", "appearance_wolf": "wolf", "appearance_knight": "knight",
	"appearance_dragon": "dragon", "appearance_ghost": "ghost", "appearance_golem": "golem",
	"appearance_musha": "musha", "appearance_astronaut": "astronaut", "appearance_gentleman": "gentleman",
}
## Awakening designs use the existing <boss>_awakened asset folder convention.
## Only explicitly supported bosses receive such assets; normal saved IDs are unchanged.
const AWAKENED_SUFFIX := "_awakened"

## 行動順などに出すボスの顔の位置（frames/00.png の中。[中心 x, 中心 y, 一辺]。中心は絵の幅・高さに対する割合、
## 一辺は絵の幅に対する割合）。2026-10-23 に13枚を目で確かめて決めた（prototypes/battle_ui_designs_2026-10-23/tools/boss_faces.json）。
## 行動順に出す22pxでも目と口元が見えるよう、竜・覚醒後の竜は低く狭くした（prototypes/battle_hud_c_2026-10-23/review/_faces22_*.png）。
## ここに無いもの（味方など）は空を返し、RBMBattleUiKit.build_portrait() の切り出し（絵の上の真ん中）を使う。
const FACE_REGIONS := {
	"slime": [0.47, 0.72, 0.32], "wolf": [0.31, 0.4, 0.22], "knight": [0.56, 0.32, 0.2], "dragon": [0.29, 0.585, 0.19],
	"ghost": [0.4, 0.23, 0.24], "golem": [0.47, 0.38, 0.22], "musha": [0.41, 0.28, 0.42], "astronaut": [0.47, 0.3, 0.24],
	"gentleman": [0.475, 0.225, 0.16], "dragon_awakened": [0.315, 0.6, 0.17], "musha_awakened": [0.52, 0.31, 0.42],
	"astronaut_awakened": [0.5, 0.29, 0.24], "gentleman_awakened": [0.49, 0.235, 0.15],
}

static var _texture_cache: Dictionary = {}

## ボスの顔の範囲（絵の画素の座標、絵の中に収める）。決めていない絵は空。
static func face_region(asset_id: String, image_size: Vector2) -> Rect2:
	if not FACE_REGIONS.has(asset_id) or image_size.x <= 0.0 or image_size.y <= 0.0:
		return Rect2()
	var f: Array = FACE_REGIONS[asset_id]
	var side := image_size.x * float(f[2])
	var region := Rect2(image_size.x * float(f[0]) - side * 0.5, image_size.y * float(f[1]) - side * 0.5, side, side)
	return region.intersection(Rect2(Vector2.ZERO, image_size))

static func known(asset_id: String) -> bool:
	if ALLY_IDS.has(asset_id) or BOSS_IDS.has(asset_id):
		return true
	if asset_id.ends_with(AWAKENED_SUFFIX):
		return BOSS_IDS.has(asset_id.substr(0, asset_id.length() - AWAKENED_SUFFIX.length()))
	return false

static func awakened_asset_id(asset_id: String) -> String:
	return asset_id if asset_id.ends_with(AWAKENED_SUFFIX) else asset_id + AWAKENED_SUFFIX

static func has_awakened_design(asset_id: String) -> bool:
	return ResourceLoader.exists(design_path(awakened_asset_id(asset_id)), "Texture2D")

static func boss_asset(appearance_id: String) -> String:
	# Empty/unknown IDs remain explicit unknowns. Do not invent a saved or visual
	# mapping between a fixture boss ID and one of the authored boss appearances.
	return str(APPEARANCES.get(appearance_id, ""))

static func display_height(asset_id: String) -> float:
	var base_id := asset_id.trim_suffix(AWAKENED_SUFFIX)
	return float(HEIGHTS.get(asset_id, HEIGHTS.get(base_id, 100.0)))

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
