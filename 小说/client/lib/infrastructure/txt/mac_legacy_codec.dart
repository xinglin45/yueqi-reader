import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _CFRange extends Struct {
  @IntPtr()
  external int location;
  @IntPtr()
  external int length;
}

/// Same CoreFoundation codec as NativeTextCodec, applied to bounded chunks in
/// the parser isolate. ABI follows the installed SDK's CFString.h/CFBase.h.
final class MacLegacyCodec {
  static Uint8List convert(Uint8List bytes, String from, String to) {
    if (!Platform.isMacOS) throw const FormatException('legacy_platform');
    final lib = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
    );
    final cstring = lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
          Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)
        >('CFStringCreateWithCString');
    final charset = lib
        .lookupFunction<
          Uint32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CFStringConvertIANACharSetNameToEncoding');
    final create = lib
        .lookupFunction<
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Uint8>,
            IntPtr,
            Uint32,
            Uint8,
          ),
          Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int)
        >('CFStringCreateWithBytes');
    final length = lib
        .lookupFunction<
          IntPtr Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CFStringGetLength');
    final get = lib
        .lookupFunction<
          IntPtr Function(
            Pointer<Void>,
            _CFRange,
            Uint32,
            Uint8,
            Uint8,
            Pointer<Uint8>,
            IntPtr,
            Pointer<IntPtr>,
          ),
          int Function(
            Pointer<Void>,
            _CFRange,
            int,
            int,
            int,
            Pointer<Uint8>,
            int,
            Pointer<IntPtr>,
          )
        >('CFStringGetBytes');
    final release = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CFRelease');
    int encoding(String name) {
      final c = name.toNativeUtf8();
      final string = cstring(nullptr, c, 0x08000100);
      malloc.free(c);
      if (string == nullptr) throw const FormatException('charset');
      try {
        final result = charset(string);
        if (result == 0xffffffff) throw const FormatException('charset');
        return result;
      } finally {
        release(string);
      }
    }

    final input = malloc<Uint8>(bytes.length),
        output = malloc<Uint8>(bytes.length * 4 + 32),
        used = calloc<IntPtr>(),
        range = calloc<_CFRange>();
    Pointer<Void> string = nullptr;
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      string = create(nullptr, input, bytes.length, encoding(from), 0);
      if (string == nullptr) throw const FormatException('legacy_encoding');
      final units = length(string);
      range.ref.length = units;
      final converted = get(
        string,
        range.ref,
        encoding(to),
        0,
        0,
        output,
        bytes.length * 4 + 32,
        used,
      );
      if (converted != units) throw const FormatException('legacy_encoding');
      return Uint8List.fromList(output.asTypedList(used.value));
    } finally {
      if (string != nullptr) release(string);
      malloc.free(input);
      malloc.free(output);
      calloc.free(used);
      calloc.free(range);
    }
  }
}
