// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// FIXME TODO
// - REINTRODUCE scaling factor -- width/offscreen.width
// - ADD audio-drivenness

// TODO LATER
// - Two-level Gray-Scott -- 10-20px and then 1px
// - Beads and API compliance? Switch to PSound? Investigate PSound API
// Power spectrum visualizer + fps

import beads.*;
import processing.video.*;

PGraphics offscreen;
Movie video;

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
  frameRate( 60 );

  background( 0. );
  noStroke();

  //
  // Set up offscreen context for the kernel shader
  // Seed the kernel

  PImage seed = loadImage( "seeds/seed 2.jpg" );
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
  if ( fc == 119 ) {
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

void loadKernelShader() {
  kernel = loadShader( "shaders/grayscott.glsl" );
  kernel.set( "res", float( offscreen.width ), float( offscreen.height ) );
}
void loadConvolverShader() {
  convolver = loadShader( "shaders/convolver.glsl" );
  convolver.set( "kres", float( offscreen.width ), float( offscreen.height ) );
  convolver.set( "fres", float( width ), float( height ) );
}
