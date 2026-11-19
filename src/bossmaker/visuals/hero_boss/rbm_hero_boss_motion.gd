extends RefCounted
## ヒーロー（hero_boss）の本体の正式モーション（Codex 2026-11-09 正式採用。motion/cels.png と motion/exposures.json）の読み込み。表示専用。
## 再生の並び（30コマ/秒のコマ番号 → [コマ名, 左上の論理ドット]）は、技の時刻表（rbm_hero_fx_timing.gd）の
## tame（指定のコマを止める長さを足す）と body_swap（見せるコマの差し替え）を足して作る。絵と座標そのものは変えない。

const ROOT := "res://assets_bossmaker/battle/hero_boss/motion/"
const SHEET_PATH := ROOT + "cels.png"
const EXPOSURES_PATH := ROOT + "exposures.json"
const FPS := 30.0
## 技 → 正式モーションの番号（04 は待機で、技には使わない）
const SEQUENCES := {"blade": "01", "array": "02", "breach": "03", "shear": "05", "press": "06"}
const TIMINGS := {
	"blade": RBMHeroFxTiming.BLADE, "array": RBMHeroFxTiming.ARRAY, "breach": RBMHeroFxTiming.BREACH,
	"shear": RBMHeroFxTiming.SHEAR, "press": RBMHeroFxTiming.PRESS,
	"heal": RBMHeroFxTiming.SUPPORT, "buff": RBMHeroFxTiming.SUPPORT, "awakened_heal": RBMHeroFxTiming.SUPPORT, "awakened_buff": RBMHeroFxTiming.SUPPORT,
}
## 支援（2026-11-17）: 正式モーションには支援の並びが無いので、他の技のコマを1枚借りる（立ち姿 → このコマ → 立ち姿。中割りなし）。
## heal＝腕を組む（blade1）、buff＝力をためる構え（array2）、awakened_heal＝両腕を広げる（release3）、awakened_buff＝爪を掲げる（release4）。
const SUPPORT_POSE := {"heal": "blade1", "buff": "array2", "awakened_heal": "release3", "awakened_buff": "release4"}
## 支援のコマを置く足元（立ち姿と同じ。コマの下辺中央）
const SUPPORT_FOOT := Vector2(390, 238)
## 待機の立ち絵（覚醒前・覚醒後）
const STANCE := {"normal": "normal", "awakened": "omega"}

static var _data := {}
static var _frames := {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPOSURES_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data

## コマの、コマ置き場（cels.png）の中の範囲。
static func rect(cel: String) -> Rect2:
	var r: Array = data().get("rects", {}).get(cel, [0, 0, 1, 1])
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))

## 技の再生の並び。[コマ名, 左上] の配列（30コマ/秒）。
static func frames(scene: String) -> Array:
	if _frames.has(scene):
		return _frames[scene]
	var out: Array = []
	var timing: Dictionary = TIMINGS.get(scene, {})
	if SUPPORT_POSE.has(scene):
		var stance: String = STANCE["awakened" if scene.begins_with("awakened_") else "normal"]
		for i in range(int(ceil(float(timing["duration"]) * FPS)) + 1):
			var t := float(i) / FPS
			var cel: String = SUPPORT_POSE[scene] if t >= float(timing["pose"]) and t < float(timing["back"]) else stance
			var r := rect(cel)
			out.append([cel, SUPPORT_FOOT - Vector2(round(r.size.x * 0.5), r.size.y)])
		_frames[scene] = out
		return out
	for seq: Dictionary in data().get("sequences", []):
		if str(seq.get("id", "")) != str(SEQUENCES.get(scene, "")):
			continue
		out.resize(int(seq["frames"]))
		for e: Dictionary in seq["exposures"]:
			for i in range(int(e["hold_frames"])):
				out[int(e["start_frame"]) + i] = [str(e["cel"]), Vector2(e["world_top_left"][0], e["world_top_left"][1])]
	for sw: Array in timing.get("body_swap", []):
		for i in range(int(sw[1])):
			out[int(sw[0]) + i] = [str(sw[2]), Vector2(sw[3][0], sw[3][1])]
	var hold := int(timing.get("tame_hold", 0))
	if hold > 0 and not out.is_empty():
		var at := int(timing["tame_frame"])
		for i in range(hold):
			out.insert(at, out[at])
	_frames[scene] = out
	return out

## t 秒の時のコマ。
static func at(scene: String, t: float) -> Array:
	var list := frames(scene)
	if list.is_empty():
		return [STANCE["normal"], Vector2(366, 148)]
	return list[clampi(int(floor(t * FPS + 0.0001)), 0, list.size() - 1)]

## 技で使うコマの名前（重なりなし）。
static func cels_of(scene: String) -> Array[String]:
	var out: Array[String] = []
	for row: Array in frames(scene):
		if not out.has(str(row[0])):
			out.append(str(row[0]))
	return out

## コマの足元（左上 + 幅の半分・高さ。論理ドット）。
static func foot_of(cel: String, top_left: Vector2) -> Vector2:
	var r := rect(cel)
	return top_left + Vector2(round(r.size.x * 0.5), r.size.y)
