shader_type canvas_item;
// 本体の絵は変えず、表示の時だけ色を載せる（暗くする・縁の照り返し・闇の侵食・影絵）。
uniform vec3 tint = vec3(.12, .08, .15);
uniform float tint_amt = 0.;
uniform vec3 rim_col = vec3(1.);
uniform float rim_amt = 0.;
uniform float rim_side = 0.;
uniform vec2 crawl_center = vec2(.5, .3);
uniform float crawl = 0.;
uniform vec3 crawl_rim = vec3(.9, .15, .25);
uniform float flash = 0.;
uniform vec3 flash_col = vec3(1.);
uniform float silhouette = 0.;
uniform vec3 sil_col = vec3(.02, .01, .04);

void fragment(){
	vec4 c = texture(TEXTURE, UV);
	vec2 t = TEXTURE_PIXEL_SIZE;
	vec3 rgb = c.rgb;
	if (crawl > 0.) {
		vec2 px = UV / t;
		vec2 cen = crawl_center / t;
		float dist = length((px - cen) * vec2(1.12, .88)) + 2. * sin(px.y * .49) + 1.8 * sin(px.x * .37);
		float scarlet = step(c.g * 1.45, c.r) * step(.31, c.r);
		if (dist < crawl && scarlet < .5) {
			rgb *= vec3(.62, .52, .68);
		}
		if (abs(dist - crawl) < 1.5 && c.b > .19) {
			rgb = crawl_rim;
		}
	}
	rgb = mix(rgb, tint, tint_amt);
	if (rim_amt > 0.) {
		float l = texture(TEXTURE, UV + vec2(-t.x, 0.)).a;
		float r = texture(TEXTURE, UV + vec2(t.x, 0.)).a;
		float u = texture(TEXTURE, UV + vec2(0., -t.y)).a;
		float e = rim_side < -.5 ? 1. - l : (rim_side > .5 ? 1. - r : max(max(1. - l, 1. - r), 1. - u));
		if (e > .5) {
			rgb = mix(rgb, rim_col, rim_amt);
		}
	}
	rgb = mix(rgb, sil_col, silhouette);
	rgb = mix(rgb, flash_col, flash);
	// COLOR にはすでにテクスチャの色が掛かっているので、掛け直さない（掛けると絵が暗くなる）。
	COLOR = vec4(rgb, c.a);
}
