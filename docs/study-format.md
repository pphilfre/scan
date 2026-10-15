# Folio Study format, version 1

Use **Library → any study area → Import or export**. Copy the AI prompt, supply your material to an external AI, paste its result, and select **Parse and validate**. Review the fields and duplicate decisions, then **Confirm import**. Folio does not send material to an AI service. Imported answers are unverified and remain editable.

The interchange file is UTF-8 JSON, a plain-text format with standard escaping. Return one object, without Markdown fences:

```json
{
  "format": "folio-study",
  "version": 1,
  "records": [
    {"type":"subject","id":"maths","title":"Mathematics","board":"Edexcel","qualification":"A level"},
    {"type":"topic","id":"algebra","subject":"maths","title":"Algebra","confidence":"New"},
    {"type":"topic","id":"quadratics","subject":"maths","parent":"algebra","title":"Quadratics"},
    {"type":"paper","id":"maths-2025-1","title":"Pure Mathematics 1","subject":"maths","board":"Edexcel","qualification":"A level","year":"2025","session":"June","number":"9MA0/01"},
    {"type":"question","id":"q1","paper":"maths-2025-1","label":"1","section":"A","pageStart":"2"},
    {"type":"question","id":"q1a","paper":"maths-2025-1","parent":"q1","label":"1(a)","topic":"quadratics","marks":"3","earned":"2","prompt":"Solve x² − 5x + 6 = 0.","working":"Factorise:\n(x − 2)(x − 3) = 0","feedback":"State both roots."},
    {"type":"markScheme","id":"ms-2025-1","paper":"maths-2025-1","question":"q1a","title":"Question 1 mark scheme","notes":"Attach an official scheme scan in Folio."},
    {"type":"mistake","id":"missed-root","question":"q1a","topic":"quadratics","title":"Missed a root","what":"I wrote only x = 2.","reasoning":"Each factor can equal zero.\nx = 2 or x = 3.","category":"method error","resolved":"false"},
    {"type":"card","id":"roots-card","topic":"quadratics","source":"record:missed-root","prompt":"How do you find all roots of a factorised quadratic?","answer":"Set each factor equal to zero.\nCheck both roots in the original equation.","hint":"Use the zero-product rule."}
  ]
}
```

All records require `type` and `id`. IDs are globally unique within the library (across types), at most 200 characters, without whitespace. Stable names such as `maths-2025-1-q1a` work well; keep the same IDs on subsequent edits. UUID strings also work. Links can refer to another record in this document or an existing library record; record order does not matter.

Apart from the document's numeric `version` and array `records`, **all values are strings**, including marks, dates and booleans. Omit optional fields when unknown. An empty string explicitly clears an optional field on update. `\n` inside a JSON string is a newline; `\"` represents a quote and `\\` a backslash. Do not put literal unescaped line breaks inside quoted strings. Unknown versions, record types and fields are reported; Folio does not discard them silently.

## Fields

| Type | Required fields, in addition to type/id | Optional fields |
| --- | --- | --- |
| `subject` | `title` | `board`, `qualification`, `notes`, `source` |
| `topic` | `title`, `subject` | `parent`, `confidence`, `notes`, `noteBooks`, `noteSections`, `notePages`, `source` |
| `paper` | `title` | `subject`, `subjectName`, `board`, `qualification`, `year`, `session`, `number`, `notes`, `pages`, `source` |
| `question` | `label`, `paper` | `parent`, `section`, `topic`, `prompt`, `answer`, `working`, `correction`, `feedback`, `marks`, `earned`, `pageStart`, `pageEnd`, `retryAt`, `notes`, `source` |
| `markScheme` | `title`, `paper` | `question`, `pages`, `notes`, `source` |
| `mistake` | `title`, `what`, `reasoning` | `question`, `topic`, `category`, `resolved`, `retryAt`, `notePages`, `source` |
| `card` | `prompt`, `answer` | `hint`, `topic`, `source`, `sourcePage`, `due`, `interval`, `repetitions`, `notes` |
| `attempt` | `date`; at least one of `question`/`mistake` | `question`, `mistake`, `earned`, `marks`, `resolved`, `session`, `notes` |
| `review` | `card`, `rating`, `date` | `session` |
| `session` | `title` | `scope`, `started`, `finished`, `notes` |

`subject`, `paper`, `topic`, `question`, `card`, `mistake`, and record-valued `session` fields refer to study IDs. A topic's `parent` must be a topic in the same subject; a question's `parent` must be a question in the same paper. Cycles are invalid. A mark scheme's optional question must belong to its paper. Session `scope` can be a subject, topic or paper. Paper `session` is ordinary text such as `June`, unlike the history records' session ID.

`source` is text or an external URL. For a flashcard linked to another study record, use `record:ID`. Cards made from notes also retain `sourcePage`. The app shows source links and allows editing. New pasted records without a source receive “Pasted study data (unverified)”.

`confidence` is `New`, `Exploring`, `Practising` or `Confident`. An omitted value means New. Confidence is self-assessed; scores do not set it automatically. Suggested mistake categories are `knowledge gap`, `method error`, `misread question` and `careless slip`; custom categories are accepted. `resolved` is `"true"` or `"false"`.

Marks are finite, nonnegative numbers, including fractional marks. `earned` requires `marks` and cannot exceed it. Omit `earned` for an unmarked question; `"0"` means marked and earned zero. Parent, paper and section totals count leaf subquestions once. Children inherit the nearest parent's section name unless they specify one. Correct the leaf marks to correct totals.

Dates use ISO 8601 with time and timezone, for example `2026-10-15T17:00:00Z`. `rating` is `Again`, `Nearly` or `Got it`. Card `interval` is days, from zero to 180; `repetitions` is a nonnegative whole number. New cards with no `due` are immediately available. Rating again schedules 10 minutes, nearly one day, and got it at least three days, increasing by 2.3 up to 180 days. Reviews are scheduled from the time of the rating, with no missed-day penalty.

## Scans and separate question imports

Papers always belong to **Past Papers**, even without a course map. Use `subjectName` for a subject name without creating a subject. Scan/import the whole paper there, or attach existing scans in selection order. Add a mark scheme record and open it to scan/import the scheme separately.

`pages` is an ordered comma-separated list of existing Folio page UUIDs. `noteBooks`, `noteSections` and `notePages` likewise refer to existing Folio UUIDs; `sourcePage` is one page UUID. These are available in exported study data after selecting notes in the app. An external AI should omit unknown UUIDs. JSON study export contains references, not image or ink bytes; use the working folder for a complete backup.

`pageStart` and `pageEnd` are positive, 1-based positions in the paper's scan list. Omit `pageEnd` for one page. A subquestion without its own range inherits the nearest parent range; topic workspaces also include children of linked questions. Questions can be imported before scanning. Folio checks a range against available scans when validating that question; append the remaining scans if necessary. Question metadata never changes the originals or their order. Paper/mark-scheme updates retain the existing scan sequence and append any newly linked UUIDs once.

To paste questions separately after scanning, select the destination paper in the preview and omit each question's `paper`, or use that paper's exported ID:

```json
{"format":"folio-study","version":1,"records":[
  {"type":"question","id":"my-paper-q2a","label":"2(a)","pageStart":"4","marks":"5","earned":"3","working":"My working\nSecond line","feedback":"Show the substitution."}
]}
```

Select a destination subject similarly for topics with no subject. Missing required links remain errors until a destination is selected. Topic links on questions are always optional.

## Duplicate decisions and export

Every preview shows additions, updates, skipped records and errors before saving. Errors identify the record and field. Correct the paste area and validate again. No records are saved while errors remain.

Exact IDs and likely matches (such as the same paper/question number or topic path) default to **Skip**. **Update** merges supplied fields into the existing record, preserving omitted fields and its scans. **Import as new** creates new IDs for matched records and redirects links within this import to those new IDs. Changing a destination regenerates the duplicate preview. Previously deleted IDs also default to Skip; explicitly updating one restores it. Records linked to a skipped deleted record must be restored, relinked or skipped together.

**Copy study data** and **Export study JSON file** use this same format and include active study records, attempts, review scheduling and sessions. Importing an unchanged export defaults to skipping it. A copy exported with scans' UUIDs is fully useful with the same restored working folder; UUID references alone do not transfer images to another library.

## Storage and recovery

Study tools add one CloudKit-compatible SwiftData entity, `StudyItem`, without changing notebook/page relationships or using unique constraints. Local store format 4 first backs up the unopened pre-study SQLite store and companion files using the existing migration backup mechanism. Versioned flat payloads, stable app IDs, soft deletion and edit histories support folder recovery and concurrent copies. The app records attempts/reviews separately from editable current marks and scheduling. Folder merge uses the newest modification, deterministic tie handling (deletion wins a tie), and retains competing study payloads in edit history. Concurrent scan appends are united in the winning sequence. Recent field versions can be inspected/restored from a record's workspace.

Working-folder manifest format 3 includes all study snapshots, tombstones and history alongside the existing scan archives. Folio reads format 2 folders with no study data. Older apps reject format 3 rather than overwrite study records they cannot understand. Original files and content-addressed page records keep their existing storage path and serialization. Retain a complete folder backup before moving between app versions.

Deleting a card also hides its review events; tombstones remain in the folder backup. Optional links to deleted study records are detached or retain a source description. A subject/paper with records that require it must have those records moved or deleted first. Removing study records never removes linked note images.
