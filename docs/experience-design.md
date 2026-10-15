# A desk for doing the work

The primary loop is physical: choose a past paper, work on paper, scan that work,
mark the scans and decide what to practise. Navigation should follow that loop.

## Design decisions

- Canvas: cool blue `#EDF2FC`; surfaces use adaptive system colours.
- Focus: indigo `#334AC7` for the active stage and timer.
- Progress: teal `#05736E` for saved marks and completed work.
- Revisit: amber `#9C570A` for lost marks and practice suggestions.
- Text: adaptive system primary/secondary colours. Dark mode has brighter accents.
- Type: SF Rounded for titles, scores and the clock; SF for reading and controls.
- Layout: left aligned desk with a single continuation action; paper workspace with
  a four-stage rail; large scan above a compact marking panel. At iPad widths the
  content remains bounded instead of stretching into long lines.

```text
Desk                         Paper
What to work on              [Sit]—[Scan]—[Mark]—[Reflect]
Progress dial + real counts   One stage's work
Continue paper                Scan / countdown / question marks
Papers | Courses              Contextual primary action
Recall | Mistakes
Books
```

Review against the brief: four more navigation tiles alone would reproduce the
old problem. The paper workspace must replace the paper's record-detail list.
The timer belongs inside Sit, where it can become the focus; the desk only offers
continuation. Dials encode actual marking coverage, actual scores and remaining
time. Empty data must not resemble achievement. Colour conveys focus, saved work
or revisiting; it does not decorate every surface.

## Behaviour

The clock saves transitions into the existing portable study store and derives
remaining time from a deadline. Leaving the view, locking the phone or relaunching
does not stop it. Pausing is explicit. A timer does not run an alarm in the
background. Resetting the timer asks before clearing the current sitting.

Scan appends through the existing original-first import pipeline. Mark shows
the ordered physical pages. Questions retain their existing page ranges and topic
links; inherited ranges work. Unassigned questions remain reachable. Multi-page
questions are marked once and paper totals continue to use leaf questions only.
Adding a page total is useful when no question breakdown exists; the UI tells the
user to choose either a page total or individual questions for the same work.

Save marks explicitly. Navigation never silently discards a draft. Zero means
marked; blank means unmarked. Fractional marks remain supported. Topic selection
uses subject chips, text search and the full parent path. Feedback follows actions:
light selection for a stage/topic/score change, success after persistence, and
error on failed persistence. Settings and Reduce Motion mute haptics. No ticking
haptics, automatic celebration or motion that interrupts marking.

## Verification

Cover clock transitions and deadline recovery, page mapping and score totals with
unit tests. Exercise Sit/Scan/Mark/Reflect, quick marking and topic selection with
UI tests. Verify compact width, accessibility sizes, dark mode and camera/haptics
on an Apple simulator/device; Windows cannot compile or render SwiftUI.
