# Native Folio for iPad — 3.0.0 source

This is the native iPadOS port of Folio: SwiftUI and UIKit screens, Apple's PencilKit handwriting engine, PDFKit/Core Graphics documents, and AVFoundation recordings. It contains no website, WebView, JavaScript, Safari shortcut, or server dependency. The minimum target is iPadOS 17; the project targets iPads, including the M5 iPad Pro.

**Status: native source project prepared; Apple compilation, signing, and device use are unverified. No installable IPA has been produced.** The development computer is Linux without Swift, Xcode, an Apple signing account, or an attached iPad. Linux project/fixture checks are described in [VERIFICATION.md](VERIFICATION.md). Do not interpret them as a successful iOS build.

Open `Folio.xcodeproj` on macOS with Xcode to build. See [INSTALL.md](INSTALL.md) for the actual installation paths and the remaining requirements for a Linux-only owner.

For Linux plus an Apple Developer membership, use the [cloud build and TestFlight steps](LINUX-TESTFLIGHT.md). The source package includes a root `codemagic.yaml` for unsigned checks and signed private upload after account/signing setup; this workflow is prepared, not executed.

## Native implementation

- Searchable library, notebook covers, folders, profiles, Favorites, and recoverable Trash.
- Native PencilKit canvas and Apple tool picker for pens, colors, widths, marker, eraser, and lasso. Pencil draws; fingers navigate by default. Optional finger drawing uses two fingers for navigation. Palm rejection and hardware gestures need real Apple Pencil testing.
- Zoomable paper, native paragraph editing and RTL text, undo/redo for handwriting, editable labels/links, five paper templates, line counts, and length changes that reject cutting off existing content.
- Page insertion, duplication, reordering, deletion confirmation, titles, contents headings, resume position, and PDF page numbering.
- Up to six open notebooks in a horizontal desk, with two visible panes on wide layouts. Each pane keeps its own page and native zoom. This does not yet reproduce the Android desk's complete shared-position/zoom behavior.
- Offline PDF import and annotation, PDF output, Word/UTF-8 text import, and PNG sharing of an explicitly selected page. Word import extracts paragraphs and tabs; it does not reproduce Word images, tables, or exact layout.
- Microphone recording and imported M4A playback using native audio APIs. Completed clips are attached to their original page; navigation and backgrounding stop recording.
- An accessible local knowledge map of folder neighbors and explicit notebook links, with a material list. This is a two-dimensional map, not the Android 3D renderer.
- Editable `.folio` import/export and whole-library ZIP migration, including Android ink, paragraph text, labels, PDF/audio assets, sections, profiles, favorites, and Trash. The Android APK is integrity-checked in a library inventory and never executed.
- Local app storage with immutable notebook revisions and an atomic library index. Imports validate before committing; collisions become independent copies with remapped notebook links and asset names. Failed imports keep the destination library. A previous index can be recovered explicitly after an opening failure. Original attachments and older revisions are retained; storage compaction is not implemented yet.

PencilKit drawings are stored in their original native representation, plus sampled portable Android strokes. Native eraser masks and lasso transforms remain exact in the native representation; portable strokes approximate curves, ink texture, and partial erasure for Android compatibility. Unknown notebook/page JSON fields are retained. Connection credentials are excluded from portable preferences.

## Existing notebooks

On Android, export **Transfer → Export app + all notebooks**, or export an individual editable `.folio`. Copy the original archive to iPad Files, then choose **Folio → Library actions → Import from Files**. Review the preview and tap **Import**. Existing destination notebooks are kept, including when you restore a second time. Keep the Android originals until you have opened pages and played recordings on the actual iPad.

Limits: 512 MB uncompressed per library, 1,000 notebooks per import, 5,000 pages per notebook, 200 MB per individual PDF/archive entry, and 1,000 pages per PDF import. The native library ZIP format is `folio-native-library`, version 1; restore it in this native edition. Individual `.folio` files use Android's notebook/PDF/audio structure.

## Feature parity still open

This is a native port of the note-taking workflow, not a verified complete reproduction of every Android feature. Android's ChatGPT account integration, in-app assistant renderer, SFTP/background server backups, full profile appearance controls, handwriting recognition/search, and the 3D graph are not implemented. Explicit PNG sharing and local Files backups are available in source. No note content is automatically sent to a service.

Physical-device verification is required for Apple Pencil latency, palm rejection, hover/squeeze/double-tap behavior, keyboard baselines/RTL, rotation and multitasking, PDF rendering/export, microphone permission, actual recording/playback, background saves, and library migration. Missing source features and unverified hardware behavior must not be described as shipping functionality.

## Development

The app uses Apple frameworks and the local `FolioCore` Swift package; there are no third-party runtime downloads. `CZlib` binds the platform zlib for Android-compatible stored/DEFLATE ZIPs. CryptoKit verifies SHA-256 inventories.

On Linux:

```sh
cd ipad-native
python3 scripts/check.py
python3 scripts/package.py
```

On macOS with Xcode and an installed iPad simulator runtime:

```sh
cd ipad-native
bash scripts/build-macos.sh check
```

That runs the core XCTest suite, native UIKit/PencilKit/PDF/import tests, a create/type/relaunch UI test, and unsigned ARM device compilation. The UI test uses a separate test library; it never resets the normal library. Simulator results are not physical-iPad results.

`python3 scripts/project.py` regenerates the checked-in Xcode project, shared scheme, metadata, and opaque app icon after adding Swift files. `scripts/make_fixtures.py` regenerates synthetic Android archives; it needs ffmpeg only if the existing generated audio fixture is missing. The workflow at `../.github/workflows/folio-native.yml` is prepared for a macOS GitHub Actions runner and has not been run here. It uploads test results and an explicitly unsigned device build; it does not publish or sign an app.
