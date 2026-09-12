shader_type canvas_item;
render_mode unshaded;
uniform float opacity = 0.0;
uniform float dissolve = 0.0;
void fragment() {
 vec2 cell = floor(UV * vec2(88.0,110.0));
 vec4 c = texture(TEXTURE, (cell+0.5)/vec2(88.0,110.0));
 float noise = fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
 c.rgb = mix(c.rgb,vec3(0.82,0.94,0.83),0.32);
 c.a *= opacity * step(dissolve,noise);
 COLOR = c;
}
