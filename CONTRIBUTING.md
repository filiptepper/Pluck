# Contributing to Pluck

First off, thank you for considering contributing to Pluck! It's people like you who make the open-source community such an amazing place to learn, inspire, and create.

---

## Code of Conduct

Please maintain a friendly, welcoming, and professional attitude in all interactions (Issues, Pull Requests, discussions).

---

## How to Report Bugs

When submitting a bug report or issue, please include as much detail as possible to help us reproduce the issue:
1. **macOS Version** (e.g. macOS 15.0 Sequoia)
2. **Audio Hardware** (e.g. Scarlett 2i2 USB interface, built-in Mac speakers)
3. **Step-by-step instructions** to reproduce the problem.
4. **Expected behavior** vs. **actual behavior**.
5. **App logs** from standard output if you ran it via terminal or Xcode.

---

## How to Propose Changes (Pull Requests)

Please follow these steps to make a contribution:

1. **Fork** the repository and create your branch from `main`:
   ```bash
   git checkout -b feat/your-awesome-feature
   ```
2. **Implement your changes**. 
3. **Handle New Files**: If you add any new source files to the project, you **must** update the `generate_xcodeproj.py` script. The Xcode project is fully generated and is not tracked in Git. Adding files in Xcode will modify the temporary project file, but those changes will be lost next time the generator runs. Add the file to the file lists and PBX groups inside `generate_xcodeproj.py`.
4. **Run Tests**:
   Before submitting, ensure all unit tests compile and pass:
   ```bash
   make test
   ```
5. **Commit your changes**. Write clear, concise commit messages.
6. **Submit a Pull Request** describing what the changes do and why they are necessary.

---

## Coding Standards

- **CoreAudio Boundaries**: Keep low-level hardware discovery, format conversions, and device configuration in [CoreAudioHelper.swift](Pluck/CoreAudioHelper.swift).
- **Real-Time Thread Hygiene**: The audio IO render callback runs on high-priority real-time threads. Never allocate memory, lock mutexes, perform ObjC/Swift retain-releases, or do I/O on the audio thread.
- **Thread Safety**: Never write to `@Published` properties from the real-time audio thread or background queues. Bridge real-time metrics (e.g. VU meters) with atomic memory barriers.
- **ThreadSanitizer Testing**: All ring buffer and synchronization changes must run cleanly under ThreadSanitizer (`make test`).
- **Self-Documenting Code**: Document public classes, structs, and methods using Swift's standard Triple-Slash (`///`) doc comment syntax.

---

Thank you again for contributing!
