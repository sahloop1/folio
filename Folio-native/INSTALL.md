# Install the native iPad app

There is no signed native installer in this folder yet. The source ZIP is not an IPA and cannot be installed by tapping it in Files. Renaming an Android APK cannot turn it into an iPad app.

## Linux plus paid Apple membership

The user is willing to enroll in Apple's developer program. Follow the [step-by-step cloud build and native TestFlight installation guide](LINUX-TESTFLIGHT.md). A root `codemagic.yaml` now provides an unsigned check workflow and a signed App Store Connect upload workflow, once the owner's accounts, certificate, and profile are configured. Neither has been run here. You can attempt the unsigned build before paying Apple.

## Linux build constraints

The Swift code can be edited and packaged on Linux. This checkout cannot build against Apple's iPadOS SDK, run Xcode/Simulator, or obtain your Apple signing identity. The native port therefore still needs an Apple build and signing step before it can become your independently installed Folio app.

A borrowed Mac with Xcode and your free Apple Account supports installing a personal development build on your own iPad. A paid Apple Developer membership is not required for this route, but Apple limits Personal Team provisioning to seven days, after which it must be rebuilt/reinstalled. [Apple account and Personal Team requirements](https://developer.apple.com/help/account/basics/about-your-developer-account).

For TestFlight or App Store distribution without owning a Mac, use a macOS build service and an Apple Developer Program account. The repository includes a macOS CI workflow for compilation/testing. Running that workflow alone does not supply signing credentials or install the app. No account has been created, paid for, connected, or used by this work. [Apple distribution programs](https://developer.apple.com/help/account/membership/programs-overview/), [uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

Swift Playground can run native Swift development projects on iPad, but its preview is a development environment and is not the independently installed app requested here. It is not the delivery path for this project. [Apple's Swift Playground description](https://developer.apple.com/swift-playground/).

## Personal installation with a borrowed Mac

1. Copy `ipad-native/` (or the unpacked `Folio-native/` source folder) to the Mac. Install an Xcode version supported by that Mac and your iPadOS version. [Apple's Xcode requirements](https://developer.apple.com/xcode/system-requirements).
2. Open `Folio.xcodeproj`. Select the **Folio** target → **Signing & Capabilities** → your Personal Team. If Apple reports that `net.sahlab.folio` is unavailable, choose a unique identifier belonging to your account and retain that identifier for updates.
3. Connect and trust the iPad, select it as the run destination, enable Developer Mode if prompted, and run **Product → Run**. This performs actual native compilation, signing, and installation. Compile errors, if any, must be fixed before installation; this project has not yet had an Xcode build.
4. Verify creating a notebook, Apple Pencil writing, typing, relaunch persistence, PDF export, and voice-note playback. Export a Files backup before importing your full Android library.
5. Keep the bundle ID and signing team for updates. Do not delete the existing app to update it; deleting the app removes its local notes.

## Build and distribution commands

Run the prepared checks on a Mac before signing:

```sh
bash scripts/build-macos.sh check
```

For a configured signing team, archive and export:

```sh
FOLIO_TEAM_ID=YOUR_TEAM_ID bash scripts/build-macos.sh archive
FOLIO_EXPORT_OPTIONS=/path/to/your/ExportOptions.plist bash scripts/build-macos.sh export
```

An export-options plist must match the actual team, certificate, device registrations, and distribution method. Xcode Organizer can create/export that configuration. A build signed for a simulator cannot be installed on a physical iPad. An unsigned device build still needs valid signing and provisioning.

Never put Apple passwords, certificates, provisioning files, or App Store Connect private keys into the source ZIP. The source package deliberately contains none.
