// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// FIXME TODO
// - Add feed/kill gradients back in
// - Toggle between video and G-S display -- 2 shaders?
// - h/v Blur for second-level kernel -- toroidal!
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

PGraphics kbuf, dummy;
Movie video;
int defaultFr = 60;

PShader kernel, convolve;
int kscale = 2; // larger == coarser-grained kernel

int brushRadius = 1<<3;

AudioContext ac;
ZeroCross zc;
PowerSpectrum ps;
SpectralPeaks sp;
SpectralCentroid sc;
SpectralDifference sd;
PeakDetector pd;
int nPeaks = 32;

PFont olFont;
float olFsize = 12.;


void setup() {
  size( 1280, 720, P2D );
  //fullScreen( P2D, 1 ); // TODO: Try FX2D renderer
  //pixelDensity( 2 );

  colorMode( HSB, 1. ); // TODO: HSB, 2pi, 1., 1.?
  frameRate( defaultFr );

  background( 0. );
  noStroke();

  //
  // Set up offscreen context for the kernel shader

  kbuf = createGraphics( width / kscale, height / kscale, P2D );
  kbuf.beginDraw();
  kbuf.colorMode( RGB, 1. );
  kbuf.background( color( 1., 0., 0. ) );
  kbuf.endDraw();

  // Stand-in for video during testing
  dummy = createGraphics( width, height, P2D );
  dummy.beginDraw();
  dummy.background( 0. );
  dummy.endDraw();

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

  // FIXME TODO: Use Analyzer class -- is it working?

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

  // Load font for overlay
  olFont = createFont( "fonts/InputSansCondensed-Black.ttf", olFsize, true ); // true==antialiasing
  textAlign( LEFT, TOP );

  // Load shaders
  loadKernelShader();
  brushOff();
  loadConvolveShader();

  // Start the video
  //video = new Movie( this, "video/JLT 12 04 2016.mov" );
  //video.loop();
}

void draw() {
  // Reload shaders every 1s
  int fc = frameCount % 60;
  if ( fc == 30 ) {
    loadKernelShader();
  }
  else if ( fc == 59 ) {
    loadConvolveShader();
  }

  //
  // Update the kernel in an offscreen buffer

  kernel.set( "kernel", kbuf );
  kernel.set( "brushP", float( mouseX / kscale ), float( ( height - mouseY ) / kscale ) );
    // 1 - height: Processing's y-axis is inverted wrt GLSL's

  kbuf.beginDraw();
  kbuf.shader( kernel );
  kbuf.rect( 0, 0, kbuf.width, kbuf.height );
  kbuf.endDraw();

  // FIXME TODO: A way to switch between video and dummy

  // Apply the kernel to the video (or show the kernel)
  convolve.set( "kernel", kbuf );
  convolve.set( "frame", dummy );
  shader( convolve );
  rect( 0, 0, width, height );
}

void loadKernelShader() {
  kernel = loadShader( "../shaders/grayscott.glsl" );
  kernel.set( "res", float( kbuf.width ), float( kbuf.height ) );
  kernel.set( "brushR", float( brushRadius ) );
}
void loadConvolveShader() {
  convolve = loadShader( "../shaders/convolve.glsl" );
  convolve.set( "res", float( width ), float( height ) );
}

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
}
