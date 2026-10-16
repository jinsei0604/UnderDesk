extends RefCounted
## 戦闘テンポ（2026-10-16）: 演出の時刻を、実際の経過時間でどう進めるかの対応表（共通部品）。
## 承認済みの演出（`_advance(t)` のタイムライン・コマの表・音のファイル）はそのままにして、演出の時刻のうち
## 「詰める区間」だけを短い実時間で進める。区間は技ごとに、その演出の専用スクリプトの表で決める。
##
## segments: [[from, to, real], ...] — 演出の時刻 from〜to を、実時間 real 秒で進める（real=0 はその区間を飛ばす）。
##   区間は重ならず、時刻の順に並べる。命中・音の合図より前の区間には、画面も音も止まっていることを確かめた
##   区間だけを入れる（飛ばしても見た目・音が途切れない所）。
## 通しの音を鳴らす演出は on_jump（飛ばした先の演出の時刻を受け取る）で音の再生位置を合わせ直す。速める区間では
## RESYNC_STEP ごとに合わせ直す（音の高さは変えず、演出に遅れないように少しずつ先へ進める）。
## 命中などの判定は「t がその時刻を超えたら」で書かれているので、区間を飛ばしても順番どおりに1回ずつ起きる。

## 実時間での長さ
static func real_length(duration: float, segments: Array) -> float:
	var total := duration
	for seg in segments:
		var a := clampf(float(seg[0]), 0.0, duration)
		var b := clampf(float(seg[1]), a, duration)
		total -= (b - a) - maxf(0.0, float(seg[2]))
	return total

## 実際の経過時間 → 演出の時刻
static func presentation_time(real: float, duration: float, segments: Array) -> float:
	var cursor := 0.0
	var left := maxf(0.0, real)
	for seg in segments:
		var a := clampf(float(seg[0]), cursor, duration)
		var b := clampf(float(seg[1]), a, duration)
		var r := maxf(0.0, float(seg[2]))
		if left <= a - cursor:
			return cursor + left
		left -= a - cursor
		if left < r:
			return a + (b - a) * left / r
		left -= r
		cursor = b
	return minf(cursor + left, duration)

## 速める区間で、通しの音の位置を合わせ直す間隔（実時間の秒）。音は速めない（高さを変えない）ので、この間隔ごとに
## 演出の時刻へ合わせ直して、遅れが溜まらないようにする（2026-10-16: 区間の終わりでだけ合わせると、区間の間に
## 音が最大0.8秒遅れていた）。
const RESYNC_STEP := 0.1

## tween に、演出の時刻 0〜duration を対応表どおりに進める区間を足す（tween_method(advance, 0, duration, duration) の代わり）。
## 区間が無ければ今までと同じ1本の tween_method になる。
static func tween_timeline(tween: Tween, advance: Callable, duration: float, segments: Array, on_jump: Callable = Callable()) -> void:
	var cursor := 0.0
	for seg in segments:
		var a := clampf(float(seg[0]), cursor, duration)
		var b := clampf(float(seg[1]), a, duration)
		var r := maxf(0.0, float(seg[2]))
		if a > cursor:
			tween.tween_method(advance, cursor, a, a - cursor)
		if r > 0.0 and on_jump.is_valid():
			# 通しの音を持つ演出: 速める区間を短く区切り、区切るたびに音の位置を演出の時刻へ合わせ直す
			var steps := maxi(1, ceili(r / RESYNC_STEP))
			for i in steps:
				var from := a + (b - a) * float(i) / steps
				var to := a + (b - a) * float(i + 1) / steps
				tween.tween_method(advance, from, to, r / steps)
				tween.tween_callback(on_jump.bind(to))
		elif r > 0.0:
			tween.tween_method(advance, a, b, r)
		else:
			tween.tween_callback(advance.bind(b))
			if on_jump.is_valid():
				tween.tween_callback(on_jump.bind(b))
		cursor = b
	if duration > cursor or segments.is_empty():
		tween.tween_method(advance, cursor, duration, duration - cursor)

## 通しの音を、演出の時刻を飛ばした先（position 秒）から鳴らし直す。同じ音を飛ばした先から別の再生役で鳴らし始め、
## fade 秒で入れ替える（つなぎ目で音が途切れたり、ぷつっと鳴ったりしないように）。新しい再生役を返す（呼び出し側は
## 以後それを止める・一時停止する）。player が鳴っていなければ何もしない（そのまま返す）。
static func crossfade_jump(player: AudioStreamPlayer, position: float, fade: float = 0.04) -> AudioStreamPlayer:
	if not is_instance_valid(player) or not player.playing or player.stream == null or not player.is_inside_tree():
		return player
	var next := AudioStreamPlayer.new()
	next.stream = player.stream
	next.bus = player.bus
	next.pitch_scale = player.pitch_scale
	var volume := player.volume_db
	next.volume_db = -60.0
	player.get_parent().add_child(next)
	next.play(clampf(position, 0.0, player.stream.get_length()))
	var tween := next.create_tween()
	tween.tween_property(next, "volume_db", volume, fade)
	var old := player
	var out := old.create_tween()
	out.tween_property(old, "volume_db", -60.0, fade)
	out.tween_callback(old.queue_free)
	return next

## 演出の時刻 t に、実際の経過時間で何秒後に着くか（presentation_time の逆。飛ばす区間の中の時刻は、その区間の始まりに着く）。
static func real_time_at(t: float, duration: float, segments: Array) -> float:
	var cursor := 0.0
	var real := 0.0
	var target := clampf(t, 0.0, duration)
	for seg in segments:
		var a := clampf(float(seg[0]), cursor, duration)
		var b := clampf(float(seg[1]), a, duration)
		var r := maxf(0.0, float(seg[2]))
		if target <= a:
			return real + (target - cursor)
		real += a - cursor
		if target < b:
			return real + (r * (target - a) / (b - a) if b > a else 0.0)
		real += r
		cursor = b
	return real + (target - cursor)
