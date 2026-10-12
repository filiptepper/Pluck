# Pluck

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Pluck is a lightweight, dedicated macOS host application built for running the **Line 6 Helix Native** Audio Unit (AU) plugin for ultra-low-latency live guitar playing.

It decouples input and output routing, letting you plug your guitar into any physical audio interface (e.g. Focusrite Scarlett, iRig, MOTU) and route processed output directly to any output device (headphones, studio monitors, or Multi-Output configurations) without requiring manual aggregate device setup in Audio MIDI Setup.

---

## Key Features

- **Dedicated CoreAudio HAL Input Capturer**: Direct, low-overhead hardware capture via AUHAL with exact channel mapping.
- **Lock-Free Atomic SPSC Ring Buffer**: Power-of-two, memory-barrier synchronized lock-free ring buffer bridging the real-time IO render thread to `AVAudioSourceNode` without lock contention or memory allocation.
- **Adaptive Clock Drift Protection**: Monitors fill levels between independent input and output hardware clocks, preventing buffer underruns while maintaining minimal latency.
- **Flexible Channel Routing**: Select any physical input channel (e.g. Input 1 or Input 2) and route to stereo or multi-channel outputs with automatic channel mirroring.
- **Hardware-Clamped Buffer Sizes**: Select buffer frame sizes (32, 64, 128, 256, 512 samples) automatically validated and clamped to your output device's supported hardware range, with live round-trip latency display.
- **State & Tone Persistence**: Automatically saves and restores your selected input/output devices, input channel, buffer size, and active Line 6 Helix Native tone preset.
- **Real-Time VU Meters**: Thread-safe atomic level meters with dBFS readout and peak monitoring.
- **Native Plugin GUI**: Dynamically locates and embeds the native Line 6 Helix Native (`aumf/6HPA/LSIX`) editor interface.
- **Instant Panic Mute**: One-click and keyboard shortcut (`Cmd+.`) panic button to mute all audio and stop the engine immediately.

---

## Prerequisites

- **macOS**: 12.0 (Monterey) or later
- **Audio Plugin**: Line 6 Helix Native Audio Unit (`.component`) installed on your system.
- **Xcode**: Command Line Tools installed (Xcode 14 or later) if building from source.

---

## Installation (Pre-built Release)

1. Download the latest `Pluck-<version>.dmg` from the [Releases](https://github.com/filiptepper/Pluck/releases) page.
2. Drag `Pluck.app` into `/Applications`.
3. **macOS 15 (Sequoia) Gatekeeper notice**:
   Because Pluck is open-source and ad-hoc signed, macOS 15 Sequoia may block opening by default. Clear the quarantine flag once in Terminal:
   ```bash
   xattr -cr /Applications/Pluck.app
   ```
   *(On macOS 14 Sonoma or earlier: Open **System Settings** -> **Privacy & Security** and click **Open Anyway**).*

---

## Quick Start (Build & Run from Source)

Pluck does not track bulky `.xcodeproj` bundles in Git. Instead, it generates a clean project on build.

1. **Clone the repository**:
   ```bash
   git clone https://github.com/filiptepper/Pluck.git
   cd Pluck
   ```

2. **Generate the Xcode project**:
   ```bash
   make generate
   ```

3. **Build the application**:
   ```bash
   make build
   ```

4. **Run the test suite**:
   ```bash
   make test
   ```

5. **Run the application**:
   ```bash
   make run
   ```

---

## Architecture

`AVAudioEngine` attaches directly to a single hardware output device. To capture from a separate physical guitar interface without creating system-wide aggregate devices:

```
[ Guitar Audio Interface ]
           │
           ▼
[ CoreAudio AUHAL Input Capturer ] (Element 1, Output Scope)
           │
           ▼
[ Lock-Free Atomic SPSC Ring Buffer ] (Power-of-2, Memory Barriers)
           │
           ▼
[ AVAudioSourceNode ]
           │
           ▼
[ Line 6 Helix Native AU ] (Stereo Processing)
           │
           ▼
[ AVAudioEngine OutputNode ] (Multi-Channel Mirroring)
           │
           ▼
[ Headphones / Monitors ]
```

1. **Input Stage:** An `AUHAL` audio unit attaches directly to the selected hardware input device on Element 1. It extracts the chosen mono input channel and writes incoming samples into a lock-free single-producer single-consumer ring buffer.
2. **Buffering & Drift:** The ring buffer uses monotonic atomic counters (`OSAtomicAdd64Barrier` / CAS) with wrap-around masking. When independent hardware clocks drift, an adaptive latency window adjusts read pointers without stalling audio.
3. **Processing & Output:** `AVAudioSourceNode` pulls samples from the ring buffer, feeding them into `AVAudioEngine`. Audio passes through the Line 6 Helix Native Audio Unit, through volume/metering taps, and into the hardware output device.

---

## Keyboard Shortcuts

- **Ctrl + Space**: Toggle Audio Engine (Start / Stop).
- **Cmd + .**: Panic (Stop engine and mute all audio immediately).

---

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on code style, concurrency rules, and PR workflow.

---

## Trademark Disclaimer

Line 6 and Helix are registered trademarks of Yamaha Guitar Group, Inc. Pluck is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Yamaha Guitar Group, Inc. or Line 6.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
