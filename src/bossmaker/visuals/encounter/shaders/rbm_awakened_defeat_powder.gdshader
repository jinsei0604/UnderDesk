shader_type canvas_item;
render_mode unshaded;
#include "res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_field.gdshaderinc"
void fragment() {
	vec2 p=UV*vec2(1280.0,720.0)-origin;
	float e=max(age-.48,0.0), q=smoothstep(0.0,.48,age);
	float spread=1.0-exp(-e*6.0);
	vec2 drift=vec2(0.0,e*e*65.0);
	vec4 g=grain(p+drift+vec2(-e*28.0,e*40.0));
	vec2 v=p+drift+(g.rg-.5)*65.0;
	float n=mist(v*1.2+vec2(-e*35.0,e*65.0));
	float density=0.0;
	vec3 col=vec3(.055,.052,.065);
	float alpha=0.0;
	if(age<.48) {
		vec2 u=v/vec2(85.0,110.0);
		alpha=smoothstep(.46,.72,n+exp(-dot(u,u))*.3)*q*.85*exp(-dot(u,u)*.7);
		float fuse=exp(-dot(p/vec2(25.0,35.0),p/vec2(25.0,35.0)))*q*q;
		col=mix(col,vec3(.90,.34,.08),fuse);
		alpha=max(alpha,fuse);
	} else {
		// Staggered rolling lobes merge as density, never as nested outlined stamps.
		for(int i=0;i<13;i++) {
			float fi=float(i), a=fi*2.39996;
			vec2 center=vec2(cos(a)*(120.0+rnd(fi+1.0)*490.0),sin(a)*(80.0+rnd(fi+9.0)*200.0))*spread;
			center.y-=e*40.0*rnd(fi+6.0);
			float size=(65.0+rnd(fi+3.0)*85.0)*(.5+spread*.85);
			vec2 u=(v-center)/vec2(size,size*(.9+rnd(fi)*.3));
			density=max(density,exp(-dot(u,u)*1.4));
		}
		vec2 center_uv=(v+vec2(0.0,e*40.0))/vec2(170.0+spread*170.0,120.0+spread*90.0);
		density=max(density,exp(-dot(center_uv,center_uv)));
		float erosion=smoothstep(.50,2.0,e)*.50;
		float value=density*.75+n*.55-erosion;
		alpha=smoothstep(.37,.66,value)*smoothstep(.02,.15,density)*(1.0-smoothstep(1.65,2.10,e));
		float light=sat((n-.35)*2.0)*.60+sat(-p.y/650.0)*.08;
		col=mix(vec3(.045,.043,.052),vec3(.28,.23,.23),light);
		float hot=1.0-smoothstep(.07,.53,e);
		float heart=exp(-dot(p/vec2(240.0,180.0),p/vec2(240.0,180.0)))*hot;
		float fire=heart*sat((n-.28)*3.0);
		col=mix(col,vec3(.91,.32,.07),sat(fire*1.7));
		col=mix(col,vec3(1.0,.86,.59),pow(sat(fire*1.3),2.0));
		alpha=max(alpha,heart);
	}
	COLOR=vec4(stepped(col),alpha*step(0.0,age));
}
