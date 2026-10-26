import 'documents.dart';

enum ReadingLayout { scroll, paged, columns }

enum ReadingFont { song, sans, mono }

enum ReadingTheme { app, system, paper, dark, green }

/// Layout is ephemeral; durable location always uses DocumentAnchor v1.
final class ReadingPreferences {
  const ReadingPreferences({
    this.layout = ReadingLayout.scroll,
    this.font = ReadingFont.song,
    this.theme = ReadingTheme.app,
    this.size = 24,
    this.lineHeight = 1.9,
    this.paragraphSpacing = 18,
    this.margin = 24,
    this.width = 900,
  });
  final ReadingLayout layout;
  final ReadingFont font;
  final ReadingTheme theme;
  final double size, lineHeight, paragraphSpacing, margin, width;
  String get family => switch (font) {
    ReadingFont.song => 'Songti SC',
    ReadingFont.sans => 'PingFang SC',
    ReadingFont.mono => 'Menlo',
  };
  Map<String, Object> toJson() => {
    'version': 1,
    'layout': layout.name,
    'font': font.name,
    'theme': theme.name,
    'size': size,
    'line_height': lineHeight,
    'paragraph_spacing': paragraphSpacing,
    'margin': margin,
    'width': width,
  };
  factory ReadingPreferences.fromJson(Map<String, dynamic> json) {
    double bounded(String key, double min, double max) {
      final v = json[key];
      if (v is! num || !v.isFinite || v < min || v > max) {
        throw const FormatException('reader_preference');
      }
      return v.toDouble();
    }

    if (json['version'] != 1) {
      throw const FormatException('reader_preference_version');
    }
    return ReadingPreferences(
      layout: ReadingLayout.values.byName(json['layout'] as String),
      font: ReadingFont.values.byName(json['font'] as String),
      theme: ReadingTheme.values.byName(json['theme'] as String),
      size: bounded('size', 16, 36),
      lineHeight: bounded('line_height', 1.2, 2.4),
      paragraphSpacing: bounded('paragraph_spacing', 0, 40),
      margin: bounded('margin', 8, 64),
      width: bounded('width', 360, 1400),
    );
  }
  ReadingPreferences copyWith({
    ReadingLayout? layout,
    ReadingFont? font,
    ReadingTheme? theme,
    double? size,
    double? lineHeight,
    double? paragraphSpacing,
    double? margin,
    double? width,
  }) => ReadingPreferences(
    layout: layout ?? this.layout,
    font: font ?? this.font,
    theme: theme ?? this.theme,
    size: size ?? this.size,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    margin: margin ?? this.margin,
    width: width ?? this.width,
  );
}

abstract interface class ReadingPreferenceRepository {
  Future<ReadingPreferences?> loadReadingPreferences(String? bookId);
  Future<void> saveReadingPreferences(
    String? bookId,
    ReadingPreferences? value,
  );
}

final class ReadingIdentity {
  const ReadingIdentity(this.bookId, this.revision, this.kind);
  final String bookId, revision;
  final DocumentKind kind;
  bool admits(DocumentAnchor anchor) =>
      anchor.revision == revision && anchor.kind == kind;
}
