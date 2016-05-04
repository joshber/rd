# rd

## Audio-driven procedural video with reaction-diffusion models

Josh Berson, [josh@joshberson.net](mailto:josh@joshberson.net)

2016 CC BY-NC-ND 4.0

A more detailed description will follow, but in essence: This is an experiment in audio-driven procedural video and in pushing as much of the logic of procedural video as possible onto the graphics layer. A controller, written in Processing, plays a video on loop and monitors the audio line in, computing X(n) (frequency spectrum) along with sound pressure level, central moments, and spectral flux onsets and passing these to a shader, “kernel.” The kernel shader implements the Gray-Scott reaction-diffusion model, using audio features to tune speed and detail parameters of the model and to induce beats (localized sudden increases in the concentration of one of the reaction-diffusion actants) and glitch in response to spectral flux onsets and spectral flatness or untonality respectivelyl. The kernel shader renders to an offscreen buffer, which is then convolved with the video to produce the final image.

It is intended for large-scale multichannel installation. At a future point, multiple instances may signal one another (e.g., to indicate local nonparametric zeitgeber such as spectral flux onsets) over ØMQ.

Inspiration comes from the work of [Mark IJzerman](http://markijzerman.com/).

![screenshot](https://github.com/joshber/rd/blob/master/screenshots/screen0.jpg)
![screenshot](https://github.com/joshber/rd/blob/master/screenshots/screen1.jpg)
![screenshot](https://github.com/joshber/rd/blob/master/screenshots/screen2.jpg)
