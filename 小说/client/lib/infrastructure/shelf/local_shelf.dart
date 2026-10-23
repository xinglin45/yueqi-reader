import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reader_storage/reader_storage.dart';

import '../../domain/jobs.dart';
import '../../domain/library.dart';
import '../../domain/shelf.dart';
import '../../domain/importing.dart';
import '../importing/local_importer.dart';
import '../storage/local_library.dart';
import 'cover_image.dart';

/// Novel-owned management. SQL changes and durable undo records commit together.
final class LocalShelf implements ShelfRepository {
  LocalShelf(this.library, this.importer);
  final LocalLibrary library;
  final LocalImporter? importer;
  StorageDatabase get db => library.database;
  String get root => library.files.root;
  Future<void> _tail = Future.value();
  bool _closing = false;
  Future<T> _serial<T>(Future<T> Function() work) {
    if (_closing) return Future.error(const StorageFailure('closed'));
    final value = _tail.then((_) => work());
    _tail = value.then<void>((_) {}, onError: (Object _) {});
    return value;
  }

  Future<void> dispose() {
    _closing = true;
    return _tail;
  }

  @override
  Future<ShelfOptions> preferences(ShelfScope scope, {bool recent = false}) =>
      _serial(() => _preferences(scope, recent: recent));
  @override
  Future<ShelfPage> list(
    ShelfScope scope,
    ShelfOptions options,
    JobContext job, {
    int page = 0,
    bool recent = false,
  }) => _serial(() => _list(scope, options, job, page: page, recent: recent));
  @override
  Future<String?> latestAction(ShelfScope scope) =>
      _serial(() => _latestAction(scope));
  @override
  Future<Uint8List?> cover(String id) => _serial(() => _cover(id));
  int get _visibility => library.access?.state.visibilityRevision ?? 0;
  Future<void> _guard(String id, int ticket) async {
    await library.managementAccess(id);
    if (ticket != _visibility) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
  }

  void _scope(ShelfScope scope) {
    if (scope == ShelfScope.adult &&
        library.access?.state.adultVisible != true) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
  }

  String _scopeFor(Map row) =>
      row['rating'] == 'adult' ||
          const ['mature', 'restricted'].contains(row['level']) ||
          ((row['minimum_age'] as int?) ?? 0) >= 18
      ? 'adult'
      : 'normal';
  Future<Map<String, Object?>> _row(String id) async {
    final rows = await db.query(
      'SELECT b.*,p.level,p.minimum_age FROM books b LEFT JOIN content_policy p ON p.book_id=b.id WHERE b.id=?',
      [id],
    );
    if (rows.isEmpty) throw const AppFailure(FailureCode.missing);
    return rows.single;
  }

  Future<ShelfOptions> _preferences(
    ShelfScope scope, {
    bool recent = false,
  }) async {
    _scope(scope);
    final rows = await db.query(
      'SELECT value FROM shelf_preferences WHERE scope=?',
      [recent ? 'recent' : scope.name],
    );
    _scope(scope);
    return rows.isEmpty
        ? ShelfOptions(sort: recent ? ShelfSort.recent : ShelfSort.added)
        : ShelfOptions.fromJson(
            jsonDecode(rows.single['value'] as String) as Map<String, dynamic>,
          );
  }

  @override
  Future<void> savePreferences(
    ShelfScope scope,
    ShelfOptions options, {
    bool recent = false,
  }) => _serial(() async {
    _scope(scope);
    if (options.search.length > 200 || options.group.length > 100) {
      throw const FormatException('shelf_options');
    }
    await db.transaction([
      SqlCommand(
        'INSERT INTO shelf_preferences VALUES(?,?) ON CONFLICT(scope) DO UPDATE SET value=excluded.value',
        [recent ? 'recent' : scope.name, jsonEncode(options.toJson())],
      ),
    ]);
  });
  Future<List<ShelfGroup>> _groups(ShelfScope scope) async {
    _scope(scope);
    final rows = await db.query(
      "SELECT id,label,kind,deleted FROM collections WHERE scope=? AND kind!='adult' ORDER BY kind,label,id",
      [scope.name],
    );
    _scope(scope);
    return [
      for (final r in rows)
        ShelfGroup(
          r['id'] as String,
          r['label'] as String,
          r['kind'] as String,
          removed: r['deleted'] == 1,
        ),
    ];
  }

  Future<ShelfPage> _list(
    ShelfScope scope,
    ShelfOptions options,
    JobContext job, {
    int page = 0,
    bool recent = false,
  }) async {
    if (page < 0 || page > 100000) throw const FormatException('shelf_page');
    _scope(scope);
    job.checkCancelled();
    final ticket = _visibility;
    final group = scope == ShelfScope.adult
        ? "(p.level IN ('mature','restricted') OR p.minimum_age>=18 OR b.rating='adult')"
        : "b.rating='general' AND p.level='general' AND (p.minimum_age IS NULL OR p.minimum_age<18)";
    final where = <String>[
      'b.deleted=?',
      group,
      "p.source_access='notRequired'",
    ];
    final args = <Object?>[options.removed ? 1 : 0];
    if (recent) where.add('COALESCE(m.last_opened,0)>0');
    if (options.state.isNotEmpty) {
      where.add("COALESCE(m.state,'unread')=?");
      args.add(options.state);
    }
    if (options.favorite) where.add('m.favorite=1');
    if (options.format.isNotEmpty) {
      where.add('d.kind=?');
      args.add(options.format);
    }
    if (options.group.isNotEmpty) {
      where.add(
        'EXISTS(SELECT 1 FROM collection_books cb JOIN collections c ON c.id=cb.collection_id WHERE cb.book_id=b.id AND c.id=? AND c.scope=? AND c.deleted=0)',
      );
      args.addAll([options.group, scope.name]);
    }
    if (options.search.isNotEmpty) {
      where.add(
        "(instr(lower(b.title),lower(?))>0 OR instr(lower(COALESCE(m.author,'')),lower(?))>0 OR EXISTS(SELECT 1 FROM collection_books cb JOIN collections c ON c.id=cb.collection_id WHERE cb.book_id=b.id AND c.scope=? AND c.deleted=0 AND instr(lower(c.label),lower(?))>0))",
      );
      args.addAll([options.search, options.search, scope.name, options.search]);
    }
    const from =
        'FROM books b JOIN content_policy p ON p.book_id=b.id LEFT JOIN book_metadata m ON m.book_id=b.id LEFT JOIN imports i ON i.document_id=(SELECT di.id FROM documents di JOIN imports ii ON ii.document_id=di.id WHERE di.book_id=b.id LIMIT 1) LEFT JOIN documents d ON d.id=i.document_id';
    final clause = where.join(' AND ');
    final order = switch (options.sort) {
      ShelfSort.manual => 'COALESCE(m.manual_order,0),b.created_at',
      ShelfSort.title => 'b.title COLLATE NOCASE',
      ShelfSort.author => "COALESCE(m.author,'') COLLATE NOCASE,b.title",
      ShelfSort.recent => 'COALESCE(m.last_opened,0) DESC',
      ShelfSort.added => 'b.created_at DESC',
    };
    final count = await db.query(
      'SELECT count(*) AS n $from WHERE $clause',
      args,
    );
    final rows = await db.query(
      "SELECT b.*,m.author,m.synopsis,m.state,m.favorite,m.manual_order,m.last_opened,m.cover_digest,m.file_health,d.kind,d.digest,d.byte_length,i.mode,i.display_name,EXISTS(SELECT 1 FROM file_recycle f WHERE f.book_id=b.id) AS recycled,(SELECT parser_version FROM documents WHERE book_id=b.id LIMIT 1) AS parser_hint,(SELECT count(*) FROM books b2 WHERE b2.title=b.title AND b2.id!=b.id AND b2.deleted=0 AND b2.rating=b.rating AND EXISTS(SELECT 1 FROM content_policy p2 WHERE p2.book_id=b2.id AND p2.level=p.level AND p2.source_access='notRequired')) AS similar $from WHERE $clause ORDER BY $order,b.id LIMIT 50 OFFSET ?",
      [...args, page * 50],
    );
    final books = <ShelfBook>[];
    for (final r in rows) {
      job.checkCancelled();
      await _guard(r['id'] as String, ticket);
      var health = r['file_health'] as String? ?? 'unknown';
      if (r['mode'] == 'managed') {
        health =
            await FileSystemEntity.type(
                  '$root/objects/${r['digest']}',
                  followLinks: false,
                ) ==
                FileSystemEntityType.file
            ? 'available'
            : 'missing';
      }
      if (r['recycled'] == 1) health = 'recycled';
      final links = await db.query(
        "SELECT cb.collection_id FROM collection_books cb JOIN collections c ON c.id=cb.collection_id WHERE cb.book_id=? AND c.kind!='adult' AND c.scope=? AND c.deleted=0",
        [r['id'], scope.name],
      );
      books.add(
        ShelfBook(
          book: BookSummary(
            id: r['id'] as String,
            title: r['title'] as String,
            subtitle: r['mode'] == 'reference' ? '系统书签引用' : '本机内容',
            persistent: true,
            protected: scope == ShelfScope.adult,
            demo: r['parser_hint'] == LocalLibrary.parser,
            previewAvailable: r['kind'] == null,
            importedTxt: r['kind'] == 'txt',
            importedEpub: r['kind'] == 'epub',
          ),
          revision: r['row_revision'] as int,
          author: r['author'] as String? ?? '',
          synopsis: r['synopsis'] as String? ?? '',
          language: r['language'] as String,
          state: ReadingState.values.byName(r['state'] as String? ?? 'unread'),
          favorite: r['favorite'] == 1,
          order: r['manual_order'] as int? ?? 0,
          lastOpened: r['last_opened'] as int? ?? 0,
          removed: r['deleted'] == 1,
          format: r['kind'] as String? ?? 'txt',
          mode: r['mode'] as String? ?? 'sample',
          health: health,
          bytes: r['byte_length'] as int? ?? 0,
          sourceName: r['display_name'] as String? ?? '',
          groups: [for (final l in links) l['collection_id'] as String],
          cover: r['cover_digest'] != null,
          recycled: r['recycled'] == 1,
          similarTitles: r['similar'] as int,
        ),
      );
    }
    final groups = await _groups(scope);
    job.checkCancelled();
    if (ticket != _visibility) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    return ShelfPage(
      List.unmodifiable(books),
      count.single['n'] as int,
      groups,
    );
  }

  static const _meta = [
    'author',
    'synopsis',
    'state',
    'favorite',
    'manual_order',
    'last_opened',
    'cover_digest',
    'file_health',
  ];
  Map<String, Object?> _defaults(String id) => {
    'book_id': id,
    'author': '',
    'synopsis': '',
    'state': 'unread',
    'favorite': 0,
    'manual_order': 0,
    'last_opened': 0,
    'cover_digest': null,
    'file_health': 'unknown',
  };
  SqlCommand _putMeta(Map<String, Object?> row) => SqlCommand(
    'INSERT INTO book_metadata(book_id,${_meta.join(',')}) VALUES(${List.filled(9, '?').join(',')}) ON CONFLICT(book_id) DO UPDATE SET ${_meta.map((s) => '$s=excluded.$s').join(',')}',
    [row['book_id'], for (final key in _meta) row[key]],
  );
  void _validate(BookEdit e) {
    for (final (text, limit) in [
      (e.title, 200),
      (e.author, 200),
      (e.synopsis, 4000),
    ]) {
      if (text != null && (text.length > limit || text.contains('\u0000'))) {
        throw const FormatException('metadata_limit');
      }
    }
    if (e.title?.trim().isEmpty == true ||
        (e.language != null &&
            !const ['zh', 'zh-Hans', 'zh-Hant'].contains(e.language)) ||
        (e.order != null && (e.order! < 0 || e.order! > 1000000000))) {
      throw const FormatException('metadata');
    }
    if (e.groups != null &&
        (e.groups!.length > 50 ||
            e.groups!.toSet().length != e.groups!.length)) {
      throw const FormatException('groups');
    }
  }

  @override
  Future<String> edit(Map<String, int> revisions, BookEdit edit) =>
      _serial(() => _edit(revisions, edit));
  Future<String> _edit(
    Map<String, int> revisions,
    BookEdit edit, {
    bool setCover = false,
    String? coverDigest,
  }) async {
    _validate(edit);
    if (revisions.isEmpty || revisions.length > 100) {
      throw const FormatException('selection');
    }
    final ticket = _visibility, action = newLocalId();
    final snapshots = <Map<String, Object?>>[], commands = <SqlCommand>[];
    for (final entry in revisions.entries) {
      final id = entry.key;
      await _guard(id, ticket);
      final row = await _row(id);
      if (row['row_revision'] != entry.value) {
        throw const StorageFailure('stale_revision');
      }
      final old =
          (await db.query('SELECT * FROM book_metadata WHERE book_id=?', [
            id,
          ])).firstOrNull ??
          _defaults(id);
      final links = await db.query(
        "SELECT cb.collection_id FROM collection_books cb JOIN collections c ON c.id=cb.collection_id WHERE cb.book_id=? AND c.kind!='adult'",
        [id],
      );
      if (edit.groups != null) {
        for (final group in edit.groups!) {
          if ((await db.query(
            "SELECT id FROM collections WHERE id=? AND scope=? AND kind!='adult' AND deleted=0",
            [group, _scopeFor(row)],
          )).isEmpty) {
            throw const FormatException('group_scope');
          }
        }
      }
      final snapshot = <String, Object?>{
        'id': id,
        'after': entry.value + 1,
        'title': row['title'],
        'language': row['language'],
        'deleted': row['deleted'],
        'meta': old,
        'groups': [for (final r in links) r['collection_id']],
      };
      if (edit.clearRecords) {
        snapshot['positions'] = await db.query(
          'SELECT * FROM positions WHERE book_id=?',
          [id],
        );
        snapshot['annotations'] = await db.query(
          'SELECT id,deleted,row_revision FROM annotations WHERE book_id=?',
          [id],
        );
        commands.addAll([
          SqlCommand('DELETE FROM positions WHERE book_id=?', [id]),
          SqlCommand(
            'UPDATE annotations SET deleted=1,row_revision=row_revision+1 WHERE book_id=?',
            [id],
          ),
        ]);
      }
      snapshots.add(snapshot);
      commands.add(
        SqlCommand(
          'UPDATE books SET title=?,language=?,deleted=?,row_revision=row_revision+1,updated_at=? WHERE id=? AND row_revision=?',
          [
            edit.title?.trim() ?? row['title'],
            edit.language ?? row['language'],
            edit.removed == null ? row['deleted'] : (edit.removed! ? 1 : 0),
            DateTime.now().millisecondsSinceEpoch,
            id,
            entry.value,
          ],
          1,
        ),
      );
      commands.add(
        _putMeta({
          ...old,
          'author': edit.author?.trim() ?? old['author'],
          'synopsis': edit.synopsis ?? old['synopsis'],
          'state': edit.state?.name ?? old['state'],
          'favorite': edit.favorite == null
              ? old['favorite']
              : (edit.favorite! ? 1 : 0),
          'manual_order': edit.order ?? old['manual_order'],
          if (setCover) 'cover_digest': coverDigest,
        }),
      );
      if (edit.groups != null) {
        commands.add(
          SqlCommand(
            "DELETE FROM collection_books WHERE book_id=? AND collection_id IN(SELECT id FROM collections WHERE kind!='adult')",
            [id],
          ),
        );
        for (final group in edit.groups!) {
          commands.add(
            SqlCommand('INSERT INTO collection_books VALUES(?,?)', [group, id]),
          );
        }
      }
    }
    for (final id in revisions.keys) {
      await _guard(id, ticket);
    }
    commands.add(
      SqlCommand('INSERT INTO shelf_actions VALUES(?,?,?)', [
        action,
        jsonEncode(snapshots),
        DateTime.now().millisecondsSinceEpoch,
      ]),
    );
    commands.add(
      const SqlCommand(
        'DELETE FROM shelf_actions WHERE id IN(SELECT id FROM shelf_actions ORDER BY created_at DESC,id DESC LIMIT -1 OFFSET 20)',
      ),
    );
    await db.transaction(commands);
    if (edit.removed == true || edit.clearRecords) {
      library.access?.invalidateProtected();
    }
    return action;
  }

  @override
  Future<void> undo(String action) => _serial(() async {
    final rows = await db.query(
      'SELECT payload FROM shelf_actions WHERE id=?',
      [action],
    );
    if (rows.isEmpty) throw const StorageFailure('undo_expired');
    final ticket = _visibility,
        commands = <SqlCommand>[
          SqlCommand('DELETE FROM shelf_actions WHERE id=?', [action], 1),
        ];
    for (final raw in jsonDecode(rows.single['payload'] as String) as List) {
      final s = Map<String, dynamic>.from(raw as Map);
      final id = s['id'] as String;
      await _guard(id, ticket);
      commands.add(
        SqlCommand(
          'UPDATE books SET title=?,language=?,deleted=?,row_revision=row_revision+1,updated_at=? WHERE id=? AND row_revision=?',
          [
            s['title'],
            s['language'],
            s['deleted'],
            DateTime.now().millisecondsSinceEpoch,
            id,
            s['after'],
          ],
          1,
        ),
      );
      commands.add(_putMeta(Map<String, Object?>.from(s['meta'] as Map)));
      commands.add(
        SqlCommand(
          "DELETE FROM collection_books WHERE book_id=? AND collection_id IN(SELECT id FROM collections WHERE kind!='adult')",
          [id],
        ),
      );
      for (final group in s['groups'] as List) {
        if ((await db.query(
          'SELECT id FROM collections WHERE id=? AND deleted=0',
          [group],
        )).isEmpty) {
          throw const StorageFailure('undo_group_changed');
        }
        commands.add(
          SqlCommand('INSERT INTO collection_books VALUES(?,?)', [group, id]),
        );
      }
      if (s.containsKey('positions')) {
        for (final p in s['positions'] as List) {
          commands.add(
            SqlCommand('INSERT INTO positions VALUES(?,?,?,?,?,?)', [
              p['book_id'],
              p['channel'],
              p['document_id'],
              p['anchor'],
              p['local_seq'],
              p['updated_at'],
            ], 1),
          );
        }
        for (final a in s['annotations'] as List) {
          commands.add(
            SqlCommand(
              'UPDATE annotations SET deleted=?,row_revision=row_revision+1 WHERE id=? AND row_revision=?',
              [a['deleted'], a['id'], (a['row_revision'] as int) + 1],
              1,
            ),
          );
        }
      }
    }
    await db.transaction(commands);
    library.access?.invalidateProtected();
  });
  void _label(String label) {
    if (label.trim().isEmpty || label.length > 80 || label.contains('\u0000')) {
      throw const FormatException('group_label');
    }
  }

  @override
  Future<String> createGroup(ShelfScope scope, String label, String kind) =>
      _serial(() async {
        _scope(scope);
        _label(label);
        if (!const ['collection', 'tag'].contains(kind)) {
          throw const FormatException('group_kind');
        }
        final count = await db.query(
          'SELECT count(*) AS n FROM collections WHERE scope=?',
          [scope.name],
        );
        if ((count.single['n'] as int) >= 500) {
          throw const FormatException('group_limit');
        }
        final id = newLocalId();
        await db.transaction([
          SqlCommand(
            'INSERT INTO collections(id,label,kind,scope) VALUES(?,?,?,?)',
            [id, label.trim(), kind, scope.name],
          ),
        ]);
        return id;
      });
  @override
  Future<void> renameGroup(ShelfScope scope, String id, String label) =>
      _serial(() async {
        _scope(scope);
        _label(label);
        await db.transaction([
          SqlCommand(
            "UPDATE collections SET label=?,row_revision=row_revision+1 WHERE id=? AND scope=? AND kind!='adult' AND deleted=0",
            [label.trim(), id, scope.name],
            1,
          ),
        ]);
      });
  @override
  Future<void> removeGroup(
    ShelfScope scope,
    String id, {
    bool removed = true,
  }) => _serial(() async {
    _scope(scope);
    await db.transaction([
      SqlCommand(
        "UPDATE collections SET deleted=?,row_revision=row_revision+1 WHERE id=? AND scope=? AND kind!='adult'",
        [removed ? 1 : 0, id, scope.name],
        1,
      ),
    ]);
  });
  Future<String?> _latestAction(ShelfScope scope) async {
    _scope(scope);
    for (final row in await db.query(
      'SELECT * FROM shelf_actions ORDER BY created_at DESC,id DESC LIMIT 20',
    )) {
      final entries = jsonDecode(row['payload'] as String) as List;
      var permitted = true;
      for (final entry in entries) {
        final book = await _row(entry['id'] as String);
        if (_scopeFor(book) != scope.name ||
            book['row_revision'] != entry['after']) {
          permitted = false;
          break;
        }
      }
      _scope(scope);
      if (permitted) return row['id'] as String;
    }
    return null;
  }

  @override
  Future<void> markOpened(String id) => _serial(() async {
    await library.checkAccess(id);
    final rows = await db.query('SELECT * FROM book_metadata WHERE book_id=?', [
      id,
    ]);
    final meta = rows.firstOrNull ?? _defaults(id);
    await db.transaction([
      _putMeta({
        ...meta,
        'last_opened': DateTime.now().millisecondsSinceEpoch,
        'state': meta['state'] == 'unread' ? 'reading' : meta['state'],
      }),
      SqlCommand(
        'UPDATE books SET row_revision=row_revision+1 WHERE id=? AND deleted=0',
        [id],
        1,
      ),
    ]);
  });
  Future<ContentFiles> _covers() async {
    final directory = Directory('$root/covers');
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const StorageFailure('unsafe_path');
    }
    await directory.create(recursive: true);
    return ContentFiles(directory.path);
  }

  Future<Uint8List?> _cover(String id) async {
    final ticket = _visibility;
    await _guard(id, ticket);
    final rows = await db.query(
      'SELECT cover_digest FROM book_metadata WHERE book_id=?',
      [id],
    );
    final digest = rows.firstOrNull?['cover_digest'] as String?;
    if (digest == null) return null;
    final bytes = Uint8List.fromList(await (await _covers()).read(digest));
    await _guard(id, ticket);
    return bytes;
  }

  @override
  Future<String> setCover(String id, int revision, Uint8List? bytes) =>
      _serial(() async {
        final ticket = _visibility;
        await _guard(id, ticket);
        String? digest;
        if (bytes != null) {
          digest = await (await _covers()).put(await normalizeCover(bytes));
        }
        await _guard(id, ticket);
        return _edit(
          {id: revision},
          const BookEdit(),
          setCover: true,
          coverDigest: digest,
        );
      });
  Future<File> _safe(String directory, String digest) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const StorageFailure('digest');
    }
    final parent = Directory('$root/$directory');
    if (await FileSystemEntity.type(parent.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const StorageFailure('unsafe_path');
    }
    await parent.create(recursive: true);
    final file = File('${parent.path}/$digest');
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const StorageFailure('unsafe_path');
    }
    return file;
  }

  Future<void> _reconcile(Map row) async {
    final digest = row['digest'] as String;
    final original = await _safe('objects', digest),
        retired = await _safe('recycle', digest);
    final source = row['intent'] == 'restore' ? retired : original,
        target = row['intent'] == 'restore' ? original : retired;
    if (await source.exists()) {
      if (await target.exists()) throw const StorageFailure('recycle_conflict');
      if ((await sha256.bind(source.openRead()).first).toString() != digest) {
        throw const StorageFailure('file_corrupt');
      }
      await source.rename(target.path);
    } else if (!await target.exists() ||
        (await sha256.bind(target.openRead()).first).toString() != digest) {
      throw const StorageFailure('file_missing');
    }
    if (row['intent'] == 'restore') {
      await db.transaction([
        SqlCommand('DELETE FROM file_recycle WHERE book_id=?', [
          row['book_id'],
        ]),
      ]);
    }
  }

  Future<void> initialize() async {
    for (final row in await db.query('SELECT * FROM file_recycle')) {
      try {
        await _reconcile(row);
      } catch (_) {
        /* Keep durable intent; explicit retry, never drop recovery metadata. */
      }
    }
  }

  @override
  Future<void> recycleFile(String id) => _serial(() async {
    final ticket = _visibility;
    await _guard(id, ticket);
    final revision = (await _row(id))['row_revision'];
    final rows = await db.query(
      'SELECT d.digest,i.mode FROM imports i JOIN documents d ON d.id=i.document_id WHERE d.book_id=?',
      [id],
    );
    if (rows.length != 1 || rows.single['mode'] != 'managed') {
      throw const StorageFailure('managed_only');
    }
    final digest = rows.single['digest'];
    final shared = await db.query(
      'SELECT DISTINCT book_id FROM documents WHERE digest=? AND book_id!=?',
      [digest, id],
    );
    if (shared.isNotEmpty) throw const StorageFailure('shared_object');
    await _guard(id, ticket);
    await db.transaction([
      SqlCommand(
        'UPDATE books SET row_revision=row_revision+1 WHERE id=? AND row_revision=?',
        [id, revision],
        1,
      ),
      SqlCommand(
        "INSERT INTO file_recycle VALUES(?,?,'recycle') ON CONFLICT(book_id) DO UPDATE SET intent='recycle'",
        [id, digest],
      ),
    ]);
    library.access?.invalidateProtected();
    await _reconcile({'book_id': id, 'digest': digest, 'intent': 'recycle'});
  });
  @override
  Future<void> restoreFile(String id) => _serial(() async {
    final ticket = _visibility;
    await _guard(id, ticket);
    final revision = (await _row(id))['row_revision'];
    await db.transaction([
      SqlCommand(
        'UPDATE books SET row_revision=row_revision+1 WHERE id=? AND row_revision=?',
        [id, revision],
        1,
      ),
      SqlCommand("UPDATE file_recycle SET intent='restore' WHERE book_id=?", [
        id,
      ], 1),
    ]);
    await _reconcile(
      (await db.query('SELECT * FROM file_recycle WHERE book_id=?', [
        id,
      ])).single,
    );
  });
  @override
  Future<String> checkFile(String id, JobContext job) => _serial(() async {
    final ticket = _visibility;
    await _guard(id, ticket);
    var health = 'available';
    try {
      await importer!.verify(id, job);
    } on ImportFailure catch (e) {
      health = e.issue.name;
    }
    job.checkCancelled();
    await _guard(id, ticket);
    final meta =
        (await db.query('SELECT * FROM book_metadata WHERE book_id=?', [
          id,
        ])).firstOrNull ??
        _defaults(id);
    await db.transaction([
      _putMeta({...meta, 'file_health': health}),
    ]);
    return health;
  });
}
