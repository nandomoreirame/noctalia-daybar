---
feature: calendar-event-delete
phase: implement-complete
started_at: 2026-10-09
spec_path: docs/specs/calendar-event-delete/SPEC.md
plan_path: docs/plans/2026-10-09-calendar-event-delete.md
---

# State: calendar-event-delete

Implemented on `develop` (T1 to T10). Depends on inbox-bookmarks-notes.

## Verified

- Unit tests cover khal roots, collection lookup, UID file pick, recurrence, deletable paths, argv builders, check removal, the hidden-event filter, and the Today `calendar` field.
- `ConfirmButton.ready: false` failed to load before the property existed (`Cannot assign to non-existent property "ready"`) and the panel loaded after it was added. The scratch assignment was removed.
- After the delete services landed, the shell log resolved the khal root from `path = ~/`. The probe log was removed before the commit.
- Reloading the shell and opening Today and Calendar loaded the panel with no TypeError for `EventDeleteButton`.

## Not walked

Smoke rows 46 to 51 were not clicked. No throwaway event was created and no real event was deleted. This session cannot hover or type into the panel, so the trash-on-hover, the confirmation bubble, OK, the offline sync warning, "Evento não encontrado", and the live `ps` argv check stay pending.

REQ-001 to REQ-005 stay Pending. REQ-006 is Done from the unit tests of the argv builders and `isDeletablePath`.
