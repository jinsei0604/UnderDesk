shader_type canvas_item;
render_mode unshaded;
uniform sampler2D skin : filter_nearest, repeat_disable;
uniform vec2 quad_origin;
uniform vec2 quad_size;
uniform vec2 body_scale;
uniform float pixel_scale = 0.75;
uniform vec2 tip;
uniform vec2 root_pos;
uniform float bud;
uniform float crush;
uniform float ripple;
uniform float age;

vec4 body_at(vec2 p) {
    vec2 sc=body_scale*pixel_scale;
    // Preserve the original 4-source-row rendering, with nearest-neighbour pixels.
    float row=floor((p.y/sc.y+196.0)/4.0)*4.0;
    float wob=sin(row*0.065-age*21.0)*ripple*0.42;
    vec2 uv=vec2((p.x-wob)/sc.x+256.0,p.y/sc.y+460.0);
    if(uv.x<116.0||uv.x>=400.0||uv.y<264.0||uv.y>=464.0) return vec4(0.0);
    return texture(skin,(floor(uv)+0.5)/512.0);
}

void fragment() {
    vec2 p=floor(quad_origin+UV*quad_size)+vec2(0.5);
    vec4 body=body_at(p);
    vec4 result=body;
    float len=max(1.0,root_pos.x-tip.x);
    float q=clamp((root_pos.x-p.x)/len,0.0,1.0);
    float curve=-3.0*sin(q*3.14159)*bud;
    float wave=sin(q*7.0-age*17.0)*ripple*0.32*sin(q*3.14159);
    float cy=mix(root_pos.y,tip.y,q)+curve+wave;
    float formation=smoothstep(0.0,0.22,bud);
    float root_width=22.0*formation;
    float shaft_width=12.0;
    // The arm continues into a blunt end; impact adds a small, soft squash.
    float width=mix(root_width,shaft_width*formation,smoothstep(0.0,0.38,q));
    width+=sin(q*3.14159)*2.0*bud;
    width+=5.0*crush*smoothstep(0.68,1.0,q)*formation;
    float dy=p.y-cy;
    float tip_growth=smoothstep(0.0,0.32,bud);
    float front=tip.x-mix(24.0,15.0,crush)*tip_growth;
    float corner=min(2.0,width*0.22);
    vec2 edge=vec2(front+corner-p.x,abs(dy)-width+corner);
    float dist=length(max(edge,vec2(0.0)))+min(max(edge.x,edge.y),0.0)-corner;
    dist=max(dist,p.x-root_pos.x);
    bool inside=dist<=0.0 && bud>0.001;
    if(inside) {
        float yn=clamp(dy/max(1.0,width),-1.0,1.0);
        // Fine, stable texture from the existing left flank. No stretched pixels.
        float tx=176.0+mod(floor((p.x-root_pos.x)/3.0),6.0)*2.0;
        float ty=mix(367.0,427.0,yn*0.5+0.5);
        vec3 col=texture(skin,(vec2(tx,ty)+0.5)/512.0).rgb;
        // Outer contour only; body/arm union suppresses the old dividing outline.
        if(dist> -1.5 && body.a<0.5) col=vec3(0.125,0.094,0.129);
        else if(dist> -3.5 && body.a<0.5) col=vec3(0.42,0.13,0.18);
        // Soft material highlight is a stepped cluster, never a blurry glow.
        float upper=abs(yn+0.49);
        if(upper<0.095 && q>0.22 && q<0.84 && mod(floor(q*20.0),7.0)<5.0) col=vec3(0.93,0.36,0.32);
        float seam=smoothstep(root_pos.x-30.0,root_pos.x+1.0,p.x);
        if(body.a>0.5) {
            // Same local skin, merging inside the flank and staying clear of the eyes.
            float shade=max(body.r,max(body.g,body.b));
            float weight=seam;
            if(shade<0.30) weight*=smoothstep(root_pos.x-12.0,root_pos.x+1.0,p.x);
            col=mix(col,body.rgb,weight);
        }
        result=vec4(col,1.0);
    }
    COLOR=result;
}
