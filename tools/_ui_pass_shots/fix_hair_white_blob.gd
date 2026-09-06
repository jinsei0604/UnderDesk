extends SceneTree

## 緊急修正パス（2026-09-03、9回目）: ユーザー報告「髪周辺の白い切り抜き
## 残り」の実体を特定する調査（本セッション）で発見した、本物の欠陥を
## 修正する。
##
## 【発見の経緯】自動フリンジ検出テスト（境界の不透明画素で明るい色を
## 探す、maxc>0.82）は0件だったが、これは探索条件が「透明画素に隣接する
## 境界画素」に限定されていたため——今回の欠陥は境界ではなく、髪の内部
## （毛先の巻き毛のすぐ近く、右肩の外側、native座標おおよそx:603-623,
## y:370-417）に孤立して存在する、彩度の低い明るい(ほぼ純白、最大で
## RGB=(1.0,1.0,1.0))不透明ブロック（約200-260画素、7素材全てに存在——
## つまりA自身を含む配布時点のオリジナル原画に元から存在していた欠陥で、
## warp生成パイプラインで新たに生じたものではない）だった。
##
## 実GPU・実背景合成のスクリーンショットで直接確認したところ、この
## ブロックは襟の白いレース飾り（連続した別形状、もっと下・左にある）
## とは明確に離れた、独立した孤立形状——髪の巻き毛のすぐ隣に唐突に
## 現れる、影も陰影もない平坦な白い塊で、意図的に描かれた衣装ハイライト
## とは考えにくい（generate_eyelid_texturesや既存の襟のレース部分は
## いずれも自然な陰影・階調を持つのに対し、この塊だけ単色に近い）。
## 背景を消したスクリーンショット（キャラクター非表示）でこの位置には
## 何も映らないことも確認済み——背景美術の要素ではなく、キャラクター
## 自身のテクスチャに焼き込まれた欠陥である。
##
## 【修正方針】シルエット（alpha）は一切変更しない——この画素は元々
## 不透明（キャラクターの一部）なので、輪郭・ポーズ・重心移動量には
## 一切影響を与えない。RGBだけを、同じフレーム内の最も近い「白ブロブ
## ではない不透明画素」（＝周囲の髪の色）で置き換える最近傍拡張方式。
## 新しい絵を描き起こさない・彩度の低い暖色系画素（肌・金・白い衣装等）
## を誤って消さないよう、検出条件は「不透明かつmaxc>0.55かつ彩度<0.12」
## という厳しい閾値のみ——本調査で実際にこの領域を走査した結果、この
## 条件に一致するのはこの1つの孤立ブロブのみで、髪・肌・金の縁取り・
## 白い襟のレール等の正当な明色画素は（彩度や輝度が異なるため）
## 一致しなかったことを確認済み。

## 本番アセットと、warpパイプラインが将来再実行された場合の参照元と
## なる「originals」アーカイブの両方に適用する——originalsを直さないと、
## 将来誰かがgenerate_amplified_idle_frames.gdを再実行した際にこの欠陥が
## 復活してしまうため。
const TARGETS := [
	{"dir": "res://assets_bossmaker/art/", "names": ["a", "ab", "b", "bc", "c", "d_posture", "e_hand", "ad"], "labels": ["A", "AB", "B", "BC", "C", "D", "E", "AD"]},
	{"dir": "res://tools/_ui_pass_shots/originals/", "names": ["a", "b", "c", "d_posture", "e_hand"], "labels": ["orig-A", "orig-B", "orig-C", "orig-D", "orig-E"]},
]

## 欠陥探索領域。右肩の毛先付近・左肩の毛先付近(髪周辺、9回目セッション
## で発見・修正済み)に加え、追加修正パス（2026-09-03、10回目）でコート
## 中央・腰のベルト付近(native x:418-428,y:556-615、前回セッションで
## 発見済みだが当時は「髪」の範囲外として保留していたもの)も今回
## あわせて修正する——前回と全く同じ「陰影のない平坦な白ブロブ」
## パターンであることを確認済み。
const SEARCH_REGIONS: Array[Rect2i] = [
	Rect2i(580, 365, 60, 60),
	Rect2i(320, 395, 40, 60),
	Rect2i(410, 550, 30, 75),
]

## 白ブロブ判定条件——不透明(a>0.5)かつ中性色で明るい画素のみ。
const BLOB_MAX_C_THRESHOLD := 0.55
const BLOB_SAT_THRESHOLD := 0.12

## 最近傍の「非ブロブ不透明画素」を探す最大半径（native px）。
const MAX_SEARCH_RADIUS := 24

func _init() -> void:
	for target in TARGETS:
		var dir: String = target["dir"]
		var names: Array = target["names"]
		var labels: Array = target["labels"]
		for i in range(names.size()):
			var path := dir + "creator_guide_idle_%s.png" % names[i]
			if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
				print("%s: ファイルなし、スキップ (%s)" % [labels[i], path])
				continue
			var img := _load(path)
			var mask := _find_blob(img)
			if mask.is_empty():
				print("%s: 白ブロブ検出なし（変更不要）" % labels[i])
				continue
			_fix_blob(img, mask)
			img.save_png(ProjectSettings.globalize_path(path))
			print("%s: 白ブロブ%d画素を髪色で置換して保存 (%s)" % [labels[i], mask.size(), path])
	quit()

func _load(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

func _is_blob_pixel(c: Color) -> bool:
	if c.a < 0.5:
		return false
	var maxc: float = max(c.r, max(c.g, c.b))
	var minc: float = min(c.r, min(c.g, c.b))
	var sat: float = 0.0 if maxc <= 0.0001 else (maxc - minc) / maxc
	return maxc > BLOB_MAX_C_THRESHOLD and sat < BLOB_SAT_THRESHOLD

func _find_blob(img: Image) -> Dictionary:
	var mask := {}
	for region in SEARCH_REGIONS:
		for y in range(region.position.y, region.position.y + region.size.y):
			for x in range(region.position.x, region.position.x + region.size.x):
				if _is_blob_pixel(img.get_pixel(x, y)):
					mask[Vector2i(x, y)] = true
	return mask

## 各ブロブ画素を、同一フレーム内で最も近い「ブロブではない不透明画素」
## の色で置き換える（alphaは変更しない——常に不透明のまま）。
func _fix_blob(img: Image, mask: Dictionary) -> void:
	for p in mask.keys():
		var replacement := _find_nearest_non_blob_color(img, mask, p.x, p.y)
		var orig := img.get_pixel(p.x, p.y)
		img.set_pixel(p.x, p.y, Color(replacement.r, replacement.g, replacement.b, orig.a))

func _find_nearest_non_blob_color(img: Image, mask: Dictionary, cx: int, cy: int) -> Color:
	for radius in range(1, MAX_SEARCH_RADIUS + 1):
		# 半径radiusのリング上を走査し、最初に見つかった有効画素を採用
		# （リング内で複数見つかる場合は左上優先——十分小さい半径なので
		# 色のばらつきは無視できる)。
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= img.get_width() or ny >= img.get_height():
					continue
				if mask.has(Vector2i(nx, ny)):
					continue
				var c := img.get_pixel(nx, ny)
				if c.a > 0.5:
					return c
	# 見つからなければ変更なし（安全側、あり得ないはずだが念のため）。
	return img.get_pixel(cx, cy)
