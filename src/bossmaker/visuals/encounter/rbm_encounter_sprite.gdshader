shader_type canvas_item;
// 登場・勝利の演出: キャラの絵を変形せずに、色だけ・消え方だけを変える（表示専用）。
// mode 0: そのまま / 1: 単色（影・縁・白い点滅）/ 2: 四角い粒で消える・現れる（threshold 0=全部見える 1=全部消える）
uniform int mode = 0;
uniform vec4 flat_color : source_color = vec4(1.0);
uniform float threshold = 0.0;
uniform float block_px = 3.0;
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float edge_width = 0.08;
uniform float rise = 0.0; // >0: 上の方から先に消える（下から積み上がる・上へほどける）
uniform float desat = 0.0; // 0〜1: 色を抜く（石像のように）

// 描く時の色（modulate）。fragment の COLOR は既にテクスチャを掛けた値なので、ここで元の色を受け取る。
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec4 c = t * vcol;
	if (mode == 1) {
		// 単色: 色は描く時の modulate（COLOR）で決める
		c = vec4(flat_color.rgb * vcol.rgb, t.a * vcol.a * flat_color.a);
	} else if (mode == 2) {
		vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE / block_px);
		float n = hash(cell);
		// 上ほど早く消える（UV.y が小さいほど閾値が下がる）
		n = mix(n, n * 0.55 + (UV.y) * 0.45, rise);
		if (n < threshold) {
			discard;
		}
		if (n < threshold + edge_width && threshold > 0.001) {
			c.rgb = mix(c.rgb, edge_color.rgb, edge_color.a);
		}
	}
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(l) * vec3(0.95, 0.95, 1.0), desat);
	COLOR = c;
}
