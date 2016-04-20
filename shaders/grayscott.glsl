// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// grayscott.glsl: Gray-Scott reaction-diffusion model, cf.
// http://mrob.com/pub/comp/xmorphia/
// http://blog.hvidtfeldts.net/index.php/2012/08/reaction-diffusion-systems/
// https://github.com/pmneila/jsexp / https://pmneila.github.io/jsexp/grayscott/

#ifdef GL_ES
precision highp float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

uniform sampler2D kernel;
uniform vec2 res; // kernel dimensions in pixels

// Audio signal features
uniform vec3 audio; // ( RMS power 0–10KHz, 10–20KHz, time in ms )

uniform float brushI; // intensity
uniform float brushR; // radius
uniform vec2 brushP; // position

// FIXME TODO noise function
// https://github.com/ashima/webgl-noise/blob/master/src/noise2D.glsl
// https://stackoverflow.com/questions/12964279/whats-the-origin-of-this-glsl-rand-one-liner
// https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl
// https://www.shadertoy.com/view/ltB3zD

//
// Noise
// https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl

// (-1,1)
float snoise( vec2 co ){
    return fract( sin( dot( co.xy ,vec2( 12.9898,78.233 ) ) ) * 43758.5453 );
}
float rand( vec2 uv ) {
  return snoise( vec2( uv.x * cos( audio.z ), uv.y * sin( audio.z ) ) );
}

//
// Laplacians

// Toroidal versions TODO
// - Check correctness of toroidal versions
//   -- does not seem to be working in cases where the initial seed (i.e., brush) did not touch the edge
// - More efficient to incorporate the branches into the initial assignments?

vec4 lp5( vec2 uv, sampler2D k, float scale ) {
  vec3 p = vec3( scale / res, 0. );

  // Five-point stencil. Imagine a 3x3 grid labeled a-i. We're just taking the y±1 and x±1 points
  vec2 b = uv - p.zy;
  vec2 d = uv - p.xz;
  vec2 f = uv + p.xz;
  vec2 h = uv + p.zy;

  vec4 UV = texture2D( k, uv );

  vec4 lp = ( 1. / ( scale * scale ) ) * (
      texture2D( k, b )
    + texture2D( k, d )
    + texture2D( k, f )
    + texture2D( k, h )
    - UV * 4. );

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

// Toroidal geometry
// Thanks: http://mrob.com/pub/comp/screensavers/ (see function gray_scott 40 percent of the way down)
vec4 torlp5( vec2 uv, sampler2D k, float scale ) {
  vec3 p = vec3( scale / res, 0. );

  // Five-point stencil. Imagine a 3x3 grid labeled a-i. We're just taking the y±1 and x±1 points
  vec2 b = uv - p.zy;
  vec2 d = uv - p.xz;
  vec2 f = uv + p.xz;
  vec2 h = uv + p.zy;

  // Wrap at the edges
  b.y += b.y < 0. ? 1. : 0.;
  d.x += d.x < 0. ? 1. : 0.;
  f.x -= f.x > 1. ? 1. : 0.;
  h.y -= h.y > 1. ? 1. : 0.;

  vec4 UV = texture2D( k, uv );

  vec4 lp = ( 1. / ( scale * scale ) ) * (
      texture2D( k, b )
    + texture2D( k, d )
    + texture2D( k, f )
    + texture2D( k, h )
    - UV * 4. );

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

//
// Nine-point stencils for the Laplacian abound
// This one comes from http://www.nada.kth.se/~tony/abstracts/Lin90-PAMI.html
// via https://en.wikipedia.org/wiki/Discrete_Laplace_operator
// It agrees with the five-point

vec4 lp9( vec2 uv, sampler2D k, float scale ) {
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

  vec4 UV = texture2D( k, uv );

  vec4 lp = ( 1. / 6. * ( scale * scale ) ) * (
      texture2D( k, a )
    + texture2D( k, b ) * 4.
    + texture2D( k, c )
    + texture2D( k, d ) * 4.
    + texture2D( k, f ) * 4.
    + texture2D( k, g )
    + texture2D( k, h ) * 4.
    + texture2D( k, i )
    - UV * 20. );

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

// Toroidal geometry
vec4 torlp9( vec2 uv, sampler2D k, float scale ) {
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

  vec4 UV = texture2D( k, uv );

  vec4 lp = ( 1. / 6. * ( scale * scale ) ) * (
      texture2D( k, a )
    + texture2D( k, b ) * 4.
    + texture2D( k, c )
    + texture2D( k, d ) * 4.
    + texture2D( k, f ) * 4.
    + texture2D( k, g )
    + texture2D( k, h ) * 4.
    + texture2D( k, i )
    - UV * 20. );

  // By returning UV here, we obviate the need to resample the current fragment
  return vec4( lp.xy, UV.xy );
}

// End of Laplacians
//

void main() {
  vec2 p = gl_FragCoord.xy / res; // p instead of uv to avoid confusion (U and V are terms of the G-S PDEs)

  // Speed and scale parameters
  float ds = .082; // diffusion rate scale. This confounded me for a week. Keep < .1. Better yet, leave it at .082
  float dr = 2.; // diffusion rate ratio, U:V. Must be ≥2. >2, you get finer detail but it's more static. Keep in [2,10]
  float dt = 2.5; // time step. Keep in [1,4). Above ~4 you get uncontrolled V growth, exposing the whole video

  // TODO: dt and power ... zc and dt noise terms

  /*/ dr and dt gradients -- systematically profile effects of different values
  float drfloor = 2.;
  float drceil = 10.;
  float dtfloor = 1.;
  float dtceil = 4.;
  dr = p.x * ( drceil - drfloor ) + drfloor;
  dt = p.y * ( dtceil - dtfloor ) + dtfloor; //*/

  // Gray-Scott state space parameters. Cf.
  // - http://mrob.com/pub/comp/xmorphia/
  // - http://mrob.com/pub/comp/xmorphia/pde-uc-classes.html
  // .062:.061 U-skate world
  // .098:.056 ??
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

  float feed = .025;
  float kill = .060;

  vec4 lpUV = torlp9( p, kernel, 1. ); // Laplacian
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
  UV.y = min( 1., UV.y + brushI * ( bd < br  ? .5 * exp( -bd * bd / ( 2. * br * br / 9. ) ) : 0. ) );

  gl_FragColor = vec4( clamp( UV + dUV * dt, 0., 1. ), 0., 1. );
}
