# novel_app

源码位置：小说/client。一套 Flutter 工程覆盖手机与 PC，共用 lib/；android/、ios/、windows/、macos/ 平台目录将在 FND-01 实际初始化时生成。

见[小说目录说明](../README.md)与[仓库布局](../../docs/repository-layout.md)。

小说阅读 App 的独立 Flutter 工程预留；负责书架、TXT/EPUB、目录、文本锚点与小说用例。四端目标：Android、iOS、Windows、macOS。初始化任务 FND-01，核心实现 NOV-01/02。

此处仅为职责和目录预留，不是已实现的可运行模块。总体架构、验收与依赖见项目根目录 docs/architecture.md 和 docs/roadmap.md。

当前按[macOS完整方案](../../docs/novel-macos-plan.md)先交付自用安装包；首次工程初始化使用专题任务 MAC-01/02，目标 lib/features/ 与四端宿主布局见[四端边界](../../docs/novel-cross-platform.md)。
