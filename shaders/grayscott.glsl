// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// grayscott.glsl: Gray-Scott reaction-diffusion model, cf.
// http://mrob.com/pub/comp/xmorphia/
// http://blog.hvidtfeldts.net/index.php/2012/08/reaction-diffusion-systems/
// https://github.com/pmneila/jsexp / https://pmneila.github.io/jsexp/grayscott/

#ifdef GL_ES
precision highp float; // necessary for snoise()
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

//
// Gray-Scott state space parameters. Cf.
// - http://mrob.com/pub/comp/xmorphia/
// - http://mrob.com/pub/comp/xmorphia/pde-uc-classes.html
// - https://pmneila.github.io/jsexp/grayscott/

const vec2
USKATE          = vec2( .062, .061 ), // U-skate world
SOLITONS        = vec2( .030, .062 ), // Solitons
PULSOLITONS     = vec2( .025, .060 ), // Pulsing solitons
WORMS           = vec2( .078, .061 ), // Worms
MAZES           = vec2( .029, .057 ), // Mazes
HOLES           = vec2( .039, .058 ), // Holes
TREERINGS       = vec2( .026, .051 ), // Tree rings
TREERINGSHOLES  = vec2( .034, .056 ), // Tree rings + holes
MOVINGSPOTS     = vec2( .014, .054 ), // Moving spots
SPOTSLOOPS      = vec2( .018, .051 ), // Spots and loops
WAVES           = vec2( .014, .045 ), // Waves
VSTEADY         = vec2( .098, .056 ); // V stays steady

uniform sampler2D kernel;
uniform vec2 res; // kernel dimensions in pixels

uniform vec2 time; // (running time in ms, instantaneous framerate in fps)

// Audio signal features
uniform vec2 spl; // Sound pressure level in dB, scaled to [0,1]. x:0–11KHz y:11–22KHz
uniform vec3 spectral; // Spectral moments. x:centroid y:spread z:flatness, all [0,1]
uniform vec4 beat; // ( x, y, radius, time of onset in ms )

// Paintbrush
uniform vec4 brush; // ( x, y, intensity, radius )

//
// Noise
// https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl

// (-1,1)
float snoise( vec2 co ){
    return fract( sin( dot( co.xy ,vec2( 12.9898,78.233 ) ) ) * 43758.5453 );
}
float rand( vec2 uv ) {
  return snoise( vec2( uv.x * cos( time.x ), uv.y * sin( time.x ) ) );
}

//
// Laplacians
// NB Five-point versions removed for loading efficiency
// Nine-point stencils for the Laplacian abound
// This one comes from http://www.nada.kth.se/~tony/abstracts/Lin90-PAMI.html
// via https://en.wikipedia.org/wiki/Discrete_Laplace_operator

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

  // The louder the environment, the faster the simulation runs. spl.x == db SPL 0–11KHz scaled [0,1]
  float dtfloor = 1.;
  float dtceil = 4.;
  dt = ( spl.x + spl.y ) * ( dtceil - dtfloor ) + dtfloor;
  dt *= 60. / time.y; // dt is calibrated for 60fps. Correct for divergence in instantaneous framerate

  // The “brighter” the sound (spectral centroid), the more local variation in the texture of the pattern
  float error = ( rand( p ) + 1. ) * 4.; // random error term in [0,8]
  dr += spectral.x * error;

  // Alternate: The greater the spectral spread, the more local variation in the speed
  // Can lead to rapid extinction
  //float error = rand( p );
  //dt += spectral.y * error;

  // dr and dt gradients -- systematically profile effects of different values
  //float drfloor = 2.;
  //float drceil = 10.;
  //float dtfloor = 1.;
  //float dtceil = 4.;
  //dr = p.x * ( drceil - drfloor ) + drfloor;
  //dt = p.y * ( dtceil - dtfloor ) + dtfloor;

  // Gray-Scott state space parameters
  vec2 fk = WAVES;
  float feed = fk.x;
  float kill = fk.y;

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
  // Draw on the kernel if the brush is on or we're in the decay shadow of a sound energy spike (beat)
  // One stroke raises the V concentration by .5 at the center,
  // with Gaussian falloff (sd = 1/3 brush radius),
  // clamped at 1
  // Thanks to https://github.com/pmneila/jsexp/blob/master/grayscott/index.html#L61
  // sqrt•dot() instead of distance() gives us a chance to correct for aspect ratio
  // Edge geometry is not toroidal, but that would be more work, computationally,
  // than it'd be worth at this stage

  vec2 bdiff = ( gl_FragCoord.xy - brush.xy ) / res.x;
  float bd = sqrt( dot( bdiff, bdiff ) );
  float br = brush.w / res.x;
  UV.y = min( 1., UV.y + brush.z * ( bd < br  ? .5 * exp( -bd * bd / ( 2. * br * br / 9. ) ) : 0. ) );

  bdiff = ( gl_FragCoord.xy - beat.xy ) / res.x;
  bd = sqrt( dot( bdiff, bdiff ) );
  br = beat.z / res.x;
  float intensity = 1. / exp( ( time.x - beat.w ) / 20. ); // Exponential decay -- 20ms is an adjusted frame period
  UV.y = min( 1., UV.y + intensity * ( bd < br  ? .5 * exp( -bd * bd / ( 2. * br * br / 9. ) ) : 0. ) );

  // Glitch: Depends on the noisiness of the spectrum (spectral flatness / tonality coefficient)
  // FIXME Does nothing unless the threshold is ≥ .54·sflatness -- why?
  UV.y = ( rand( p ) + 1. ) * .5 < .54 * spectral.z ? 1. - UV.y : UV.y;

  gl_FragColor = vec4( clamp( UV + dUV * dt, 0., 1. ), 0., 1. );
}
