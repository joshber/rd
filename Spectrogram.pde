import java.util.*; // ArrayDeque

import ddf.minim.*;
import ddf.minim.analysis.*;

// TODO
// - Experiment with color map -- maybe do more with saturation?

class Spectrogram {
  final float log10 = log( 10. ); // For converting intensities to dB

  AudioInput in;
  FFT fft;
  final int nfbins = 256;

  ArrayDeque<int[]> sg;
  final int nframes = 60;

  color[] colors;
  final int colorResolution = 4;
  final float alpha = .75;
  final int xstretch = 2;

  Spectrogram( AudioInput ai ) {
    in = ai;
    fft = new FFT( in.bufferSize(), in.sampleRate() );
    fft.linAverages( nfbins );

    zeroOutSgQueue();
    buildColorMap();
  }

  void zeroOutSgQueue() {
    sg = new ArrayDeque<int[]>( nframes );
    for ( int i = 0 ; i < nframes ; ++i ) {
      int[] frame = new int[ nfbins ];
      for ( int j = 0 ; j < nfbins ; ++ j ) {
        frame[ j ] = 120 * colorResolution; // transparent
      }
      sg.add( frame );
    }
  }

  // To get a good-looking spectrogram, use stop colors
  void buildColorMap() {
    pushStyle();
    colorMode( HSB, 360., 1., 1. );

    colors = new color[ 120 * colorResolution + 1 ];
    colors[ 120 * colorResolution ] = color( 0., 0., 1., 0. ); // Transparent, for special cases

    colorMapB();
    popStyle();
  }

  void colorMapA() {
    int i;

    // < 10dB: Black
    for ( i = 0 ; i < 10 * colorResolution ; ++i )
      colors[ i ] = color( 0., alpha );

    // 10–49dB: Fade up to full brightness, hue set to blue
    for ( ; i < 50 * colorResolution ; ++i )
      colors[ i ] = color( 240., 1., ( i - 10 * colorResolution - 1 ) / ( 40. * colorResolution ), alpha );

    // 50–89dB: Rotate from blue to yellow, maintaing full brightness
    for ( ; i < 90 * colorResolution ; ++i )
      colors[ i ] = color( int( 240 + 180 * ( i - 50 * colorResolution - 1 ) / ( 40. * colorResolution ) ) % 360, 1., 1., alpha );
      // int( 240 + 180 * ( i - 50 * cR ) / ( 40. * cR ) ) % 360:
      // As i goes from 50cR to 90cR, we're rotating the hue through 180 degrees,
      // from blue to yellow, keeping saturation and brightness constant

    // 90–120dB: Hue stays at yellow, brightness at 1, saturation fades to 0 (i.e., white)
    for ( ; i < 120 * colorResolution ; ++i )
      colors[ i ] = color( 60., ( i - 90 * colorResolution - 1 ) / ( 30. * colorResolution ), 1., alpha );
  }

  void colorMapB() {
    // https://en.wikipedia.org/wiki/Spectrogram#/media/File:Spectrogram-19thC.png
    int i;

    // < 10dB: Black
    for ( i = 0 ; i < 10 * colorResolution ; ++i )
      colors[ i ] = color( 0., alpha );

    // 10–39dB: Fade up to full brightness, hue set to blue
    for ( ; i < 40 * colorResolution ; ++i )
      colors[ i ] = color( 240., 1., ( i - 10 * colorResolution - 1 ) / ( 20. * colorResolution ), alpha );

    // 40–89dB: Rotate from blue to yellow, maintaing full brightness
    for ( ; i < 90 * colorResolution ; ++i )
      colors[ i ] = color( int( 240 + 180 * ( i - 40 * colorResolution - 1 ) / ( 50. * colorResolution ) ) % 360, 1., 1., alpha );
      // int( 240 + 180 * ( i - 40 * cR ) / ( 50. * cR ) ) % 360:
      // As i goes from 40cR to 89cR, we're rotating the hue through 180 degrees,
      // from blue to yellow, keeping saturation and brightness constant

    // 90–99dB: Hue stays at yellow, brightness at 1, saturation fades to 0 (i.e., white)
    for ( ; i < 100 * colorResolution ; ++i )
      colors[ i ] = color( 60., ( i - 89 * colorResolution - 1 ) / ( 10. * colorResolution ), 1., alpha );

    // 100–120dB: White
    for ( ; i < 120 * colorResolution ; ++i )
      colors[ i ] = color( 0., 0., 1., alpha );
  }

  void draw( int margin ) {
    // Add a new sample frame to the spectrogram
    fft.forward( in.mix );

    int[] frame = new int[ nfbins ];
    for ( int i = 0 ; i < nfbins ; ++i ) {
      // TODO: /1e-10 instead of 1e-12 bc it looks like Minim is returning amplitudes in e-2 units
      // -- scaling down two orders of magnitude yields more plausible dB values
      float amp = fft.getAvg( i );
      int dB = floor( colorResolution * 10. * log( amp * amp / 1e-10 ) / log10 ); // Convert to decibels(*)
      frame[ i ] = min( max( 0, dB ), 479 );
      // (*) Actually cR·dB -- dB == 10·log10(intensity / 1e-12 W/m2). We use a cR·120-step color range, whence cR·
    }

    sg.remove(); // Remove the oldest frame
    sg.add( frame );

    int i = 0;
    for ( int[] f : sg ) {
      float xoff = width - ( nframes * xstretch + margin ) + i * xstretch; // Draw from the left
      for ( int k = 0 ; k < nfbins ; ++k ) {
        float yoff = height - k - margin; // Draw from the bottom
        fill( colors[ f[ k ] ] );
        rect( xoff, yoff, xstretch, 1 );
      }
      ++i;
    }
  }
}
