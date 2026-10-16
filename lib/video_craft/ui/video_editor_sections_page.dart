import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:neom_media_recovery/neom_media_recovery.dart';

import '../data/video_craft_preview_backend.dart';
import '../data/video_craft_trim_exporter.dart';
import '../domain/video_craft_project.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_controller.dart';
import 'video_craft_workspace.dart';

class VideoEditorPickedFile {
  const VideoEditorPickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

enum VideoEditorSaveResult { saved, downloadStarted, cancelled }

/// The page supplies platform file dialogs by default; tests or applications can
/// inject their own storage boundary without an account or service locator.
abstract class VideoEditorFileAccess {
  const VideoEditorFileAccess();
  Future<VideoEditorPickedFile?> open({required List<String> extensions});
  Future<VideoEditorSaveResult> save({
    required Uint8List bytes,
    required String name,
    required String extension,
  });
}

class PlatformVideoEditorFileAccess extends VideoEditorFileAccess {
  const PlatformVideoEditorFileAccess();
  @override
  Future<VideoEditorPickedFile?> open({
    required List<String> extensions,
  }) async {
    // iOS excludes dynamic UTIs for these unregistered project extensions.
    // Select any document there, validate its suffix here, then validate the
    // actual format/version/content in the workspace's project/recipe decoder.
    final unfilteredProject =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        extensions.any(const {'neomvideoproject', 'neomvideo'}.contains);
    final result = await FilePicker.pickFiles(
      type: unfilteredProject ? FileType.any : FileType.custom,
      allowedExtensions: unfilteredProject ? null : extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (unfilteredProject &&
        !extensions.any(
          (extension) =>
              file.name.toLowerCase().endsWith('.${extension.toLowerCase()}'),
        )) {
      throw FormatException(
        'Select a ${extensions.map((e) => '.$e').join(' or ')} file.',
      );
    }
    final limit = extensions.contains(VideoCraftProject.extension)
        ? VideoCraftProject.maxProjectBytes
        : extensions.contains('json')
        ? 1024 * 1024
        : null;
    if (limit != null && file.size > limit) {
      throw const FormatException(
        'The selected document exceeds its size limit.',
      );
    }
    final bytes = file.bytes ?? await file.xFile.readAsBytes();
    if (limit != null && bytes.length > limit) {
      throw const FormatException(
        'The selected document exceeds its size limit.',
      );
    }
    if (bytes.isEmpty) {
      throw const FormatException('The selected file is empty.');
    }
    return VideoEditorPickedFile(file.name, bytes);
  }

  @override
  Future<VideoEditorSaveResult> save({
    required Uint8List bytes,
    required String name,
    required String extension,
  }) async {
    final path = await FilePicker.saveFile(
      fileName: name,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );
    // The browser starts a download and intentionally returns no local path.
    if (kIsWeb) return VideoEditorSaveResult.downloadStarted;
    return path == null
        ? VideoEditorSaveResult.cancelled
        : VideoEditorSaveResult.saved;
  }
}

class _SaveCancelled implements Exception {
  const _SaveCancelled();
  @override
  String toString() => 'Save cancelled.';
}

/// Self-contained page for timing and preview animation. Saving a recipe writes
/// JSON; video export writes the rendered trim. It does not update an upload flow.
class VideoEditorSectionsPage extends StatefulWidget {
  const VideoEditorSectionsPage({
    super.key,
    this.source,
    this.controller,
    this.previewBackend,
    this.trimExporter,
    this.files = const PlatformVideoEditorFileAccess(),
    this.recoveryId,
    this.recoveryStore,
  });
  final VideoCraftSource? source;
  final VideoCraftController? controller;
  final VideoCraftPreviewBackend? previewBackend;
  final VideoCraftTrimExporter? trimExporter;
  final VideoEditorFileAccess files;
  final String? recoveryId;
  final MediaRecoveryStore? recoveryStore;
  @override
  State<VideoEditorSectionsPage> createState() =>
      _VideoEditorSectionsPageState();
}

class _VideoEditorSectionsPageState extends State<VideoEditorSectionsPage> {
  late final VideoCraftController _controller;
  String? _fileStatus;
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? VideoCraftController();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  String get _stem {
    final name =
        _controller.recipe?.sourceName ?? widget.source?.name ?? 'video';
    final stem = name
        .replaceFirst(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9 _.-]'), '_');
    return stem.isEmpty ? 'video' : stem;
  }

  Future<VideoCraftSource?> _openVideo() async {
    final file = await widget.files.open(
      extensions: const ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'],
    );
    return file == null
        ? null
        : VideoCraftSource.bytes(file.bytes, name: file.name);
  }

  Future<String?> _openRecipe() async {
    final file = await widget.files.open(
      extensions: const ['neomvideo', 'json'],
    );
    return file == null ? null : utf8.decode(file.bytes);
  }

  Future<Uint8List?> _openProject() async {
    final file = await widget.files.open(
      extensions: const [VideoCraftProject.extension],
    );
    return file?.bytes;
  }

  Future<void> _save(Uint8List bytes, String name, String extension) async {
    final result = await widget.files.save(
      bytes: bytes,
      name: name,
      extension: extension,
    );
    if (mounted) {
      setState(
        () => _fileStatus = switch (result) {
          VideoEditorSaveResult.saved => 'Saved $name.',
          VideoEditorSaveResult.downloadStarted => 'Download started: $name.',
          VideoEditorSaveResult.cancelled => 'Save cancelled.',
        },
      );
    }
    // A cancelled dialog must not resolve as a successful workspace delivery.
    if (result == VideoEditorSaveResult.cancelled) throw const _SaveCancelled();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tiempo y animación')),
    body: SafeArea(
      child: Column(
        children: [
          if (_fileStatus != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_fileStatus!, key: const Key('video-file-status')),
            ),
          Expanded(
            child: VideoCraftWorkspace(
              recoveryId: widget.recoveryId,
              recoveryStore: widget.recoveryStore,
              controller: _controller,
              source: widget.source,
              previewBackend: widget.previewBackend,
              trimExporter: widget.trimExporter,
              onPickSource: _openVideo,
              onOpenRecipe: _openRecipe,
              onOpenProject: _openProject,
              onSaveProject: (bytes) => _save(
                bytes,
                '$_stem.${VideoCraftProject.extension}',
                VideoCraftProject.extension,
              ),
              onSaveRecipe: (json) => _save(
                Uint8List.fromList(utf8.encode(json)),
                '$_stem.recipe.json',
                'json',
              ),
              onExportVideo: (bytes) => _save(bytes, '$_stem.trim.mp4', 'mp4'),
            ),
          ),
        ],
      ),
    ),
  );
}
