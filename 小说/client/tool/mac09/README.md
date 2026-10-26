# MAC-09检查入口

根目录`./tool/check.sh`执行固定SDK、格式、严格分析、Flutter/Dart及Python工具回归。新增测试覆盖有界分页完整性、UTF-16/emoji、精确重排、保存竞态、不同通道/修订、SQLite偏好与位置重启、损坏偏好、导航和隐私目录遮罩。

从小说/client运行：

```sh
../../tool/dartw run tool/mac09/export_schema.dart > ../../docs/storage/novel-schema-v8.sql
../../tool/flutterw build macos --debug --no-pub -t tool/mac09/renderer_probe.dart
../../tool/flutterw build macos --release --no-pub -t tool/mac09/probe_main.dart
```

renderer_probe只打开摘要固定的自产长篇asset，资料位于系统support下mac09-renderer-probe，点击“运行排版检查”保存results.json。它调用同一生产原生视图，核对三次重排的同一字符、该字符仍可见、翻页、恢复、Dart规范映射及外联隔离；不接受任意路径或脚本，不代替实际文件选择器。已有MAC-07探针继续验证跨行内/跨块选区、字体/图片等样本。

probe_main仅注入mac09-probe资料目录，业务源码与默认入口相同。用真实文件选择器导入fixtures/novel/mac09的普通自产TXT/EPUB；检查三布局、窄窗回退、字体/行距/段距/边距/行宽/主题、全局与单书偏好、专注/全屏、目录/进度跳转与返回、退出重启。不要在生产库代用户提交成年声明。

`generate_fixtures.py`可重建中性长篇TXT/EPUB及对应asset，来源和摘要记在fixture manifest中。测试仅用自产内容，不依赖外部书源。

结束后重建默认main.dart的Debug/Release，并用根目录`python3 tool/sign_macos_internal.py`校验内部ad-hoc Release。检查入口不作为正式产物交付。
