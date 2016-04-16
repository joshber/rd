// rd: Audio-driven procedural video with reactiond-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// FIXME TODO
// - Brush aspect ratio
// - Toggle between video and G-S display -- toggle in convolver, not with dummy?

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
PGraphics dummy;
Movie video;
int defaultFr = 60;
String seedpath = "";

PShader kernel, convolve;
int kscale = 2;

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

  if ( ! seedpath.equals( "" ) ) {
    PImage seed = loadImage( "seeds/" + seedpath + ".png" );
    seed.loadPixels();
    offscreen = createGraphics( seed.width, seed.height, P2D );
    offscreen.beginDraw();
    offscreen.loadPixels();
    arrayCopy( seed.pixels, offscreen.pixels );
    offscreen.updatePixels();
    offscreen.endDraw();
  }
  else {
    offscreen = createGraphics( width / kscale, height / kscale, P2D );
    offscreen.beginDraw();
    offscreen.colorMode( RGB, 1. );
    offscreen.background( color( 1., 0., 0. ) );
    offscreen.endDraw();
  }

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
  // Reload shaders every 2s
  int fc = frameCount % 120;
  if ( fc == 60 ) {
    loadKernelShader();
  }
  else if ( fc == 119 ) {
    loadConvolveShader();
  }

  //
  // Update the kernel in an offscreen buffer

  kernel.set( "kernel", offscreen );
  kernel.set( "brushP", float( mouseX / kscale ), float( ( height - mouseY ) / kscale ) );
    // 1 - height: Processing's y-axis is inverted wrt GLSL's

  offscreen.beginDraw();
  offscreen.shader( kernel );
  offscreen.rect( 0, 0, offscreen.width, offscreen.height );
  offscreen.endDraw();

  // FIXME TODO: A way to switch between video and dummy

  // Apply the kernel to the video (or show the kernel)
  convolve.set( "kernel", offscreen );
  convolve.set( "frame", dummy );
  shader( convolve );
  rect( 0, 0, width, height );

  // TODO: Add a visualizer -- spectral peaks, power spectrum etc?
  // Maybe an instantaneous power spectrum up the righthand side--log freq vertical, power by hue, 180 to 0 degrees in HSB
}

void loadKernelShader() {
  kernel = loadShader( "shaders/grayscott.glsl" );
  kernel.set( "res", float( offscreen.width ), float( offscreen.height ) );
  kernel.set( "brushR", float( brushRadius ) );
}
void loadConvolveShader() {
  convolve = loadShader( "shaders/convolve.glsl" );
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
  offscreen.beginDraw();
  offscreen.background( color( 1., 0., 0., 1. ) );
  offscreen.endDraw();
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
