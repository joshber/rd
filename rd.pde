// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// FIXME TODO
// - SOMETHING is still not right with my algorithm -- I'm not getting the kinds of patterns I should be
// TO TRY
// - Go back to drawing to the screen, temporarily
// ??

// - Convert video frame to G-S input: http://mrob.com/pub/comp/screensavers/
// - OR, use the video frame for feed and kill rates, as MRob does

// - ADD audio-drivenness
// - On beats (spectral peaks), add a splotch to the kernel?
// - Multiple scales -- try scale factor in kernel shader,
//   calculate 2 Laplacians at different scales (different px, scale factor)

// TODO LATER
// - Beads and API compliance? Switch to PSound? Investigate PSound API
// - Power spectrum visualizer + fps
// McCabe's algorithm?

import beads.*;
import processing.video.*;

PGraphics offscreen;
Movie video;
int defaultFr = 60;

PShader kernel, convolver;

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
  size( 1280, 720, P2D );
  //fullScreen( P2D, 1 ); // TODO: Try FX2D renderer
  //pixelDensity( 2 );

  colorMode( HSB, 1. ); // TODO: HSB, 2pi, 1., 1.?
  frameRate( defaultFr );

  background( 0. );
  noStroke();

  //
  // Set up offscreen context for the kernel shader
  // Seed the kernel

  PImage seed = loadImage( "seeds/seed11.png" );
  seed.loadPixels();
  offscreen = createGraphics( seed.width, seed.height, P2D );
  offscreen.beginDraw();
  offscreen.loadPixels();
  arrayCopy( seed.pixels, offscreen.pixels );
  offscreen.updatePixels();
  offscreen.endDraw();

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

  // Load shaders
  loadKernelShader();
  loadConvolverShader();

  // Start the video
  video = new Movie( this, "video/JLT 12 04 2016.mov" );
  video.loop();
}

void draw() {
  // Reload shaders every 2s
  int fc = frameCount % 120;
  if ( fc == 60 ) {
    loadKernelShader();
  }
  else if ( fc == 119 ) {
    loadConvolverShader();
  }

  // Update the kernel in an offscreen buffer
  kernel.set( "kernel", offscreen );
  offscreen.beginDraw();
  offscreen.shader( kernel );
  offscreen.rect( 0, 0, offscreen.width, offscreen.height );
  offscreen.endDraw();

  // Apply the kernel to the video
  convolver.set( "kernel", offscreen );
  convolver.set( "frame", video );
  shader( convolver );
  rect( 0, 0, width, height );

  // TODO: Add a visualizer -- spectral peaks, power spectrum etc?
  // Maybe an instantaneous power spectrum up the righthand side--log freq vertical, power by hue, 180 to 0 degrees in HSB
}

void movieEvent( Movie m ) {
  m.read();
}

void keyPressed() {
  if ( '1' <= key && key <= '9' ) {
    frameRate( int( key ) - int( '0' ) );
  }
  else if ( key == ' ' ) {
    frameRate( defaultFr );
  }
  // FIXME TODO: OPTION TO RESEED KERNEL
}

void loadKernelShader() {
  kernel = loadShader( "shaders/grayscott.glsl" );
  kernel.set( "res", float( offscreen.width ), float( offscreen.height ) );
}
void loadConvolverShader() {
  convolver = loadShader( "shaders/convolver.glsl" );
  convolver.set( "res", float( width ), float( height ) );
}
