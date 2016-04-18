// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// blurY: Gaussian aggregation in the y dimension
// Takes the output of blurX as its input
// Thanks: http://www.blackpawn.com/texts/blur/

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

uniform sampler2D blurX;
uniform vec2 res; // kernel dimensions in pixels

void main() {
  vec2 uv = gl_FragCoord.xy / res;
  vec2 y = vec2( 0., 1. / res.y );

  // Fragments above and below
  vec2 a = uv - y;
  vec2 b = uv + y;

  // Toroidal geometry
  a.y += a.y < 0. ? 1. : 0.;
  b.y -= b.y > 1. ? 1. : 0.;

  vec4 c = texture2D( blurX, a ) + 2. * texture2D( blurX, uv ) + texture2D( blurX, b );

  gl_FragColor = vec4( c.rg, 0., 1. );
}
