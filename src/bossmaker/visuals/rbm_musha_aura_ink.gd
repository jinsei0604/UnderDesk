extends RefCounted
## 朽ちた機械武者の覚醒後の常時オーラ(rbm_musha_aura.gd)の墨の描画部品。表示専用の
## 静的な関数だけで、状態を持たない。すべて整数座標・アンチエイリアス無しで、他のVFXと
## 同じドット絵の質感にそろえる。
##
## - brush : 毛筆の墨帯(根元は太く濃く、先端は掠れて消える)。画面端から入る墨に使う。
## - slash : ごく低頻度の斬痕(黒中心・縁にわずかな暗赤。白い線は使わない)。
## - trace : 石畳の溝に沿って伸びて消える細い墨筆。
## - groove_paths : 背景画像の暗い溝を辿って、上の墨筆の通り道を求める(起動時に一度だけ)。
const Timeline = preload("res://src/bossmaker/visuals/rbm_musha_aura_timeline.gd")

const INK := Color(0.012, 0.011, 0.02)
const SEG := 26
const BRISTLES := 9

## 毛筆の墨帯。head/tail は 0〜1(どこまで伸びたか/根元がどこまで薄れたか)、alpha は全体の濃さ。
## 太い数本の筆(ブリスル)線を平行に引き、先端ほど途切れさせて掠れを出す。
static func brush(n: CanvasItem, base: Vector2, theta: float, bend: float, length_full: float, width_full: float, seed_a: float, head: float, tail: float, alpha: float) -> void:
	if head <= 0.03 or alpha <= 0.01:
		return
	var length := length_full * head
	var dir0 := Vector2(sin(theta), -cos(theta))
	var nrm0 := Vector2(cos(theta), sin(theta))
	var r0 := tail / head
	var pts: Array = []
	var widths: Array = []
	for i in range(SEG + 1):
		var r := float(i) / SEG
		pts.append(base + dir0 * length * r + nrm0 * (bend * length * r * r * 0.5))
		var w := width_full * (0.60 + 0.40 * smoothstep(0.0, 0.10, r)) * (1.0 - 0.50 * pow(r, 1.5))
		if r0 > 0.0:
			w *= clampf((r - r0) / 0.14, 0.0, 1.0)
		widths.append(w)
	var col := Color(INK.r, INK.g, INK.b, 0.93 * alpha)
	for j in range(BRISTLES):
		var cj := float(j) / (BRISTLES - 1) - 0.5
		var end_r := 1.0 - 0.58 * pow(Timeline.hash01(seed_a, j * 3.1), 1.1) - 0.10 * absf(cj) * 2.0
		for i in range(SEG):
			var r := float(i) / SEG
			if r < r0 or r > end_r:
				continue
			var dry := 0.02 + 0.85 * smoothstep(0.22, 1.0, r)
			if Timeline.hash01(seed_a + j * 7.7, floorf(i * 0.5) * 1.3) < dry:
				continue
			var a_pt: Vector2 = pts[i]
			var b_pt: Vector2 = pts[i + 1]
			var tan_v := (b_pt - a_pt).normalized()
			var nrm := Vector2(-tan_v.y, tan_v.x)
			var wa: float = widths[i]
			var wb: float = widths[i + 1]
			var lw := maxf(1.0, roundf(maxf(wa, wb) / (BRISTLES - 1) * 1.3))
			n.draw_line((a_pt + nrm * cj * wa).round(), (b_pt + nrm * cj * wb).round(), col, lw, false)

## 斬痕。local は出てからの秒(0〜Timeline.SLASH_SPAN)、gate は全体の強さ(0〜1)。
static func slash(n: CanvasItem, center: Vector2, shape: Dictionary, local: float, gate: float) -> void:
	if local < 0.0 or local > Timeline.SLASH_SPAN or gate <= 0.01:
		return
	var a: float = shape.angle
	var dir := Vector2(sin(a), -cos(a))
	var nrm := Vector2(-dir.y, dir.x)
	var open := smoothstep(0.0, 0.04, local)
	var fade := (1.0 - smoothstep(0.16, Timeline.SLASH_SPAN, local)) * gate
	var half := float(shape.length) * 0.5 * open
	var w := float(shape.width) * fade
	var p0 := center - dir * half
	var p1 := center + dir * half
	var edge := Color(.46, .05, .07, .50 * fade)
	n.draw_line((p0 + nrm * (w + 1.0)).round(), (p1 + nrm * (w + 1.0)).round(), edge, 1.0, false)
	n.draw_line((p0 - nrm * (w + 1.0)).round(), (p1 - nrm * (w + 1.0)).round(), edge, 1.0, false)
	var poly := PackedVector2Array([p0.round(), (center + nrm * w).round(), p1.round(), (center - nrm * w).round()])
	if Geometry2D.triangulate_polygon(poly).size() > 0:
		n.draw_colored_polygon(poly, Color(.003, .003, .006, .97 * fade))

## 溝に沿う墨筆。trace は Timeline.active_traces() の1要素、path は溝の点列。
static func trace(n: CanvasItem, path: PackedVector2Array, info: Dictionary, power: float, jolt: float) -> void:
	var local: float = info.local
	var life: float = info.life
	var count := path.size() - 1
	if count < 2 or power <= 0.0:
		return
	var head := 1.0 - pow(1.0 - clampf(local / 1.9, 0.0, 1.0), 2.0)
	var tail := smoothstep(life * 0.45, life * 0.95, local) * 0.9
	var alpha := power * (1.0 - smoothstep(life * 0.72, life, local))
	if alpha <= 0.01:
		return
	var i0 := int(floor(tail * count))
	var i1 := int(floor(head * count))
	var seed_a: float = info.seed
	var wbase: float = float(info.width) * (1.0 + 0.25 * jolt)
	for i in range(i0, i1):
		var f := float(i) / count
		# 先端ほど細く、掠れて途切れる。
		var fr := float(i - i0) / maxf(float(i1 - i0), 1.0)
		if Timeline.hash01(seed_a, floorf(i * 0.5)) < 0.50 * pow(fr, 1.4):
			continue
		var w := maxf(1.0, roundf(wbase * (1.0 - 0.75 * f) * (0.55 + 0.45 * (1.0 - fr))))
		n.draw_line(path[i], path[i + 1], Color(INK.r, INK.g, INK.b, 0.30 * alpha), w + 2.0, false)
		n.draw_line(path[i], path[i + 1], Color(INK.r, INK.g, INK.b, 0.88 * alpha), w, false)

## 石畳の溝を辿る点列。luminance は「ローカル座標 → 明るさ(0〜1)」。foot はボスの足元。
## 暗い溝へ向かって2.5pxずつ進み、進行方向から大きく外れず(±0.95rad)、地面の外へ出ない。
## 溝のガタつきは均して、なめらかな筆の線にする。
static func groove_paths(luminance: Callable, foot: Vector2, ground_bottom: float) -> Array:
	var out: Array = []
	for k in range(Timeline.TRACE_POOL):
		out.append(_trace_groove(luminance, foot, k, ground_bottom))
	return out

static func _trace_groove(luminance: Callable, foot: Vector2, k: int, ground_bottom: float) -> PackedVector2Array:
	var side := -1.0 if k % 2 == 0 else 1.0
	var start := Vector2(foot.x + side * (34.0 + Timeline.hash01(k, 1.0) * 80.0), foot.y + 2.0 + Timeline.hash01(k, 2.0) * 12.0)
	var best_y := start.y
	var best_l := 9.0
	for dy in range(-8, 9):
		var l: float = luminance.call(start + Vector2(0, dy))
		if l < best_l:
			best_l = l
			best_y = start.y + dy
	start.y = best_y
	var ang0 := (0.0 if side > 0.0 else PI) + (Timeline.hash01(k, 3.0) - 0.5) * 0.5
	var p := start
	var ang := ang0
	var raw := PackedVector2Array([start])
	for i in range(64):
		var best_a := ang
		var best_s := 9.0
		for da in [-0.7, -0.35, 0.0, 0.35, 0.7]:
			var a: float = ang + da
			if absf(a - ang0) > 0.95:
				continue
			var q := p + Vector2(cos(a), sin(a)) * 2.5
			if q.y < foot.y - 8.0 or q.y > ground_bottom:
				continue
			var sc: float = float(luminance.call(q)) + 0.006 * absf(da)
			if sc < best_s:
				best_s = sc
				best_a = a
		ang = lerpf(ang, best_a, 0.75)
		p += Vector2(cos(ang), sin(ang)) * 2.5
		raw.append(p)
	var pts := PackedVector2Array()
	for i in range(raw.size()):
		var acc := Vector2.ZERO
		var cnt := 0
		for j in range(maxi(0, i - 4), mini(raw.size(), i + 5)):
			acc += raw[j]
			cnt += 1
		pts.append((acc / cnt).round())
	return pts
