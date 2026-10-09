---
feature: daybar-mvp
phase: implement-complete
started_at: 2026-10-09
spec_path: docs/specs/daybar-mvp/SPEC.md
plan_path: docs/plans/2026-10-09-daybar-mvp.md
---

# State: daybar-mvp

Implementation is complete. `npm test` reports 124 passed. The source-reference guard is clean.

Google Calendar setup was not run. `khal` and `vdirsyncer` are not installed, and no OAuth client was created. Rows that need them stay open. P1 traceability is `Done` only where a smoke row passed.

## Smoke

Passed:

- Rows 2 and 3 (REQ-001): `capture` opens the centered overlay. A second call keeps a single `noctalia-daybar-capture` layer.
- Row 19 (REQ-016): with khal absent, the Calendar tab shows the not-configured message, the clock and the month grid. The Today tab still renders.
- Row 24 (REQ-022): `open focus` and `open calendar` open the toolbar on that tab. `toggle` closes it. `capture` opens the overlay.

Not passed:

- Rows 1, 4-10, 15-17, 20-23, 25 and 26 were not driven. This machine has no Wayland key injector, so the overlay and panel could not be typed into.
- Rows 11-14 are blocked: khal and vdirsyncer are absent, so no Google event, reminder, sync failure or calendar reload was observed.
- Row 18 shows the clock and the month grid. Previous/next month and event dots were not exercised.

P1 still Pending: REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-017, REQ-018, REQ-019, REQ-020, REQ-021, REQ-023.
