# Folio 2 device checks

Use iOS 26 on physical devices; validate the installation method you intend to distribute.

## Preservation and working folders

- Upgrade a populated version 1 install without changing its container. Verify original bytes, ink, corrected OCR, favourites, colours, dividers and ordering. Check `Library Backups` is created before migration. A failed store must remain intact.
- Choose a Files folder outside the disposable container. Import a photo without pressing Save now: verify `Folio Library/originals` receives an image automatically, then check new scans and edits continue saving after dismissing Settings. Add a scanned page, ink, nested dividers, tags, bookmark, link, crop and revision covers. Check the saved time, then use Save now as a second check.
- Reset the **test** LiveContainer guest container, reinstall, choose the same folder and verify the entire library restores. Repeat with several large PDFs, Unfiled, deleted items and version history. Retain an independent copy during destructive installation testing.
- Test local Files and iCloud Drive folders, revoked folder permission, offline providers and reselecting the folder after a reset. Disconnect must preserve both local data and folder files.
- In Settings, tap Choose working folder, select a folder and press Open. Verify the connecting state, Connected label and saved time. Force quit and reopen, then verify the folder reconnects without choosing it again.
- Open the folder from a second independent container, edit/save, and try to save from the stale first container. Verify it reports a changed index; reconnect and check both edits are recoverable. Missing files must produce an error without replacing the index.

## Capture, organisation and reading

- Scan multiple handwritten pages continuously before Save; check crop/retake/cancel, denied camera permission, import photos/PDFs, locked PDFs and stopping a batch. The bottom plus must reveal three glass source buttons and close cleanly. A destination prompt must follow capture/import; dismissing it must retain the originals in Unfiled.
- Insert a multi-page batch before a chosen page, at a divider and at the end. Confirm order and section membership. Try all paper templates.
- Add a divider before and after a page without dragging. Verify its larger row and edge tab are easy to tap, then swipe through it as a numbered reader page with its title, icon and colour.
- Add multiple images to a lined paper page, position each, draw over them, save, reopen and export. Confirm the original paper remains available in history.
- Drag crop, straighten, brightness and contrast sliders continuously and check the preview changes before releasing each slider.
- Edit OCR text from the reader pencil, cancel once and save once; verify search reflects only the saved correction.
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

## Study tools

- Open every Library study area on compact iPhone and iPad, at large Dynamic Type sizes and with VoiceOver. Create a subject, nested topics and a standalone paper without a subject or topic. Confirm new topics show neutral progress and confidence remains self-assessed.
- From a topic link a book, a nested divider and individual notes. Open each original. Lock the book and confirm linked note contents stay protected until unlocked in Books. Make a card from a reader note, then open its source.
- Scan a multi-page paper, import an ordered photo selection, import a PDF and append another batch. Verify original order in the reader, annotate/crop a page, then edit paper metadata and question marks. Ensure ink, original bytes and order remain unchanged. Attach existing scans in a chosen order. Cancel/interrupt capture and confirm saved originals remain recoverable in Unfiled.
- Import question metadata before and after scanning. Use question 1 with 1(a)/1(b), one unmarked and one marked zero; confirm question/paper/section totals count leaves once. Override a child's section and correct marks. Open each question range. Capture a mark scheme and link it both to the whole paper and a specific question. Search and exercise all filters, including questions needing another attempt.
- Mark a question; verify the mistake/card/retry actions appear after the editor closes. Add working, multiline correction and teacher feedback. Retry a mistake twice (still practising, then resolved), verify history, linked question, notes and resulting cards.
- Review due cards with reveal, hint and all three ratings. Confirm the next dates, editing, source links, empty queue, and card deletion after a review. Set a test card's due date to last month through pasted data and confirm no penalty. Move between cards with VoiceOver. Use system haptics enabled/disabled, Study haptics off and Reduce Motion on; confirm visible feedback still communicates every result.
- Copy the AI prompt, use its example, paste/validate, inspect the preview and confirm. Paste it again and confirm Skip defaults. Exercise Update with omitted fields, Import as new with cross-record links, deleted-ID handling and destination subject/paper choices. Try malformed JSON, unknown types/fields, numeric rather than string marks, invalid links, parent cycles, negative/excess marks and reversed/out-of-range pages. Errors must identify record and field, with no partial save. Verify multiline text survives copy/export/import.
- Run a session scoped to a subject, nested topic and paper: review a card, mark a question, retry a mistake, update confidence and finish. Check summary counts/marks and a useful next step. Closing early must keep already saved practice.
- Upgrade a populated pre-study store, reconnect a format 2 folder, then save format 3. Restore that folder into an empty installation and verify courses, paper order, mark schemes, attempts, schedules, edit history, deletion markers, originals and ink. Reconnect repeatedly without duplicates. Restore two copies, edit the same study record differently and sync/merge; confirm one current ID and the losing edit in history. Ensure a stale folder writer still refuses an overwrite. Verify CloudKit schema deployment includes the additive StudyItem entity before release.
