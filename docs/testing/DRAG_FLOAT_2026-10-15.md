# Detaching video tabs into floating windows

`test/video_craft/video_craft_workspace_drag_float_test.dart` sends real mouse
gestures through the shared workspace. It covers:

- A dock tab dropped onto free canvas space creates one float. Hover changes no preferences; the accepted drop writes once and matches the preview rectangle.
- The source group's visible size is used initially. Resizing, redocking and reopening preserve the intended layout and stored geometry.
- Dragging the only tab in a float repositions that float without changing its ID or preferred size. Detaching one tab from a multi-tab float keeps the other tab and its original geometry.
- The video preview stays mounted, playback/frame/backend counts remain stable, title drafts survive, a prepared MP4 stays available, and workspace changes create no document undo entries.
- Pointer cancellation, Escape, dropping outside the workspace and dropping on group/window headers do not write preferences.

The canvas remains the document surface: it cannot become an ordinary tab or
split group. Free canvas space can now hold floating tools above it. Older
tab-drag/edge tests that rejected canvas drops were updated to reject drops
outside the workspace instead. Existing edge splitting and tab merging remain
covered by the baseline suites.

The tests use memory preferences and a deterministic preview/exporter; they do
not claim new codec validation. The host app checks real platform storage with
separate native processes and Chrome. Layout preferences do not save unsaved
documents or restore live playback sessions.

## Manual verification on web and desktop

1. Open a video, apply one title edit, leave another title uncommitted, prepare an MP4 and start playback.
2. Drag Animation onto empty canvas space. Compare the floating preview and resulting window; the source Timing tab should remain in place.
3. Resize the float and drag its Animation tab back onto Timing's tab strip. Confirm the draft, playback and MP4 remain available.
4. Float Animation again, merge Timing into it, then drag Timing out to a second free position. Only Timing should detach.
5. Reopen the editor and compare both groups, tab membership and floating rectangles.
6. Repeat a free-space drag but cancel with Escape. Also drop outside the workspace and on a window header; these attempts must leave preferences unchanged.
7. Undo once: only the applied title edit should be undone.

Run the new suite with `flutter test test/video_craft/video_craft_workspace_drag_float_test.dart`
and add `--platform chrome` for browser validation. Campaign logs are in
`2026-10-15-drag-float/` beside this report.

## Automated results

Flutter 3.47.5 / Dart 3.13.4:

| Check | Result | Log |
| --- | --- | --- |
| Analysis of `lib/video_craft` and `test/video_craft` | No issues | `analyze.log` |
| Complete video-craft VM suite | 81 passed | `vm.log` |
| Chrome: drag-float, edge, tab, docking and layout suites | 19 passed | `chrome.log` |

All three new cases pass on VM and Chrome. Rendered resize/translation dimensions
use a 0.001-pixel tolerance for floating-point transforms; preferred dimensions
and serialized restoration remain exact. Initial fixture diagnostics are retained
in `initial-float-precision.log` and `initial-rendered-size-equality.log`.
