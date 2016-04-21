// rd: Audio-driven procedural video with reaction-diffusion models
// Inspired by Mark IJzerman
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

// TODO
// - *** Adjust sensitivity of beat detection
// - *** NEED A BETTER WAY TO DO LOG SPECTROGRAM
// - FFT windowing
// - Pass framerate to kernel to compensate, i.e., adjust dt to maintain constant speed in the R-D process?
// - Centroid in spectrogram
// - How can we make spectrogram frames independent of frame rate?

// TODO LATER
// - Signaling among instances -- PDEs for nonparametric zeitgeber?
// - Break out spectrogram as an AudioListener
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
final float log10 = log( 10. ); // For converting amplitudes to dB
//float fftBw; // FFT spectral bin bandwidth
BeatDetect beat;

// Spectrogram!
ArrayDeque<int[]> sg;
final int sgSize = 60;
final int sgFbins = 240; // Will be a little less for log spectrogram -- see displaySg()
color[] sgColor;
final float sgAlpha = .75;
boolean sgLog = false; // Logarithmic frequency axis?

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

// Does ambient sound influence the R-D process?
boolean actuateSpectral = false;
boolean actuateBeats = false;


void setup() {
  size( 1280, 720, P2D );
  //fullScreen( P2D /*FX2D*/, 1 );
  //pixelDensity( 2 );

  colorMode( RGB, 1. );
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
  // Reload shaders every 2s
  int fc = frameCount % 120;
  if ( fc == 60 ) {
    loadKernelShader();
  }
  else if ( fc == 119 ) {
    loadDisplayShaders( false ); // only reload the display shader currently in use
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

  // TODO: Experiment with windows
  fft = new FFT( in.bufferSize(), in.sampleRate() );
  fft.window( FFT.HAMMING );
  //fftBw = in.sampleRate() / in.bufferSize();

  beat = new BeatDetect();
  beatP = new PVector( 0., 0. );
  beatIntensity = 0.;
  beatRadius = 0.;

  //
  // Set up the spectrogram!

  sg = new ArrayDeque<int[]>( sgSize + 1 ); // +1: For when we've added a new frame but not yet removed the oldest

  //
  // To get a good-looking spectrogram, you need to use stop colors
  // TODO More dynamic range in the low end?

  sgColor = new color[ 240 ];
  int i;
  for ( i = 0 ; i < 20 ; ++i )
    sgColor[ i ] = color( 0., sgAlpha ); // < 10dB: black
  for ( ; i < 100 ; ++i )
    sgColor[ i ] = color( 0., 0., ( i - 19 ) / 80., sgAlpha ); // 10–49dB: black to blue
  for ( ; i < 140 ; ++i )
    sgColor[ i ] = color( ( i - 99 ) / 40., 0., ( 139 - i ) / 40., sgAlpha ); // 50–69dB: blue to red
  for ( ; i < 180 ; ++i )
    sgColor[ i ] = color( 1., ( i - 139 ) / 40., 0., sgAlpha ); // 70–89dB: red to yellow
  for ( ; i < 240 ; ++i )
    sgColor[ i ] = color( ( i - 179 ) / 60., 1., ( i - 179 ) / 60., sgAlpha ); // 90–120dB: yellow to white
}

// analyzeAudio()
// In the past we've used AudioListeners
// But doing it in the event loop might work just as well, since threading is not an issue
// In the interest of encapsulating audio-related stuff, this fn sets uniforms in the kernel shader
void analyzeAudio() {
  if ( actuateSpectral ) {
    // Just two bands, low and high, split around 10KHz (assuming sample freq of 44.1KHz)
    fft.linAverages( 2 );
    fft.forward( in.mix );
    float amp0 = fft.getAvg( 0 );
    float amp1 = fft.getAvg( 1 );

    //
    // Convert to Bels, then rescale to [0,1] ( · 10/120 or simply /12)
    // TODO: /1e-10 instead of 1e-12 bc it looks like Minim is returning amplitudes in e-2 units
    // -- scaling down two orders of magnitude yields more plausible dB values

    float db0 = clamp( log( amp0 * amp0 / 1e-10 ) / log10 / 12., 0., 1. );
    float db1 = clamp( log( amp1 * amp1 / 1e-10 ) / log10 / 12., 0., 1. );

    kernel.set( "sound", db0, db1, float( millis() ) );
  }
  else {
    // We pass in 60dB when there's no actuation to indicate “medium speed”
    kernel.set( "sound", .5, 0., 0. );
  }

  if ( actuateBeats ) {
    // Beat detection
    beat.detect( in.mix );
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
    kernel.set( "beat", beatP.x, beatP.y, beatIntensity, beatRadius );
  }
  else {
    kernel.set( "beat", 0., 0., 0., 0. );
  }
}

// displaySg()
// TODO Uncouple display width from spectrogram buffer size
// Atm, each entry in the queue represents data from a single draw() frame,
// and we simply draw the spectrogram that many pixels wide
void displaySg() {
  final int stretch = 5;

  resetShader();
  pushStyle();

  if ( sgLog )
    fft.logAverages( 11, sgFbins / 12 ); // Assumes Fs == 44.1KHz, so 12 octaves to Nyquist frequency
  else
    fft.linAverages( sgFbins );

  fft.forward( in.mix ); // compute newest spectrum

  // Add the newest spectrum to the spectrogram
  int[] frame = new int[ sgFbins ];
  int n = min( sgFbins, fft.avgSize() ); // We reuse this below
  for ( int i = 0 ; i < sgFbins ; ++i ) {
    if ( i < n ) {
      // TODO: /1e-10 instead of 1e-12 bc it looks like Minim is returning amplitudes in e-2 units
      // -- scaling down two orders of magnitude yields more plausible dB values
      float amp = fft.getAvg( i );
      int db2 = floor( 20. * log( amp * amp / 1e-10 ) / log10 ); // Convert to decibels(*)
      frame[ i ] = min( max( 0, db2 ), 239 );
      // (*) Actually 2·dB, which is 10·log10(intensity / 1e-12 W/m2). We use a 240-color range, so 2·
    }
    else
      frame[ i ] = 0;
      // if n < sgFbins (i.e., we're in log spectrum mode), zero out the fbin headroom in case we switch to linear
  }
  sg.add( frame );

  // If the queue has reached its maximum size, remove the oldest frame of frequency data
  if ( sg.size() > sgSize )
    sg.remove();

  int i = 0;
  for ( int[] f : sg ) {
    float xOffset = width - ( sgSize * stretch + 1.5 * olFsize ) + i * stretch; // Draw from the left
    for ( int k = 0 ; k < n ; ++k ) {
      float yOffset = height - 1.5 * olFsize - k; // Draw from the bottom
      fill( sgColor[ f[ k ] ] );
      rect( xOffset, yOffset, stretch, 1 );
    }
    ++i;
  }
  // If the spectrogram queue is empty and we have not yet filled the plot region, fill it out
  for ( ; i < sgSize ; ++i ) {
    float xOffset = width - ( sgSize * stretch + 1.5 * olFsize ) + i * stretch; // Draw from the left
    for ( int k = 0 ; k < n ; ++k ) {
      float yOffset = height - 1.5 * olFsize - k; // Draw from the bottom
      fill( 0., sgAlpha );
      rect( xOffset, yOffset, stretch, 1 );
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
  if ( key == 'A' ) {
    actuateSpectral = ! actuateSpectral;
  }
  else if ( key == 'B' ) {
    actuateBeats = ! actuateBeats;
  }
  else if ( '1' <= key && key <= '9' ) {
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
