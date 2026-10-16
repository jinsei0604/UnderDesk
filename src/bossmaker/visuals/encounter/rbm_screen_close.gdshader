shader_type canvas_item;
// 前の画面が、古いモニターの電源を切るように閉じる（登場演出の入り。表示専用）。
// いま画面に出ている物（前の画面）を画面のテクスチャとして読み、縦に縮めながら明るくし、最後は横一本の光が中央へ縮んで消える。
// CPU への読み出しはしない（GPU の中の写しだけ）。キャンバス 1280×720 の座標で計算し、画面の画素へは
// 実際の表示の拡大率（get_final_transform の拡大率）を掛けて変換する（COMBAT_PRESENTATION §5.3）。
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float closing = 0.0;          // 0=そのまま 1=消えた
uniform vec2 canvas_size = vec2(1280.0, 720.0);
uniform vec2 screen_scale = vec2(1.0); // キャンバス 1px が画面の何 px か

void fragment() {
	vec2 p = UV * canvas_size;
	vec3 col = vec3(0.0);
	if (closing <= 0.0) {
		col = texture(screen_tex, SCREEN_UV).rgb;
	} else if (closing < 0.7) {
		// 縦に縮み、白っぽく明るくなる
		float k = closing / 0.7;
		float s = k * k * (3.0 - 2.0 * k);
		float h = floor(mix(canvas_size.y, 4.0, s) + 0.5);
		float top = floor((canvas_size.y - h) * 0.5 + 0.5);
		if (p.y >= top && p.y < top + h) {
			vec2 src = vec2(p.x, (p.y - top) / h * canvas_size.y);
			vec2 suv = SCREEN_UV + (src - p) * screen_scale * SCREEN_PIXEL_SIZE;
			col = texture(screen_tex, suv).rgb * (1.0 + 1.6 * k);
		}
	} else if (closing < 1.0) {
		// 横一本の光が中央へ縮んで消える
		float k = (closing - 0.7) / 0.3;
		float w = floor(mix(canvas_size.x, 0.0, k) + 0.5);
		float a = 1.0 - k * 0.6;
		vec2 c = canvas_size * 0.5;
		if (abs(p.x - c.x) < w * 0.5 && p.y >= c.y - 2.0 && p.y < c.y + 2.0) {
			col = mix(col, vec3(0.85, 0.98, 1.0), a);
		}
		if (abs(p.x - c.x) < w * 0.3 && p.y >= c.y - 1.0 && p.y < c.y + 1.0) {
			col = mix(col, vec3(1.0), a);
		}
	}
	COLOR = vec4(col, 1.0);
}
