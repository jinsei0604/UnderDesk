shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 覚醒後の黒い炎。体の輪郭から立ち上り、長い炎の先だけが紅く縁取られる。
// TEXTURE: r=上へ伸びやすい距離、g=全方向で同じ距離（どちらも64ドットで1）、b・a=一番近い体の点の位置。
// 炎の長さは「一番近い体の点」で決めるので、炎が体から離れて浮かない。
uniform float flow = 0.;
uniform float power = 1.;
uniform float reach = 26.;
uniform float max_r = 24.;
// 体のどの高さまで炎が届いたか（0=足元、1=頭まで全部）
uniform float rise = 1.;
uniform float seed = 0.;
uniform vec2 world_origin = vec2(0.);
uniform vec3 pal[5];
uniform vec3 glow_col = vec3(.8, .05, .16);
uniform float glow = .14;

void fragment(){
	vec2 ts = vec2(textureSize(TEXTURE, 0));
	vec2 px = floor(UV * ts) + .5;
	vec4 f = texture(TEXTURE, px / ts);
	float d = f.r * 64.;
	float iso = f.g * 64.;
	COLOR = vec4(0.);
	if (power > .001 && d < 63.) {
		vec2 src = f.ba * (ts - 1.) + .5;
		// 模様は世界の座標に固定する（ポーズが変わっても炎の流れが途切れない）
		vec2 q = src + world_origin;
		if (rise < .999) {
			float body_h = (ts.y - 8. - src.y) / max(ts.y - 72., 1.);
			if (rise * 1.14 - body_h + (hfx_n(vec2(q.x * .09, flow * 1.4)) - .5) * .18 < 0.) {
				discard;
			}
		}
		float wav = (hfx_n(vec2(d * .09 - flow * 1.6, q.x * .05 + seed)) - .5) * 7.;
		float n1 = hfx_fbm(vec2((q.x + wav) * .2 + seed, q.y * .05 - d * .012 + flow * .9), 3);
		float n2 = hfx_fbm(vec2((q.x + wav) * .47 - seed, q.y * .11 + flow * 1.7), 2);
		float tongue = clamp((n1 - .4) * 3. + (n2 - .5) * .5, 0., 1.);
		// 足元では細く、体の上半分で伸びる
		float foot = .3 + .7 * smoothstep(0., 30., ts.y - 8. - src.y);
		float r = min(power * (5. + reach * tongue * tongue) * foot, max_r);
		// 体の点の真上から横へ外れるほど短くして、炎の先を細くする。先の方だけ輪郭を揺らす。
		vec2 w_ = px + world_origin;
		float n3 = hfx_fbm(vec2(w_.x * .16, w_.y * .09 + flow * 2.2), 2);
		float rim = r - d - abs(px.x - src.x + (n3 - .5) * 10.) * .9 + (n3 - .5) * 6. * smoothstep(2., 14., d);
		if (rim > 0.) {
			int idx = 0;
			bool tall = r > 10.;
			if (rim < 1.) { idx = tall ? 4 : 2; }
			else if (rim < 2.2) { idx = tall ? 3 : 1; }
			else if (rim < 3.6 && tall) { idx = 2; }
			else if (iso < 1.5) { idx = 1; }
			else if (abs(2. * hfx_fbm(vec2(q.x * .12, q.y * .05 - d * .08 + flow * 1.5) + seed, 2) - 1.) < .1) { idx = 1; }
			COLOR = vec4(pal[idx], 1.);
		} else if (glow > 0. && rim > -14.) {
			float g = exp(rim / 5.) * glow * clamp(power, 0., 1.);
			COLOR = vec4(glow_col * g, 0.);
		}
	}
}
