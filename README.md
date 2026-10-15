# 阅读软件

“阅读软件”是两款独立阅读产品的开发项目：**小说阅读 App（暂定名：阅栖）** 与 **漫画阅读 App（名称待定）**。二者均面向 Android、iOS、Windows、macOS，采用 Flutter 客户端与可选的 Spring Boot 共享服务。项目显示名保持“阅读软件”，开发目录名为“阅栖”。

当前阶段：**项目基础与任务拆分已建立，应用尚未实现**。目录说明文件不是 Flutter 或 Spring Boot 工程；当前没有启动命令、已安装依赖、真实接口或内容访问凭据。

当前开发方向（2026-10-15）：先做 **macOS 小说 App，自用、通过安装包运行**；保留 Windows、Android、iOS 的同一 Flutter 工程与平台接口，漫画和云服务按后续里程碑实施。macOS 专题方案已完成，尚未开始应用实现。

小说内容范围已收敛为**中文资源（含简繁）**，优先免费书源，普通与18+来源都需设计接入。“搜索18+书源”默认关闭，关闭时不发出18+源搜索请求，开启后才加入这些来源；具体来源仍逐项核验。漫画语言范围保持原计划。

已确认内置核验过的免费来源并支持自行导入；关闭18+搜索只影响搜索，已有成人收藏保留在独立分组并可按已有权限阅读。**完整首版必须有普通和18+来源的在线搜索/阅读**；本地阅读包仅为内部检查点。详细规则见 [小说来源与18+搜索策略](docs/novel-source-policy.md)。

- [macOS 小说 App 完整功能方案](docs/novel-macos-plan.md)：日常阅读、听书、书源、下载、备份、隐私与版本范围。
- [macOS 开发任务与验收](docs/novel-macos-backlog.md)：MAC-00～MAC-26、依赖、验收场景和性能预算。
- [macOS 详细开发步骤](docs/novel-macos-implementation-steps.md)：23步执行顺序、代码落点、交付物和逐步验收。
- [开发环境核验](docs/development-environment.md)与[中文来源首轮核验](docs/source-audit-2026-10-15.md)：本机事实、技术选型前提与来源未决条件。
- [第00步单源续验](docs/source-step00-2026-10-15.md)：中国大陆自用范围、有限普通/成人候选矩阵、38次观测和未解除条件；本开发聊天本批仅执行MAC-18，未进入第01步。
- [截图五个书源合集逐项核验](docs/source-collections-audit-2026-10-15.md)：实际文件数量、版本差异、脚本/付费能力、有限网络样本和未通过项。
- [小说四端目录与技术边界](docs/novel-cross-platform.md)：平台适配、稳定数据/锚点、可选服务端与发布规划。

## 产品与技术约定

| 项目 | 小说阅读 App | 漫画阅读 App |
|---|---|---|
| 核心 | TXT/EPUB 排版、章节、书签 | CBZ/ZIP、图片、长条漫、单页/双页 |
| 内容与阅读 | 中文简繁小说、中文检索与听书 | 中日韩漫画、左右向与连续滚动 |
| 本地数据 | 独立 SQLite、正文缓存 | 独立 SQLite、图片缓存 |
| 来源接口 | 搜索、详情、目录、章节内容 | 搜索、详情、目录、页面资源清单 |
| 可共享能力 | 账号、设备、同步协议、分级、基础 UI | 同左，独立内容命名空间 |

Local-first：未登录、断网或共享服务停机时，已有本地书籍、下载内容、进度和书签仍可使用。MySQL 只在需要云端持久化时引入，Redis 不作为第一版必需依赖。

## 目录

```text
阅栖/
├── AGENTS.md
├── README.md
├── 小说/
│   ├── client/             # 一套 Flutter 客户端：Android/iOS/Windows/macOS
│   └── server/             # reader-novel 业务模块，装配到共享服务
├── 漫画/
│   ├── client/             # 另一套 Flutter 客户端，覆盖同样四端
│   └── server/             # reader-comic 业务模块，装配到共享服务
├── packages/
│   ├── reader_core/        # 通用模型、语言、分级
│   ├── reader_storage/     # SQLite 抽象、迁移；两 App 分库
│   ├── reader_sync/        # 共享同步协议与客户端
│   ├── reader_ui/          # 可复用 UI 基础
│   ├── platform_services/  # 文件权限/安全存储/语音/窗口等平台接口预留
│   ├── novel_sources/     # 小说适配器及规则解释边界
│   └── comic_sources/     # 漫画适配器及扩展边界
├── services/reader_platform/
│   ├── app/               # 单一 Spring Boot 启动入口预留
│   └── modules/           # 账号/同步/分级等共享模块，非独立服务
├── docs/
│   ├── requirements.md
│   ├── architecture.md
│   ├── interfaces.md
│   ├── data-sources.md
│   ├── roadmap.md
│   ├── context.md
│   └── reference/conversation.md
├── fixtures/              # 合法测试样本预留，目前为空
└── infra/environments/    # dev/test/prod 配置与部署说明预留
```

## 交接阅读顺序

1. [开发约定](AGENTS.md)与[需求](docs/requirements.md)：范围、优先级、验收。
2. [架构](docs/architecture.md)与[接口草案](docs/interfaces.md)：模块边界、存储、缓存与同步。
3. [数据源清单](docs/data-sources.md)：候选入口、免费与授权的待核验项。
4. [路线图](docs/roadmap.md)：任务 ID、依赖、交付物与下一步。
5. [上下文](docs/context.md)及[原聊天归档](docs/reference/conversation.md)：讨论来源、变更与未定问题。

## 仓库与代码组织

使用一个 GitHub 仓库 [xinglin45/yueqi-reader](https://github.com/xinglin45/yueqi-reader)，按“小说”“漫画”分开产品目录，每款产品只有一套跨平台 Flutter 客户端。两款 App 仍分别构建、签名和发布；共用 packages/ 与 services/reader_platform/。远程地址为 git@github.com:xinglin45/yueqi-reader.git，默认分支 main。

小说/server 与 漫画/server 是不同业务模块，随共享 Spring Boot 单体装配部署，不是两个独立启动服务。开发、测试、生产使用同一份源码，通过环境配置区分；手机端与 PC 端的原生适配在各自 Flutter 工程内管理。

详细比较、平台目录和发布规则见 [仓库布局约定](docs/repository-layout.md)。本地 Git 已初始化并关联该远程，沿用远程已有的 main 提交历史；当前内容仍是目录与文档骨架。

## 从 Codex 开始

将此目录作为开发工作目录。本开发聊天本批按用户要求只执行 **第00步 / MAC-18** 中文普通/18+来源核验，已交付[单源续验](docs/source-step00-2026-10-15.md)，任务仍进行中。**MAC-01 / 第01步**为后续工程初始化任务，本批未开始。macOS先验证本地内部检查点，再合入联网能力形成完整首版；漫画/云服务保持后续计划。

推荐任务提示：“在‘阅读软件’项目中执行 MAC-01，遵守 AGENTS.md 和 macOS 专题方案，先运行 macOS 小说客户端、保留四端边界；报告版本选择、验证结果、尚未验证的平台和下一任务。”

## 数据、费用与发布

2026-10-15 来源续验：维基文库《孔乙己》完整短篇技术样本通过，《三國演義》具体点校版本有未决线索；Gutendex中文列表本轮取得（接口报告441、本页32），Gutenberg官方OPDS搜索/详情有获取链接，未下载EPUB。Pixiv官方政策已取得，拒绝当前未获许可规则采集路径；AO3完整条款仍读取失败，仅取得OTW免费服务说明。按用户确认的中国自用范围核验，尚无来源完成内置审批，普通/18+门槛均未满足；详见[第00步记录](docs/source-step00-2026-10-15.md)。

同日按用户要求检查截图五个合集：AOA文件3907条、XIU2为22、关耳为86；Tickmao公开下载文件194，内部另一个文件1000；破冰作者/AOA128，另一分发文件91。配置数量已取证，星级/全包有效率没有证据；没有逐条运行数千规则或完成App搜书阅读，不整包启用。

候选来源不能自动启用或随产品打包。“公开可访问”“接口免费”“作品可再分发”“允许商业使用”分别判断。本轮仅更新方案、环境和来源证据，没有生成应用或安装依赖。

小说只选中文资源，漫画保留中日韩资源；两者保留内容分级能力。小说18+源搜索默认关闭，开启后才参与搜索；开关不改变来源自身的访问要求或内容使用权限。当前先自用，未来公开发行模式、地区、渠道和合作来源另行确定。

## 工作区与项目位置

原 ChatGPT 项目名称保持“阅读软件”。开发文件已迁至 /Users/catmint/个人/AI/CODE/自用工具/阅栖，原同步镜像的 AGENTS.md 和 sources/ 未改变。

本目录为后续开发的主目录；不要改动同级 ListenText 或原同步镜像文件。源码许可证尚未选定，未附加默认开源或商用许可。

Codex 项目服务已创建本地记录，名称“阅读软件”、根目录为本目录；侧栏本地项目登记仍未完成。需要在 Codex 中打开本目录，让侧栏识别本地项目，再归入“自用工具”并关联当前开发聊天。目标结构：自用工具 → 阅读软件 → 整理阅读软件项目基础。后续开发使用本目录。
