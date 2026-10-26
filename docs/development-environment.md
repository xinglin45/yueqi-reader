# 开发环境与依赖核验

2026-10-26更新：**MAC-09阅读器、排版与位置恢复已完成，代码、自动化及原生验收通过；下一主任务为第11步MAC-10：中文全文搜索**。TXT/EPUB已接入共享会话、滚动/分页/双栏、可调排版、自动进度与历史返回；102项Flutter/Dart及13项Python测试通过，见[MAC-09验收](verifications/mac-09-2026-10-26.md)。完整首版来源仍0/0，MAC-10及原生低存在感窗口尚未开始。

最新核验：2026-10-26，MAC-01/02、MAC-06研究、MAC-03存储与MAC-16分级隐私及MAC-04文件导入及MAC-05 TXT与MAC-07 EPUB与MAC-08书架管理已完成。以下当前结果优先于文末2026-10-15只读历史；完整证据见[基础工程验收](verifications/mac-01-2026-10-16.md)。

## 当前实际基线

| 项目 | 已验证结果 |
|---|---|
| 系统/机器 | macOS27.0.1 build26A434、arm64、64GiB内存 |
| Xcode/SDK | Xcode27.1 build27A9275、macOS SDK27.0、Swift6.4；首次运行组件检查退出0 |
| Flutter/Dart | 官方Git稳定标签3.47.7、Dart3.13.5；提交/engine固定在[tool/flutter-sdk.json](../tool/flutter-sdk.json) |
| 调用方式 | 项目tool/flutterw、tool/dartw；SDK位于用户工具目录，包装命令只为子进程补PATH，不改全局配置 |
| 原生依赖 | MAC-03加入path_provider与sqlite3的原生assets（objective_c/sqlite3 frameworks）；默认SwiftPM/native-assets路径。未装CocoaPods，实际Debug/Release构建通过；未来插件按需补充 |
| doctor | Flutter、可用设备与网络检查通过；Android许可未接受完整、CocoaPods缺失两项警告，未把这些写成已解决 |
| 工程 | 小说/client四端宿主已生成；macOS arm64 Debug构建、Release构建/实际窗口通过；本批Debug隔离入口与生产入口均已运行，其他三端未构建 |
| 当前依赖 | Flutter、纯Dart reader_core/platform_services、精确phosphor_icons3.0.1以及flutter_test/flutter_lints；MAC-03增加精确sqlite3 3.7.1、path_provider2.1.6、crypto3.0.7/path1.9.1和reader_storage；MAC-04将xml6.6.1转为直接运行依赖，原生文件/GB18030/Big5使用系统API；研究dev依赖锁定epub_view3.3.0/html0.15.6（旧HTML仅已知样本对照，不是生产解析选型）；完整应用锁文件与[许可清单](licenses/README.md)留存 |
| 中文目录检查 | 格式、严格Dart分析及102项Flutter/Dart测试、13项Python样本测试通过；Flutter CLI LSP入口有中文字节长度错误，采用同SDKDart分析，见[ADR-0001](decisions/0001-mac01-flutter-toolchain.md) |
| 产物 | 本机Release内部检查包0.0.10+10、31.5MB工具报告、最低目标12.0、arm64、ad-hoc校验通过；含D1壳、真实本地库与自产样本/位置持久化、本机声明/独立成人分组/隐私锁、系统只读文件授权与TXT/EPUB托管/引用导入、TXT分章/分块及受控EPUB滚动/目录/资源/选区位置、真实书架管理/有界查询/可撤销操作/托管回收，含本地排版、自动位置；不含来源能力，未正式公证分发 |

SDK归档端点本轮返回404，改从官方仓库固定标签，未修改SDK源码；不声称核验未获取归档的SHA-256。MAC-02装配/导航采用SDK接口，Riverpod/go_router候选本批未引入，见[ADR-0002](decisions/0002-mac02-shell-and-jobs.md)；MAC-06使用系统WKWebView/AVSpeechSynthesizer研究并冻结对照依赖，见[验收](verifications/mac-06-2026-10-19.md)；MAC-03实际SQLite为绑定库3.54.0，见[验收](verifications/mac-03-2026-10-20.md)；Drift尚未引入，正式EPUB/TTS绑定与后端版本仍在对应任务实际使用时核验锁定，不被本批SDK决定自动批准。

新终端从仓库根运行 `python3 tool/sdk.py install`、`./tool/check.sh`；本机已有匹配SDK时安装命令只校验并显示版本。不要直接flutter upgrade。项目源代码许可证仍未选择，未接受Android许可、购买证书或接入付费服务。

## 2026-10-15只读核验与候选方案（历史）

以下保留原始观测与当时未来计划，未安装/未初始化等措辞仅指2026-10-15。

核验日期：2026-10-15，Asia/Singapore。仅执行只读检查，没有安装 SDK、接受许可、初始化工程或运行 App。本文件区分本机观测与未来版本决策，不作为四端兼容证明。

### 本机观测

| 项目 | 实际结果 | 对开发的影响 |
|---|---|---|
| 系统 | macOS 27.0.1，build 26A434，arm64 | 首批先在当前 Apple Silicon 机器验证；最低系统与 Intel 支持未决定 |
| Xcode | 27.0，build 27A266a | 工具可查询，不等于 Flutter/插件已通过此版本构建 |
| Command Line Tools | xcode-select 指向 /Applications/Xcode.app/Contents/Developer；xcrun 72 | 初始化时继续检查 SDK、构建、许可和首次运行组件状态 |
| Flutter / Dart | 当前 PATH 中未找到 | MAC-01 需配置 SDK；不能声称已有可运行工程 |
| 常见 Flutter 路径 | /opt/homebrew/share/flutter、~/development/flutter、~/flutter、~/.fvm/default 下未找到 bin/flutter | 仅代表本次检查位置，没有证明整机未安装 |
| CocoaPods | 当前 PATH 中未找到 pod | 根据选定 Flutter 与原生插件的依赖方式决定是否安装；不能据此断言所有工程无法构建 |
| Java | OpenJDK 26.0.2.1 | 后端尚未初始化，不据此锁定 Spring Boot/Java 组合 |
| Maven | 3.9.16，所用 Homebrew Java 为 26.0.1 | 与系统 Java 不同；服务端任务需明确 JAVA_HOME 与兼容矩阵 |
| 仓库 | main；小说/client 和漫画/client 仍只有说明 | 本轮无 Flutter 宿主、依赖锁文件或运行服务 |

### MAC-01 的执行顺序

1. 先定位已有 SDK；需要安装时选择官方 stable SDK，记录来源、版本、Dart 版本和完整性，使用项目专用版本约定。
2. 查所选 SDK 对当前 Xcode/macOS 的要求，运行 flutter doctor -v、flutter devices。当前 macOS 构建所需项必须解决；Windows 构建不能在本机假定通过。
3. 检查 Xcode 许可和组件状态。需要接受法律条款时由账户所有者处理，不把 sudo xcodebuild -license accept 放进无人值守脚本。
4. 依据插件清单核验 CocoaPods/Swift Package Manager，记录实际采用方式。原生工具存在与依赖可解析分别验证。
5. 在临时目录生成 novel_app 四端模板，检查 diff 后合入小说/client，保留已有 README；不要覆盖根目录或漫画目录。
6. 选定应用标识、显示名“阅栖”、最低部署系统和构建架构。占位标识需注明，正式签名前冻结；不冒用未持有的域名。
7. 在中文仓库路径完成依赖解析、静态检查、基础测试、macOS Debug 运行与 Release 构建，记录结果。其他宿主生成不等于其他三端已验证。
8. 提交 SDK 版本约定、应用锁文件、依赖许可清单与复现命令；机器路径、证书、Token 和个人 Team ID 不提交。

以上命令均为未来任务，本轮没有运行 flutter doctor、flutter create 或 flutter build。

### 建议基线与试验

以下尚未安装、联合解析或锁定版本。2026-10-15 阅读了维护者文档；上游平台支持不是本项目实测结果。

| 领域 | 建议 | 锁定条件 |
|---|---|---|
| 状态与装配 | Riverpod；异步状态、生命周期与取消令牌分离 | 所选 Flutter/Dart 联合解析、任务取消小样通过 |
| 路由 | go_router；路由只传稳定 ID | 桌面返回、无效路由、隐私锁重定向通过 |
| SQLite | Drift；封装表/迁移、事务和数据访问 | SQLite 运行方式、后台工作与中文索引试验通过 |
| 文件/安全存储/窗口 | platform_services 端口，按需插件或原生实现 | 四端能力矩阵、macOS 权限重启恢复和 Release 验证 |
| EPUB | 比较受控 WebView 与 Flutter 排版路线 | MAC-06 位置/选字/搜索/TTS/资源隔离及许可通过 |
| TTS | SpeechService，系统语音优先，必要时原生桥接 | MAC-12 中文回调、暂停恢复、离线和长时播放通过 |

选型发现：flutter_tts 的平台功能表未把 macOS 列入 pause 和 speech marks 支持项，不能因为包声明支持 macOS 就承诺完整听书体验。需要验证所选版本，必要时用 Apple 原生语音接口补足；不静默删掉暂停/恢复。句级回调不可用时可显示已提交朗读段落，必须说明粒度，不能伪造逐字同步。

依据：[Flutter macOS 环境](https://docs.flutter.dev/platform-integration/macos/setup)、[构建分发](https://docs.flutter.dev/platform-integration/macos/building)、[Riverpod](https://pub.dev/packages/flutter_riverpod)、[go_router](https://pub.dev/packages/go_router)、[Drift](https://pub.dev/packages/drift)、[flutter_tts 功能表](https://pub.dev/packages/flutter_tts)、[Apple AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)。精确版本待联合核验。

下一步见 [macOS 详细开发步骤](novel-macos-implementation-steps.md)。本机环境事实不替代实现任务验收。
