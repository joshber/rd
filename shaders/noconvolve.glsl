// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// noconvolve.glsl: Display a kernel, no convolution with a video frame

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

uniform sampler2D kernel;
uniform vec2 res; // viewport dimensions in pixels

//
// RGB-HSB conversion
// via http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
// cf. https://www.shadertoy.com/view/lsdGzN
// cf. https://www.shadertoy.com/view/4sS3Dc
// cf. http://www.chilliant.com/rgb2hsv.html

vec3 rgb_hsb( vec3 c ) {
    vec4 K = vec4( 0., -1. / 3., 2. / 3., -1. ) ;
    vec4 p = c.g < c.b ? vec4( c.bg, K.wz ) : vec4( c.gb, K.xy );
    vec4 q = c.r < p.x ? vec4( p.xyw, c.r ) : vec4( c.r, p.yzx );

    float d = q.x - min( q.w, q.y );
    float e = 1.e-10;
    return vec3( abs( q.z + ( q.w - q.y ) / ( 6. * d + e ) ), d / ( q.x + e ), q.x );
}

vec3 hsb_rgb( vec3 c ) {
    vec4 K = vec4( 1., 2. / 3., 1. / 3., 3. );
    vec3 p = abs( fract( c.xxx + K.xyz ) * 6. - K.www );
    return c.z * mix( K.xxx, clamp( p - K.xxx, 0., 1. ), c.y );
}

// End of color space converters
//

void main() {
  vec2 uv = gl_FragCoord.xy / res;
  vec2 k = texture2D( kernel, uv ).xy;

  //
  // Display the reaction-diffusion pattern

  // HSB target ranges
  float hfloor = .3;
  float hceil = 1.;
  float sfloor = .5;
  float sceil = 1.;
  float bfloor = .2;
  float bceil = 1.;

  vec3 c;
  c.x = k.y * ( hceil - hfloor ) + hfloor;
  c.y = k.y * ( sceil - sfloor ) + sfloor;
  c.z = k.y * ( bceil - bfloor ) + bfloor;

  gl_FragColor = vec4( hsb_rgb( c ), 1. );
}
