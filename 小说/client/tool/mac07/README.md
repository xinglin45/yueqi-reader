# MAC-07 EPUB检查工具

从根目录执行`./tool/check.sh`验证固定SDK、严格分析、Flutter/Dart与Python测试。样本只用项目自产中性文本/几何图，现有MAC-06字体附MIT许可。不会代用户在生产库确认成年声明或添加书籍。

在小说/client目录使用独立AOT加载探针：

```sh
mkdir -p build/mac07
../../tool/dartw compile exe tool/mac07/loader_probe.dart -o build/mac07/loader-probe
build/mac07/loader-probe ../../fixtures/novel/mac07/流式EPUB3.epub
build/mac07/loader-probe ../../fixtures/novel/mac06/mountain-letter.epub
```

计时只覆盖解析/资源净化/临时落盘，不含导入复制、SQL或Flutter/WebKit布局；maxRss是独立进程峰值，不能作为完整App内存。与构建/测试错开运行。工具自行清理临时目录。

两种原生检查入口均使用真实生产解析器、资源端口与MacEpubSurface：

```sh
../../tool/flutterw build macos --debug --no-pub -t tool/mac07/renderer_probe.dart
../../tool/flutterw build macos --debug --no-pub -t tool/mac07/probe_main.dart
```

renderer_probe仅加载摘要白名单匹配的既有自产MAC-06资产，输入文件端口为仅此资产的替身，不代表原生授权验收。可以真实鼠标选字，再点“保存引擎检查”；固定检查包括page/隔离world、原文/跨元素与跨段/ruby映射、图片/字体、外联/跨书/未知资源拒绝和三种布局恢复。JSON只输出该已知自产内容，写在系统资料目录mac07-renderer-probe/results；没有任意文件输入或生产日志。原生失败只报告有限阶段/数字错误码。

probe_main仅注入mac07-probe资料目录，显示“MAC-07 隔离检查”，其余与默认App相同。通过真实NSOpenPanel选择fixtures/novel/mac07/流式EPUB3.epub，以普通＋引用检查书架→正文→目录→图片查看→保存选区→重启授权/位置。Release也用该入口验证沙盒/WK运行；结束后必须用默认main.dart重建Debug/Release，避免交付检查入口。

重建小样：从根目录`python3 小说/client/tool/mac07/generate_fixtures.py`，只使用既有Pillow产生自产几何JPEG；不需要为测试下载书籍/规则。验收与边界见docs/verifications/mac-07-2026-10-22.md及ADR-0010。
