# HelixPlayer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a native macOS SwiftUI application that hosts Line 6 Helix Native AU, routes a selected input channel from a selected input device through it, and outputs to a selected output device using a programmatically created aggregate device.

**Architecture:** We use CoreAudio HAL to enumerate audio hardware, query channels, and construct a programmatic aggregate device. We use `AVAudioEngine` for low-latency routing, load Helix Native using `AVAudioUnit.instantiate`, wrap its GUI using `NSViewControllerRepresentable`, and test the components using native `XCTest`.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, CoreAudio, XCTest.

## Global Constraints
*   Target OS: macOS 11.0 or later.
*   Sandboxing: Disabled to ensure third-party AUv2 plugins load correctly.
*   Microphone Permissions: `NSMicrophoneUsageDescription` in Info.plist is required.
*   Main target: Helix Native (`aumf` / `6HPA` / `LSIX`). Fallback target: Apple Delay (`aufx` / `dely` / `appl`).

---

### Task 1: Scaffolding and Xcode Project Generation
Generate the directory structure, source files, and a python script to create the `HelixPlayer.xcodeproj` file so it is ready to open and build in Xcode.

**Files:**
*   Create: `HelixPlayer/Info.plist`
*   Create: `HelixPlayer/HelixPlayerApp.swift`
*   Create: `HelixPlayer/ContentView.swift`
*   Create: `HelixPlayerTests/HelixPlayerTests.swift`
*   Create: `generate_xcodeproj.py`
*   Create: `Makefile`

**Interfaces:**
*   Produces: An executable Xcode project `HelixPlayer.xcodeproj` containing targets `HelixPlayer` and `HelixPlayerTests`.

- [ ] **Step 1: Create the Info.plist**
  Write the application's configuration with microphone permission and bundle identifiers.
  File: `HelixPlayer/Info.plist`
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>CFBundleIdentifier</key>
      <string>com.helixplayer.HelixPlayer</string>
      <key>CFBundleName</key>
      <string>HelixPlayer</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>LSMinimumSystemVersion</key>
      <string>11.0</string>
      <key>NSMicrophoneUsageDescription</key>
      <string>HelixPlayer needs access to your audio interface inputs to route your guitar signal.</string>
      <key>LSBackgroundOnly</key>
      <false/>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Create the placeholder App entry point**
  File: `HelixPlayer/HelixPlayerApp.swift`
  ```swift
  import SwiftUI

  @main
  struct HelixPlayerApp: App {
      var body: some Scene {
          WindowGroup {
              ContentView()
          }
      }
  }
  ```

- [ ] **Step 3: Create the placeholder ContentView**
  File: `HelixPlayer/ContentView.swift`
  ```swift
  import SwiftUI

  struct ContentView: View {
      var body: some View {
          Text("HelixPlayer Scaffolding")
              .frame(width: 800, height: 600)
      }
  }
  ```

- [ ] **Step 4: Create the placeholder Tests file**
  File: `HelixPlayerTests/HelixPlayerTests.swift`
  ```swift
  import XCTest

  final class HelixPlayerTests: XCTestCase {
      func testPlaceholder() {
          XCTAssertTrue(true)
      }
  }
  ```

- [ ] **Step 5: Create the python script to generate HelixPlayer.xcodeproj**
  Write a script to programmatically output a standard Xcode project package.
  File: `generate_xcodeproj.py`
  ```python
  import os

  xcodeproj_path = "HelixPlayer.xcodeproj"
  os.makedirs(xcodeproj_path, exist_ok=True)

  pbxproj_content = """// !$*UTF8*$!
  {
  	archiveVersion = 1;
  	classes = {
  	};
  	objectVersion = 54;
  	objects = {

  /* Begin PBXBuildFile section */
  		00000001 /* Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = 00000005 /* Info.plist */; };
  		00000002 /* HelixPlayerApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 00000006 /* HelixPlayerApp.swift */; };
  		00000003 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 00000007 /* ContentView.swift */; };
  		00000004 /* HelixPlayerTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 00000008 /* HelixPlayerTests.swift */; };
  		00000010 /* CoreAudioHelper.swift in Sources */ = {isa = PBXBuildFile; fileRef = 00000011 /* CoreAudioHelper.swift */; };
  		00000012 /* AudioEngineManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 00000013 /* AudioEngineManager.swift */; };
  /* End PBXBuildFile section */

  /* Begin PBXContainerItemProxy section */
  		00000020 /* PBXContainerItemProxy */ = {
  			isa = PBXContainerItemProxy;
  			containerPortal = 00000030 /* Project object */;
  			proxyType = 1;
  			remoteGlobalIDString = 00000040 /* HelixPlayer */;
  			remoteInfo = HelixPlayer;
  		};
  /* End PBXContainerItemProxy section */

  /* Begin PBXFileReference section */
  		00000005 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
  		00000006 /* HelixPlayerApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HelixPlayerApp.swift; sourceTree = "<group>"; };
  		00000007 /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
  		00000008 /* HelixPlayerTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HelixPlayerTests.swift; sourceTree = "<group>"; };
  		00000011 /* CoreAudioHelper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CoreAudioHelper.swift; sourceTree = "<group>"; };
  		00000013 /* AudioEngineManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AudioEngineManager.swift; sourceTree = "<group>"; };
  		00000050 /* HelixPlayer.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = HelixPlayer.app; sourceTree = BUILT_PRODUCTS_DIR; };
  		00000060 /* HelixPlayerTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = HelixPlayerTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
  /* End PBXFileReference section */

  /* Begin PBXFrameworksBuildPhase section */
  		00000070 /* Frameworks */ = {
  			isa = PBXFrameworksBuildPhase;
  			buildActionMask = 2147483647;
  			files = (
  			);
  			runOnlyForDeploymentPostprocessing = 0;
  		};
  		00000071 /* Frameworks */ = {
  			isa = PBXFrameworksBuildPhase;
  			buildActionMask = 2147483647;
  			files = (
  			);
  			runOnlyForDeploymentPostprocessing = 0;
  		};
  /* End PBXFrameworksBuildPhase section */

  /* Begin PBXGroup section */
  		00000080 /* Main Group */ = {
  			isa = PBXGroup;
  			children = (
  				00000090 /* HelixPlayer */,
  				00000091 /* HelixPlayerTests */,
  				00000092 /* Products */,
  			);
  			sourceTree = "<group>";
  		};
  		00000090 /* HelixPlayer */ = {
  			isa = PBXGroup;
  			children = (
  				00000005 /* Info.plist */,
  				00000006 /* HelixPlayerApp.swift */,
  				00000007 /* ContentView.swift */,
  				00000011 /* CoreAudioHelper.swift */,
  				00000013 /* AudioEngineManager.swift */,
  			);
  			path = HelixPlayer;
  			sourceTree = "<group>";
  		};
  		00000091 /* HelixPlayerTests */ = {
  			isa = PBXGroup;
  			children = (
  				00000008 /* HelixPlayerTests.swift */,
  			);
  			path = HelixPlayerTests;
  			sourceTree = "<group>";
  		};
  		00000092 /* Products */ = {
  			isa = PBXGroup;
  			children = (
  				00000050 /* HelixPlayer.app */,
  				00000060 /* HelixPlayerTests.xctest */,
  			);
  			name = Products;
  			sourceTree = "<group>";
  		};
  /* End PBXGroup section */

  /* Begin PBXNativeTarget section */
  		00000040 /* HelixPlayer */ = {
  			isa = PBXNativeTarget;
  			buildConfigurationList = 000000a0 /* Build configuration list for PBXNativeTarget "HelixPlayer" */;
  			buildPhases = (
  				000000b0 /* Sources */,
  				00000070 /* Frameworks */,
  			);
  			buildRules = (
  			);
  			dependencies = (
  			);
  			name = HelixPlayer;
  			productName = HelixPlayer;
  			productReference = 00000050 /* HelixPlayer.app */;
  			productType = "com.apple.product-type.application";
  		};
  		00000041 /* HelixPlayerTests */ = {
  			isa = PBXNativeTarget;
  			buildConfigurationList = 000000a1 /* Build configuration list for PBXNativeTarget "HelixPlayerTests" */;
  			buildPhases = (
  				000000b1 /* Sources */,
  				00000071 /* Frameworks */,
  			);
  			buildRules = (
  			);
  			dependencies = (
  				000000c0 /* TargetDependency */,
  			);
  			name = HelixPlayerTests;
  			productName = HelixPlayerTests;
  			productReference = 00000060 /* HelixPlayerTests.xctest */;
  			productType = "com.apple.product-type.bundle.unit-test";
  		};
  /* End PBXNativeTarget section */

  /* Begin PBXProject section */
  		00000030 /* Project object */ = {
  			isa = PBXProject;
  			attributes = {
  				LastSwiftUpdateCheck = 1300;
  				LastUpgradeCheck = 1300;
  				TargetAttributes = {
  					00000040 = {
  						CreatedOnToolsVersion = 13.0;
  					};
  					00000041 = {
  						CreatedOnToolsVersion = 13.0;
  						TestTargetID = 00000040 /* HelixPlayer */;
  					};
  				};
  			};
  			buildConfigurationList = 000000d0 /* Build configuration list for PBXProject "HelixPlayer" */;
  			compatibilityVersion = "Xcode 9.3";
  			developmentRegion = en;
  			hasScannedForEncodings = 0;
  			knownRegions = (
  				en,
  				Base,
  			);
  			mainGroup = 00000080 /* Main Group */;
  			productRefGroup = 00000092 /* Products */;
  			projectDirPath = "";
  			projectRoot = "";
  			targets = (
  				00000040 /* HelixPlayer */,
  				00000041 /* HelixPlayerTests */,
  			);
  		};
  /* End PBXProject section */

  /* Begin PBXSourcesBuildPhase section */
  		000000b0 /* Sources */ = {
  			isa = PBXSourcesBuildPhase;
  			buildActionMask = 2147483647;
  			files = (
  				00000002 /* HelixPlayerApp.swift in Sources */,
  				00000003 /* ContentView.swift in Sources */,
  				00000010 /* CoreAudioHelper.swift in Sources */,
  				00000012 /* AudioEngineManager.swift in Sources */,
  			);
  			runOnlyForDeploymentPostprocessing = 0;
  		};
  		000000b1 /* Sources */ = {
  			isa = PBXSourcesBuildPhase;
  			buildActionMask = 2147483647;
  			files = (
  				00000004 /* HelixPlayerTests.swift in Sources */,
  				00000010 /* CoreAudioHelper.swift in Sources */,
  				00000012 /* AudioEngineManager.swift in Sources */,
  			);
  			runOnlyForDeploymentPostprocessing = 0;
  		};
  /* End PBXSourcesBuildPhase section */

  /* Begin PBXTargetDependency section */
  		000000c0 /* TargetDependency */ = {
  			isa = PBXTargetDependency;
  			target = 00000040 /* HelixPlayer */;
  			targetProxy = 00000020 /* PBXContainerItemProxy */;
  		};
  /* End PBXTargetDependency section */

  /* Begin XCBuildConfiguration section */
  		000000e0 /* Debug */ = {
  			isa = XCBuildConfiguration;
  			buildSettings = {
  				ALWAYS_SEARCH_USER_PATHS = NO;
  				CLANG_ANALYZER_NONNULL = YES;
  				CLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
  				CLANG_CXX_LIBRARY = "libc++";
  				CLANG_ENABLE_MODULES = YES;
  				CLANG_ENABLE_OBJC_ARC = YES;
  				CLANG_ENABLE_OBJC_WEAK = YES;
  				COPY_PHASE_STRIP = NO;
  				DEBUG_INFORMATION_FORMAT = dwarf;
  				ENABLE_STRICT_OBJC_MSGSEND = YES;
  				ENABLE_TESTABILITY = YES;
  				GCC_C_LANGUAGE_STANDARD = gnu11;
  				GCC_DYNAMIC_NO_PIC = NO;
  				GCC_NO_COMMON_BLOCKS = YES;
  				GCC_OPTIMIZATION_LEVEL = 0;
  				GCC_PREPROCESSOR_DEFINITIONS = (
  					"DEBUG=1",
  					"$(inherited)",
  				);
  				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
  				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
  				GCC_WARN_UNDECLARED_SELECTOR = YES;
  				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
  				GCC_WARN_UNUSED_FUNCTION = YES;
  				GCC_WARN_UNUSED_VARIABLE = YES;
  				MACOSX_DEPLOYMENT_TARGET = 11.0;
  				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
  				MTL_FAST_MATH = YES;
  				ONLY_ACTIVE_ARCH = YES;
  				SDKROOT = macosx;
  				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
  				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
  			};
  			name = Debug;
  		};
  		000000e1 /* Release */ = {
  			isa = XCBuildConfiguration;
  			buildSettings = {
  				ALWAYS_SEARCH_USER_PATHS = NO;
  				CLANG_ANALYZER_NONNULL = YES;
  				CLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
  				CLANG_CXX_LIBRARY = "libc++";
  				CLANG_ENABLE_MODULES = YES;
  				CLANG_ENABLE_OBJC_ARC = YES;
  				CLANG_ENABLE_OBJC_WEAK = YES;
  				COPY_PHASE_STRIP = NO;
  				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
  				ENABLE_NS_ASSERTIONS = NO;
  				ENABLE_STRICT_OBJC_MSGSEND = YES;
  				GCC_C_LANGUAGE_STANDARD = gnu11;
  				GCC_NO_COMMON_BLOCKS = YES;
  				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
  				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
  				GCC_WARN_UNDECLARED_SELECTOR = YES;
  				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
  				GCC_WARN_UNUSED_FUNCTION = YES;
  				GCC_WARN_UNUSED_VARIABLE = YES;
  				MACOSX_DEPLOYMENT_TARGET = 11.0;
  				MTL_ENABLE_DEBUG_INFO = NO;
  				MTL_FAST_MATH = YES;
  				SDKROOT = macosx;
  				SWIFT_COMPILATION_MODE = wholemodule;
  				SWIFT_OPTIMIZATION_LEVEL = "-O";
  			};
  			name = Release;
  		};
  		000000e2 /* Debug */ = {
  			isa = XCBuildConfiguration;
  			buildSettings = {
  				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
  				CODE_SIGN_STYLE = Automatic;
  				COMBINE_HIDPI_IMAGES = YES;
  				INFOPLIST_FILE = HelixPlayer/Info.plist;
  				LD_RUNPATH_SEARCH_PATHS = (
  					"$(inherited)",
  					"@executable_path/../Frameworks",
  				);
  				PRODUCT_BUNDLE_IDENTIFIER = com.helixplayer.HelixPlayer;
  				PRODUCT_NAME = "$(TARGET_NAME)";
  				SWIFT_VERSION = 5.0;
  			};
  			name = Debug;
  		};
  		000000e3 /* Release */ = {
  			isa = XCBuildConfiguration;
  			buildSettings = {
  				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
  				CODE_SIGN_STYLE = Automatic;
  				COMBINE_HIDPI_IMAGES = YES;
  				INFOPLIST_FILE = HelixPlayer/Info.plist;
  				LD_RUNPATH_SEARCH_PATHS = (
  					"$(inherited)",
  					"@executable_path/../Frameworks",
  				);
  				PRODUCT_BUNDLE_IDENTIFIER = com.helixplayer.HelixPlayer;
  				PRODUCT_NAME = "$(TARGET_NAME)";
  				SWIFT_VERSION = 5.0;
  			};
  			name = Release;
  		};
  		000000e4 /* Debug */ = {
  			isa = XCBuildConfiguration;
  			buildSettings = {
  				BUNDLE_LOADER = "$(TEST_HOST)";
  				CODE_SIGN_STYLE = Automatic;
  				PRODUCT_BUNDLE_IDENTIFIER = com.helixplayer.HelixPlayerTests;
  				PRODUCT_NAME = "$(TARGET_NAME)";
  				SWIFT_VERSION = 5.0;
  				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/HelixPlayer.app/Contents/MacOS/HelixPlayer";
  			};
  			name = Debug;
  		};
  		000000e5 /* Release */ = {
  			isa = XCBuildConfiguration;
  			buildSettings = {
  				BUNDLE_LOADER = "$(TEST_HOST)";
  				CODE_SIGN_STYLE = Automatic;
  				PRODUCT_BUNDLE_IDENTIFIER = com.helixplayer.HelixPlayerTests;
  				PRODUCT_NAME = "$(TARGET_NAME)";
  				SWIFT_VERSION = 5.0;
  				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/HelixPlayer.app/Contents/MacOS/HelixPlayer";
  			};
  			name = Release;
  		};
  /* End XCBuildConfiguration section */

  /* Begin XCConfigurationList section */
  		000000d0 /* Build configuration list for PBXProject "HelixPlayer" */ = {
  			isa = XCConfigurationList;
  			buildConfigurations = (
  				000000e0 /* Debug */,
  				000000e1 /* Release */,
  			);
  			defaultConfigurationIsVisible = 0;
  			defaultConfigurationName = Release;
  		};
  		000000a0 /* Build configuration list for PBXNativeTarget "HelixPlayer" */ = {
  			isa = XCConfigurationList;
  			buildConfigurations = (
  				000000e2 /* Debug */,
  				000000e3 /* Release */,
  			);
  			defaultConfigurationIsVisible = 0;
  			defaultConfigurationName = Release;
  		};
  		000000a1 /* Build configuration list for PBXNativeTarget "HelixPlayerTests" */ = {
  			isa = XCConfigurationList;
  			buildConfigurations = (
  				000000e4 /* Debug */,
  				000000e5 /* Release */,
  			);
  			defaultConfigurationIsVisible = 0;
  			defaultConfigurationName = Release;
  		};
  /* End XCConfigurationList section */
  	};
  	rootObject = 00000030 /* Project object */;
  }
  """

  with open(os.path.join(xcodeproj_path, "project.pbxproj"), "w") as f:
      f.write(pbxproj_content)
  print("HelixPlayer.xcodeproj generated successfully.")
  ```

- [ ] **Step 6: Create the Makefile**
  A Makefile to coordinate running the generator, compiling targets, running tests, and executing the app.
  File: `Makefile`
  ```makefile
  .PHONY: all generate build test run clean

  all: generate build

  generate:
  	python3 generate_xcodeproj.py

  build: generate
  	xcodebuild -project HelixPlayer.xcodeproj -scheme HelixPlayer -configuration Debug -sdk macosx build

  test: generate
  	xcodebuild -project HelixPlayer.xcodeproj -scheme HelixPlayerTests -configuration Debug -sdk macosx test

  run: build
  	./build/Debug/HelixPlayer.app/Contents/MacOS/HelixPlayer

  clean:
  	rm -rf build HelixPlayer.xcodeproj
  ```

- [ ] **Step 7: Verify generation and compilation**
  Run: `python3 generate_xcodeproj.py`
  Expected: Prints "HelixPlayer.xcodeproj generated successfully."
  Run: `make build`
  Expected: Succeeds and builds the app under `build/Debug/HelixPlayer.app`.

- [ ] **Step 8: Commit**
  ```bash
  git add HelixPlayer/Info.plist HelixPlayer/HelixPlayerApp.swift HelixPlayer/ContentView.swift HelixPlayerTests/HelixPlayerTests.swift generate_xcodeproj.py Makefile
  git commit -m "chore: setup Xcode project structure and scaffolding"
  ```

---

### Task 2: CoreAudio C-Bridge Implementation (CoreAudioHelper.swift)
Implement a robust interface to interact with macOS CoreAudio HAL to get device lists, check input/output channels, set buffer sizes, and create programmatic aggregate devices.

**Files:**
*   Create: `HelixPlayer/CoreAudioHelper.swift`
*   Modify: `HelixPlayerTests/HelixPlayerTests.swift`

**Interfaces:**
*   Produces:
    *   `struct AudioDevice: Identifiable, Hashable`
    *   `class CoreAudioHelper`
        *   `static func getAllDevices() -> [AudioDevice]`
        *   `static func createAggregateDevice(inputUID: String, outputUID: String) -> AudioDeviceID?`
        *   `static func destroyAggregateDevice(_ deviceID: AudioDeviceID) -> Bool`
        *   `static func setBufferSize(deviceID: AudioDeviceID, size: UInt32) -> Bool`
        *   `static func getBufferSize(deviceID: AudioDeviceID) -> UInt32`

- [ ] **Step 1: Write CoreAudioHelper and AudioDevice struct**
  Write the CoreAudio bridging logic in Swift.
  File: `HelixPlayer/CoreAudioHelper.swift`
  ```swift
  import CoreAudio
  import Foundation

  public struct AudioDevice: Identifiable, Hashable {
      public var id: AudioDeviceID { deviceID }
      public let deviceID: AudioDeviceID
      public let name: String
      public let uid: String
      public let inputChannels: Int
      public let outputChannels: Int
      public let sampleRate: Double

      public func hash(into hasher: inout Hasher) {
          hasher.combine(deviceID)
      }
      
      public static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
          return lhs.deviceID == rhs.deviceID
      }
  }

  public class CoreAudioHelper {
      public static func getAllDevices() -> [AudioDevice] {
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioHardwarePropertyDevices,
              mScope: kAudioObjectPropertyScopeGlobal,
              mElement: 0
          )
          var size: UInt32 = 0
          var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
          guard status == noErr else { return [] }
          
          let count = Int(size) / MemoryLayout<AudioDeviceID>.size
          var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
          status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
          guard status == noErr else { return [] }
          
          var devices: [AudioDevice] = []
          for deviceID in deviceIDs {
              // 1. Get Name
              var nameAddress = AudioObjectPropertyAddress(
                  mSelector: kAudioDevicePropertyDeviceNameCFString,
                  mScope: kAudioObjectPropertyScopeGlobal,
                  mElement: 0
              )
              var nameCF: CFString = "" as CFString
              var nameSize = UInt32(MemoryLayout<CFString>.size)
              status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameCF)
              let name = (status == noErr) ? (nameCF as String) : "Unknown Device"
              
              // 2. Get UID
              var uidAddress = AudioObjectPropertyAddress(
                  mSelector: kAudioDevicePropertyDeviceUID,
                  mScope: kAudioObjectPropertyScopeGlobal,
                  mElement: 0
              )
              var uidCF: CFString = "" as CFString
              var uidSize = UInt32(MemoryLayout<CFString>.size)
              status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidCF)
              let uid = (status == noErr) ? (uidCF as String) : ""
              
              // 3. Channels Count
              let inputChannels = getChannelCount(deviceID: deviceID, isInput: true)
              let outputChannels = getChannelCount(deviceID: deviceID, isInput: false)
              
              // 4. Sample Rate
              var rateAddress = AudioObjectPropertyAddress(
                  mSelector: kAudioDevicePropertyNominalSampleRate,
                  mScope: kAudioObjectPropertyScopeGlobal,
                  mElement: 0
              )
              var sampleRate: Double = 0.0
              var rateSize = UInt32(MemoryLayout<Double>.size)
              status = AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &sampleRate)
              
              devices.append(AudioDevice(
                  deviceID: deviceID,
                  name: name,
                  uid: uid,
                  inputChannels: inputChannels,
                  outputChannels: outputChannels,
                  sampleRate: sampleRate
              ))
          }
          return devices
      }
      
      private static func getChannelCount(deviceID: AudioDeviceID, isInput: Bool) -> Int {
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioDevicePropertyStreamConfiguration,
              mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
              mElement: 0
          )
          var size: UInt32 = 0
          var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
          guard status == noErr && size > 0 else { return 0 }
          
          let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
          defer { bufferList.deallocate() }
          
          status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
          guard status == noErr else { return 0 }
          
          let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
          var channelCount = 0
          for buffer in buffers {
              channelCount += Int(buffer.mNumberChannels)
          }
          return channelCount
      }
      
      public static func getBufferSize(deviceID: AudioDeviceID) -> UInt32 {
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioDevicePropertyBufferFrameSize,
              mScope: kAudioObjectPropertyScopeGlobal,
              mElement: 0
          )
          var bufferSize: UInt32 = 0
          var size = UInt32(MemoryLayout<UInt32>.size)
          let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &bufferSize)
          return status == noErr ? bufferSize : 0
      }
      
      public static func setBufferSize(deviceID: AudioDeviceID, size: UInt32) -> Bool {
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioDevicePropertyBufferFrameSize,
              mScope: kAudioObjectPropertyScopeGlobal,
              mElement: 0
          )
          var bufferSize = size
          let dataSize = UInt32(MemoryLayout<UInt32>.size)
          let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &bufferSize)
          return status == noErr
      }
      
      public static func createAggregateDevice(inputUID: String, outputUID: String) -> AudioDeviceID? {
          let subDevices: [[String: Any]] = [
              [
                  kAudioSubDeviceUIDKey: inputUID,
                  kAudioSubDeviceDriftCompensationKey: 1
              ],
              [
                  kAudioSubDeviceUIDKey: outputUID,
                  kAudioSubDeviceDriftCompensationKey: 0 // Clock master
              ]
          ]
          
          let desc: [String: Any] = [
              kAudioAggregateDeviceNameKey: "HelixPlayer Aggregate",
              kAudioAggregateDeviceUIDKey: "com.helixplayer.aggregate",
              kAudioAggregateDeviceSubDeviceListKey: subDevices,
              kAudioAggregateDeviceIsPrivateKey: 0 // Public
          ]
          
          var aggregateID: AudioDeviceID = 0
          let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregateID)
          return status == noErr ? aggregateID : nil
      }
      
      public static func destroyAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
          let status = AudioHardwareDestroyAggregateDevice(deviceID)
          return status == noErr
      }
  }
  ```

- [ ] **Step 2: Add unit tests for CoreAudioHelper**
  File: `HelixPlayerTests/HelixPlayerTests.swift`
  ```swift
  import XCTest
  @testable import HelixPlayer

  final class HelixPlayerTests: XCTestCase {
      func testCoreAudioDeviceFetching() {
          let devices = CoreAudioHelper.getAllDevices()
          XCTAssertFalse(devices.isEmpty, "System should report at least one audio device (e.g., system output).")
          for dev in devices {
              XCTAssertFalse(dev.name.isEmpty, "Device must have a non-empty name.")
              XCTAssertFalse(dev.uid.isEmpty, "Device must have a non-empty UID.")
          }
      }
      
      func testBufferSizeHelpers() {
          let devices = CoreAudioHelper.getAllDevices()
          guard let testDevice = devices.first(where: { $0.outputChannels > 0 }) else { return }
          let currentSize = CoreAudioHelper.getBufferSize(deviceID: testDevice.deviceID)
          XCTAssertGreaterThan(currentSize, 0, "Buffer size should be greater than 0.")
      }
  }
  ```

- [ ] **Step 3: Run the tests to verify passing**
  Run: `make test`
  Expected: Tests pass with no failures.

- [ ] **Step 4: Commit**
  ```bash
  git add HelixPlayer/CoreAudioHelper.swift HelixPlayerTests/HelixPlayerTests.swift
  git commit -m "feat: implement CoreAudio hardware helpers and unit tests"
  ```

---

### Task 3: Audio Engine Manager (AudioEngineManager.swift)
Implement the central audio state machine manager that configures `AVAudioEngine`, loads the Audio Unit (Helix Native or AUDelay), creates aggregate devices, performs routing, and provides VU levels to the UI.

**Files:**
*   Create: `HelixPlayer/AudioEngineManager.swift`
*   Modify: `HelixPlayerTests/HelixPlayerTests.swift`

**Interfaces:**
*   Produces:
      *   `class AudioEngineManager: ObservableObject`
          *   `@Published var isRunning: Bool`
          *   `@Published var inputLevel: Float`
          *   `@Published var outputLevel: Float`
          *   `@Published var helixUnit: AVAudioUnit?`
          *   `@Published var selectedInputDevice: AudioDevice?`
          *   `@Published var selectedOutputDevice: AudioDevice?`
          *   `@Published var selectedInputChannel: Int`
          *   `@Published var selectedBufferSize: UInt32`
          *   `@Published var isBypassed: Bool`
          *   `func startEngine()`
          *   `func stopEngine()`
          *   `func toggleBypass()`

- [ ] **Step 1: Write AudioEngineManager**
  File: `HelixPlayer/AudioEngineManager.swift`
  ```swift
  import Foundation
  import AVFoundation
  import CoreAudio
  import Combine

  public class AudioEngineManager: ObservableObject {
      @Published public var isRunning = false
      @Published public var inputLevel: Float = 0.0
      @Published public var outputLevel: Float = 0.0
      @Published public var helixUnit: AVAudioUnit? = nil
      
      @Published public var selectedInputDevice: AudioDevice? = nil {
          didSet { triggerReconfiguration() }
      }
      @Published public var selectedOutputDevice: AudioDevice? = nil {
          didSet { triggerReconfiguration() }
      }
      @Published public var selectedInputChannel: Int = 0 {
          didSet { triggerReconfiguration() }
      }
      @Published public var selectedBufferSize: UInt32 = 128 {
          didSet { updateDeviceBufferSize() }
      }
      @Published public var isBypassed = false {
          didSet { helixUnit?.bypass = isBypassed }
      }
      
      private var engine = AVAudioEngine()
      private var aggregateDeviceID: AudioDeviceID? = nil
      private var isConfiguring = false
      private var activityToken: NSObjectProtocol? = nil
      
      public static let availableBufferSizes: [UInt32] = [32, 64, 128, 256, 512]
      
      public init() {
          // Select default devices
          let devices = CoreAudioHelper.getAllDevices()
          selectedInputDevice = devices.first(where: { $0.inputChannels > 0 })
          selectedOutputDevice = devices.first(where: { $0.outputChannels > 0 })
          
          NotificationCenter.default.addObserver(
              forName: .AVAudioEngineConfigurationChange,
              object: nil,
              queue: .main
          ) { [weak self] _ in
              self?.triggerReconfiguration()
          }
      }
      
      deinit {
          stopEngine()
      }
      
      public func startEngine() {
          guard !isRunning else { return }
          configureAudioSession()
          
          do {
              try engine.start()
              isRunning = true
              
              // Prevent sleep & throttling
              activityToken = ProcessInfo.processInfo.beginActivity(
                  options: [.userInitiated, .idleSystemSleepDisabled],
                  reason: "Live Audio Hosting"
              )
          } catch {
              print("Failed to start AVAudioEngine: \(error)")
          }
      }
      
      public func stopEngine() {
          guard isRunning else { return }
          engine.stop()
          engine.reset()
          isRunning = false
          
          if let token = activityToken {
              ProcessInfo.processInfo.endActivity(token)
              activityToken = nil
          }
          
          cleanupAggregateDevice()
      }
      
      public func toggleBypass() {
          isBypassed.toggle()
      }
      
      private func triggerReconfiguration() {
          guard !isConfiguring else { return }
          isConfiguring = true
          
          let wasRunning = isRunning
          if wasRunning { stopEngine() }
          
          setupAudioGraph()
          
          if wasRunning { startEngine() }
          isConfiguring = false
      }
      
      private func updateDeviceBufferSize() {
          if let device = selectedOutputDevice {
              _ = CoreAudioHelper.setBufferSize(deviceID: device.deviceID, size: selectedBufferSize)
          }
          if let device = selectedInputDevice {
              _ = CoreAudioHelper.setBufferSize(deviceID: device.deviceID, size: selectedBufferSize)
          }
      }
      
      private func cleanupAggregateDevice() {
          if let aggregateID = aggregateDeviceID {
              _ = CoreAudioHelper.destroyAggregateDevice(aggregateID)
              aggregateDeviceID = nil
          }
      }
      
      private func configureAudioSession() {
          // macOS does not use AVAudioSession.sharedInstance().setCategory() like iOS.
          // Native CoreAudio properties set directly.
      }
      
      private func setupAudioGraph() {
          engine = AVAudioEngine()
          cleanupAggregateDevice()
          
          guard let input = selectedInputDevice, let output = selectedOutputDevice else { return }
          
          var targetDeviceID = output.deviceID
          
          // Create aggregate device if input and output are physical different devices
          if input.deviceID != output.deviceID {
              if let aggregateID = CoreAudioHelper.createAggregateDevice(inputUID: input.uid, outputUID: output.uid) {
                  self.aggregateDeviceID = aggregateID
                  targetDeviceID = aggregateID
              }
          }
          
          // Set device on the HAL Unit
          let outputUnit = engine.outputNode.audioUnit!
          var deviceID = targetDeviceID
          let deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
          AudioUnitSetProperty(
              outputUnit,
              kAudioOutputUnitProperty_CurrentDevice,
              kAudioUnitScope_Global,
              0,
              &deviceID,
              deviceSize
          )
          
          updateDeviceBufferSize()
          
          // Define plugin (Helix Native or Fallback AUDelay)
          var desc = AudioComponentDescription(
              componentType: kAudioUnitType_MusicEffect, // aumf
              componentSubType: 0x36485041,              // '6HPA' (Helix Native)
              componentManufacturer: 0x4c534958,         // 'LSIX' (Line 6)
              componentFlags: 0,
              componentFlagsMask: 0
          )
          
          // Check if Helix is available. If not, use Apple Delay
          let component = AudioComponentFindNext(nil, &desc)
          if component == nil {
              print("Helix Native not found. Using Apple Delay fallback.")
              desc = AudioComponentDescription(
                  componentType: kAudioUnitType_Effect,  // aufx
                  componentSubType: kAudioUnitSubType_Delay, // dely
                  componentManufacturer: kAudioUnitManufacturer_Apple, // appl
                  componentFlags: 0,
                  componentFlagsMask: 0
              )
          }
          
          let group = DispatchGroup()
          group.enter()
          
          AVAudioUnit.instantiate(with: desc, options: []) { [weak self] (audioUnit, error) in
              defer { group.leave() }
              guard let self = self, let au = audioUnit else { return }
              self.helixUnit = au
              self.engine.attach(au)
          }
          
          _ = group.wait(timeout: .now() + 5.0)
          
          guard let helix = helixUnit else { return }
          
          let hardwareInputFormat = engine.inputNode.inputFormat(forBus: 0)
          let hardwareOutputFormat = engine.outputNode.outputFormat(forBus: 0)
          
          // Audio Engine Input -> Helix (with selected mono channel mapping)
          let monoFormat = AVAudioFormat(
              commonFormat: .pcmFormatFloat32,
              sampleRate: hardwareInputFormat.sampleRate,
              channels: 1,
              interleaved: false
          )!
          
          // Connect Input Node -> Helix Node
          engine.connect(engine.inputNode, to: helix, format: monoFormat)
          
          // Connect Helix Node -> Output Node
          engine.connect(helix, to: engine.outputNode, format: hardwareOutputFormat)
          
          // Install Volume Meter Tap
          installMeterTaps()
          
          engine.prepare()
      }
      
      private func installMeterTaps() {
          let bufferSize: AVAudioFrameCount = 1024
          
          // Input Tap
          engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] (buffer, _) in
              guard let self = self else { return }
              self.inputLevel = self.calculateRMS(buffer: buffer)
          }
          
          // Output Tap
          engine.outputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] (buffer, _) in
              guard let self = self else { return }
              self.outputLevel = self.calculateRMS(buffer: buffer)
          }
      }
      
      private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
          guard let channelData = buffer.floatChannelData else { return 0.0 }
          let channelCount = Int(buffer.format.channelCount)
          let frameLength = Int(buffer.frameLength)
          
          var sum: Float = 0.0
          var sampleCount = 0
          
          // If we want a specific channel (selectedInputChannel), read that channel
          let targetChannel = min(max(0, selectedInputChannel), channelCount - 1)
          let data = channelData[targetChannel]
          
          for i in 0..<frameLength {
              let val = data[i]
              sum += val * val
              sampleCount += 1
          }
          
          if sampleCount == 0 { return 0.0 }
          let rms = sqrt(sum / Float(sampleCount))
          return rms
      }
  }
  ```

- [ ] **Step 2: Add unit tests for AudioEngineManager**
  File: `HelixPlayerTests/HelixPlayerTests.swift`
  ```swift
  import XCTest
  import AVFoundation
  @testable import HelixPlayer

  final class HelixPlayerTests: XCTestCase {
      func testCoreAudioDeviceFetching() {
          let devices = CoreAudioHelper.getAllDevices()
          XCTAssertFalse(devices.isEmpty)
      }
      
      func testBufferSizeHelpers() {
          let devices = CoreAudioHelper.getAllDevices()
          guard let testDevice = devices.first(where: { $0.outputChannels > 0 }) else { return }
          let currentSize = CoreAudioHelper.getBufferSize(deviceID: testDevice.deviceID)
          XCTAssertGreaterThan(currentSize, 0)
      }
      
      func testAudioEngineManagerInitialization() {
          let manager = AudioEngineManager()
          XCTAssertNotNil(manager.selectedInputDevice)
          XCTAssertNotNil(manager.selectedOutputDevice)
          XCTAssertFalse(manager.isRunning)
          XCTAssertFalse(manager.isBypassed)
      }
      
      func testBypassToggle() {
          let manager = AudioEngineManager()
          XCTAssertFalse(manager.isBypassed)
          manager.toggleBypass()
          XCTAssertTrue(manager.isBypassed)
      }
  }
  ```

- [ ] **Step 3: Run the tests to verify passing**
  Run: `make test`
  Expected: PASS

- [ ] **Step 4: Commit**
  ```bash
  git add HelixPlayer/AudioEngineManager.swift HelixPlayerTests/HelixPlayerTests.swift
  git commit -m "feat: implement AudioEngineManager and integration tests"
  ```

---

### Task 4: UI Development (NSViewControllerRepresentable & ContentView)
Implement the Audio Unit UI bridge and construct the primary SwiftUI application layout.

**Files:**
*   Modify: `HelixPlayer/ContentView.swift`
*   Create: `HelixPlayer/AUViewRepresentable.swift`

**Interfaces:**
*   Produces:
      *   `struct AUViewRepresentable: NSViewControllerRepresentable`
      *   `struct ContentView: View`

- [ ] **Step 1: Implement AUViewRepresentable**
  File: `HelixPlayer/AUViewRepresentable.swift`
  ```swift
  import SwiftUI
  import AppKit
  import AVFoundation

  public struct AUViewRepresentable: NSViewControllerRepresentable {
      public let audioUnit: AVAudioUnit?

      public func makeNSViewController(context: Context) -> NSViewController {
          let containerVC = NSViewController()
          containerVC.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
          
          guard let auNode = audioUnit else {
              showEmptyMessage(vc: containerVC, message: "No Audio Unit Loaded")
              return containerVC
          }
          
          auNode.auAudioUnit.requestViewController { (vc) in
              DispatchQueue.main.async {
                  if let viewController = vc {
                      containerVC.addChild(viewController)
                      viewController.view.frame = containerVC.view.bounds
                      viewController.view.autoresizingMask = [.width, .height]
                      containerVC.view.addSubview(viewController.view)
                  } else {
                      self.showEmptyMessage(vc: containerVC, message: "This Audio Unit doesn't support custom GUI.")
                  }
              }
          }
          
          return containerVC
      }

      public func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
          // Handle sizing/updates if needed
      }
      
      private func showEmptyMessage(vc: NSViewController, message: String) {
          let textField = NSTextField(labelWithString: message)
          textField.alignment = .center
          textField.font = NSFont.systemFont(ofSize: 18, weight: .medium)
          textField.textColor = .secondaryLabelColor
          textField.frame = vc.view.bounds
          textField.autoresizingMask = [.width, .height]
          vc.view.addSubview(textField)
      }
  }
  ```

- [ ] **Step 2: Implement ContentView**
  File: `HelixPlayer/ContentView.swift`
  ```swift
  import SwiftUI

  struct ContentView: View {
      @StateObject private var manager = AudioEngineManager()
      
      var body: some View {
          HStack(spacing: 0) {
              // Sidebar (Left Controls)
              VStack(alignment: .leading, spacing: 20) {
                  Text("HelixPlayer")
                      .font(.system(size: 24, weight: .bold, design: .rounded))
                      .foregroundColor(.primary)
                      .padding(.bottom, 10)
                  
                  // Engine Switcher
                  Button(action: {
                      if manager.isRunning {
                          manager.stopEngine()
                      } else {
                          manager.startEngine()
                      }
                  }) {
                      HStack {
                          Image(systemName: manager.isRunning ? "stop.fill" : "play.fill")
                          Text(manager.isRunning ? "Stop Engine" : "Start Engine")
                              .fontWeight(.semibold)
                      }
                      .frame(maxWidth: .infinity)
                      .padding(.vertical, 10)
                      .background(manager.isRunning ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                      .foregroundColor(.white)
                      .cornerRadius(8)
                  }
                  .buttonStyle(PlainButtonStyle())
                  
                  Divider()
                  
                  // Device Selection
                  VStack(alignment: .leading, spacing: 12) {
                      Text("AUDIO ROUTING")
                          .font(.caption)
                          .fontWeight(.bold)
                          .foregroundColor(.secondary)
                      
                      // Input Device
                      VStack(alignment: .leading, spacing: 4) {
                          Text("Input Device")
                              .font(.caption2)
                          Picker("", selection: $manager.selectedInputDevice) {
                              Text("None").tag(nil as AudioDevice?)
                              ForEach(CoreAudioHelper.getAllDevices().filter { $0.inputChannels > 0 }, id: \.self) { dev in
                                  Text(dev.name).tag(dev as AudioDevice?)
                              }
                          }
                          .labelsHidden()
                      }
                      
                      // Input Channel
                      VStack(alignment: .leading, spacing: 4) {
                          Text("Input Channel")
                              .font(.caption2)
                          Picker("", selection: $manager.selectedInputChannel) {
                              if let channels = manager.selectedInputDevice?.inputChannels {
                                  ForEach(0..<channels, id: \.self) { ch in
                                      Text("Channel \(ch + 1)").tag(ch)
                                  }
                              } else {
                                  Text("No channels").tag(0)
                              }
                          }
                          .labelsHidden()
                      }
                      
                      // Output Device
                      VStack(alignment: .leading, spacing: 4) {
                          Text("Output Device")
                              .font(.caption2)
                          Picker("", selection: $manager.selectedOutputDevice) {
                              Text("None").tag(nil as AudioDevice?)
                              ForEach(CoreAudioHelper.getAllDevices().filter { $0.outputChannels > 0 }, id: \.self) { dev in
                                  Text(dev.name).tag(dev as AudioDevice?)
                              }
                          }
                          .labelsHidden()
                      }
                  }
                  
                  Divider()
                  
                  // Settings (Buffer / Latency)
                  VStack(alignment: .leading, spacing: 12) {
                      Text("PERFORMANCE")
                          .font(.caption)
                          .fontWeight(.bold)
                          .foregroundColor(.secondary)
                      
                      VStack(alignment: .leading, spacing: 4) {
                          Text("Buffer Size (Latency)")
                              .font(.caption2)
                          Picker("", selection: $manager.selectedBufferSize) {
                              ForEach(AudioEngineManager.availableBufferSizes, id: \.self) { size in
                                  Text("\(size) Samples").tag(size)
                              }
                          }
                          .labelsHidden()
                      }
                      
                      Toggle("Bypass Plugin", isOn: $manager.isBypassed)
                          .toggleStyle(CheckboxToggleStyle())
                          .font(.body)
                  }
                  
                  Divider()
                  
                  // VU Meters
                  VStack(alignment: .leading, spacing: 12) {
                      Text("AUDIO LEVELS")
                          .font(.caption)
                          .fontWeight(.bold)
                          .foregroundColor(.secondary)
                      
                      VStack(alignment: .leading, spacing: 4) {
                          HStack {
                              Text("Input")
                                  .font(.caption2)
                              Spacer()
                              Text(String(format: "%.1f dB", 20 * log10(max(0.0001, manager.inputLevel))))
                                  .font(.system(.caption2, design: .monospaced))
                          }
                          ProgressView(value: min(1.0, manager.inputLevel * 5.0))
                              .tint(.green)
                      }
                      
                      VStack(alignment: .leading, spacing: 4) {
                          HStack {
                              Text("Output")
                                  .font(.caption2)
                              Spacer()
                              Text(String(format: "%.1f dB", 20 * log10(max(0.0001, manager.outputLevel))))
                                  .font(.system(.caption2, design: MonospacedEncoding.self as? Font.Design ?? .monospaced))
                          }
                          ProgressView(value: min(1.0, manager.outputLevel * 5.0))
                              .tint(.blue)
                      }
                  }
                  
                  Spacer()
                  
                  // Panic / Mute button
                  Button(action: {
                      manager.stopEngine()
                  }) {
                      Text("PANIC (MUTE ALL)")
                          .font(.caption)
                          .fontWeight(.bold)
                          .frame(maxWidth: .infinity)
                          .padding(.vertical, 8)
                          .background(Color.red)
                          .foregroundColor(.white)
                          .cornerRadius(6)
                  }
                  .buttonStyle(PlainButtonStyle())
              }
              .frame(width: 250)
              .padding(20)
              .background(Color(NSColor.windowBackgroundColor))
              
              // Divider
              Rectangle()
                  .fill(Color(NSColor.separatorColor))
                  .frame(width: 1)
                  .edgesIgnoringSafeArea(.all)
              
              // Main Window (Plugin Editor GUI)
              VStack(spacing: 0) {
                  if manager.helixUnit != nil {
                      AUViewRepresentable(audioUnit: manager.helixUnit)
                  } else {
                      VStack {
                          ProgressView()
                              .scaleEffect(1.5)
                              .padding(.bottom, 10)
                          Text("Loading Audio Unit...")
                              .foregroundColor(.secondary)
                      }
                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                  }
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(NSColor.underPageBackgroundColor))
          }
          .frame(width: 1050, height: 650)
      }
  }
  ```

- [ ] **Step 3: Run project compilation and validation**
  Run: `make build`
  Expected: Success, binary compiled.

- [ ] **Step 4: Commit**
  ```bash
  git add HelixPlayer/ContentView.swift HelixPlayer/AUViewRepresentable.swift
  git commit -m "feat: complete SwiftUI frontend and NSView wrapping interfaces"
  ```

---

## Execution Handoff
Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
