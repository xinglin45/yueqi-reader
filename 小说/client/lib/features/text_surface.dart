import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../domain/documents.dart';
import '../domain/reading.dart';
import '../domain/txt.dart';
import 'reading_controls.dart';

final class TextSlice {
  const TextSlice(this.block, this.start, this.end, this.height);
  final TxtBlock block;
  final int start, end;
  final double height;
}

/// At most the eight decoded blocks of TxtPage are measured, never a book.
List<List<TextSlice>> paginateText(
  TxtPage page,
  TextStyle style,
  double width,
  double height,
  TextScaler scaler,
  double spacing,
) {
  final result = <List<TextSlice>>[[]];
  var used = 0.0;
  for (final block in page.blocks) {
    final painter = TextPainter(
      text: TextSpan(text: block.text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: width);
    var start = 0;
    for (final line in painter.computeLineMetrics()) {
      var end = painter
          .getLineBoundary(
            painter.getPositionForOffset(Offset(0, line.baseline)),
          )
          .end;
      if (end < block.text.length && block.text.codeUnitAt(end) == 10) end++;
      if (end <= start) continue;
      if (!utf16Boundary(block.text, end)) end++;
      if (used + line.height > height && result.last.isNotEmpty) {
        result.add([]);
        used = 0;
      }
      final slices = result.last;
      if (slices.isNotEmpty && slices.last.block == block) {
        final old = slices.removeLast();
        slices.add(TextSlice(block, old.start, end, old.height + line.height));
      } else {
        slices.add(TextSlice(block, start, end, line.height));
      }
      used += line.height;
      start = end;
    }
    if (start < block.text.length) {
      result.last.add(
        TextSlice(
          block,
          start,
          block.text.length,
          style.fontSize! * style.height!,
        ),
      );
    }
    painter.dispose();
    used += spacing;
  }
  return result;
}

class TextReadingSurface extends StatefulWidget {
  const TextReadingSurface({
    super.key,
    required this.page,
    required this.preferences,
    required this.onAnchor,
    required this.onPrevious,
    required this.onNext,
    this.anchor,
  });
  final TxtPage page;
  final ReadingPreferences preferences;
  final DocumentAnchor? anchor;
  final ValueChanged<DocumentAnchor> onAnchor;
  final VoidCallback? onPrevious, onNext;
  @override
  State<TextReadingSurface> createState() => _TextReadingSurfaceState();
}

class _TextReadingSurfaceState extends State<TextReadingSurface> {
  final scroll = ScrollController();
  final viewport = GlobalKey();
  final keys = <String, GlobalKey>{};
  DocumentAnchor? current;
  List<List<TextSlice>> pages = [];
  int page = 0;
  Object? layoutKey;
  bool restoring = false;
  int layoutGeneration = 0;
  DocumentAnchor anchor(TxtBlock block, int offset) => DocumentAnchor.capture(
    kind: DocumentKind.txt,
    revision: widget.page.index.id,
    chapterId: widget.page.chapter.id,
    spineHref: 'text.txt',
    blockId: block.id,
    text: block.text,
    start: offset,
    end: offset,
  );
  @override
  void initState() {
    super.initState();
    current = widget.anchor;
    scroll.addListener(_observe);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TextReadingSurface old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page || old.anchor != widget.anchor) {
      current = widget.anchor;
      final ids = widget.page.blocks.map((b) => b.id).toSet();
      keys.removeWhere((id, _) => !ids.contains(id));
      layoutKey = null;
    }
  }

  RenderParagraph? _paragraph(String? id) {
    RenderParagraph? result;
    void find(RenderObject node) {
      if (result != null) return;
      if (node is RenderParagraph) {
        result = node;
        return;
      }
      node.visitChildren(find);
    }

    final node = keys[id]?.currentContext?.findRenderObject();
    if (node != null) find(node);
    return result;
  }

  void _observe() {
    if (restoring ||
        !mounted ||
        widget.preferences.layout != ReadingLayout.scroll) {
      return;
    }
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final top = box.localToGlobal(Offset.zero);
    for (final b in widget.page.blocks) {
      final render = _paragraph(b.id);
      if (render is! RenderParagraph || !render.attached) continue;
      final rect = render.localToGlobal(Offset.zero) & render.size;
      if (rect.bottom <= top.dy) continue;
      var at = render
          .getPositionForOffset(
            render.globalToLocal(
              Offset(rect.left, (top.dy + 1).clamp(rect.top, rect.bottom)),
            ),
          )
          .offset
          .clamp(0, b.text.length);
      if (!utf16Boundary(b.text, at)) at--;
      current = anchor(b, at);
      widget.onAnchor(current!);
      return;
    }
  }

  void _restore() {
    if (!mounted) return;
    if (widget.preferences.layout == ReadingLayout.scroll) {
      final a = current;
      final render = _paragraph(a?.blockId);
      final box = viewport.currentContext?.findRenderObject() as RenderBox?;
      if (render is RenderParagraph &&
          box != null &&
          scroll.hasClients &&
          a != null) {
        final caret = render.getOffsetForCaret(
          TextPosition(offset: a.start),
          Rect.zero,
        );
        final dy =
            render.localToGlobal(caret).dy - box.localToGlobal(Offset.zero).dy;
        restoring = true;
        scroll.jumpTo(
          (scroll.offset + dy).clamp(0, scroll.position.maxScrollExtent),
        );
        restoring = false;
      }
      restoring = false;
      if (a != null) {
        widget.onAnchor(a);
      } else {
        _observe();
      }
    } else {
      restoring = false;
      if (current != null) {
        widget.onAnchor(current!);
      } else {
        _reportPage();
      }
    }
  }

  void _reportPage() {
    if (pages.isEmpty || pages[page].isEmpty) return;
    final first = pages[page].first;
    current = anchor(first.block, first.start);
    widget.onAnchor(current!);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final p = widget.preferences,
          colors = readingColors(
            p,
            (p.theme == ReadingTheme.system
                    ? MediaQuery.platformBrightnessOf(context)
                    : Theme.of(context).brightness) ==
                Brightness.dark,
          );
      final columns = p.layout == ReadingLayout.columns && c.maxWidth >= 720
          ? 2
          : 1;
      final innerWidth =
          (c.maxWidth.clamp(0, p.width) -
                  p.margin * 2 -
                  (columns == 2 ? 32 : 0))
              .clamp(80, double.infinity) /
          columns;
      final height = (c.maxHeight - p.margin * 2 - 48).clamp(
        80,
        double.infinity,
      );
      final style = TextStyle(
        fontFamily: p.family,
        fontFamilyFallback: const ['STSong', 'serif'],
        fontSize: p.size,
        height: p.lineHeight,
        color: colors.$2,
      );
      final nextKey = (
        widget.page,
        p,
        c.maxWidth,
        c.maxHeight,
        MediaQuery.textScalerOf(context),
      );
      if (nextKey != layoutKey) {
        layoutKey = nextKey;
        if (p.layout != ReadingLayout.scroll) {
          pages = paginateText(
            widget.page,
            style,
            innerWidth,
            height.toDouble(),
            MediaQuery.textScalerOf(context),
            p.paragraphSpacing,
          );
          final at = current;
          page = 0;
          if (at != null) {
            final found = pages.indexWhere(
              (s) => s.any(
                (f) =>
                    f.block.id == at.blockId &&
                    f.start <= at.start &&
                    (at.start < f.end || at.start == f.block.text.length),
              ),
            );
            if (found >= 0) page = (found ~/ columns) * columns;
          }
        }
        restoring = true;
        final ticket = ++layoutGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ticket == layoutGeneration) _restore();
        });
      }
      return ColoredBox(
        color: colors.$1,
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: p.width),
                  child: Padding(
                    padding: EdgeInsets.all(p.margin),
                    child: p.layout == ReadingLayout.scroll
                        ? SizedBox.expand(
                            key: viewport,
                            child: NotificationListener<ScrollEndNotification>(
                              onNotification: (_) {
                                _observe();
                                return false;
                              },
                              child: SingleChildScrollView(
                                controller: scroll,
                                child: SelectionArea(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final b in widget.page.blocks)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: p.paragraphSpacing,
                                          ),
                                          child: Text(
                                            b.text,
                                            key: keys.putIfAbsent(
                                              b.id,
                                              () => GlobalKey(),
                                            ),
                                            textScaler: MediaQuery.textScalerOf(
                                              context,
                                            ),
                                            style: style,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var col = 0; col < columns; col++) ...[
                                if (col > 0) const SizedBox(width: 32),
                                Expanded(
                                  child: ClipRect(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (page + col < pages.length)
                                          for (final slice in pages[page + col])
                                            Padding(
                                              padding: EdgeInsets.only(
                                                bottom:
                                                    slice ==
                                                        pages[page + col].last
                                                    ? 0
                                                    : p.paragraphSpacing,
                                              ),
                                              child: Text(
                                                slice.block.text.substring(
                                                  slice.start,
                                                  slice.end,
                                                ),
                                                style: style,
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: page > 0 && p.layout != ReadingLayout.scroll
                      ? () {
                          setState(
                            () => page = (page - columns).clamp(
                              0,
                              pages.length - 1,
                            ),
                          );
                          _reportPage();
                        }
                      : widget.onPrevious,
                  child: const Text('上一页'),
                ),
                Flexible(
                  child: Text(
                    p.layout == ReadingLayout.scroll
                        ? '滚动 · 约${((widget.page.blocks.first.ordinal + 1) / widget.page.index.blocks * 100).round()}%'
                        : '当前内容 ${page + 1} / ${pages.length}${columns == 2 ? ' · 双栏' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed:
                      p.layout != ReadingLayout.scroll &&
                          page + columns < pages.length
                      ? () {
                          setState(() => page += columns);
                          _reportPage();
                        }
                      : widget.onNext,
                  child: const Text('下一页'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
