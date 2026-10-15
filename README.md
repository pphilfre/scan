# Folio

A native iPhone and iPad notebook for handwritten ideas. Built for **iOS 26** with SwiftUI, Liquid Glass, VisionKit, Vision, SwiftData, PencilKit and PDFKit. No third-party app dependencies, accounts, subscriptions, or remote OCR services.

## What is implemented

- Native document scanner with edge detection, cropping, straightening and enhancement; multi-photo and multi-file imports, including PDFs.
- Accurate, language-aware on-device Vision recognition, with book titles and tags as custom vocabulary. Original image bytes are saved before recognition; editable OCR text is stored separately. Interrupted recognition resumes on launch, and failed recognition can be retried.
- Custom books with colours, SF Symbols and two cover styles. Maths, Physics and Economics are created as empty starter books.
- Draggable section dividers and pages, native reorder controls, automatic numbering, and page moves between books. Moving a divider updates the section membership of pages following it.
- Search across book titles, section names, page titles, OCR text, tags and detected dates, with highlighted text snippets. The floating glass input and adjacent close control follow the keyboard safe area.
- Native page curls (scroll transitions with Reduce Motion), pinch and double-tap zoom, full-screen reading, thumbnails and a recognised-text view.
- Rename, duplicate, rotate, delete, annotate, tag and favourite pages. Original scans and PencilKit ink remain separate. Recently viewed pages appear in the library.
- Automatic titles, date detection, suggested sections and reviewed text corrections.
- Local SwiftData persistence, optional CloudKit sync, and PDF sharing for pages and complete books, including annotations and rotations.

Handwriting accuracy depends on the source. Vision does not guarantee mathematical notation, diagrams, or preservation of the original text layout. The scan is always available. PDF exports contain the visible pages and ink; editable OCR text stays in the library.

## Open in Xcode

Requirements: Xcode 26 or later and XcodeGen. CI uses the same **Xcode 26.6 / macos-26** toolchain as `pphilfre/mail`.

```sh
brew install xcodegen
xcodegen generate --spec project.yml
open Folio.xcodeproj
```

Select a signing team and a unique bundle identifier if needed. Use a physical iPhone or iPad to test document scanning and Apple Pencil. Photos, PDF import, OCR, organisation and reading can be tested in the simulator.

## GitHub Actions

[Builds and downloads](https://github.com/pphilfre/scan/actions/workflows/ios.yml)

Pushing to `main` or `work` runs two jobs concurrently:

1. **Device IPA:** builds arm64 Release and uploads `Folio-device-IPA`, containing an unsigned IPA and SHA-256 checksum.
2. **Simulator tests:** compiles the app/tests while an existing iOS 26 simulator boots, then tests without rebuilding.

No package resolution, external app dependencies, runtime downloads, scheduled builds, or release publishing. Stale runs are cancelled; both jobs have a 15-minute cap. Compiler module caches are separated by platform, runner image and toolchain. Build logs and test results are uploaded for diagnosis. An IPA artifact alone does not establish that the parallel tests passed.

The IPA is **unsigned** and needs compatible signing before installation. It is not an App Store or TestFlight upload. Signing with iCloud requires the matching Apple capabilities and container described below.

## Optional iCloud

Offline storage is the default. The sync switch checks the iCloud account, then applies on the next app launch using the **same store URL**. It does not move users to an empty, separate cloud store. A startup error offers “Open offline” without deleting saved files.

For a signed installation:

1. Register `dev.freddiephilpot.folio` (or your replacement app identifier) in your Apple developer team.
2. Enable iCloud / CloudKit and push notifications, create `iCloud.dev.freddiephilpot.folio`, and include the matching capabilities in the provisioning profile.
3. Update `Configuration/Folio.entitlements`, `FolioApp.swift`, and `SettingsView.swift` together if changing identifiers.
4. Initialise the schema in development, then deploy the CloudKit schema to production before distributing production builds. Configure the production APNs entitlement through your distribution signing profile.
5. Sign in to iCloud on the device, enable sync in Folio, then close and reopen the app.

The schema uses default values, optional relationships, explicit inverses, and no uniqueness constraints for CloudKit compatibility. CloudKit handles eventual synchronisation; test on two signed devices before distributing a sync-enabled release.

## Verification

`Tests/LibraryTests.swift` checks divider membership/order, independent duplication, cascade deletion, title/date/section metadata, search snippets, a real Vision recognition request, and a rotated PDF export/import round trip.

Local source checks in the Linux workspace validate Swift syntax, workflow/project structure, JSON assets, entitlements and shell syntax. Apple framework type checking and the tests require the GitHub macOS jobs. Physical-device checks are listed in [docs/device-checks.md](docs/device-checks.md).
