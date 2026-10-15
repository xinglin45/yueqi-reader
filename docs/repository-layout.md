# 仓库、产品与部署环境

更新日期：2026-10-15。状态：已调整本地目录骨架并初始化 Git、关联远程仓库；应用工程与部署配置尚未实现。

## 决策

推荐一个根仓库 yueqi-reader，项目显示名仍为“阅读软件”。在仓库内按“小说”“漫画”区分产品代码，分别拥有 Flutter 客户端和服务端领域模块，共享基础包与单体服务启动入口。

远程仓库为 [xinglin45/yueqi-reader](https://github.com/xinglin45/yueqi-reader)，SSH 地址 git@github.com:xinglin45/yueqi-reader.git，默认分支 main。已检查远程初始提交只有 README.md；本地从该历史继续提交，不覆盖或强制改写远程历史。

## 方案比较

| 方案 | 影响 | 本项目判断 |
|---|---|---|
| 按 Android/iOS/Windows/macOS 各维护独立源码/仓库 | 平台间业务修复、同步协议与阅读功能容易重复维护 | 每产品采用一个 Flutter 工程，只分平台适配与构建目标 |
| 按 dev/test/prod 各复制一套源码/仓库 | 环境间代码漂移，难以确定生产运行的版本 | 同一源码版本，配置和发布记录区分环境 |
| 小说、漫画各一个仓库 | 产品隔离清晰，但共享包/协议/单体后端需额外跨仓版本管理 | 暂不拆；团队、权限或发布周期明显独立时再评估 |
| 一个仓库，按两产品分目录 | 共享接口与依赖能在同一变更中更新，同时保留独立 App 构建 | 当前推荐 |

产品目录、Git 仓库、运行环境与部署产物是四个不同层次。两个产品目录不要求两个仓库；一个仓库也不要求一起发布所有 App。

## 实际目录

```text
阅栖/                            # 一个根仓库的位置
├── 小说/
│   ├── README.md
│   ├── client/                  # 小说 Flutter 工程预留，包名 novel_app
│   └── server/                  # Java 模块 reader-novel 预留
├── 漫画/
│   ├── README.md
│   ├── client/                  # 漫画 Flutter 工程预留，包名 comic_app
│   └── server/                  # Java 模块 reader-comic 预留
├── packages/                    # 共用基础及分别拥有的来源适配包
├── services/reader_platform/
│   ├── app/                     # 唯一 Spring Boot 启动入口
│   └── modules/                 # 账号、设备、同步、分级等共享模块
├── infra/environments/
│   ├── dev/                     # 本地开发环境
│   ├── test/                    # 测试/预发布环境
│   └── prod/                    # 生产环境
├── docs/
└── fixtures/
```

client/ 与 server/ 当前只有 README，没有业务源码或构建文件。平台目录、lib/ 与 Java src/ 应在 FND-01 初始化真实工程时生成，不创建看似可编译的空工程。

2026-10-15 当前执行顺序：由 FND-01 的 macOS 先行子任务 MAC-01/02 开始，先初始化 小说/client 和所需共享包，保留四端宿主/平台接口；漫画与 Java 实现延后。本批目录细化见 [novel-cross-platform.md](novel-cross-platform.md)，系统能力预留位于 packages/platform_services。所有平台当前仍未实现/验证。

## 客户端源码规则

每个 client/ 内将包含：

- lib/：共享于该 App 四个平台的 Dart 业务、阅读器与界面。
- android/、ios/、windows/、macos/：原生适配、权限、签名与打包配置。
- test/、assets/ 与 pubspec.yaml：实际初始化后按需要建立。

两款 App 有不同包名/安装标识、阅读引擎、书架/本地库与独立版本。不同屏幕/输入设备的布局和交互在同一 App 工程中适配，不另复制 mobile/ 和 pc/ 两套业务代码。

Flutter 官方说明支持从一套代码构建多个平台，同时允许平台专有实现；这不表示所有插件或原生功能自动支持四端。[Flutter 平台集成](https://docs.flutter.dev/platform-integration)

## 服务端源码规则

- 小说/server 与 漫画/server 仅承载对应领域模块，不各自建立 Spring Boot 主程序。
- 公共身份、设备、同步、来源目录和分级能力保留在共享模块。
- services/reader_platform/app 是唯一启动模块，装配小说与漫画领域模块。
- 在选择 Maven/Gradle 后，根级聚合构建以英文模块标识映射两个中文产品目录；依赖用模块接口，不依赖复制代码或软链接。
- 默认一个服务端部署产物，服务端数据库按账户/App/领域隔离；两 App 本地 SQLite 仍分别拥有。
- 手机与 PC 调用同一套同步协议，不分别维护服务器实现。

初始化时应验证中文路径在选定构建工具、CI 和平台插件中的实际行为。包名和模块标识使用英文；若工具不支持中文路径，记录证据并调整路径，不复制两套源码。

## 环境与发布

环境配置预留 dev/test/prod，只保存非敏感模板、部署说明和验证步骤。服务器地址、数据库连接、日志、限额等由环境配置区分；真实密钥在运行环境或安全存储注入。

Spring Boot 支持外部配置，使同一应用代码在不同环境使用不同参数。[Spring Boot 外部配置](https://docs.spring.io/spring-boot/reference/features/external-config.html)

计划构建产物：

| 产物 | 源码位置 | 发布边界 |
|---|---|---|
| 小说 Android/iOS/Windows/macOS 安装包 | 小说/client | 小说 App 独立版本与各平台构建/签名 |
| 漫画 Android/iOS/Windows/macOS 安装包 | 漫画/client | 漫画 App 独立版本与各平台构建/签名 |
| 共享服务 Java 产物 | 服务启动入口 + 共享模块 + 两产品 server | 共享服务独立版本，按环境部署 |

CI 后续按变更路径触发；共享包/协议变更需要验证两款客户端，服务端模块变更需要验证单体集成。Windows 构建需 Windows 环境，iOS/macOS 构建需 macOS 环境，不能把本机构建成功视作四端通过。构建工具、CI 与版本标签方案由 FND-01 进一步确定。

## 已执行的调整

- apps/novel_app → 小说/client。
- apps/comic_app → 漫画/client。
- services/reader_platform/modules/reader-novel → 小说/server。
- services/reader_platform/modules/reader-comic → 漫画/server。
- 创建环境说明目录，更新根 README、AGENTS、架构与路线图。
- 未生成应用代码，未创建嵌套 Git 仓库；仅在“阅栖”根目录维护一个 Git 仓库并关联用户指定远程。

后续仅当需要独立团队权限、共享组件正式版本化或产品运维边界改变时再拆仓库。拆分前另记录接口/版本迁移方案，避免共享服务被无意复制成两套。
