# neom_video_editor

Flutter video editing for Open Neom. The module keeps its existing application editor and adds a reusable Craft workspace for video timing, title animation and web MP4 composition.

**Español:** el espacio Craft reproduce un vídeo real, permite marcar entrada/salida, editar una receta y previsualizar un título con claves de opacidad. La receta no contiene el vídeo. El exportador web incorpora el título y sus claves de opacidad al MP4 H.264/AAC; el exportador nativo compone el título y su animación mediante el adaptador Open Neom para Android/iOS/macOS. No se afirma paridad con Filmcraft, Effectcraft ni otros editores.

## Reusable workspace

```dart
import 'package:neom_video_editor/neom_video_editor.dart';

VideoCraftWorkspace(
  source: VideoCraftSource.bytes(videoBytes, name: 'clip.mp4'),
  onPickSource: pickVideoSource,
  onSaveRecipe: saveRecipeJson,
  onOpenRecipe: openRecipeJson,
  onOpenProject: openProjectBytes,
  onSaveProject: saveProjectBytes,
  active: isVisible, // e.g. the selected IndexedStack tab
  onExportVideo: saveVideoBytes,
);
```

Every argument is optional. A workspace without a source shows its empty state; host-dependent actions are disabled when the corresponding callback is absent. `VideoCraftSource` accepts bytes or a URI and optional `CraftFrameRate`. If the rate is unknown, the timeline starts at 30 fps; this is an editing rate, not automatic source-rate detection.

The [public entry point](lib/neom_video_editor.dart) exports the source, recipe, self-contained project, controller, workspace and backend interfaces. `onSaveRecipe` receives JSON text; `onOpenRecipe` returns JSON or null. `onExportVideo` receives rendered video bytes. On web, **Export MP4** first renders a snapshot in memory, then **Save rendered MP4** invokes that callback from a fresh user gesture so the browser can start the download. Finishing the encoder is not a successful file-save claim; cancellation/failure during save allows retrying the prepared result. `VideoCraftController.pause()` lets a host stop playback before hiding the workspace.

## What is implemented

| Area | Current behavior |
|---|---|
| Source and preview | Open video bytes/URI with a real `video_player` backend, play/pause, seek and navigate frames. Source changes release the previous media resource. |
| Timing / edit | Frame-rate selection (including 29.97/59.94), exact timing/timecode through `neom_filmcraft` and Craft core, Go to timecode, an exclusive In/Out interval, bounded undo/redo. |
| Animation | A title overlay and scalar opacity keys evaluated by `neom_effectcraft` against the current frame. |
| Project | Versioned `.neomvideoproject` file containing the original compressed video, editing recipe and saved playhead, with SHA-256 integrity validation. |
| Recipe | Versioned JSON with source name/duration, frame rate, trim, title and keys. Reopening requires a matching source name and duration. |
| Export | A platform factory selects WebCodecs/Mediabunny composition on web (trim + title + opacity + audio) or the Open Neom `pro_video_editor` adapter on Android/iOS/macOS. Both compose animated titles and preserve a supported source audio track, with progress and cancellation. |

The recipe stores frame-rate integers as strings and validates bounds on decode. It does not embed media or cryptographically identify the source; matching name/duration is a compatibility check, not content verification. Changing the editing frame rate preserves time positions subject to frame quantization.

**Go to timecode** accepts `00:00:10:00`, shorthand `1000` (ten seconds), `+15` (fifteen frames forward) or `-1.00` (one second backward), using Enter or **Go**. The active editing rate determines the timecode convention; 29.97/59.94 use drop-frame. Omitted labels such as `00;01;00;00` at 29.97, malformed text and destinations outside the source show an error without pausing or moving playback or changing the trim/recipe. A valid destination pauses and seeks the media backend. This is a Dart port of Filmcraft's existing parser, audited at `8309f21a` on 2026-10-15; it is not a new upstream feature or a replacement codec/export pipeline.

## Portable video projects

**Save project** writes a `.neomvideoproject` document containing the original compressed media bytes, source name, rational editing FPS, trim, title, opacity keyframes and playhead. **Open project** restores that source and preview directly in a fresh editor; the original file does not need to be selected again. The existing `.neomvideo`/JSON recipe flow remains available and continues to require the matching source separately. Exporting an MP4 produces rendered media; saving a project preserves editable settings and original media.

`onSaveProject` receives `Uint8List`; `onOpenProject` returns `Future<Uint8List?>`, with null meaning cancellation. Hosts should report a cancelled or failed save by throwing so the workspace keeps its edits and permits retry. With embedded byte sources, the save callback runs before an asynchronous boundary to retain a browser user gesture. Saving a URI source first reads its media with a size limit, then offers **Save prepared project** for a new download gesture. URI reading supports local files and HTTP(S) on native targets, and HTTP(S)/blob resources on web; browser origin/CORS restrictions still apply. Editing the recipe invalidates a previously prepared project snapshot.

Ctrl+S and Command+S save the focused workspace. Set `active: false` when retaining a hidden workspace in an `IndexedStack`, then true when showing it; this removes its shortcuts and focus participation. The buttons remain available for touch interfaces.

The binary v1 container uses a fixed magic/version/length prefix, bounded UTF-8 JSON metadata, unmodified compressed video bytes and a SHA-256 checksum covering the prefix, metadata and video. It has no base64 or archive decompression. Limits are 256 MiB source media and 1 MiB metadata; file adapters should allow at most `VideoCraftProject.maxProjectBytes`. Unknown container versions, malformed types, invalid edit ranges, unsupported media signatures, truncated/trailing bytes and checksum mismatches are rejected before replacing the editing session. The checksum detects damage; it is not an author signature. Supported signatures are ISO BMFF (MP4/MOV), EBML (WebM/MKV) and AVI; a recognized header alone does not establish playback support.

Opening validates a candidate with the real preview decoder and checks the saved duration/trim against it within one editing frame plus 1 ms. The default player keeps the previous source until candidate decoding/seeking succeeds. An injected backend is reopened with the previous source on failure; a backend that also fails that rollback reports the preview failure while retaining the previous edits. A successful open starts a new undo history; unsaved edits are retained on corrupt/failed opens. The format and pure Dart codec are shared across web/mobile/desktop, while actual media decoding, memory availability and file dialogs remain platform dependent.

## Platform and file boundaries

### Optional local recovery

Pass a stable `recoveryId` and optionally a `MediaRecoveryStore` to
`VideoCraftWorkspace` or `VideoEditorSectionsPage`. The default null ID disables
all recovery reads and writes. Hosts should scope IDs to the account and document
(ASCII letters/digits plus `_.:-`, at most 160 characters); changing accounts must
also change the ID. The default store is local IndexedDB on web and the native
application support directory on supported native platforms. A test memory store
does not provide durable recovery.

Accepted edits, undo/redo, a completed seek, pause and title drafts enqueue a
snapshot after 800 ms of inactivity. Playback ticks do not write a project every
frame. URI media is read once per source identity and reused; the snapshot embeds
the original compressed media, recipe and cursor without rendering an MP4 or
calling any save/upload callback. A small recovery-only envelope stores an
unapplied title separately; restoring it does not apply the title to the recipe.
The portable `.neomvideoproject` format is unchanged. Opacity slider previews,
unsubmitted timecode text, undo history and prepared exports are not recovered.

On startup an existing record offers **Restore session** / **Discard recovery**.
It never silently replaces the supplied source and blocks autosave until the
decision. Restore validates the portable project and real preview timing before
installing it, keeping the prior accepted edits on failure. Discard deletes only
the observed revision and then allows recovery of the current editor. Corruption,
quota/storage failures and another session's conflicting write remain visible;
retrying a conflict reads the newer record and requires another choice.

The saved indicator appears only after the store commits. Native lifecycle
notifications and teardown attempt a flush, but browser/process termination can
interrupt pending work; this is not a guarantee of saving the final keystroke.
Recovery is separate from a user-owned project file and from workspace layout
preferences. The default binary store limit is 256 MiB including the recovery
envelope/project metadata, so media near the portable project's upper limit can
exceed recovery capacity. Encoding/checksums can still block web's main thread
for large sources; no worker or performance guarantee is introduced.

For host-specific delivery wording, `exportLabel`, `saveRenderedLabel` and
`exportReadyMessage` customize the existing render/save flow without changing
its callbacks. Defaults remain **Export MP4** / **Save rendered MP4**.

See [recovery validation and manual checks](docs/testing/RECOVERY_2026-10-15.md).

Preview codec availability is determined by the browser or native player. The default factory reports WebCodecs availability in a secure web context (HTTPS or localhost); every export additionally checks its real decoder and H.264/AAC encoder support. The native composition exporter reports availability on Android, iOS and macOS; Windows and Linux remain unsupported. Availability in code is not evidence that a codec/export path has passed on every device. Native source bytes may require a temporary file; web uses a temporary media resource.

The workspace needs no Core, SINT or Firebase initialization. Hosts own selection, save/download/cancellation feedback, and may inject `VideoCraftPreviewBackend` or `VideoCraftTrimExporter`. Tests using these doubles validate the editor contract, not a native codec or platform file dialog.

### Resizable, remembered workspace

`VideoCraftWorkspace` uses `neom_craft_workspace`, based on Rust `craft-libs/craft-ui`. The protected canvas keeps the preview, transport, scrubber and timecode navigation. Timing and Animation can remain tabs, occupy separate horizontal/vertical groups, or float inside the editor. Each group menu splits, floats, docks or moves its active panel; drag dividers and floating window headers/corners to change geometry. Keyboard arrows also adjust geometry and Escape cancels an unfinished drag. The shared tree supports nested splits; video currently registers two tool panels.

The tree, split ratios, floating rectangles, selections, visibility and desktop width save automatically under `neom.craft.workspace.v1.neom_video_editor`. JSON v2 migrates existing v1 preferences on the next layout edit. Preferences are local to the web origin/native application and separate from video project files, recipe JSON and undo history. Reorganizing panels does not reopen the player, seek the source or invalidate prepared project/MP4 bytes. Toolbar actions remain available with any layout.

Narrow viewports stack the docked tree below the canvas and constrain floating windows without replacing preferred geometry. Floats are windows inside the editor, not separate OS windows. Drag tabs to reorder them or move them between docked/floating groups; touch uses a long press. An insertion marker shows the destination. Drop over a docked group body edge to create a left/right/top/bottom split, with a half-group preview. The tab strip keeps its reorder behavior; floating windows accept tab merges, and floating tabs can split docked groups. Dropping a tab onto free workspace creates a floating window with a placement preview; a tab can also detach from a multi-tab float. The document canvas remains underneath. Headers, dividers, blocked groups and locations outside the workspace reject this fallback. Multi-monitor windows remain pending. Missing/failed stores expose feedback without preventing editing; unknown records are preserved until reset. Hosts can inject `workspaceStore: MemoryCraftWorkspaceStore()` or another `CraftWorkspaceStore`, retaining its instance when rebuilding. See [web/macOS validation](../../../../codebase_artcraft/docs/testing/WORKSPACE_DRAG_FLOAT_2026-10-15.md).

## Web MP4 backend

`createVideoCraftTrimExporter()` selects the default exporter. On web it implements `VideoCraftControlledExporter`: existing `exportTrim(source, recipe)` remains available, while `exportWithOptions` accepts progress and a `VideoCraftExportCancellation` token. Its `includesAnimatedTitles` capability allows the UI to distinguish composition from native trim. The workspace snapshots the recipe for export and does not deliver partial bytes after cancellation.

The local asset bundles **Mediabunny 1.61.4 (MPL-2.0)** and uses WebCodecs, without an upload or runtime CDN. A shared Flutter painter lays out the title for preview and export; the encoder blends its rasterized pixels at the opacity evaluated for each source frame, including a nonzero In point. The output is true MP4 with lossy H.264 video and AAC audio. Unsupported audio aborts export instead of silently muting it; silent inputs do not require an AAC encoder.

Explicit limits: one video track, 256 MiB input, SDR, even display dimensions, and at most 8,294,400 pixels/frame. Oversize input is rejected, not downscaled. Audio retains track channel count and sample rate where the browser can decode/re-encode them. Metadata/subtitles and archival color-profile preservation are outside this contract. Input and output reside in browser memory; long exports require device-specific memory validation. The backend script loads from the Flutter asset URL on the host origin; it does not require `blob:` in `script-src`. Custom CSP/asset-origin configuration must permit that served local script.

See [backend build and provenance](tool/web_export/README.md), [Mediabunny license](assets/web/MEDIABUNNY_LICENSE) and [notices](assets/web/THIRD_PARTY_NOTICES.txt). Rebuild the bundled asset from its locked source with `npm ci && npm test && npm run build` in `tool/web_export`; consumers do not install npm dependencies at runtime.

## Native MP4 composition

Android/iOS/macOS use the local `pro_video_editor` 1.22.0+neom.1 adapter. It composites the same Flutter-rendered title PNG, interpolates opacity keys per source frame after trimming, and enables original audio. Preflight requires the adapter handshake, at most 512 MiB input, even dimensions up to 8,294,400 pixels, and zero or one audio track. Inputs with multiple audio tracks are rejected explicitly. Output dimensions, FPS, audio presence and duration are checked before delivering bytes. Codec padding can extend AAC duration within the validation tolerance of one frame plus 120 ms; this is not sample-exact audio editing. Portable projects have their separate, smaller 256 MiB media limit.

See [native export design and platform boundaries](README_NATIVE_EXPORT.md) for the fork, tests and integration requirements. Windows/Linux composition remains unsupported. Declared platform support and synthetic tests do not replace device evidence; actual runs belong in the host validation report.

## Existing application integration

[VideoEditorPage](lib/video_editor/ui/video_editor_page.dart) and the existing routes retain the Open Neom account/media-service integration, role-based duration rules and plugin-based crop/export paths. They depend on Core/Commons/SINT and native-file APIs; importing the new public workspace barrel does not route through that legacy page.

[VideoEditorSectionsPage](lib/video_craft/ui/video_editor_sections_page.dart) is a separate file-backed entry point with selection, project/recipe save and open, and platform-selected MP4 delivery. The existing editor can open it through «Tiempo y animación», pausing its previous player first. The legacy route remains tied to native-file APIs; web consumers should mount this new page or `VideoCraftWorkspace` directly, as the example host does.

Runtime dependencies include `video_player`, `pro_video_editor`, `video_editor`, `easy_video_editor`, `video_compress`, `fraction`, platform file services, `neom_craft_libs`, `neom_filmcraft` and `neom_effectcraft`. Existing plugins remain for application compatibility rather than proving additional Craft capabilities.

## Run and validate

From the `codebase_flutter` root, with `codebase_artcraft` checked out beside it:

```sh
cd ../codebase_artcraft/apps/neom_media_editors_example
flutter pub get
flutter run -d chrome
```

The [host README](../../../../codebase_artcraft/apps/neom_media_editors_example/README.md) describes the actual file adapters, samples and development runners. Its Video tab pauses when switching back to Image. For this module's tests, run `flutter test` after resolving its local dependencies. Keep controller/widget results separate from real video playback and native composition/export results.

Consuming applications must supply local Craft/core overrides as shown in the host. Overrides in a dependency's own pubspec do not propagate to the application.

The [full-resolution/MP4 validation campaign](../../../../codebase_artcraft/docs/testing/FULL_RES_IMAGE_WEB_MP4_2026-10-13.md) records actual codec/export checks separately from widget tests. Earlier trim-only and preview tests are not evidence of the new web exporter.

## Remaining scope and provenance

Multitrack editing, arbitrary compositing/effects graphs, audio mixing, automatic frame-rate probing, proxy management and codec-independent exports remain outside this slice. Packaged projects currently contain one source and its recipe; they are not a multitrack interchange format.

This is original Flutter integration around bounded independent Dart ports. [Filmcraft MIGRATION](../../../../codebase_artcraft/packages/neom_filmcraft/MIGRATION.md), [Effectcraft MIGRATION](../../../../codebase_artcraft/packages/neom_effectcraft/MIGRATION.md) and [Craft core MIGRATION](../../../../codebase_artcraft/packages/neom_craft_libs/MIGRATION.md) preserve source revisions and attribution. Rust-oracle tests cover those translated algorithms, not a complete editor.

The module is licensed under [Apache License 2.0](LICENSE). Preserve the dependencies' individual license and notice files. No upstream media assets are copied. See the suite [community guide](../../../../codebase_artcraft/docs/COMMUNITY.md) for the independent ArtCraft homage and contribution scope.
