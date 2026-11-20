# Pulse

A feature-rich metronome for iPhone and iPad, built for musicians who play in more than 4/4.

Native SwiftUI, no audio files: every click is synthesized in code by a sample-accurate engine.

## What it does

**Meters**
- Simple, compound and odd meters: 2/4 … 15/16, any numerator 1–32 over 1, 2, 4, 8, 16 or 32.
- Groupings for additive meters (7/8 as 2+2+3, 11/8 as 3+3+3+2, or type your own like `3+3+2`). Accents follow the groups.
- Beat unit that counts what you count: 6/8 in dotted quarters, 7/8 in eighths, or any note value. Changing it keeps the speed you hear.
- Mixed-meter patterns: chain bars (7/8, 8/8, 5/4 …) with repeat counts and loop them.
- Per-beat accents: tap any beat to cycle silent / soft / normal / accent.
- Polyrhythm layer: 2 to 16 evenly spaced clicks across each bar (3 against 4, 5 against 4, 7 against 8) with its own sound.

**Subdivisions**: eighths, triplets, sixteenths, quintuplets, sextuplets, septuplets, swing (adjustable), shuffle, off-beats only, gallop, syncopated, plus a custom pattern editor that mutes individual slots.

**Sounds**: 30 synthesized voices (clicks, wood blocks, beeps, cowbells, kick/snare/hats, rim, clap, shaker, clave, sticks, marimba, chimes, triangle, mechanical tick-tock) in 10 ready-made kits. Any sound can play at any level. Pitch ±12 semitones and independent volumes.

**Practice**: speed trainer (ramp up or down every N bars), gap click (N bars on, M bars silent), count-in (1, 2 or 4 bars).

**Visuals**: Pendulum, Pulse (full-panel flash with big group-aware counts), Orbit (the bar as a ring), Bounce (a ball hopping pad to pad). Six themes. Full-screen stage mode. Haptic tick on each beat. A latency slider lines the visuals up with Bluetooth speakers.

**Siri, Shortcuts, Action Button**: see below.

**Everything else**: tap tempo, drag-ruler tempo, tempo names, 30 built-in presets, your own saved presets, lock-screen and headphone controls, background audio, plays along with other audio.

## Talking to it (App Intents)

Every control is an App Intent, so it works from Siri, Shortcuts, Spotlight, the Action Button and Lock Screen controls.

| Say / run | Intent |
|---|---|
| "Start Pulse" / "Stop Pulse" | `StartMetronomeIntent` (optional tempo), `StopMetronomeIntent`, `ToggleMetronomeIntent` |
| "Speed up Pulse" / "Slow down Pulse" | `SpeedUpIntent`, `SlowDownIntent` (amount in BPM, default 5) |
| "Set the tempo in Pulse" | `SetTempoIntent` (Siri asks for the number) |
| Faster or slower by N BPM or N percent | `ChangeTempoIntent` |
| "Double the tempo in Pulse", "Half time in Pulse" | `ScaleTempoIntent` |
| "Set Pulse to seven eight" | `SetTimeSignatureIntent`, plus `SetCustomTimeSignatureIntent` (beats, note value, grouping) |
| "Subdivide Pulse into triplets" | `SetSubdivisionIntent` |
| "Change the sound in Pulse to wood block" | `SetSoundIntent` |
| "Start Waltz in Pulse" | `StartPresetIntent`, `LoadPresetIntent` (built-in and your presets) |
| Build from 80 to 140 BPM, +4 every 4 bars | `StartSpeedTrainerIntent`, `StopSpeedTrainerIntent` |
| Count-in, polyrhythm, volume, visual | `SetCountInIntent`, `SetPolyrhythmIntent`, `SetVolumeIntent`, `SetVisualModeIntent` |
| "What's my tempo?" | `GetTempoIntent` (speaks the settings and returns the BPM) |

Tempo, subdivision, sound and meter changes made while playing take effect on the next beat, without stopping the click. Intents that start playback open the app so iOS lets the audio session begin.

## Layout

```
PulseKit/             Swift package: engine, synth, models. No UIKit; unit-tested on the Mac with `swift test`.
  Types.swift         AccentLevel, BeatUnit, Meter (grouping/accents), BarSpec, Subdivision
  Settings.swift      MetronomeSettings, PolyLayer, SpeedTrainer, GapClick
  Sounds.swift        SoundID, SoundKit, synthesis recipes, peak-normalised SoundBank
  Voice.swift         allocation-free modal synth voice
  Core.swift          MetronomeCore: the real-time scheduler
  Phase.swift         PlaybackPhase: what is audible right now, for the visuals
  Tempo.swift         tempo names, tap tempo
  Presets.swift       30 built-in presets
Pulse/                iOS app
  Model/              Metronome (observable model), AudioOutput (AVAudioEngine), preferences/themes
  Intents/            App Intents, enums, preset entity, Siri phrases
  Views/              main screen, tempo ruler, beat grid, visuals, sheets
PulseTests/           model + intent tests
scripts/make-icon.swift
project.yml           xcodegen spec (run `xcodegen generate`)
```

## How the timing works

`MetronomeCore.render` runs inside the audio render callback. It keeps time as a fractional sample position (`Double`), so tempos that don't divide the sample rate evenly never drift, and it starts each click on the exact sample inside the buffer. It never allocates or blocks: voices are preallocated, settings arrive through a try-lock mailbox, and compiled settings are retained on the main thread so the audio thread never frees them.

The UI doesn't run its own clock. The engine publishes the last 32 pulses with their sample positions and the host time of each buffer; `PlaybackPhase.compute` turns that into the position being heard right now, so the visuals stay locked to the sound at any buffer size. Output latency (e.g. Bluetooth) is added automatically; the Settings slider fine-tunes it.

## Build and test

```bash
cd PulseKit && swift test            # 67 engine tests, incl. 10 minutes with no drift
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test   # 28 app + intent tests
```

For screenshots and manual checks, Debug builds accept launch arguments:
`-pulse.demo.preset builtin.seven-eight -pulse.demo.visual orbit -pulse.demo.theme ocean -pulse.demo.bpm 140 -pulse.demo.play YES`

## Notes

- Deployment target iOS 26. Signing uses team `9WZ66DZ69J`; build for a device from Xcode as usual.
- Siri skills (the iOS 27.3 beta `ToolIntent` / Skills bundle work described in `_SIRI_AI_2026-11.md`) is not wired up yet; the intents here work with today's Siri and Shortcuts, and are the right base for it.
