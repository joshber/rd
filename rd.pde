// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// TODO
// - Switch to Minim
// - Turn volume off with Minim
// *** VISUALIZER -- spectrogram! -- 256 freq bins
// - Low range power modulates dt
// - High range power adds small noise term to dt
// - On beats (power peaks), add a splotch to the kernel, brushI fades with exponential decay

// TODO LATER
// - Signaling among instances -- PDEs for nonparametric zeitgeber?
// - Implement Yang's algorithm -- two textures for the two sides of the kernel,
//   or use wz if it's possible to get it back to Processing safely
// - Unsupervised learning

import beads.*;
import processing.video.*;

//
// Rendering globals

PGraphics kbuf, dummy;
Movie video;
int defaultFr = 60;

PShader kernel, convolve, noconvolve, display;
int kscale = 2; // larger == coarser-grained kernel

int brushRadius = 1<<3;
float brushIntensity = 0.;

//
// Audio globals

AudioContext ac;
ZeroCross zc;
Power power;
PowerSpectrum ps;
SpectralDifference sd;
PeakDetector pd;

//
// Overlay and UI globals

PFont olFont;
float olFsize = 12.;

boolean showVideo = false;
boolean justVideo = false;
boolean showFr = false;


void setup() {
  size( 1280, 720, P2D );
  //fullScreen( P2D /*FX2D*/, 1 );
  //pixelDensity( 2 );

  colorMode( HSB, 1. );
  frameRate( defaultFr );

  background( 0. );
  noStroke();

  // Frame buffer for the reaction-diffusion kernel
  kbuf = createGraphics( width / kscale, height / kscale, P2D );
  kbuf.beginDraw();
  kbuf.colorMode( RGB, 1. );
  kbuf.background( color( 1., 0., 0. ) );
  kbuf.endDraw();

  // Stand-in for video during testing
  dummy = createGraphics( width, height, P2D );
  dummy.beginDraw();
  dummy.background( color( 1. ) ); // 1: So that we'll still see an image with convolve
  dummy.endDraw();

  // Load shaders
  loadKernelShader();
  loadDisplayShaders( true ); // true == load both

  //
  // Set up audio in and analyzer

  ac = new AudioContext();
  float sampleRate = ac.getSampleRate();

  UGen mic = ac.getAudioInput();

  ShortFrameSegmenter sfs = new ShortFrameSegmenter( ac );
  // TODO: Tweak chunk size and hop size? setChunkSize() setHopSize()
  sfs.addInput( mic );

  zc = new ZeroCross( ac, 100. ); // 100ms frame
  zc.addInput( sfs ); // FIXME -- NOT WORKING

  power = new Power();
  sfs.addListener( power );

  FFT fft = new FFT();
  sfs.addListener( fft );

  ps = new PowerSpectrum();
  fft.addListener( ps );

  sd = new SpectralDifference( sampleRate );
  ps.addListener( sd );

  // Beat detection
  ps.addListener( sd );
  pd = new PeakDetector();
  sd.addListener( pd );
  // TODO: Set threshold and alpha, add beat callback (Sonifying Processing, p. 116)

  ac.out.addDependent( sfs );
  ac.start();

  // Audio analysis is go!
  //

  // Load font for overlay
  olFont = createFont( "fonts/InputSansCondensed-Black.ttf", olFsize, true ); // true == antialiasing
  textAlign( RIGHT, TOP );

  // Start the video
  video = new Movie( this, "video/JLT 12 04 2016.mov" );
  // FIXME Disable audio? video.volume( 0 ) does not work
  video.loop();
}

void draw() {
  // Reload shaders every 1s
  int fc = frameCount % 60;
  if ( fc == 30 ) {
    loadKernelShader();
  }
  else if ( fc == 59 ) {
    loadDisplayShaders( false );
  }

  //
  // Update the kernel in an offscreen buffer

  kernel.set( "kernel", kbuf );
  kernel.set( "brushI", brushIntensity );
  kernel.set( "brushP", float( mouseX / kscale ), float( ( height - mouseY ) / kscale ) ); // (*)
    // (*) height - mouseY: Processing's y-axis is inverted wrt GLSL's

  kbuf.beginDraw();
  kbuf.shader( kernel );
  kbuf.rect( 0, 0, kbuf.width, kbuf.height );
  kbuf.endDraw();

  if ( justVideo ) {
    resetShader();
    image( video, 0, 0, width, height );
  }
  else {
    // Apply the kernel to the video or display the kernel itself
    display.set( "kernel", kbuf );
    if ( showVideo )
      display.set( "frame", video );
      shader( display );
      rect( 0, 0, width, height );
  }

  if ( showFr ) displayFr(); // display framerate
}

//
// Overlays

void displayFr() {
  String fps = String.format( "%.2f fps", frameRate );

  resetShader();
  pushStyle();

  textFont( olFont );
  textSize( olFsize );
  textAlign( RIGHT, TOP );
  float xEdge = width - 1.5 * olFsize;

  // Drop shadow
  translate( 1., 1. );
  fill( 0., .5 );
  text( fps, xEdge, 1.5 * olFsize );
  translate( -1., -1. );

  fill( 1., 1. ); // text color
  text( fps, xEdge, 1.5 * olFsize );

  popStyle();
}

//
// Shader management

void loadKernelShader() {
  kernel = loadShader( "../shaders/grayscott.glsl" );
  kernel.set( "res", float( kbuf.width ), float( kbuf.height ) );
  kernel.set( "brushR", float( brushRadius ) );
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

void setBrushRadius( int i ) {
  brushRadius = 1 << i;
  kernel.set( "brushR", float( brushRadius ) );
}
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
  if ( '1' <= key && key <= '9' ) {
    frameRate( int( key ) - int( '0' ) );
  }
  else if ( key == ' ' ) {
    frameRate( defaultFr );
  }
  else if ( 'a' <= key && key <= 'f' ) {
    setBrushRadius( int( key ) - int( 'a' ) + 1 );
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
  else if ( key == 'p' ) {
    showFr = ! showFr;
  }
}

//
// Utilities

float clamp( float x, float a, float b ) {
  return min( max( x, a ), b );
}
