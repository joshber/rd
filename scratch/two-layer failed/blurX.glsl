// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// blurX: Gaussian aggregation in the x dimension
// Thanks: http://www.blackpawn.com/texts/blur/

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

uniform sampler2D kernel;
uniform vec2 res; // kernel dimensions in pixels

void main() {
  vec2 uv = gl_FragCoord.xy / res;
  vec2 x = vec2( 1. / res.x, 0. );

  // Fragments left and right
  vec2 l = uv - x;
  vec2 r = uv + x;

  // Toroidal geometry
  l.x += l.x < 0. ? 1. : 0.;
  r.x -= r.x > 1. ? 1. : 0.;

  // FIXME COMMENT RATIOS
  vec4 c = texture2D( kernel, l ) + 2 * texture2D( kernel, uv ) + texture2D( kernel, r );

  gl_FragColor = vec4( c.rg, 0., 1. );
}
