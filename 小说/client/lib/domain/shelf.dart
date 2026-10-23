import 'dart:typed_data';

import 'library.dart';
import 'jobs.dart';

enum ShelfScope { normal, adult }

enum ReadingState { unread, reading, finished }

enum ShelfSort { manual, title, author, recent, added }

final class ShelfOptions {
  const ShelfOptions({
    this.grid = true,
    this.state = '',
    this.sort = ShelfSort.added,
    this.format = '',
    this.group = '',
    this.favorite = false,
    this.removed = false,
    this.search = '',
  });
  final bool grid, favorite, removed;
  final String state, format, group, search;
  final ShelfSort sort;
  Map<String, Object> toJson() => {
    'grid': grid,
    'favorite': favorite,
    'removed': removed,
    'state': state,
    'format': format,
    'group': group,
    'search': search,
    'sort': sort.name,
  };
  factory ShelfOptions.fromJson(Map<String, dynamic> v) => ShelfOptions(
    grid: v['grid'] != false,
    favorite: v['favorite'] == true,
    removed: v['removed'] == true,
    state: ReadingState.values.any((s) => s.name == v['state'])
        ? v['state'] as String
        : '',
    format: const ['txt', 'epub'].contains(v['format'])
        ? v['format'] as String
        : '',
    group: v['group'] as String? ?? '',
    search: v['search'] as String? ?? '',
    sort:
        ShelfSort.values.where((s) => s.name == v['sort']).firstOrNull ??
        ShelfSort.added,
  );
  ShelfOptions change({
    bool? grid,
    bool? favorite,
    bool? removed,
    String? state,
    String? format,
    String? group,
    String? search,
    ShelfSort? sort,
  }) => ShelfOptions(
    grid: grid ?? this.grid,
    favorite: favorite ?? this.favorite,
    removed: removed ?? this.removed,
    state: state ?? this.state,
    format: format ?? this.format,
    group: group ?? this.group,
    search: search ?? this.search,
    sort: sort ?? this.sort,
  );
}

final class ShelfGroup {
  const ShelfGroup(this.id, this.label, this.kind, {this.removed = false});
  final bool removed;
  final String id, label, kind;
}

final class ShelfBook {
  const ShelfBook({
    required this.book,
    required this.revision,
    required this.author,
    required this.synopsis,
    required this.language,
    required this.state,
    required this.favorite,
    required this.order,
    required this.lastOpened,
    required this.removed,
    required this.format,
    required this.mode,
    required this.health,
    required this.bytes,
    required this.groups,
    required this.cover,
    required this.recycled,
    required this.similarTitles,
    this.sourceName = '',
  });
  final BookSummary book;
  final int revision, order, lastOpened, bytes, similarTitles;
  final String author, synopsis, language, format, mode, health;
  final String sourceName;
  final ReadingState state;
  final bool favorite, removed, cover, recycled;
  final List<String> groups;
}

final class ShelfPage {
  const ShelfPage(this.books, this.total, this.groups);
  final List<ShelfBook> books;
  final int total;
  final List<ShelfGroup> groups;
}

final class BookEdit {
  const BookEdit({
    this.title,
    this.author,
    this.synopsis,
    this.language,
    this.state,
    this.favorite,
    this.order,
    this.removed,
    this.groups,
    this.clearRecords = false,
  });
  final String? title, author, synopsis, language;
  final ReadingState? state;
  final bool? favorite, removed;
  final int? order;
  final List<String>? groups;
  final bool clearRecords;
}

abstract interface class ShelfRepository {
  Future<ShelfOptions> preferences(ShelfScope scope, {bool recent = false});
  Future<void> savePreferences(
    ShelfScope scope,
    ShelfOptions options, {
    bool recent = false,
  });
  Future<ShelfPage> list(
    ShelfScope scope,
    ShelfOptions options,
    JobContext job, {
    int page = 0,
    bool recent = false,
  });
  Future<String> edit(Map<String, int> revisions, BookEdit edit);
  Future<void> undo(String action);
  Future<String> createGroup(ShelfScope scope, String label, String kind);
  Future<void> renameGroup(ShelfScope scope, String id, String label);
  Future<void> removeGroup(ShelfScope scope, String id, {bool removed = true});
  Future<String?> latestAction(ShelfScope scope);
  Future<void> markOpened(String bookId);
  Future<Uint8List?> cover(String bookId);
  Future<String> setCover(String bookId, int revision, Uint8List? bytes);
  Future<void> recycleFile(String bookId);
  Future<void> restoreFile(String bookId);
  Future<String> checkFile(String bookId, JobContext job);
}
