shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 center = vec2(350.0, 400.0);
uniform vec2 stage_origin = vec2(0.0);
uniform vec2 stage_size = vec2(1280.0, 720.0);
uniform float unit = 1.75;
uniform float cutoff = 660.0;
uniform float amount = 0.0;
uniform float seam = 0.0;
uniform float fold = 0.0;
uniform vec2 jolt = vec2(0.0);
void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 local = pixel - stage_origin;
	vec2 d = (local - center) / unit;
	float r = max(length(d), .1);
	float side = 1.0 - smoothstep(cutoff - 60.0 * unit, cutoff, local.x);
	float reach = 235.0;
	float nr = r < reach ? reach * pow(r/reach, 1.0 - .80*amount) : r;
	float twist = .48 * amount * pow(1.0-clamp(r/reach, 0.0, 1.0), 1.4) * side;
	mat2 rotation = mat2(vec2(cos(twist), sin(twist)), vec2(-sin(twist), cos(twist)));
	vec2 warped = rotation * d * mix(1.0, nr/r, side);
	float h = 5.0 + 71.0*seam;
	float lens = exp(-pow(d.x/22.0, 2.0)) * exp(-pow(d.y/(h+8.0), 6.0)) * seam * (1.0-fold) * side;
	warped.x += sign(d.x) * (8.0 + 3.0*cos(d.y*.14)) * lens;
	warped.y += sin(d.y*.11) * 5.0 * lens;
	vec2 source = center + warped*unit + jolt*side;
	// Nearest pixel grid and a strict boss-side boundary, including camera jolt.
	source = mix(local, floor(source/unit+.5)*unit, side);
	source = clamp(source, vec2(.5), stage_size-vec2(.5));
	COLOR = texture(screen_tex, (source+stage_origin)*SCREEN_PIXEL_SIZE);
}
