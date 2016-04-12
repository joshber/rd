#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// grayscott.glsl
// Implement Gray-Scott reaction-diffusoin model, cf.
// http://blog.hvidtfeldts.net/index.php/2012/08/reaction-diffusion-systems/
// http://mrob.com/pub/comp/xmorphia/
// http://www.karlsims.com/rd.html

// FIXME TODO
// PASS IN FREQ SPECTRUM AS A TEXTURE, USE IT TO MODIFY PARAMETERS

uniform sampler2D kernel;
uniform vec2 res; // viewport dimensions in pixels

//
// Laplacian

// FIXME -- clamp texture coordinates?
vec2 lp5( vec2 uv, vec2 px ) {
  vec3 p = vec3( px, 0. );

  vec2 b = uv - p.zy;
  vec2 d = uv - p.xz;
  vec2 e = uv + p.xz;
  vec2 g = uv + p.zy;

  vec4 lp =
      texture2D( kernel, b )
    + texture2D( kernel, d )
    + texture2D( kernel, e )
    + texture2D( kernel, g )
    - 4. * texture2D( kernel, uv );

  return lp.xy;
}

// FIXME -- clamp texture coordinates?
vec2 lp9( vec2 uv, vec2 px ) {
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

  vec4 lp =
        texture2D( kernel, a )
      + texture2D( kernel, b ) * 4.
      + texture2D( kernel, c )
      + texture2D( kernel, d ) * 4.
      + texture2D( kernel, e ) * 4.
      + texture2D( kernel, f )
      + texture2D( kernel, g ) * 4.
      + texture2D( kernel, h )
      - 20. * texture2D( kernel, uv );

  return lp.xy;
}

// End of vector field utility functions
//

//
// Gradients

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
  vec2 uv = gl_FragCoord.xy / res;
  uv.y = 1. - uv.y; // Processing inverts y-axis
  vec2 px = 1. / res;
  vec2 center = vec2( .5, .5 );

  // Parameters
  float feed = gaussian( distance( uv, center ), .9, .1 );//.055;
  float kill = gaussian( distance( uv, center ), .1, .01 );//.062;
  float diffusionA = linear( uv.x, .01, .1 );//.1;
  float diffusionB = linear( uv.y, .1, .01 );//.1;
  float dt = .1;

  vec2 c = texture2D( kernel, uv ).xy;
  float a = c.x;
  float b = c.y;
  float abb = a * b * b;

  vec2 lc = lp9( uv, px ); // Laplacian

  vec2 dc = vec2( diffusionA * lc.x - abb + feed * ( 1. - a ),
                  diffusionB * lc.y + abb - ( feed + kill ) * b );

  gl_FragColor = vec4( clamp( c + dc * dt, 0., 1. ), 0., 1. );
}
