// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// convolver.glsl: Apply a kernel to a frame of video

// TODO: Add distortion -- glitch, compression, blur ...

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_COLOR_SHADER

uniform sampler2D kernel;
uniform sampler2D frame;
uniform vec2 res; // viewport dimensions in pixels

//
// RGB-HSB conversion
// via http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
// cf. https://www.shadertoy.com/view/lsdGzN
// cf. https://www.shadertoy.com/view/4sS3Dc
// cf. http://www.chilliant.com/rgb2hsv.html

vec3 rgb2hsb( vec3 c ) {
    vec4 K = vec4( 0., -1. / 3., 2. / 3., -1. ) ;
    vec4 p = c.g < c.b ? vec4( c.bg, K.wz ) : vec4( c.gb, K.xy );
    vec4 q = c.r < p.x ? vec4( p.xyw, c.r ) : vec4( c.r, p.yzx );

    float d = q.x - min( q.w, q.y );
    float e = 1.e-10;
    return vec3( abs( q.z + ( q.w - q.y ) / ( 6. * d + e ) ), d / ( q.x + e ), q.x );
}

vec3 hsb2rgb( vec3 c ) {
    vec4 K = vec4( 1., 2. / 3., 1. / 3., 3. );
    vec3 p = abs( fract( c.xxx + K.xyz ) * 6. - K.www );
    return c.z * mix( K.xxx, clamp( p - K.xxx, 0., 1. ), c.y );
}

// End of color space converters
//

void main() {
  vec2 kuv = gl_FragCoord.xy / res;
  vec2 fuv = vec2( kuv.x, 1. - kuv.y ); // Processing inverts y-axis in video

  vec2 k = texture2D( kernel, kuv ).xy;
  vec3 c = rgb2hsb( texture2D( frame, fuv ).rgb );

  // TODO: Experiment with different ways of applying the kernel
  // - Rescale f, e.g. [-1,1]
  // - c.y * ( f.x + 1. ) ...
  // - fract( c.x * f.x ) -- apply to hue
  // - f = abs( log( abs( f ) ) )

  // Modify c components with f
  //c.x = fract( c.x + k.x );
  c.y = clamp( c.y * k.x, 0., 1. ); // Saturation
  c.z = clamp( c.z * k.y, 0., 1. ); // Brightness

  gl_FragColor = vec4( hsb2rgb( c ), 1. );

  // FIXME TODO: Implement a better color scheme for testing
  //gl_FragColor = vec4( k, 0., 1. );
}
