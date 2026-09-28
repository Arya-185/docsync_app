# Tests

```bash
flutter analyze        # must be clean
flutter test           # 65 tests
```

Both must pass before touching anything under `lib/features/chat/view/` — this app has no
version control, so a bad edit is unrecoverable and the suite is the only safety net.

## What each suite is for

| File | Covers |
|---|---|
| `test/rag_event_test.dart` | `RagEvent.fromJson` over every SSE type, including an unknown type still mapping to `ignore` — the property that keeps an older build safe when the server adds an event |
| `test/trail_pairing_test.dart` | the activity trail's state machine: a start with no finish must not spin forever, a finish with no start must not appear from nowhere, transient steps vanish when done |
| `test/commit_test.dart` | the `ai_commit.php` POST carries `action`, `args` and `conv` — and **no `Origin` header** |
| `test/a2ui_render_test.dart` | the A2UI surfaces actually DRAW, and the action verbs produce the right sentences |
| `test/bubble_text_test.dart` | Markdown rendering, and the conditional supersede rule |

## The two rules that are easy to break

**No `Origin` header on the commit.** `ai_commit.php`'s same-origin guard is permissive only
when both `Origin` and `Referer` are absent, and dio sends neither. Setting `Origin` to
anything turns a working call into a 403. The app sends `X-DocSync-App: 1` instead.

**Superseded text is dropped only once a surface has RENDERED.** The server sends a results
list twice — as cards and as the same rows in prose — because a client that cannot draw the
surface must still get the rows, and an empty answer is never persisted. `ChatMessage.content`
keeps the whole answer; `visibleContent(rendered:)` removes the duplicate. Defaulting
`rendered` to false is deliberate: assume nothing drew.

## `test/fixtures/surfaces.json` is a COPY

It comes from `web/fixtures/surfaces.json` in the server repo
(`C:\wamp64\www\docsync_abc_latest`), which `tests/php/ai_uisurface_test.php` generates.
**Testing the identical bytes on both platforms is the only thing that proves the two renderers
agree** — genui here, `@a2ui/web_core` there, two independent implementations of one protocol.

Nothing automates the copy. When `UiSurface` gains or changes a surface, re-copy the file; the
suite fails with "re-copy web/fixtures/surfaces.json" if a key goes missing, but it cannot
notice a key whose CONTENT changed.
