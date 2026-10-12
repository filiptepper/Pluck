# HelixPlayer — Adversarial Code Review

- **Date:** 2026-10-12
- **Commit reviewed:** `6bfc493` (main)
- **Scope:** all tracked sources, tests, build scripts, CI/release workflows, README/CONTRIBUTING
- **Verdict:** **Not ready for public release.** The core audio path has real concurrency bugs. The tests touch real hardware but check almost nothing that matters. The README describes features that no longer exist.

## How this was verified

| Check | Result |
|---|---|
| `make test` | 7/7 pass. The log shows tests open the real mic, change real device buffer sizes, and instantiate Helix Native |
| Clean Debug build | 4 compiler warnings (`CoreAudioHelper.swift` L51, L62, L163, L198) |
| Tests with Thread Sanitizer (`-enableThreadSanitizer YES`) | **Hangs forever.** Main thread blocks in HAL at `AudioEngineManager.swift:307` while 2 concurrent reconfigurations sit in HAL at L564 |
| `codesign -dv` on build | `adhoc, linker-signed`, `Sealed Resources=none` |
| Apple TN2091 (AUHAL) | Confirms the input channel map belongs on **Output scope, element 1** |
| Physical Hardware (Channel 2) | **Confirmed broken:** Guitar plugged into input 2 with "Channel 2" selected produces total silence |

---

## Severity summary

| ID | Severity | Finding |
|---|---|---|
| C1 | Critical | `AudioRingBuffer` is not thread-safe (no atomics or memory ordering) and does not handle overflow |
| C2 | Critical | Engine state is mutated from 3 queues with no synchronization |
| C3 | Critical | PANIC/Stop can do nothing while audio keeps playing |
| C4 | Critical | Test target compiles app sources twice, and the test host runs the full app |
| C5 | Critical | README advertises features that were removed. Leftover dead code |
| H1 | High | Input channel map uses wrong scope (confirmed broken: input 2 produces silence) |
| H2 | High | Drift "compensation" is a hard read-head jump with thresholds that break at 512 frames |
| H3 | High | Sample-rate handling: stale cached rate, possible reconfig loop |
| H4 | High | Device hot-plug and input-device loss are not observed |
| H5 | High | `WindowGroup` lets Cmd+N start a 2nd engine and a 2nd Helix instance |
| H6 | High | Release artifacts are unsigned. The install instructions no longer work on macOS 15+ |
| M1–M8 | Medium | RT-thread safety, UX state bugs, CoreAudio helper UB, defaults/persistence |
| L1–L6 | Low | Standards drift, logging, hygiene, legal/trademark |

---

## Critical

### C1. `AudioRingBuffer` is not lock-free or thread-safe
[AudioEngineManager.swift L9-75](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L9-L75)

- `writeHead` and `readHead` are plain `Int` vars. Two real-time threads use them: the input IOProc and the output render. There are no atomics and no acquire/release ordering.
- On Apple Silicon (weak memory model), the reader can see the new `writeHead` before the sample stores land. The result is stale or garbage samples.
- **No overflow check.** `write()` never checks free space. If the consumer stalls (output device hiccup, engine not started yet while the capturer runs), the writer laps the reader. `w == r` is ambiguous (empty vs. full), and `availableToRead()` then returns a wrapped, wrong value. The output plays audio up to 16384 samples old.
- `reset()` (L546) writes both heads from `audioQueue` while an old render or IO thread may still be running.
- `% capacity` in the inner loop is a division per sample. Use a power-of-two capacity and `& mask`.

**Fix:** use monotonically increasing indices, a power-of-two capacity, and acquire/release atomics. Return frames written or dropped so overflow is observable.

```swift
// Requires swift-atomics (SPM) or a 10-line C shim with <stdatomic.h>.
// (Synchronization.Atomic needs macOS 15; deployment target is 12.)
final class SPSCRingBuffer {
    private let capacity: Int, mask: Int
    private let storage: UnsafeMutablePointer<Float>
    private let written = ManagedAtomic<Int>(0)   // producer-owned
    private let read    = ManagedAtomic<Int>(0)   // consumer-owned

    /// Producer thread only. Returns frames actually written.
    @discardableResult
    func write(_ src: UnsafePointer<Float>, count: Int) -> Int {
        let w = written.load(ordering: .relaxed)
        let r = read.load(ordering: .acquiring)
        let n = min(count, capacity - (w - r))
        for i in 0..<n { storage[(w + i) & mask] = src[i] }
        written.store(w + n, ordering: .releasing)
        return n
    }
    /// Consumer thread only. Zero-fills on underrun; returns frames read.
    func read(into dst: UnsafeMutablePointer<Float>, count: Int) -> Int { /* symmetric */ }
}
```

### C2. Unsynchronized shared state across main, `audioQueue`, and `DispatchQueue.global`
- `engine` is **reassigned** on `audioQueue` ([L545](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L545)) while the main thread calls `engine.start()` / `engine.stop()` ([L409](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L409), [L437](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L437)). A concurrent reference reassignment and read is a use-after-free crash waiting to happen.
- `inputCapturer` is set to nil or replaced on `audioQueue` ([L491](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L491), [L616](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L616)) and read on main ([L406](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L406)).
- `shouldStartAfterConfig` is written on main and read on `audioQueue` ([L722](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L722)).
- The AU instantiate completion hops to **`DispatchQueue.global`** ([L795](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L795)), not `audioQueue`. So `configureAndStartEngine` can run **concurrently** with the next reconfiguration's `engine = AVAudioEngine()`. The `configVersion` check (L800) is a TOCTOU: the version can change one line later. `configVersion` is also read off-main without synchronization.
- `startEngine()`'s "direct path" ignores `isConfiguring` and calls `engine.start()` on main mid-reconfiguration.

**Fix:** pick one owner. All engine, capturer, and ring state lives on `audioQueue`. Main only sends *intents* (`start`, `stop`, `select(input:)`…) and receives a published state enum: `.idle | .configuring | .running | .failed(String)`. Hop the AU completion to `audioQueue.async` and re-check the version **there**.

### C3. PANIC/Stop can silently fail while audio plays
Race ([L431-434](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L431-L434), [L722-753](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L722-L753)):
1. Engine running → user changes a device → `isRunning = false`, `shouldStartAfterConfig = true`.
2. `audioQueue` reads `shouldStartAfterConfig == true` at L722 and starts the engine and capturer.
3. User hits PANIC: `stopEngine()` sets the flag false, then `guard isRunning else { return }`. **Nothing is stopped.**
4. The main-queue block sees the flag false → `isRunning` stays false, status reads "Audio Unit loaded".
5. Audio is live, the UI says stopped, and PANIC is a no-op until the user presses *Start*.

Same desync when `engine.start()` succeeds but `inputCapturer.start()` throws (L409-410, L725-726): the engine keeps running with `isRunning == false`.

**Fix:** `stopEngine()` must be unconditional and idempotent. Always dispatch `engine.stop(); inputCapturer?.stop()` to the owning queue and bump `configVersion` so in-flight setups abort. Roll back the engine if the capturer fails to start. This is a live-audio app with mic + speakers, so a broken panic button is a feedback/hearing hazard.

### C4. Tests run against two copies of the app plus the running app
[generate_xcodeproj.py L194-199](file:///Users/filiptepper/Code/HelixPlayer/generate_xcodeproj.py#L194-L199)

- The test target compiles `CoreAudioHelper.swift` and `AudioEngineManager.swift` **again** while also using `TEST_HOST` + `@testable import HelixPlayer`. The stack sample shows both `HelixPlayer.debug.dylib` and `HelixPlayerTests` copies of `AudioEngineManager` running at the same time.
- `TEST_HOST` launches the full app, so `ContentView` creates its own `AudioEngineManager`. That opens the mic, sets buffer sizes, and instantiates Helix Native **during every test run**.
- `AudioEngineManager.init()` triggers **two** reconfigurations: the log shows Version 1 and 2 at launch (`@Published` + `didSet` fire in init). Every test that constructs the manager touches real devices and keeps running after the test ends.
- Result: a reproducible **hang under TSan**, and nondeterministic results on CI.

**Fix:**
1. Remove the app sources from the test target's Sources phase. Rely on `@testable import`.
2. Skip app UI/engine startup when running under XCTest, or set `TEST_HOST` to empty for a pure logic bundle.
3. Make `AudioEngineManager.init()` side-effect free. Hardware access starts on an explicit `activate()`.

### C5. README sells features the code doesn't have
[README.md](file:///Users/filiptepper/Code/HelixPlayer/README.md)

| README claim | Reality |
|---|---|
| "Programmatic Aggregate Devices" / "How It Works" steps 2-4 | `aggregateDeviceID` is **never assigned**. `createAggregateDevice` is only called from tests |
| "Clock Drift Compensation" via CoreAudio | Replaced by ring-buffer read-head jumps (see H2) |
| "Graceful Fallback… Apple AUDelay" | No fallback exists. The app shows "Helix Native Not Found" |
| "Crash Recovery… on launch **and shutdown**" | Only on launch. Private aggregates die with the process anyway |

**Fix:** pick one architecture. Either delete the aggregate code paths (`cleanupAggregateDevice`, `destroyAllOrphanedAggregateDevices`, `createAggregateDevice`, the multi-output aggregate test) or restore them. Then rewrite README "Key Features" and "How It Works" to match. Also update or remove `docs/superpowers/*` (stale AI planning docs describing the old design).

---

## High

### H1. Input channel selection is broken (confirmed)
[AudioEngineManager.swift L157-160](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L157-L160)

TN2091: the input channel map goes on **`kAudioUnitScope_Output`, element 1**. The code uses `kAudioUnitScope_Input` and discards the status (`_ =`). Because the HAL rejects this invalid property/scope combination, no mapping occurs and input 2 produces complete silence.

- **Status:** **Confirmed broken on physical hardware** (guitar plugged into input 2 with "Channel 2" selected results in no audio).
- **Fix:** use `kAudioUnitScope_Output`, throw on non-`noErr`, and validate `inputChannel < deviceInputChannels`.

The buffer-size `AudioUnitSetProperty` (L164) also ignores its status.

### H2. Drift handling causes audible artifacts; fixed thresholds break at large buffers
[AudioEngineManager.swift L50-74](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L50-L74)

- Input and output run on **independent clocks**, so drift is guaranteed. Correcting it by **jumping** the read head causes a discontinuity (click) every time. Underruns zero-fill mid-buffer, which also clicks.
- Thresholds are hard-coded in samples (2048 / 256), independent of sample rate and buffer size. At **512 frames**, the post-jump target (256) is **less than one callback**, so every correction guarantees an underrun.
- There is no target fill level or prefill, so steady-state latency is whatever phase offset the two devices start with. Any jitter can push it into underrun.
- **Fix:** prefill to `target = 2 × max(inBuf, outBuf)`. Correct drift by **resampling slightly**: track fill level with a slow PI controller and nudge an `AVAudioConverter` / varispeed ratio by ±0.1 %. Alternatively, go back to an aggregate device with `kAudioSubDeviceDriftCompensationKey` (already written in `CoreAudioHelper`). Derive thresholds from buffer size and rate.

### H3. Sample-rate handling
- The capturer is configured at the **output's** cached rate ([L612](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L612)). Per TN2091, AUHAL doesn't reliably sample-rate convert on input. A 44.1 kHz interface into a 48 kHz output will either fail `AudioUnitSetProperty` or play at the wrong pitch. Read the input device's live nominal rate and convert explicitly, or set both devices to the same rate.
- `AudioDevice` equality is by `deviceID` only ([CoreAudioHelper.swift L16-22](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/CoreAudioHelper.swift#L16-L22)). After a rate change, `selectedOutputDevice` keeps the **stale struct** (old `sampleRate`). The config-change handler ([L333-357](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L333-L357)) sees "changed" and reconfigures with the **old** rate. The next notification sees "changed" again, so a reconfiguration loop is likely.
- **Fix:** look up the live rate from the HAL inside `setupAudioGraphAsync`. Refresh selected devices from `availableDevices` by UID without re-triggering `didSet`.

### H4. Hot-plug and device loss are not observed
- Only `.AVAudioEngineConfigurationChange` is observed ([L315](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L315)). It fires for the engine's output, not for the device list, and never for the separate input `AudioInputCapturer`.
- Plugging the interface in after launch → it never appears in the picker. Unplugging the input → silent failure.
- **Fix:** add an `AudioObjectAddPropertyListenerBlock` for `kAudioHardwarePropertyDevices`, plus `kAudioDevicePropertyDeviceIsAlive` / `NominalSampleRate` on the selected input and output devices. Keep and remove the `NotificationCenter` token. `object: nil` currently also catches notifications from discarded engines.

### H5. Multiple windows = multiple engines
[HelixPlayerApp.swift](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/HelixPlayerApp.swift)

`WindowGroup` + `@StateObject` in `ContentView`: Cmd+N creates a 2nd `AudioEngineManager` → a 2nd capturer on the same device, a 2nd Helix Native instance, and 2 engines fighting over the output.

- **Fix:** `.commands { CommandGroup(replacing: .newItem) {} }` (macOS 12), or `Window` on macOS 13+. Own the manager at the `App` level.
- Also add `applicationShouldTerminateAfterLastWindowClosed → true`, or stop audio when the window closes.

### H6. Release artifacts and distribution
[release.yml](file:///Users/filiptepper/Code/HelixPlayer/.github/workflows/release.yml), [docs/code_signing_notarization.md](file:///Users/filiptepper/Code/HelixPlayer/docs/code_signing_notarization.md)

- Builds are `CODE_SIGNING_ALLOWED=NO`: linker ad-hoc signed, bundle **not sealed**. Downloaded and quarantined, Apple Silicon will likely report *"HelixPlayer is damaged"*. **Verify** by downloading the release `.dmg` on another Mac.
- Release notes say "right-click → Open". **macOS 15 Sequoia removed that bypass.** Users must go to System Settings → Privacy & Security → *Open Anyway*.
- The notarization doc enables Hardened Runtime but does not mention **`com.apple.security.cs.disable-library-validation`**. Helix Native is a third-party, in-process AU signed by another team. Under Hardened Runtime, library validation will block it. The first notarized build would fail to load the plugin.
- `allow-unsigned-executable-memory` in the entitlements: document why it's needed (or drop it). Note the entitlements file is never applied while signing is disabled.
- **Fix (min):** `codesign --force --deep -s - HelixPlayer.app` in CI, plus updated Sequoia instructions. **Fix (proper):** Developer ID + notarization with the correct entitlements.

---

## Medium

### M1. Real-time thread hygiene
- The input IOProc calls a closure capturing `[weak self]` ([L622-624](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L622-L624)). The weak load retains the manager on the IO thread. If that's the last reference, `deinit` (→ `engine.stop()`, `@Published` writes) runs **on the IO thread**.
- `rawInputLevel` / `rawOutputLevel` are non-atomic `Float`s written from the IO and tap threads and read by the main timer: a formal data race.
- **Fix:** store the meter value in an atomic (`UInt32` bit pattern), or put it in the ring object. No Swift object retain/release in the IOProc.
- `AudioInputCapturer` uses `Unmanaged.passUnretained(self)`. It's safe only because `deinit` stops the unit first. Document that invariant.

### M2. Input channel not clamped on device change
[L239-244](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L239-L244): selecting a 2-channel device after channel 5 leaves `selectedInputChannel = 4` → silence, and the picker shows no selection. Clamp in `didSet`. That also triggers a second full reconfiguration, so coalesce (see M3).

### M3. Reconfiguration storms
- Init fires 2 reconfigurations; the first aborts with "Input/Output device not selected" and flashes an error.
- Every picker change does a full teardown and rebuild.
- `isConfiguring` is a `Bool`, so an aborted older version clears it while a newer one is still in flight.
- **Fix:** debounce intents (~50 ms) and track configuration by version, not a Bool.

### M4. Defaults and persistence
- The default input is "first device with inputs". On the reviewer's Mac that was **"Filip's iPhone Microphone"**, and the output was **BlackHole 16ch**. Use `kAudioHardwarePropertyDefaultInputDevice` / `DefaultOutputDevice`.
- Nothing persists: devices (store by **UID**, not `deviceID`), channel, buffer size, bypass, and most importantly **plugin state** (`auAudioUnit.fullState`). Users lose their current tone edits on every launch.
- Built-in mic + built-in speakers as defaults = feedback risk. Consider warning.

### M5. Space bar shortcut may steal typing from the plugin UI
[ContentView.swift L54](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/ContentView.swift#L54): an unmodified `.space` key equivalent is processed before the first responder. Typing a preset name with a space in Helix Native's editor would probably toggle the engine. **Verify**, then use a modifier or scope the shortcut.

### M6. `CoreAudioHelper` correctness and duplication
[CoreAudioHelper.swift](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/CoreAudioHelper.swift)

- 4 compiler warnings: `var x: CFString` passed as a raw out-pointer (L51, L62, L163, L198). It works by accident. Use `Unmanaged<CFString>?` as `getSubDeviceUIDs` already does.
- Device enumeration is copy-pasted 3 times. Extract `allDeviceIDs()` and a generic `getProperty<T>(_:scope:)` / `getString(_:)`.
- `isMultiOutput` relies on the private UID prefix `~:AMS2_StackedOutput`. Prefer `kAudioDevicePropertyTransportType == kAudioDeviceTransportTypeAggregate` plus `kAudioAggregateDevicePropertyComposition` (stacked key).
- The magic `0x61737562` should be `kAudioSubDeviceClassID`. `kAudioAggregateDevicePropertyActiveSubDeviceList` is simpler than walking owned objects.
- Mixed `mElement: 0` vs `kAudioObjectPropertyElementMain`.

### M7. Infinite spinner states
[ContentView.swift L229-240](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/ContentView.swift#L229-L240): the AU only loads after a successful device setup. With input/output set to "None", denied mic permission, or capturer init failure, the main pane shows "Loading Audio Unit…" forever. Load the AU independently of devices, or show the actual error.

Related: [AUViewRepresentable.swift](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AUViewRepresentable.swift) ignores `audioUnit` changes in `updateNSViewController`. Add `.id(ObjectIdentifier(unit))` at the call site.

### M8. Buffer size changes are only partly applied
- There's no validation against `kAudioDevicePropertyBufferFrameSizeRange`. If 32 is rejected, the failure is only logged and the UI still shows 32.
- Changing the size doesn't rebuild the capturer or recompute ring thresholds (H2).
- Show the **actual** applied size and an estimated round-trip latency (buffers + `kAudioDevicePropertyLatency` + `SafetyOffset` + ring fill).

---

## Low

- **L1. CONTRIBUTING is contradicted by the code.** "Keep unsafe pointers confined to `CoreAudioHelper.swift`" → `AudioRingBuffer` / `AudioInputCapturer` live in `AudioEngineManager.swift`. "Document public APIs with `///`" → almost none are. Contributors will notice. Move `AudioRingBuffer` and `AudioInputCapturer` into their own files and drop meaningless `public` in an app target.
- **L2. Logging:** `print` + `fflush(stdout)` on every call. Use `os.Logger` (levels, Console.app, no stdout flush cost). Update CONTRIBUTING's "attach stdout logs" advice.
- **L3. Main-thread HAL calls:** `getAllDevices()` in `init` and in the notification handler, and `engine.start()` in `startEngine()`, can block for ms–100s of ms (Bluetooth, aggregates). The TSan hang shows main blocking in HAL behind `audioQueue`.
- **L4. UI nits:** duplicate `.font(.caption)` + `.font(.system…)` (one is dead) ×6. The meter is linear `×5` (saturates at −14 dBFS) with no clip indicator.
- **L5. `maxFrames = 4096`** silently truncates larger IO cycles ([L211](file:///Users/filiptepper/Code/HelixPlayer/HelixPlayer/AudioEngineManager.swift#L211)). Size it from `kAudioUnitProperty_MaximumFramesPerSlice`.
- **L6. Repo and legal hygiene:**
  - Bundle ID `com.helixplayer.*`: use a reverse-DNS domain you control (e.g. `pl.tepper.Pluck`).
  - "Helix" and "Line 6" are Yamaha Guitar Group trademarks. Add a "not affiliated with or endorsed by Line 6" disclaimer, and consider whether the app name is a risk.
  - `workflow_dispatch` default `v1.0.1` points at an existing tag. Remove the default.
  - Actions are pinned by tag, not SHA (supply chain). Acceptable for a hobby project, but worth knowing.
  - README "Xcode 13" requirement is unverified. State what CI actually uses.
  - `Info.plist` version is managed by both `release.sh` and the release workflow. Pick one source of truth.

---

## Test suite: verdict per test

| Test | Verdict | Why |
|---|---|---|
| `testCoreAudioDeviceFetching` | Environment-dependent | Fails on a CI runner with no audio devices. Asserts nothing about app logic |
| `testBufferSizeHelpers` | **Vacuous pass** | `guard … else { return }` passes when no device exists. Only checks `> 0` |
| `testAudioEngineManagerInitialization` | Harmful | Touches real hardware (mic, buffer sizes, Helix instantiation), outlives the test, asserts 2 default Bools |
| `testBypassToggle` | Trivial + harmful | Tests `Bool.toggle()`. Never checks `shouldBypassEffect` on an AU. Same hardware side effects |
| `testMultiChannelOutputRoutingWithAudioUnit` | Tests Apple, not you | Exercises `AVAudioEngine` directly. `XCTAssertNoThrow(engine.prepare())` can't fail (non-throwing). Starts real output |
| `testMultiOutputDetection` | OK but trivial | String prefix check |
| `testMultiOutputHandling` | Tests dead code | `createAggregateDevice` is unused by the app. Creates real aggregate devices on the dev machine |

**Missing coverage:** the ring buffer (the most bug-prone pure logic, added in the last commit) has **zero tests**. Also untested: the channel map, the reconfiguration state machine, device-change detection, RMS, and dB formatting.

## Proposed test plan

### Step 1: make code testable (no hardware)
1. Extract pure functions:
   - `OutputChannelMap.make(deviceChannels:mirrorToAllPairs:) -> [Int32]`. It's currently duplicated at L579-594 and L699-712.
   - `DeviceSelection.needsReconfiguration(old:new:devices:) -> Bool` (L333-357).
   - `Meter.rms(_:)`, `Meter.dB(_:)`.
2. Put hardware behind a protocol: `protocol AudioHardware { func devices() -> [AudioDevice]; func setBufferSize(...) -> Bool; func makeCapturer(...) throws -> AudioCapturing; ... }`. Add a `FakeAudioHardware` for tests.
3. Make `AudioEngineManager(hardware:auLoader:)` side-effect free until `activate()`.

### Step 2: meaningful unit tests
**Ring buffer** (`SPSCRingBuffer`):
- write N, read N → identical samples, same order
- read more than available → available samples, then zeros; return value == available
- wraparound across the capacity boundary preserves order
- write when full → returns frames written < requested; no corruption of unread data
- drift correction: fill above the high-water mark, read → the output is the *most recent* samples, and post-read fill == target
- **concurrency stress under TSan:** the producer writes a ramp `0,1,2,…` in random chunk sizes on one thread, and the consumer reads on another. Assert values are strictly increasing except at documented skip points, with zero TSan reports.

**Channel map:**
- `(2,false) → [0,1]`, `(1,false) → [0]`, `(16,false) → [0,1,-1×14]`
- `(4,true) → [0,1,0,1]`, `(5,true) → [0,1,0,1,-1]`, `(0,_) → []`

**State machine** (with fakes):
- `stop()` during `.configuring` → the final state is `.idle`, and the fake engine's `start` call count is 0, or it was stopped afterwards (regression test for C3)
- capturer start throws → the engine is stopped and the state is `.failed`
- stale AU-instantiate completion (version bumped) is discarded and the fake AU is not attached
- changing the input device to fewer channels clamps `selectedInputChannel`
- a rapid sequence of 5 selection changes → exactly 1 hardware reconfiguration (debounce)
- a device-list change that removes the selected input → `.failed("Input disconnected")`

### Step 3: separate hardware integration tests
- Move them to a separate test plan or scheme, not run on CI by default.
- Use `try XCTSkipUnless(!CoreAudioHelper.getAllDevices().isEmpty)` instead of silent `return`.
- Enable **Thread Sanitizer** on the unit-test scheme in CI (`-enableThreadSanitizer YES`).

---

## Pre-release checklist (in order)

1. [x] C4: fix the test target (remove duplicate sources, no app startup under XCTest). 12 unit tests pass under TSan.
2. [x] C1: atomic SPSC ring buffer + comprehensive tests (order, wraparound, underrun zero padding, concurrent stress).
3. [x] C2 + C3: single-queue ownership, unconditional stop with config versioning, rollback on partial start, regression tests.
4. [x] H1: fix input channel map scope & check status code (`kAudioUnitScope_Output` Element 1, confirmed working on hardware).
5. [x] C5: README/docs rewrite to match reality (AUHAL input capturer + ring buffer + AVAudioEngine). Deleted dead aggregate code.
6. [x] H5: single window (`CommandGroup(replacing: .newItem) {}`) and AppDelegate termination on window close.
7. [x] H2/H3/H4: dynamic drift protection, live nominal sample rate querying & alignment, hot-plug device listener lifecycle.
8. [x] H6: ad-hoc codesigning with entitlements in CI and Makefile (`codesign --force --deep -s - --entitlements ...`), macOS 15 Sequoia Gatekeeper instructions, documented `com.apple.security.cs.disable-library-validation`.
9. [x] L6: reverse-DNS bundle identifier (`pl.tepper.Pluck`), Line 6 / Helix trademark disclaimers.
10. [x] M-items addressed: M1 (atomic VU meters), M2 (input channel clamp), M5 (scoped shortcut), M6 (Unmanaged CFString compiler warnings, listener cleanup), M7 (AUViewRepresentable identity and explicit error states), L4 (cleaned duplicate SwiftUI fonts).
