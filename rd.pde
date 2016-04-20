// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// TODO
// - *** How can we make spectrogram frames independent of frame rate?
// - *** How can we reduce latency?
// - *** Beat splotching is waaay too sensitive. Need to raise thresholds
// - Low range power modulates dt
// - High range power adds small noise term to dt
// - FFT windowing

// TODO LATER
// - Signaling among instances -- PDEs for nonparametric zeitgeber?
// - Implement Yang's algorithm -- two textures for the two sides of the kernel,
//   or use wz if it's possible to get it back to Processing safely
// - Unsupervised learning

import java.util.*; // ArrayDeque

import ddf.minim.*;
import ddf.minim.analysis.*;

import processing.video.*;

//
// Rendering globals

PGraphics kbuf;
Movie video;
int defaultFr = 60;

PShader kernel, convolve, noconvolve, display;
int kscale = 2; // larger == coarser-grained kernel

float brushIntensity = 0.;
int brushRadius = 1<<3;

//
// Audio globals

Minim minim;
AudioInput in;
FFT fft;
float fftBw; // FFT spectral bin bandwidth
BeatDetect beat;

ArrayDeque<float[]> sg; // spectrogram
int sgSize;
int sgFbins;
boolean sgLog;

// For actuating beats in the kernel
PVector beatP;
float beatIntensity, beatRadius;

//
// UI globals

PFont olFont;
float olFsize = 12.;

boolean showVideo = false;
boolean justVideo = false;
boolean showSg = false;
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

  // Load shaders
  loadKernelShader();
  loadDisplayShaders( true ); // true == load both

  // Load font for overlay
  olFont = createFont( "fonts/InputSansCondensed-Black.ttf", olFsize, true ); // true == antialiasing
  textAlign( RIGHT, TOP );

  setupAudio();

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

  analyzeAudio();

  kernel.set( "kernel", kbuf );
  kernel.set( "brush", float( mouseX / kscale ), float( ( height - mouseY ) / kscale ), brushIntensity, brushRadius );
    // height - mouseY: Processing's y-axis is inverted wrt GLSL's

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

  if ( showSg ) displaySg(); // display spectrogram
  if ( showFr ) displayFr(); // display framerate
}

//
// Audio-related

void setupAudio() {
  minim = new Minim( this );
  in = minim.getLineIn();
  fft = new FFT( in.bufferSize(), in.sampleRate() );
  println( fft.specSize() );
  fftBw = in.sampleRate() / in.bufferSize();
  beat = new BeatDetect();
  beatP = new PVector( 0., 0. );
  beatIntensity = 0.;
  beatRadius = 0.;

  sgSize = 60;
  sgFbins = 240; // Will be 220 for log spectrogram -- see displaySg()
  sgLog = false;
  sg = new ArrayDeque<float[]>( sgSize + 1 ); // +1: For when we've added a new frame but not yet removed the oldest
}

// analyzeAudio()
// In the past we've used AudioListeners
// But doing it in the event loop might work just as well, since threading is not an issue
// In the interest of encapsulating audio-related stuff, this fn sets uniforms in the kernel shader
void analyzeAudio() {
  // Power spectrum
  fft.logAverages( 10000, 1 ); // min bandwidth == 10KHz (in practice, just two bands at the moment)
  fft.forward( in.mix );

  // Beat detection
  beat.detect( in.mix );
  if ( beat.isOnset() ) {
    beatIntensity = random( 1., 2. );
    beatP.x = random( kbuf.width );
    beatP.y = random( kbuf.height );
    beatRadius = random( width / 20., width / 8. );
  }
  else {
    // Exponentional decay
    beatIntensity = beatIntensity < .001 ? 0. : beatIntensity / 2.; // FIXME TUNE DECAY RATE!
  }

  // Update kernel uniforms
  kernel.set( "power", fft.getAvg( 0 ), fft.getAvg( 1 ), millis() );
  kernel.set( "beat", beatP.x, beatP.y, beatIntensity, beatRadius );
}

// displaySg()
// TODO Uncouple display width from spectrogram buffer size
// Atm, each entry in the queue represents data from a single draw() frame,
// and we simply draw the spectrogram that many pixels wide
void displaySg() {
  resetShader();
  pushStyle();

  if ( sgLog )
    fft.logAverages( 11, sgFbins / 12 ); // Assumes Fs == 44.1KHz, so 12 octaves to Nyquist frequency
  else
    fft.linAverages( sgFbins );

  fft.forward( in.mix ); // compute newest power spectrum

  // Add the newest power spectrum to the spectrogram
  float[] frame = new float[ sgFbins ]; // FIXME: (*)
  int n = min( sgFbins, fft.avgSize() ); // We reuse this below
  for ( int i = 0 ; i < sgFbins ; ++i ) {
    frame[ i ] = i < n ? fft.getAvg( i ) : 0.;
  }
  sg.add( frame );

  // If the queue has reached its maximum size, remove the oldest frame of frequency data
  if ( sg.size() > sgSize )
    sg.remove();

  // Hue and brightness vary by power
  float hfloor = .5;
  float hceil = 1.;
  float bfloor = .5;
  float bceil = 1.;

  int i = 0;
  for ( float[] f : sg ) {
    float xOffset = width - ( sgSize + 1.5 * olFsize ) + i; // Draw from the left
    for ( int k = 0 ; k < n ; ++k ) {
      float yOffset = height - 1.5 * olFsize - k; // Draw from the bottom
      float pow = f[ k ];
      float h = pow * ( hceil - hfloor ) + hfloor;
      float b = pow * ( bceil - bfloor ) + bfloor;
      fill( h, 1., b, .75 ); // Show the power
      rect( xOffset, yOffset, 1, 1 );
    }
    ++i;
  }
  // If the spectrogram queue is empty and we have not yet filled the plot region, fill it out
  for ( ; i < sgSize ; ++i ) {
    float xOffset = width - ( sgSize + 1.5 * olFsize ) + i; // Draw from the left
    for ( int k = 0 ; k < n ; ++k ) {
      float yOffset = height - 1.5 * olFsize - k; // Draw from the bottom
      fill( 0., .75 ); // FIXME COLOR No data to show
      rect( xOffset, yOffset, 1, 1 );
    }
  }

  popStyle();
}

//
// Additional UI overlays

void displayFr() {
  String fps = String.format( "%.2f fps", frameRate );

  resetShader();
  pushStyle();

  textFont( olFont );
  textSize( olFsize );
  textAlign( RIGHT, TOP );
  float xOffset = width - 1.5 * olFsize;
  float yOffset = 1.5 * olFsize;

  // Drop shadow
  translate( 1., 1. );
  fill( 0., .5 );
  text( fps, xOffset, yOffset );
  translate( -1., -1. );

  fill( 1., 1. ); // text color
  text( fps, xOffset, yOffset );

  popStyle();
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
  if ( '1' <= key && key <= '9' ) {
    frameRate( int( key ) - int( '0' ) );
  }
  else if ( key == ' ' ) {
    frameRate( defaultFr );
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
  else if ( key == 'p' ) {
    showFr = ! showFr;
  }
  else if ( key == 'g' ) {
    showSg = ! showSg;
  }
  else if ( key == 'G' ) {
    sgLog = ! sgLog;
  }
}

//
// Utilities

float clamp( float x, float a, float b ) {
  return min( max( x, a ), b );
}
