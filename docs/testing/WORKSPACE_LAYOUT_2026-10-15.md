# Video workspace layout verification

> Continuación: [divisiones y ventanas flotantes, web/macOS](../../../../../../codebase_artcraft/docs/testing/WORKSPACE_DOCKING_2026-10-15.md). Este informe conserva la evidencia de la fase inicial.


This change adapts the shared Flutter workspace shell to the video editor. The
shell and its pure Dart layout model record their Rust `craft-libs` reference and
bounded scope in their own migration documentation. This editor only composes
existing video controls into that shell; it does not port a second video engine.

## Automated contracts

`test/video_craft/video_craft_workspace_layout_test.dart` exercises:

- A 1200 px workspace: drag the divider, select each inspector, hide/show the
  sidebar while video is playing. The same backend and preview widget remain
  mounted; source, transport position, recipe object and document undo survive.
- A fresh workspace with the same injected store: panel extent, active Animation
  tab and sidebar visibility restore without adding a document undo entry.
- Resize the viewport to 390 px and back: stacked inspector placement, retained
  desktop width and title draft, and no preview remount or layout overflow.
- Export from the Animation inspector through the global toolbar.
- Resize and hide the inspector after encoding: prepared MP4 bytes still save
  from a fresh user gesture, using the same recipe snapshot.

The existing workspace, project, timecode, async source-race and export tests
remain necessary. They use an isolated in-memory preference store so a Chrome
test cannot inherit real user preferences or another test's selected inspector.

Verified on 2026-10-15 with Flutter 3.47.5 / Dart 3.13.4:

| Check | Result | Evidence |
| --- | --- | --- |
| `dart analyze lib/video_craft test/video_craft` | No issues | [analysis log](2026-10-15-workspace/analyze.log) |
| `flutter test --no-pub --reporter expanded test/video_craft` | 67 passed | [VM log](2026-10-15-workspace/vm.log) |
| `flutter test --no-pub --platform chrome --reporter expanded test/video_craft` | 66 passed | [Chrome log](2026-10-15-workspace/chrome.log) |

The five new workspace tests passed on both runners. The platform-specific source
adapter tests differ between VM and Chrome, hence the different suite totals.

## Real browser / desktop procedure

1. Open the example host, select Video, open a supported local clip and play it.
2. On a wide window, drag the divider in both directions. The preview remains
   visible and playback does not restart. Change Timing / edit to Animation.
3. Type a title without applying it, hide/show the inspector and change tabs.
   The draft is retained. Apply it and set opacity keys; verify the animation
   follows the playhead and Undo removes a document edit, not a panel resize.
4. Wait for the workspace saved indicator, reload the browser or quit/reopen the
   native app. Panel size and selected tab return. A document only reopens after
   explicitly opening its saved project; layout persistence is not autosave.
5. Hide the inspector, reload/reopen again, then show it. The selected tab and
   previous usable extent return. Reset restores the default workspace only.
6. Make the viewport narrow: inspect panels below the preview, scroll each area
   independently, then widen it. No overflow or media reload. Compact layout has
   a bounded inspector height; only the wide layout has a resizable divider.
7. Export MP4 while Animation is active. After rendering, resize/hide the
   inspector and use Save rendered MP4. Inspect the saved title and animation.
8. Change the image editor workspace separately. Reopen Video and confirm its
   preferences did not change. Web origins and different native host apps have
   separate stores; they are not synchronized by this feature.

Automated backend doubles establish lifecycle and document contracts, not codec
quality or a real file-picker result. Platform build and real-host results belong
in the suite's workspace verification report.
