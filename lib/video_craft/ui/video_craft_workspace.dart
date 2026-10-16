import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neom_craft_libs/neom_craft_libs.dart';
import 'package:neom_craft_workspace/neom_craft_workspace.dart';
import 'package:neom_filmcraft/neom_filmcraft.dart' show FilmTimecode;
import 'package:neom_media_recovery/neom_media_recovery.dart';
import '../data/video_craft_export_control.dart';
import '../data/video_craft_exporter_factory.dart';
import '../data/video_craft_preview_backend.dart';
import '../data/video_craft_project_source.dart';
import '../data/video_craft_recovery.dart';
import '../data/video_craft_trim_exporter.dart';
import '../domain/video_craft_project.dart';
import '../domain/video_craft_recipe.dart';
import '../domain/video_craft_source.dart';
import '../rendering/video_craft_title_renderer.dart';
import 'video_craft_controller.dart';

/// Independent video editing sections. Hosts own file selection and delivery;
/// recipe callbacks receive JSON, and MP4 callbacks receive actual rendered bytes.
class VideoCraftWorkspace extends StatefulWidget {
  const VideoCraftWorkspace({
    super.key,
    this.controller,
    this.source,
    this.previewBackend,
    this.onPickSource,
    this.onSaveRecipe,
    this.onOpenRecipe,
    this.onOpenProject,
    this.onSaveProject,
    this.active = true,
    this.trimExporter,
    this.onExportVideo,
    this.workspaceStore,
    this.recoveryId,
    this.recoveryStore,
    this.exportLabel = 'Export MP4',
    this.saveRenderedLabel = 'Save rendered MP4',
    this.exportReadyMessage,
  });

  /// Local workspace preferences are separate from projects and undo history.
  /// Null uses the platform preference store; inject a store for host control.
  final CraftWorkspaceStore? workspaceStore;

  /// Opt in with a stable, account/document-scoped ID. Null disables recovery.
  /// Recovery stays local and never uploads, exports MP4 or invokes save callbacks.
  final String? recoveryId;
  final MediaRecoveryStore? recoveryStore;
  final String exportLabel, saveRenderedLabel;
  final String? exportReadyMessage;
  final VideoCraftController? controller;
  final VideoCraftSource? source;
  final VideoCraftPreviewBackend? previewBackend;
  final Future<VideoCraftSource?> Function()? onPickSource;
  final Future<void> Function(String json)? onSaveRecipe;
  final Future<String?> Function()? onOpenRecipe;
  final Future<Uint8List?> Function()? onOpenProject;
  final Future<void> Function(Uint8List bytes)? onSaveProject;

  /// Hosts using IndexedStack set false while this editor is hidden.
  final bool active;
  final VideoCraftTrimExporter? trimExporter;
  final Future<void> Function(Uint8List bytes)? onExportVideo;
  @override
  State<VideoCraftWorkspace> createState() => _VideoCraftWorkspaceState();
}

class _VideoCraftWorkspaceState extends State<VideoCraftWorkspace>
    with WidgetsBindingObserver {
  VideoCraftRecoverySession? _recovery;
  VideoCraftRecipe? _recoveryRecipe;
  String _recoveryDraft = '';
  final _recoveryMediaCache = VideoCraftRecoverySourceCache();
  bool _restoringRecovery = false;
  late VideoCraftController _controller;
  late VideoCraftPreviewBackend _preview;
  final _title = TextEditingController();
  final _timecode = TextEditingController();
  final _workspaceFocus = FocusNode(debugLabel: 'video-workspace');
  bool _savingProject = false;
  Uint8List? _preparedProject;
  VideoCraftRecipe? _preparedProjectRecipe;
  VideoCraftSource? _source;
  String _lastTitle = '';
  String? _message;
  bool _busy = false, _seeking = false, _stopping = false;
  int _generation = 0, _seekRevision = 0, _playRevision = 0;
  int _pickRevision = 0;
  double? _opacityDraft;
  double? _exportProgress;
  VideoCraftExportCancellation? _exportCancellation;
  Future<void> Function()? _saveRendered;
  VideoCraftRecipe? _renderedRecipe;
  late final VideoCraftTrimExporter _defaultExporter =
      createVideoCraftTrimExporter();
  Future<void> _seekChain = Future.value();
  VideoCraftTrimExporter get _exporter =>
      widget.trimExporter ?? _defaultExporter;
  bool get _includesTitles =>
      _exporter is VideoCraftControlledExporter &&
      (_exporter as VideoCraftControlledExporter).includesAnimatedTitles;
  @override
  void initState() {
    super.initState();
    _bind();
    WidgetsBinding.instance.addObserver(this);
    _title.addListener(_onTitleDraft);
    _configureRecovery();
    if (widget.source != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(() => _open(widget.source!));
      });
    }
  }

  void _bind() {
    _controller = widget.controller ?? VideoCraftController();
    _preview = widget.previewBackend ?? VideoPlayerCraftBackend();
    _controller.attachPause(() async {
      ++_playRevision;
      await _preview.pause();
      _scheduleRecovery();
    });
    _controller.addListener(_onEdit);
    _preview.addListener(_onPreview);
  }

  void _unbind(VideoCraftWorkspace previous) {
    _controller.removeListener(_onEdit);
    _controller.attachPause(null);
    _preview.removeListener(_onPreview);
    if (previous.controller == null) _controller.dispose();
    if (previous.previewBackend == null) {
      _preview.dispose();
    } else {
      _preview.pause().catchError((Object _) {});
    }
  }

  @override
  void didUpdateWidget(covariant VideoCraftWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recoveryId != widget.recoveryId ||
        oldWidget.recoveryStore != widget.recoveryStore) {
      _configureRecovery();
    }
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _workspaceFocus.requestFocus();
      });
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.previewBackend != widget.previewBackend) {
      _recovery?.invalidatePending();
      _recoveryMediaCache.clear();
      _cancelExport();
      ++_generation;
      ++_seekRevision;
      ++_playRevision;
      _busy = false;
      _seeking = false;
      _stopping = false;
      _seekChain = Future.value();
      _unbind(oldWidget);
      _bind();
      _source = null;
      _preparedProject = null;
      _preparedProjectRecipe = null;
      if (widget.source != null) _run(() => _open(widget.source!));
    } else if (oldWidget.source != widget.source && widget.source != null) {
      _run(() => _open(widget.source!));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _title.removeListener(_onTitleDraft);
    final recovery = _recovery;
    recovery?.removeListener(_onRecoveryChanged);
    if (recovery != null) unawaited(recovery.finish());
    _cancelExport();
    ++_generation;
    ++_seekRevision;
    _unbind(widget);
    _title.dispose();
    _timecode.dispose();
    _workspaceFocus.dispose();
    super.dispose();
  }

  void _configureRecovery() {
    _recoveryMediaCache.clear();
    final previous = _recovery;
    previous?.removeListener(_onRecoveryChanged);
    if (previous != null) unawaited(previous.finish());
    final id = widget.recoveryId;
    _recovery = id == null
        ? null
        : VideoCraftRecoverySession(
            widget.recoveryStore ?? createDefaultMediaRecoveryStore(),
            id,
          );
    final current = _recovery;
    current?.addListener(_onRecoveryChanged);
    if (current != null) {
      unawaited(current.read());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(current, _recovery)) _scheduleRecovery();
      });
    }
  }

  void _onRecoveryChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleRecovery() {
    final session = _recovery, source = _source, recipe = _controller.recipe;
    if (session == null ||
        source == null ||
        recipe == null ||
        _busy ||
        _restoringRecovery) {
      return;
    }
    final frame = _controller.frame;
    final draft = _title.text == recipe.title ? null : _title.text;
    session.schedule(() async {
      final media = await _recoveryMediaCache.resolve(source);
      return VideoCraftRecoveryData(
        VideoCraftProject(source: media, recipe: recipe, frame: frame),
        titleDraft: draft,
      ).encode();
    });
  }

  void _onTitleDraft() {
    if (_title.text == _recoveryDraft) return;
    _recoveryDraft = _title.text;
    _scheduleRecovery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Best effort only: a killed process/browser need not grant enough time.
      _scheduleRecovery();
      final recovery = _recovery;
      if (recovery != null) unawaited(recovery.flush());
    }
  }

  Future<void> _restoreRecovery() async {
    final recovery = _recovery, candidate = _recovery?.candidate;
    if (recovery == null || candidate == null || _busy || _restoringRecovery) {
      return;
    }
    _restoringRecovery = true;
    try {
      final recovered = VideoCraftRecoveryData.decode(candidate.bytes);
      // Uses the same transactional decoder/preview validation as manual open.
      await _installProject(recovered.project);
      if (!mounted ||
          !identical(recovery, _recovery) ||
          !identical(_source, recovered.project.source)) {
        return;
      }
      if (recovered.titleDraft != null) _title.text = recovered.titleDraft!;
      recovery.acceptRecovery();
      setState(
        () =>
            _message = 'Session recovered. An unapplied title remains a draft.',
      );
    } catch (error) {
      if (mounted && identical(recovery, _recovery)) {
        recovery.reportError(error);
      }
    } finally {
      _restoringRecovery = false;
      if (mounted && identical(recovery, _recovery) && !recovery.blocked) {
        _scheduleRecovery();
      }
    }
  }

  Future<void> _discardRecovery() async {
    final recovery = _recovery;
    if (recovery == null) return;
    await recovery.discard();
    if (mounted && identical(recovery, _recovery) && !recovery.blocked) {
      _scheduleRecovery();
    }
  }

  Widget _buildRecoveryStatus() {
    final recovery = _recovery!;
    final error = recovery.error;
    final text = recovery.loading
        ? 'Checking local recovery…'
        : error != null
        ? 'Local recovery failed: $error'
        : recovery.candidate != null
        ? 'A saved local session is available. Restore or discard it before autosave resumes.'
        : recovery.saving
        ? 'Saving local recovery…'
        : recovery.dirty
        ? 'Local recovery pending…'
        : recovery.savedAt != null
        ? 'Local recovery saved on this device.'
        : 'Local recovery enabled. Project files are saved separately.';
    return Wrap(
      key: const Key('video-recovery-banner'),
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text, key: const Key('video-recovery-status')),
        if (recovery.candidate != null)
          TextButton(
            key: const Key('video-recovery-restore'),
            onPressed: _busy || recovery.loading ? null : _restoreRecovery,
            child: const Text('Restore session'),
          ),
        if (recovery.discardRevision != null)
          TextButton(
            key: const Key('video-recovery-discard'),
            onPressed: _busy || recovery.loading ? null : _discardRecovery,
            child: const Text('Discard recovery'),
          ),
        if (error != null)
          TextButton(
            key: const Key('video-recovery-retry'),
            onPressed: recovery.loading ? null : recovery.retry,
            child: const Text('Retry recovery'),
          ),
      ],
    );
  }

  void _onEdit() {
    if (!mounted) return;
    if (_saveRendered != null &&
        !identical(_renderedRecipe, _controller.recipe)) {
      _saveRendered = null;
      _renderedRecipe = null;
      _message = 'Edits changed. Export MP4 again to save the updated video.';
    }
    if (_preparedProject != null &&
        !identical(_preparedProjectRecipe, _controller.recipe)) {
      _preparedProject = null;
      _preparedProjectRecipe = null;
    }
    final title = _controller.recipe?.title ?? '';
    if (title != _lastTitle) {
      _lastTitle = title;
      _title.text = title;
    }
    if (!identical(_recoveryRecipe, _controller.recipe)) {
      _recoveryRecipe = _controller.recipe;
      _scheduleRecovery();
    }
    setState(() {});
  }

  void _onPreview() {
    if (!mounted || _busy) return;
    if (!_seeking) _controller.setPosition(_preview.position);
    final recipe = _controller.recipe;
    if (!_stopping &&
        _preview.isPlaying &&
        recipe != null &&
        _preview.position >= recipe.timeAtFrame(recipe.outFrame)) {
      _stopping = true;
      final generation = _generation;
      final preview = _preview;
      _run(() async {
        try {
          await preview.pause();
          if (!mounted ||
              generation != _generation ||
              preview != _preview ||
              !identical(recipe, _controller.recipe)) {
            return;
          }
          await _seekFrame(recipe.outFrame - 1);
        } finally {
          _stopping = false;
        }
      });
    }
    setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _pickSource() async {
    final generation = _generation;
    final revision = ++_pickRevision;
    bool isCurrent() =>
        mounted && generation == _generation && revision == _pickRevision;
    VideoCraftSource? source;
    try {
      source = await widget.onPickSource!();
    } catch (_) {
      if (isCurrent()) rethrow;
      return;
    }
    if (isCurrent() && source != null) await _open(source);
  }

  Future<void> _open(VideoCraftSource source) async {
    _recovery?.invalidatePending();
    _cancelExport();
    final generation = ++_generation;
    ++_seekRevision;
    ++_playRevision;
    _seeking = false;
    _seekChain = Future.value();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _preview.open(source);
      if (!mounted || generation != _generation) return;
      try {
        _controller.attachMedia(
          name: source.name,
          duration: _preview.duration,
          frameRate: source.frameRate,
        );
      } catch (_) {
        _source = null;
        _controller.clearMedia();
        rethrow;
      }
      _source = source;
      _preparedProject = null;
      _preparedProjectRecipe = null;
      _opacityDraft = null;
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _scheduleRecovery();
      }
    }
  }

  Future<void> _seekFrame(int frame, {bool cancelPlay = true}) async {
    if (cancelPlay) ++_playRevision;
    final r = _controller.recipe;
    if (r == null) return;
    final revision = ++_seekRevision;
    final generation = _generation;
    final target = frame.clamp(0, r.frameCount - 1);
    _controller.setFrame(target);
    _opacityDraft = null;
    _seeking = true;
    _seekChain = _seekChain.catchError((Object _) {}).then((_) async {
      if (!mounted || generation != _generation || revision != _seekRevision) {
        return;
      }
      await _preview.pause();
      if (!mounted || generation != _generation || revision != _seekRevision) {
        return;
      }
      await _preview.seek(r.timeAtFrame(target));
    });
    try {
      await _seekChain;
      if (mounted && revision == _seekRevision && generation == _generation) {
        _scheduleRecovery();
      }
    } finally {
      if (mounted && revision == _seekRevision) {
        setState(() => _seeking = false);
      }
    }
  }

  Future<void> _goToTimecode() async {
    final recipe = _controller.recipe;
    if (recipe == null) return;
    final frame = FilmTimecode.parseFrames(
      _timecode.text,
      recipe.frameRate,
      dropFrame: recipe.frameRate.supportsDropFrame,
      current: BigInt.from(_controller.frame),
    );
    // Validate before touching transport/selection; _seekFrame's clamping is
    // appropriate for step buttons, but would hide a mistyped destination here.
    if (frame.isNegative || frame >= BigInt.from(recipe.frameCount)) {
      throw FormatException(
        'Timecode is outside this video: ${recipe.timecode(0)} to '
        '${recipe.timecode(recipe.frameCount - 1)}.',
      );
    }
    setState(() => _message = null);
    await _seekFrame(frame.toInt());
  }

  Future<void> _togglePlay() async {
    final playRevision = ++_playRevision;
    final generation = _generation;
    if (_preview.isPlaying) {
      await _preview.pause();
      _scheduleRecovery();
      return;
    }
    final r = _controller.recipe!;
    if (_controller.frame < r.inFrame || _controller.frame >= r.outFrame - 1) {
      await _seekFrame(r.inFrame, cancelPlay: false);
    }
    await _seekChain;
    if (!mounted ||
        generation != _generation ||
        playRevision != _playRevision) {
      return;
    }
    await _preview.play();
  }

  Future<void> _save() async {
    final snapshot = _controller.recipe!;
    await widget.onSaveRecipe!(snapshot.encode());
    if (mounted) {
      setState(
        () => _message = identical(snapshot, _controller.recipe)
            ? 'Recipe delivered to host. Video is not embedded.'
            : 'Recipe delivered. Later changes are not included.',
      );
    }
  }

  Future<void> _openRecipe() async {
    final generation = _generation;
    final json = await widget.onOpenRecipe!();
    if (!mounted || json == null || generation != _generation) return;
    await _controller.pause();
    if (!mounted || generation != _generation) return;
    _controller.loadRecipe(json);
    await _seekFrame(_controller.recipe!.inFrame);
    if (mounted) {
      setState(() => _message = 'Recipe opened for the current source.');
    }
  }

  Future<void> _saveProject() async {
    if (_savingProject ||
        _busy ||
        _source == null ||
        _controller.recipe == null ||
        widget.onSaveProject == null) {
      return;
    }
    final source = _source!, recipe = _controller.recipe!;
    final frame = _controller.frame, generation = _generation;
    final deliver = widget.onSaveProject!;
    setState(() => _savingProject = true);
    try {
      if (source.bytes != null) {
        // No await before the host callback: a browser download retains the
        // Save/Ctrl+S user gesture. Encoding snapshots all current media bytes.
        final bytes = VideoCraftProject(
          source: source,
          recipe: recipe,
          frame: frame,
        ).encode();
        await deliver(bytes);
        if (mounted && generation == _generation) {
          setState(
            () => _message = identical(recipe, _controller.recipe)
                ? 'Project delivered with its source video and edits.'
                : 'Project delivered. Later edits are not included.',
          );
        }
      } else {
        final media = await readVideoCraftProjectSource(source);
        if (!mounted ||
            generation != _generation ||
            !identical(recipe, _controller.recipe)) {
          return;
        }
        final bytes = VideoCraftProject(
          source: VideoCraftSource.bytes(
            media,
            name: source.name,
            frameRate: recipe.frameRate,
          ),
          recipe: recipe,
          frame: frame,
        ).encode();
        setState(() {
          _preparedProject = bytes;
          _preparedProjectRecipe = recipe;
          _message =
              'Project prepared with the video. Save the prepared project.';
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) rethrow;
    } finally {
      if (mounted) setState(() => _savingProject = false);
    }
  }

  Future<void> _deliverPreparedProject() async {
    final bytes = _preparedProject;
    if (bytes == null || widget.onSaveProject == null) return;
    final generation = _generation;
    try {
      await widget.onSaveProject!(bytes);
    } catch (_) {
      if (mounted && generation == _generation) rethrow;
      return;
    }
    if (mounted &&
        generation == _generation &&
        identical(bytes, _preparedProject)) {
      setState(
        () => _message = 'Project delivered with its source video and edits.',
      );
    }
  }

  Future<void> _openProject() async {
    final generation = _generation, revision = ++_pickRevision;
    bool current() =>
        mounted && generation == _generation && revision == _pickRevision;
    Uint8List? bytes;
    try {
      bytes = await widget.onOpenProject!();
    } catch (_) {
      if (current()) rethrow;
      return;
    }
    if (!current() || bytes == null) return;
    // Validate lengths, types, media and checksum before touching the session.
    final project = VideoCraftProject.decode(bytes);
    if (!current()) return;
    await _installProject(project);
  }

  Future<void> _installProject(VideoCraftProject project) async {
    _recovery?.invalidatePending();
    final generation = ++_generation;
    ++_seekRevision;
    ++_playRevision;
    _seeking = false;
    _seekChain = Future.value();
    final previous = _preview;
    final previousSource = _source;
    final previousPosition = _controller.position;
    final ownsCandidate = widget.previewBackend == null;
    final candidate = ownsCandidate ? VideoPlayerCraftBackend() : previous;
    var installed = false;
    bool current() =>
        mounted && generation == _generation && identical(previous, _preview);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _controller.pause();
      if (!current()) return;
      await candidate.open(project.source);
      if (!current()) return;
      final toleranceUs =
          (1000000 / project.recipe.frameRate.framesPerSecond).ceil() + 1000;
      if (!candidate.isReady ||
          (candidate.duration - project.recipe.duration).inMicroseconds.abs() >
              toleranceUs ||
          project.recipe.timeAtFrame(project.recipe.outFrame).inMicroseconds >
              candidate.duration.inMicroseconds + toleranceUs) {
        throw const FormatException(
          'Project timing does not match its embedded video.',
        );
      }
      await candidate.seek(project.recipe.timeAtFrame(project.frame));
      if (!current()) return;
      if (ownsCandidate) {
        previous.removeListener(_onPreview);
        _preview = candidate;
        candidate.addListener(_onPreview);
      }
      _source = project.source;
      _preparedProject = null;
      _preparedProjectRecipe = null;
      _opacityDraft = null;
      _cancelExport();
      _controller.restoreProject(project.recipe, frame: project.frame);
      installed = true;
      if (ownsCandidate) previous.dispose();
      setState(
        () => _message = 'Project opened with its embedded video and edits.',
      );
    } catch (error) {
      // Default backend uses a separate candidate, so the prior player is still
      // intact. Injected backends are restored explicitly if opening failed.
      if (current() && !ownsCandidate && previousSource != null) {
        try {
          await previous.open(previousSource);
          if (current()) await previous.seek(previousPosition);
        } catch (_) {
          if (current()) {
            throw StateError(
              'Project could not open. The previous edits remain; its preview must be reopened.',
            );
          }
        }
      }
      if (mounted && generation == _generation) rethrow;
    } finally {
      if (ownsCandidate && !installed) candidate.dispose();
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _scheduleRecovery();
      }
    }
  }

  void _cancelExport() {
    _saveRendered = null;
    if (_exportCancellation != null) _busy = false;
    _exportCancellation?.cancel();
    _exportCancellation = null;
    _exportProgress = null;
  }

  Future<void> _export() async {
    final source = _source!, recipe = _controller.recipe!;
    final deliver = widget.onExportVideo!;
    final exporter = _exporter;
    final includesTitles = _includesTitles;
    final generation = _generation;
    final cancellation = VideoCraftExportCancellation();
    bool isCurrent() =>
        mounted &&
        generation == _generation &&
        identical(cancellation, _exportCancellation);
    setState(() {
      _busy = true;
      _message = null;
      _exportProgress = null;
      _exportCancellation = cancellation;
      _saveRendered = null;
    });
    try {
      await _controller.pause();
      if (!isCurrent() || cancellation.isCancelled) return;
      final bytes = exporter is VideoCraftControlledExporter
          ? await exporter.exportWithOptions(
              source,
              recipe,
              cancellation: cancellation,
              onProgress: (progress) {
                if (isCurrent() && !cancellation.isCancelled) {
                  setState(() => _exportProgress = progress.clamp(0, 1));
                }
              },
            )
          : await exporter.exportTrim(source, recipe);
      if (!isCurrent() || cancellation.isCancelled) return;
      if (includesTitles) {
        // A fresh click starts the host's download/save dialog with browser user
        // activation. Encoding can outlive the activation from Export MP4.
        setState(() {
          _saveRendered = () => deliver(bytes);
          _renderedRecipe = recipe;
          _message = identical(recipe, _controller.recipe)
              ? (widget.exportReadyMessage ??
                    'MP4 ready with the title and opacity animation. Save the rendered video.')
              : 'MP4 ready. Later edits are not included in this rendered video.';
        });
      } else {
        await deliver(bytes);
        if (isCurrent()) {
          setState(
            () => _message =
                'Trimmed video delivered. The title overlay is preview only.',
          );
        }
      }
    } catch (error) {
      if (isCurrent()) {
        setState(
          () => _message = cancellation.isCancelled
              ? 'Export cancelled.'
              : error.toString(),
        );
      }
    } finally {
      if (isCurrent()) {
        setState(() {
          if (cancellation.isCancelled) _message = 'Export cancelled.';
          _exportCancellation = null;
          _exportProgress = null;
          _busy = false;
        });
      }
    }
  }

  Future<void> _deliverRendered() async {
    final save = _saveRendered;
    if (save == null) return;
    // Do not await other work before calling the host: keep the user gesture.
    await save();
    if (mounted && identical(save, _saveRendered)) {
      setState(
        () => _message = 'MP4 delivered with the title and opacity animation.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _controller.recipe;
    final ready = r != null && _preview.isReady && !_busy;
    void saveShortcut() {
      if (widget.active && ready && widget.onSaveProject != null) {
        _run(_preparedProject == null ? _saveProject : _deliverPreparedProject);
      }
    }

    return CallbackShortcuts(
      bindings: {
        if (widget.active) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              saveShortcut,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
              saveShortcut,
        },
      },
      child: Focus(
        focusNode: _workspaceFocus,
        autofocus: widget.active,
        canRequestFocus: widget.active,
        descendantsAreFocusable: widget.active,
        child: CraftWorkspaceShell(
          workspaceId: 'neom_video_editor',
          store: widget.workspaceStore,
          initialPanelId: 'timing',
          toolbar: _buildToolbar(context, ready),
          canvas: _buildCanvas(context, r, ready),
          panels: [
            CraftWorkspacePanel(
              id: 'timing',
              title: 'Timing / edit',
              icon: Icons.av_timer,
              child: r == null
                  ? const Center(child: Text('Open a video to edit timing.'))
                  : _buildTimingPanel(context, r, ready),
            ),
            CraftWorkspacePanel(
              id: 'animation',
              title: 'Animation',
              icon: Icons.animation,
              child: r == null
                  ? const Center(
                      child: Text('Open a video to animate a title.'),
                    )
                  : _buildAnimationPanel(context, r, ready),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool ready) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_recovery != null) _buildRecoveryStatus(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('video-open'),
              onPressed: _busy || widget.onPickSource == null
                  ? null
                  : () => _run(_pickSource),
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Open video'),
            ),
            FilledButton.icon(
              key: const Key('video-save-project'),
              onPressed:
                  ready && !_savingProject && widget.onSaveProject != null
                  ? () => _run(_saveProject)
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                _savingProject ? 'Preparing project…' : 'Save project',
              ),
            ),
            OutlinedButton.icon(
              key: const Key('video-open-project'),
              onPressed: !_busy && widget.onOpenProject != null
                  ? () => _run(_openProject)
                  : null,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open project'),
            ),
            OutlinedButton(
              onPressed: ready && widget.onSaveRecipe != null
                  ? () => _run(_save)
                  : null,
              child: const Text('Save recipe'),
            ),
            OutlinedButton(
              onPressed: ready && widget.onOpenRecipe != null
                  ? () => _run(_openRecipe)
                  : null,
              child: const Text('Open recipe'),
            ),
            FilledButton(
              onPressed:
                  ready &&
                      _source != null &&
                      _exporter.isSupported &&
                      widget.onExportVideo != null
                  ? () => _run(_export)
                  : null,
              child: Text(
                _includesTitles ? widget.exportLabel : 'Export trimmed video',
              ),
            ),
            IconButton(
              tooltip: 'Undo',
              onPressed: ready && _controller.canUndo ? _controller.undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: ready && _controller.canRedo ? _controller.redo : null,
              icon: const Icon(Icons.redo),
            ),
          ],
        ),
        if (_busy) LinearProgressIndicator(value: _exportProgress),
        if (_exportCancellation != null)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _exportProgress == null
                    ? 'Preparing MP4…'
                    : 'Exporting MP4: ${(_exportProgress! * 100).round()}%',
              ),
              TextButton(
                onPressed: () => setState(() {
                  _exportCancellation?.cancel();
                  _message = 'Cancelling export…';
                }),
                child: const Text('Cancel export'),
              ),
            ],
          ),
        if (_preparedProject != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('video-save-prepared-project'),
              onPressed: _busy ? null : () => _run(_deliverPreparedProject),
              icon: const Icon(Icons.save_alt),
              label: const Text('Save prepared project'),
            ),
          ),
        if (_saveRendered != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _run(_deliverRendered),
              icon: const Icon(Icons.save_alt),
              label: Text(widget.saveRenderedLabel),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_message!, key: const Key('video-status')),
          ),
        if (_preview.error != null)
          Text(
            _preview.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );

  Widget _buildCanvas(
    BuildContext context,
    VideoCraftRecipe? r,
    bool ready,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      // Reserve room for transport and timecode in short desktop windows and
      // stacked mobile layouts. The entire canvas remains scrollable when even
      // the controls alone exceed the viewport (for example with a keyboard).
      final previewHeight = constraints.hasBoundedHeight
          ? (constraints.maxHeight - 220).clamp(72.0, 360.0).toDouble()
          : 360.0;
      return SingleChildScrollView(
        key: const Key('video-canvas-scroll'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'Open a video to edit timing and animate a title.\nProjects include the source video; recipes store edits separately.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              Text(
                r.sourceName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Center(
                child: ConstrainedBox(
                  key: const Key('video-preview-viewport'),
                  constraints: BoxConstraints(
                    maxWidth: 800,
                    maxHeight: previewHeight,
                  ),
                  child: AspectRatio(
                    aspectRatio: _preview.aspectRatio > 0
                        ? _preview.aspectRatio
                        : 16 / 9,
                    child: ColoredBox(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _preview.buildView(context),
                          IgnorePointer(
                            child: Opacity(
                              key: const Key('video-title-opacity'),
                              opacity: _controller.opacity,
                              child: Semantics(
                                label: r.title,
                                child: CustomPaint(
                                  key: const Key('video-title-overlay'),
                                  painter: VideoCraftTitlePainter(
                                    title: r.title,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: _preview.isPlaying ? 'Pause' : 'Play selection',
                    onPressed: ready ? () => _run(_togglePlay) : null,
                    icon: Icon(
                      _preview.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous frame',
                    onPressed: ready
                        ? () => _run(() => _seekFrame(_controller.frame - 1))
                        : null,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    tooltip: 'Next frame',
                    onPressed: ready
                        ? () => _run(() => _seekFrame(_controller.frame + 1))
                        : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                  Text(
                    '${r.timecode(_controller.frame)} · Frame ${_controller.frame}',
                    key: const Key('video-playhead'),
                  ),
                ],
              ),
              Slider(
                key: const Key('video-scrub'),
                value: _controller.frame.toDouble(),
                min: 0,
                max: (r.frameCount - 1).toDouble(),
                onChanged: ready && r.frameCount > 1
                    ? (value) => _run(() => _seekFrame(value.round()))
                    : null,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('video-timecode-input'),
                      controller: _timecode,
                      enabled: ready,
                      maxLength: 128,
                      textInputAction: TextInputAction.go,
                      decoration: const InputDecoration(
                        labelText: 'Go to timecode',
                        hintText: '00:00:10:00, +15, -1.00',
                        counterText: '',
                      ),
                      onSubmitted: ready ? (_) => _run(_goToTimecode) : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: const Key('video-timecode-go'),
                    onPressed: ready ? () => _run(_goToTimecode) : null,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Go'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _buildTimingPanel(
    BuildContext context,
    VideoCraftRecipe r,
    bool ready,
  ) => SingleChildScrollView(
    key: const Key('video-timing-scroll'),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Timeline rate: ${r.frameRate.framesPerSecond.toStringAsFixed(3)} fps. Match this to the source.',
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final rate in [
              CraftFrameRate(24, 1),
              CraftFrameRate(25, 1),
              CraftFrameRate(30000, 1001),
              CraftFrameRate(30, 1),
              CraftFrameRate(60000, 1001),
              CraftFrameRate(60, 1),
            ])
              ActionChip(
                label: Text(
                  rate.denominator == BigInt.one
                      ? '${rate.numerator}'
                      : rate.framesPerSecond.toStringAsFixed(2),
                ),
                onPressed: ready
                    ? () => _run(() async {
                        await _controller.pause();
                        _controller.setFrameRate(rate);
                        await _seekFrame(_controller.frame);
                      })
                    : null,
              ),
          ],
        ),
        Text(
          'In ${r.inFrame} (${r.timecode(r.inFrame)}) · Out ${r.outFrame} (${r.timecode(r.outFrame)}, exclusive)',
          key: const Key('video-range'),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: ready && _controller.frame < r.outFrame
                  ? () => _controller.setTrim(_controller.frame, r.outFrame)
                  : null,
              child: const Text('Set In'),
            ),
            OutlinedButton(
              onPressed: ready && _controller.frame >= r.inFrame
                  ? () => _controller.setTrim(r.inFrame, _controller.frame + 1)
                  : null,
              child: const Text('Set Out after frame'),
            ),
            OutlinedButton(
              onPressed: ready
                  ? () => _controller.setTrim(0, r.frameCount)
                  : null,
              child: const Text('Full source'),
            ),
          ],
        ),
        const Text(
          'Frame-based edit boundaries; decoded seek accuracy depends on the player and source codec.',
        ),
        const SizedBox(height: 12),
        Text(
          _exporter.isSupported
              ? (_includesTitles
                    ? 'Exports MP4 with the title, opacity animation and source audio. Codec support is checked before rendering.'
                    : 'Exports trim only. Animated titles are preview only.')
              : 'Video export is unavailable on this platform. You can save the recipe.',
        ),
      ],
    ),
  );

  Widget _buildAnimationPanel(
    BuildContext context,
    VideoCraftRecipe r,
    bool ready,
  ) => SingleChildScrollView(
    key: const Key('video-animation-scroll'),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('video-title-input'),
          controller: _title,
          enabled: ready,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: ready ? _controller.setTitle : null,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: ready ? () => _controller.setTitle(_title.text) : null,
            child: const Text('Apply title'),
          ),
        ),
        Text(
          'Opacity ${((_opacityDraft ?? _controller.opacity) * 100).round()}% · Frame ${_controller.frame}',
        ),
        Slider(
          key: const Key('video-opacity-slider'),
          value: _opacityDraft ?? _controller.opacity,
          onChanged: ready
              ? (value) => setState(() => _opacityDraft = value)
              : null,
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: ready
                  ? () {
                      _controller.putOpacityKey(
                        _opacityDraft ?? _controller.opacity,
                      );
                      setState(() => _opacityDraft = null);
                    }
                  : null,
              child: const Text('Set opacity key'),
            ),
            OutlinedButton(
              onPressed: ready && r.opacityKeys.containsKey(_controller.frame)
                  ? _controller.removeOpacityKey
                  : null,
              child: const Text('Remove key'),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final entry
                in (r.opacityKeys.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key))))
              ActionChip(
                label: Text(
                  'Frame ${entry.key}: ${(entry.value * 100).round()}%',
                ),
                onPressed: ready
                    ? () => _run(() => _seekFrame(entry.key))
                    : null,
              ),
          ],
        ),
        Text(
          'Linear opacity keys use Effectcraft at the same source time as the video. '
          '${_includesTitles ? 'The MP4 export includes this animation.' : 'This overlay is preview only.'}',
        ),
      ],
    ),
  );
}
