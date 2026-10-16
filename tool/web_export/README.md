# Local web MP4 export backend

`npm ci && npm test && npm run build` rebuilds the checked-in Flutter asset.
No npm install or network CDN is needed at application runtime. The wrapper is
Open Neom code; it is not a port of a Craft renderer or a full video editor.

- Mediabunny **1.61.4**, MPL-2.0, from https://github.com/Vanilagy/mediabunny
  and https://www.npmjs.com/package/mediabunny/v/1.61.4.
- Unmodified upstream source corresponding to the bundled library is available
  in the versioned npm archive and GitHub repository. `package-lock.json`
  records npm integrity; `assets/web/MEDIABUNNY_LICENSE` includes its license.
- Build tool: esbuild 0.25.12. The generated IIFE retains library license notices.
- Primary API documentation: https://mediabunny.dev/guide/converting-media-files
  (Conversion), https://mediabunny.dev/guide/writing-media-files,
  https://mediabunny.dev/guide/supported-formats-and-codecs.

The Dart adapter resolves the script URL through Flutter
`dart:ui_web.assetManager.getAssetUrl`, including subdirectory hosting and a
configured assetBase. It needs no inline script or `blob:` CSP exception; CSP
must permit scripts from the configured asset origin. It uses WebCodecs and
Canvas 2D, with no upload or real-time screen/audio recording.

Export composes every frame at source display dimensions, with source rotation
baked in and the selected recipe frame rate. A PNG from the same Flutter title
painter used by preview is composited per frame. Process timestamps from
Mediabunny are relative to the trimmed output; opacity keys remain on source
frames, therefore the wrapper adds `inFrame` before evaluating linear opacity.

All audio tracks are decoded and encoded to AAC at their original channel count
and sample rate. An unsupported codec, track, or encoder aborts the export.
Audio is never deliberately dropped. Conversion is forced to transcode the
selected range instead of expanding it to copied keyframe/packet boundaries.
AAC encoder delay/padding can extend the final audio track: the 24 fps browser
fixture produced exactly 4.000 s / 96 video frames and 4.074667 s of AAC (about
75 ms of padding). Sample-exact final audio duration is not guaranteed.
Encoding is lossy H.264/AAC; container metadata/colour
profiles and independent subtitle tracks are not an archival-preservation API.

Current explicit bounds: one video track; input up to 256 MiB; SDR; even display
dimensions; up to 8,294,400 pixels/frame. Larger sources are rejected, not scaled.
Codec support depends on the browser/OS, checked before work begins. Silent
inputs do not require an AAC encoder. Output is a true `ftyp` MP4, not WebM with
an MP4 extension. Cancel aborts fetch/conversion and never returns partial bytes.
Output and input are in browser memory; long exports can hit device memory limits.
