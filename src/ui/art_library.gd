class_name UDArtLibrary
extends RefCounted
## Sprite lookup by naming convention: drop a PNG into assets/art/ and
## it replaces the placeholder rectangle — no code changes needed (§6).
##
## Recognized names:
##   minion_0.png .. minion_5.png  (variant = minion id % 6, party units)
##   enemy_<enemy_id>.png  (trash mobs and bosses, data/enemies/ ids)
##   room_<room_id>.png  (e.g. room_dorm.png)
##   weapon_<weapon_id>.png  (data/weapons/ ids)
##   depot.png
##   dialog_bg_<archive|treasure|shop|altar|guild|dorm>.png
##   (illustrated backdrop behind a UDCardDialog's card grid)
##   dig_background.png  (the cave backdrop behind the battle view)
##   series_<series_id>.png  (e.g. series_journal.png, the archive shelf icon)
##   item_rank_<Z|S|A|B|C|D>.png  (the treasure shelf's rank-card icon)
##
## Frame animation: add <key>_f2.png, <key>_f3.png, ... and the sprite
## cycles through them automatically (the base file is frame 1).
##
## Spatial variants: add <key>_v2.png, <key>_v3.png, ... and
## variant_texture(key, seed)/tiled_texture(key, cell) pick one
## deterministically per call site instead of animating over time.
## Unlike _fN frames these never change on their own.
##
## After adding files run the editor once or `godot --headless --import`.

const ART_DIR: String = "res://assets/art"
const MINION_VARIANTS: int = 6
const PLACEHOLDER_ICON_SIZE: int = 28

var _frames: Dictionary = {}  # key -> Array[Texture2D]
var _variants: Dictionary = {}  # key -> Array[Texture2D], [0] duplicates _frames[key][0]
var _icon_cache: Dictionary = {}  # "shape:seed:size" -> Texture2D


## room_ids/item_ids/shop_ids/doc_ids/enemy_ids are optional: passing them
## lets shipped assets like room_<id>.png or item_<id>.png be found up
## front. Anything missing still renders via icon_or_placeholder() and
## upgrades automatically once the matching PNG is dropped in.
static func load_default(
	room_ids: Array[String],
	item_ids: Array[String] = [],
	shop_ids: Array[String] = [],
	doc_ids: Array[String] = [],
	series_ids: Array[String] = [],
	enemy_ids: Array[String] = [],
	weapon_ids: Array[String] = [],
) -> UDArtLibrary:
	var lib := UDArtLibrary.new()
	var keys: Array[String] = [
		"depot",
		"dialog_bg_archive", "dialog_bg_treasure", "dialog_bg_shop",
		"dialog_bg_altar", "dialog_bg_guild", "dialog_bg_dorm",
		"dig_background",
	]
	for i in MINION_VARIANTS:
		keys.append("minion_%d" % i)
	for rank in UD.ITEM_RANKS:
		keys.append("item_rank_%s" % rank)
	for room_id in room_ids:
		keys.append("room_%s" % room_id)
	for item_id in item_ids:
		keys.append("item_%s" % item_id)
	for shop_id in shop_ids:
		keys.append("shop_%s" % shop_id)
	for doc_id in doc_ids:
		keys.append(doc_id)
	for series_id in series_ids:
		keys.append("series_%s" % series_id)
	for enemy_id in enemy_ids:
		keys.append("enemy_%s" % enemy_id)
	for weapon_id in weapon_ids:
		keys.append("weapon_%s" % weapon_id)
	for key in keys:
		var frames: Array = []
		var base_path := "%s/%s.png" % [ART_DIR, key]
		if ResourceLoader.exists(base_path, "Texture2D"):
			frames.append(load(base_path))
			var frame_index := 2
			while true:
				var frame_path := "%s/%s_f%d.png" % [ART_DIR, key, frame_index]
				if not ResourceLoader.exists(frame_path, "Texture2D"):
					break
				frames.append(load(frame_path))
				frame_index += 1
		if not frames.is_empty():
			lib._frames[key] = frames
			var variants: Array = [frames[0]]
			var variant_index := 2
			while true:
				var variant_path := "%s/%s_v%d.png" % [ART_DIR, key, variant_index]
				if not ResourceLoader.exists(variant_path, "Texture2D"):
					break
				variants.append(load(variant_path))
				variant_index += 1
			lib._variants[key] = variants
	return lib


func has_art(key: String) -> bool:
	return _frames.has(key)


func texture(key: String) -> Texture2D:
	if not _frames.has(key):
		return null
	return (_frames[key] as Array)[0]


func frame_count(key: String) -> int:
	if not _frames.has(key):
		return 0
	return (_frames[key] as Array).size()


## Returns the frame for an arbitrary animation counter (wraps around).
func frame(key: String, index: int) -> Texture2D:
	if not _frames.has(key):
		return null
	var frames := _frames[key] as Array
	return frames[posmod(index, frames.size())]


## Deterministic spatial variant lookup (e.g. per dig-grid cell) so a
## terrain tile isn't a single texture stamped identically everywhere.
## `seed` should be stable per call site (e.g. a hash of the cell coords);
## same seed always yields the same variant. Falls back to texture(key)
## when no _vN files are shipped.
func variant_texture(key: String, seed: int) -> Texture2D:
	if not _variants.has(key):
		return texture(key)
	var variants := _variants[key] as Array
	return variants[posmod(seed, variants.size())]


## Seamless tiling: the _vN variants were sliced from one NxN source image
## (row-major), so indexing them by (x, y) position reconstructs that image
## tiled across the world — a coherent rock surface, not random fragments.
func tiled_texture(key: String, cell: Vector2i) -> Texture2D:
	if not _variants.has(key):
		return texture(key)
	var variants := _variants[key] as Array
	var n := int(round(sqrt(float(variants.size()))))
	if n < 1:
		return variants[0]
	var idx := posmod(cell.y, n) * n + posmod(cell.x, n)
	return variants[posmod(idx, variants.size())]


func minion_key(minion_id: int) -> String:
	return "minion_%d" % (minion_id % MINION_VARIANTS)


## Real art if shipped under `key`, otherwise a small generated icon so
## list dialogs (shop/treasures/archive) read as illustrated rather than
## plain text even before final art exists (§6). `seed_text` picks the
## icon's color deterministically; `shape` is "gem" / "rune" / "book".
func icon_or_placeholder(key: String, seed_text: String, shape: String) -> Texture2D:
	if has_art(key):
		return texture(key)
	return placeholder_icon(seed_text, shape)


func placeholder_icon(seed_text: String, shape: String) -> Texture2D:
	var cache_key := "%s:%s" % [shape, seed_text]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key]
	var size := PLACEHOLDER_ICON_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var color := _seed_color(seed_text)
	match shape:
		"gem":
			_paint_diamond(image, color)
		"book":
			_paint_book(image, color)
		_:
			_paint_circle(image, color)
	var tex := ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = tex
	return tex


static func _seed_color(seed_text: String) -> Color:
	var hue := float(absi(seed_text.hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.85)


static func _paint_diamond(image: Image, color: Color) -> void:
	var size := image.get_width()
	var center := float(size) / 2.0
	var radius := center - 2.0
	for y in size:
		for x in size:
			var d := absf(x - center) + absf(y - center)
			if d <= radius:
				image.set_pixel(x, y, color.lightened(0.35) if d > radius - 2.5 else color)


static func _paint_circle(image: Image, color: Color) -> void:
	var size := image.get_width()
	var center := float(size) / 2.0
	var radius := center - 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - center, y - center).length()
			if d <= radius:
				image.set_pixel(x, y, color.lightened(0.35) if d > radius - 2.5 else color)


static func _paint_book(image: Image, color: Color) -> void:
	var size := image.get_width()
	var margin := int(size * 0.14)
	for y in range(margin, size - margin):
		for x in range(margin, size - margin):
			var edge := x < margin + 2 or x >= size - margin - 2 \
				or y < margin + 2 or y >= size - margin - 2
			image.set_pixel(x, y, color.lightened(0.35) if edge else color)
	var spine_x := size / 2
	for y in range(margin, size - margin):
		image.set_pixel(spine_x, y, color.darkened(0.35))
