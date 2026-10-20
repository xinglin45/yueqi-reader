import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:reader_core/reader_core.dart';
import 'package:sqlite3/sqlite3.dart';

final class StorageFailure implements Exception {
  const StorageFailure(this.code);
  final String code;
  @override
  String toString() => 'StorageFailure($code)';
}

/// SQL is application-owned code, never source rules or imported book input.
final class SqlCommand {
  const SqlCommand(
    this.sql, [
    this.parameters = const [],
    this.expectedChanges,
  ]);
  final String sql;
  final List<Object?> parameters;
  final int? expectedChanges;
  Map<String, Object?> encode() => {
    'sql': sql,
    'parameters': parameters,
    'changes': expectedChanges,
  };
}

final class SchemaStep {
  const SchemaStep(this.version, this.statements);
  final int version;
  final List<String> statements;
  Map<String, Object> encode() => {
    'version': version,
    'statements': statements,
  };
}

/// One persistent isolate owns one connection. Requests are serialized there.
final class StorageDatabase {
  StorageDatabase._(this._isolate, this._port, this.info);
  final Isolate _isolate;
  final SendPort _port;
  final Map<String, Object?> info;
  bool _closed = false;
  bool get readOnly => info['read_only'] == true;

  static Future<StorageDatabase> open({
    required String directory,
    required ReaderProduct product,
    required List<SchemaStep> migrations,
  }) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_serve, <Object?>[
      ready.sendPort,
      directory,
      product.namespace,
      migrations.map((s) => s.encode()).toList(),
    ]);
    try {
      final response = (await ready.first.timeout(
        const Duration(seconds: 30),
      )) as Map<Object?, Object?>;
      if (response['error'] != null) {
        throw StorageFailure(response['error']! as String);
      }
      return StorageDatabase._(
        isolate,
        response['port']! as SendPort,
        (response['info']! as Map<Object?, Object?>).cast<String, Object?>(),
      );
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<Object?> _request(String operation, Object? payload) async {
    if (_closed) throw const StorageFailure('closed');
    final reply = ReceivePort();
    try {
      _port.send([reply.sendPort, operation, payload]);
      final value = (await reply.first.timeout(
        const Duration(seconds: 30),
      )) as Map<Object?, Object?>;
      if (value['error'] != null)
        throw StorageFailure(value['error']! as String);
      return value['value'];
    } finally {
      reply.close();
    }
  }

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await _request(
      'query',
      SqlCommand(sql, parameters).encode(),
    );
    return (result! as List<Object?>)
        .map((r) => (r! as Map<Object?, Object?>).cast<String, Object?>())
        .toList();
  }

  Future<void> transaction(List<SqlCommand> commands) async {
    await _request('write', commands.map((c) => c.encode()).toList());
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      await _request('close', null);
    } finally {
      _closed = true;
      _isolate.kill();
    }
  }
}

int _applicationId(String product) =>
    product == 'novel' ? 0x59514e56 : 0x5951434d;

void _serve(List<Object?> arguments) {
  final ready = arguments[0]! as SendPort;
  Database? db;
  RandomAccessFile? lease;
  try {
    final directory = Directory(arguments[1]! as String);
    final product = arguments[2]! as String;
    if (product != 'novel' && product != 'comic') {
      throw const StorageFailure('product');
    }
    final steps = (arguments[3]! as List<Object?>)
        .map((s) => (s! as Map<Object?, Object?>).cast<String, Object?>())
        .toList();
    if (steps.isEmpty ||
        List.generate(
          steps.length,
          (i) => steps[i]['version'] == i + 1,
        ).contains(false)) {
      throw const StorageFailure('migration_sequence');
    }
    directory.createSync(recursive: true);
    // Advisory lease across cooperating processes; SQLite locks remain authoritative.
    lease = File(p.join(directory.path, '$product.writer.lock'))
        .openSync(mode: FileMode.append);
    lease.lockSync(FileLock.exclusive);
    final file = p.join(directory.path, '$product.sqlite');
    db = sqlite3.open(file);
    db.execute('PRAGMA busy_timeout = 2500');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA synchronous = FULL');
    if (db.select('PRAGMA quick_check').single.values.single != 'ok') {
      throw const StorageFailure('corrupt');
    }
    final version = db.userVersion;
    final application = db.select('PRAGMA application_id').single.values.single;
    if ((version > 0 || application != 0) &&
        application != _applicationId(product)) {
      throw const StorageFailure('wrong_product');
    }
    if (version == 0 &&
        db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .isNotEmpty) {
      throw const StorageFailure('unrecognized_database');
    }
    String? recovery;
    String? backup;
    if (version > steps.length) {
      recovery = 'newer_schema';
    } else if (version < steps.length) {
      try {
        if (version > 0) {
          final backups = Directory(p.join(directory.path, 'migration-backups'))
            ..createSync();
          final backupTarget = p.join(
            backups.path,
            'v$version-${DateTime.now().microsecondsSinceEpoch}.sqlite',
          );
          final partialBackup = '$backupTarget.partial';
          db.execute('VACUUM INTO ?', [partialBackup]);
          final check = sqlite3.open(partialBackup, mode: OpenMode.readOnly);
          try {
            if (check.userVersion != version ||
                check.select('PRAGMA quick_check').single.values.single !=
                    'ok') {
              throw const StorageFailure('backup_verification');
            }
          } finally {
            check.close();
          }
          File(partialBackup).renameSync(backupTarget);
          backup = backupTarget;
        }
        db.execute('BEGIN EXCLUSIVE');
        try {
          for (final step in steps.skip(version)) {
            for (final sql
                in (step['statements']! as List<Object?>).cast<String>()) {
              db.execute(sql);
            }
            db.userVersion = step['version']! as int;
          }
          db.execute('PRAGMA application_id = ${_applicationId(product)}');
          if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
            throw const StorageFailure('foreign_key_check');
          }
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } catch (_) {
        recovery = 'migration_failed';
      }
    }
    if (recovery != null && version == 0) {
      throw const StorageFailure('initialization_failed');
    }
    if (recovery != null) {
      db.close();
      db = sqlite3.open(file, mode: OpenMode.readOnly);
      db.execute('PRAGMA query_only = ON');
    } else {
      db.execute('PRAGMA journal_mode = WAL');
    }
    final connection = db;
    final heldLease = lease;
    final input = ReceivePort();
    ready.send({
      'port': input.sendPort,
      'info': <String, Object?>{
        'version': connection.userVersion,
        'read_only': recovery != null,
        'recovery': recovery,
        'backup': backup == null ? null : p.basename(backup),
        'sqlite_version': sqlite3.version.toString(),
      },
    });
    input.listen((Object? message) {
      final args = message! as List<Object?>;
      final reply = args[0]! as SendPort;
      try {
        final op = args[1];
        if (op == 'close') {
          connection.close();
          heldLease.unlockSync();
          heldLease.closeSync();
          input.close();
          reply.send({'value': null});
          return;
        }
        if (op == 'query') {
          final command = (args[2]! as Map<Object?, Object?>);
          // All caller queries are read-only, including when schema recovery is active.
          connection.execute('PRAGMA query_only = ON');
          try {
            final rows = connection.select(
              command['sql']! as String,
              (command['parameters']! as List<Object?>),
            );
            reply.send({
              'value': rows.map((r) => Map<String, Object?>.from(r)).toList(),
            });
          } finally {
            if (recovery == null) connection.execute('PRAGMA query_only = OFF');
          }
        } else if (op == 'write') {
          if (recovery != null) throw const StorageFailure('read_only');
          connection.execute('BEGIN IMMEDIATE');
          try {
            for (final value in args[2]! as List<Object?>) {
              final c = value! as Map<Object?, Object?>;
              connection.execute(
                c['sql']! as String,
                c['parameters']! as List<Object?>,
              );
              if (c['changes'] != null &&
                  connection.updatedRows != c['changes']) {
                throw const StorageFailure('conflict');
              }
            }
            connection.execute('COMMIT');
          } catch (_) {
            connection.execute('ROLLBACK');
            rethrow;
          }
          reply.send({'value': null});
        } else {
          throw const StorageFailure('operation');
        }
      } catch (error) {
        reply.send({
          'error': error is StorageFailure ? error.code : 'database_operation',
        });
      }
    });
  } catch (error) {
    db?.close();
    if (lease != null) {
      try {
        lease.unlockSync();
      } catch (_) {}
      lease.closeSync();
    }
    ready.send({
      'error': error is StorageFailure ? error.code : 'database_open',
    });
  }
}
