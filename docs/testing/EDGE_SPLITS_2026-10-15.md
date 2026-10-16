# Splitting video panels by dragging to an edge

The new consumer suite is `test/video_craft/video_craft_workspace_edge_split_test.dart`.
All layout changes use real mouse gestures through the shared Flutter UI.

Six cases cover:

- Animation dropped at each of Timing's four edges, first from the same dock and then from a floating group.
- Half-panel preview geometry, no persistence during hover and one write on accepted drop.
- Horizontal/vertical orientation, before/after order, custom divider ratios and exact saved layout on a fresh mount.
- The same mounted preview, backend open/pause counts, playing state, frame, title draft, recipe identity, one document undo and a prepared MP4 download.
- Pointer cancellation, Escape and dropping outside the workspace without writes.
- A floating destination accepting a tab merge at its edge without creating a nested split.

Run from this package:

```sh
flutter test test/video_craft/video_craft_workspace_edge_split_test.dart
flutter test --platform chrome test/video_craft/video_craft_workspace_edge_split_test.dart
```

The preview backend/exporter are deterministic fakes. These tests validate workspace
behavior and preservation of an already prepared export; they do not retest codecs.
The host application's native write/read processes and real Chrome campaign cover
platform preference persistence separately. Layout restoration does not restore
unsaved document drafts or a running player session.

## Manual check on web and desktop

1. Open a video, apply one title edit, type another title without applying it, and prepare an MP4.
2. Start playback. Drag the Animation tab over each body edge of Timing, checking the half-panel preview before releasing.
3. Check that playback and the playhead continue, the draft remains and the prepared MP4 can still be saved.
4. Float Animation, move the window away from Timing and drag its tab onto a Timing edge; the emptied float should close.
5. Resize the divider, close and reopen the editor, and compare axis, order and divider position.
6. Hover over an edge and cancel with Escape; the preview should disappear and the saved workspace should stay unchanged.
7. Drag onto free space above the canvas: it now creates a floating window while keeping the canvas intact. Drag onto a floating panel edge: it should merge tabs, not create a split inside the float.
8. Undo once: only the applied title edit should be undone.

Evidence logs are stored in `2026-10-15-edge-splits/` next to this report.

## Automated results

Flutter 3.47.5 / Dart 3.13.4:

| Check | Result | Evidence |
| --- | --- | --- |
| Analysis of `lib/video_craft` and `test/video_craft` | No issues | `analyze.log` |
| Complete `test/video_craft` VM suite | 78 passed | `vm.log` |
| Chrome: edge-split, tab-drag, docking and layout suites | 16 passed | `chrome.log` |

All six new cases pass in VM and Chrome. The initial float-to-left fixture still
covered its destination edge; the shell correctly rejected that obscured target.
Moving the test window fully over the canvas resolved the fixture without any
application change. The initial diagnostic is retained as
`initial-fixture-occlusion.log`.
