# Native animated MP4 export

`createVideoCraftTrimExporter()` selects the native implementation on Android, iOS and macOS. `ProVideoCraftTrimExporter` keeps its historical name and `exportTrim` entry point, but now renders the complete supported recipe: trim, the shared Flutter title canvas, and arbitrary linear opacity keyframes. It implements `VideoCraftControlledExporter` for progress/cancellation. Windows and Linux remain explicitly unsupported.

The encoder is **pro_video_editor 1.22.0+neom.1**, a local BSD 3-Clause fork in `codebase_artcraft/vendor/pro_video_editor`. Android uses Media3; iOS/macOS use AVFoundation and CoreImage. This is Flutter plugin integration, not a port of the Rust codec/render backend. Filmcraft/Effectcraft provide the recipe's timing and animation semantics.

## Rendering contract

- Input may be bytes, a local file URI, or an HTTP(S) media URL. HTTP sources are downloaded into the job's own temporary folder. User source files are never deleted.
- Output retains source display dimensions and frame rate. The wrapper does not apply a lower-resolution quality preset. Unsupported odd dimensions are rejected rather than silently cropped.
- The title uses exactly the same `VideoCraftTitlePainter` as preview/web export. It is rasterized once into a full-size transparent PNG; native compositing applies the curve at every output frame.
- `[inFrame, outFrame)` is the source selection. Source keys are shifted into output frame coordinates, with interpolated boundary keys preserving curves that begin or end outside the selection. Rational frame rates remain rational across the channel.
- Android decodes to the following keyframe or end of source so B-frames near the out point retain their reference packets, then limits muxed video/audio to the original interval. This may process extra reference frames; they are not included in the result.
- Native trim timestamps have a distinct contract from preview seek: Android truncates rational boundaries to microseconds as its extractor does; Apple receives exact frame/FPS rationals and builds `CMTime` without microsecond rounding. This prevents shifting a non-integer start or generating an extra final composition frame.
- Original audio is enabled. Sources with more than one audio stream are explicitly rejected because the underlying sequential compositor selects one stream. The finished output is inspected and rejected if the audio stream disappears, dimensions/FPS change, or duration deviates substantially.
- Audio can be re-encoded. AAC priming/padding may extend container duration; sample-exact trim or lossless audio is not claimed. Validation permits one recipe frame plus 120 ms of container-duration difference.
- Video-stream duration is checked separately with half a nominal source frame plus 1 ms tolerance. A missing/short stream fails even when the container duration is extended by audio. Duration checks alone cannot detect repeated frames; the independent fixture auditor also decodes and matches actual frames.
- Result must be an MP4 with an `ftyp` header. No WebM is renamed to MP4. Device encoder failures propagate without producing a purported success result.

Current bounds: **512 MiB input/output**, **8.3 million pixels per frame (4K UHD fits)**, positive even width/height, and **0 or 1 audio stream**. Larger inputs/frames fail with a clear message. Codec, HDR/color conversion and multichannel behavior depend on the native OS; advanced mastering parity is outside the current validated scope.

## Cancellation and cleanup

A token cancelled before/during preflight or title rasterization prevents native dispatch. A cancellation during encoding targets the exact task ID. The exporter awaits the native operation's completion/cancellation before deleting its temporary folder. Even if the encoder completes during a cancellation race, those bytes are discarded. Progress is monotonic and completion is reported only after output verification. Stream subscriptions/listeners are removed on all exits.

## Host configuration

The workspace overrides `pro_video_editor` to the local fork. A host consuming this module must make that override too and perform a full native rebuild; hot reload cannot install native code. A runtime handshake rejects stock/old binaries with an actionable error. This local override is not automatically inherited by consumers of a published Dart package. Upstreaming or distributing the fork is therefore a prerequisite for standalone pub.dev distribution of the native feature.

The web factory remains on Mediabunny/WebCodecs and does not load `dart:io` or the native codec implementation. See [web backend documentation](tool/web_export/README.md) for its separate browser capability checks.

## Verification

Automated checks live in:

- `test/video_craft/video_craft_native_render_plan_test.dart`: every frame of a trimmed curve, outside keys, one-frame ranges, constant/empty curves, exact rational serialization, invalid native keys.
- `test/native/video_craft_native_exporter_test.dart`: native boundary simulation, old-plugin refusal, cancellation before/during preflight/render, late result rejection, progress, audio/dimension validation and file cleanup. These are VM boundary tests, not codec/device certification.
- Fork `tool/check_neom_opacity.py`: production Swift curve arithmetic; `tool/check_neom_trim.py`: exact CoreMedia range arithmetic; Android `OpacityKeyframesTest`: Kotlin curve/parser arithmetic.
- Host `integration_test/project_export_test.dart`: project file saved/reopened, original preview seek, native MP4 rendering, output reopened in the real video player.
- Host `integration_test/native_fractional_trim_test.dart`: selection `[25,119)` at 24 fps, exercising non-integer-second boundaries and supplying artifacts for the independent 94-frame check.
- Host `tool/verify_media_exports.py video`: independent FFmpeg check of frame count/trim, title fade and 440 Hz audio for the numbered fixture. See the host's dated test evidence for platforms actually executed.

Manual device checks still include: cancel a long export, leave/reopen the editor, verify microphone/camera imports and orientation, inspect Unicode/multiline titles, validate a 23.976/29.97 fps source, check phone storage/thermal limits, and compare audio sync throughout a longer source. A successful desktop fixture does not by itself certify iOS or every Android hardware encoder.
