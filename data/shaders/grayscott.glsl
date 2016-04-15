// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// grayscott.glsl: Gray-Scott reaction-diffusion model, cf.
// http://mrob.com/pub/comp/xmorphia/
// http://blog.hvidtfeldts.net/index.php/2012/08/reaction-diffusion-systems/
// http://www.karlsims.com/rd.html

// FIXME TODO
// PASS IN FREQ SPECTRUM AS A TEXTURE, USE IT TO MODIFY PARAMETERS

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

uniform sampler2D kernel;
uniform vec2 res; // kernel dimensions in pixels

//
// Laplacians

// FIXME TODO: Implement toroidal Laplacians

/* NB TODO http://mrob.com/pub/comp/screensavers/
vec2 cup = vec2( c.x, (c.y+1.0 > sz.y) ? c.y+1.0-sz.y : c.y+1.0);
    vec2 cdn = vec2( c.x, (c.y<1.0) ? c.y+sz.y-1.0 : c.y-1.0);
    vec2 crt = vec2((c.x+1.0 > sz.x) ? c.x+1.0-sz.x : c.x+1.0, c.y);
    vec2 clt = vec2((c.x<1.0) ? c.x+sz.x-1.0 : c.x-1.0, c.y);

Look at how he implements a toroid (closing edges) on a 5-point stencil!
*/

vec4 lp5( vec2 uv, float scale ) {
  vec3 p = vec3( scale / res, 0. );

  vec2 b = uv - p.zy;
  vec2 d = uv - p.xz;
  vec2 f = uv + p.xz;
  vec2 h = uv + p.zy;

  vec4 UV = texture2D( kernel, uv );

  vec4 lp = ( 1. / ( scale * scale ) ) * (
      texture2D( kernel, b )
    + texture2D( kernel, d )
    + texture2D( kernel, f )
    + texture2D( kernel, h )
    - UV * 4. );

  return vec4( lp.xy, UV.xy ); // Sample the current fragment just once
}

// Nine-point stencils for the Laplacian abound
// http://www.nada.kth.se/~tony/abstracts/Lin90-PAMI.html
// via https://en.wikipedia.org/wiki/Discrete_Laplace_operator
// suggested this one, which agreees with the five-point

vec4 lp9( vec2 uv, float scale ) {
  vec3 p = vec3( scale / res, 0. );
  vec3 q = vec3( p.x, -p.y, 0. );

  vec2 a = uv - p.xy;
  vec2 b = uv - p.zy;
  vec2 c = uv + q.xy;
  vec2 d = uv - p.xz;
  vec2 f = uv + p.xz;
  vec2 g = uv - q.xy;
  vec2 h = uv + p.zy;
  vec2 i = uv + p.xy;

  vec4 UV = texture2D( kernel, uv );

  vec4 lp = ( 1. / 6. * ( scale * scale ) ) * (
      texture2D( kernel, a )
    + texture2D( kernel, b ) * 4.
    + texture2D( kernel, c )
    + texture2D( kernel, d ) * 4.
    + texture2D( kernel, f ) * 4.
    + texture2D( kernel, g )
    + texture2D( kernel, h ) * 4.
    + texture2D( kernel, i )
    - UV * 20. );

  return vec4( lp.xy, UV.xy ); // Sample the current fragment just once
}

// End of vector field utility functions
//

void main() {
  vec2 p = gl_FragCoord.xy / res;

  // State space parameters
  float feed = .062; // .062:.061 == U-skate world
  float kill = .061;

  // Speed and scale parameters
  float ds = .2; // diffusion scale
  float dr = 2.; // diffusion rate ratio, U:V
  float dt = .2; // time step

  vec4 lpUV = lp9( p, 1. ); // Laplacian
  vec2 lp = lpUV.xy;
  vec2 UV = lpUV.zw;

  // Convenience definitions
  float U = UV.x;
  float V = UV.y;
  float UVV = U * V * V;

  vec2 dUV = vec2(  ds * lp.x - UVV + feed * ( 1. - U ),
                    ds / dr * lp.y + UVV - ( feed + kill ) * V );

  gl_FragColor = vec4( clamp( UV + dUV * dt, 0., 1. ), 0., 1. );
}
