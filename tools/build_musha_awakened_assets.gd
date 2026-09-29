extends SceneTree

## 朽ちた機械武者の覚醒後(asset id "musha_awakened")の本番用素材を、承認済み
## v4試作の素材から組み立てる一回限りのツール。
##
## 使い方(--srcはv4試作のassetsフォルダ。個人の一時フォルダをコードへ固定しない):
##   godot --headless --path . -s res://tools/build_musha_awakened_assets.gd -- --src=<v4試作のassets>
##
## 生成物(res://assets_bossmaker/battle/musha_awakened/):
##   awakened.png / swing.png / brush.png / new_regions.json  試作素材をそのまま配置(演出が使う)
##   design.png                                             覚醒後の静止姿(抜刀待機、眼の細い赤線を焼き込み済み)
##   frames/00..11.png + frames.json                        通常表示用(全ポーズ同じ静止姿)

const OUT := "res://assets_bossmaker/battle/musha_awakened/"
## awakened.pngの4番目(抜刀待機)。矩形・足元・眼の位置は試作の確定値(new_regions.json / scene.gd)。
const IDLE_RECT := Rect2i(672, 640, 456, 579)
const IDLE_FOOT := Vector2i(971, 1215)
const IDLE_EYE := Vector2i(925, 742)
## 表示倍率0.335(試作)。表示の高さ = 579 * 0.335。
## キャンバスは、通常版(musha: 1200x1800にキャラ高さ1410=78.3%、上余白16.1%)と同じ比率にする——
## ボス選択画面のプレビューはキャンバスに合わせて縮小表示されるため、余白の比率が違うと
## 同じ高さのキャラが違う大きさに見える。戦闘中の表示(body_height基準)には影響しない。
const CANVAS := Vector2i(536, 739)
const CROP_AT := Vector2i(40, 119)

func _init() -> void:
	var src := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="):
			src = arg.substr("--src=".length())
	if src.is_empty():
		printerr("--src=<v4試作のassetsフォルダ> を指定してください")
		quit(1)
		return
	if not src.ends_with("/"):
		src += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	for file_name in ["awakened.png", "swing.png", "brush.png", "new_regions.json"]:
		var bytes := FileAccess.get_file_as_bytes(src + file_name)
		if bytes.is_empty():
			printerr("missing: " + src + file_name)
			quit(1)
			return
		var f := FileAccess.open(OUT + file_name, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()

	var atlas := Image.load_from_file(src + "awakened.png")
	atlas.convert(Image.FORMAT_RGBA8)
	var crop := atlas.get_region(IDLE_RECT)
	# 試作のboss_new()と同じく、原画の眼を暗色で覆ってから細い赤線を描く(覚醒後は常に点灯)。
	var eye := IDLE_EYE - IDLE_RECT.position
	crop.fill_rect(Rect2i(eye - Vector2i(7, 10), Vector2i(15, 21)), Color(.035, .027, .032))
	crop.fill_rect(Rect2i(eye - Vector2i(10, 2), Vector2i(20, 4)), Color(1, .04, .05))
	crop.fill_rect(Rect2i(eye - Vector2i(4, 1), Vector2i(8, 2)), Color(1, .6, .52))
	crop.save_png(ProjectSettings.globalize_path(OUT + "design.png"))

	var frame := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	frame.blit_rect(crop, Rect2i(Vector2i.ZERO, IDLE_RECT.size), CROP_AT)
	for i in range(12):
		frame.save_png(ProjectSettings.globalize_path(OUT + "frames/%02d.png" % i))

	var foot := IDLE_FOOT - IDLE_RECT.position + CROP_AT
	var bbox := [CROP_AT.x, CROP_AT.y, IDLE_RECT.size.x, IDLE_RECT.size.y]
	var pose_records: Array = []
	for i in range(12):
		pose_records.append({"index": i, "bbox": bbox})
	var meta := {
		"asset_id": "musha_awakened",
		"canvas": [CANVAS.x, CANVAS.y],
		"foot": [foot.x, foot.y],
		"body_height": IDLE_RECT.size.y,
		"poses": pose_records,
	}
	var m := FileAccess.open(OUT + "frames.json", FileAccess.WRITE)
	m.store_string(JSON.stringify(meta, "  "))
	m.close()
	print("MUSHA_AWAKENED_ASSETS_OK foot=%s canvas=%s display_height=%.3f" % [foot, CANVAS, IDLE_RECT.size.y * 0.335])
	quit(0)
