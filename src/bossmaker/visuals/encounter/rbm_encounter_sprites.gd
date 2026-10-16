extends RefCounted
## 登場・勝利の演出で、戦闘のキャラ（味方・ボス）の既存のポーズ画像を、本番の RBMCharacterVisual と同じ倍率・足元で描く
## （表示専用）。絵は拡大縮小で変形させない（本番と同じ表示の大きさのまま、位置とポーズだけを変える）。
## 倍率・足元・ポーズの範囲は、戦闘画面に出ているキャラの絵の部品（RBMCharacterVisual）が読み終えた値を受け取る
## （register_stage()。再生の最初のフレームでファイルを読まない）。部品が無いキャラだけ frames.json を読む。
const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")

static var _meta := {}

## ステージに出ているキャラの絵の部品から、倍率・足元・ポーズの範囲を受け取る（演出を始める前に呼ぶ）。
static func register_stage(stage: Control) -> void:
	if not is_instance_valid(stage):
		return
	var visuals: Dictionary = stage.get("_visuals")
	for key in visuals:
		var v: Object = visuals[key]
		if not is_instance_valid(v) or not ("_pixel_scale" in v) or not ("asset_id" in v):
			continue
		var id := str(v.get("asset_id"))
		if id.is_empty():
			continue
		_meta[id] = {"canvas": Vector2(v.get("_canvas_size")), "foot": Vector2(v.get("_foot")), "scale": float(v.get("_pixel_scale")),
			"poses": v.get("_pose_rects")}

## {canvas, foot, scale, poses[]}。登録が無い時だけ frames.json を読む（本番の RBMCharacterVisual.setup と同じ式）。
static func meta(asset_id: String) -> Dictionary:
	if _meta.has(asset_id):
		return _meta[asset_id]
	var path := Assets.ROOT + asset_id + "/frames.json"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	var m := {"canvas": Vector2(512, 512), "foot": Vector2(256, 460), "scale": 1.0, "poses": []}
	if data is Dictionary:
		var c: Array = data.get("canvas", [512, 512])
		var f: Array = data.get("foot", [256, 460])
		m.canvas = Vector2(c[0], c[1])
		m.foot = Vector2(f[0], f[1])
		m.poses = data.get("poses", [])
		m.scale = Assets.display_height(asset_id) / maxf(1.0, float(data.get("body_height", 400)))
	_meta[asset_id] = m
	return m

## 1体分の 12 ポーズの画像の場所（warm_paths() 用）。
static func pose_paths(asset_id: String) -> Array[String]:
	var out: Array[String] = []
	if not Assets.has_pose_frames(asset_id):
		return out
	for i in range(Assets.POSE_COUNT):
		out.append(Assets.frame_path(asset_id, i))
	return out

static func texture(asset_id: String, pose: int) -> Texture2D:
	return Assets.texture(asset_id, pose)

## 本番の RBMCharacterVisual と同じ左上の位置（足元から、整数に丸める）。
static func origin(asset_id: String, foot: Vector2) -> Vector2:
	var m := meta(asset_id)
	return (foot - Vector2(m.foot) * float(m.scale)).round()

## 1ポーズを描く。ground_y を渡すと、その高さより下は描かない（地面から現れる・沈む）。
static func draw(ci: CanvasItem, asset_id: String, pose: int, foot: Vector2, mod: Color = Color.WHITE, ground_y: float = INF) -> void:
	var tex := texture(asset_id, pose)
	if tex == null or mod.a <= 0.003:
		return
	var m := meta(asset_id)
	var s: float = m.scale
	var o := origin(asset_id, foot)
	var size: Vector2 = Vector2(m.canvas) * s
	if ground_y == INF or ground_y >= o.y + size.y:
		ci.draw_texture_rect(tex, Rect2(o, size), false, mod)
		return
	var visible_h := clampf(ground_y - o.y, 0.0, size.y)
	if visible_h <= 0.0:
		return
	var src_h := visible_h / s
	ci.draw_texture_rect_region(tex, Rect2(o, Vector2(size.x, visible_h)), Rect2(0, 0, m.canvas.x, src_h), mod)

## ポーズの見えている範囲（ステージ座標）。frames.json の bbox から。
static func pose_rect(asset_id: String, pose: int, foot: Vector2) -> Rect2:
	var m := meta(asset_id)
	var poses: Array = m.poses
	if pose >= poses.size():
		return Rect2(foot - Vector2(40, 100), Vector2(80, 100))
	var b: Array = poses[pose]["bbox"]
	var s: float = m.scale
	return Rect2(origin(asset_id, foot) + Vector2(b[0], b[1]) * s, Vector2(b[2], b[3]) * s)
