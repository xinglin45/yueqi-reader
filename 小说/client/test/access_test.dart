import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/application/access.dart';
import 'package:novel_app/application/discovery.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/infrastructure/device_access_store.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:novel_app/infrastructure/storage/schema.dart';
import 'package:platform_services/platform_services.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_storage/reader_storage.dart';

JobContext job() => JobContext(id: 1, isCurrent: () => true, report: (_) {});
const normal = ContentRating(
  level: RatingLevel.general,
  sourceAccess: SourceAccess.notRequired,
);
const adult = ContentRating(
  level: RatingLevel.restricted,
  sourceAccess: SourceAccess.notRequired,
);
const approvedAdult = DiscoverySource(
  'adult',
  SourceMode.adult,
  enabled: true,
  approved: true,
  accessible: true,
);
const approvedNormal = DiscoverySource(
  'normal',
  SourceMode.normal,
  enabled: true,
  approved: true,
  accessible: true,
);

class Locations implements StorageLocationProvider {
  Locations(this.root);
  final String root;
  @override
  Future<AppStorageLocations> locations() async =>
      AppStorageLocations(support: '$root/support', cache: '$root/cache');
}

class DelayedStore implements DeviceAccessStore {
  AccessState value = const AccessState();
  @override
  Future<AccessState> read() async => value;
  final pending = <Completer<void>>[];
  bool fail = false;
  @override
  Future<void> write(AccessState state) async {
    final gate = Completer<void>();
    pending.add(gate);
    await gate.future;
    if (fail) throw const FileSystemException('test');
    value = state;
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
Future<void> copyTree(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entry in source.list()) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is Directory) {
      await copyTree(entry, Directory('${target.path}/$name'));
    } else if (entry is File) {
      await entry.copy('${target.path}/$name');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('five ratings, source conditions, raw unknown and upstream minimum age fail closed', () {
    for (final level in RatingLevel.values) {
      for (final upstream in SourceAccess.values) {
        final rating = ContentRating(
          level: level,
          raw: '原始评级',
          minimumAge: level == RatingLevel.restricted ? 18 : null,
          originalRegions: const ['source-label-only'],
          evidence: 'owned',
          sourceAccess: upstream,
        );
        final allowedSource =
            upstream == SourceAccess.notRequired ||
            upstream == SourceAccess.allowed;
        final known =
            level != RatingLevel.unknown && level != RatingLevel.prohibited;
        expect(
          mayRead(rating, const AccessState(acknowledged: true)),
          allowedSource && known,
        );
        expect(
          mayRead(rating, const AccessState()),
          allowedSource && level == RatingLevel.general,
        );
        expect(
          mayRead(
            rating,
            const AccessState(acknowledged: true, privacyLocked: true),
          ),
          allowedSource && level == RatingLevel.general,
        );
      }
    }
    expect(
      mayRead(
        const ContentRating(
          level: RatingLevel.general,
          minimumAge: 21,
          sourceAccess: SourceAccess.notRequired,
        ),
        const AccessState(acknowledged: true),
      ),
      false,
    );
    expect(
      mayRead(
        const ContentRating(
          level: RatingLevel.general,
          minimumAge: 18,
          sourceAccess: SourceAccess.notRequired,
        ),
        const AccessState(),
      ),
      false,
    );
  });
  test('declaration, discovery and privacy remain independent; invalidation stops sessions synchronously', () async {
    final store = MemoryAccessStore();
    final access = await AccessController.open(store);
    var stops = 0;
    final remove = access.registerProtectedStop(() => stops++);
    expect(access.state.adultDiscovery, false);
    await access.acknowledge();
    expect(access.state.adultVisible, true);
    expect(access.state.includeAdultSources, false);
    await access.setDiscovery(true);
    final visibility = access.state.visibilityRevision;
    await access.setDiscovery(false);
    expect(access.state.visibilityRevision, visibility);
    expect(mayRead(adult, access.state), true);
    expect(stops, 0);
    final locking = access.lock();
    expect(access.state.adultVisible, false);
    expect(stops, 1);
    await locking;
    await access.unlock();
    expect(access.state.acknowledged, true);
    access.invalidateProtected();
    expect(stops, 2);
    await access.clearAcknowledgement();
    expect(stops, 3);
    expect(access.state.includeAdultSources, false);
    expect(mayRead(normal, access.state), true);
    await expectLater(access.setDiscovery(true), throwsStateError);
    remove();
    await access.dispose();
    final reopened = await AccessController.open(store);
    expect(reopened.state.acknowledged, false);
    await reopened.dispose();
  });
  test('queued stale grants cannot reopen a lock or clear; failed persistence never grants', () async {
    final store = DelayedStore();
    final access = AccessController(store);
    final grant = access.acknowledge();
    await tick();
    expect(access.state.acknowledged, false);
    final clear = access.clearAcknowledgement();
    store.pending[0].complete();
    await grant;
    await tick();
    expect(access.state.acknowledged, false);
    store.pending[1].complete();
    await clear;
    expect(store.value.acknowledged, false);
    expect(store.value.privacyLocked, true);
    store.fail = true;
    final failing = access.acknowledge();
    final expectation = expectLater(
      failing,
      throwsA(isA<FileSystemException>()),
    );
    await tick();
    store.pending[2].complete();
    await expectation;
    expect(access.state.adultVisible, false);
    expect(mayRead(normal, access.state), true);
    await access.dispose();
  });
  test('discovery filters before request; mixed normal path and late cancellation use the same coordinator', () async {
    final access = AccessController(MemoryAccessStore());
    final calls = <String>[];
    final modes = <bool>[];
    final gates = <String, Completer<List<DiscoveryHit>>>{};
    final tokens = <DiscoveryCancellation>[];
    final discovery = DiscoveryCoordinator(
      access,
      [
        approvedAdult,
        approvedNormal,
        const DiscoverySource(
          'mixed-safe',
          SourceMode.mixed,
          enabled: true,
          approved: true,
          accessible: true,
          reliableNormalPath: true,
        ),
        const DiscoverySource(
          'mixed-unsafe',
          SourceMode.mixed,
          enabled: true,
          approved: true,
          accessible: true,
        ),
        const DiscoverySource(
          'unknown',
          SourceMode.unknown,
          enabled: true,
          approved: true,
          accessible: true,
        ),
        const DiscoverySource(
          'unapproved',
          SourceMode.adult,
          enabled: true,
          accessible: true,
        ),
        const DiscoverySource(
          'disabled',
          SourceMode.adult,
          approved: true,
          accessible: true,
        ),
      ],
      (source, query, normalOnly, token) async {
        calls.add(source.id);
        modes.add(normalOnly);
        tokens.add(token);
        if (gates[source.id] case final gate?) return gate.future;
        return [
          const DiscoveryHit('n', '自产普通标签', normal),
          const DiscoveryHit('a', '自产分级标签', adult),
          const DiscoveryHit(
            'u',
            '未知',
            ContentRating(level: RatingLevel.unknown),
          ),
        ];
      },
    );
    final off = await discovery.search('测试');
    expect(calls, ['normal', 'mixed-safe']);
    expect(modes.every((v) => v), true);
    expect(off.every((h) => !h.rating.protected), true);
    await access.acknowledge();
    calls.clear();
    await discovery.search('确认但关闭');
    expect(calls.contains('adult'), false);
    await access.setDiscovery(true);
    calls.clear();
    modes.clear();
    final on = await discovery.search('开启');
    expect(calls, ['adult', 'normal', 'mixed-safe', 'mixed-unsafe']);
    expect(modes.any((v) => v), false);
    expect(on.any((h) => h.rating.protected), true);
    gates['adult'] = Completer<List<DiscoveryHit>>();
    final late = discovery.search('迟到');
    await tick();
    await access.setDiscovery(false);
    expect(tokens[tokens.length - 4].cancelled, true);
    gates['adult']!.complete([const DiscoveryHit('late', '迟到标签', adult)]);
    expect(await late, isEmpty);
    expect(discovery.results.any((h) => h.rating.protected), false);
    await discovery.dispose();
    await access.dispose();
  });
  test('source access expiry and privacy block direct preview/position routes, while search OFF preserves adult collection', () async {
    final dir = await Directory.systemTemp.createTemp('mac16-policy-');
    final db = await StorageDatabase.open(
      directory: dir.path,
      product: ReaderProduct.novel,
      migrations: novelSchema,
    );
    final access = AccessController(MemoryAccessStore());
    final library = LocalLibrary(db, ContentFiles(dir.path), access: access);
    try {
      await expectLater(
        library.addClassificationCard(job()),
        throwsA(isA<AppFailure>()),
      );
      final ordinary = (await library.addDemonstration(job())).value.single;
      await access.acknowledge();
      final card = (await library.addClassificationCard(job())).value.single;
      expect(card.protected, true);
      expect((await library.load(job())).value.map((b) => b.id), [ordinary.id]);
      await access.setDiscovery(true);
      await access.setDiscovery(false);
      final preview = (await library.preview(card.id, job())).value;
      expect(preview.paragraphs.single, contains('不含成人正文'));
      final anchor = DocumentAnchor.capture(
        kind: DocumentKind.txt,
        revision: preview.documentRevision!,
        chapterId: preview.chapterId!,
        spineHref: preview.spineHref!,
        blockId: 'p0',
        text: preview.paragraphs.single,
        start: 0,
        end: 0,
      );
      await library.savePosition(
        card.id,
        PositionChannel.reading,
        anchor,
        expectedSequence: 0,
      );
      await access.lock();
      await expectLater(
        library.preview(card.id, job()),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        library.loadPosition(card.id, PositionChannel.reading),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        library.savePosition(
          card.id,
          PositionChannel.reading,
          anchor,
          expectedSequence: 1,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect((await library.load(job())).value.single.id, ordinary.id);
      await access.unlock();
      expect((await library.loadAdult(job())).value.single.id, card.id);
      await library.setSourceAccess(card.id, SourceAccess.expired);
      expect((await library.loadAdult(job())).value, isEmpty);
      await expectLater(
        library.preview(card.id, job()),
        throwsA(isA<AppFailure>()),
      );
      await library.setSourceAccess(card.id, SourceAccess.allowed);
      expect((await library.preview(card.id, job())).value.book.id, card.id);
      final newSession = LocalLibrary(
        db,
        ContentFiles(dir.path),
        access: access,
      );
      await expectLater(
        newSession.preview(card.id, job()),
        throwsA(isA<AppFailure>()),
      );
      await library.setSourceAccess(card.id, SourceAccess.notRequired);
      await access.clearAcknowledgement();
      expect((await db.query('SELECT id FROM books')), hasLength(2));
      expect(await db.query('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await access.dispose();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
  test('schema4 migration preserves raw metadata; unknown classification never becomes normal', () async {
    final dir = await Directory.systemTemp.createTemp('mac16-migrate-');
    var db = await StorageDatabase.open(
      directory: dir.path,
      product: ReaderProduct.novel,
      migrations: novelSchema.take(3).toList(),
    );
    try {
      final library = LocalLibrary(db, ContentFiles(dir.path));
      await library.addDemonstration(job());
      await db.transaction([
        const SqlCommand(
          "INSERT INTO books(id,title,language,rating,created_at,updated_at) VALUES('unknown','未知标签','zh','unknown',1,1)",
        ),
      ]);
      await db.close();
      db = await StorageDatabase.open(
        directory: dir.path,
        product: ReaderProduct.novel,
        migrations: novelSchema,
      );
      expect(db.info['version'], 5);
      final rows = await db.query(
        "SELECT * FROM content_policy WHERE book_id='unknown'",
      );
      expect(rows.single['level'], 'unknown');
      expect(rows.single['source_access'], 'unknown');
      expect(rows.single['regional_review'], 'skipped_by_user');
      expect(
        (await LocalLibrary(db, ContentFiles(dir.path)).load(job())).value,
        hasLength(1),
      );
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
  test('device state survives restart but portable library copy and fresh library do not restore permission; corruption fails closed', () async {
    final dir = await Directory.systemTemp.createTemp('mac16-device-');
    AppDependencies? first, copy;
    try {
      first = await AppDependencies.open(Locations('${dir.path}/a'));
      await first.access!.acknowledge();
      await first.access!.setDiscovery(true);
      await first.close!();
      first = await AppDependencies.open(Locations('${dir.path}/a'));
      expect(first.access!.state.acknowledged, true);
      expect(first.access!.state.includeAdultSources, true);
      await first.close!();
      first = null;
      await copyTree(
        Directory('${dir.path}/a/support/novel'),
        Directory('${dir.path}/b/support/novel'),
      );
      copy = await AppDependencies.open(Locations('${dir.path}/b'));
      expect(copy.access!.state.acknowledged, false);
      expect(copy.access!.state.includeAdultSources, false);
      await copy.close!();
      copy = null;
      final store = LocalDeviceAccessStore(
        '${dir.path}/a/support/novel-device',
      );
      await File('${store.directory}/access-v1.json').writeAsString('{broken');
      expect((await store.read()).adultVisible, false);
      await store.write(
        const AccessState(acknowledged: true, includeAdultSources: true),
      );
      await Directory('${dir.path}/a/support/novel').delete(recursive: true);
      first = await AppDependencies.open(Locations('${dir.path}/a'));
      expect(first.access!.state.acknowledged, false);
      expect(
        () => validatePortableAccess({'acknowledged': true}),
        throwsFormatException,
      );
      expect(
        () => AccessState.fromLocalJson({'schema_version': 1}),
        throwsFormatException,
      );
    } finally {
      await first?.close?.call();
      await copy?.close?.call();
      await dir.delete(recursive: true);
    }
  });
}
