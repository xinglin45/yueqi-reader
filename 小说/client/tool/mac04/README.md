# MAC-04可重复检查

所有命令从项目根目录运行，使用固定SDK。样本是自产中性文字和生成ZIP，不访问公网、不下载书源、不包含成人正文或外部素材。

```sh
python3 小说/client/tool/mac04/generate_fixtures.py
./tool/check.sh
cd 小说/client
../../tool/dartw run tool/mac04/export_schema.dart
```

export_schema只创建临时空库、导出当前DDL后清理。固定快照位于docs/storage/novel-schema-v5.sql。fixtures/novel/mac04/manifest.json记录字节数/摘要，生成器使用固定ZIP时间；超限压缩样本只占少量压缩空间。

macOS中文编码检查直接编译生产NativeTextCodec，同一系统CoreFoundation逻辑：

```sh
mkdir -p 小说/client/build/mac04
swiftc 小说/client/macos/Runner/NativeTextCodec.swift 小说/client/tool/mac04/native_codec_probe.swift -o 小说/client/build/mac04/native-codec-probe
小说/client/build/mac04/native-codec-probe fixtures/novel/mac04
```

原生界面隔离入口（在小说/client内）：

```sh
../../tool/flutterw build macos --debug -t tool/mac04/probe_main.dart
```

它使用同一NovelApp和平台文件桥接，仅将书库和设备状态存放位置注入系统资料目录下mac04-probe，不触碰生产书架或成年声明。右上角有“MAC-04 隔离检查”标记。只通过系统文件选择/拖放选择自产fixture；不会自动确认成年声明。安全范围书签UUID仍由相同原生适配保存在设备grants目录，属于本机测试产物，不提交仓库。结束后必须重新以默认main.dart构建Debug/Release，避免把检查入口当作交付入口。

实现、实测/替身覆盖区别和限制见docs/verifications/mac-04-2026-10-21.md。此工具不代表TXT/EPUB完整阅读引擎已经集成。
