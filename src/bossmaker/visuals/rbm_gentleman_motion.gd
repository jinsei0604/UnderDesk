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

## 2026-11-20 ユーザー「動きを繋げるようにしてて違和感がすごい。新ボスと同じく要所の絵を切り替える方式に」:
## 16コマの中割りは描かず、中割りの番号を要所の絵（各列の [から, まで, 絵]）に読み替え、その絵のまま止める。
## 切り替わる時刻は今の通しの音と同じ（中割りがその範囲に入った時刻）。昔の1枚絵（legacy_*）はそのまま。
const KEYS := {
	"hat_reach": [[0, 7, "hat_reach_00"], [8, 15, "hat_reach_15"]],
	"normal_draw_fire": [[0, 3, "hat_reach_00"], [4, 6, "normal_draw_fire_05"], [7, 9, "normal_draw_fire_15"], [10, 11, "normal_draw_fire_11"], [12, 15, "normal_draw_fire_15"]],
	"bow_down": [[0, 2, "hat_reach_15"], [3, 6, "bow_down_04"], [7, 11, "bow_down_08"], [12, 15, "bow_down_15"]],
	"bow_up": [[0, 4, "bow_down_08"], [5, 9, "bow_up_08"], [10, 14, "hat_reach_15"], [15, 15, "hat_reach_00"]],
	"dual_open_raise": [[0, 3, "dual_open_raise_00"], [4, 10, "dual_open_raise_07"], [11, 15, "dual_open_raise_15"]],
	"dual_open_fire": [[0, 1, "dual_open_fire_00"], [2, 4, "dual_open_fire_03"], [5, 7, "dual_open_fire_07"], [8, 9, "dual_open_fire_09"], [10, 15, "dual_open_fire_15"]],
	"dual_forward_raise": [[0, 4, "dual_forward_raise_00"], [5, 11, "dual_forward_raise_08"], [12, 15, "dual_forward_raise_15"]],
	"dual_forward_fire": [[0, 1, "dual_forward_fire_00"], [2, 4, "dual_forward_fire_03"], [5, 15, "dual_forward_fire_15"]],
}
## 技ごとに絵を差し替える区間 [から, まで, 絵]。2026-11-20 ユーザー「全体攻撃の最後、上に撃たずにパーティーの方へ」→ 全体の最後の一発は
## 構えた絵（水平の銃）のまま四人の方へ撃つので、差し替えは無し（真上へ撃つ legacy_signal はやめた）。
const OVERRIDES := {}
## 銃口（足元からの相対、絵の画素）と銃身の向き [x, y, 向きx, 向きy]。弾は銃身の向きに飛ぶ（2026-11-20 ユーザー「銃弾の角度がおかしい」）。
## near＝片手撃ちの銃・二丁を開いた左の銃・前に二丁の下の銃、far＝二丁を開いた右の銃・前に二丁の上の銃。
const GUNS := {
	"normal_draw_fire_15": {"near": [-49.0, -64.5, -1.0, 0.0]},
	"normal_draw_fire_11": {"near": [-41.0, -83.0, -0.6, -0.8]},
	"legacy_signal": {"near": [-14.0, -97.0, 0.0, -1.0]},
	"dual_open_raise_15": {"near": [-45.0, -86.0, -0.97, -0.24], "far": [44.0, -79.0, 1.0, 0.0]},
	"dual_open_fire_00": {"near": [-43.0, -78.0, -1.0, 0.0], "far": [42.0, -78.0, 1.0, 0.0]},
	"dual_open_fire_03": {"near": [-43.0, -77.0, -1.0, 0.0], "far": [40.0, -91.0, 0.5, -0.87]},
	"dual_open_fire_07": {"near": [-43.0, -77.0, -1.0, 0.0], "far": [42.0, -77.0, 1.0, 0.0]},
	"dual_open_fire_09": {"near": [-38.0, -88.0, -0.5, -0.87], "far": [42.0, -77.0, 1.0, 0.0]},
	"dual_open_fire_15": {"near": [-44.0, -79.0, -1.0, 0.0], "far": [43.0, -79.0, 1.0, 0.0]},
	"dual_forward_raise_15": {"near": [-34.0, -62.0, -1.0, 0.0], "far": [-54.0, -78.0, -1.0, 0.0]},
	"dual_forward_fire_00": {"near": [-33.0, -57.5, -1.0, 0.0], "far": [-47.0, -77.0, -1.0, 0.0]},
	"dual_forward_fire_03": {"near": [-33.0, -57.5, -1.0, 0.0], "far": [-30.0, -92.0, -0.5, -0.87]},
	"dual_forward_fire_15": {"near": [-32.0, -57.5, -1.0, 0.0], "far": [-46.0, -76.0, -1.0, 0.0]},
}
## 構えた姿の銃口の高さ（片手撃ち。足元から）。影・本体をこの高さで相手に合わせる。
const AIM_POSE := "normal_draw_fire_15"
const RECOIL_POSE := "normal_draw_fire_11"

static func key_pose(name: String) -> String:
	var cut := name.rfind("_")
	if cut < 0 or not KEYS.has(name.substr(0, cut)): return name
	var index := int(name.substr(cut + 1))
	for r in KEYS[name.substr(0, cut)]:
		if index >= int(r[0]) and index <= int(r[1]): return str(r[2])
	return name

static func frame(kind: String, t: float) -> String:
	for r in OVERRIDES.get(kind, []):
		if t >= float(r[0]) and t < float(r[1]): return str(r[2])
	var data := clip(kind)
	return key_pose(str(data.frames[frame_index(data,t)]))

static func texture(name: String) -> Texture2D:
	if not _textures.has(name): _textures[name] = load(ROOT+"motion_frames/"+name+".png")
	return _textures[name] as Texture2D

## 絵の銃口と向き（足元からの相対）。その絵に銃が無ければ空。flip は左右反転した絵（右を向く影）。
static func gun(pose: String, hand: String, flip: bool = false) -> Dictionary:
	var g: Dictionary = GUNS.get(pose, {})
	if not g.has(hand): hand = "near" if g.has("near") else "far"
	if not g.has(hand): return {}
	var v: Array = g[hand]
	var s := -1.0 if flip else 1.0
	return {"p": Vector2(float(v[0]) * s, float(v[1])), "d": Vector2(float(v[2]) * s, float(v[3])).normalized()}

static func muzzle(kind: String, t: float, hand: String) -> Vector2:
	var g := gun(frame(kind, t), hand)
	if not g.is_empty(): return g.p
	var data := clip(kind)
	if data.has("muzzles"):
		var points: Dictionary = data.muzzles[frame_index(data,t)]
		if points.has(hand): return Vector2(float(points[hand][0]),float(points[hand][1]))
	return Vector2(-49,-64.5) if kind=="single" else Vector2(-34,-59)

## 影の撃つ相手（2026-11-20）: 影はそれぞれ1人の相手の横に、その相手の高さで並んで水平に撃つので、影ごとに相手を固定する。
static func shadow_target(e: Dictionary, count: int) -> int:
	return posmod(int(e.shooter), maxi(1, count))
