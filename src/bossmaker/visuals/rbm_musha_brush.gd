extends Node2D
## 覚醒後の技名の黒毛筆(生成済みPNGの2文字合成)。属性文字+「境」(単体)/「界」(全体)。
## 全技名は黒固定・属性色は使わない。フォント描画やカラー文字に置き換えない。衝撃と
## 同時に出現し、.95秒から墨崩壊、1.05秒からfade、1.5秒で消滅する。
const ROOT := "res://assets_bossmaker/battle/musha_awakened/"
const HEIGHT_SINGLE := 145.0
const HEIGHT_ALL := 175.0
const LIFETIME := 1.5
## brush.pngの並び: 0無 1炎 2氷 3雷 4風 5境 6界。
const SUFFIX_SINGLE := 5
const SUFFIX_ALL := 6

const SHADER_CODE := """shader_type canvas_item;
uniform float fade=1.0;
uniform float dissolve=0.0;
void fragment(){
 float a=texture(TEXTURE,UV).a;
 float n=fract(sin(dot(floor(UV*vec2(200.0,180.0)),vec2(12.9898,78.233)))*43758.5453);
 vec2 px=TEXTURE_PIXEL_SIZE*4.0;
 float rim=max(max(texture(TEXTURE,UV+vec2(px.x,0)).a,texture(TEXTURE,UV-vec2(px.x,0)).a),max(texture(TEXTURE,UV+vec2(0,px.y)).a,texture(TEXTURE,UV-vec2(0,px.y)).a));
 COLOR=vec4(mix(vec3(.72,.71,.67),vec3(.005),step(.08,a)),max(a,rim*.72)*fade*step(dissolve,n));
}"""

var _glyphs: Array[Sprite2D] = []
var _regions: Array = []

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader := Shader.new()
	shader.code = SHADER_CODE
	for i in range(2):
		var g := Sprite2D.new()
		g.region_enabled = true
		g.visible = false
		g.material = ShaderMaterial.new()
		(g.material as ShaderMaterial).shader = shader
		add_child(g)
		_glyphs.append(g)

func configure() -> void:
	var texture := load(ROOT + "brush.png") as Texture2D
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "new_regions.json"))
	if parsed is Dictionary:
		_regions = (parsed as Dictionary).get("brush", [])
	for g in _glyphs:
		g.texture = texture

static func _rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])

## attribute_index: 0..4(無炎氷雷風)。age: 着弾からの経過(負なら非表示)。at: 2文字の中心。
func show_brush(attribute_index: int, huge: bool, age: float, at: Vector2) -> void:
	var visible_now := age >= 0.0 and age < LIFETIME and _regions.size() >= 7
	for g in _glyphs:
		g.visible = visible_now
	if not visible_now:
		return
	var size_px := HEIGHT_ALL if huge else HEIGHT_SINGLE
	var indices := [attribute_index, SUFFIX_ALL if huge else SUFFIX_SINGLE]
	for i in range(2):
		var g := _glyphs[i]
		g.region_rect = _rect(_regions[indices[i]])
		g.scale = Vector2.ONE * size_px / g.region_rect.size.y * (1.0 + .05 * (1.0 - smoothstep(0.0, .1, age)))
		g.position = at + Vector2((i - .5) * size_px * .96, 0)
		(g.material as ShaderMaterial).set_shader_parameter("fade", 1.0 - smoothstep(1.05, 1.5, age))
		(g.material as ShaderMaterial).set_shader_parameter("dissolve", smoothstep(.95, 1.5, age))

func hide_brush() -> void:
	for g in _glyphs:
		g.visible = false
