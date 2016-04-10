#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

// Cf.
// http://blog.hvidtfeldts.net/index.php/2012/08/reaction-diffusion-systems/
// http://mrob.com/pub/comp/xmorphia/
// http://www.karlsims.com/rd.html

// TODO: Add orientation to the diffusion rates, per Sims' description?

uniform vec2 res; // viewport dimensions in pixels

uniform sampler2d filter;

uniform vec4 feedkill;
uniform vec4 diffusion;
uniform float dt;

void main() {
  vec2 uv = gl_FragCoord.xy / res;
  vec2 px = 1. / res;

  // TODO: Experiment with gradients
  // distance( uv, vec2( .5, .5 ) ) -- 2D, centered at center of image

  // Determine local feed and kill rates
  float f = linear( uv.x, feedkill.x, feedkill.y );
  float k = linear( uv.y, feedkill.z, feedkill.w );

  // Determine local diffusion rates
  float difF = linear( uv.x, diffusion.x, diffusion.y );
  float difK = linear( uv.y, diffusion.z, diffusion.w );

  vec4 v = texture2d( filter, uv );
  vec2 lv = laplacian( uv, vec4( px, 0., -px.x )).xy;
  float fkk = v.x * v.y * v.y;

  vec2 dV = vec2( difF * lv.x - fkk + f * ( 1. - v.x ),
                  difK * lv.y + fkk - ( f + k ) * v.y );

  gl_FragColor = vec4( dV * dt, 0., 0. );
}

// FIXME TODO: Clamp texture accesses for edge cases
// e.g. texture2d( filter, clamp( uv - offset.xy, 0., 1. ) ) ?? or do I need vec2s in the clamp range?
vec4 laplacian( vec2 uv, vec4 offset ) {
  return
  // Row 1
  + .5 * texture2d( filter, uv - offset.xy )
  + texture2d( filter, uv - offset.zy )
  + .5 * texture2d( filter, uv - offset.wy )
  // Row 2
  + texture2d( filter, uv - offset.xz )
  - 6. * texture2d( filter, uv )
  + texture2d( filter, uv + offset.xz )
  // Row 3
  + .5 * texture2d( filter, uv + offset.wy )
  + texture2d( filter, uv + offset.zy )
  + .5 * texture2d( filter, uv + offset.xy )
  ;
}

//
// Gradients for feed/kill and diffusion rates

float linear( float x, float f0, float slope ) {
  return clamp( slope * x + f0, 0., 1. );
}

float exponential( float x, float f0, float e ) {
  return clamp( f0 * exp( x * e ), 0., 1. );
}

float gaussian( float x, float mean, float sd ) {
  // TODO!
}

float hamming( float x, FIXME ) {
  // TODO!
}
