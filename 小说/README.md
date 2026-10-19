# 小说阅读 App · 阅栖

- [client/](client/README.md)：小说 Flutter 客户端代码入口，一套工程覆盖 Android、iOS、Windows、macOS。
- [server/](server/README.md)：小说业务模块 reader-novel，装配进共享 Spring Boot 单体。

MAC-01已初始化client四端Flutter宿主并验证macOS基础壳；MAC-02已实现D1导航/响应布局/端口/任务状态，真实阅读业务与Java服务仍未实现。App 独立发布，本地 SQLite 与漫画 App 分开。
共享能力位于根目录 packages/ 与 services/reader_platform/。本目录不是独立 Git 仓库；建议由根仓库 yueqi-reader 管理。

参见[仓库布局](../docs/repository-layout.md)、[架构](../docs/architecture.md)和[路线图](../docs/roadmap.md)。

首批优先 macOS 自用安装包，按[完整功能方案](../docs/novel-macos-plan.md)、[任务与验收](../docs/novel-macos-backlog.md)、[四端代码边界](../docs/novel-cross-platform.md)推进；MAC-02应用壳与[MAC-06研究](../docs/verifications/mac-06-2026-10-19.md)已完成，下一主任务第04步MAC-03本地数据与位置协议；工程检查版不代表完整阅读App。

小说资源仅中文简繁，免费普通/18+来源、内置＋导入、在线搜索阅读与18+搜索开关均为完整首版必需；默认不搜索成人源，关闭开关保留独立分组已有收藏阅读。规则见[小说来源策略](../docs/novel-source-policy.md)。
