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

vec2 lp5( vec2 uv, vec2 px, float scale ) {
  px *= scale;

  vec3 p = vec3( px, 0. );

  vec2 b = uv - p.zy;
  vec2 d = uv - p.xz;
  vec2 e = uv + p.xz;
  vec2 g = uv + p.zy;

  vec4 lp = ( 1. / ( scale * scale ) ) * (
      texture2D( kernel, b )
    + texture2D( kernel, d )
    + texture2D( kernel, e )
    + texture2D( kernel, g )
    - texture2D( kernel, uv ) * 4. );

  return lp.xy;
}

// Nine-point stencils for the Laplacian abound
// http://www.nada.kth.se/~tony/abstracts/Lin90-PAMI.html
// via https://en.wikipedia.org/wiki/Discrete_Laplace_operator
// got me this one, which agreees with the five-point

vec2 lp9( vec2 uv, vec2 px, float scale ) {
  px *= scale;

  vec3 p = vec3( px, 0. );
  vec3 q = vec3( px.x, -px.y, 0. );

  vec2 a = uv - p.xy;
  vec2 b = uv - p.zy;
  vec2 c = uv + q.xy;
  vec2 d = uv - p.xz;
  vec2 e = uv + p.xz;
  vec2 f = uv - q.xy;
  vec2 g = uv + p.zy;
  vec2 h = uv + p.xy;

  vec4 lp = ( 1. / 6. * ( scale * scale ) ) * (
      texture2D( kernel, a )
    + texture2D( kernel, b ) * 4.
    + texture2D( kernel, c )
    + texture2D( kernel, d ) * 4.
    + texture2D( kernel, e ) * 4.
    + texture2D( kernel, f )
    + texture2D( kernel, g ) * 4.
    + texture2D( kernel, h )
    - texture2D( kernel, uv ) * 20. );

  return lp.xy;
}

// End of vector field utility functions
//

void main() {
  vec2 uv = gl_FragCoord.xy / res;
  //uv.y = 1. - uv.y; // It appears Processing does .not. invert y-axis in offscreen buffers
  vec2 px = 1. / res;

  // Parameters
  float feed = .062; // .062:.061 == U-skate world
  float kill = .061;
  float ds = .2; // diffusion scale
  float dr = 2.; // diffusion rate ratio, A/B
  float dt = .1; // time step

  vec2 c = texture2D( kernel, uv ).xy;
  float a = c.x;
  float b = c.y;
  float abb = a * b * b;

  vec2 lc = lp9( uv, px, 1. ); // Laplacian

  vec2 dc = vec2( ds * lc.x - abb + feed * ( 1. - a ),
                  ds / dr * lc.y + abb - ( feed + kill ) * b );

  gl_FragColor = vec4( clamp( c + dc * dt, 0., 1. ), 0., 1. );
}
