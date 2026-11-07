# Changelog

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
