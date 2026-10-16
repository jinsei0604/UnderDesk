extends RefCounted
## 登場・勝利の演出: 味方の絵を1コマずつ描く（表示専用）。コマは次の2種類。
##   "b:N"  … 本番の12ポーズ（assets_bossmaker/battle/<味方>/frames/NN.png。RBMCharacterVisual と同じ倍率・足元）
##   "s:N"  … Codex が作った完成済みの中割りのコマ（actions/*_intermediates_*.png）。位置・足元・倍率は
##            Codex の各スクリプトの定義（CELLS・PIVOTS/FEET・倍率・執事の顔の差し替え）を読むだけで使い、同じ式で描く。
## Codex のスクリプト・素材は変更しない。絵を伸縮・回転させない（執事の顔の差し替えは Codex と同じ扱い）。
const Sprites = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_sprites.gd")
const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
const Hero = preload("res://src/bossmaker/visuals/rbm_hero_action.gd")
const Butler = preload("res://src/bossmaker/visuals/rbm_butler_action.gd")
const Healer = preload("res://src/bossmaker/visuals/rbm_healer_action.gd")
const SamuraiBody = preload("res://src/bossmaker/visuals/rbm_samurai_body.gd")
const TankBody = preload("res://src/bossmaker/visuals/rbm_tank_body.gd")

static var _sheets := {}

## 中割りのコマの1枚絵の場所（Codex の各スクリプトの定義を読むだけ）。
static func sheet_path(asset: String) -> String:
	match asset:
		"hero": return Hero.SHEET_PATH
		"butler": return Butler.SHEET
		"healer": return Healer.SHEET
		"samurai": return SamuraiBody.SHEET
		"tank": return TankBody.SHEET
	return ""

## 読み込む素材（warm_paths() 用）: 中割りのコマの1枚絵と、執事の顔に使う元の絵。
static func warm_paths(assets: Array) -> Array[String]:
	var out: Array[String] = []
	for a in assets:
		var p := sheet_path(str(a))
		if not p.is_empty() and not out.has(p):
			out.append(p)
		if str(a) == "butler":
			out.append(Assets.frame_path("butler", 0))
	return out

## 中割りのコマの1枚絵（事前読み込みで読み終えている物を受け取る。読めていない時は null で、その味方は動かさない）。
static func sheet(asset: String) -> Texture2D:
	if _sheets.has(asset):
		return _sheets[asset]
	var path := sheet_path(asset)
	if path.is_empty() or not ResourceLoader.has_cached(path):
		return null
	var t: Texture2D = load(path)
	_sheets[asset] = t
	return t

## 再生の前に、読み終えている1枚絵を受け取る（allow_load はテスト・検証用）。
static func hold(assets: Array, allow_load: bool = false) -> void:
	for a in assets:
		var path := sheet_path(str(a))
		if not _sheets.has(str(a)) and not path.is_empty() and (allow_load or ResourceLoader.has_cached(path)):
			_sheets[str(a)] = load(path)

static func draw(ci: CanvasItem, asset: String, frame: String, foot: Vector2, mod: Color = Color.WHITE) -> void:
	var kind := frame.substr(0, 1)
	var n := int(frame.substr(2))
	if kind == "b":
		Sprites.draw(ci, asset, n, foot, mod)
		return
	var tex := sheet(asset)
	if tex == null:
		return
	foot = foot.round()
	match asset:
		"hero":
			var r: Rect2 = Hero.CELLS[n]
			ci.draw_texture_rect_region(tex, Rect2((foot + (r.position - Hero.PIVOTS[n]) * Hero.PIXEL_SCALE).round(), r.size * Hero.PIXEL_SCALE), r, mod)
		"healer":
			var sc := 82.0 / 292.0
			var cell: Rect2 = Healer.CELLS[n]
			ci.draw_texture_rect_region(tex, Rect2((foot + (cell.position - Healer.FEET[n]) * sc).round(), cell.size * sc), cell, mod)
		"butler":
			_draw_butler(ci, tex, n, foot, mod)
		"samurai":
			# 本番の侍の描き方（rbm_samurai_body.gd）と同じ。色を掛ける時は modulate の代わりに同じ式で描く。
			if mod == Color.WHITE:
				SamuraiBody.draw_frame(ci, tex, n, foot)
			else:
				var regions: Array = [SamuraiBody.CELLS[n]]
				if n == 9: regions.append(Rect2(511, 661, 93, 66))
				if n == 10: regions.append(Rect2(780, 659, 123, 68))
				for region: Rect2 in regions:
					ci.draw_texture_rect_region(tex, Rect2((foot + (region.position - SamuraiBody.FEET[n]) * SamuraiBody.SCALE).round(), region.size * SamuraiBody.SCALE), region, mod)
		"tank":
			var rect: Rect2 = TankBody.CELLS[n]
			ci.draw_texture_rect_region(tex, Rect2((foot + (rect.position - TankBody.FEET[n]) * TankBody.SCALES[n]).round(), rect.size * TankBody.SCALES[n]), rect, mod)

## 執事: 中割りのコマの顔の部分を抜き、承認済みの元の顔（frames/00 の ORIGINAL_HEAD）を元の倍率で重ねる（Codex の _draw と同じ式）。
static func _draw_butler(ci: CanvasItem, tex: Texture2D, n: int, foot: Vector2, mod: Color) -> void:
	var sc := Assets.display_height("butler") / 264.0
	var cell: Rect2 = Butler.CELLS[n]
	var cut: Rect2 = Butler.HEAD_CUTS[n]
	for region in [Rect2(cell.position, Vector2(cell.size.x, cut.position.y - cell.position.y)),
		Rect2(Vector2(cell.position.x, cut.position.y), Vector2(cut.position.x - cell.position.x, cut.size.y)),
		Rect2(Vector2(cut.end.x, cut.position.y), Vector2(cell.end.x - cut.end.x, cut.size.y)),
		Rect2(Vector2(cell.position.x, cut.end.y), Vector2(cell.size.x, cell.end.y - cut.end.y))]:
		if region.has_area():
			ci.draw_texture_rect_region(tex, Rect2((foot + (region.position - Butler.FEET[n]) * sc).round(), region.size * sc), region, mod)
	var head := Assets.texture("butler", 0)
	var head_scale: float = float(Sprites.meta("butler").scale)
	var anchor: Vector2 = (foot + (Vector2(cut.get_center().x, cut.end.y) - Butler.FEET[n]) * sc).round()
	ci.draw_set_transform(anchor, 0.10 if n in [13, 14] else 0.0)
	ci.draw_texture_rect_region(head, Rect2(Vector2(-56, -108) * head_scale, Butler.ORIGINAL_HEAD.size * head_scale), Butler.ORIGINAL_HEAD, mod)
	ci.draw_set_transform(Vector2.ZERO)

## 武器の先・手の位置（光らせる所）。分からない時は頭の上あたり。
static func tip(asset: String, frame: String, foot: Vector2) -> Vector2:
	var kind := frame.substr(0, 1)
	var n := int(frame.substr(2))
	if kind == "s":
		match asset:
			"hero":
				if Hero.TIPS.has(n):
					return foot + (Vector2(Hero.TIPS[n]) - Hero.PIVOTS[n]) * Hero.PIXEL_SCALE
			"samurai":
				return SamuraiBody.tip(n, foot)
			"healer":
				return foot + (Healer.TIPS[n] - Healer.FEET[n]) * (82.0 / 292.0)
			"butler":
				return foot + (Butler.WATCHES[n] - Butler.FEET[n]) * (Assets.display_height("butler") / 264.0)
			"tank":
				return TankBody.head(n, foot) + Vector2(0, -20)
	return foot + Vector2(0, -100)
