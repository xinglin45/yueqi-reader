import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/documents.dart';
import '../../domain/epub.dart';
import '../../domain/jobs.dart';

final class MacEpubController {
  MacEpubController(this.channel);
  final MethodChannel channel;
  bool _closed = false;
  Future<Object?> capture() => _invoke('capture');
  Future<Object?> checks() => _invoke('checks');
  Future<Object?> layout(double size, bool dark) =>
      _invoke('layout', {'size': size, 'dark': dark});
  Future<Object?> restore(DocumentAnchor anchor) =>
      _invoke('restore', {'anchor': anchor.toJson()});
  Future<Object?> _invoke(String method, [Object? args]) async {
    if (_closed) throw const EpubFailure(EpubIssue.expired);
    final value = await channel
        .invokeMethod<Object?>(method, args)
        .timeout(const Duration(seconds: 10));
    if (_closed) throw const EpubFailure(EpubIssue.expired);
    return value;
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      await channel
          .invokeMethod<void>('dispose')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    channel.setMethodCallHandler(null);
  }
}

/// Platform-specific presentation; the EPUB reader domain sees no AppKit or JS.
class MacEpubSurface extends StatefulWidget {
  const MacEpubSurface({
    super.key,
    required this.reader,
    required this.chapter,
    required this.size,
    required this.dark,
    required this.onCreated,
    required this.onReady,
    required this.onNavigate,
    required this.onError,
    this.anchor,
    this.fragment = '',
  });
  final EpubDocumentReader reader;
  final EpubChapter chapter;
  final double size;
  final bool dark;
  final DocumentAnchor? anchor;
  final String fragment;
  final ValueChanged<MacEpubController> onCreated;
  final VoidCallback onReady;
  final void Function(String, String) onNavigate;
  final ValueChanged<String> onError;
  @override
  State<MacEpubSurface> createState() => _MacEpubSurfaceState();
}

class _MacEpubSurfaceState extends State<MacEpubSurface> {
  MacEpubController? controller;
  Timer? timeout;
  bool ready = false;
  @override
  void dispose() {
    timeout?.cancel();
    unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MacEpubSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ready &&
        (oldWidget.size != widget.size || oldWidget.dark != widget.dark)) {
      _layout();
    }
  }

  Future<void> _layout() async {
    try {
      final result = await controller!.layout(widget.size, widget.dark);
      if (!mounted) return;
      epubSelection(widget.chapter, result);
    } catch (_) {
      if (mounted) widget.onError('layout');
    }
  }

  Future<void> _created(int id) async {
    final channel = MethodChannel('reader/epub/$id'),
        current = MacEpubController(MethodChannel('reader/epub/$id'));
    controller = current;
    channel.setMethodCallHandler((call) async {
      if (!mounted) throw PlatformException(code: 'disposed');
      final args = call.arguments;
      if (call.method == 'resource') {
        if (args is! Map ||
            args['session'] != widget.chapter.session.id ||
            args['id'] is! String) {
          throw PlatformException(code: 'invalid_resource');
        }
        final resource = await widget.reader.resource(
          widget.chapter.session,
          args['id'] as String,
          JobContext(id: 0, isCurrent: () => mounted, report: (_) {}),
        );
        if (!mounted) throw PlatformException(code: 'disposed');
        return {'mime': resource.mime, 'bytes': resource.bytes};
      }
      if (call.method == 'ready') {
        if (args is! Map ||
            args['session'] != widget.chapter.session.id ||
            args['resource'] != widget.chapter.spine.resource ||
            args['blocks'] is! Map ||
            !mapEquals(
              Map<String, String>.from(args['blocks'] as Map),
              widget.chapter.blocks,
            )) {
          widget.onError('mapping');
          unawaited(current.dispose());
          return null;
        }
        timeout?.cancel();
        ready = true;
        widget.onReady();
        if (mounted) await _layout();
      } else if (call.method == 'navigate') {
        if (args is Map &&
            args['session'] == widget.chapter.session.id &&
            args['resource'] is String &&
            args['fragment'] is String) {
          widget.onNavigate(
            args['resource'] as String,
            args['fragment'] as String,
          );
        }
      } else if (call.method == 'error') {
        timeout?.cancel();
        final kind = args is Map ? args['kind'] : null;
        widget.onError(
          const {
                'invalid_session',
                'resource_policy',
                'load_failed',
                'text_mapping',
                'process_terminated',
              }.contains(kind)
              ? '$kind${args is Map && args['code'] is int ? ':${args['code']}' : ''}'
              : 'native',
        );
      }
      return null;
    });
    if (!mounted) {
      await current.dispose();
      return;
    }
    widget.onCreated(current);
    timeout = Timer(const Duration(seconds: 25), () {
      if (mounted && !ready) widget.onError('timeout');
    });
    try {
      await channel.invokeMethod<void>('start');
    } catch (_) {
      if (mounted) widget.onError('start');
    }
  }

  @override
  Widget build(BuildContext context) => AppKitView(
    viewType: 'local.yueqi.epub',
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: _created,
    creationParams: {
      'session': widget.chapter.session.id,
      'resource': widget.chapter.spine.resource,
      'spines': widget.chapter.session.spine.map((s) => s.resource).toList(),
      'fragment': widget.fragment,
      'anchor': widget.anchor?.toJson(),
      'size': widget.size,
      'dark': widget.dark,
    },
  );
}
