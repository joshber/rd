// Spectrogram class
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

import java.util.*; // ArrayDeque

import processing.sound.*;

// TODO
// Experiment with color map -- More darkness in the low end?
// A-weighting of SPL?

class Spectrogram {
  final float NYQUIST = 22050.;
    // No way to query AudioIn for sample rate, so we assume Fs == 44.1KHz
  final float log10 = log( 10. ); // For converting intensities to dB

  processing.sound.FFT fft;
  final int nbands = 256;
  final float bw = NYQUIST / nbands;

  float[] spectrum = new float[ nbands ];

  ArrayDeque<color[]> sg;
  final int nframes = 60;

  color[] colors;
  color centroidColor, spreadColor, indicatorColor;
  final int cr = 8; // color resolution, i.e., colors/decibel
  final float alpha = .75;
  final int xstretch = 2;

  boolean centroidp = false;
  boolean spreadp = false;

  // Avoid consing PVectors unnecessarily -- see draw() and spread()
  // NB, heycentroid is not threadsafe
  final PVector nocentroid = new PVector( 0., 1. );
  final PVector heycentroid = new PVector( 0., 0. );


  Spectrogram( PApplet instantiater, AudioIn in ) {
    fft = new processing.sound.FFT( instantiater, nbands );
    fft.input( in );

    buildColorMap();
    zeroOutSgQueue();
  }

  // Returns the spectral centroid, or 0 if we're not calculating the centroid
  // NB, When spreadp is true, no check to make sure centroidp is too. spread |= centroid
  float draw( int margin, boolean indicatorp ) {
    fft.analyze( spectrum );

    PVector sc = nocentroid;
    int centroidk = centroidp ? floor( ( sc = centroid() ).x / bw ) : -1;
    int spreadk = spreadp ? floor( spread( sc ) / bw ) : -1;

    // Add a new sample frame to the spectrogram
    color[] frame = new color[ nbands ];
    for ( int k = 0 ; k < nbands ; ++k ) {
      int dB = floor( cr * 10. * log( spectrum[ k ] / 1e-10 ) / log10 ); // Convert to decibels(*)
      frame[ k ] = k == centroidk ? centroidColor : k == spreadk ? spreadColor : colors[ min( max( 0, dB ), 120 * cr - 1 ) ];
      // (*) Actually cr·dB -- dB == 10·log10(intensity / 1e-12 W/m2). We use a cr·120-step color range, whence cr·
      // TODO: /1e-10. FFT seems to be using e-2 units. Scaling down yields more plausible dB values
    }

    sg.remove(); // Remove the oldest frame
    sg.add( frame );

    int i = 0;
    for ( int[] f : sg ) {
      float xoff = width - ( nframes * xstretch + margin ) + i * xstretch; // Draw from the left
      for ( int k = 0 ; k < nbands ; ++k ) {
        float yoff = height - k - margin; // Draw from the bottom
        fill( f[ k ] );
        rect( xoff, yoff, xstretch, 1 );
      }
      ++i;
    }

    // Draw an indicator strip below the spectrogram, e.g. for “Recording”
    if ( indicatorp ) {
      fill( indicatorColor );
      rect( width - ( nframes * xstretch + margin ), height - margin + 1, nframes * xstretch, 2 );
    }

    return sc.x;
  }

  // Spectral centroid
  // Returns a PVector so we can reuse the denominator if we're also calculating spectral spread
  PVector centroid() {
    float num = 0.;
    float den = 0.;
    for ( int k = 0 ; k < nbands ; ++k ) {
      float x = sqrt( spectrum[ k ] ); // |X(n,k)|
      num += ( k + .5 ) * bw * x; // Sum(f(k)·|X(n,k)|)
      den += x; // Sum(|X(n,k)|)
    }
    heycentroid.x = num / den;
    heycentroid.y = den;
    return heycentroid;
  }

  // Spectral spread
  float spread( PVector sc ) {
    float c = sc.x;
    float num = 0.;
    float den = sc.y; // Sum(|X(n,k)|)
    for ( int k = 0 ; k < nbands ; ++k ) {
      float x = sqrt( spectrum[ k ] ); // |X(n,k)|
      float diff = ( k + .5 ) * bw - c; // f(k) - SC
      num += diff * diff * x; // Sum((f(k) - SC)^2·|X(n,k)|)
    }
    return sqrt( num / den );
  }

  // Spectral flatness (tonality coefficient): [0,1] [pure tone, white noise]
  float flatness() {
    float num = 0.;
    float den = 0.;
    for ( int k = 0 ; k < nbands ; ++k ) {
      float x = sqrt( spectrum[ k ] ); // |X(n,k)|
      num += log( x ); // Sum(ln|X(n,k)|)
      den += x; // Sum(|X(n,k)|)
    }
    return nbands * exp( num / nbands ) / den;
  }
  // For when we already have the denominator handy
  float flatness( float den ) {
    float num = 0.;
    for ( int k = 0 ; k < nbands ; ++k ) {
      float x = sqrt( spectrum[ k ] ); // |X(n,k)|
      num += log( x ); // Sum(ln|X(n,k)|)
    }
    return nbands * exp( num / nbands ) / den;
  }

  //
  // Central moments and other heuristic measures

  float getCentroid( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    return centroid().x;
  }
  float getCentroid() {
    return getCentroid( true );
  }

  float getSpread( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    return spread( centroid() );
  }
  float getSpread() {
    return getSpread( true );
  }

  float getFlatness( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    return flatness();
  }
  float getFlatness() {
    return getFlatness( true );
  }

  PVector getCentroidSpreadFlatness( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    PVector sc = centroid();
    return new PVector( sc.x, spread( sc ), flatness( sc.y ) );
  }
  PVector getCentroidSpreadFlatness() {
    return getCentroidSpreadFlatness( true );
  }

  // Sound pressure level in dB, scaled to [0,1]
  // TODO: Check correctness
  float getSPL( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    float spl = 0.;
    for ( int k = 0 ; k < nbands ; ++k ) {
      spl += log( spectrum[ k ] / 1e-10 ) / log10;
    }
    return spl / ( 12. * nbands ); // /12: rescaling Bels to [0,1]
  }
  float getSPL() {
    return getSPL( true );
  }

  //
  // Initialization

  // To get a good-looking spectrogram, use stop colors
  void buildColorMap() {
    pushStyle();
    colorMode( HSB, 360., 1., 1., 1. );

    centroidColor = color( 180., 1., 1., 1. ); // CMY cyan, maximum brightness and opacity
    spreadColor = color( 120., 1., 1., 1. ); // RGB green, maximum brightness and opacity
    indicatorColor = color( 0., 1., .67, 1. ); // Red

    colors = new color[ 120 * cr + 1 ];
    colors[ 120 * cr ] = color( 0., 0., 1., 0. ); // Transparent, for special cases

    colorMapA();
    popStyle();
  }

  // Darker at the low end than previously
  void colorMapA() {
    // https://en.wikipedia.org/wiki/Spectrogram#/media/File:Spectrogram-19thC.png
    int i;

    // < 20dB: Black
    for ( i = 0 ; i < 20 * cr ; ++i )
      colors[ i ] = color( 0., 0., 0., alpha );

    // 20–39dB: Fade up to full brightness, hue set to blue
    for ( ; i < 40 * cr ; ++i )
      colors[ i ] = color( 240., 1., ( i - 20 * cr - 1 ) / ( 20. * cr ), alpha );

    // 40–89dB: Rotate from blue to yellow, maintaing full brightness
    for ( ; i < 90 * cr ; ++i )
      colors[ i ] = color( int( 240 + 180 * ( i - 40 * cr - 1 ) / ( 50. * cr ) ) % 360, 1., 1., alpha );
      // int( 240 + 180 * ( i - 40 * cr ) / ( 50. * cr ) ) % 360:
      // As i goes from 40cr to 89cr, we're rotating the hue through 180 degrees,
      // from blue to yellow, keeping saturation and brightness constant

    // 90–99dB: Hue stays at yellow, brightness at 1, saturation fades to 0 (i.e., white)
    for ( ; i < 100 * cr ; ++i )
      colors[ i ] = color( 60., ( i - 89 * cr - 1 ) / ( 10. * cr ), 1., alpha );

    // 100–120dB: White
    for ( ; i < 120 * cr ; ++i )
      colors[ i ] = color( 0., 0., 1., alpha );
  }

  void zeroOutSgQueue() {
    sg = new ArrayDeque<color[]>( nframes );
    for ( int i = 0 ; i < nframes ; ++i ) {
      color[] frame = new color[ nbands ];
      for ( int j = 0 ; j < nbands ; ++ j ) {
        frame[ j ] = colors[ 120 * cr ]; // transparent
      }
      sg.add( frame );
    }
  }

  //
  // Parameter handlers

  boolean drawCentroid() {
    return centroidp;
  }
  void drawCentroid( boolean p ) {
    centroidp = p;
  }

  boolean drawSpread() {
    return spreadp;
  }
  void drawSpread( boolean p ) {
    spreadp = p;
  }
}
