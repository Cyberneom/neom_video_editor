import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';
import 'package:neom_video_editor/video_craft/data/video_craft_recovery.dart';

VideoCraftProject project({String title = 'Applied'}) => VideoCraftProject(
  source: VideoCraftSource.bytes(
    Uint8List.fromList([
      0,
      0,
      0,
      24,
      102,
      116,
      121,
      112,
      105,
      115,
      111,
      109,
      ...List.generate(128, (i) => i),
    ]),
    name: 'fixture.mp4',
    frameRate: CraftFrameRate(24, 1),
  ),
  recipe: VideoCraftRecipe(
    sourceName: 'fixture.mp4',
    duration: const Duration(seconds: 8),
    frameRate: CraftFrameRate(24, 1),
    inFrame: 24,
    outFrame: 120,
    title: title,
    opacityKeys: const {24: 1, 72: .5, 119: 0},
  ),
  frame: 72,
);

class ControlledStore implements MediaRecoveryStore {
  final memory = MemoryMediaRecoveryStore();
  Object? writeError, readError;
  Completer<void>? writeGate;
  int reads = 0, writes = 0, deletes = 0;
  final revisions = <String?>[];
  @override
  Future<MediaRecoverySnapshot?> read(String key) async {
    ++reads;
    if (readError != null) throw readError!;
    return memory.read(key);
  }

  @override
  Future<MediaRecoverySnapshot> write(
    String key,
    Uint8List bytes, {
    String? expectedRevision,
  }) async {
    ++writes;
    revisions.add(expectedRevision);
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    if (writeError != null) throw writeError!;
    return memory.write(key, bytes, expectedRevision: expectedRevision);
  }

  @override
  Future<void> delete(String key, {String? expectedRevision}) async {
    ++deletes;
    await memory.delete(key, expectedRevision: expectedRevision);
  }
}

Future<Uint8List> bytes(int value) async => Uint8List.fromList([value]);

void main() {
  test(
    'URI media cache reads once and an older failed source cannot clear the new cache',
    () async {
      final old = Completer<Uint8List>();
      var reads = 0;
      final cache = VideoCraftRecoverySourceCache(
        reader: (source) async {
          ++reads;
          if (source.name == 'old.mp4') return old.future;
          return project().source.bytes!;
        },
      );
      final first = VideoCraftSource.uri(
        Uri.parse('https://example.invalid/old.mp4'),
      );
      final second = VideoCraftSource.uri(
        Uri.parse('https://example.invalid/new.mp4'),
      );
      final previous = cache.resolve(first);
      final previousFailure = expectLater(previous, throwsStateError);
      final current = await cache.resolve(second);
      expect(await cache.resolve(second), same(current));
      old.completeError(StateError('Old source unavailable'));
      await previousFailure;
      expect(await cache.resolve(second), same(current));
      expect(reads, 2);
    },
  );

  test(
    'recovery envelope preserves portable project and separate title draft',
    () {
      final original = project();
      final decoded = VideoCraftRecoveryData.decode(
        VideoCraftRecoveryData(original, titleDraft: 'Not applied').encode(),
      );
      expect(decoded.project.encode(), original.encode());
      expect(decoded.titleDraft, 'Not applied');
      expect(decoded.project.recipe.title, 'Applied');
      final broken = VideoCraftRecoveryData(original).encode()..last ^= 1;
      expect(
        () => VideoCraftRecoveryData.decode(broken),
        throwsFormatException,
      );
      expect(
        () => VideoCraftRecoveryData(original, titleDraft: 'a' * 1001).encode(),
        throwsFormatException,
      );
    },
  );

  test('superseded source preparation and its failure never commit', () async {
    final store = ControlledStore();
    final session = VideoCraftRecoverySession(store, 'video.stale');
    addTearDown(session.dispose);
    await session.read();
    final old = Completer<Uint8List>();
    session.schedule(() => old.future);
    final flush = session.flush();
    session.invalidatePending();
    session.schedule(() => bytes(2));
    old.completeError(StateError('Old source disappeared'));
    await flush;
    expect(store.writes, 1);
    expect((await store.read(session.key))!.bytes, [2]);
    expect(session.error, isNull);
    expect(session.dirty, isFalse);
  });

  test(
    'an edit during commit writes the latest snapshot after its CAS revision',
    () async {
      final store = ControlledStore(), gate = Completer<void>();
      final session = VideoCraftRecoverySession(store, 'video.serial');
      addTearDown(session.dispose);
      await session.read();
      store.writeGate = gate;
      session.schedule(() => bytes(1));
      final flush = session.flush();
      await Future<void>.delayed(Duration.zero);
      session.schedule(() => bytes(2));
      expect(session.savedAt, isNull);
      expect(session.dirty, isTrue);
      gate.complete();
      await flush;
      expect(store.writes, 2);
      expect(store.revisions.first, isNull);
      expect(store.revisions.last, isNotNull);
      expect((await store.read(session.key))!.bytes, [2]);
      expect(session.savedAt, isNotNull);
      expect(session.dirty, isFalse);
    },
  );

  test('existing recovery blocks writes until explicit discard', () async {
    final store = ControlledStore();
    await store.memory.write('video.choice', Uint8List.fromList([7]));
    final session = VideoCraftRecoverySession(store, 'video.choice');
    addTearDown(session.dispose);
    await session.read();
    session.schedule(() => bytes(9));
    await session.flush();
    expect(session.blocked, isTrue);
    expect(store.writes, 0);
    await session.discard();
    await session.flush();
    expect(store.deletes, 1);
    expect((await store.read(session.key))!.bytes, [9]);
  });

  test(
    'conflict preserves the other session and re-read requires a new decision',
    () async {
      final store = ControlledStore();
      final session = VideoCraftRecoverySession(store, 'video.conflict');
      addTearDown(session.dispose);
      await session.read();
      await store.memory.write(session.key, Uint8List.fromList([8]));
      session.schedule(() => bytes(3));
      await session.flush();
      expect(session.error, isA<MediaRecoveryConflictException>());
      expect(session.blocked, isTrue);
      await session.retry();
      expect(session.candidate!.bytes, [8]);
      expect(session.blocked, isTrue);
      expect((await store.read(session.key))!.bytes, [8]);
    },
  );

  test(
    'quota failure retains previous commit and retry persists newest edit',
    () async {
      final store = ControlledStore();
      final session = VideoCraftRecoverySession(store, 'video.quota');
      addTearDown(session.dispose);
      await session.read();
      session.schedule(() => bytes(1));
      await session.flush();
      store.writeError = const MediaRecoveryException(
        MediaRecoveryErrorCode.quotaExceeded,
      );
      session.schedule(() => bytes(2));
      await session.flush();
      expect(session.error, isA<MediaRecoveryException>());
      expect(session.dirty, isTrue);
      expect((await store.read(session.key))!.bytes, [1]);
      session.schedule(() => bytes(3));
      store.writeError = null;
      await session.retry();
      expect((await store.read(session.key))!.bytes, [3]);
    },
  );

  test(
    'unreadable record is protected until its exact token is discarded',
    () async {
      final store = ControlledStore();
      final record = await store.memory.write(
        'video.corrupt',
        Uint8List.fromList([5]),
      );
      store.readError = MediaRecoveryException(
        MediaRecoveryErrorCode.corrupt,
        revision: record.revision,
      );
      final session = VideoCraftRecoverySession(store, 'video.corrupt');
      addTearDown(session.dispose);
      await session.read();
      session.schedule(() => bytes(7));
      await session.flush();
      expect(store.writes, 0);
      expect(session.discardRevision, record.revision);
      await session.discard();
      store.readError = null;
      await session.flush();
      expect((await store.read(session.key))!.bytes, [7]);
    },
  );
}
