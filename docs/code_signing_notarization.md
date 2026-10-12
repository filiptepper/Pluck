# macOS Code Signing & Notarization Guide

To distribute Pluck without users seeing macOS Gatekeeper warnings ("app cannot be opened because it is from an unidentified developer"), you must **code-sign** the application with a valid Apple Developer ID certificate and **notarize** it with Apple's Notary Service.

This guide explains how to set this up locally and how to automate it in your GitHub Actions workflow.

---

## Prerequisites

1. **Apple Developer Account:** You must be enrolled in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year).
2. **Developer ID Application Certificate:**
   - Go to the Apple Developer portal -> **Certificates, Identifiers & Profiles**.
   - Create a new certificate of type **Developer ID Application**.
   - Download and double-click to install it into your Mac's **Keychain Access**.
3. **App-Specific Password:**
   - Go to [appleid.apple.com](https://appleid.apple.com/) and generate an app-specific password (e.g., `abcd-efgh-ijkl-mnop`) for your Apple ID. This is required for notarization.
4. **Your Team ID:** Find your 10-character Team ID in the membership section of the Developer portal (e.g., `AB1234CD56`).

---

## Part 1: Local Signing & Notarization

If you want to sign and notarize a release manually on your local Mac:

### 1. Build and Sign the App
Run the build command, passing your Developer ID Certificate name (e.g., `Developer ID Application: Your Name (AB1234CD56)`):

```bash
# 1. Build release
make release

# 2. Codesign the .app bundle (with hardened runtime and entitlements enabled)
codesign --force --options runtime --deep --entitlements Pluck/Pluck.entitlements --sign "Developer ID Application: Your Name (AB1234CD56)" build/Release/Pluck.app
```

> [!IMPORTANT]
> **Why `Pluck.entitlements` is Critical:**
> When Hardened Runtime (`--options runtime`) is enabled, macOS strictly enforces library validation by default, blocking any third-party dynamic libraries or Audio Units not signed by your Team ID.
> Pluck requires:
> - `com.apple.security.device.audio-input`: Grants microphone/hardware input access.
> - `com.apple.security.cs.disable-library-validation`: Permits loading third-party in-process Audio Units (like Line 6 Helix Native). Without this, the AU will fail to load.
> - `com.apple.security.cs.allow-unsigned-executable-memory`: Allows plugins that generate dynamic DSP assembly.


### 2. Create the DMG
Create the DMG file using `hdiutil`:
```bash
rm -rf build/DMG && mkdir -p build/DMG
cp -R build/Release/Pluck.app build/DMG/
ln -s /Applications build/DMG/Applications
hdiutil create -volname "Pluck" -srcfolder build/DMG -ov -format UDZO Pluck-1.0.dmg
rm -rf build/DMG
```

### 3. Notarize the DMG
Notarize the DMG using `notarytool`:
```bash
xcrun notarytool submit Pluck-1.0.dmg \
    --apple-id "your-apple-id@email.com" \
    --password "your-app-specific-password" \
    --team-id "AB1234CD56" \
    --wait
```

### 4. Staple the Ticket
Once notarization succeeds, attach the approval ticket directly to the DMG:
```bash
xcrun stapler staple Pluck-1.0.dmg
```
Now, users downloading `Pluck-1.0.dmg` will be able to open the app without Gatekeeper warnings.

---

## Part 2: Automating in GitHub Actions

To make the GitHub Actions workflow automatically sign and notarize your DMG on every tag release, follow these steps:

### Step 1: Export the Signing Certificate
1. Open **Keychain Access** on your Mac.
2. Right-click your **Developer ID Application** certificate and select **Export**.
3. Save it as a `.p12` file (e.g., `certificate.p12`) with a strong password.
4. Convert the `.p12` file to a Base64 string so it can be stored in GitHub Secrets:
   ```bash
   base64 -i certificate.p12 -o certificate.txt
   ```

### Step 2: Add Secrets to your GitHub Repository
In your GitHub repository settings, go to **Settings -> Secrets and variables -> Actions**, and add the following repository secrets:

| Secret Name | Description |
|---|---|
| `MACOS_CERTIFICATE` | The full contents of `certificate.txt` (the Base64-encoded `.p12` file) |
| `MACOS_CERTIFICATE_PWD` | The password you used when exporting the `.p12` certificate |
| `APPLE_ID` | Your Apple ID email address |
| `APPLE_ID_PASSWORD` | The app-specific password you generated at appleid.apple.com |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |

### Step 3: Update `release.yml`
Update your `.github/workflows/release.yml` workflow to import the certificate, sign, package, notarize, and staple the DMG. 

Below is the modified release job configuration:

```yaml
      # 1. Import Developer Certificate
      - name: Install Apple Certificate
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.MACOS_CERTIFICATE }}
          P12_PASSWORD: ${{ secrets.MACOS_CERTIFICATE_PWD }}
          KEYCHAIN_PASSWORD: "temporary-keychain-password"
        run: |
          # Create variables
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db

          # Import certificate from secrets
          echo -n "$BUILD_CERTIFICATE_BASE64" | base64 --decode --output "$CERTIFICATE_PATH"

          # Create temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Import certificate into keychain
          security import "$CERTIFICATE_PATH" -k "$KEYCHAIN_PATH" -P "$P12_PASSWORD" -T /usr/bin/codesign;
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          
          # Make keychain default
          security default-keychain -s "$KEYCHAIN_PATH"

      # 2. Build app bundle
      - name: Build Application
        run: |
          python3 generate_xcodeproj.py
          xcodebuild -project Pluck.xcodeproj \
                     -scheme Pluck \
                     -configuration Release \
                     -sdk macosx \
                     build \
                     CONFIGURATION_BUILD_DIR=${{ github.workspace }}/build/Release

      # 3. Codesign the .app bundle with Hardened Runtime and Entitlements
      - name: Codesign App
        run: |
          codesign --force --options runtime --deep --entitlements Pluck/Pluck.entitlements --sign "Developer ID Application" ${{ github.workspace }}/build/Release/Pluck.app

      # 4. Package as DMG
      - name: Create DMG Disk Image
        run: |
          rm -rf build/DMG
          mkdir -p build/DMG
          cp -R build/Release/Pluck.app build/DMG/
          ln -s /Applications build/DMG/Applications
          hdiutil create -volname "Pluck" -srcfolder build/DMG -ov -format UDZO Pluck-${{ github.ref_name }}.dmg
          rm -rf build/DMG

      # 5. Notarize DMG
      - name: Notarize DMG
        run: |
          xcrun notarytool submit Pluck-${{ github.ref_name }}.dmg \
            --apple-id "${{ secrets.APPLE_ID }}" \
            --password "${{ secrets.APPLE_ID_PASSWORD }}" \
            --team-id "${{ secrets.APPLE_TEAM_ID }}" \
            --wait

      # 6. Staple Notarization Ticket to DMG
      - name: Staple DMG
        run: |
          xcrun stapler staple Pluck-${{ github.ref_name }}.dmg

      # 7. Create ZIP (Optional, signed but unstapled)
      - name: Create ZIP
        run: |
          cd build/Release
          zip -r ../../Pluck-${{ github.ref_name }}.zip Pluck.app

      # 8. Create GitHub Release and Upload signed assets
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            Pluck-${{ github.ref_name }}.dmg
            Pluck-${{ github.ref_name }}.zip
          name: Release ${{ github.ref_name }}
          body: |
            ## Pluck ${{ github.ref_name }}
            
            Welcome to the new release of Pluck!
            
            ### Installation
            1. Download `Pluck-${{ github.ref_name }}.dmg` below.
            2. Double-click to open.
            3. Drag `Pluck.app` to your `/Applications` folder.
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
