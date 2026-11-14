# Native iPad port verification — 2026-11-14

Status: source preparation, not a compiled or installed iPad release.

## Checks available on this Linux computer

`python3 scripts/check.py` validates deterministic Xcode source membership, object references, the shared build/test scheme, iPad metadata and document associations, microphone description, privacy manifest, the opaque 1024-pixel app icon, and the native entry point/PencilKit canvas. It verifies the synthetic Android archives with Python's independent ZIP reader, including DEFLATE/data descriptors, CRCs, SHA-256 inventory, cross-notebook page links, and Trash.

`python3 scripts/package.py` reruns those checks and creates `dist/Folio-iPad-Native-3.0.0-source.zip` in the parent workspace. Every packaged source has a SHA-256 inventory, the finished ZIP is reopened and integrity-checked, and an adjacent checksum is written. A source ZIP does not establish that the Swift code compiles.

The macOS build script was run on Linux and rejected the host with exit status 2, as intended. Python syntax compilation and Bash syntax checks passed. The generated M4A fixture was independently probed as AAC audio with a 0.250-second duration. The blank PDF fixture is checked with Poppler's `pdfinfo`; those checks establish fixture validity only, not iPad rendering or playback.

## Prepared, not executed here

- 16 core XCTest methods cover Android streaming import, editable round trips, Trash, Unicode search, unknown fields, SHA-256/CRC failure, missing attachments, hostile paths, import budgets, extreme numeric values, collision remapping, stable page IDs/sections, resize protection, stale-save tickets, failed-import atomicity, and explicit index recovery.
- 6 native XCTest methods cover PencilKit import/persistence, partial erasure in portable exports, generated PDF/image readability, actual native PDF/audio validation, typed-note disk reload, and rejection of an overfull paste before changing the existing text.
- 1 UI test creates a notebook, types, backgrounds and relaunches the app, checks the stored paragraph, and captures a Simulator screenshot. It uses an isolated test library.
- The macOS workflow runs those suites and unsigned device compilation. It has not been submitted or run; there is no CI result or Apple build log.

No Swift compiler or Xcode is installed. A download probe to the official Swift distribution host failed DNS resolution in this sandbox. No signed `.ipa`, TestFlight upload, App Store release, simulator run, or physical iPad test is claimed.

On the user's follow-up requesting installation steps and accepting the annual Apple membership fee, a Codemagic configuration and `LINUX-TESTFLIGHT.md` were added. The configuration includes an unsigned check path and a separate manually started signed App Store Connect upload path. The latter needs the owner's private Apple API integration, distribution certificate, and profile. Local YAML parsing, Bash syntax for every embedded step, build-number rollover and invalid-input handling, and packaged guide/workflow paths and hashes passed. No Codemagic login, Apple enrollment, payment, signing-resource creation, or cloud execution took place.

## Required before using it as the main notebook app

Compile and run all prepared suites on macOS. Then verify on the actual M5 iPad: launch/rotation/multitasking, Apple Pencil pressure/palm rejection/eraser/lasso/undo, finger navigation and zoom, typing and RTL, library save/relaunch/background recovery, PDF visual fidelity and sharing, document import, microphone permission and audible recording playback, and an Android library migration with existing destination notebooks. Keep the original Android library and a Files backup until those checks pass.

SFTP backup and Android's ChatGPT integration are not ported; those are source feature gaps, not merely untested behavior. Other parity limits are listed in README.md.
