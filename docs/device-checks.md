# Device checks

Use a signed build on iOS 26. Run these before distribution:

- Allow camera access; scan a multi-page handwritten note. Review edges, retake and crop, then save to a chosen book. Confirm cancellation and denied camera permission behave correctly.
- Import portrait and landscape photos, a rotated photo, a PDF, a password-protected PDF and an unreadable file. Confirm saved pages survive stopping a batch. A single PDF is limited to 100 pages per import to avoid runaway imports.
- Compare OCR to several real handwriting samples, including faint writing and equations. Correct text, quit and reopen, then search the correction offline.
- Drag pages across dividers and move the dividers themselves. Check membership and numbering. Repeat using Edit controls and VoiceOver.
- Duplicate a page, move it to another book, rotate it, annotate it with Pencil and finger, undo/redo, then export. Confirm the original scan is unchanged and ink aligns after rotation.
- Swipe native page curls, use previous/next and thumbnails, pinch and double tap, enter/exit full screen, and enable Reduce Motion. Test a large book and rotate the device.
- Open search with the keyboard shown; verify the glass bar is directly above it, clear works, close dismisses it, and result snippets highlight matches. Check hardware keyboard and iPad split view.
- Check light/dark appearance, large Dynamic Type, VoiceOver labels and increased contrast.
- Export a complete book, inspect every page and ink in Files, then import that PDF again.
- On two signed devices, enable iCloud with the configured container, restart and confirm books, images, text, dividers, tags and ink sync. Disable sync/restart and verify the local library remains. Test offline edits and reconnecting. Verify production schema before distribution.

Vision recognises text, not structured mathematical expressions. Always offer the preserved original for review. No OCR content is sent to an external recognition service.
