extends RefCounted

## ボス戦作成トップの2枚のカードの絵（2026-10、ユーザーが4案から選んだもの。画像は使わず図形だけで描く）。
##   NewBattleArt     = 「新しいボス戦を作る」: ドット絵の白紙の書類と「＋」の札、ゆっくり明滅するきらめき（案1）。
##   SavedBattlesArt  = 「保存したボス戦を編集」: ホログラムの線画の重なったデータのカード、点滅するカーソルと走査線（案2）。
## glow（0〜1）はカードが選ばれている度合い。選ばれるほど明るくなる。表示されている間だけ動く。

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")

## 表示されている間だけ _process を回す（画面を離れたら止める）。
class AnimatedArt:
	extends Control
	var glow := 0.0
	var time := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(is_visible_in_tree())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED:
			set_process(is_visible_in_tree())

	func set_glow(value: float) -> void:
		if is_equal_approx(value, glow):
			return
		glow = value
		_glow_changed()

	func _glow_changed() -> void:
		queue_redraw()

	func _process(delta: float) -> void:
		time += delta
		_tick()

	func _tick() -> void:
		queue_redraw()

## 案1: 36×36ドット（1ドット5px）。書類の形は最初に1回だけ組み、色だけを glow で変える。
## 書類は glow が変わった時だけ描き直し、毎フレーム描き直すのは子のきらめきだけ。
class NewBattleArt:
	extends AnimatedArt
	const N := 36
	const CELL := 5.0
	const COLORS := {
		"outline": [Color("05080c"), Color("05080c")],
		"page": [Color("10232a"), Color("12333c")],
		"edge": [Color("4a6a74"), Color("43efff")],
		"fold": [Color("1d3d46"), Color("24525c")],
		"fold_edge": [Color("6a8f99"), Color("8fe3ef")],
		"dash": [Color("2a4a54"), Color("2f8ea0")],
		"badge": [Color("2a7f90"), Color("43efff")],
		"badge_edge": [Color("1d5a66"), Color("2fb8c8")],
		"mark": [Color("eef5f6"), Color("06262c")],
	}
	## きらめき: [位置, 腕の長さ, 明滅の位相]
	const SPARKLES := [[Vector2i(31, 6), 2, 0.0], [Vector2i(3, 21), 1, 1.7], [Vector2i(33, 18), 1, 3.1]]
	var roles: PackedStringArray = []
	var _sparkles: Control

	func _ready() -> void:
		_build()
		_sparkles = Control.new()
		_sparkles.name = "Sparkles"
		_sparkles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sparkles.draw.connect(_draw_sparkles)
		add_child(_sparkles)
		_sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)
		super._ready()

	func _tick() -> void:
		_sparkles.queue_redraw()

	func _put(x: int, y: int, role: String) -> void:
		if x >= 0 and y >= 0 and x < N and y < N:
			roles[y * N + x] = role

	func _role(x: int, y: int) -> String:
		if x < 0 or y < 0 or x >= N or y >= N:
			return ""
		return roles[y * N + x]

	func _build() -> void:
		roles.resize(N * N)
		roles.fill("")
		# 書類（右上の角が折れている）
		for y in range(4, 32):
			for x in range(7, 27):
				if x >= 21 and y <= 9:
					var fx := x - 21
					var fy := y - 4
					if fx > fy:
						continue
					_put(x, y, "fold_edge" if fx == fy else "fold")
				else:
					_put(x, y, "page")
		var edges: Array[Vector2i] = []
		for y in N:
			for x in N:
				if _role(x, y) == "page" and _touches_empty(x, y):
					edges.append(Vector2i(x, y))
		for e in edges:
			_put(e.x, e.y, "edge")
		# まだ何も書かれていない行（点線）
		for row in [[10, 10, 17], [14, 10, 23], [18, 10, 23], [22, 10, 19]]:
			for x in range(row[1], row[2] + 1):
				if (x - row[1]) % 3 != 2:
					_put(x, row[0], "dash")
		# 右下の「＋」の札
		for y in N:
			for x in N:
				var d := Vector2(x, y).distance_to(Vector2(26, 27))
				if d <= 6.3:
					_put(x, y, "badge_edge" if d > 5.2 else "badge")
		for k in range(-3, 4):
			_put(26 + k, 27, "mark")
			_put(26, 27 + k, "mark")
		# 外側の輪郭
		var outline: Array[Vector2i] = []
		for y in N:
			for x in N:
				if _role(x, y) == "" and _touches_filled(x, y):
					outline.append(Vector2i(x, y))
		for o in outline:
			_put(o.x, o.y, "outline")

	func _touches_empty(x: int, y: int) -> bool:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _role(x + o.x, y + o.y) == "":
				return true
		return false

	func _touches_filled(x: int, y: int) -> bool:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _role(x + o.x, y + o.y) != "":
				return true
		return false

	func _origin() -> Vector2:
		return ((size - Vector2(N, N) * CELL) / 2.0).round()

	func _draw() -> void:
		var origin := _origin()
		var palette := {}
		for key in COLORS:
			palette[key] = (COLORS[key][0] as Color).lerp(COLORS[key][1], glow)
		for y in N:
			for x in N:
				var role: String = roles[y * N + x]
				if role.is_empty():
					continue
				draw_rect(Rect2(origin + Vector2(x, y) * CELL, Vector2(CELL, CELL)), palette[role])

	func _draw_sparkles() -> void:
		var origin := _origin()
		for s in SPARKLES:
			var c: Vector2i = s[0]
			var arm: int = s[1]
			var a: float = (0.25 + 0.75 * (0.5 + 0.5 * sin(time * 3.0 + float(s[2])))) * (0.5 + 0.5 * glow)
			var color := Color(S.TEXT, a)
			_sparkles.draw_rect(Rect2(origin + Vector2(c) * CELL, Vector2(CELL, CELL)), color)
			for k in range(1, arm + 1):
				for o in [Vector2i(k, 0), Vector2i(-k, 0), Vector2i(0, k), Vector2i(0, -k)]:
					_sparkles.draw_rect(Rect2(origin + Vector2(c + o) * CELL, Vector2(CELL, CELL)), Color(color, a * (0.7 if k == 1 else 0.4)))

## 案2: 斜めに傾いた3枚のデータのカード（奥の2枚は薄く）。一番手前のカードの2行目に点滅するカーソル、
## 上から下へ走査線。全体がゆっくり上下に浮く。線は3回重ねて描き、ぼんやり光らせる。
class SavedBattlesArt:
	extends AnimatedArt
	const CARD_W := 210.0
	const CARD_H := 112.0
	const SKEW := 28.0
	const ROW_LENGTHS := [0.55, 0.8, 0.65, 0.4]

	func _ready() -> void:
		clip_contents = true
		super._ready()

	func _c(a: float) -> Color:
		return Color(S.ACCENT, clampf(a, 0.0, 1.0))

	func _glow_line(a: Vector2, b: Vector2, alpha: float, width: float) -> void:
		draw_line(a, b, _c(alpha * 0.15), width + 6.0, true)
		draw_line(a, b, _c(alpha * 0.35), width + 2.5, true)
		draw_line(a, b, _c(alpha), width, true)

	func _glow_polyline(points: PackedVector2Array, alpha: float, width: float) -> void:
		draw_polyline(points, _c(alpha * 0.15), width + 6.0, true)
		draw_polyline(points, _c(alpha * 0.35), width + 2.5, true)
		draw_polyline(points, _c(alpha), width, true)

	## カードの中の位置(u, v)を、傾けた画面上の位置にする。
	func _skewed(origin: Vector2, u: float, v: float) -> Vector2:
		return origin + Vector2(u + (CARD_H - v) / CARD_H * SKEW, v)

	func _draw() -> void:
		var k := 0.5 + 0.5 * glow
		var cx := size.x / 2.0
		var cy := size.y / 2.0 + 4.0 + sin(time * 1.5) * 3.0
		for i in range(2, -1, -1):
			var origin := Vector2(cx - CARD_W / 2.0 - SKEW / 2.0 - i * 20.0, cy - CARD_H / 2.0 + i * 15.0)
			_card(origin, (0.95 if i == 0 else 0.4 - i * 0.1) * k, i == 0)

	func _card(o: Vector2, alpha: float, front: bool) -> void:
		var points := PackedVector2Array([_skewed(o, 0, 0), _skewed(o, CARD_W, 0), _skewed(o, CARD_W, CARD_H), _skewed(o, 0, CARD_H), _skewed(o, 0, 0)])
		var face := points.slice(0, 4)
		draw_colored_polygon(face, Color(0.03, 0.08, 0.1, 0.92))
		draw_colored_polygon(face, _c(0.05 * alpha))
		_glow_polyline(points, alpha, 1.5)
		if not front:
			return
		for r in ROW_LENGTHS.size():
			var y := 24.0 + r * 21.0
			var end: float = 18.0 + float(ROW_LENGTHS[r]) * (CARD_W - 40.0)
			if r == 1:
				draw_colored_polygon(PackedVector2Array([_skewed(o, 12, y - 8), _skewed(o, CARD_W - 12, y - 8), _skewed(o, CARD_W - 12, y + 8), _skewed(o, 12, y + 8)]), _c(0.14 * alpha))
				_glow_line(_skewed(o, 18, y), _skewed(o, end, y), alpha, 2.0)
				if fmod(time, 1.0) < 0.6:
					_glow_line(_skewed(o, end + 7, y - 7), _skewed(o, end + 7, y + 7), alpha, 2.0)
			else:
				draw_line(_skewed(o, 18, y), _skewed(o, end, y), _c(0.45 * alpha), 2.0, true)
		var scan := fmod(time * 45.0, CARD_H)
		draw_line(_skewed(o, 0, scan), _skewed(o, CARD_W, scan), _c(0.18 * alpha), 1.0, true)
