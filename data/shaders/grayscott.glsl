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

// FIXME -- add min and max to clamp to edges
vec2 lp5( vec2 uv, vec2 px ) {
  vec3 p = vec3( px, 0. );
  vec2 a = uv - p.zy;
  vec2 b = uv - p.xz;
  vec2 c = uv + p.xz;
  vec2 d = uv + p.zy;

  vec4 lp =
      texture2D( kernel, a )
    + texture2D( kernel, b )
    + texture2D( kernel, c )
    + texture2D( kernel, d )
    - 4. * texture2D( kernel, uv );

  return lp.xy;
}

// FIXME -- THIS IS INCORRECT. p.w assumes 1:1 aspect ratio. Reimplement
// FIXME -- CHANGE clamp to min and max
vec2 lp9( vec2 uv, vec4 offset ) {
  return (

  // Row 1
  + .5 * texture2D( kernel, clamp( uv - offset.xy, 0., 1. ) )
  + texture2D( kernel, clamp( uv - offset.zy, 0., 1. ) )
  + .5 * texture2D( kernel, clamp( uv - offset.wy, 0., 1. ) )

  // Row 2
  + texture2D( kernel, clamp( uv - offset.xz, 0., 1. ) )
  - 6. * texture2D( kernel, uv )
  + texture2D( kernel, clamp( uv + offset.xz, 0., 1. ) )

  // Row 3
  + .5 * texture2D( kernel, clamp( uv + offset.wy, 0., 1. ) )
  + texture2D( kernel, clamp( uv + offset.zy, 0., 1. ) )
  + .5 * texture2D( kernel, clamp( uv + offset.xy, 0., 1. ) )

  ).xy;
}

// End of vector field utility functions
//


void main() {
  vec2 uv = gl_FragCoord.xy / res;
  vec2 px = 1. / res;

  // Parameters
  float feed = .055;
  float kill = .062;
  float diffusionA = 1.;
  float diffusionB = .5;
  float dt = 1.;

  vec2 c = texture2D( kernel, uv ).xy;
  float a = c.x;
  float b = c.y;
  float abb = a * b * b;

  vec2 lc = lp5( uv, px ); // Laplacian

  vec2 dc = vec2( diffusionA * lc.x - abb + feed * ( 1. - a ),
                  diffusionB * lc.y + abb - ( feed + kill ) * b );

  gl_FragColor = vec4( clamp( c + dc * dt, 0., 1. ), 0., 1. );
}
