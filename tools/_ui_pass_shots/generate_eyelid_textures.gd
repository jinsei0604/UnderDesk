extends SceneTree

## §19: まばたきの瞼を「矩形ColorRect」から、キャラクター自身の既存
## ピクセルだけを使った「閉じ目の実形状パッチ」へ置き換える準備。
## 新しい絵は一切描かない——各目の緩いbounding rect内で「明らかに目
## （暗い虹彩／明るいハイライト）」と判定できる画素だけを、同じ列の
## すぐ上にある地肌色で上書きする（=眉/額の地肌が下へ続いているように
## 見せる、単純な機械的フィル）。bounding rect内でも元から地肌色だった
## 画素（両目の間の鼻筋寄りの余白等）はそのまま変更しない。

const SRC := "res://assets_bossmaker/art/creator_guide_character.png"
const OUT_DIR := "res://assets_bossmaker/art/"

const EYE_L_RECT := Rect2i(445, 255, 42, 35)
const EYE_R_RECT := Rect2i(522, 255, 40, 32)
# 地肌色サンプル元の探索を始める行（目のbounding rect上端よりさらに
# 上——眉/前髪の影を避け、確実に地肌に達するまで遡る）。
const SKIN_SEARCH_START_OFFSET := 6
const SKIN_SEARCH_MAX_UP := 40

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	_build_eyelid_texture(img, EYE_L_RECT, OUT_DIR + "creator_guide_character_eyelid_left.png")
	_build_eyelid_texture(img, EYE_R_RECT, OUT_DIR + "creator_guide_character_eyelid_right.png")
	print("done")
	quit()

func _build_eyelid_texture(img: Image, rect: Rect2i, out_path: String) -> void:
	var out := Image.create(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	var replaced := 0
	for lx in range(rect.size.x):
		var native_x: int = rect.position.x + lx
		# この列の「地肌色」を、目のbounding rectより上から探して確定する
		# （最初に見つかった、暗すぎず・白すぎない=地肌らしい画素）。
		var skin_color := _find_skin_color_above(img, native_x, rect.position.y - SKIN_SEARCH_START_OFFSET)
		for ly in range(rect.size.y):
			var native_y: int = rect.position.y + ly
			var c := img.get_pixel(native_x, native_y)
			if _is_eye_pixel(c):
				out.set_pixel(lx, ly, skin_color)
				replaced += 1
			else:
				out.set_pixel(lx, ly, c)
	out.save_png(ProjectSettings.globalize_path(out_path))
	print("saved %s (replaced %d/%d pixels)" % [out_path, replaced, rect.size.x * rect.size.y])

func _find_skin_color_above(img: Image, x: int, start_y: int) -> Color:
	for i in range(SKIN_SEARCH_MAX_UP):
		var y: int = start_y - i
		if y < 0:
			break
		var c := img.get_pixel(x, y)
		if c.a < 0.5:
			continue
		if _is_plausible_skin(c):
			return c
	# 見つからなければ既知の肌色平均値へフォールバック（万一の保険）。
	return Color(0.98, 0.79, 0.62)

func _is_plausible_skin(c: Color) -> bool:
	# 実測した肌色(0.98,0.79,0.62)に近い暖色・中〜高明度の画素。
	var maxc: float = max(c.r, max(c.g, c.b))
	if maxc < 0.55:
		return false
	if not (c.r >= c.g and c.g >= c.b):
		return false
	var sat: float = (maxc - min(c.r, min(c.g, c.b))) / maxc
	return sat > 0.10 and sat < 0.55

func _is_eye_pixel(c: Color) -> bool:
	if c.a < 0.5:
		return false
	var maxc: float = max(c.r, max(c.g, c.b))
	var minc: float = min(c.r, min(c.g, c.b))
	var sat: float = 0.0 if maxc <= 0.0001 else (maxc - minc) / maxc
	# 暗い虹彩（低明度）、白いハイライト（高明度・低彩度）、または灰色系
	# （彩度が低く地肌の暖色らしさが無い——まぶたの影・グレーのハイライト
	# 縁取り等）のいずれか。地肌は必ず暖色（r>g>b、彩度0.10〜0.55程度）
	# なので、それに当てはまらない低彩度画素はこの矩形内では基本的に
	# 「目」由来と判断してよい。
	if maxc < 0.35:
		return true
	if sat < 0.15:
		return true
	return false
