# MAC-06研究入口

本目录为第03步技术试验，不是第二个产品工程，不改变已确认D1主入口。默认lib/main.dart仍是MAC-02壳。

在仓库根重建样本与本地检查：

```sh
python3 小说/client/tool/mac06/epub_probe.py
python3 -m unittest discover -s 小说/client/tool/mac06 -p 'test_*.py'
python3 小说/client/tool/mac06/search_probe.py
python3 小说/client/tool/mac06/native_sqlite_probe.py
./tool/check.sh
```

运行真实Flutter/macOS渲染对比（在小说/client内）：

```sh
../../tool/flutterw run -d macos --debug -t tool/mac06/probe.dart
```

可切换受控WKWebView与epub_view3.3.0。后者只为已知自产样本锁定dev依赖，html0.15.6用于重现兼容试验，不作为生产不可信HTML解析选型。资源预算/净化研究由Python离线探针提供，正式Dart导入尚未实现。

WKWebView使用Runner内**仅Debug编译**的Mac06WebView.swift，经AppKitView和独立MethodChannel桥接。Debug沙盒的network.client为WebKit子进程工作所需；内容仍由无文件路径的白名单资源代理、非持久数据存储、CSP和导航规则隔离。Release未注册该平台视图，也未增加网络客户端权限，不能宣称Release阅读器已集成。

系统TTS研究源在packages/platform_services/experiments/macos/SpeechProbe.swift。运行 `python3 小说/client/tool/mac06/run_speech_probe.py` 编译并完成约十分钟静音播放/采样；不改系统音量、语音偏好、网络开关，不下载语音。探针进程被sandbox-exec禁止网络，但不能据此证明系统XPC语音进程也离线。Swift5模式会报告Sendable警告，正式MAC-12须完成Actor隔离与全量生命周期验收；不把研究类直接当生产SpeechService。

原始控制台/二进制/数据库保留在忽略的build/mac06目录；提交的JSON仅含自产fixture和脱敏测量。复现会覆盖本批研究JSON，历史验收应在相应Git提交查看。
