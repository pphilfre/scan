# Folio 2 device checks

Use iOS 26 on physical devices; validate the installation method you intend to distribute.

## Preservation and working folders

- Upgrade a populated version 1 install without changing its container. Verify original bytes, ink, corrected OCR, favourites, colours, dividers and ordering. Check `Library Backups` is created before migration. A failed store must remain intact.
- Choose a Files folder outside the disposable container. Import a photo without pressing Save now: verify `Folio Library/originals` receives an image automatically, then check new scans and edits continue saving after dismissing Settings. Add a scanned page, ink, nested dividers, tags, bookmark, link, crop and revision covers. Check the saved time, then use Save now as a second check.
- Reset the **test** LiveContainer guest container, reinstall, choose the same folder and verify the entire library restores. Repeat with several large PDFs, Unfiled, deleted items and version history. Retain an independent copy during destructive installation testing.
- Test local Files and iCloud Drive folders, revoked folder permission, offline providers and reselecting the folder after a reset. Disconnect must preserve both local data and folder files.
- Open the folder from a second independent container, edit/save, and try to save from the stale first container. Verify it reports a changed index; reconnect and check both edits are recoverable. Missing files must produce an error without replacing the index.

## Capture, organisation and reading

- Scan multiple handwritten pages continuously before Save; check crop/retake/cancel, denied camera permission, import photos/PDFs, locked PDFs and stopping a batch. The three-icon toolbar must stay compact. A destination prompt must follow capture/import; dismissing it must retain the originals in Unfiled.
- Insert a multi-page batch before a chosen page, at a divider and at the end. Confirm order and section membership. Try all paper templates.
- Nest and reparent dividers; change finish/colour/icon/spine, drag a whole branch, jump using edge tabs, and export overlapping selected sections without duplicate pages.
- In Organise, multi-select, rename, tag, duplicate, rotate, crop, move and delete. Check Undo after each destructive action and restore from Recently Deleted after relaunch.
- Annotate with finger/Pencil, highlight, underline using the ruler, erase and undo/redo. Crop/straighten/rotate before and after annotation; confirm alignment and preservation of originals in reading and PDF export.
- Resize/move revision covers, reveal one/all, hide, close/reopen and rotate. Link across books and follow/remove the link without creating an image copy. Restore a prior edit from history.
- Open the reader normally with thumbnails on: the image/text must occupy the main reading area. Exercise every menu tool on its first presentation. Select two thumbnails in the reader and share a two-page PDF.
- Check bookmarks and Recent within books, full screen, swipe/curl, Reduce Motion, thumbnail navigation, zoom, grid/list and display settings. Navigate/export a book containing hundreds of pages while observing memory.
- Check keyboard-adjacent search, matches, close, hardware keyboards, VoiceOver, Dynamic Type, light/dark mode, iPhone landscape and iPad split view.

## Protection and integrations

- Enable app/book protection. Test biometrics, device-passcode fallback, cancel and authentication unavailable. Background from every sheet/reader/search and verify switcher snapshots reveal nothing.
- Search/link/export paths must not reveal locked or deleted note contents. Reopening a protected book after backgrounding must authenticate again.
- Test Home/Lock Screen widgets, URL routing and Scan note shortcuts on a directly installed build. Record which integrations LiveContainer actually exposes; guest extensions are not guaranteed to be registered by iOS.
- Test optional iCloud on two correctly signed devices, including concurrent text/ink edits, folder restores on both, offline edits/reconnect, deletion/restore, duplicate reconciliation and version recovery. Deploy the CloudKit production schema before distribution.
