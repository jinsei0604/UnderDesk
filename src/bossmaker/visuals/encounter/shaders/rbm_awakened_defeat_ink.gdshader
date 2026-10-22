shader_type canvas_item;
render_mode unshaded;
#include "res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_field.gdshaderinc"
void fragment() {
	vec2 p=UV*vec2(1280.0,720.0)-origin;
	float e=max(age-.62,0.0), q=smoothstep(0.0,.62,age);
	float spread=1.0-exp(-e*7.8);
	vec2 motion=vec2(-e*90.0,e*65.0);
	vec4 g=grain(p+motion);
	vec2 warp=(g.rg-.5)*100.0;
	vec2 v=p+warp;
	float n=mist(p*1.5+motion);
	float density=0.0;
	float alpha=0.0;
	vec3 col=vec3(.045,.038,.065);
	if (age<.62) {
		float d=length(v/vec2(125.0,160.0));
		alpha=smoothstep(.52,.73,n+(1.0-d)*.30)*q*.85*(1.0-smoothstep(.4,1.6,d));
		float eye=exp(-dot((p-vec2(-10.0,-48.0))/vec2(29.0,12.0),(p-vec2(-10.0,-48.0))/vec2(29.0,12.0)))*q;
		col=mix(col,vec3(.85,.12,.14),eye);
		alpha=max(alpha,eye*.85);
	} else {
		// Unequal liquid plumes: widths bend and break with density, no stroked contours.
		for(int i=0;i<9;i++) {
			float fi=float(i), a=fi*2.39996+.23;
			vec2 dir=vec2(cos(a),sin(a)*.76); dir=normalize(dir);
			float reach=(460.0+rnd(fi+8.0)*620.0)*spread;
			float along=dot(v,dir);
			float width=(35.0+rnd(fi+4.0)*62.0)*(1.0-sat(along/(reach+1.0))*.65);
			float across=dot(v,vec2(-dir.y,dir.x))+sin(along*.012+fi)*24.0*spread;
			float plume=exp(-across*across/(width*width+1.0))*smoothstep(-20.0,90.0,along)*(1.0-smoothstep(reach*.62,reach,along));
			density=max(density,plume);
		}
		float core=exp(-dot(v/vec2(130.0,160.0),v/vec2(130.0,160.0)));
		density=max(density,core);
		float erosion=smoothstep(.26,1.66,e)*.65;
		alpha=smoothstep(.38,.56,density*.60+n*.67-erosion)*smoothstep(.03,.17,density)*(1.0-smoothstep(1.35,1.85,e));
		float light=pow(sat(n*1.5-.25),3.0)*.28;
		col+=vec3(.33,.22,.27)*light;
		float ember=pow(sat(g.b*2.0-.75),3.0)*exp(-length(p)/280.0)*(1.0-smoothstep(.18,.66,e));
		col=mix(col,vec3(.75,.12,.14),ember);
		float hot=exp(-dot(p/vec2(120.0+160.0*spread,95.0+100.0*spread),p/vec2(120.0+160.0*spread,95.0+100.0*spread)))*pow(1.0-smoothstep(.015,.22,e),2.0);
		col=mix(col,vec3(1.0,.84,.64),hot);
		alpha=max(alpha,hot);
	}
	COLOR=vec4(stepped(col),alpha*step(0.0,age));
}
