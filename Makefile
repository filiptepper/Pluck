VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Pluck/Info.plist)

.PHONY: all generate build test run clean release dmg

all: generate build

generate:
	python3 scripts/generate_icons.py
	python3 generate_xcodeproj.py

build: generate
	xcodebuild -project Pluck.xcodeproj -scheme Pluck -configuration Debug -sdk macosx build CONFIGURATION_BUILD_DIR=$(PWD)/build/Debug

test: generate
	xcodebuild -project Pluck.xcodeproj -scheme PluckTests -configuration Debug -sdk macosx test CONFIGURATION_BUILD_DIR=$(PWD)/build/Debug

run: build
	./build/Debug/Pluck.app/Contents/MacOS/Pluck

release: generate
	xcodebuild -project Pluck.xcodeproj -scheme Pluck -configuration Release -sdk macosx build CONFIGURATION_BUILD_DIR=$(PWD)/build/Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
	codesign --force --deep -s - --entitlements Pluck/Pluck.entitlements build/Release/Pluck.app
	cd build/Release && zip -r ../../Pluck-Release.zip Pluck.app
	@echo "Local release build completed: Pluck-Release.zip"

dmg: release
	rm -rf build/DMG
	mkdir -p build/DMG
	cp -R build/Release/Pluck.app build/DMG/
	ln -s /Applications build/DMG/Applications
	hdiutil create -volname "Pluck" -srcfolder build/DMG -ov -format UDZO Pluck-$(VERSION).dmg
	rm -rf build/DMG
	@echo "Local DMG build completed: Pluck-$(VERSION).dmg"

clean:
	rm -rf build Pluck.xcodeproj HelixPlayer.xcodeproj Pluck-Release.zip HelixPlayer-Release.zip Pluck-*.dmg HelixPlayer-*.dmg Pluck/Assets.xcassets
