// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// FIXME TODO
// FIXME SEED THE GRID -- FROM AN IMAGE
// http://www.karlsims.com/rd.html
// Some typical values used, for those interested, are: DA=1.0, DB=.5, f=.055, k=.062
// (f and k vary for different behaviors), and Δt=1.0. The Laplacian is performed with a
// 3x3 convolution with center weight -1, adjacent neighbors .2, and diagonals .05.
// The grid is initialized with A=1, B=0, and a small area is seeded with B=1.

// FIXME DON'T PASS ANYTHING TO THE SHADERS --
// Handle all modification to parameters inside the shader. Just pass the frequency spectrum as a texture

// - Relationship between pixels[] and sampler2D might not be what you think -- bit order reversed?
// - TEST the hypothesis that a PGraphics won't work as the buffer -- doesn't sound right
// - Two-level Gray-Scott -- 10-20px and then 1px
// - Beads and API compliance? Switch to PSound? Investigate PSound API

import beads.*;
import processing.video.*;

PImage kBuf;
Movie vBuf;

PShader kernel, convolver;
PVector res;

AudioContext ac;
ZeroCross zc;
PowerSpectrum ps;
SpectralPeaks sp;
SpectralCentroid sc;
SpectralDifference sd;
PeakDetector pd;
int nPeaks = 32;

PFont overlayFont;
float overlayFontSize = 12.;


void setup() {
  size( 1192, 1080, P2D );
  //fullScreen( P2D, 1 ); // TODO: Try FX2D renderer
  //pixelDensity( 2 );

  colorMode( HSB, 1. ); // TODO: HSB, 2pi, 1., 1.?
  frameRate( 60. );

  background( 0. );
  noStroke();

  res = new PVector( width, height );
  loadKernelShader();
  loadConvolverShader();

  // FIXME FIXME TODO LOAD SEED KERNEL FROM IMAGE
  kBuf = createImage( width, height, RGB );
  kBuf.loadPixels();
  for ( int i = 0 ; i < kWidth * kHeight ; ++i ) {
    kBuf.pixels[ i ] = color( 1., 1., 0. );
  }
  kBuf.updatePixels();

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

  overlayFont = createFont( "fonts/InputSansCondensed-Black.ttf", overlayFontSize, true ); // true==antialiasing
  textAlign( LEFT, TOP );

  // Start the video
  //vBuf = new Movie( this, "video/Bastard Hypnotics.mov" );
  //vBuf.loop();
}

void draw() {
  // Reload shaders every 3s
  int fc = frameCount % 180;
  if ( fc == 179 ) {
    loadKernelShader();
  }

  // Draw to screen, then copy into the persistent buffer
  kernel.set( "kernel", kBuf );
  shader( kernel );
  rect( 0, 0, width, height );
  loadPixels();
  kBuf.loadPixels();
  for ( int i = 0 ; i < width * height ; ++i ) {
    kBuf.pixels[ i ] = pixels[ i ];
  }
  kBuf.updatePixels();

  //convolver.set( "kernel", kBuf );
  //convolver.set( "frame", vBuf );
  //shader( convolver );
  //rect( 0, 0, width, height );

  // TODO: Add a visualizer -- spectral peaks, power spectrum etc?
  // Maybe an instantaneous power spectrum up the righthand side--log freq vertical, power by hue, 180 to 0 degrees in HSB
}

void movieEvent( Movie m ) {
  m.read();
}

void loadKernelShader() {
  kernel = loadShader( "shaders/grayscott.glsl" );
  kernel.set( "res", res.x, res.y );
}
void loadConvolverShader() {
  convolver = loadShader( "shaders/convolver.glsl" );
  convolver.set( "res", res.x, res.y );
}
