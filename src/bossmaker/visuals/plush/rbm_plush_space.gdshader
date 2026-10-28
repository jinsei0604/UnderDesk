shader_type canvas_item;
render_mode unshaded;
// Local adaptation of Musha ink director SPACE_SHADER: opposite bank sliding,
// nearest screen fetch, native integer offsets; no blur and no global flashes.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 center = vec2(430.0,477.0);
uniform float amount = 0.0;
void fragment(){
 vec2 p=floor(UV*vec2(1280.0,720.0))+.5;
 vec2 u=vec2(-.42,.907524);vec2 n=vec2(.907524,.42);
 vec2 d=p-center;float a=dot(d,u);float s=dot(d,n);
 float length_gate=1.0-smoothstep(57.0,85.0,abs(a));
 float taper=pow(max(0.0,1.0-abs(a)/85.0),.58);
 float notch=sin(floor(a/8.0)*2.7)*1.7+sin(floor(a/13.0)*1.9);
 float gap=max(0.0,(13.0*taper+notch*length_gate)*amount);
 float fall=(1.0-smoothstep(18.0,68.0,abs(s)))*length_gate;
 float sign_side=s>=0.0?1.0:-1.0;
 vec2 offset=(u*sign_side*12.0+n*sign_side*gap)*amount*fall;
 offset=round(offset);
 vec2 uv=SCREEN_UV-offset*SCREEN_PIXEL_SIZE*(vec2(1.0)/SCREEN_PIXEL_SIZE/vec2(1280.0,720.0));
 vec3 col=texture(screen_tex,uv).rgb;
 if(amount>.001 && abs(a)<85.0){
   float edge=abs(s)-gap;
   if(edge<0.0){
     col=vec3(.018,.012,.030);
     if(s>gap*.55){col=vec3(.095,.052,.135);}
   }
   // Unequal fractured banks: a pale cutting edge, a dark violet opposite bank.
   if(edge>=0.0 && edge<1.5*amount && length_gate>.12){
     col=mix(col,s<0.0?vec3(.66,.53,.71):vec3(.30,.17,.39),amount);
   }
 }
 COLOR=vec4(col,1.0);
}
