# Changelog

## 1.3.0

- 3D on speakers: Relief now cancels the sound of each speaker that reaches the opposite ear, so the stereo image spreads well beyond the speakers. Tuned for the built-in speakers (close together) and for external ones. Works best sitting in front of the screen.
- Virtual Bass: small speakers sound fuller. The bass they can't play is turned into its harmonics, which the ear hears as bass, and the deepest bass that would only distort is turned down.
- Low-Volume Boost: at low volume the ear loses bass and treble; Relief adds them back, more as you turn the volume down.

## 1.2.0

- Real 3D for headphones: your music is played by virtual speakers in front of you and virtual surrounds behind, in a small room, using a model of how sound reaches each ear (timing and head shadow). The sound comes from outside your head.
- Headphone model correction: pick your headphones among 6,000 models (AirPods, Sony, Bose, Sennheiser…) and Relief corrects their own colouration toward a neutral, balanced sound. Remembered for each output. Corrections from the AutoEq project (MIT licence).
- New "MacBook Speakers" preset: lifts the lowest range laptop speakers can play, without wasting power on bass they can't reproduce.
- The equalizer glides when you move a band: no more clicks.

## 1.1.2

- New icon and menu bar icon: a sound wave in relief.

## 1.1.1

- New icon and menu bar icon: a landscape of sound in relief, distinct from the system volume icon.

## 1.1.0

- New macOS-style icon and menu bar icon; the interface now uses the system accent color.
- Output picker and system volume (with mute) in the panel.
- Speakers or headphones chosen automatically for each output (Bluetooth, headphones jack),
  and remembered when you change it.
- Global shortcuts: on/off (⌃⌥⌘R), show the panel, equalizer, next preset, speakers/headphones,
  night mode, booster up/down — with an on-screen confirmation.
- Settings window (⌘,): general, shortcuts, updates, about; reset of all app volumes.
- Right-click the menu bar icon for a quick menu.

## 1.0.2

- Automatic standby: after 20 seconds without any sound, Relief releases the output device
  (saves battery, lets Bluetooth headphones sleep) and wakes up as soon as an app plays sound.
  Can be turned off in the settings menu.

## 1.0.1

- Look-ahead limiter: loud passages with the booster are smoothed instead of clipped.
- Relief never starts unless it can exclude its own sound (prevents any feedback loop).
- No more needless audio restarts when the output device sends a notification without a real change.
- Relief starts as soon as the audio permission is granted in System Settings (open the panel).
- Unmuting an app restores its previous volume.
- The app list no longer collapses when more than five apps play sound.

## 1.0.0

First release: 3D surround (speakers and headphones), 10-band equalizer with presets, volume booster with limiter, ambience, clarity, bass boost, night mode, per-app volume, automatic updates.
