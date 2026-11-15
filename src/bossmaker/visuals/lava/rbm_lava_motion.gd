class_name RBMLavaMotion
extends RefCounted
## 熔鉱炉の番人／噴界炉の巨神（lava）のキーポーズの読み込み（表示専用）。
## 本体は Codex のキーポーズ（2026-11-11、assets_bossmaker/battle/lava/motion/<技>/<番号>.png、320×180、足元 (176,155)）を
## そのまま切り替えるだけで、中割り・変形・パーツ分割はしない（2026-11-14 ユーザーが確認動画で採用）。
## 技: pre_single・pre_all（覚醒前）、awaken（覚醒）、post_single・post_all（覚醒後）。

const ROOT := "res://assets_bossmaker/battle/lava/motion/"
const POSES_PATH := ROOT + "poses.json"
## エフェクトを付ける場所（tools/lava/bake_lava_assets.gd が測る。技ごとに [front, top, center, mark] の絵の画素）
const ANCHORS_PATH := ROOT + "anchors.json"
## 覚醒後の常時オーラの距離（tools/lava/bake_lava_assets.gd が焼く）
const FIELD_ROOT := "res://assets_bossmaker/battle/lava/aura_fields/"
const ORIGIN := Vector2(176, 155)
const MOVES := ["pre_single", "pre_all", "awaken", "post_single", "post_all"]
## 立ち姿: 覚醒前＝awaken の1枚目、覚醒後＝awaken の5枚目（覚醒し終えた姿。試作で採用した立ち絵）
const STANCE := {"pre": ["awaken", 1], "post": ["awaken", 5]}
## 覚醒後の常時オーラを焼くポーズ
const AURA_POSES := {"post_single": [1, 2, 3, 4], "post_all": [1, 2, 3, 4], "awaken": [4, 5]}
## 立ち絵（frames/00〜11.png）に切り出すキーポーズの範囲（覚醒前・覚醒後とも同じ。足元はこの中の (80,131)）
const STANCE_CROP := Rect2i(96, 24, 168, 136)
const M_SIDE := 34
const M_TOP := 64

static var _poses := {}
static var _anchors := {}

static func pose_path(move: String, n: int) -> String:
	return ROOT + "%s/%02d.png" % [move, n]

static func pose_count(move: String) -> int:
	return (data().get(move, []) as Array).size()

static func data() -> Dictionary:
	if _poses.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POSES_PATH))
		if parsed is Dictionary:
			_poses = parsed["poses"]
	return _poses

## [x0, y0, x1, y1]（右と下は含まない）
static func bbox(move: String, n: int) -> Array:
	var list: Array = data().get(move, [])
	return list[n - 1]["bbox"] if n >= 1 and n <= list.size() else [0, 0, 0, 0]

static func stance_path(form: String) -> String:
	var s: Array = STANCE[form]
	return pose_path(str(s[0]), int(s[1]))

static func field_path(move: String, n: int) -> String:
	return FIELD_ROOT + "%s_%d.res" % [move, n]

## 距離の画像の左上（絵の画素）。
static func field_origin(move: String, n: int) -> Vector2:
	var b := bbox(move, n)
	return Vector2(float(b[0]) - M_SIDE, float(b[1]) - M_TOP)

static func has_field(move: String, n: int) -> bool:
	return AURA_POSES.has(move) and (AURA_POSES[move] as Array).has(n)

static func anchors() -> Dictionary:
	if _anchors.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ANCHORS_PATH))
		if parsed is Dictionary:
			_anchors = parsed
	return _anchors
