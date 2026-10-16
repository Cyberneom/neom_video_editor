# Timecode navigation validation — 2026-10-15

Scope: the migrated Filmcraft text parser and its **Go to timecode** consumer.
No changes to project schemas, encoders, overlay rendering, audio or file adapters.
The Rust parser source existed before the latest upstream fast-forward.

With `/Users/serzen/src/flutter/bin/flutter` (3.47.5), from the module root:

```sh
flutter test --no-pub --reporter expanded test/video_craft
flutter test --no-pub --platform chrome --reporter expanded test/video_craft
flutter test --no-pub --reporter expanded test/native
dart analyze lib/video_craft test/video_craft
```

Results: **62/62 Craft VM, 61/61 Craft Chrome, 12/12 native VM**, static analysis
clean. Logs are adjacent. The IO-specific source test explains the VM/Chrome
count difference. Native tests use controlled platform doubles; these are not
new real-device codec or system-dialog measurements.

The four new widget tests check:

- Absolute timecode using Enter and relative frame/second offsets seek the media
  backend at the exact expected frame time without changing recipe/undo history.
- Malformed, negative and beyond-duration destinations leave the cursor, trim,
  recipe identity, pause count and seek history unchanged; the error is visible.
- At 29.97 and 59.94, valid first-minute labels seek frames 1800/3600; omitted
  labels are rejected without a seek.

The separate pure Dart engine passed **49/49 VM and 49/49 Chrome**, including a
39-row oracle executed against Filmcraft `8309f21a`. See its `MIGRATION.md` and
`test/fixtures/oracle/README.md` for deliberate parser validation differences.

## Manual follow-up in a normal host

These are reproducible checks, **not a claim of manual execution in this pass**.

1. Open a video and choose the editing rate matching its source. In Timing/edit,
   enter `00:00:01:10`, press Enter, then `+15` and `-1.00`; confirm the playhead,
   displayed frame and paused video move together. Repeat via **Go** on touch.
2. Mark a nonzero In point, type a bad label and a label after the video end.
   Confirm a visible error, unchanged trim and no forced pause/seek. While playing,
   ordinary playback may continue advancing naturally after invalid input.
3. With a source longer than one minute, select 29.97 then use `00;01;00;02`.
   Confirm frame 1800. `00;01;00;00` must fail. At 59.94 the valid label is
   `00;01;00;04` (frame 3600); labels 00–03 are omitted.
4. Save/reopen a project after navigating; verify the saved playhead, trim/title
   and opacity keys. Render/save MP4 and compare with the prior recipe's export:
   moving the playhead alone must not change the export interval or animation.

Navigation uses the existing media player's seek operation. This feature does
not promise frame-perfect decoder seeking for every source codec, and a decoder
failure during a valid seek remains a playback error rather than a syntax error.
