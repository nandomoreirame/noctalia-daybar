# Spec: Bookmarks and Notes

## Problem Statement

The Inbox tab mixes two unrelated things in one list: read-later links (a bare URL each,
no title, only "archive") and captured notes (one line of plain text, no editing). Links
need to work like a bookmark manager, with the page's title, description and image as a
browser shows them. Notes need room to be written and read as Markdown.

## Goals

- Bookmarks and Notes are separate toolbar tabs, each using the whole panel.
- A saved link shows a browser-like preview (image, title, description) without the user
  typing anything but the URL.
- A note opens in a large window, rendered as Markdown, and is edited in place without a
  save button.
- Nothing in either tab makes a network request just because it is displayed.

## Context

- Today `data.links` holds `{ id, url, archived, createdAt }` and `data.notes` holds
  `{ id, text, createdAt }`; both are shown by `components/InboxView.qml`.
- All existing links and notes are test data. The user chose to discard them: no migration.
- Pure logic lives in `utils/**/*.js` (QML JS libraries, vitest through the transform in
  `vitest.config.js`); QML is thin UI; long-lived services live in `Main.qml`.
- External commands are argv arrays, never shell strings (`CLAUDE.md` hard constraints).

## Verified Claims

| Claim | Source (file:line) | Verified |
|-------|--------------------|----------|
| Store schema is version 1 and keeps `links` and `notes` lists | `utils/store.js:7`, `utils/store.js:55` | yes |
| The toolbar tabs and their icons are defined once and shared by panel and bar widget | `utils/tabs.js:5`, `utils/tabs.js:7` | yes |
| Link and note captures commit through `Main.addLink` / `Main.addNote` | `Main.qml:116`, `Main.qml:118`, `Main.qml:288` | yes |
| A lone http(s) URL is inferred as a link capture | `utils/capture/registry.js:35` | yes |
| Clipboard prefill skips URLs that are already saved | `utils/inbox.js:35` | yes |
| `NText` can render Qt-native Markdown (`Text.MarkdownText`) | `/etc/xdg/quickshell/noctalia-shell/Widgets/NText.qml:36` | yes |
| A layer-shell window can take keyboard focus on demand (`WlrKeyboardFocus.OnDemand`) | `/usr/lib/qt6/qml/Quickshell/Wayland` (used by installed plugins) | yes |
| `curl` 8.22 is installed at `/usr/bin/curl` | `curl --version` | yes |
| Current data has 0 links and 1 note (both test data) | `~/.local/share/noctalia-daybar/data.json` | yes |
| Qt `Text.MarkdownText` fetches remote images referenced as `![](https://...)` | n/a (Qt behavior) | assumption |
| Most sites expose `og:title` / `og:description` / `og:image` in the first 2 MB of HTML | n/a (web) | assumption |

## Requirements

### P1

**Tabs and data**

1. **[REQ-001]** WHEN the toolbar is shown THEN the system SHALL offer five tabs in this order: Calendar, Today, Focus, Bookmarks (icon `bookmark`), Notes (icon `notes`); the Inbox tab SHALL no longer exist.
2. **[REQ-002]** WHEN `data.json` is read with `version` < 2 THEN the system SHALL drop `links` and `notes`, start `bookmarks` and `notes` empty and write `version: 2`; a saved `ui.lastTab` that is no longer a tab SHALL fall back to the default tab.

**Bookmarks**

3. **[REQ-003]** WHEN a link is saved (capture Link type, or the Bookmarks tab field) THEN the system SHALL store it at once with its domain as the title and show it at the top of the list.
4. **[REQ-004]** WHEN a saved URL matches an existing bookmark after normalization (no trailing slash, no `#fragment`, no `utm_*` parameters) THEN the system SHALL replace the existing one: keep its id, move it to the top and fetch its preview again (overwriting a manually edited title).
5. **[REQ-005]** WHEN a bookmark is saved and the "Fetch link previews" setting is on (default) THEN the system SHALL fetch the page with `curl` (argv, http/https only, 8 s timeout, 2 MB cap) and set the title, description and image from `og:title`/`og:description`/`og:image`, falling back to `<title>` and `<meta name="description">`.
6. **[REQ-006]** WHEN a preview image URL is found THEN the system SHALL download it once to `~/.cache/noctalia-daybar/thumbs/<id>` with the same limits and display only the local file; displaying the list SHALL never make a network request.
7. **[REQ-007]** WHEN a preview fetch fails (network, timeout, no metadata) THEN the system SHALL keep the domain title, show no toast, and offer "Refresh preview" on the row; at most 3 fetches SHALL run at once, the rest queued.
8. **[REQ-008]** WHEN the Bookmarks tab is shown THEN each row SHALL show a 64x40 thumbnail (or a `world` icon), the title (bold, one line), the description (dim, up to two lines) and `domain · date`, newest first; clicking the row SHALL open the URL via `xdg-open`.
9. **[REQ-009]** WHEN the pointer is over a bookmark row THEN the system SHALL offer copy URL, refresh preview, edit title (inline, Enter saves, Esc cancels) and delete.
10. **[REQ-010]** WHEN the user types in the Bookmarks search field THEN the list SHALL be filtered by title, description and URL (case- and accent-insensitive).

**Notes**

11. **[REQ-011]** WHEN a note is listed THEN its title SHALL be its first non-empty line stripped of Markdown markup, followed by a one-line plain-text snippet and the relative time of its last edit; notes SHALL be ordered by last edit, newest first, with a search field and a "New note" button.
12. **[REQ-012]** WHEN a note is clicked THEN the system SHALL open a centered overlay window (up to 1100x800, at most 90% of the screen) showing the note rendered as Markdown, with title, last-edit date and edit/preview, copy, delete and close actions.
13. **[REQ-013]** WHEN the pencil, a double-click on the text or Ctrl+E is used THEN the window SHALL switch to a monospace plain-text editor; Ctrl+E again SHALL return to the preview.
14. **[REQ-014]** WHEN the note text changes THEN the system SHALL save 600 ms after the last keystroke and on close; Ctrl+S SHALL save at once; Esc SHALL close the window (saving).
15. **[REQ-015]** WHEN "New note" is used THEN the window SHALL open in edit mode on an empty note; a new note still empty when the window closes SHALL be discarded.
16. **[REQ-016]** WHEN a note is rendered THEN links SHALL open only for `http`, `https` and `mailto` (via `xdg-open`), and remote images SHALL be rendered as a link with their alt text; local images SHALL be shown.
17. **[REQ-017]** WHEN a note is captured with `/n text` THEN the system SHALL create a note whose text is that line.

**Deleting**

18. **[REQ-018]** WHEN delete is clicked on a note or bookmark (list row or note window) THEN the system SHALL show a bubble anchored to the button with a question and "OK" / "Cancel"; keyboard focus SHALL start on "Cancel"; Esc or a click outside SHALL cancel; only "OK" deletes. Deleting a bookmark SHALL also delete its cached thumbnail.

**Settings**

19. **[REQ-019]** WHEN the Settings page is opened THEN it SHALL offer "Fetch link previews" (on by default); with it off, bookmarks keep the domain title and no request is made.

## Edge Cases

- **Relative or protocol-relative `og:image`** (`/img.png`, `//cdn/x.png`) is resolved against the page URL; a non-http(s) result is ignored.
- **HTML entities and whitespace** in titles/descriptions are decoded and collapsed; title is capped at 200 characters, description at 400.
- **Page larger than 2 MB / slow server** - curl stops at the cap or timeout; whatever HTML arrived is still parsed, else the fetch counts as failed.
- **Non-UTF-8 pages** may show garbled accents (accepted limit; no charset conversion).
- **Bookmark deleted while its fetch runs** - the result is discarded and any downloaded thumbnail removed.
- **Same URL saved twice quickly** - the second save replaces the first and its fetch result wins; a stale result for a superseded fetch is ignored.
- **Fetch setting turned off with fetches queued** - queued fetches are dropped; running ones finish but nothing new starts.
- **Hostile page metadata** (`<script>` in `og:title`) is stored and shown as plain text, never rich text.
- **`javascript:`/`file:` links in a note** are not opened; nothing happens on click.
- **Note window open when the note is deleted from elsewhere** - the window closes.
- **Note with only whitespace** counts as empty (discarded when new, title "Untitled" when existing).
- **Two notes with the same first line** - both are listed; titles need not be unique.
- **Clipboard prefill** - a URL already saved is still not prefilled.

## Architecture Decisions

1. **Two tabs instead of an Inbox with a switch** - each list gets the whole panel. Discarded: one tab with an inner segmented control.
2. **No data migration** - test data only; store v2 drops `links`/`notes`. Discarded: converting links to bookmarks.
3. **Metadata via curl + pure parser** - `curl` argv in a `Process`, HTML parsed by `utils/pagemeta.js` (regex over `<meta>`/`<title>`, unit-tested). Discarded: a WebEngine view (heavy) and an external metadata API (privacy).
4. **Thumbnails cached locally** - downloaded once to `~/.cache/noctalia-daybar/thumbs/`. Discarded: loading remote images in `Image` (a request on every panel open).
5. **Qt-native Markdown** - `Text.MarkdownText` for rendering, with a pure pre-pass (`utils/markdown.js`) that turns remote images into links and a link handler that only opens http(s)/mailto. Discarded: a custom Markdown-to-HTML parser (~400 lines to maintain).
6. **Derived note title** - first line, no separate title field. Discarded: a title field (one more input, drifts from content).
7. **Autosave** - debounced 600 ms + on close + Ctrl+S. Discarded: explicit save button.
8. **Own overlay window for notes** - a `PanelWindow` on `WlrLayer.Overlay` with `WlrKeyboardFocus.OnDemand`, like the capture overlay. Discarded: rendering the note inside the 680x360 panel.
9. **Confirm bubble for deletes** - one reusable `components/ui/ConfirmButton.qml`. Discarded: two-click confirm without text, modal dialog, undo toast.

## Grilling Log

Decisions surfaced and resolved during the grilling pass (pre-build stress test).

| # | Decision | Resolution | Rationale |
|---|----------|------------|-----------|
| 1 | How to separate links and notes | Two tabs, Bookmarks and Notes | Each list uses the whole panel |
| 2 | Bookmark organization | Simple list with browser-like preview; no tags or folders | User preference; YAGNI |
| 3 | Where a note opens | Own large overlay window | Long notes need room |
| 4 | Bookmark title source | Fetched from the page | No typing beyond the URL |
| 5 | Markdown renderer | Qt-native `Text.MarkdownText` | No parser to maintain |
| 6 | Preview image storage | Download once to a local cache | No request when the list is shown |
| 7 | Note title | Derived from the first line | Standard for Markdown notes |
| 8 | Preview fetching default | Setting "Fetch link previews", on | Opt-out for privacy |
| 9 | Existing data | Discard, no migration (store v2) | All test data |
| 10 | Tab names and icons | Bookmarks (`bookmark`), Notes (`notes`), after Focus | Matches the existing tab style |
| 11 | Note saving | Autosave 600 ms + on close + Ctrl+S | Nothing lost on an accidental close |
| 12 | Read/edit switch | Opens in preview; pencil, double-click or Ctrl+E edit; Esc closes; empty new note discarded | Reading is the common case |
| 13 | Delete confirmation | Anchored bubble with message, "OK" and "Cancel"; focus on Cancel; Esc/click outside cancels | Explicit, hard to trigger by accident |
| 14 | Bookmark row | Thumbnail, title, 2-line description, domain · date; click opens; hover actions; search; add field; newest first | Browser-like |
| 15 | Fetch failure | Save at once with domain title; no toast; "Refresh preview"; max 3 concurrent | Never lose a capture; no noise |
| 16 | Duplicate URL | Normalized match replaces the old bookmark, moves it to the top and fetches again | User preference: a re-save means "refresh" |
| 17 | Notes list | Title, snippet, relative edit time; last edited first; search; "New note"; hover copy/delete | Mirrors the bookmarks list |
| 18 | Remote images in notes | Rendered as a link with alt text | No network request from a note |
| 19 | Note window look | Up to 1100x800, theme surface color, monospace editor, no per-note colors | Fits the toolbar style |
| 20 | Creating notes | `/n text` keeps creating one-line notes; long notes via "New note" | No new global shortcut |

## Constraints

- No `eval`/`Function`; every external command is an argv array (`curl`, `xdg-open`, `rm`, `mkdir`).
- Page metadata is untrusted input: shown as plain text (`Text.PlainText`), lengths capped.
- Code, comments and commits in English; UI strings in `pt` and `en` via i18n.
- No reference to any previous or source project in code, docs, comments or commits.

## Out of Scope

| Item | Reason |
|------|--------|
| Tags and folders for bookmarks | User chose a simple list |
| Per-note colors | Not part of this app's look |
| Sync with browser bookmarks | Not requested |
| Archiving bookmarks | A simple list has no archive state |
| Migrating existing links/notes | Test data only |
| Charset conversion for non-UTF-8 pages | Rare; accepted limit |
| Favicons | og:image covers the preview |

## Test Strategy

- **Unit (vitest, TDD):** `url.js` (normalization, domain), `pagemeta.js` (og/title/description extraction, entities, relative image URLs, caps, hostile input), `bookmarks.js` (add/replace, preview, failure, rename, delete, search, order), `notes.js` (title, snippet, add/update/delete, blank detection, search, order), `markdown.js` (remote image rewrite, openable links), `fetch.js` (curl argv), `fetchpool.js` (concurrency 3, stale results), `store.js` v2, `tabs.js`, relative time formatting, i18n coverage.
- **Runtime (manual):** rows added to `docs/SMOKE.md` for the two tabs, preview fetch, thumbnail cache, note window, autosave, confirm bubble.
- **Gate:** `npm test` green before each commit.

## Requirement Traceability

| ID | Description | Priority | Status |
|----|-------------|----------|--------|
| REQ-001 | Five tabs, Inbox removed | P1 | Pending |
| REQ-002 | Store v2, no migration | P1 | Done |
| REQ-003 | Save bookmark at once | P1 | Pending |
| REQ-004 | Duplicate replaces and refetches | P1 | Pending |
| REQ-005 | Fetch page metadata | P1 | Done |
| REQ-006 | Cached thumbnail | P1 | Done |
| REQ-007 | Fetch failure handling, concurrency 3 | P1 | Pending |
| REQ-008 | Bookmark row and order | P1 | Pending |
| REQ-009 | Bookmark hover actions | P1 | Pending |
| REQ-010 | Bookmark search | P1 | Pending |
| REQ-011 | Notes list | P1 | Pending |
| REQ-012 | Note window | P1 | Pending |
| REQ-013 | Edit/preview switch | P1 | Pending |
| REQ-014 | Autosave | P1 | Pending |
| REQ-015 | New note, empty discarded | P1 | Pending |
| REQ-016 | Safe Markdown links and images | P1 | Pending |
| REQ-017 | `/n` capture | P1 | Pending |
| REQ-018 | Confirm bubble for deletes | P1 | Pending |
| REQ-019 | Fetch previews setting | P1 | Pending |
