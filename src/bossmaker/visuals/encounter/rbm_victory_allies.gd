extends RefCounted
## 味方の勝利の動き（案B。表示専用）。絵は本番の12ポーズ（b:N）と、Codex の完成済みの中割りのコマ（s:N）だけを使い、
## コマの切り替え（決めた時刻の表）と、2px単位の小さな跳ねだけで動かす（伸縮・回転はしない）。
## 戦闘不能の味方は動かさない（倒れたまま）。一人ずつ少しずらして、その人らしい動きをする。時間は t0 からの相対。
##   勇者=剣を振り上げて高く掲げ、刃が光る → 胸の前に立てる
##   老執事=懐中時計を確かめ（カチ）→ 身を乗り出して時計を差し出す → 胸の前で手を整える → 両手を広げる
##   少女=杖を掲げて2回跳ねる（宝石がきらめく）→ 目を閉じて杖を抱え、ほっとする
##   侍=刀を掲げて光らせる → 刀先を鞘口へ（ここから刀身が鞘を滑る音）→ 納め切る（鍔が鞘口に当たる「カチッ」）
##   ハンマー使い=頭上に振り上げ → 地面へ打ち下ろす（土煙）→ 柄頭に両手を置いて胸を張る → 前を指さす
const AF = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_ally_frames.gd")

var p   # victory_player.gd
var t0 := 1.0
var keys: Array = []
var frames := {}     # key -> 今のコマ
var offsets := {}    # key -> 足元からのずれ
var _fired := {}
var _glints: Array = []
var _done := false

## [t0からの時刻, コマ, 出来事]
const SEQ := {
	"hero": [[0.0, "s:9", ""], [0.10, "s:6", "swish"], [0.22, "s:14", "glint"], [1.75, "s:12", ""], [2.45, "s:15", ""]],
	"butler": [[0.0, "s:15", "tick"], [0.72, "s:13", ""], [1.35, "s:12", ""], [2.05, "s:10", "sparkle"]],
	"healer": [[0.0, "s:9", "hop"], [0.36, "s:10", "hop"], [0.80, "s:8", "sparkle"], [1.75, "s:5", ""]],
	"samurai": [[0.0, "s:19", "glint"], [0.42, "s:16", "sheathe"], [0.64, "s:17", ""], [0.86, "s:18", "click"]],
	"tank": [[0.0, "s:8", ""], [0.16, "s:9", ""], [0.36, "s:11", "thud"], [0.92, "s:19", ""], [1.95, "s:18", ""]],
}
const ORDER := ["tank", "hero", "healer", "butler", "samurai"]
const LENGTH := 3.25

func setup() -> void:
	for key in p.stage.get("_party_keys"):
		keys.append(str(key))
	var assets: Array = []
	for key in keys:
		assets.append(asset(key))
	AF.hold(assets)
	p.ally_layer.draw_fn = _draw

func asset(key: String) -> String:
	return str(p.stage.get("_asset_ids")[key])

func downed(key: String) -> bool:
	return bool(p.stage.call("_unit_state", key).get("is_downed", false))

func foot(key: String) -> Vector2:
	return p.stage.call("_foot", key)

func advance(t: float, dt: float) -> void:
	for key in keys:
		if downed(key):
			continue
		var a := asset(key)
		# 中割りのコマの1枚絵を読めていない味方は、本番の見た目のまま動かさない（再生中に読まない）
		if AF.sheet(a) == null:
			continue
		var lt := t - t0 - ORDER.find(a) * 0.17
		var fr := _seq_frame(SEQ.get(a, []), lt, key)
		var off := Vector2.ZERO
		if a == "healer":
			off.y = -_hop(lt, 0.30, 12.0) - _hop(lt - 0.36, 0.30, 10.0)
		if fr.is_empty():
			if frames.has(key):
				_show_real(key, true)
				frames.erase(key)
			continue
		frames[key] = fr
		offsets[key] = off.snapped(Vector2(2, 2))
		_show_real(key, false)
	for g in _glints:
		g.age += dt
	_glints = _glints.filter(func(g): return g.age < 0.32)

func _seq_frame(seq: Array, lt: float, key: String) -> String:
	var fr := ""
	for i in range(seq.size()):
		var row: Array = seq[i]
		if lt >= float(row[0]):
			fr = row[1]
			var ev: String = row[2]
			if not ev.is_empty():
				var id := "%s:%d" % [key, i]
				if not _fired.has(id):
					_fired[id] = true
					_event(key, ev, fr)
	return fr

func _event(key: String, ev: String, fr: String) -> void:
	var a := asset(key)
	var tip := AF.tip(a, fr, foot(key))
	match ev:
		"glint":
			_glints.append({"at": tip, "age": 0.0})
			p.fx.stars(tip, 5, Color(1, 0.98, 0.9), 8.0)
			p.sfx.play("enc:sparkle", -6.0)
		"sparkle":
			p.fx.stars(tip, 7, Color(1, 0.95, 0.75), 12.0)
			p.sfx.play("enc:sparkle", -8.0, 0.0, -1.0, 1.15)
		"tick":
			p.sfx.play("enc:watch_tick", -6.0)
			_glints.append({"at": tip, "age": 0.0})
		"sheathe":
			# 刀身が鞘を滑る音から始まり、0.44秒後（納め切るコマ s:18 の時刻）に鍔の「カチッ」が鳴る1つの音
			# ファンファーレと重なるので、ほかの味方の音より大きめに鳴らす（-3dB では埋もれて聞こえなかった）
			p.sfx.play("enc:sheathe", 2.0)
		"click":
			_glints.append({"at": foot(key) + Vector2(-4, -44), "age": 0.0})
		"swish":
			p.sfx.play("game:wind_swing", -10.0)
		"hop":
			p.fx.stars(tip, 4, Color(0.85, 0.75, 1.0), 8.0)
		"thud":
			p.camera.shake(2, 0.18)
			p.fx_back.puff(foot(key) + Vector2(26, 0), 8, 30, Color(0.6, 0.58, 0.6, 0.85), 0.8)
			p.sfx.play("enc:hammer_thud", -6.0)

static func _hop(x: float, length: float, h: float) -> float:
	if x < 0.0 or x > length:
		return 0.0
	return h * sin(PI * pow(x / length, 0.8))

func _show_real(key: String, show: bool) -> void:
	var v: Control = p.stage.get("_visuals")[key]
	v.visible = show

func finish_now() -> void:
	_done = true

func restore() -> void:
	for key in keys:
		_show_real(key, true)

func _draw(ci: CanvasItem) -> void:
	for key in frames:
		AF.draw(ci, asset(key), frames[key], foot(key) + Vector2(offsets.get(key, Vector2.ZERO)))

func draw_top(ci: CanvasItem) -> void:
	for g in _glints:
		var k: float = 1.0 - float(g.age) / 0.32
		var c: Vector2 = (g.at as Vector2).round()
		var ln := roundf(4.0 + 12.0 * k)
		ci.draw_rect(Rect2(c + Vector2(-ln, -1), Vector2(ln * 2, 2)), Color(1, 1, 0.95, 0.8 * k))
		ci.draw_rect(Rect2(c + Vector2(-1, -ln), Vector2(2, ln * 2)), Color(1, 1, 0.95, 0.8 * k))
		ci.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 1, k))
