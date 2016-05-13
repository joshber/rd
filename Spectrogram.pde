// Spectrogram class
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

import java.util.*; // ArrayDeque

import processing.sound.*;

// TODO
// Spectral flux onset recognition needs further burn-in
// - Is implementation of g correct?
// - TRY DIFFERENT DEFAULT ALPHA (.9?)
// Experiment with color map -- More darkness in the low end?
// SPL: A-weighting?


class SpectrogramFFTLoop implements Runnable {
  Spectrogram sg;

  SpectrogramFFTLoop( Spectrogram invoker ) {
    sg = invoker;
  }

  public void run() {
    try {
      while ( true ) {
        if ( sg.isPaused() ) return;

        sg.computeFrame();

        Thread.sleep( 10 ); // Aiming for 60fps
          // If it's too close to Animation thread frame rate (i.e., sleep( 17 ))
          // you get aliasing in the form of judder in the spectrogram animation
      }
    }
    catch ( InterruptedException e ) {
      println( "SpectrogramFFTLoop interrupted: " + e );
    }
  }
}

class Spectrogram {
  final float NYQUIST = 22050.;
    // No way to query AudioIn for sample rate, so we assume Fs == 44.1KHz
  final float log10 = log( 10. ); // For converting intensities to dB

  FFT fft;
  final int nbands = 256;
  final float bw = NYQUIST / nbands;

  float[] spectrum = new float[ nbands ];
  float[] prevSpectrum = new float[ nbands ];

  // Spectrogram
  ArrayDeque<color[]> sg;
  final int nframes = 60;

  //
  // Color mapping

  color[] colors;
  color centroidColor, spreadColor, indicatorColor;
  final int cr = 8; // color resolution, i.e., colors/decibel
  final float alpha = .75;
  final int xstretch = 2;

  //
  // Spectrogram options

  boolean centroidp = false;
  boolean spreadp = false;

  // Avoid consing PVectors unnecessarily -- see computeFrame(), draw() and spread()
  // NB, heycentroid and spl are not threadsafe
  final PVector nocentroid = new PVector( 0., 1. );
  final PVector heycentroid = new PVector( 0., 1. );
  final PVector spl = new PVector( 0., 0. );

  //
  // Spectral flux (for beat detection)

  ArrayDeque<float[]> flux;
  final int sfpulse = 13;
    // Spectral flux pulse width: How many sample frames do we need to detect an onset?
    // Radius of [-9,3], so 13 frames altogether
    // Less expensive than methods that require taking variance over 500–1000ms of flux

  // For quick traversal in isOnset()
  float[] fluxary = new float[ sfpulse ];

  float threshold;
  float alphaThreshold;
  float gAlpha;
    // Second threshold function (see isOnset() ): g(n) = max( SF(n), alpha·g(n - 1) + (1 - alpha)·SF(n) )

  //
  // Background threading

  Thread fftThread;
  boolean paused;


  Spectrogram( PApplet instantiater ) {
    AudioIn in = new AudioIn( instantiater, 0 );
    in.start();

    fft = new FFT( instantiater, nbands );
    fft.input( in );

    buildColorMap();
    initializeSgQueue();
    initializeFluxQueue();
    resetThresholds();

    start();
  }

  //
  // Handle background threading

  void start() {
    fftThread = new Thread( new SpectrogramFFTLoop( this ), "Spectrogram FFT Thread" );
    restart();
  }
  void restart() {
    paused = false;
    fftThread.start();
  }
  void pause() {
    paused = true;
  }
  boolean isPaused() {
    return paused;
  }

  //
  // Analysis

  // computeFrame: Computes one new frame of the plot
  // Updates the centroid measure if centroidp == true
  // Tail-calls computeFlux()
  // NB, When spreadp is true, no check to make sure centroidp is too. spread |= centroid,
  // so spreadp && !centroidp yields unreliable results for spread
  synchronized void computeFrame() {
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

    heycentroid.x = sc.x;
    heycentroid.y = sc.y;

    computeFlux();
  }

  // computeFlux: Computes one frame of spectral flux
  synchronized void computeFlux() {
    float accum = 0.;
    for ( int k = 0 ; k < nbands ; ++k ) {
      float fk = spectrum[ k ];
      float diff = fk - prevSpectrum[ k ];
      diff = .5 * ( diff + abs( diff ) ); // Half-wave rectifier
      accum += diff;
      prevSpectrum[ k ] = fk; // X(n) becomes the comparandum for X(n+1)
    }

    // Normalize spectral flux to a Gaussian with mean 0, sd 1, clamped to six sigma
    accum = clamp( exp( accum * accum / 4. ), -6., 6. );

    // Add a frame to the running average
    float[] frame = new float[ 1 ];
    frame[ 0 ] = accum;
    flux.remove();
    flux.add( frame );
  }

  //
  // Draw the spectrogram!
  // Returns the spectral centroid, or 0 if we're not calculating the centroid

  synchronized float draw( int margin ) {
    return draw( margin, false );
  }
  synchronized float draw( int margin, boolean indicatorp ) {
    if ( isPaused() )
      return 0.;

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

    return heycentroid.x; // heycentroid gets set in computeFrame()
  }

  //
  // Central moments and other heuristic measures

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
  // Public-facing accessors for central moments, spectral flatness, and SPL

  synchronized float getCentroid( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    return centroid().x;
  }
  synchronized float getCentroid() {
    return getCentroid( paused );
  }

  synchronized float getSpread( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    return spread( centroid() );
  }
  synchronized float getSpread() {
    return getSpread( paused );
  }

  synchronized float getFlatness( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    return flatness();
  }
  synchronized float getFlatness() {
    return getFlatness( paused );
  }

  synchronized PVector getCentroidSpreadFlatness( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );
    PVector sc = centroid();
    return new PVector( sc.x, spread( sc ), flatness( sc.y ) );
  }
  synchronized PVector getCentroidSpreadFlatness() {
    return getCentroidSpreadFlatness( paused );
  }

  // Sound pressure level in dB, scaled to [0,1]
  // Returns a PVector with SPL for low and high ranges (i.e., [0,11KHz),(11,22KHz] )
  synchronized PVector getSPL( boolean reanalyze ) {
    if ( reanalyze )
      fft.analyze( spectrum );

    float lo = 0.;
    float hi = 0.;
    int k;
    for ( k = 0 ; k < nbands / 2 ; ++k ) {
      lo += log( spectrum[ k ] / 1e-10 ) / log10;
      hi += log( spectrum[ k * 2 ] / 1e-10 ) / log10;
    }

    // /12: rescaling Bels to [0,1]
    spl.x = lo / ( 12. * nbands );
    spl.y = hi / ( 12. * nbands );
    return spl;
  }
  synchronized PVector getSPL() {
    return getSPL( paused );
  }

  // isOnset: Implements spectral flux onset algorithm from
  // Dixon S 2006 Onset detection revisited. Proc 9th Int Conf on Digital Audio Effects
  // http://www.dafx.ca/proceedings/papers/p_133.pdf
  synchronized boolean isOnset() {
    final int r = 3; // Radius of local maximum search
    final int m = 3; // Attack radius multiplier for mean calculation

    // Copy the buffer to an array for fast dereferences
    int i = 0;
    for ( float[] f : flux ) {
      fluxary[ i++ ] = f[ 0 ];
    }

    // f: Index of the sample frame we're testing to see if it's an onset
    int f = r * m; // f = rm: We need space at the front for the attack radius averaging

    boolean onsetp = true;

    float accum = 0.;
    float sf = fluxary[ f ];

    // Three tests to see if frame f is an onset
    // All must be satisfied

    // 1. Compare SF(f) to SF([f - r, f + r])
    //    On the side, accumulate SF([f - rm, f + r]) for test 2
    for ( i = f - r * m ; i <= r ; ++i ) {
      float cmp = fluxary[ i ];
      if ( i >= -r && sf < cmp ) { // SF(f) ≥ SF([f - r, f + r ])
        onsetp = false;
        break;
      }
      accum += fluxary[ i ];
    }

    // 2. If SF(f) passed test 1, compare it to the mean of SF([f - rm, f + r])
    if ( onsetp ) {
      float mean = accum / ( m * r + r + 1. );
      if ( sf < mean + threshold ) {
        onsetp = false;
      }
    }

    // 3. If SF(f) passed test 2, compare it to gAlpha
    if ( onsetp && sf < gAlpha ) {
      onsetp = false;
    }

    // Update gAlpha
    gAlpha = max( sf, alphaThreshold * gAlpha + ( 1. - alphaThreshold ) * sf );
    if ( Float.isInfinite( gAlpha ) || Float.isNaN( gAlpha ) )
      gAlpha = 1.;
      // TODO: Kludge to keep onset detection from getting extinguished
      // Not clear why it still happens now that spectral flux values are clamped

    return onsetp;
  }

  //
  // Initialization

  // To get a good-looking spectrogram, use stop colors
  void buildColorMap() {
    pushStyle();
    colorMode( HSB, 360., 1., 1., 1. );

    centroidColor = color( 180., 1., 1., 1. ); // CMY cyan, maximum brightness and opacity
    spreadColor = color( 120., 1., 1., 1. ); // RGB green, maximum brightness and opacity
    indicatorColor = color( 0., 0., .8, 1. ); // Bright gray

    colors = new color[ 120 * cr + 1 ];
    colors[ 120 * cr ] = color( 0., 0., 1., 0. ); // Transparent, for special cases

    colorMapA();
    popStyle();
  }

  // Inspiration: https://en.wikipedia.org/wiki/Spectrogram#/media/File:Spectrogram-19thC.png
  void colorMapA() {
    int i;

    // < 20dB: Black
    for ( i = 0 ; i < 20 * cr ; ++i )
      colors[ i ] = color( 0., 0., 0., alpha );

    // 20–39dB: Fade up to full brightness, hue set to blue
    for ( ; i < 40 * cr ; ++i )
      colors[ i ] = color( 240., 1., ( i - 20 * cr - 1 ) / ( 20. * cr ), alpha );

    // 40–89dB: Rotate from blue to yellow via red, maintaing full brightness
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

  void initializeSgQueue() {
    sg = new ArrayDeque<color[]>( nframes );
    for ( int f = 0 ; f < nframes ; ++f ) {
      color[] frame = new color[ nbands ];
      for ( int k = 0 ; k < nbands ; ++k ) {
        frame[ k ] = colors[ 120 * cr ]; // transparent
      }
      sg.add( frame );
    }
  }

  void initializeFluxQueue() {
    // Zero out X(n - 1) so we have a basis for comparison to start with
    for ( int k = 0 ; k < nbands ; ++k ) {
      prevSpectrum[ k ] = 0.;
    }

    // Initialize with 1s (+1sd) so we don't mistakenly register an onset as soon as the signal starts
    flux = new ArrayDeque<float[]>( sfpulse );
    for ( int f = 0 ; f < sfpulse ; ++f ) {
      float[] frame = new float[ 1 ];
      frame[ 0 ] = 1.;
      flux.add( frame );
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

  void setThreshold( float t ) {
    threshold = t > 0 ? t : threshold;
  }
  void setAlpha( float a ) {
    alphaThreshold = a > 0 ? a : alphaThreshold;
  }
  void setThresholds( float t, float a ) {
    threshold = t > 0 ? t : threshold;
    alphaThreshold = a > 0 ? a : alphaThreshold;
  }
  void resetThresholds() {
    threshold = .9;
    alphaThreshold = .2;
    gAlpha = 1.;
      // Now that we clamp the Gaussian spectral flux, initial value should not matter so much
      // But setting it to 1 helps guard against false positives in the first frames
  }
  PVector getThresholds() {
    return new PVector( threshold, alphaThreshold );
  }
}
