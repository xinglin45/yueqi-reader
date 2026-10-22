# MAC-05检查与实测

只用自产中性样本，所有大样本在忽略的build或系统临时目录动态生成；不依赖公网、成人正文、登录或后端。SDK由项目包装命令固定。

从项目根目录运行`./tool/check.sh`；它检查客户端/共享包、64项Flutter/Dart测试与13项Python工具测试。TXT新增测试含逐字节Unicode/源偏移、旧编码、schema5→6、版本/回滚/故障/取消/并行阅读与实际界面组件。

在小说/client目录导出当前空库DDL：

```sh
../../tool/dartw run tool/mac05/export_schema.dart
```

它只创建临时空库并清理，不读取用户书库。当前快照为docs/storage/novel-schema-v6.sql；旧DDL和工具仅作历史范围对照，当前导出使用mac05入口。

独立Dart AOT解析器与系统旧编码探针（在小说/client目录）：

```sh
mkdir -p build/mac05
../../tool/dartw compile exe tool/mac05/benchmark.dart -o build/mac05/benchmark
build/mac05/benchmark build/mac05/benchmark-data
../../tool/dartw compile exe tool/mac05/codec_probe.dart -o build/mac05/codec-probe
build/mac05/codec-probe ../../fixtures/novel/mac04
```

benchmark生成10 MiB/50 MiB UTF-8简繁/emoji/组合字符样本，计时包含isolate启动、全文件解码/分章/摘要与索引落盘，排除输入生成、导入复制、数据库提交和Flutter排版。输入只有LF，规范化全文摘要必须等于源摘要以核对无丢字。maxRss为同一独立AOT进程的累计峰值，不能算成Flutter应用内存/Release首屏成绩；运行时避免与其他构建/测试并发。小样CRLF、UTF16、复杂边界和取消由自动测试补充。

原生UI隔离入口：

```sh
../../tool/flutterw build macos --debug --no-pub -t tool/mac05/probe_main.dart
```

仅注入系统资料目录下mac05-probe，使用相同业务/原生文件桥接；右上角显示“MAC-05 隔离检查”。通过系统面板选择fixtures/novel/mac05/章节-utf8.txt，可用普通＋引用检查分章、重复标题、目录、实际正文、手动位置和重启授权。不会自动确认成年声明；不改生产书架。结束后以默认main.dart重新构建Debug/Release，避免交付探针入口。

验收、限额和未实现项见docs/verifications/mac-05-2026-10-22.md与ADR-0009。字节检查点续传、完整排版/自动进度不在本步。
