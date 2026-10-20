import 'package:flutter/material.dart';

import '../domain/documents.dart';
import '../domain/library.dart';

/// Explicit paragraph checkpoints for the owned sample. Full tracking is MAC-09.
class PreviewParagraphs extends StatefulWidget {
  const PreviewParagraphs({
    super.key,
    required this.preview,
    this.positions,
    this.readOnly = false,
  });
  final ReadingPreview preview;
  final PositionRepository? positions;
  final bool readOnly;
  @override
  State<PreviewParagraphs> createState() => _PreviewParagraphsState();
}

class _PreviewParagraphsState extends State<PreviewParagraphs> {
  late int _sequence;
  String? _selected, _message;
  bool _saving = false;
  late final List<GlobalKey> _paragraphs;
  @override
  void initState() {
    super.initState();
    _sequence = widget.preview.positionSequence;
    _selected = widget.preview.restoredBlockId;
    _paragraphs = List.generate(
      widget.preview.paragraphs.length,
      (_) => GlobalKey(),
    );
    final index = widget.preview.blockIds.indexOf(_selected ?? '');
    if (index >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final context = _paragraphs[index].currentContext;
          if (context != null) {
            Scrollable.ensureVisible(context, alignment: 0.15);
          }
        }
      });
    }
  }

  Future<void> _save(int index) async {
    if (_saving) return;
    final preview = widget.preview;
    setState(() => _saving = true);
    try {
      final anchor = DocumentAnchor.capture(
        kind: DocumentKind.txt,
        revision: preview.documentRevision!,
        chapterId: preview.chapterId!,
        spineHref: preview.spineHref!,
        blockId: preview.blockIds[index],
        text: preview.paragraphs[index],
        start: 0,
        end: 0,
      );
      final saved = await widget.positions!.savePosition(
        preview.book.id,
        PositionChannel.reading,
        anchor,
        expectedSequence: _sequence,
      );
      if (mounted) {
        setState(() {
          _sequence = saved.sequence;
          _selected = anchor.blockId;
          _message = '已记住第${index + 1}段，下次打开可继续。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = '未能保存位置，原记录仍保留。请重新打开后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.preview.positionNeedsReview)
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text('原位置暂时无法精确恢复，已回到章节开头。旧位置仍保留。'),
        ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(_message!, semanticsLabel: _message),
        ),
      for (final (index, paragraph) in widget.preview.paragraphs.indexed)
        Padding(
          key: _paragraphs[index],
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.preview.blockIds.isNotEmpty &&
                  _selected == widget.preview.blockIds[index])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '上次记住 · 第${index + 1}段',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                ),
              SelectableText(
                paragraph,
                style: const TextStyle(
                  fontFamily: 'Songti SC',
                  fontFamilyFallback: ['STSong', 'serif'],
                  fontSize: 24,
                  height: 1.9,
                ),
              ),
              if (widget.positions != null &&
                  widget.preview.documentRevision != null)
                TextButton(
                  key: ValueKey('remember-paragraph-$index'),
                  onPressed: _saving || widget.readOnly
                      ? null
                      : () => _save(index),
                  child: const Text('记住这一段'),
                ),
            ],
          ),
        ),
    ],
  );
}
