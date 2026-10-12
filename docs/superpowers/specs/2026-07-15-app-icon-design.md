# Design Specification: HelixPlayer Monogram "H" App Icon Integration

* **Date**: 2026-07-15
* **Status**: Proposed

## Context & Objectives

HelixPlayer currently has no custom application icon, displaying the default blank macOS application icon. 
Following design exploration, the **Monogram "H"** concept has been chosen. This concept combines a metallic guitar neck (representing physical guitar input), a responsive VU meter (representing audio processing output), and a blue/emerald green double-helix (representing the Line 6 Helix Native integration).

This document outlines the implementation details for generating the required icon sizes, packaging them into a macOS asset catalog, and modifying the programmatic Xcode project generator to compile the icon with the application.

## Detailed Design

### 1. Icon Generation
We will use a Python script `scripts/generate_icons.py` to automate the generation of the asset catalog. It will:
- Read the high-resolution source image from `/Users/filiptepper/.gemini/antigravity/brain/c79dd1a3-83cb-4224-8614-0132f123de9d/helix_player_icon_monogram_1784160265279.jpg`.
- Create the target folder structure at `HelixPlayer/Assets.xcassets/AppIcon.appiconset`.
- Run macOS `sips` (System Image Utility) via subprocess commands to resize the source image to the 10 required PNG files:
  - `icon_16x16.png` (16x16)
  - `icon_16x16@2x.png` (32x32)
  - `icon_32x32.png` (32x32)
  - `icon_32x32@2x.png` (64x64)
  - `icon_128x128.png` (128x128)
  - `icon_128x128@2x.png` (256x256)
  - `icon_256x256.png` (256x256)
  - `icon_256x256@2x.png` (512x512)
  - `icon_512x512.png` (512x512)
  - `icon_512x512@2x.png` (1024x1024)
- Generate a `Contents.json` file inside `AppIcon.appiconset` referencing all the image assets.

### 2. Xcode Project Modifications (`generate_xcodeproj.py`)
To build the assets into the application:
1. **File Reference**: Define `Assets.xcassets` inside `project.pbxproj`'s File Reference section:
   ```
   00000016 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = Assets.xcassets; path = HelixPlayer/Assets.xcassets; sourceTree = "<group>"; };
   ```
2. **Build File Reference**: Add a build file representation for the resources phase:
   ```
   00000017 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = 00000016 /* Assets.xcassets */; };
   ```
3. **Group Membership**: Include `00000016` in the `HelixPlayer` group children.
4. **Resources Build Phase**: Define a `PBXResourcesBuildPhase` section containing the assets build file:
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
5. **Target Build Phases**: Add `000000c1 /* Resources */` to the build phases of target `00000040 /* HelixPlayer */`.

## Verification Plan

### Automated/Compilation Verification
- Run `make clean && make build` to ensure the project generates correctly and compiles without resource errors.

### Manual UI Verification
- Launch the built application with `make run`.
- Confirm that the new Monogram "H" icon appears in the macOS dock.
- Verify the icon displays correctly in Finder when viewing the packaged `HelixPlayer.app`.
