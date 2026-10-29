extends RefCounted
## 勝利の文字（案B。表示専用）＋撃破ターンとクリアタイム。画面の層に描く（戦場のカメラでは拡大されない）。
## 「VICTORY!」が1字ずつ上から落ちて弾む → 「〇〇を倒した！」 → 下地付きの小さな札に「撃破ターン N ｜ クリアタイム m:ss」。
## 色はメニューと同じ紺＋水色。
## 耐久勝利（p.survival、2026-10-29）: 「耐久成功！」（英語は SURVIVED!）→「〇〇の猛攻を耐え抜いた！」→「クリアターン N ｜ クリアタイム」。
## 必要だったターン数は書かない（勝利条件が非公開のボスでも明かさない）。
const S = preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const LATIN := preload("res://assets_bossmaker/fonts/Oxanium-SemiBold.ttf")

var p
var t := 0.0
var out := 0.0

func advance(age: float) -> void:
	t = age

func fade_out(k: float) -> void:
	out = k

static func time_text(seconds: float) -> String:
	var s := int(round(seconds))
	return "%d:%02d" % [s / 60, s % 60]

func draw(ci: CanvasItem) -> void:
	if p.allies == null:
		return
	var lt: float = t - float(p.allies.t0)
	var a := 1.0 - out
	if a <= 0.0 or lt < 0.0:
		return
	# 文字の後ろの暗い帯（明るい背景でも読めるように。上下の縁は段にして柔らかく消す）
	var band_k := clampf((lt - 0.10) / 0.2, 0.0, 1.0) * a
	if band_k > 0.0:
		var top := 138.0
		var h := 156.0
		ci.draw_rect(Rect2(0, top, 1280, h), Color(0.02, 0.04, 0.07, 0.55 * band_k))
		for i in range(4):
			var e := 6.0 * (i + 1)
			ci.draw_rect(Rect2(0, top - e, 1280, 6), Color(0.02, 0.04, 0.07, 0.55 * band_k * (1.0 - (i + 1) / 5.0)))
			ci.draw_rect(Rect2(0, top + h + e - 6, 1280, 6), Color(0.02, 0.04, 0.07, 0.55 * band_k * (1.0 - (i + 1) / 5.0)))
	var word: String = TranslationServer.translate("耐久成功！") if p.survival else "VICTORY!"
	var size := 64
	## 英字は Oxanium、日本語（「耐久成功！」）は日本語の文字を持つ既定のフォント。
	var title_font: Font = LATIN if word == word.to_ascii_buffer().get_string_from_ascii() else ThemeDB.fallback_font
	var widths: Array[float] = []
	var total := 0.0
	for ch in word:
		var w := title_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 4.0
		widths.append(w)
		total += w
	var x := 640.0 - total * 0.5
	for i in range(word.length()):
		var st := 0.15 + i * 0.07
		var k := lt - st
		if k >= 0.0:
			var y := 0.0
			if k < 0.16:
				y = -60.0 * (1.0 - k / 0.16) * (1.0 - k / 0.16)
			elif k < 0.30:
				y = -10.0 * sin(PI * (k - 0.16) / 0.14)
			var pos := Vector2(x, 196 + roundf(y / 2.0) * 2.0)
			ci.draw_string(title_font, pos + Vector2(3, 4), word[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.0, 0.05, 0.08, 0.6 * a))
			ci.draw_string_outline(title_font, pos, word[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(S.ACCENT_SOFT, 0.9 * a))
			ci.draw_string(title_font, pos, word[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(S.TEXT, a))
		x += widths[i]
	var font := ThemeDB.fallback_font
	if lt > 0.85:
		var k2 := clampf((lt - 0.85) / 0.2, 0.0, 1.0)
		var headline: String = (TranslationServer.translate("%s の猛攻を耐え抜いた！") if p.survival else TranslationServer.translate("%s を倒した！")) % p.boss_name
		_center(ci, font, headline, Vector2(640, 236), 22, Color(S.TEXT, a * k2), Color(0, 0, 0, 0.6 * a * k2), 5)
	if lt > 1.15:
		var k3 := clampf((lt - 1.15) / 0.2, 0.0, 1.0)
		var stats := TranslationServer.translate("クリアターン %d　｜　クリアタイム %s" if p.survival else "撃破ターン %d　｜　クリアタイム %s") % [p.turn, time_text(p.clear_seconds)]
		var w := font.get_string_size(stats, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var box := Rect2(Vector2(roundf(640 - w * 0.5 - 18), 252 + roundf((1.0 - k3) * 6)), Vector2(roundf(w + 36), 34))
		ci.draw_rect(box, Color(S.PANEL, 0.86 * a * k3))
		ci.draw_rect(Rect2(box.position, Vector2(3, box.size.y)), Color(S.ACCENT, a * k3))
		_center(ci, font, stats, Vector2(640, box.position.y + 24), 18, Color(S.TEXT, a * k3), Color(0, 0, 0, 0), 0)

func _center(ci: CanvasItem, font: Font, text: String, at: Vector2, size: int, color: Color, outline: Color, outline_px: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(roundf(at.x - w * 0.5), at.y)
	if outline_px > 0 and outline.a > 0.0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_px, outline)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
