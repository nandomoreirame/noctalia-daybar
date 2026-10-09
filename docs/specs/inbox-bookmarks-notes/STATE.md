---
feature: inbox-bookmarks-notes
phase: implement-complete
started_at: 2026-10-09
spec_path: docs/specs/inbox-bookmarks-notes/SPEC.md
plan_path: docs/plans/2026-10-09-inbox-bookmarks-notes.md
---

# State: inbox-bookmarks-notes

Implemented on `develop` (T1 through T20).

Smoke rows 27-45 were not clicked through. There is no virtual keyboard in this session, so capture typing, hover actions, rename, the confirm bubble and the note shortcuts were not driven. Rows that were not walked stay Pending in the spec. Partial evidence:

- BN-REQ-002: a v1 `data.json` (one link, no notes) became version 2 and lost the links array on the first bookmark save. Tasks and reminders stayed.
- BN-REQ-003, BN-REQ-005, BN-REQ-006: `addBookmark("https://github.com")` stored the bookmark. After the fetch, status was `ok`, with a title, a description and a thumbnail file of 618778 bytes under the thumbs cache. The capture overlay was not used, so BN-REQ-003 stays Pending.
- BN-REQ-001: IPC `open` for calendar, today, focus, bookmarks and notes succeeded, and `ui.lastTab` became `notes`. Tab icons and labels were not seen. No daybar TypeError in the log. The row stays Pending.
- BN-REQ-011: NotesView loaded with one note and logged no type error. The relative time was not seen. The probe note was removed.
- BN-REQ-012, BN-REQ-014: the note overlay opened (`noctalia-daybar-note`) and `save()` wrote a note. Rendered Markdown, Ctrl+E, Ctrl+S, Esc and the 600 ms timer were not driven. The probe note was removed.

Not walked: BN-REQ-004, BN-REQ-007, BN-REQ-008, BN-REQ-009, BN-REQ-010, BN-REQ-013, BN-REQ-015, BN-REQ-016, BN-REQ-017, BN-REQ-018, BN-REQ-019.

Done in the traceability table: REQ-002, REQ-005, REQ-006.
