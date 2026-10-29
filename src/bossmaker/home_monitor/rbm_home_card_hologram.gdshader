// ホームの「ボス作成」カードのホログラム（2026-10-28）。ドット絵の明るさだけを水色の濃淡にする。走査線は RBMHomeCardArt が重ねる。
shader_type canvas_item;

uniform float alpha = 0.7;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	COLOR = vec4(mix(vec3(0.05, 0.35, 0.42), vec3(0.45, 0.98, 1.0), l * 1.4), c.a * alpha * COLOR.a);
}
