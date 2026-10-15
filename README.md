# Folio 2

A native iOS 26 notebook for iPhone and iPad, built with SwiftUI, Liquid Glass, VisionKit, Vision, SwiftData, PencilKit, PDFKit, Core Image, LocalAuthentication, WidgetKit and App Intents. No third-party runtime dependencies or remote OCR services.

## A level study

The home screen is a **study desk** with circular marking progress and a continuation action. Past papers open a **Sit → Scan → Mark → Reflect** workspace:

- **Sit:** a configurable countdown dial with pause/resume and finish. Its saved deadline survives navigation, backgrounding and relaunch. The timer stays inside the sitting screen; it does not schedule a background alarm.
- **Scan:** camera, ordered photos, PDFs or existing scans, followed by a visual page gallery.
- **Mark:** page thumbnails and a large scan with question scores beside it. Use **Mark this page** for one page total, or add individual questions. Mixing totals and questions for the same page is rejected. Quick score buttons support zero, full marks and fractional typed scores. Choose topics through searchable subject chips and nested topic paths.
- **Reflect:** score and marking coverage, lost marks to revisit, and topic totals. Multi-page questions count once; subquestions retain inherited page ranges/topics.

Colour distinguishes focus, saved progress and practice opportunities. Recall has tangible prompt/answer surfaces and rating buttons; topic confidence is selectable directly. Haptics follow selections and successful saves, with Settings and Reduce Motion respected. See [experience design](docs/experience-design.md).

The Library has **Course maps**, **Past Papers**, **Flashcards & review**, and **Mistakes**, alongside your existing books. Start with a paper or a few cards; a course map is optional.

- Create subjects, topics and nested subtopics. Each topic brings together linked books, dividers, note pages, questions, mistakes and cards. Confidence is self-assessed, with new topics shown as opportunities to explore.
- Scan or import complete papers independently of topics, attach mark schemes, and open their ordered scans in the existing reader for annotations. Add questions/subquestions, scan ranges, working, corrections, feedback and marks. Paper, section and parent totals count leaf marks once. Search/filter by subject, board, year, topic, score and further practice.
- Record mistakes and retry them as resolved or still practising. Create editable cards manually or from a note's reader menu, question or mistake. Review prompt → reveal → Again/Nearly/Got it; scheduling has no missed-day penalties.
- Start a study session from a subject, topic or paper, review cards, practise, mark and see a concise summary with a next step. Study haptics use restrained system feedback and can be disabled in Settings; Reduce Motion also mutes them.
- Paste structured data from an external AI, validate it, inspect its fields, choose skip/update/new for duplicates, and confirm a final summary. Import metadata/questions separately from scans, and copy/export study data with the same versioned JSON format. **Copy prompt for AI** includes the full field contract and example. See [the format and examples](docs/study-format.md).

Study records, practice events, edit history and deletion markers are included in working-folder saves and merges. Manifest format 3 reads older format 2 folders; older apps cannot overwrite the new format. JSON study export contains scan references; the working folder remains the complete backup of images and ink.

## Working folder and LiveContainer

**Settings → Working folder → Choose working folder…** opens the native Files folder picker. Choose a durable location **outside Folio’s/LiveContainer’s disposable app container**. Folio creates a `Folio Library` subfolder there and automatically saves its portable library after changes, including imports while sheets are open. Original images use their normal file extensions in `Folio Library/originals`; folder access stays open while connected.

The app uses local SwiftData for responsive offline editing. The chosen folder contains immutable originals, content-addressed page records, annotations, crops/enhancements, tags, dividers, books, bookmarks, links, deleted items and version history. Its coordinated, atomic `Library.json` index is committed after the referenced files. Unchanged originals and page records are reused.

Before updating or changing containers, use **Save now** and check the saved time. If LiveContainer resets Folio’s app storage or its permission bookmark, reinstall/open Folio and **select that same working folder again**. Existing records are matched by UUID and merged into the local database. You can also choose a different folder to save a portable copy. Disconnecting never deletes the folder or local notes.

Keep the folder available offline in Files. If another container changes its index, Folio refuses a stale overwrite and asks you to reconnect/merge. Older page edits are kept as versions. The folder is readable in Files; Face ID protects the app interface, not these exported files. A reset before the first successful folder save cannot be recovered from that folder.

## Books and organisation

- Colours, two-colour gradients, linen/paper/ruled finishes, SF Symbols and spine labels.
- Physical coloured edge tabs jump between dividers. Nested sections support parent selection, colours, icons, divider styles and ordering; section exports include descendants.
- Configurable bookshelf and thumbnail sizes, grid/list layouts, reading background, page numbers, thumbnail strip and page-turn animations.
- A bottom plus expands into camera, photos and files glass buttons. Native scanning supports continuous multi-page batches; originals are saved into Unfiled before a destination/position prompt appears. Photo/PDF import, paper insertion and scans can target any position.
- Dedicated organiser with drag-and-drop, native list reordering, multi-selection, batch rename/tags, duplication, rotation, crop/enhancement, movement, export and deletion.
- Recoverable deletion, persistent Recently Deleted and a 20-command in-session undo history. Page edits retain immutable version records; sync duplicates are reconciled without discarding competing edits or different originals.

## Reading and editing

- Native page curls, swipe navigation through pages and dividers, pinch/double-tap zoom, full screen, a fixed-height thumbnail strip with multi-page PDF sharing, bookmarks and recently viewed pages within books.
- Accurate language-aware Vision OCR, editable/searchable text and automatic titles/date/section suggestions. Interrupted recognition resumes; the original is saved first.
- PencilKit pen, highlighter, eraser, ruler-assisted underline and undo/redo. Ink remains separate and aligns with crop, straightening and rotation.
- Non-destructive crop, straightening, brightness, contrast and colour/grey/ink/warm filters.
- Blank, lined, squared, dotted and graph paper templates. Each paper page supports PencilKit ink and multiple positioned images, kept as editable layers over the original paper.
- Revision mode with movable/resizable answer covers, individual reveal, reveal/hide all and persistent cover positions.
- Related-page links across books store identifiers without duplicating images.
- PDF export for individual/selected pages, multiple sections or a complete book. Export reads originals in short-lived contexts, rendering one page at a time. PDFs contain visible scans and ink; OCR text stays editable in Folio.
- Glass search directly above the keyboard with a separate close button; book/section/page/text/tag/date matches and highlighted text snippets. Locked/deleted note contents stay out of results.

Vision does not guarantee handwritten equations or original text layout. The source scan remains available for review.

## Privacy, sync and quick capture

App-wide and per-book protection use `deviceOwnerAuthentication`: Face ID/Touch ID where available, with device-passcode fallback. Locks reset on backgrounding, and an opaque cover protects app-switcher snapshots, including presented sheets.

Offline storage is the default. Optional CloudKit uses the same store URL, preserves edit history and consolidates duplicate app UUIDs that can arise when restoring the same folder on two devices. Concurrent page versions can be reviewed/restored. Changing sync requires reopening the app.

The included Home Screen/Lock Screen widget and **Scan note** App Shortcut route to the capture toolbar/Unfiled. **LiveContainer may not register guest-app widgets, Siri shortcuts or URL schemes with iOS.** These integrations require an installation method that exposes them to the operating system. Scanning, organisation and working-folder recovery are available inside the app.

## Build and install

```sh
brew install xcodegen
xcodegen generate --spec project.yml
open Folio.xcodeproj
```

CI follows `pphilfre/mail`: **macos-26 / Xcode 26.6**, no package or simulator downloads. Device IPA and the core/study simulator suites run concurrently with 15-minute caps. Separate simulator suites give study UI tests their own time budget when a cold simulator boots slowly. Simulator discovery/boot occurs alongside generic simulator compilation; tests run without rebuilding. Stale runs are cancelled and module caches/logs are retained.

[Builds and IPA downloads](https://github.com/pphilfre/scan/actions/workflows/ios.yml)

`Folio-device-IPA` contains an **unsigned** IPA (including the widget extension) and checksum. Signing is needed for installation; the build does not publish to TestFlight or the App Store.

For iCloud, register the app and `iCloud.dev.freddiephilpot.folio`, enable CloudKit/push notifications, use matching provisioning, initialise the development schema and deploy it to production before distributing. Update the identifiers together in `project.yml`, `Configuration/Folio.entitlements`, `FolioApp.swift` and `SettingsView.swift` when using another team/app ID. Widget signing must match its containing app.

## Data migration and validation

The original `Notebook`, `BookSection`, `NotePage`, attributes and relationships are retained. New properties use defaults or optional values for additive lightweight migration and CloudKit compatibility. Before opening an older local store, Folio copies the unopened SQLite/WAL/support files to `Application Support/Library Backups`. It never resets a failed store; offline retry remains available.

Tests include a frozen copy of the **actual version 1 and shipped version 2 models**, reopen those stores with the current schema, and verify scan bytes, ink, OCR, tags and relationships. Other tests cover nested membership, recoverable actions and undo, linking without image copies, cropping/rotation, Vision, PDF round trips, locked-note access, portable-folder restoration into an empty container, automatic folder saves after imports, selected PDF order and stale-index protection. UI tests launch with an isolated in-memory library and exercise image/text layout, every reader tool, PDF sharing, compact capture and the post-import destination prompt.

Linux preflight checks cover Swift syntax, assets, entitlements, project/workflow structure and shell syntax. Native compilation and XCTest run in GitHub Actions. Camera, biometrics, Apple Pencil, Files providers, LiveContainer recovery and two-device sync require [device checks](docs/device-checks.md).
