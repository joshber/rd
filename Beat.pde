// Beat detector class
// Josh Berson, josh@joshberson.net
// 2016 CC BY-NC-ND 4.0

import beads.*;

class Beat {
  PeakDetector pd;
  boolean onsetp = false;

  Beat() {
    AudioContext ac = new AudioContext();
    Gain gain = new Gain( ac, 2, .5 );
    UGen mic = ac.getAudioInput();
    ShortFrameSegmenter sfs = new ShortFrameSegmenter( ac );
    beads.FFT fft = new beads.FFT();
    PowerSpectrum ps = new PowerSpectrum();
    SpectralDifference sd = new SpectralDifference( ac.getSampleRate() );
    pd = new PeakDetector();

    ac.out.addDependent( sfs );
    sfs.addInput( mic );
    sfs.addListener( fft );
    fft.addListener( ps );
    ps.addListener( sd );
    sd.addListener( pd );

    pd.setThreshold( .2 );
    pd.setAlpha( .9 );

    pd.addMessageListener(
      new Bead() {
        protected void messageReceived( Bead b ) {
          onsetp = true;
        }
      }
    );

    ac.start();
  }

  boolean isOnset() {
    boolean p = onsetp;
    onsetp = false;
    return p;
  }
}
