// GLOBAL TODO:
// - Fix feed/kill and diffusion gradients with a texture (xyzw intensities = relative proportions)
// - Cycle through movies randomly selected from data/movies ?

import beads.*;
import processing.video.*;

PGraphics fBuf;
Movie vBuf;

PFont overlayFont;
int overlayFontSize = 12.;

PShader filterA, filterB, convolver;

AudioContext ac;
PowerSpectrum ps;
SpectralPeaks sp;
PeakDetector pd;
int nPeaks = 32;

void setup() {
  size( 1192, 1080, P2D );
  //fullScreen( P2D, 1 ); // TODO: Try FX2D renderer
  //pixelDensity( 2 );
  colorMode( RGB, 1. ); // TODO: HSB, 2pi, 1., 1.?

  background( 0. );
  noStroke();

  filterA = loadShader( "shaders/grayscott.glsl" );
  convolver = loadShader( "shaders/convolver.glsl" );

  PVector res = new PVector( width, height );
  filterA.set( "res", res.x, res.y );
  convolver.set( "res", res.x, res.y );

  // Filter starts empty. Feed/kill gradients ensure a pattern develops (see filter shader)
  fBuf = createGraphics( width, height, P2D );
  fBuf.beginDraw();
  fBuf.background( 0. );

  //
  // Set up audio in and analyzer

  ac = new AudioContext();

  Gain g = new Gain( ac, 2., .5 ); // TODO: What do gain parameters mean?
  ac.out.addInput( g );

  UGen mic = ac.getAudioInput();

  ShortFrameSegmenter sfs = new ShortFrameSegmenter( ac );
  // TODO: set sfs chunk size and hop size
  //sfs.setChunkSize( 1024 );
  //sfs.setHopSize( 441 );
  sfs.addInput( mic );

  FFT fft = new FFT();
  sfs.addListener( fft );

  ps = new PowerSpectrum();
  fft.addListener( ps );

  sp = new SpectralPeaks( ac, nPeaks );
  ps.addListener( sp );

  // Beat detection
  SpectralDifference sd = new SpectralDifference( ac.getSampleRate() );
  ps.addListener( sd );
  pd = new PeakDetector();
  sd.addListener( pd );
  // TODO: Add callback for beat event (Sonifying Processing, p. 116)

  ac.addDependent( sfs );
  ac.start();

  // Audio analysis is go!
  //

  overlayFont = createFont( "fonts/InputSansCondensed-Black.ttf", overlayFontSize, true ); // true==antialiasing
  textalign( LEFT, TOP );

  // Start the video
  vBuf = new Movie( this, "video/TK" );
  vBuf.loop();
}

void draw() {
  // TODO: Pass in parameters determined by audio in
  filterA.set( "feedkill", .01, 10., .2, 5. );
  filterA.set( "diffusion", 1., 0., 1., 0. );
  filterA.set( "dt", 1. );

  filterA.set( "filter", fBuf );
  shader( filterA );
  fBuf.rect( 0, 0, width, height );

  .set( "filter", fBuf );
  convolver.set( "frame", vBuf );
  shader( convolver );
  rect( 0, 0, width, height );

  // TODO: Add a visualizer -- spectral peaks, power spectrum etc?
  // Maybe an instantaneous power spectrum up the righthand side--log freq vertical, power by hue, 180 to 0 degrees in HSB
}

void movieEvent( Movie m ) {
  m.read();
}
