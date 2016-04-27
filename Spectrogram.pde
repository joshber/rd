import java.util.*; // ArrayDeque

import ddf.minim.*;
import ddf.minim.analysis.*;

// TODO
// Experiment with color map -- maybe do more with saturation?
// More darkness in the low end
// Maybe rotate from blue to yellow through green while raising brightness from .5 to 1?
// Maybe as above but rotating from red to yellow through orange?

class Spectrogram {
  final float log10 = log( 10. ); // For converting intensities to dB

  AudioInput in;
  FFT fft;
  final int nbands = 256;

  ArrayDeque<color[]> sg;
  final int nframes = 60;

  color[] colors;
  final int cr = 4; // color resolution, i.e., colors/decibel
  final float alpha = .75;
  final int xstretch = 2;

  Spectrogram( AudioInput ai ) {
    in = ai;
    fft = new FFT( in.bufferSize(), in.sampleRate() );
    fft.linAverages( nbands );

    buildColorMap();
    zeroOutSgQueue();
  }

  // To get a good-looking spectrogram, use stop colors
  void buildColorMap() {
    pushStyle();
    colorMode( HSB, 360., 1., 1., 1. );

    colors = new color[ 120 * cr + 1 ];
    colors[ 120 * cr ] = color( 0., 0., 1., 0. ); // Transparent, for special cases

    colorMapA();
    popStyle();
  }

  void colorMapA() {
    // https://en.wikipedia.org/wiki/Spectrogram#/media/File:Spectrogram-19thC.png
    int i;

    // < 10dB: Black
    for ( i = 0 ; i < 10 * cr ; ++i )
      colors[ i ] = color( 0., alpha );

    // 10–39dB: Fade up to full brightness, hue set to blue
    for ( ; i < 40 * cr ; ++i )
      colors[ i ] = color( 240., 1., ( i - 10 * cr - 1 ) / ( 20. * cr ), alpha );

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

  void draw( int margin ) {
    fft.forward( in.mix );

    // Add a new sample frame to the spectrogram
    color[] frame = new color[ nbands ];
    for ( int i = 0 ; i < nbands ; ++i ) {
      float a = fft.getAvg( i );
      int dB = floor( cr * 10. * log( a * a / 1e-10 ) / log10 ); // Convert to decibels(*)
      frame[ i ] = colors[ min( max( 0, dB ), 120 * cr - 1 ) ];
      // (*) Actually cr·dB -- dB == 10·log10(intensity / 1e-12 W/m2). We use a cr·120-step color range, whence cr·
      // TODO: /1e-10. Looks like Minim is using e-2 units. Scaling down yields more plausible dB values
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
  }
}
