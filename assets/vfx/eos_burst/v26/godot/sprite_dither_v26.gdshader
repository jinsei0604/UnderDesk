shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform bool reveal_next = false;

float bayer4(ivec2 pixel) {
	int x = pixel.x % 4;
	int y = pixel.y % 4;
	int index = x + y * 4;
	float value = 0.0;
	if (index == 0) value = 0.0;
	else if (index == 1) value = 8.0;
	else if (index == 2) value = 2.0;
	else if (index == 3) value = 10.0;
	else if (index == 4) value = 12.0;
	else if (index == 5) value = 4.0;
	else if (index == 6) value = 14.0;
	else if (index == 7) value = 6.0;
	else if (index == 8) value = 3.0;
	else if (index == 9) value = 11.0;
	else if (index == 10) value = 1.0;
	else if (index == 11) value = 9.0;
	else if (index == 12) value = 15.0;
	else if (index == 13) value = 7.0;
	else if (index == 14) value = 13.0;
	else value = 5.0;
	return (value + 0.5) / 16.0;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	if (texel.a < 0.5) {
		discard;
	}
	ivec2 source_pixel = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
	float threshold = bayer4(source_pixel);
	bool keep_pixel = reveal_next ? (progress > threshold) : (progress <= threshold);
	if (!keep_pixel) {
		discard;
	}
	COLOR = texel * COLOR;
}
