extends Sprite2D
## 朽ちた機械武者専用の筆文字(無・炎・氷・雷・風)。命中VFXの背後に出て、墨が
## 散るように欠けて消える。氷は必ず専用のice.png(ink.pngの3番目は「水」に見える
## ため使わない)。他のボスへは追加しない。
const ROOT := "res://assets_bossmaker/battle/musha/"
const LIFETIME := 0.85

const INK_SHADER_CODE := """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform float dissolve = 0.0;
void fragment(){
 vec4 s=texture(TEXTURE,UV);
 float n=fract(sin(dot(floor(UV*vec2(220.0,150.0)),vec2(12.9898,78.233)))*43758.5453);
 float keep=step(dissolve,n);
 vec3 c=mix(vec3(0.012,0.009,0.017),tint.rgb,smoothstep(0.15,0.85,UV.y)*0.72+0.20);
 COLOR=vec4(c,s.a*tint.a*keep);
}"""

var _ink: Texture2D
var _ice: Texture2D
var _regions: Dictionary = {}

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	region_enabled = true
	visible = false
	var shader := Shader.new()
	shader.code = INK_SHADER_CODE
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = shader

func configure() -> void:
	_ink = load(ROOT + "ink.png") as Texture2D
	_ice = load(ROOT + "ice.png") as Texture2D
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "regions.json"))
	if parsed is Dictionary:
		_regions = parsed

static func _rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])

## index: 0無 1炎 2氷 3雷 4風。age: 筆文字自身の経過時間。size: 表示の高さ(px)。
func show_glyph(index: int, age: float, at: Vector2, size_px: float, tint: Color) -> void:
	visible = age >= 0.0 and age < LIFETIME and not _regions.is_empty()
	if not visible:
		return
	var use_ice := index == 2
	texture = _ice if use_ice else _ink
	region_rect = _rect(_regions["ice"] if use_ice else _regions["ink"][index])
	position = at
	scale = Vector2.ONE * size_px / region_rect.size.y * (1.0 + 0.10 * (1.0 - smoothstep(0.0, 0.12, age)))
	var c := tint
	c.a = (1.0 - smoothstep(0.40, 0.85, age)) * 0.96
	(material as ShaderMaterial).set_shader_parameter("tint", c)
	(material as ShaderMaterial).set_shader_parameter("dissolve", smoothstep(0.38, 0.85, age))
