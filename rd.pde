// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// TODO
// - *** Pass in SPL 0-11KHz and 11-22KHz as a vec2, and spectral moments separately as a vec3
//   -- give yourself OPTIONS
// - REFACTOR -- Box the beat actuation stuff ... and then make Beads go away
// - GLITCH needs to be stateful across per-fragment shader calls -- set a position and a (small) radius, as with beat
//   Say, every random(6,60) frames, a new center, P, is chosen
//   Then, in the kernel shader, flatness is used as the coefficient
//   for some kind of subtle glitch centered on P
// - Tune video convolution

import processing.sound.*;
import processing.video.*;

//
// Rendering globals

PGraphics kbuf;
Movie video;
int fr = 60;

PShader kernel, convolve, noconvolve, display;
int kscale = 2; // larger == coarser-grained kernel

float brushIntensity = 0.;
int brushRadius = 1<<3;

//
// Audio globals

Spectrogram sg;
Beat beat;

// For actuating beats in the kernel
PVector beatP = new PVector( 0., 0. );
float beatIntensity = 0;
float beatRadius = 0;

//
// UI globals

PFont uiFont;
final float uiFsize = 12.;

// What appears in the viewport?
boolean showVideo = false;
boolean justVideo = false;
boolean showSpectrogram = false;
boolean showFramerate = false;

// Does ambient sound influence the R-D process?
boolean useSound = false;


void setup() {
  size( 1280, 720, P2D );
  //fullScreen( P2D /*FX2D*/, 1 );
  //pixelDensity( 2 );

  colorMode( RGB, 1. );
  frameRate( fr );

  background( 0. );
  noStroke();

  // Frame buffer for the reaction-diffusion kernel
  kbuf = createGraphics( width / kscale, height / kscale, P2D );
  kbuf.beginDraw();
  kbuf.colorMode( RGB, 1. );
  kbuf.background( color( 1., 0., 0. ) );
  kbuf.endDraw();

  // Load shaders
  loadKernelShader();
  loadDisplayShaders( true ); // true == load both

  // Load UI font
  uiFont = createFont( "fonts/InputSansCondensed-Black.ttf", uiFsize, true ); // true == antialiasing
  textFont( uiFont );
  textSize( uiFsize );
  textAlign( RIGHT, TOP );

  AudioIn in = new AudioIn( this, 0 );
  in.start();
  sg = new Spectrogram( this, in );
  sg.drawCentroid( true );
  sg.drawSpread( true );
  sg.getCentroid( true );
    // Make sure we've decomposed the signal at least once,
    // since analysis comes before drawing the spectrogram in draw()
  beat = new Beat();

  // Start the video
  video = new Movie( this, "video/JLT 12 04 2016.mov" );
  video.volume( 0 ); // FIXME Does this work? Not on OSX …
  video.loop();
}

void draw() {
  // Reload shaders every 2s
  int fc = frameCount % 120;
  if ( fc == 60 ) {
    loadKernelShader();
    sg.getCentroid( true );
      // TODO: For reasons unclear, we need to reprime the FFT after reloading the shader,
      // otherwise it drops a frame and V goes to extinction in the kernel
  }
  else if ( fc == 119 ) {
    loadDisplayShaders( false ); // only reload the display shader currently in use
  }

  analyzeAudio();

  kernel.set( "kernel", kbuf );
  kernel.set( "time", float( millis() ), frameRate );
  kernel.set( "brush", float( mouseX / kscale ), float( ( height - mouseY ) / kscale ), brushIntensity, brushRadius );
    // height - mouseY: Processing's y-axis is inverted wrt GLSL's

  // Update the kernel in an offscreen buffer
  kbuf.beginDraw();
  kbuf.shader( kernel );
  kbuf.rect( 0, 0, kbuf.width, kbuf.height );
  kbuf.endDraw();

  if ( ! justVideo ) {
    // Apply the kernel to the video or display the kernel itself
    display.set( "kernel", kbuf );
    if ( showVideo )
      display.set( "frame", video );
    shader( display );
    rect( 0, 0, width, height );
  }
  else {
    resetShader();
    image( video, 0, 0, width, height );
  }

  resetShader();
  if ( showSpectrogram ) sg.draw( 10, useSound );
  if ( showFramerate ) drawFramerate();
}

void analyzeAudio() {
  if ( ! useSound ) {
    kernel.set( "sound", .5, .5, 0., .1 );
    kernel.set( "beat", 0., 0., 0., 0. );
    return;
  }

  float spl = sg.getSPL( ! showSpectrogram );
  PVector csf = sg.getCentroidSpreadFlatness( false );

  if ( beat.isOnset() ) {
    beatIntensity = 1.;
    beatP.x = random( kbuf.width );
    beatP.y = random( kbuf.height );
    beatRadius = random( width / 20., width / 10. );
  }
  else {
    // Exponentional decay -- TODO Tune decay gamma
    beatIntensity = beatIntensity < .001 ? 0. : beatIntensity / 2.;
  }

  kernel.set( "sound", spl, csf.x / sg.NYQUIST, csf.y / sg.NYQUIST, csf.z );
  kernel.set( "beat", beatP.x, beatP.y, beatIntensity, beatRadius );
}

//
// UI overlays

void drawFramerate() {
  final float xoff = width - 10;
  final float yoff = 10;

  String fps = String.format( "%.2f fps", frameRate );

  // Drop shadow
  fill( 0., .5 );
  text( fps, xoff + 1, yoff + 1 );

  fill( 1., 1. );
  text( fps, xoff, yoff );
}

//
// Shader management

void loadKernelShader() {
  kernel = loadShader( "../shaders/grayscott.glsl" );
  kernel.set( "res", float( kbuf.width ), float( kbuf.height ) );
}
void loadDisplayShaders( boolean both ) {
  if ( both ) {
    convolve = loadShader( "../shaders/convolve.glsl" );
    convolve.set( "res", float( width ), float( height ) );
    noconvolve = loadShader( "../shaders/noconvolve.glsl" );
    noconvolve.set( "res", float( width ), float( height ) );
    display = showVideo ? convolve : noconvolve;
  }
  else if ( showVideo ) {
    convolve = loadShader( "../shaders/convolve.glsl" );
    convolve.set( "res", float( width ), float( height ) );
    display = convolve;
  }
  else {
    noconvolve = loadShader( "../shaders/noconvolve.glsl" );
    noconvolve.set( "res", float( width ), float( height ) );
    display = noconvolve;
  }
}

//
// Kernel management

void resetKernel() {
  kbuf.beginDraw();
  kbuf.background( color( 1., 0., 0., 1. ) );
  kbuf.endDraw();
}

//
// Event handlers

void movieEvent( Movie m ) {
  m.read();
}

void mouseDragged() {
  brushIntensity = 1.;
}
void mouseMoved() {
  brushIntensity = 0.;
}
void mouseReleased() {
  brushIntensity = 0.;
}

void keyPressed() {
  if ( key == 's' ) {
    useSound = ! useSound;
  }
  else if ( '1' <= key && key <= '2' ) {
    frameRate( 10 * ( int( key ) - int( '0' ) ) );
  }
  else if ( key == ' ' ) {
    frameRate( fr );
  }
  else if ( 'a' <= key && key <= 'f' ) {
    brushRadius = 1 << ( int( key ) - int( 'a' ) + 1 );
  }
  else if ( key == 'r' ) {
    resetKernel();
  }
  else if ( key == 'v' ) {
    showVideo = ! showVideo;
    display = showVideo ? convolve : noconvolve;
  }
  else if ( key == 'V' ) {
    justVideo = ! justVideo;
  }
  else if ( key == 'g' ) {
    showSpectrogram = ! showSpectrogram;
  }
  else if ( key == 'p' ) {
    showFramerate = ! showFramerate;
  }
}

//
// Utilities

float clamp( float x, float a, float b ) {
  return min( max( x, a ), b );
}
