extends SceneTree

## 朽ちた機械武者(asset id "musha")の本番用素材を、承認済み試作の素材から
## 組み立てる一回限りのツール。
##
## 使い方(--srcは試作のassetsフォルダ。個人の一時フォルダをコードへ固定しない):
##   godot --headless --path . -s res://tools/build_musha_assets.gd -- --src=<試作のassets>
##
## 生成物(res://assets_bossmaker/battle/musha/):
##   poses.png / ink.png / ice.png / regions.json            試作素材をそのまま配置
##   design.png                                             静止姿(idleの使用領域を切り出したもの。演出でも使う)
##   frames/00..10.png(静止姿), frames/11.png(被弾・戦闘不能=俯いた調律姿) + frames.json

const OUT := "res://assets_bossmaker/battle/musha/"
## 試作の確定値(引き継ぎ資料 §3): idleの使用領域と、被弾/戦闘不能に使う調律姿(ID 5)の矩形・足元。
const IDLE_REGION := Rect2i(98, 145, 748, 1410)
const IDLE_HEIGHT := 180.0
const POSE5_REGION := Rect2i(1190, 543, 322, 465)
const POSE5_FOOT := Vector2i(1355, 988)
const POSE5_SCALE := 0.445
## フレームのキャンバス(idleの1ピクセル=表示上 IDLE_HEIGHT/1410)。調律姿は
## 試作の表示倍率(0.445)をこのキャンバスの縮尺へ換算して置く。
const CANVAS := Vector2i(1200, 1800)
const FOOT := Vector2i(600, 1700)

func _init() -> void:
	var src := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="):
			src = arg.substr("--src=".length())
	if src.is_empty():
		printerr("--src=<試作のassetsフォルダ> を指定してください")
		quit(1)
		return
	if not src.ends_with("/"):
		src += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))

	for file_name in ["poses.png", "ink.png", "ice.png", "regions.json"]:
		var bytes := FileAccess.get_file_as_bytes(src + file_name)
		if bytes.is_empty():
			printerr("missing: " + src + file_name)
			quit(1)
			return
		var f := FileAccess.open(OUT + file_name, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()

	var idle := Image.load_from_file(src + "idle.png")
	idle.convert(Image.FORMAT_RGBA8)
	var idle_crop := idle.get_region(IDLE_REGION)
	idle_crop.save_png(ProjectSettings.globalize_path(OUT + "design.png"))

	# frames/00.png: idle領域を足元(下辺中央)がFOOTに来るよう等倍でキャンバスへ。
	var frame0 := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	var idle_at := Vector2i(FOOT.x - IDLE_REGION.size.x / 2, FOOT.y - IDLE_REGION.size.y)
	frame0.blit_rect(idle_crop, Rect2i(Vector2i.ZERO, IDLE_REGION.size), idle_at)
	# 全12ポーズを揃える慣例(RBMVisualAssets.has_pose_frames)に従い、01〜10は静止姿と同じ。
	for i in range(11):
		frame0.save_png(ProjectSettings.globalize_path(OUT + "frames/%02d.png" % i))

	# frames/11.png: 調律姿(ID 5)を試作の表示倍率(0.445)のまま、足元アンカーをFOOTへ。
	# キャンバスの縮尺(idle 1pxあたり IDLE_HEIGHT/1410 表示px)へ換算した拡大率で最近傍拡大する。
	var poses := Image.load_from_file(src + "poses.png")
	poses.convert(Image.FORMAT_RGBA8)
	var pose5 := poses.get_region(POSE5_REGION)
	var canvas_scale := IDLE_HEIGHT / float(IDLE_REGION.size.y)
	var factor := POSE5_SCALE / canvas_scale
	var scaled_size := Vector2i(roundi(POSE5_REGION.size.x * factor), roundi(POSE5_REGION.size.y * factor))
	pose5.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)
	var anchor_local := Vector2(POSE5_FOOT - POSE5_REGION.position) * factor
	var pose5_at := Vector2i(FOOT.x - roundi(anchor_local.x), FOOT.y - roundi(anchor_local.y))
	var frame11 := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	frame11.blit_rect(pose5, Rect2i(Vector2i.ZERO, scaled_size), pose5_at)
	frame11.save_png(ProjectSettings.globalize_path(OUT + "frames/11.png"))

	var idle_bbox := [idle_at.x, idle_at.y, IDLE_REGION.size.x, IDLE_REGION.size.y]
	var pose5_bbox := [pose5_at.x, pose5_at.y, scaled_size.x, scaled_size.y]
	var pose_records: Array = []
	for i in range(12):
		var use_pose5 := (i == 11)
		pose_records.append({"index": i, "bbox": pose5_bbox if use_pose5 else idle_bbox})
	var meta := {
		"asset_id": "musha",
		"canvas": [CANVAS.x, CANVAS.y],
		"foot": [FOOT.x, FOOT.y],
		"body_height": IDLE_REGION.size.y,
		"poses": pose_records,
	}
	var m := FileAccess.open(OUT + "frames.json", FileAccess.WRITE)
	m.store_string(JSON.stringify(meta, "  "))
	m.close()
	print("MUSHA_ASSETS_OK idle_at=%s pose5_at=%s scaled=%s canvas=%s" % [idle_at, pose5_at, scaled_size, CANVAS])
	quit(0)
