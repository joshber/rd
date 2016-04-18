// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// FIXME TODO
// - h/v Blur for second-level kernel -- toroidal!
// - Add feed/kill gradients back in
// - Abstract UI signals from keyPressed()
// - (Log-binned?) power spectrum visualizer + spectral peaks + zero crossings + fps
//   -- do it with a shader, just draw it on parts of the screen

// - Add audio-drivenness
// - On beats (spectral peaks), add a splotch to the kernel?

// TODO LATER
// - Signaling among instances -- PDEs for nonparametric zeitgeber?
// - Unsupervised learning
// - Beads and API compliance? Switch to PSound? Investigate PSound API

import beads.*;
import processing.video.*;

//
// Rendering globals

PGraphics kbuf, bbuf, dummy;
Movie video;
int defaultFr = 60;

PShader kernel, blurX, blurY, convolve, noconvolve, display;
int kscale = 2; // larger == coarser-grained kernel

int brushRadius = 1<<3;
boolean twoLevel = false;
float kWeight = .99; // relative weight of kernel levels 1 and 2, when two-level kernel is enabled

//
// Audio globals

AudioContext ac;
ZeroCross zc;
PowerSpectrum ps;
SpectralPeaks sp;
SpectralCentroid sc;
SpectralDifference sd;
PeakDetector pd;
int nPeaks = 32;

//
// Overlay and UI globals

PFont olFont;
float olFsize = 12.;

boolean showVideo = false;
boolean showFr = false;


void setup() {
  size( 1280, 720, P2D );
  //fullScreen( P2D /*FX2D*/, 1 );
  //pixelDensity( 2 );

  colorMode( HSB, 1. ); // TODO: HSB, 2pi, 1., 1.?
  frameRate( defaultFr );

  background( 0. );
  noStroke();

  //
  // Set up an offscreen context for the kernel shader

  // Frame buffer for the reaction-diffusion kernel
  kbuf = createGraphics( width / kscale, height / kscale, P2D );
  kbuf.beginDraw();
  kbuf.colorMode( RGB, 1. );
  kbuf.background( color( 1., 0., 0. ) );
  kbuf.endDraw();

  // Frame buffer to blur kbuf for a second, coarser-grained reaction-diffusion process
  bbuf = createGraphics( width / kscale, height / kscale, P2D );
  bbuf.beginDraw();
  bbuf.colorMode( RGB, 1. );
  bbuf.background( color( 0. ) );
  bbuf.endDraw();

  // Stand-in for video during testing
  dummy = createGraphics( width, height, P2D );
  dummy.beginDraw();
  dummy.background( color( 1. ) ); // 1: So that we'll still see an image with convolve
  dummy.endDraw();

  // Rendering context is go!
  //

  //
  // Set up audio in and analyzer

  ac = new AudioContext();
  float sampleRate = ac.getSampleRate();

  UGen mic = ac.getAudioInput();

  ShortFrameSegmenter sfs = new ShortFrameSegmenter( ac );
  // TODO: set sfs chunk size and hop size
  //sfs.setChunkSize( 1024 );
  //sfs.setHopSize( 441 );
  sfs.addInput( mic );

  zc = new ZeroCross( ac, 200. ); // 200ms frame

  FFT fft = new FFT();
  sfs.addListener( fft );

  ps = new PowerSpectrum();
  fft.addListener( ps );

  sp = new SpectralPeaks( ac, nPeaks );
  ps.addListener( sp );

  sc = new SpectralCentroid( sampleRate );
  ps.addListener( sc );

  sd = new SpectralDifference( sampleRate );
  ps.addListener( sd );

  // Beat detection
  SpectralDifference sd = new SpectralDifference( ac.getSampleRate() );
  ps.addListener( sd );
  pd = new PeakDetector();
  sd.addListener( pd );
  // TODO: Add callback for beat event (Sonifying Processing, p. 116)

  ac.out.addDependent( sfs );
  ac.start();

  // Audio analysis is go!
  //

  //
  // Load shaders

  loadKernelShader();
  brushOff();
  loadDisplayShaders( true ); // true == load both

  // These get loaded just once
  blurX = loadShader( "../shaders/blurX.glsl" );
  blurY = loadShader( "../shaders/blurY.glsl" );
  blurX.set( "res", float( width / kscale ), float( height / kscale ) );
  blurY.set( "res", float( width / kscale ), float( height / kscale ) );

  // Load font for overlay
  olFont = createFont( "fonts/InputSansCondensed-Black.ttf", olFsize, true ); // true == antialiasing
  textAlign( RIGHT, TOP );

  // Start the video
  //video = new Movie( this, "video/JLT 12 04 2016.mov" );
  // FIXME Disable audio? video.volume( 0 ) does not work
  //video.loop();
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

  // FIXME FIXME CHECK -- Not working, might be here
  if ( twoLevel ) {
    blurX.set( "kernel", kbuf );
    bbuf.beginDraw();
    bbuf.shader( blurX );
    bbuf.rect( 0, 0, bbuf.width, bbuf.height );

    blurY.set( "blurX", bbuf );
    bbuf.shader( blurY );
    bbuf.rect( 0, 0, bbuf.width, bbuf.height );
    bbuf.endDraw();
  }

  kernel.set( "kernel", kbuf );
  kernel.set( "blur", bbuf );
  kernel.set( "brushP", float( mouseX / kscale ), float( ( height - mouseY ) / kscale ) ); // (*)
    // (*) height - mouseY: Processing's y-axis is inverted wrt GLSL's

  kbuf.beginDraw();
  kbuf.shader( kernel );
  kbuf.rect( 0, 0, kbuf.width, kbuf.height );
  kbuf.endDraw();

  // Apply the kernel to the video or display the kernel itself
  display.set( "kernel", kbuf );
  if ( showVideo )
    display.set( "frame", dummy );
  shader( display );
  rect( 0, 0, width, height );

  // FIXME VISUALIZER SHADER

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
  kernel.set( "weight", twoLevel ? kWeight : 1. );
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

void brushOff() {
  kernel.set( "brush", false );
}
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
  kernel.set( "brush", true );
}
void mouseMoved() {
  brushOff();
}
void mouseReleased() {
  brushOff();
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
  else if ( key == '#' ) {
    twoLevel = ! twoLevel;
    kernel.set( "weight", twoLevel ? kWeight : 1. );
  }
  else if ( key == 'v' ) {
    showVideo = ! showVideo;
    display = showVideo ? convolve : noconvolve;
  }
  else if ( key == 'p' ) {
    showFr = ! showFr;
  }
}
