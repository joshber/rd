// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// grayscott.glsl: Gray-Scott reaction-diffusion model, cf.
// http://mrob.com/pub/comp/xmorphia/
// http://blog.hvidtfeldts.net/index.php/2012/08/reaction-diffusion-systems/
// https://github.com/pmneila/jsexp / https://pmneila.github.io/jsexp/grayscott/

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

uniform sampler2D kernel;
uniform vec2 res; // kernel dimensions in pixels

uniform bool brush;
uniform float brushR; // brush radius
uniform vec2 brushP; // brush position

//
// Laplacians

// Toroidal version TODO
// - Check correctness of toroidal versions
// -- does not seem to be working in cases where the initial seed (i.e., brush) did not touch the edge
// - More efficient to incorporate the branches into the initial assignments?

vec4 lp5( vec2 uv, float scale ) {
  vec3 p = vec3( scale / res, 0. );

  // Five-point stencil. Imagine a 3x3 grid labeled a-i. We're just taking the y±1 and x±1 points
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

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

// Toroidal geometry
// Thanks: http://mrob.com/pub/comp/screensavers/ (see function gray_scott 40 percent of the way down)
vec4 torlp5( vec2 uv, float scale ) {
  vec3 p = vec3( scale / res, 0. );

  // Five-point stencil. Imagine a 3x3 grid labeled a-i. We're just taking the y±1 and x±1 points
  vec2 b = uv - p.zy;
  vec2 d = uv - p.xz;
  vec2 f = uv + p.xz;
  vec2 h = uv + p.zy;

  // Wrap at the edges FIXME CHECK
  b.y += b.y < 0. ? 1. : 0.;
  d.x += d.x < 0. ? 1. : 0.;
  f.x -= f.x > 1. ? 1. : 0.;
  h.y -= h.y > 1. ? 1. : 0.;

  vec4 UV = texture2D( kernel, uv );

  vec4 lp = ( 1. / ( scale * scale ) ) * (
      texture2D( kernel, b )
    + texture2D( kernel, d )
    + texture2D( kernel, f )
    + texture2D( kernel, h )
    - UV * 4. );

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

//
// Nine-point stencils for the Laplacian abound
// This one comes from http://www.nada.kth.se/~tony/abstracts/Lin90-PAMI.html
// via https://en.wikipedia.org/wiki/Discrete_Laplace_operator
// It agrees with the five-point

vec4 lp9( vec2 uv, float scale ) {
  vec3 p = vec3( scale / res, 0. );
  vec3 q = vec3( p.x, -p.y, 0. );

  // Nine-point stencil: 3x3 grid labeled a-i
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

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

// Toroidal geometry
vec4 torlp9( vec2 uv, float scale ) {
  vec3 p = vec3( scale / res, 0. );
  vec3 q = vec3( p.x, -p.y, 0. );

  // Nine-point stencil: 3x3 grid labeled a-i
  vec2 a = uv - p.xy;
  vec2 b = uv - p.zy;
  vec2 c = uv + q.xy;
  vec2 d = uv - p.xz;
  vec2 f = uv + p.xz;
  vec2 g = uv - q.xy;
  vec2 h = uv + p.zy;
  vec2 i = uv + p.xy;

  //
  // Wrap at the edges

  // Sides
  b.y += b.y < 0. ? 1. : 0.;
  d.x += d.x < 0. ? 1. : 0.;
  f.x -= f.x > 1. ? 1. : 0.;
  h.y -= h.y > 1. ? 1. : 0.;

  // Corners
  a.x += a.x < 0. ? 1. : 0.;
  a.y += a.y < 0. ? 1. : 0.;
  c.x -= c.x > 1. ? 1. : 0.;
  c.y += c.y < 0. ? 1. : 0.;
  g.x += g.x < 0. ? 1. : 0.;
  g.y -= g.y > 1. ? 1. : 0.;
  i.x -= i.x > 1. ? 1. : 0.;
  i.y -= i.y > 1. ? 1. : 0.;

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

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

// End of Laplacians
//

//
// Gradients
// I.e., to systematically vary feed and kill across the kernel

float linear( float x, float a, float b ) {
  return b + x * ( a - b );
}

float exponential( float x, float e, float a ) {
  return x * a * exp( e );
}

float gaussian( float x, float mu, float sig ) {
  return mu * exp( - x * x / ( 2 * sig * sig ) );
}

// End of gradients
//

void main() {
  vec2 p = gl_FragCoord.xy / res;

  // Gray-Scott state space parameters
  // .062:.061 U-skate world
  // .098:.056 Worms
  // .078:.061 Worms
  // .030:.062 Solitons
  // .025:.060 Pulsing solitons
  // .029:.057 Mazes
  // .039:.058 Holes
  // .026:.051 Chaos
  // .034:.056 Chaos + holes
  // .014:.054 Moving spots
  // .018:.051 Spots and loops
  // .014:.045 Waves
  float feed = .014;
  float kill = .045;

  // Speed and scale parameters
  float ds = .082; // diffusion rate scale. This confounded me for a week. Keep it low
  float dr = 2.; // diffusion rate ratio, U:V
  float dt = 2.5; // time step

  vec4 lpUV = torlp9( p, 1. ); // Laplacian
  vec2 lp = lpUV.xy;
  vec2 UV = lpUV.zw;

  // Convenience definitions
  float U = UV.x;
  float V = UV.y;
  float UVV = U * V * V;

  // Gray-Scott
  vec2 dUV = vec2(  ds * lp.x - UVV + feed * ( 1. - U ),
                    ds / dr * lp.y + UVV - ( feed + kill ) * V );

  //
  // Draw on the kernel if the brush is on
  // One stroke raises the V concentration by .5 at the center,
  // with Gaussian falloff (sd = 1/3 brush radius),
  // clamped at 1
  // Thanks to https://github.com/pmneila/jsexp/blob/master/grayscott/index.html#L61
  // sqrt•dot() instead of distance() gives us a chance to correct for aspect ratio
  // Edge geometry is not toroidal, but that would be more work, computationally,
  // than it'd be worth at this stage

  vec2 bdiff = ( gl_FragCoord.xy - brushP ) / res.x;
  float bd = sqrt( dot( bdiff, bdiff ) );
  float br = brushR / res.x;
  UV.y = min( 1., UV.y + ( ( brush && bd < br ) ? .5 * exp( -bd * bd / ( 2. * br * br / 9. ) ) : 0. ) );

  gl_FragColor = vec4( clamp( UV + dUV * dt, 0., 1. ), 0., 1. );
}
