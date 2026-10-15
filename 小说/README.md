# 小说阅读 App · 阅栖

- [client/](client/README.md)：小说 Flutter 客户端代码入口，一套工程覆盖 Android、iOS、Windows、macOS。
- [server/](server/README.md)：小说业务模块 reader-novel，装配进共享 Spring Boot 单体。

当前只有目录说明，没有已初始化的 Flutter/Java 工程。App 独立发布，本地 SQLite 与漫画 App 分开。
共享能力位于根目录 packages/ 与 services/reader_platform/。本目录不是独立 Git 仓库；建议由根仓库 yueqi-reader 管理。

参见[仓库布局](../docs/repository-layout.md)、[架构](../docs/architecture.md)和[路线图](../docs/roadmap.md)。

首批优先 macOS 自用安装包，按[完整功能方案](../docs/novel-macos-plan.md)、[任务与验收](../docs/novel-macos-backlog.md)、[四端代码边界](../docs/novel-cross-platform.md)推进；下一实现任务 MAC-01。方案已完成，应用尚未开始。
