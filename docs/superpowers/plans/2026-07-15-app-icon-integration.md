# App Icon Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the custom Monogram "H" application icon into the HelixPlayer macOS application bundle.

**Architecture:** Create an asset catalog (`Assets.xcassets`) containing `AppIcon.appiconset` with resized variants generated via a Python helper script. Modify the Xcode project generator script (`generate_xcodeproj.py`) to declare a PBXResourcesBuildPhase and compile the catalog on build.

**Tech Stack:** Python 3, Xcode CLI (`xcodebuild`), macOS `sips` tool.

## Global Constraints

- Target macOS version: macOS 12.0 or later.
- Do not check raw generated icon PNGs into Git; generate them programmatically or check the generated script.
- The high-resolution source icon artwork is located at `/Users/filiptepper/.gemini/antigravity/brain/c79dd1a3-83cb-4224-8614-0132f123de9d/helix_player_icon_monogram_1784160265279.jpg`.

---

### Task 1: Create Icon Generation Script

**Files:**
- Create: `scripts/generate_icons.py`

**Interfaces:**
- Consumes: High-resolution artwork at `/Users/filiptepper/.gemini/antigravity/brain/c79dd1a3-83cb-4224-8614-0132f123de9d/helix_player_icon_monogram_1784160265279.jpg`
- Produces: Generated icon PNG sizes and `Contents.json` at `HelixPlayer/Assets.xcassets/AppIcon.appiconset/`

- [ ] **Step 1: Write the generation script**
  Create the folder `scripts/` if it doesn't exist, and write `scripts/generate_icons.py` with the following content:

  ```python
  import os
  import json
  import subprocess

  source_image = "/Users/filiptepper/.gemini/antigravity/brain/c79dd1a3-83cb-4224-8614-0132f123de9d/helix_player_icon_monogram_1784160265279.jpg"
  target_dir = "HelixPlayer/Assets.xcassets/AppIcon.appiconset"

  os.makedirs(target_dir, exist_ok=True)

  sizes = [
      {"size": 16, "scale": 1, "filename": "icon_16x16.png"},
      {"size": 16, "scale": 2, "filename": "icon_16x16@2x.png"},
      {"size": 32, "scale": 1, "filename": "icon_32x32.png"},
      {"size": 32, "scale": 2, "filename": "icon_32x32@2x.png"},
      {"size": 128, "scale": 1, "filename": "icon_128x128.png"},
      {"size": 128, "scale": 2, "filename": "icon_128x128@2x.png"},
      {"size": 256, "scale": 1, "filename": "icon_256x256.png"},
      {"size": 256, "scale": 2, "filename": "icon_256x256@2x.png"},
      {"size": 512, "scale": 1, "filename": "icon_512x512.png"},
      {"size": 512, "scale": 2, "filename": "icon_512x512@2x.png"},
  ]

  contents = {
      "images": [],
      "info": {
          "version": 1,
          "author": "xcode"
      }
  }

  for item in sizes:
      px_size = item["size"] * item["scale"]
      out_path = os.path.join(target_dir, item["filename"])
      cmd = ["sips", "-z", str(px_size), str(px_size), source_image, "--out", out_path]
      subprocess.run(cmd, check=True)
      
      contents["images"].append({
          "size": f"{item['size']}x{item['size']}",
          "idiom": "mac",
          "filename": item["filename"],
          "scale": f"{item['scale']}x"
      })

  with open(os.path.join(target_dir, "Contents.json"), "w") as f:
      json.dump(contents, f, indent=2)

  print("Icons generated successfully.")
  ```

- [ ] **Step 2: Run the script to generate icons**
  Run: `python3 scripts/generate_icons.py`
  Expected Output: "Icons generated successfully."

- [ ] **Step 3: Verify output files exist**
  Run: `ls HelixPlayer/Assets.xcassets/AppIcon.appiconset`
  Expected Output: Shows 10 PNG files and `Contents.json`.

- [ ] **Step 4: Commit**
  Run:
  ```bash
  git add scripts/generate_icons.py
  git commit -m "feat: add icon generation script"
  ```

---

### Task 2: Update Xcode Project Generator

**Files:**
- Modify: `generate_xcodeproj.py`

**Interfaces:**
- Consumes: `generate_xcodeproj.py`
- Produces: Regenerated `HelixPlayer.xcodeproj/project.pbxproj` including resource catalog reference and resources build phase.

- [ ] **Step 1: Edit generate_xcodeproj.py**
  Modify [generate_xcodeproj.py](file:///Users/filiptepper/Code/HelixPlayer/generate_xcodeproj.py) to add the asset catalog references and PBXResourcesBuildPhase.
  
  Specifically, make these updates:
  
  1. Add to the `/* Begin PBXBuildFile section */` block:
     ```
     		00000017 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = 00000016 /* Assets.xcassets */; };
     ```
  2. Add to the `/* Begin PBXFileReference section */` block:
     ```
     		00000016 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = Assets.xcassets; path = Assets.xcassets; sourceTree = "<group>"; };
     ```
  3. Add to the `00000090 /* HelixPlayer */` children under `/* Begin PBXGroup section */`:
     ```
     				00000016 /* Assets.xcassets */,
     ```
  4. Add a new `/* Begin PBXResourcesBuildPhase section */` block right after the `PBXSourcesBuildPhase` section:
     ```
     /* Begin PBXResourcesBuildPhase section */
     		000000c1 /* Resources */ = {
     			isa = PBXResourcesBuildPhase;
     			buildActionMask = 2147483647;
     			files = (
     				00000017 /* Assets.xcassets in Resources */,
     			);
     			runOnlyForDeploymentPostprocessing = 0;
     		};
     /* End PBXResourcesBuildPhase section */
     ```
  5. Under target `00000040 /* HelixPlayer */`, add `000000c1 /* Resources */` to `buildPhases`:
     ```
     			buildPhases = (
     				000000b0 /* Sources */,
     				00000070 /* Frameworks */,
     				000000c1 /* Resources */,
     			);
     ```

- [ ] **Step 2: Regenerate the project file**
  Run: `make generate`
  Expected Output: "HelixPlayer.xcodeproj generated successfully."

- [ ] **Step 3: Run project validation**
  Run: `git diff HelixPlayer.xcodeproj/project.pbxproj`
  Expected Output: Shows the added resources build phase, file references, and group inclusion.

- [ ] **Step 4: Commit**
  Run:
  ```bash
  git add generate_xcodeproj.py
  git commit -m "feat: integrate Assets.xcassets into Xcode project generator"
  ```

---

### Task 3: Build and Verify Integration

**Files:**
- None (Build & run validation only)

**Interfaces:**
- Consumes: Xcode build system, generated app icon assets.
- Produces: Compiled `HelixPlayer.app` with app icon.

- [ ] **Step 1: Perform clean build**
  Run: `make clean && make build`
  Expected Output: Build completes successfully without warnings/errors.

- [ ] **Step 2: Run the application**
  Run: `make run`
  Expected Output: App launches successfully. Confirm that the application icon in the macOS dock has changed to the new Monogram "H" design.

- [ ] **Step 3: Pack and verify Release packaging**
  Run: `make release`
  Expected Output: Local release build completed: HelixPlayer-Release.zip. Double-click the generated zip and check HelixPlayer.app in Finder to verify the app icon displays properly.

- [ ] **Step 4: Clean up temporary untracked asset catalog files from Git**
  Run: `echo "HelixPlayer/Assets.xcassets" >> .gitignore`
  Verify with `git status` that generated icons are ignored.
  Commit:
  ```bash
  git add .gitignore
  git commit -m "chore: ignore generated Assets.xcassets"
  ```
