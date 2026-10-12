---
feature: focus-clock-detach
phase: none
started_at: 2026-10-12
spec_path: docs/specs/focus-clock-detach/SPEC.md
plan_path: docs/plans/2026-10-12-focus-clock-detach.md
---

# State: focus-clock-detach

Implemented on `main` (T1 to T10). Grok (balance exhausted) and Codex (usage limit) were
unavailable; Claude implemented and reviewed.

## Verified

- `npm test`: 429 passed; tier1 and tier2 gates pass.
- With `ui.clockWindow`/`ui.clockOverlay` set in data.json, a shell restart reopened both
  forms; niri listed the window ("Daybar timer", app_id `dev.noctalia.noctalia-qs`) and the
  layer `noctalia-daybar-clock` with no keyboard interactivity.
- `niri msg action close-window` on the window wrote `clockWindow: false`.
- Shell log had no daybar error after each reload.

## Not walked

Nobody clicked, hovered or looked at the forms: smoke rows 63 to 70 are pending (buttons,
hover controls, overlay corner vs bar, sizes, window resize, the README window-rule).
