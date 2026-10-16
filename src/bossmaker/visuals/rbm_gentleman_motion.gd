extends RefCounted
## Approved v8 full-body drawings and timestamps. Never uses combat state or RNG.
const ROOT := "res://assets_bossmaker/battle/gentleman/"
const MOTION_PATH := ROOT + "motion.json"
static var _data: Dictionary = {}

## 戦闘テンポ（2026-10-16）: 演出の時刻のうち詰める区間（rbm_tempo_map.gd、[から, まで, 実時間]）。承認済みのコマ・音はそのまま。
## 一覧画像（0.1秒ごと）と音の推移で、画面も音も止まっていることを確かめた区間だけ。命中の直後0.65秒（揺れ）と、
## 最後の0.5秒（かばう味方が元の位置へ戻る）は詰めない。
##   単体: 構えたまま止まる所（撃鉄の音 1.3秒の余韻が消えた後）と、煙が消えた後の立ち姿（4.5〜5.5）
##   全体: 杭の煙が消えた後の立ち姿 / 覚醒後の単体: 命中の煙が消えた後の立ち姿（約2.8秒）
##   覚醒後の全体: 最初の立ち姿・煙が消えた後（暗いお辞儀のまま止まる所は、脈打つ音のつなぎ目がずれるので詰めない）
##   強化・回復: 構えのまま光が育つ間（音は無音）を2倍の速さで
const TEMPO := {
	"single": [[1.50, 1.90, 0.0], [4.50, 5.50, 0.0]],
	"all": [[7.70, 8.25, 0.0]],
	"awakened_single": [[4.60, 7.40, 0.0]],
	"awakened_all": [[0.10, 0.60, 0.0], [12.60, 13.00, 0.0]],
	"heal": [[1.00, 2.40, 0.70]],
	"buff": [[1.00, 2.40, 0.70]],
}

static func tempo(kind: String) -> Array:
	return TEMPO.get(kind, [])
static var _textures: Dictionary = {}

static func clip(kind: String) -> Dictionary:
	if _data.is_empty():
		# JSON のリソースとして読む(戦闘の開始時に rbm_presentation_warmup.gd が裏で読んでいれば、すぐに返る)。
		var json := load(MOTION_PATH) as JSON
		_data = json.data if json != null and json.data is Dictionary else JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH))
	return _data["clips"][kind]

static func frame_index(data: Dictionary, t: float) -> int:
	return clampi(int(t*60.0),0,data.frames.size()-1)

static func frame(kind: String, t: float) -> String:
	var data := clip(kind)
	return str(data.frames[frame_index(data,t)])

static func texture(name: String) -> Texture2D:
	if not _textures.has(name): _textures[name] = load(ROOT+"motion_frames/"+name+".png")
	return _textures[name] as Texture2D

static func muzzle(kind: String, t: float, hand: String) -> Vector2:
	var data := clip(kind)
	if data.has("muzzles"):
		var points: Dictionary = data.muzzles[frame_index(data,t)]
		if points.has(hand): return Vector2(float(points[hand][0]),float(points[hand][1]))
	return Vector2(-44,-72) if kind=="single" else Vector2(-34,-59)
